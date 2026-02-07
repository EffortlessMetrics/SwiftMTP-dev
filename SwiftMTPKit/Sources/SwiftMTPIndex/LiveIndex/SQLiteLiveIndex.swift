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
        // Upserted: objects with changeCounter > anchor
        let upsertSQL = "SELECT * FROM live_objects WHERE deviceId = ? AND changeCounter > ? AND stale = 0"
        let upserted: [IndexedObjectChange] = try db.withStatement(upsertSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, anchor)
            let objects = try readObjects(stmt)
            return objects.map { IndexedObjectChange(kind: .upserted, object: $0) }
        }

        // Deleted: stale objects with changeCounter > anchor
        let deletedSQL = "SELECT * FROM live_objects WHERE deviceId = ? AND changeCounter > ? AND stale = 1"
        let deleted: [IndexedObjectChange] = try db.withStatement(deletedSQL) { stmt in
            try db.bind(stmt, 1, deviceId)
            try db.bind(stmt, 2, anchor)
            let objects = try readObjects(stmt)
            return objects.map { IndexedObjectChange(kind: .deleted, object: $0) }
        }

        return upserted + deleted
    }

    // MARK: - LiveIndexWriter

    public func upsertObjects(_ objects: [IndexedObject], deviceId: String) async throws {
        try db.exec("BEGIN TRANSACTION")
        do {
            let counter = try await nextChangeCounter(deviceId: deviceId)
            let now = Int64(Date().timeIntervalSince1970)

            let sql = """
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
            for obj in objects {
                try db.withStatement(sql) { stmt in
                    try db.bind(stmt, 1, obj.deviceId)
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
            }
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    public func markStaleChildren(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws {
        if let ph = parentHandle {
            let sql = "UPDATE live_objects SET stale = 1 WHERE deviceId = ? AND storageId = ? AND parentHandle = ?"
            try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                try db.bind(stmt, 3, Int64(ph))
                _ = try db.step(stmt)
            }
        } else {
            let sql = "UPDATE live_objects SET stale = 1 WHERE deviceId = ? AND storageId = ? AND parentHandle IS NULL"
            try db.withStatement(sql) { stmt in
                try db.bind(stmt, 1, deviceId)
                try db.bind(stmt, 2, Int64(storageId))
                _ = try db.step(stmt)
            }
        }
    }

    public func removeObject(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) async throws {
        let counter = try await nextChangeCounter(deviceId: deviceId)
        // Mark as stale with updated change counter so enumerateChanges picks it up
        let sql = "UPDATE live_objects SET stale = 1, changeCounter = ? WHERE deviceId = ? AND storageId = ? AND handle = ?"
        try db.withStatement(sql) { stmt in
            try db.bind(stmt, 1, counter)
            try db.bind(stmt, 2, deviceId)
            try db.bind(stmt, 3, Int64(storageId))
            try db.bind(stmt, 4, Int64(handle))
            _ = try db.step(stmt)
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
        // Ensure device_index_state row exists
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

        return try await currentChangeCounter(deviceId: deviceId)
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

    // MARK: - Helpers

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
