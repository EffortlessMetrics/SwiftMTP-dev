import Foundation
import SwiftMTPCore
import SwiftMTPObservability
@preconcurrency import SQLite

/// Captures device object graph into SQLite for offline browsing and diffing
public final class Snapshotter {
    private let db: Connection
    private let log = MTPLog.index

    // Table definitions
    private let devices = Table("devices")
    private let storages = Table("storages")
    private let objects = Table("objects")
    private let snapshots = Table("snapshots")

    // Column expressions
    private let deviceId = Expression<String>("id")
    private let deviceModel = Expression<String?>("model")
    private let deviceLastSeenAt = Expression<Int64?>("lastSeenAt")

    private let storageId = Expression<Int64>("id")
    private let storageDeviceId = Expression<String>("deviceId")
    private let storageDescription = Expression<String?>("description")
    private let storageCapacity = Expression<Int64?>("capacity")
    private let storageFree = Expression<Int64?>("free")
    private let storageReadOnly = Expression<Int64?>("readOnly")
    private let storageLastIndexedAt = Expression<Int64?>("lastIndexedAt")

    private let objectDeviceId = Expression<String>("deviceId")
    private let objectStorageId = Expression<Int64>("storageId")
    private let objectHandle = Expression<Int64>("handle")
    private let objectParentHandle = Expression<Int64?>("parentHandle")
    private let objectName = Expression<String>("name")
    private let objectPathKey = Expression<String>("pathKey")
    private let objectSize = Expression<Int64?>("size")
    private let objectMtime = Expression<Int64?>("mtime")
    private let objectFormat = Expression<Int64>("format")
    private let objectGen = Expression<Int64>("gen")
    private let objectTombstone = Expression<Int64>("tombstone")

    private let snapshotDeviceId = Expression<String>("deviceId")
    private let snapshotGen = Expression<Int64>("gen")
    private let snapshotCreatedAt = Expression<Int64>("createdAt")

    public init(db: Connection) {
        self.db = db
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

        try db.run(devices.insert(or: .replace,
            self.deviceId <- deviceId.raw,
            deviceModel <- info.model,
            deviceLastSeenAt <- Int64(timestamp.timeIntervalSince1970)
        ))
    }

    private func captureStorageInfo(storage: MTPStorageInfo, deviceId: MTPDeviceID, timestamp: Date) async throws {
        try db.run(storages.insert(or: .replace,
            storageId <- Int64(storage.id.raw),
            storageDeviceId <- deviceId.raw,
            storageDescription <- storage.description,
            storageCapacity <- Int64(storage.capacityBytes),
            storageFree <- Int64(storage.freeBytes),
            storageReadOnly <- storage.isReadOnly ? 1 : 0,
            storageLastIndexedAt <- Int64(timestamp.timeIntervalSince1970)
        ))
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
        try db.transaction {
            for object in objects {
                let pathComponents = buildPathComponents(for: object.handle, parentMap: parentMap, nameMap: nameMap)
                let pathKey = PathKey.normalize(storage: storage.id.raw, components: pathComponents)

                try db.run(self.objects.insert(or: .replace,
                    objectDeviceId <- deviceId.raw,
                    objectStorageId <- Int64(storage.id.raw),
                    objectHandle <- Int64(object.handle),
                    objectParentHandle <- object.parent.map { Int64($0) },
                    objectName <- object.name,
                    objectPathKey <- pathKey,
                    objectSize <- object.sizeBytes.map { Int64($0) },
                    objectMtime <- object.modified.map { Int64($0.timeIntervalSince1970) },
                    objectFormat <- Int64(object.formatCode),
                    objectGen <- Int64(gen),
                    objectTombstone <- 0
                ))
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
        let previousObjects = objects.filter(
            objectDeviceId == deviceId.raw &&
            objectGen < Int64(currentGen) &&
            objectTombstone == 0
        )

        try db.run(previousObjects.update(objectTombstone <- 1))
    }

    private func recordSnapshot(deviceId: MTPDeviceID, gen: Int, timestamp: Date) throws {
        try db.run(self.snapshots.insert(
            snapshotDeviceId <- deviceId.raw,
            snapshotGen <- Int64(gen),
            snapshotCreatedAt <- Int64(timestamp.timeIntervalSince1970)
        ))
    }

    /// Get the latest snapshot generation for a device
    /// - Parameter deviceId: Device identifier
    /// - Returns: Latest generation number, or nil if no snapshots exist
    public func latestGeneration(for deviceId: MTPDeviceID) throws -> Int? {
        let query = snapshots.filter(snapshotDeviceId == deviceId.raw)
            .order(snapshotGen.desc)
            .limit(1)

        guard let row = try db.pluck(query) else { return nil }
        return Int(row[snapshotGen])
    }

    /// Get the previous generation before the specified one
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - currentGen: Current generation
    /// - Returns: Previous generation, or nil if none exists
    public func previousGeneration(for deviceId: MTPDeviceID, before currentGen: Int) throws -> Int? {
        let query = snapshots.filter(
            snapshotDeviceId == deviceId.raw &&
            snapshotGen < Int64(currentGen)
        ).order(snapshotGen.desc).limit(1)

        guard let row = try db.pluck(query) else { return nil }
        return Int(row[snapshotGen])
    }
}
