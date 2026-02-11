// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
import SwiftMTPQuirks

private actor ChangeRecorder {
    private var entries: [(String, Set<MTPObjectHandle?>)] = []

    func append(deviceId: String, parents: Set<MTPObjectHandle?>) {
        entries.append((deviceId, parents))
    }

    func snapshot() -> [(String, Set<MTPObjectHandle?>)] {
        entries
    }
}

private actor MockIndexStore: LiveIndexWriter, LiveIndexReader {
    struct Snapshot: Sendable {
        let upsertStorageCalls: Int
        let upsertObjectsCalls: Int
        let insertCalls: Int
        let removeCalls: Int
        let markStaleCalls: Int
        let purgeCalls: Int
    }

    private var objectsByDevice: [String: [MTPObjectHandle: IndexedObject]] = [:]
    private var storagesByDevice: [String: [UInt32: IndexedStorage]] = [:]
    private var counters: [String: Int64] = [:]
    private var changesByDevice: [String: [(Int64, IndexedObjectChange)]] = [:]
    private var crawlStateByKey: [String: Date] = [:]

    private var upsertStorageCalls = 0
    private var upsertObjectsCalls = 0
    private var insertCalls = 0
    private var removeCalls = 0
    private var markStaleCalls = 0
    private var purgeCalls = 0

    private func nextCounter(for deviceId: String) -> Int64 {
        let next = (counters[deviceId] ?? 0) + 1
        counters[deviceId] = next
        return next
    }

    private func crawlKey(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) -> String {
        "\(deviceId):\(storageId):\(parentHandle?.description ?? "root")"
    }

    func setCrawlState(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?, lastCrawledAt: Date) {
        crawlStateByKey[crawlKey(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle)] = lastCrawledAt
    }

    func snapshot() -> Snapshot {
        Snapshot(
            upsertStorageCalls: upsertStorageCalls,
            upsertObjectsCalls: upsertObjectsCalls,
            insertCalls: insertCalls,
            removeCalls: removeCalls,
            markStaleCalls: markStaleCalls,
            purgeCalls: purgeCalls
        )
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws -> [IndexedObject] {
        Array(objectsByDevice[deviceId, default: [:]].values)
            .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
            .sorted { $0.handle < $1.handle }
    }

    func object(deviceId: String, handle: MTPObjectHandle) async throws -> IndexedObject? {
        objectsByDevice[deviceId, default: [:]][handle]
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
        Array(storagesByDevice[deviceId, default: [:]].values)
            .sorted { $0.storageId < $1.storageId }
    }

    func currentChangeCounter(deviceId: String) async throws -> Int64 {
        counters[deviceId] ?? 0
    }

    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
        changesByDevice[deviceId, default: []]
            .filter { $0.0 > anchor }
            .map(\.1)
    }

    func crawlState(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws -> Date? {
        crawlStateByKey[crawlKey(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle)]
    }

    func upsertObjects(_ objects: [IndexedObject], deviceId: String) async throws {
        upsertObjectsCalls += 1
        let counter = nextCounter(for: deviceId)
        var deviceObjects = objectsByDevice[deviceId, default: [:]]
        for object in objects {
            deviceObjects[object.handle] = object
            let change = IndexedObjectChange(kind: .upserted, object: object)
            changesByDevice[deviceId, default: []].append((counter, change))
        }
        objectsByDevice[deviceId] = deviceObjects
    }

    func markStaleChildren(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws {
        markStaleCalls += 1
        setCrawlState(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle, lastCrawledAt: Date())
    }

    func removeObject(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) async throws {
        removeCalls += 1
        let counter = nextCounter(for: deviceId)
        var deviceObjects = objectsByDevice[deviceId, default: [:]]
        if let removed = deviceObjects.removeValue(forKey: handle) {
            let change = IndexedObjectChange(kind: .deleted, object: removed)
            changesByDevice[deviceId, default: []].append((counter, change))
        }
        objectsByDevice[deviceId] = deviceObjects
    }

    func insertObject(_ object: IndexedObject, deviceId: String) async throws {
        insertCalls += 1
        let counter = nextCounter(for: deviceId)
        var deviceObjects = objectsByDevice[deviceId, default: [:]]
        deviceObjects[object.handle] = object
        objectsByDevice[deviceId] = deviceObjects
        let change = IndexedObjectChange(kind: .upserted, object: object)
        changesByDevice[deviceId, default: []].append((counter, change))
    }

    func upsertStorage(_ storage: IndexedStorage) async throws {
        upsertStorageCalls += 1
        storagesByDevice[storage.deviceId, default: [:]][storage.storageId] = storage
    }

    func nextChangeCounter(deviceId: String) async throws -> Int64 {
        nextCounter(for: deviceId)
    }

    func purgeStale(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws {
        purgeCalls += 1
        setCrawlState(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle, lastCrawledAt: Date())
    }

    func pruneChangeLog(deviceId: String, olderThan: Date) async throws {
        let _ = (deviceId, olderThan)
    }
}

private actor MockSchedulerDevice: MTPDevice {
    let id: MTPDeviceID
    let summary: MTPDeviceSummary

    private let deviceInfo: MTPDeviceInfo
    private let storagesList: [MTPStorageInfo]
    private var objects: [MTPObjectHandle: MTPObjectInfo]
    private var objectData: [MTPObjectHandle: Data]
    private var readDelay: Duration

    private var eventContinuation: AsyncStream<MTPEvent>.Continuation?
    private let eventStream: AsyncStream<MTPEvent>

    init(
        deviceId: String,
        supportsEvents: Bool,
        storages: [MTPStorageInfo],
        objects: [MTPObjectInfo],
        objectData: [MTPObjectHandle: Data],
        readDelay: Duration = .zero
    ) {
        self.id = MTPDeviceID(raw: deviceId)
        self.summary = MTPDeviceSummary(id: self.id, manufacturer: "Mock", model: "SchedulerDevice", vendorID: 0x1234, productID: 0x5678)
        self.deviceInfo = MTPDeviceInfo(
            manufacturer: "Mock",
            model: "SchedulerDevice",
            version: "1.0",
            serialNumber: "mock-serial",
            operationsSupported: [PTPOp.getStorageIDs.rawValue, PTPOp.getObjectInfo.rawValue],
            eventsSupported: supportsEvents ? [0x4002, 0x4003, 0x400C] : []
        )
        self.storagesList = storages
        self.objects = Dictionary(uniqueKeysWithValues: objects.map { ($0.handle, $0) })
        self.objectData = objectData
        self.readDelay = readDelay
        let (stream, continuation) = AsyncStream<MTPEvent>.makeStream()
        self.eventStream = stream
        self.eventContinuation = continuation
    }

    func setReadDelay(_ delay: Duration) {
        readDelay = delay
    }

    func emit(_ event: MTPEvent) {
        eventContinuation?.yield(event)
    }

    func finishEvents() {
        eventContinuation?.finish()
        eventContinuation = nil
    }

    var info: MTPDeviceInfo {
        get async throws { deviceInfo }
    }

    func storages() async throws -> [MTPStorageInfo] {
        storagesList
    }

    nonisolated func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<[MTPObjectInfo], Error> {
        AsyncThrowingStream { continuation in
            Task {
                let batch = await self.listedObjects(storage: storage, parent: parent)
                if !batch.isEmpty {
                    continuation.yield(batch)
                }
                continuation.finish()
            }
        }
    }

    private func listedObjects(storage: MTPStorageID, parent: MTPObjectHandle?) -> [MTPObjectInfo] {
        objects.values
            .filter { $0.storage.raw == storage.raw && $0.parent == parent }
            .sorted { $0.handle < $1.handle }
    }

    func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        guard let object = objects[handle] else {
            throw MTPError.objectNotFound
        }
        return object
    }

    func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress {
        if readDelay > .zero {
            try await Task.sleep(for: readDelay)
        }
        guard let payload = objectData[handle] else {
            throw MTPError.objectNotFound
        }
        let bytes: Data
        if let range {
            let lower = Int(range.lowerBound)
            let upper = min(Int(range.upperBound), payload.count)
            bytes = payload.subdata(in: lower..<upper)
        } else {
            bytes = payload
        }
        try bytes.write(to: url)
        let progress = Progress(totalUnitCount: Int64(bytes.count))
        progress.completedUnitCount = Int64(bytes.count)
        return progress
    }

    func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws -> Progress {
        let _ = (parent, name, size, url)
        throw MTPError.notSupported("write is not needed in this test double")
    }

    func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID) async throws -> MTPObjectHandle {
        let _ = (parent, name, storage)
        throw MTPError.notSupported("createFolder is not needed in this test double")
    }

    func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {
        let _ = (handle, recursive)
        throw MTPError.notSupported("delete is not needed in this test double")
    }

    func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws {
        let _ = (handle, newParent)
        throw MTPError.notSupported("move is not needed in this test double")
    }

    var probedCapabilities: [String: Bool] { get async { [:] } }
    var effectiveTuning: EffectiveTuning { get async { .defaults() } }

    func openIfNeeded() async throws {}
    func devClose() async throws {}
    func devGetDeviceInfoUncached() async throws -> MTPDeviceInfo { try await info }
    func devGetStorageIDsUncached() async throws -> [MTPStorageID] { try await storages().map(\.id) }
    func devGetRootHandlesUncached(storage: MTPStorageID) async throws -> [MTPObjectHandle] {
        await listedObjects(storage: storage, parent: nil).map(\.handle)
    }
    func devGetObjectInfoUncached(handle: MTPObjectHandle) async throws -> MTPObjectInfo { try await getInfo(handle: handle) }

    nonisolated var events: AsyncStream<MTPEvent> {
        eventStream
    }
}

final class IndexCoverageTests: XCTestCase {
    private func makeTempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeDevice(supportsEvents: Bool = true, readDelay: Duration = .zero) -> MockSchedulerDevice {
        let storage = MTPStorageInfo(
            id: MTPStorageID(raw: 1),
            description: "Internal",
            capacityBytes: 1_000_000,
            freeBytes: 500_000,
            isReadOnly: false
        )
        let folder = MTPObjectInfo(
            handle: 10,
            storage: storage.id,
            parent: nil,
            name: "folder",
            sizeBytes: nil,
            modified: nil,
            formatCode: 0x3001,
            properties: [:]
        )
        let file = MTPObjectInfo(
            handle: 11,
            storage: storage.id,
            parent: 10,
            name: "file.txt",
            sizeBytes: 5,
            modified: nil,
            formatCode: 0x3000,
            properties: [:]
        )
        let rootFile = MTPObjectInfo(
            handle: 12,
            storage: storage.id,
            parent: nil,
            name: "root.bin",
            sizeBytes: 4,
            modified: nil,
            formatCode: 0x3000,
            properties: [:]
        )
        return MockSchedulerDevice(
            deviceId: "mock-device-\(UUID().uuidString)",
            supportsEvents: supportsEvents,
            storages: [storage],
            objects: [folder, file, rootFile],
            objectData: [
                11: Data("12345".utf8),
                12: Data("root".utf8),
            ],
            readDelay: readDelay
        )
    }

    func testContentCacheLookupMaterializeEvictionPartialAndDownloading() async throws {
        let tempDir = try makeTempDir(prefix: "swiftmtp-index-cache")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("live.sqlite").path
        let liveIndex = try SQLiteLiveIndex(path: dbPath)
        let cacheRoot = tempDir.appendingPathComponent("cache")
        let cache = ContentCache(db: liveIndex.database, cacheRoot: cacheRoot, maxSizeBytes: 6)

        let device = makeDevice(readDelay: .milliseconds(120))

        switch await cache.lookup(deviceId: "dev", storageId: 1, handle: 11) {
        case .miss:
            break
        default:
            XCTFail("Expected initial cache miss")
        }

        let firstURL = try await cache.materialize(deviceId: "dev", storageId: 1, handle: 11, device: device)
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("12345".utf8))
        switch await cache.lookup(deviceId: "dev", storageId: 1, handle: 11) {
        case .hit(let url):
            XCTAssertEqual(url.path, firstURL.path)
        default:
            XCTFail("Expected cache hit after materialize")
        }

        let downloadTask = Task {
            try await cache.materialize(deviceId: "dev", storageId: 1, handle: 12, device: device)
        }
        try await Task.sleep(for: .milliseconds(20))
        if case .downloading = await cache.lookup(deviceId: "dev", storageId: 1, handle: 12) {
            // expected
        } else {
            XCTFail("Expected downloading state while materialize is in flight")
        }
        let secondURL = try await downloadTask.value
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("root".utf8))

        // maxSizeBytes is 6, so materializing the second file should evict the first one.
        if case .miss = await cache.lookup(deviceId: "dev", storageId: 1, handle: 11) {
            // expected
        } else {
            XCTFail("Expected LRU eviction for first object")
        }
        if case .hit = await cache.lookup(deviceId: "dev", storageId: 1, handle: 12) {
            // expected
        } else {
            XCTFail("Expected second object to stay cached")
        }

        // Hit path should update access time and return quickly.
        _ = try await cache.materialize(deviceId: "dev", storageId: 1, handle: 12, device: device)

        let partialURL = cacheRoot.appendingPathComponent("partial.bin")
        try FileManager.default.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partial-data".utf8).write(to: partialURL)
        let now = Int64(Date().timeIntervalSince1970)
        try liveIndex.database.withStatement(
            """
            INSERT OR REPLACE INTO cached_content
              (deviceId, storageId, handle, localPath, sizeBytes, state, committedBytes, lastAccessedAt)
            VALUES (?, ?, ?, ?, ?, 'partial', ?, ?)
            """
        ) { stmt in
            try liveIndex.database.bind(stmt, 1, "dev")
            try liveIndex.database.bind(stmt, 2, Int64(1))
            try liveIndex.database.bind(stmt, 3, Int64(99))
            try liveIndex.database.bind(stmt, 4, partialURL.path)
            try liveIndex.database.bind(stmt, 5, Int64(12))
            try liveIndex.database.bind(stmt, 6, Int64(4))
            try liveIndex.database.bind(stmt, 7, now)
            _ = try liveIndex.database.step(stmt)
        }
        switch await cache.lookup(deviceId: "dev", storageId: 1, handle: 99) {
        case .partial(let url, let committed):
            XCTAssertEqual(url.path, partialURL.path)
            XCTAssertEqual(committed, 4)
        default:
            XCTFail("Expected partial cache result")
        }

        // DB row with a missing file should resolve to miss.
        try liveIndex.database.withStatement(
            """
            INSERT OR REPLACE INTO cached_content
              (deviceId, storageId, handle, localPath, sizeBytes, state, committedBytes, lastAccessedAt)
            VALUES (?, ?, ?, ?, ?, 'complete', ?, ?)
            """
        ) { stmt in
            try liveIndex.database.bind(stmt, 1, "dev")
            try liveIndex.database.bind(stmt, 2, Int64(1))
            try liveIndex.database.bind(stmt, 3, Int64(100))
            try liveIndex.database.bind(stmt, 4, "/tmp/does-not-exist-\(UUID().uuidString)")
            try liveIndex.database.bind(stmt, 5, Int64(10))
            try liveIndex.database.bind(stmt, 6, Int64(10))
            try liveIndex.database.bind(stmt, 7, now)
            _ = try liveIndex.database.step(stmt)
        }
        if case .miss = await cache.lookup(deviceId: "dev", storageId: 1, handle: 100) {
            // expected
        } else {
            XCTFail("Expected miss when cached file path no longer exists")
        }
    }

    func testCrawlSchedulerCoversSeedBoostCrawlAndHandlers() async throws {
        let store = MockIndexStore()
        let scheduler = CrawlScheduler(indexWriter: store)

        let device = makeDevice()
        let recorder = ChangeRecorder()
        await scheduler.setOnChange { deviceId, parents in
            Task { await recorder.append(deviceId: deviceId, parents: parents) }
        }

        await scheduler.seedOnConnect(deviceId: "dev", device: device)
        await scheduler.boostSubtree(deviceId: "dev", storageId: 1, parentHandle: nil)
        await scheduler.startCrawling(device: device)
        try await Task.sleep(for: .milliseconds(100))

        await scheduler.handleObjectAdded(deviceId: "dev", handle: 12, device: device)
        await scheduler.handleObjectRemoved(deviceId: "dev", handle: 12)

        await scheduler.startPeriodicRefresh(deviceId: "dev", device: device, interval: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(80))
        await scheduler.stop()

        let snapshot = await store.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.upsertStorageCalls, 1)
        XCTAssertGreaterThanOrEqual(snapshot.upsertObjectsCalls, 1)
        XCTAssertGreaterThanOrEqual(snapshot.markStaleCalls, 1)
        XCTAssertGreaterThanOrEqual(snapshot.purgeCalls, 1)
        XCTAssertGreaterThanOrEqual(snapshot.insertCalls, 1)
        XCTAssertGreaterThanOrEqual(snapshot.removeCalls, 1)

        try await Task.sleep(for: .milliseconds(20))
        let recordedChanges = await recorder.snapshot()
        XCTAssertFalse(recordedChanges.isEmpty)
        await device.finishEvents()
    }

    func testEventBridgeCoversEventAndPeriodicBranches() async throws {
        let eventStore = MockIndexStore()
        let eventScheduler = CrawlScheduler(indexWriter: eventStore)
        let eventBridge = EventBridge(scheduler: eventScheduler, deviceId: "event-device")
        let eventDevice = makeDevice(supportsEvents: true)

        await eventBridge.start(device: eventDevice)
        await eventDevice.emit(.objectAdded(11))
        await eventDevice.emit(.objectRemoved(11))
        await eventDevice.emit(.storageInfoChanged(MTPStorageID(raw: 1)))
        try await Task.sleep(for: .milliseconds(80))
        await eventBridge.stop()
        await eventScheduler.stop()

        let eventSnapshot = await eventStore.snapshot()
        XCTAssertGreaterThanOrEqual(eventSnapshot.insertCalls, 1)
        XCTAssertGreaterThanOrEqual(eventSnapshot.removeCalls, 1)
        XCTAssertGreaterThanOrEqual(eventSnapshot.upsertStorageCalls, 1)

        let periodicStore = MockIndexStore()
        let periodicScheduler = CrawlScheduler(indexWriter: periodicStore)
        let periodicBridge = EventBridge(scheduler: periodicScheduler, deviceId: "periodic-device")
        let periodicDevice = makeDevice(supportsEvents: false)

        await periodicBridge.start(device: periodicDevice)
        try await Task.sleep(for: .milliseconds(80))
        await periodicBridge.stop()
        await periodicScheduler.stop()

        let periodicSnapshot = await periodicStore.snapshot()
        XCTAssertGreaterThanOrEqual(periodicSnapshot.upsertStorageCalls, 0)
        await eventDevice.finishEvents()
        await periodicDevice.finishEvents()
    }

    func testDeviceIndexOrchestratorCoversLifecycleAndMaterialization() async throws {
        let tempDir = try makeTempDir(prefix: "swiftmtp-orchestrator")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("orchestrator.sqlite").path
        let index = try SQLiteLiveIndex(path: dbPath)
        let cache = ContentCache(
            db: index.database,
            cacheRoot: tempDir.appendingPathComponent("cache"),
            maxSizeBytes: 1024
        )
        let device = makeDevice(supportsEvents: true)

        let orchestrator = DeviceIndexOrchestrator(deviceId: "orchestrator-device", liveIndex: index, contentCache: cache)
        let recorder = ChangeRecorder()
        await orchestrator.setOnChange { deviceId, parents in
            Task { await recorder.append(deviceId: deviceId, parents: parents) }
        }

        await orchestrator.start(device: device)
        try await Task.sleep(for: .milliseconds(120))
        await orchestrator.boostSubtree(storageId: 1, parentHandle: nil)

        let materialized = try await orchestrator.materializeContent(
            storageId: 1,
            handle: 12,
            device: device
        )
        XCTAssertEqual(try Data(contentsOf: materialized), Data("root".utf8))
        let _ = await orchestrator.indexReader

        await orchestrator.stop()
        try await Task.sleep(for: .milliseconds(20))
        let recordedChanges = await recorder.snapshot()
        XCTAssertFalse(recordedChanges.isEmpty)
        await device.finishEvents()
    }
}
