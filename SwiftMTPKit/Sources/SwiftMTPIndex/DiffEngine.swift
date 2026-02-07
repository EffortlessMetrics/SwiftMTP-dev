// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import OSLog
import SQLite3

/// Represents the differences between two device snapshots
public struct MTPDiff: Sendable {
    /// Objects that were added in the new snapshot
    public var added: [Row] = []
    /// Objects that were removed (tombstoned) in the new snapshot
    public var removed: [Row] = []
    /// Objects that were modified between snapshots
    public var modified: [Row] = []

    /// Represents a single object in the diff
    public struct Row: Sendable {
        public let handle: UInt32
        public let storage: UInt32
        public let pathKey: String
        public let size: UInt64?
        public let mtime: Date?
        public let format: UInt16

        public init(handle: UInt32, storage: UInt32, pathKey: String, size: UInt64?, mtime: Date?, format: UInt16) {
            self.handle = handle
            self.storage = storage
            self.pathKey = pathKey
            self.size = size
            self.mtime = mtime
            self.format = format
        }
    }

    /// Total number of changes
    public var totalChanges: Int {
        added.count + removed.count + modified.count
    }

    /// Check if the diff is empty (no changes)
    public var isEmpty: Bool {
        totalChanges == 0
    }
}

/// Engine for computing differences between device snapshots
public final class DiffEngine: Sendable {
    private let db: SQLiteDB
    private let persistence: (any MTPPersistenceProvider)?
    private let log = Logger(subsystem: "SwiftMTP", category: "index")

    public init(dbPath: String, persistence: (any MTPPersistenceProvider)? = nil) throws {
        self.db = try SQLiteDB(path: dbPath)
        self.persistence = persistence
    }

    /// Compute the differences between two snapshots
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - oldGen: Previous snapshot generation (nil means compare to empty)
    ///   - newGen: New snapshot generation
    /// - Returns: Diff containing added, removed, and modified objects
    public func diff(deviceId: MTPDeviceID, oldGen: Int?, newGen: Int) async throws -> MTPDiff {
        log.info("Computing diff for device \(deviceId.raw) between generations \(oldGen ?? -1) and \(newGen)")

        let startTime = Date()

        // Load objects from both generations
        let oldObjects = try await loadObjects(deviceId: deviceId, gen: oldGen)
        let newObjects = try await loadObjects(deviceId: deviceId, gen: newGen)

        var diff = MTPDiff()
        var matchedPaths = Set<String>()

        // Find added and modified objects
        for (pathKey, newObj) in newObjects {
            if let oldObj = oldObjects[pathKey] {
                // Object exists in both - check for modifications
                if hasChanged(oldObj, newObj) {
                    diff.modified.append(newObj.row)
                }
                matchedPaths.insert(pathKey)
            } else {
                // Object only in new snapshot - added
                diff.added.append(newObj.row)
            }
        }

        // Find removed objects (those in old but not in new)
        for (pathKey, oldObj) in oldObjects where !matchedPaths.contains(pathKey) {
            diff.removed.append(oldObj.row)
        }

        let duration = Date().timeIntervalSince(startTime)
        log.info("Diff computation completed for device \(deviceId.raw): +\(diff.added.count) -\(diff.removed.count) ~\(diff.modified.count) in \(duration)s")

        return diff
    }

    /// Load all objects for a specific generation
    private func loadObjects(deviceId: MTPDeviceID, gen: Int?) async throws -> [String: ObjectRecord] {
        guard let gen = gen else { return [:] }

        var result = [String: ObjectRecord]()

        // Try modern persistence first
        if let persistence = self.persistence {
            let records = try await persistence.objectCatalog.fetchObjects(deviceId: deviceId, generation: gen)
            
            if !records.isEmpty {
                for record in records {
                    let row = MTPDiff.Row(handle: record.handle, storage: record.storage, pathKey: record.pathKey,
                                        size: record.size, mtime: record.mtime, format: record.format)
                    let objectRecord = ObjectRecord(row: row, size: record.size, mtime: record.mtime)
                    result[record.pathKey] = objectRecord
                }
                return result
            }
        }

        // Fallback to SQLite
        try db.withStatement("SELECT storageId, handle, pathKey, size, mtime, format FROM objects WHERE deviceId = ? AND gen = ?") { stmt in
            try db.bind(stmt, 1, deviceId.raw)
            try db.bind(stmt, 2, Int64(gen))

            while try db.step(stmt) {
                let storageId = UInt32(db.colInt64(stmt, 0) ?? 0)
                let handle = UInt32(db.colInt64(stmt, 1) ?? 0)
                let pathKey = db.colText(stmt, 2) ?? ""
                let size = db.colInt64(stmt, 3).map { UInt64($0) }
                let mtime = db.colInt64(stmt, 4).map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let format = UInt16(db.colInt64(stmt, 5) ?? 0)

                let row = MTPDiff.Row(handle: handle, storage: storageId, pathKey: pathKey,
                                    size: size, mtime: mtime, format: format)
                let record = ObjectRecord(row: row, size: size, mtime: mtime)
                result[pathKey] = record
            }
        }

        return result
    }

    /// Check if two object records represent changes
    private func hasChanged(_ oldObj: ObjectRecord, _ newObj: ObjectRecord) -> Bool {
        // Check size difference
        if oldObj.size != newObj.size {
            return true
        }

        // Check modification time difference (with tolerance)
        return !timeEqual(oldObj.mtime, newObj.mtime)
    }

    /// Compare modification times with tolerance for filesystem differences
    private func timeEqual(_ lhs: Date?, _ rhs: Date?, tolerance: TimeInterval = 300) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.timeIntervalSince1970 - right.timeIntervalSince1970) <= tolerance
        default:
            return false // One is nil, other isn't
        }
    }

    /// Internal record type for diff computation
    private struct ObjectRecord {
        let row: MTPDiff.Row
        let size: UInt64?
        let mtime: Date?
    }
}
