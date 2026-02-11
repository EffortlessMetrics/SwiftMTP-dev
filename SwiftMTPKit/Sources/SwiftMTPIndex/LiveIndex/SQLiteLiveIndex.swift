// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// SQLite-backed implementation of the live object index.
///
/// Opens a database in the app group container so both the host app (writer)
/// and the File Provider extension (reader) can access it concurrently via WAL mode.
public final class SQLiteLiveIndex: LiveIndexReader, LiveIndexWriter, @unchecked Sendable {
    private let db: SQLiteDB

    /// Expose the underlying database handle for sharing with `ContentCache`.
    public var database: SQLiteDB { db }

    /// Open (or create) the live index database at `path`.
    /// - Parameters:
    ///   - path: Path to the SQLite database file.
    ///   - readOnly: If true, opens in read-only mode (for File Provider extension).
    public init(path: String, readOnly: Bool = false) throws {
        self.db = try SQLiteDB(path: path, readOnly: readOnly)
        if !readOnly {
            try createSchema()
        }
    }

    /// Open at a well-known app group location.
    public static func appGroupIndex(readOnly: Bool = false) throws -> SQLiteLiveIndex {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.effortlessmetrics.swiftmtp"
        )
        let dir = container ?? FileManager.default.temporaryDirectory
        let dbPath = dir.appendingPathComponent("live_index.sqlite").path
        return try SQLiteLiveIndex(path: dbPath, readOnly: readOnly)
    }

    // MARK: - Schema

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS live_objects (
            deviceId      TEXT    NOT NULL,
            storageId     INTEGER NOT NULL,
            handle        INTEGER NOT NULL,
            parentHandle  INTEGER,
            name          TEXT    NOT NULL,
            pathKey       TEXT    NOT NULL,
            sizeBytes     INTEGER,
            mtime         INTEGER,
            formatCode    INTEGER NOT NULL,
            isDirectory   INTEGER NOT NULL DEFAULT 0,
            changeCounter INTEGER NOT NULL,
            crawledAt     INTEGER NOT NULL,
            stale         INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (deviceId, storageId, handle)
        );
        CREATE INDEX IF NOT EXISTS idx_live_parent ON live_objects(deviceId, storageId, parentHandle);
        CREATE INDEX IF NOT EXISTS idx_live_change ON live_objects(deviceId, changeCounter);

        CREATE TABLE IF NOT EXISTS live_storages (
            deviceId    TEXT    NOT NULL,
            storageId   INTEGER NOT NULL,
            description TEXT,
            capacity    INTEGER,
            free        INTEGER,
            readOnly    INTEGER,
            PRIMARY KEY (deviceId, storageId)
        );

        CREATE TABLE IF NOT EXISTS crawl_state (
            deviceId     TEXT    NOT NULL,
            storageId    INTEGER NOT NULL,
            parentHandle INTEGER NOT NULL,
            lastCrawledAt INTEGER,
            status       TEXT    NOT NULL DEFAULT 'pending',
            priority     INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (deviceId, storageId, parentHandle)
        );

        CREATE TABLE IF NOT EXISTS device_index_state (
            deviceId      TEXT PRIMARY KEY,
            changeCounter INTEGER NOT NULL DEFAULT 0,
            lastFullCrawl INTEGER
        );

        CREATE TABLE IF NOT EXISTS device_identities (
            domainId     TEXT PRIMARY KEY,
            identityKey  TEXT NOT NULL,
            displayName  TEXT NOT NULL,
            vendorId     INTEGER,
            productId    INTEGER,
            usbSerial    TEXT,
            mtpSerial    TEXT,
            manufacturer TEXT,
            model        TEXT,
            createdAt    INTEGER NOT NULL,
            lastSeenAt   INTEGER NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_identity_key ON device_identities(identityKey);

        CREATE TABLE IF NOT EXISTS live_changes (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId      TEXT    NOT NULL,
            changeCounter INTEGER NOT NULL,
            storageId     INTEGER NOT NULL,
            handle        INTEGER,
            parentHandle  INTEGER,
            kind          TEXT    NOT NULL,
            createdAt     INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_live_changes_device_counter
            ON live_changes(deviceId, changeCounter);
        CREATE INDEX IF NOT EXISTS idx_live_changes_device_parent
            ON live_changes(deviceId, storageId, parentHandle, changeCounter);

        CREATE TABLE IF NOT EXISTS cached_content (
            deviceId       TEXT    NOT NULL,
            storageId      INTEGER NOT NULL,
            handle         INTEGER NOT NULL,
            localPath      TEXT    NOT NULL,
            sizeBytes      INTEGER NOT NULL,
            etag           TEXT,
            state          TEXT    NOT NULL DEFAULT 'complete',
            committedBytes INTEGER NOT NULL DEFAULT 0,
            lastAccessedAt INTEGER NOT NULL,
            PRIMARY KEY (deviceId, storageId, handle)
        );
        CREATE INDEX IF NOT EXISTS idx_cache_lru ON cached_content(lastAccessedAt ASC);
        """
        // Execute each statement separately — sqlite3_exec handles multiple statements
        try db.exec(sql)
    }

    // MARK: - LiveIndexReader

    public func children(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws -> [IndexedObject] {
        let sql: String
        if let ph = parentHandle {
            sql = "SELECT * FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle = ? AND stale = 0"
            return try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                try db.bind(stmt, 3, Int64(ph))
                return try readObjects(stmt)
            }
        } else {
            sql = "SELECT * FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle IS NULL AND stale = 0"
            return try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                return try readObjects(stmt)
            }
        }
    }

    public func object(deviceId: String, handle: MTPObjectHandle) async throws -> IndexedObject? {
        let sql = "SELECT * FROM live_objects WHERE deviceId = ? AND handle = ? AND stale = 0 LIMIT 1"
        return try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, Int64(handle))
            let objects = try readObjects(stmt)
            return objects.first
        }
    }

    public func storages(deviceId: String) async throws -> [IndexedStorage] {
        let sql = "SELECT * FROM live_storages WHERE deviceId = ?"
        return try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, deviceId)
            var result: [IndexedStorage] = []
            while try db.step(stmt) {
                result.append(IndexedStorage(
                    deviceId: db.colText(stmt, 0) ?? "",
                    storageId: UInt32(db.colInt64(stmt, 1) ?? 0),
                    description: db.colText(stmt, 2) ?? "",
                    capacity: db.colInt64(stmt, 3).map(UInt64.init),
                    free: db.colInt64(stmt, 4).map(UInt64.init),
                    readOnly: (db.colInt64(stmt, 5) ?? 0) != 0
                ))
            }
            return result
        }
    }

    public func currentChangeCounter(deviceId: String) async throws -> Int64 {
        let sql = "SELECT changeCounter FROM device_index_state WHERE deviceId = ?"
        return try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, deviceId)
            if try db.step(stmt) {
                return db.colInt64(stmt, 0) ?? 0
            }
            return 0
        }
    }

    public func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
        // Read from live_changes, deduplicate: latest change per (storageId, handle) wins.
        let changesSQL = """
        SELECT c.storageId, c.handle, c.kind, c.changeCounter
        FROM live_changes c
        WHERE c.deviceId = ? AND c.changeCounter > ?
        ORDER BY c.changeCounter ASC
        """
        // Build deduplicated map: (storageId, handle) → latest kind
        struct ChangeKey: Hashable { let storageId: UInt32; let handle: UInt32 }
        var latestChanges: [ChangeKey: (kind: String, counter: Int64)] = [:]

        try db.withStatement(changesSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, anchor)
            while try db.step(stmt) {
                let sid = UInt32(db.colInt64(stmt, 0) ?? 0)
                guard let handle = db.colInt64(stmt, 1).map({ UInt32($0) }) else { continue }
                let kind = db.colText(stmt, 2) ?? "upsert"
                let counter = db.colInt64(stmt, 3) ?? 0
                let key = ChangeKey(storageId: sid, handle: handle)
                // Later entries overwrite earlier ones (higher counter wins)
                latestChanges[key] = (kind: kind, counter: counter)
            }
        }

        var result: [IndexedObjectChange] = []
        for (key, change) in latestChanges {
            if change.kind == "delete" {
                // Return tombstone from live_objects (stale row)
                let sql = "SELECT * FROM live_objects WHERE deviceId = ? AND storageId = ? AND handle = ? LIMIT 1"
                let obj: IndexedObject? = try db.withStatement(sql) { stmt in
                    try db.bind(stmt, 1, deviceId)
                    try db.bind(stmt, 2, Int64(key.storageId))
                    try db.bind(stmt, 3, Int64(key.handle))
                    return try readObjects(stmt).first
                }
                if let obj = obj {
                    result.append(IndexedObjectChange(kind: .deleted, object: obj))
                }
            } else {
                // Upsert: fetch current (non-stale) object
                let sql = "SELECT * FROM live_objects WHERE deviceId = ? AND storageId = ? AND handle = ? AND stale = 0 LIMIT 1"
                let obj: IndexedObject? = try db.withStatement(sql) { stmt in
                    try db.bind(stmt, 1, deviceId)
                    try db.bind(stmt, 2, Int64(key.storageId))
                    try db.bind(stmt, 3, Int64(key.handle))
                    return try readObjects(stmt).first
                }
                if let obj = obj {
                    result.append(IndexedObjectChange(kind: .upserted, object: obj))
                }
                // If object was upserted then deleted (stale=1), the dedup already picked delete
            }
        }

        return result
    }

    // MARK: - LiveIndexWriter

    public func upsertObjects(_ objects: [IndexedObject], deviceId: String) async throws {
        let now = Int64(Date().timeIntervalSince1970)

        try db.withTransaction {
            let counter = try nextChangeCounterSync(deviceId: deviceId)
            let upsertSQL = """
            INSERT INTO live_objects (deviceId, storageId, handle, parentHandle, name, pathKey, sizeBytes, mtime, formatCode, isDirectory, changeCounter, crawledAt, stale)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(deviceId, storageId, handle) DO UPDATE SET
                parentHandle = excluded.parentHandle,
                name = excluded.name,
                pathKey = excluded.pathKey,
                sizeBytes = excluded.sizeBytes,
                mtime = excluded.mtime,
                formatCode = excluded.formatCode,
                isDirectory = excluded.isDirectory,
                changeCounter = excluded.changeCounter,
                crawledAt = excluded.crawledAt,
                stale = 0
            """
            let changeSQL = """
            INSERT INTO live_changes (deviceId, changeCounter, storageId, handle, parentHandle, kind, createdAt)
            VALUES (?, ?, ?, ?, ?, 'upsert', ?)
            """
            for obj in objects {
                try db.withStatement(upsertSQL) { stmt in
                    try db.bind(stmt, 1, deviceId)
                    try db.bind(stmt, 2, Int64(obj.storageId))
                    try db.bind(stmt, 3, Int64(obj.handle))
                    try db.bind(stmt, 4, obj.parentHandle.map { Int64($0) })
                    try db.bind(stmt, 5, obj.name)
                    try db.bind(stmt, 6, obj.pathKey)
                    try db.bind(stmt, 7, obj.sizeBytes.map { Int64($0) })
                    try db.bind(stmt, 8, obj.mtime.map { Int64($0.timeIntervalSince1970) })
                    try db.bind(stmt, 9, Int64(obj.formatCode))
                    try db.bind(stmt, 10, obj.isDirectory ? Int64(1) : Int64(0))
                    try db.bind(stmt, 11, counter)
                    try db.bind(stmt, 12, now)
                    _ = try db.step(stmt)
                }
                try db.withStatement(changeSQL) { stmt in
                    try db.bind(stmt, 1, deviceId)
                    try db.bind(stmt, 2, counter)
                    try db.bind(stmt, 3, Int64(obj.storageId))
                    try db.bind(stmt, 4, Int64(obj.handle))
                    try db.bind(stmt, 5, obj.parentHandle.map { Int64($0) })
                    try db.bind(stmt, 6, now)
                    _ = try db.step(stmt)
                }
            }
        }
    }

    public func markStaleChildren(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws {
        let now = Int64(Date().timeIntervalSince1970)

        try db.withTransaction {
            // Query affected children to record delete changes
            let selectSQL: String
            if parentHandle != nil {
                selectSQL = "SELECT handle FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle = ? AND stale = 0"
            } else {
                selectSQL = "SELECT handle FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle IS NULL AND stale = 0"
            }
            let handles: [UInt32] = try db.withStatement(selectSQL) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                if let ph = parentHandle {
                    try db.bind(stmt, 3, Int64(ph))
                }
                var result: [UInt32] = []
                while try db.step(stmt) {
                    if let h = db.colInt64(stmt, 0) { result.append(UInt32(h)) }
                }
                return result
            }

            guard !handles.isEmpty else { return }

            let counter = try nextChangeCounterSync(deviceId: deviceId)

            // Mark stale and bump change counter
            let updateSQL: String
            if parentHandle != nil {
                updateSQL = "UPDATE live_objects SET stale = 1, changeCounter = ? WHERE deviceId = ? AND storageId = ? AND parentHandle = ?"
            } else {
                updateSQL = "UPDATE live_objects SET stale = 1, changeCounter = ? WHERE deviceId = ? AND storageId = ? AND parentHandle IS NULL"
            }
            try db.withStatement(updateSQL) { stmt in
                try db.bind(stmt, 1, counter)
                try db.bind(stmt, 2, deviceId)
                try db.bind(stmt, 3, Int64(storageId))
                if let ph = parentHandle {
                    try db.bind(stmt, 4, Int64(ph))
                }
                _ = try db.step(stmt)
            }

            // Insert delete change records for each affected handle
            let changeSQL = """
            INSERT INTO live_changes (deviceId, changeCounter, storageId, handle, parentHandle, kind, createdAt)
            VALUES (?, ?, ?, ?, ?, 'delete', ?)
            """
            for handle in handles {
                try db.withStatement(changeSQL) { stmt in
                    try db.bind(stmt, 1, deviceId)
                    try db.bind(stmt, 2, counter)
                    try db.bind(stmt, 3, Int64(storageId))
                    try db.bind(stmt, 4, Int64(handle))
                    try db.bind(stmt, 5, parentHandle.map { Int64($0) })
                    try db.bind(stmt, 6, now)
                    _ = try db.step(stmt)
                }
            }
        }
    }

    public func removeObject(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) async throws {
        let now = Int64(Date().timeIntervalSince1970)

        try db.withTransaction {
            let counter = try nextChangeCounterSync(deviceId: deviceId)

            // Get parent handle for the change record
            let parentHandle: Int64? = try db.withStatement(
                "SELECT parentHandle FROM live_objects WHERE deviceId = ? AND storageId = ? AND handle = ?"
            ) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                try db.bind(stmt, 3, Int64(handle))
                if try db.step(stmt) { return db.colInt64(stmt, 0) }
                return nil
            }

            // Mark as stale with updated change counter
            let sql = "UPDATE live_objects SET stale = 1, changeCounter = ? WHERE deviceId = ? AND storageId = ? AND handle = ?"
            try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, counter)
                try db.bind(stmt, 2, deviceId)
                try db.bind(stmt, 3, Int64(storageId))
                try db.bind(stmt, 4, Int64(handle))
                _ = try db.step(stmt)
            }

            // Insert delete change record
            let changeSQL = """
            INSERT INTO live_changes (deviceId, changeCounter, storageId, handle, parentHandle, kind, createdAt)
            VALUES (?, ?, ?, ?, ?, 'delete', ?)
            """
            try db.withStatement(changeSQL) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, counter)
                try db.bind(stmt, 3, Int64(storageId))
                try db.bind(stmt, 4, Int64(handle))
                try db.bind(stmt, 5, parentHandle)
                try db.bind(stmt, 6, now)
                _ = try db.step(stmt)
            }
        }
    }

    public func insertObject(_ object: IndexedObject, deviceId: String) async throws {
        try await upsertObjects([object], deviceId: deviceId)
    }

    public func upsertStorage(_ storage: IndexedStorage) async throws {
        let sql = """
        INSERT INTO live_storages (deviceId, storageId, description, capacity, free, readOnly)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(deviceId, storageId) DO UPDATE SET
            description = excluded.description,
            capacity = excluded.capacity,
            free = excluded.free,
            readOnly = excluded.readOnly
        """
        try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, storage.deviceId)
            try db.bind(stmt, 2, Int64(storage.storageId))
            try db.bind(stmt, 3, storage.description)
            try db.bind(stmt, 4, storage.capacity.map { Int64($0) })
            try db.bind(stmt, 5, storage.free.map { Int64($0) })
            try db.bind(stmt, 6, storage.readOnly ? Int64(1) : Int64(0))
            _ = try db.step(stmt)
        }
    }

    public func nextChangeCounter(deviceId: String) async throws -> Int64 {
        try db.withTransaction {
            try nextChangeCounterSync(deviceId: deviceId)
        }
    }

    public func purgeStale(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws {
        if let ph = parentHandle {
            let sql = "DELETE FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle = ? AND stale = 1"
            try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                try db.bind(stmt, 3, Int64(ph))
                _ = try db.step(stmt)
            }
        } else {
            let sql = "DELETE FROM live_objects WHERE deviceId = ? AND storageId = ? AND parentHandle IS NULL AND stale = 1"
            try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                _ = try db.step(stmt)
            }
        }
    }

    public func pruneChangeLog(deviceId: String, olderThan: Date) async throws {
        let cutoff = Int64(olderThan.timeIntervalSince1970)
        let sql = "DELETE FROM live_changes WHERE deviceId = ? AND createdAt < ?"
        try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, cutoff)
            _ = try db.step(stmt)
        }
    }

    // MARK: - Crawl State Reader

    public func crawlState(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws -> Date? {
        let sql: String
        if parentHandle != nil {
            sql = "SELECT lastCrawledAt FROM crawl_state WHERE deviceId = ? AND storageId = ? AND parentHandle = ?"
        } else {
            sql = "SELECT lastCrawledAt FROM crawl_state WHERE deviceId = ? AND storageId = ? AND parentHandle = 0"
        }
        return try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, Int64(storageId))
            if let ph = parentHandle {
                try db.bind(stmt, 3, Int64(ph))
            }
            if try db.step(stmt), let ts = db.colInt64(stmt, 0) {
                return Date(timeIntervalSince1970: TimeInterval(ts))
            }
            return nil
        }
    }

    // MARK: - Data Migration

    /// Migrate rows with old ephemeral deviceId (VID:PID@bus:addr pattern) to a new stable domainId.
    ///
    /// Called on first attach after update: checks if any rows match the device's vid:pid pattern
    /// and rewrites them to use the stable domainId.
    public func migrateEphemeralDeviceId(vidPidPattern: String, newDomainId: String) throws {
        // Match rows where deviceId looks like "xxxx:xxxx@y:z" (ephemeral format)
        // and starts with the given vid:pid prefix
        let tables = ["live_objects", "live_storages", "crawl_state", "device_index_state", "cached_content", "live_changes"]
        try db.withTransaction {
            for table in tables {
                let pattern = "\(vidPidPattern)@%"
                let sql = "UPDATE \(table) SET deviceId = ? WHERE deviceId LIKE ?"
                try db.withStatement(sql) { stmt in
                    try db.bind(stmt, 1, newDomainId)
                    try db.bind(stmt, 2, pattern)
                    _ = try db.step(stmt)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Synchronous version of `nextChangeCounter` for use inside `withTransaction` closures.
    private func nextChangeCounterSync(deviceId: String) throws -> Int64 {
        let ensureSQL = "INSERT OR IGNORE INTO device_index_state (deviceId, changeCounter) VALUES (?, 0)"
        try db.withStatement(ensureSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            _ = try db.step(stmt)
        }

        let incrSQL = "UPDATE device_index_state SET changeCounter = changeCounter + 1 WHERE deviceId = ?"
        try db.withStatement(incrSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            _ = try db.step(stmt)
        }

        let selectSQL = "SELECT changeCounter FROM device_index_state WHERE deviceId = ?"
        return try db.withStatement(selectSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            if try db.step(stmt) {
                return db.colInt64(stmt, 0) ?? 0
            }
            return 0
        }
    }

    private func readObjects(_ stmt: OpaquePointer) throws -> [IndexedObject] {
        var result: [IndexedObject] = []
        while try db.step(stmt) {
            result.append(IndexedObject(
                deviceId: db.colText(stmt, 0) ?? "",
                storageId: UInt32(db.colInt64(stmt, 1) ?? 0),
                handle: MTPObjectHandle(db.colInt64(stmt, 2) ?? 0),
                parentHandle: db.colInt64(stmt, 3).map { MTPObjectHandle($0) },
                name: db.colText(stmt, 4) ?? "",
                pathKey: db.colText(stmt, 5) ?? "",
                sizeBytes: db.colInt64(stmt, 6).map { UInt64($0) },
                mtime: db.colInt64(stmt, 7).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                formatCode: UInt16(db.colInt64(stmt, 8) ?? 0),
                isDirectory: (db.colInt64(stmt, 9) ?? 0) != 0,
                changeCounter: db.colInt64(stmt, 10) ?? 0
            ))
        }
        return result
    }
}

// MARK: - DeviceIdentityStore

extension SQLiteLiveIndex: DeviceIdentityStore {
    public func resolveIdentity(signals: DeviceIdentitySignals) async throws -> StableDeviceIdentity {
        let key = signals.identityKey()
        let now = Int64(Date().timeIntervalSince1970)

        return try db.withTransaction {
            // Try to find existing identity by key
            let selectSQL = "SELECT domainId, displayName, createdAt, lastSeenAt FROM device_identities WHERE identityKey = ?"
            let existing: StableDeviceIdentity? = try db.withStatement(selectSQL) { stmt in
                try db.bind(stmt, 1, key)
                if try db.step(stmt) {
                    let domainId = db.colText(stmt, 0) ?? ""
                    let displayName = db.colText(stmt, 1) ?? ""
                    let createdAt = db.colInt64(stmt, 2).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                    let lastSeenAt = db.colInt64(stmt, 3).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                    return StableDeviceIdentity(domainId: domainId, displayName: displayName, createdAt: createdAt, lastSeenAt: lastSeenAt)
                }
                return nil
            }

            if let identity = existing {
                // Update lastSeenAt
                let updateSQL = "UPDATE device_identities SET lastSeenAt = ? WHERE domainId = ?"
                try db.withStatement(updateSQL) { stmt in
                    try db.bind(stmt, 1, now)
                    try db.bind(stmt, 2, identity.domainId)
                    _ = try db.step(stmt)
                }
                return StableDeviceIdentity(
                    domainId: identity.domainId,
                    displayName: identity.displayName,
                    createdAt: identity.createdAt,
                    lastSeenAt: Date()
                )
            }

            // Create new identity
            let domainId = UUID().uuidString
            let displayName = signals.displayName()
            let insertSQL = """
            INSERT INTO device_identities (domainId, identityKey, displayName, vendorId, productId, usbSerial, mtpSerial, manufacturer, model, createdAt, lastSeenAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            try db.withStatement(insertSQL) { stmt in
                try db.bind(stmt, 1, domainId)
                try db.bind(stmt, 2, key)
                try db.bind(stmt, 3, displayName)
                try db.bind(stmt, 4, signals.vendorId.map { Int64($0) })
                try db.bind(stmt, 5, signals.productId.map { Int64($0) })
                try db.bind(stmt, 6, signals.usbSerial)
                try db.bind(stmt, 7, signals.mtpSerial)
                try db.bind(stmt, 8, signals.manufacturer)
                try db.bind(stmt, 9, signals.model)
                try db.bind(stmt, 10, now)
                try db.bind(stmt, 11, now)
                _ = try db.step(stmt)
            }

            return StableDeviceIdentity(domainId: domainId, displayName: displayName, createdAt: Date(), lastSeenAt: Date())
        }
    }

    public func identity(for domainId: String) async throws -> StableDeviceIdentity? {
        let sql = "SELECT domainId, displayName, createdAt, lastSeenAt FROM device_identities WHERE domainId = ?"
        return try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, domainId)
            if try db.step(stmt) {
                return StableDeviceIdentity(
                    domainId: db.colText(stmt, 0) ?? "",
                    displayName: db.colText(stmt, 1) ?? "",
                    createdAt: db.colInt64(stmt, 2).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
                    lastSeenAt: db.colInt64(stmt, 3).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                )
            }
            return nil
        }
    }

    public func updateMTPSerial(domainId: String, mtpSerial: String) async throws {
        try db.withTransaction {
            // First get the current identity key
            let selectSQL = "SELECT identityKey, vendorId, productId, manufacturer, model FROM device_identities WHERE domainId = ?"
            let row: (key: String, vid: Int64?, pid: Int64?, mfr: String?, mdl: String?)? = try db.withStatement(selectSQL) { stmt in
                try db.bind(stmt, 1, domainId)
                if try db.step(stmt) {
                    return (
                        key: db.colText(stmt, 0) ?? "",
                        vid: db.colInt64(stmt, 1),
                        pid: db.colInt64(stmt, 2),
                        mfr: db.colText(stmt, 3),
                        mdl: db.colText(stmt, 4)
                    )
                }
                return nil
            }
            guard let row else { return }

            // Only upgrade identity key if it was a type hash (weakest signal)
            let newKey: String?
            if row.key.hasPrefix("type:") {
                newKey = "mtp:\(mtpSerial)"
            } else {
                newKey = nil
            }

            if let newKey {
                let updateSQL = "UPDATE device_identities SET mtpSerial = ?, identityKey = ? WHERE domainId = ?"
                try db.withStatement(updateSQL) { stmt in
                    try db.bind(stmt, 1, mtpSerial)
                    try db.bind(stmt, 2, newKey)
                    try db.bind(stmt, 3, domainId)
                    _ = try db.step(stmt)
                }
            } else {
                let updateSQL = "UPDATE device_identities SET mtpSerial = ? WHERE domainId = ?"
                try db.withStatement(updateSQL) { stmt in
                    try db.bind(stmt, 1, mtpSerial)
                    try db.bind(stmt, 2, domainId)
                    _ = try db.step(stmt)
                }
            }
        }
    }

    public func allIdentities() async throws -> [StableDeviceIdentity] {
        let sql = "SELECT domainId, displayName, createdAt, lastSeenAt FROM device_identities ORDER BY lastSeenAt DESC"
        return try db.withStatement(sql) { stmt in
            var result: [StableDeviceIdentity] = []
            while try db.step(stmt) {
                result.append(StableDeviceIdentity(
                    domainId: db.colText(stmt, 0) ?? "",
                    displayName: db.colText(stmt, 1) ?? "",
                    createdAt: db.colInt64(stmt, 2).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
                    lastSeenAt: db.colInt64(stmt, 3).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                ))
            }
            return result
        }
    }

    public func removeIdentity(domainId: String) async throws {
        let sql = "DELETE FROM device_identities WHERE domainId = ?"
        try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, domainId)
            _ = try db.step(stmt)
        }
    }
}
