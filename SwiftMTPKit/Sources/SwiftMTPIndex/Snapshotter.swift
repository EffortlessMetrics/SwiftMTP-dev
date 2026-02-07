// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import OSLog
import SQLite3

/// Captures device object graph into SQLite for offline browsing and diffing
public final class Snapshotter: Sendable {
    private let db: SQLiteDB
    private let log = Logger(subsystem: "SwiftMTP", category: "index")

    public init(dbPath: String) throws {
        self.db = try SQLiteDB(path: dbPath)
        try setupSchema()
    }

    private func setupSchema() throws {
        // Devices table
        try db.exec("""
            CREATE TABLE IF NOT EXISTS devices(
                id TEXT PRIMARY KEY,
                model TEXT,
                lastSeenAt INTEGER
            )
        """)

        // Storages table
        try db.exec("""
            CREATE TABLE IF NOT EXISTS storages(
                id INTEGER PRIMARY KEY,
                deviceId TEXT NOT NULL,
                description TEXT,
                capacity INTEGER,
                free INTEGER,
                readOnly INTEGER,
                lastIndexedAt INTEGER
            )
        """)

        // Objects table with generation support
        try db.exec("""
            CREATE TABLE IF NOT EXISTS objects(
                deviceId TEXT NOT NULL,
                storageId INTEGER NOT NULL,
                handle INTEGER NOT NULL,
                parentHandle INTEGER,
                name TEXT NOT NULL,
                pathKey TEXT NOT NULL,
                size INTEGER,
                mtime INTEGER,
                format INTEGER NOT NULL,
                gen INTEGER NOT NULL,
                tombstone INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(deviceId, handle, gen)
            )
        """)

        // Snapshots table
        try db.exec("""
            CREATE TABLE IF NOT EXISTS snapshots(
                deviceId TEXT NOT NULL,
                gen INTEGER NOT NULL,
                createdAt INTEGER NOT NULL,
                PRIMARY KEY(deviceId, gen)
            )
        """)
    }

    /// Capture a complete snapshot of the device
    /// - Parameters:
    ///   - device: The MTP device to snapshot
    ///   - deviceId: Unique identifier for the device
    /// - Returns: The generation number of the snapshot
    public func capture(device: any MTPDevice, deviceId: MTPDeviceID) async throws -> Int {
        let start = Date()
        let gen = Int(start.timeIntervalSince1970)

        log.info("Starting snapshot capture for device \(deviceId.raw), generation \(gen)")

        // Capture device info
        try await captureDeviceInfo(device: device, deviceId: deviceId, timestamp: start)

        // Capture storage info and objects
        let deviceStorages = try await device.storages()
        for storage in deviceStorages {
            try await captureStorageInfo(storage: storage, deviceId: deviceId, timestamp: start)
            try await captureObjects(device: device, storage: storage, deviceId: deviceId, gen: gen)
        }

        // Mark previous generation objects as tombstoned
        try markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: gen)

        // Record snapshot
        try recordSnapshot(deviceId: deviceId, gen: gen, timestamp: start)

        let duration = Date().timeIntervalSince(start)
        log.info("Snapshot capture completed for device \(deviceId.raw), generation \(gen), duration \(duration)s")

