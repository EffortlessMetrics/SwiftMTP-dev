import Foundation
import SwiftMTPCore
import SwiftMTPObservability
@preconcurrency import SQLite

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
public final class DiffEngine {
    private let db: Connection
    private let log = MTPLog.index

    // Table definitions
    private let objects = Table("objects")

    // Column expressions
    private let objectDeviceId = Expression<String>("deviceId")
    private let objectStorageId = Expression<Int64>("storageId")
    private let objectHandle = Expression<Int64>("handle")
    private let objectPathKey = Expression<String>("pathKey")
    private let objectSize = Expression<Int64?>("size")
    private let objectMtime = Expression<Int64?>("mtime")
    private let objectFormat = Expression<Int64>("format")
    private let objectGen = Expression<Int64>("gen")

    public init(db: Connection) {
        self.db = db
    }

    /// Compute the differences between two snapshots
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - oldGen: Previous snapshot generation (nil means compare to empty)
    ///   - newGen: New snapshot generation
    /// - Returns: Diff containing added, removed, and modified objects
    public func diff(deviceId: MTPDeviceID, oldGen: Int?, newGen: Int) throws -> MTPDiff {
        log.info("Computing diff for device \(deviceId.raw) between generations \(oldGen ?? -1) and \(newGen)")

        let startTime = Date()

        // Load objects from both generations
        let oldObjects = try loadObjects(deviceId: deviceId, gen: oldGen)
        let newObjects = try loadObjects(deviceId: deviceId, gen: newGen)

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
    private func loadObjects(deviceId: MTPDeviceID, gen: Int?) throws -> [String: ObjectRecord] {
        guard let gen = gen else { return [:] }

        let query = objects.filter(
            objectDeviceId == deviceId.raw &&
            objectGen == Int64(gen)
        )

        var result = [String: ObjectRecord]()

        for row in try db.prepare(query) {
            let storageId = UInt32(row[objectStorageId])
            let handle = UInt32(row[objectHandle])
            let pathKey = String(row[objectPathKey])
            let size = row[objectSize].map { UInt64($0) }
            let mtime = row[objectMtime].map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let format = UInt16(row[objectFormat])

            let row = MTPDiff.Row(handle: handle, storage: storageId, pathKey: pathKey,
                                size: size, mtime: mtime, format: format)
            let record = ObjectRecord(row: row, size: size, mtime: mtime)
            result[pathKey] = record
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