        return gen
    }

    private func captureDeviceInfo(device: any MTPDevice, deviceId: MTPDeviceID, timestamp: Date) async throws {
        let info = try await device.info

        try db.withStatement("INSERT OR REPLACE INTO devices(id, model, lastSeenAt) VALUES(?,?,?)") { stmt in
            try db.bind(stmt, 1, deviceId.raw)
            try db.bind(stmt, 2, info.model)
            try db.bind(stmt, 3, Int64(timestamp.timeIntervalSince1970))
            _ = try db.step(stmt)
        }
    }

    private func captureStorageInfo(storage: MTPStorageInfo, deviceId: MTPDeviceID, timestamp: Date) async throws {
        try db.withStatement("INSERT OR REPLACE INTO storages(id, deviceId, description, capacity, free, readOnly, lastIndexedAt) VALUES(?,?,?,?,?,?,?)") { stmt in
            try db.bind(stmt, 1, Int64(storage.id.raw))
            try db.bind(stmt, 2, deviceId.raw)
            try db.bind(stmt, 3, storage.description)
            try db.bind(stmt, 4, Int64(storage.capacityBytes))
            try db.bind(stmt, 5, Int64(storage.freeBytes))
            try db.bind(stmt, 6, Int64(storage.isReadOnly ? 1 : 0))
            try db.bind(stmt, 7, Int64(timestamp.timeIntervalSince1970))
            _ = try db.step(stmt)
        }
    }

    private func captureObjects(device: any MTPDevice, storage: MTPStorageInfo, deviceId: MTPDeviceID, gen: Int) async throws {
        // Collect all objects first to build complete parent-child relationships
        var allObjects = [MTPObjectInfo]()
        let objectStream = device.list(parent: nil, in: storage.id)

        do {
            for try await page in objectStream {
                allObjects.append(contentsOf: page)
            }
        } catch {
            log.error("Failed to list objects for storage \(storage.id.raw) on device \(deviceId.raw): \(error.localizedDescription)")
            return // Continue with other storages
        }

        // Build parent-child map for path construction
        var parentMap = [UInt32: UInt32]() // child -> parent
        var nameMap = [UInt32: String]() // handle -> name
        var objectMap = [UInt32: MTPObjectInfo]() // handle -> object info

        for object in allObjects {
            objectMap[object.handle] = object
            nameMap[object.handle] = object.name
            if let parent = object.parent {
                parentMap[object.handle] = parent
            }
        }

        // Process objects in batches
        let batchSize = 100
        for batchStart in stride(from: 0, to: allObjects.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allObjects.count)
            let batch = Array(allObjects[batchStart..<batchEnd])
            try processObjectBatch(batch, storage: storage, deviceId: deviceId, gen: gen,
                                 parentMap: parentMap, nameMap: nameMap)
        }
    }

    private func processObjectBatch(_ objects: [MTPObjectInfo], storage: MTPStorageInfo, deviceId: MTPDeviceID, gen: Int,
                                   parentMap: [UInt32: UInt32], nameMap: [UInt32: String]) throws {
        for object in objects {
            let pathComponents = buildPathComponents(for: object.handle, parentMap: parentMap, nameMap: nameMap)
            let pathKey = PathKey.normalize(storage: storage.id.raw, components: pathComponents)

            try db.withStatement("""
                INSERT OR REPLACE INTO objects(deviceId, storageId, handle, parentHandle, name, pathKey, size, mtime, format, gen, tombstone)
                VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """) { stmt in
                try db.bind(stmt, 1, deviceId.raw)
                try db.bind(stmt, 2, Int64(storage.id.raw))
                try db.bind(stmt, 3, Int64(object.handle))
                try db.bind(stmt, 4, object.parent.map { Int64($0) })
                try db.bind(stmt, 5, object.name)
                try db.bind(stmt, 6, pathKey)
                try db.bind(stmt, 7, object.sizeBytes.map { Int64($0) })
                try db.bind(stmt, 8, object.modified.map { Int64($0.timeIntervalSince1970) })
                try db.bind(stmt, 9, Int64(object.formatCode))
                try db.bind(stmt, 10, Int64(gen))
                try db.bind(stmt, 11, Int64(0))
                _ = try db.step(stmt)
            }
        }
    }

    internal func buildPathComponents(for handle: UInt32, parentMap: [UInt32: UInt32], nameMap: [UInt32: String]) -> [String] {
        var components = [String]()
        var currentHandle = handle
        var visited = Set<UInt32>()

        // Walk up the parent chain to build the full path
        while let name = nameMap[currentHandle], !visited.contains(currentHandle) {
            visited.insert(currentHandle)
            components.append(name)

            // Move to parent if it exists
            if let parent = parentMap[currentHandle] {
                currentHandle = parent
            } else {
                break
            }

            // Safety check to prevent infinite loops (shouldn't happen with proper MTP data)
            if visited.count > 1000 {
                log.warning("Path building detected potential cycle or excessive depth for handle \(handle), depth \(visited.count)")
                break
            }
        }

        // Reverse to get root-to-leaf order
        components.reverse()
        return components
    }

    private func markPreviousGenerationTombstoned(deviceId: MTPDeviceID, currentGen: Int) throws {
        try db.withStatement("UPDATE objects SET tombstone = 1 WHERE deviceId = ? AND gen < ? AND tombstone = 0") { stmt in
            try db.bind(stmt, 1, deviceId.raw)
            try db.bind(stmt, 2, Int64(currentGen))
            _ = try db.step(stmt)
        }
    }

    private func recordSnapshot(deviceId: MTPDeviceID, gen: Int, timestamp: Date) throws {
        try db.withStatement("INSERT INTO snapshots(deviceId, gen, createdAt) VALUES(?,?,?)") { stmt in
            try db.bind(stmt, 1, deviceId.raw)
            try db.bind(stmt, 2, Int64(gen))
            try db.bind(stmt, 3, Int64(timestamp.timeIntervalSince1970))
            _ = try db.step(stmt)
        }
    }

    /// Get the latest snapshot generation for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Latest generation number, or nil if no snapshots exist
    public func latestGeneration(for deviceId: MTPDeviceID) throws -> Int? {
        let result = try db.withStatement("SELECT gen FROM snapshots WHERE deviceId = ? ORDER BY gen DESC LIMIT 1") { stmt -> Int64? in
            try db.bind(stmt, 1, deviceId.raw)
            return try db.step(stmt) ? db.colInt64(stmt, 0) : nil
        }
        return result.map { Int($0) }
    }

    /// Get the previous generation before the specified one
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - currentGen: Current generation
    /// - Returns: Previous generation, or nil if none exists
    public func previousGeneration(for deviceId: MTPDeviceID, before currentGen: Int) throws -> Int? {
        let result = try db.withStatement("SELECT gen FROM snapshots WHERE deviceId = ? AND gen < ? ORDER BY gen DESC LIMIT 1") { stmt -> Int64? in
            try db.bind(stmt, 1, deviceId.raw)
            try db.bind(stmt, 2, Int64(currentGen))
            return try db.step(stmt) ? db.colInt64(stmt, 0) : nil
        }
        return result.map { Int($0) }
    }
}
