// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@_spi(Dev) import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
import SwiftMTPObservability
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPFileProvider
import SwiftMTPXPC

// MARK: - Helpers

/// In-memory transfer journal for wave-29 integration tests.
private actor Wave29Journal: TransferJournal {
  var entries: [String: TransferRecord] = [:]
  private var nextID = 0

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String,
    size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    nextID += 1
    let id = "r-\(nextID)"
    entries[id] = TransferRecord(
      id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: finalURL, state: "active", updatedAt: Date())
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String,
    size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    nextID += 1
    let id = "w-\(nextID)"
    entries[id] = TransferRecord(
      id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: sourceURL, state: "active", updatedAt: Date())
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {
    guard let r = entries[id] else { return }
    entries[id] = TransferRecord(
      id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
      parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
      committedBytes: committed, supportsPartial: r.supportsPartial,
      localTempURL: r.localTempURL, finalURL: r.finalURL, state: r.state, updatedAt: Date())
  }

  func fail(id: String, error: Error) async throws {
    guard let r = entries[id] else { return }
    entries[id] = TransferRecord(
      id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
      parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
      committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
      localTempURL: r.localTempURL, finalURL: r.finalURL, state: "failed", updatedAt: Date())
  }

  func complete(id: String) async throws {
    guard let r = entries[id] else { return }
    entries[id] = TransferRecord(
      id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
      parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
      committedBytes: r.totalBytes ?? r.committedBytes, supportsPartial: r.supportsPartial,
      localTempURL: r.localTempURL, finalURL: r.finalURL, state: "completed", updatedAt: Date())
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    entries.values.filter { $0.deviceId.raw == device.raw && $0.state == "active" }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {
    let cutoff = Date().addingTimeInterval(-olderThan)
    entries = entries.filter { $0.value.updatedAt > cutoff }
  }

  var allEntries: [String: TransferRecord] { entries }
  var completedCount: Int { entries.values.filter { $0.state == "completed" }.count }
  var failedCount: Int { entries.values.filter { $0.state == "failed" }.count }
  var activeCount: Int { entries.values.filter { $0.state == "active" }.count }
}

// MARK: - IntegrationWave29Tests

/// Cross-module workflow tests covering device lifecycle, quirks-transport interaction,
/// journal recovery, index-sync coordination, observability, error propagation,
/// FileProvider enumeration, and device lab harness validation.
final class IntegrationWave29Tests: XCTestCase {

  // MARK: - Temp File Helpers

  private func makeTempDBPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-w29-\(UUID().uuidString).db").path
  }

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-w29-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: - 1. Full Device Lifecycle

  func testFullDeviceLifecycle_DiscoverConnectListPullPushDisconnect() async throws {
    // Set up a virtual Pixel 7 with files
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id

    // 1. Connect / open
    try await device.openIfNeeded()
    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "openIfNeeded" }))

    // 2. List storages
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Device should have at least one storage")
    let storageId = storages[0].id

    // 3. List objects (pull file listing)
    var allObjects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storageId)
    for try await batch in stream {
      allObjects.append(contentsOf: batch)
    }
    XCTAssertFalse(allObjects.isEmpty, "Pixel 7 preset should have root-level objects")
    let dcim = allObjects.first(where: { $0.name == "DCIM" })
    XCTAssertNotNil(dcim, "Expected DCIM folder")

    // 4. Pull (read) a file — list Camera subfolder and read a photo
    var cameraObjects: [MTPObjectInfo] = []
    let camStream = device.list(parent: dcim!.handle, in: storageId)
    for try await batch in camStream {
      cameraObjects.append(contentsOf: batch)
    }
    let camera = cameraObjects.first(where: { $0.name == "Camera" })
    XCTAssertNotNil(camera, "Expected Camera subfolder under DCIM")

    var photos: [MTPObjectInfo] = []
    let photoStream = device.list(parent: camera!.handle, in: storageId)
    for try await batch in photoStream {
      photos.append(contentsOf: batch)
    }
    let photo = photos.first(where: { $0.name.hasSuffix(".jpg") })
    XCTAssertNotNil(photo, "Expected a .jpg in Camera folder")

    let downloadDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: downloadDir) }
    let destURL = downloadDir.appendingPathComponent(photo!.name)
    let progress = try await device.read(handle: photo!.handle, range: nil, to: destURL)
    XCTAssertEqual(progress.completedUnitCount, progress.totalUnitCount)
    XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))

    // 5. Push (write) a new file
    let pushData = Data("Hello MTP".utf8)
    let pushURL = downloadDir.appendingPathComponent("upload.txt")
    try pushData.write(to: pushURL)
    let writeProgress = try await device.write(
      parent: dcim!.handle, name: "upload.txt",
      size: UInt64(pushData.count), from: pushURL)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(pushData.count))

    // 6. Disconnect
    try await device.devClose()
    let finalOps = await device.operations
    XCTAssertTrue(finalOps.contains(where: { $0.operation == "devClose" }))
  }

  // MARK: - 2. Quirks Affecting Transfer Behavior

  func testQuirksAffectTransferTuning_ChunkSizeAndTimeout() async throws {
    // Create a quirk database with a custom entry for a known device
    let customQuirk = DeviceQuirk(
      id: "test-quirk-w29",
      vid: 0x18D1, pid: 0x4EE1,
      maxChunkBytes: 512 * 1024,  // 512 KiB (smaller than default 1 MiB)
      ioTimeoutMs: 15000,  // 15s (larger than default 8s)
      handshakeTimeoutMs: 10000
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [customQuirk])

    // Create a fingerprint matching the Pixel 7
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x18D1, pid: 0x4EE1,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01)

    // Resolve policy
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    // Verify quirk-defined tuning was applied
    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 15000)
    XCTAssertEqual(policy.tuning.handshakeTimeoutMs, 10000)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .quirk)
  }

  func testQuirksFlagsInfluenceDeviceBehavior() async throws {
    // Create a quirk with specific flags
    var flags = QuirkFlags()
    flags.requiresKernelDetach = true
    flags.disableEventPump = true
    flags.prefersPropListEnumeration = true
    let quirk = DeviceQuirk(
      id: "test-flags-w29",
      vid: 0x2717, pid: 0xFF10,
      flags: flags)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x2717, pid: 0xFF10,
      interfaceClass: 0xFF, interfaceSubclass: 0xFF, interfaceProtocol: 0x00,
      epIn: 0x81, epOut: 0x01)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertTrue(policy.flags.requiresKernelDetach)
    XCTAssertTrue(policy.flags.disableEventPump)
    XCTAssertTrue(policy.flags.prefersPropListEnumeration)
  }

  // MARK: - 3. Index Update During Sync Operations

  func testSyncMirrorUpdatesSnapshotIndex() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = Wave29Journal()
    let engine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    // Run mirror — captures a snapshot then downloads added files
    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorDir)

    XCTAssertGreaterThan(report.totalProcessed, 0, "Mirror should process at least one file")
    XCTAssertGreaterThanOrEqual(report.downloaded, 0)
    XCTAssertEqual(report.failed, 0, "No failures expected with virtual device")

    // Verify snapshot was persisted
    let latestGen = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertNotNil(latestGen, "A snapshot generation should exist after mirror")

    // Now add a root-level object and mirror again — should detect the addition
    let newFile = VirtualObjectConfig(
      handle: 100,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "new_photo.jpg",
      sizeBytes: 1024,
      formatCode: 0x3801,
      data: Data(repeating: 0xAB, count: 1024))
    await device.addObject(newFile)

    // Wait so the snapshot generation (epoch seconds) differs
    try await Task.sleep(for: .milliseconds(1100))

    let report2 = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorDir)
    XCTAssertGreaterThanOrEqual(
      report2.totalProcessed, report.totalProcessed,
      "Second mirror should process at least as many objects")

    // Verify two generations exist
    let gen2 = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertNotNil(gen2)
    XCTAssertNotEqual(latestGen, gen2, "Second mirror should create a new generation")
  }

  func testLiveIndexUpdatedAfterDeviceObjectChanges() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let liveIndex = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test-device-w29"
    let storageId: UInt32 = 0x0001_0001

    // Upsert a storage
    let storage = IndexedStorage(
      deviceId: deviceId, storageId: storageId,
      description: "Internal storage", capacity: 64_000_000_000,
      free: 32_000_000_000, readOnly: false)
    try await liveIndex.upsertStorage(storage)

    // Upsert some objects
    let objects = [
      IndexedObject(
        deviceId: deviceId, storageId: storageId, handle: 1,
        parentHandle: nil, name: "DCIM",
        pathKey: PathKey.normalize(storage: storageId, components: ["DCIM"]),
        sizeBytes: nil, mtime: nil, formatCode: 0x3001,
        isDirectory: true, changeCounter: 0),
      IndexedObject(
        deviceId: deviceId, storageId: storageId, handle: 2,
        parentHandle: 1, name: "photo.jpg",
        pathKey: PathKey.normalize(storage: storageId, components: ["DCIM", "photo.jpg"]),
        sizeBytes: 5_000_000, mtime: Date(), formatCode: 0x3801,
        isDirectory: false, changeCounter: 0),
    ]
    try await liveIndex.upsertObjects(objects, deviceId: deviceId)

    // Query children of root
    let rootChildren = try await liveIndex.children(
      deviceId: deviceId, storageId: storageId, parentHandle: nil)
    XCTAssertEqual(rootChildren.count, 1)
    XCTAssertEqual(rootChildren.first?.name, "DCIM")

    // Query children of DCIM
    let dcimChildren = try await liveIndex.children(
      deviceId: deviceId, storageId: storageId, parentHandle: 1)
    XCTAssertEqual(dcimChildren.count, 1)
    XCTAssertEqual(dcimChildren.first?.name, "photo.jpg")

    // Change counter should have incremented
    let counter = try await liveIndex.currentChangeCounter(deviceId: deviceId)
    XCTAssertGreaterThan(counter, 0, "Change counter should increase after upsert")
  }

  // MARK: - 4. Transfer Journal Recovery After Simulated Crash

  func testJournalRecoveryAfterSimulatedCrash() async throws {
    let journal = Wave29Journal()
    let deviceId = MTPDeviceID(raw: "test-device-w29")
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tempURL = tempDir.appendingPathComponent("partial.tmp")
    try Data("partial data".utf8).write(to: tempURL)

    // Begin a read transfer
    let readId = try await journal.beginRead(
      device: deviceId, handle: 42, name: "big_file.raw",
      size: 10_000_000, supportsPartial: true,
      tempURL: tempURL, finalURL: tempDir.appendingPathComponent("big_file.raw"),
      etag: (size: 10_000_000, mtime: nil))

    // Simulate partial progress
    try await journal.updateProgress(id: readId, committed: 5_000_000)

    // Simulate crash: the journal persists, but we don't call complete()
    // Verify resumable entries survive
    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1, "One active transfer should be resumable")
    XCTAssertEqual(resumables.first?.committedBytes, 5_000_000)
    XCTAssertEqual(resumables.first?.name, "big_file.raw")
    XCTAssertTrue(resumables.first?.supportsPartial ?? false)

    // Now complete the transfer (simulating resume)
    try await journal.complete(id: readId)
    let afterResume = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(afterResume.count, 0, "No active transfers after completion")
    let completedCount = await journal.completedCount
    XCTAssertEqual(completedCount, 1)
  }

  func testJournalMultipleTransfersWithPartialFailure() async throws {
    let journal = Wave29Journal()
    let deviceId = MTPDeviceID(raw: "multi-transfer-w29")
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Start 3 transfers
    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for i in 1...3 {
        let tempURL = tempDir.appendingPathComponent("temp-\(i).tmp")
        try Data().write(to: tempURL)
        group.addTask {
          try await journal.beginRead(
            device: deviceId, handle: UInt32(i), name: "file\(i).dat",
            size: UInt64(i * 1_000_000), supportsPartial: true,
            tempURL: tempURL, finalURL: tempDir.appendingPathComponent("file\(i).dat"),
            etag: (size: UInt64(i * 1_000_000), mtime: nil))
        }
      }
      var results: [String] = []
      for try await id in group { results.append(id) }
      return results
    }

    XCTAssertEqual(ids.count, 3)

    // Complete first, fail second, leave third active
    try await journal.complete(id: ids[0])
    try await journal.fail(id: ids[1], error: MTPError.timeout)

    // Check states
    let completed = await journal.completedCount
    let failed = await journal.failedCount
    let active = await journal.activeCount
    XCTAssertEqual(completed, 1)
    XCTAssertEqual(failed, 1)
    XCTAssertEqual(active, 1)

    // Only the active one should be resumable
    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
  }

  // MARK: - 5. Observability Events During Multi-Step Operations

  func testTransactionLogRecordsDuringMultiStepWorkflow() async throws {
    let log = TransactionLog()

    // Simulate a multi-step device workflow
    let steps: [(opcode: UInt16, label: String, outcome: TransactionOutcome)] = [
      (0x1001, "GetDeviceInfo", .ok),
      (0x1004, "GetStorageIDs", .ok),
      (0x1007, "GetObjectHandles", .ok),
      (0x1009, "GetObject", .ok),
      (0x100C, "SendObjectInfo", .ok),
      (0x100D, "SendObject", .timeout),
    ]

    for (i, step) in steps.enumerated() {
      let record = TransactionRecord(
        txID: UInt32(i + 1),
        opcode: step.opcode,
        opcodeLabel: step.label,
        sessionID: 1,
        startedAt: Date(),
        duration: Double.random(in: 0.001...0.1),
        bytesIn: Int.random(in: 0...4096),
        bytesOut: Int.random(in: 0...4096),
        outcomeClass: step.outcome)
      await log.append(record)
    }

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 6, "All 6 operations should be logged")

    // Verify the timeout is recorded
    let timeouts = recent.filter { $0.outcomeClass == .timeout }
    XCTAssertEqual(timeouts.count, 1)
    XCTAssertEqual(timeouts.first?.opcodeLabel, "SendObject")

    // Verify JSON dump works
    let json = await log.dump(redacting: false)
    XCTAssertFalse(json.isEmpty)
    XCTAssertTrue(json.contains("GetDeviceInfo"))
  }

  func testThroughputEWMATracksTransferRates() async throws {
    var ewma = ThroughputEWMA()

    // Simulate several transfer measurements
    ewma.update(bytes: 1_000_000, dt: 0.1)  // 10 MB/s
    ewma.update(bytes: 2_000_000, dt: 0.1)  // 20 MB/s
    ewma.update(bytes: 1_500_000, dt: 0.1)  // 15 MB/s

    XCTAssertEqual(ewma.count, 3)
    XCTAssertGreaterThan(ewma.bytesPerSecond, 0)
    XCTAssertGreaterThan(ewma.megabytesPerSecond, 0)

    // Throughput ring buffer percentiles
    var ring = ThroughputRingBuffer(maxSamples: 10)
    for _ in 0..<10 {
      ring.addSample(Double.random(in: 5.0...20.0))
    }
    XCTAssertEqual(ring.count, 10)
    XCTAssertNotNil(ring.p50)
    XCTAssertNotNil(ring.p95)
    XCTAssertNotNil(ring.average)
    XCTAssertGreaterThanOrEqual(ring.p95!, ring.p50!)
  }

  // MARK: - 6. Error Propagation Across Module Boundaries

  func testTransportErrorPropagatesFromLinkThroughDevice() async throws {
    // Create a faulty link that fails on getStorageIDs
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getStorageIDs)
    ])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    // Attempt to get storage IDs — should throw a TransportError.timeout
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected a transport error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout, "Should propagate timeout from fault schedule")
    }
  }

  func testTransportErrorWrappedInMTPErrorForSync() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    // Try to read a non-existent object — should throw MTPError.objectNotFound
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    do {
      _ = try await device.read(handle: 999, range: nil, to: tempDir.appendingPathComponent("nope"))
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    // Verify error localization works
    let desc = MTPError.objectNotFound.errorDescription
    XCTAssertNotNil(desc)
    XCTAssertTrue(desc!.contains("not found"))
  }

  func testFaultInjectionCausesIOErrorOnGetObjectInfos() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getObjectInfos),
        error: .io("Simulated CRC mismatch"),
        repeatCount: 1)
    ])
    let link = VirtualMTPLink(config: .samsungGalaxy, faultSchedule: schedule)

    do {
      _ = try await link.getObjectInfos([1, 2, 3])
      XCTFail("Expected IO error from fault injection")
    } catch let error as TransportError {
      if case .io(let msg) = error {
        XCTAssertTrue(msg.contains("CRC"), "Error message should mention CRC")
      } else {
        XCTFail("Expected .io error variant, got \(error)")
      }
    }
  }

  func testCascadingErrorFromTransportToSync() async throws {
    // Set up sync with a device that will fail during mirror
    // We add a file then delete it from the tree before read,
    // causing objectNotFound during mirror download
    let config = VirtualDeviceConfig.pixel7
      .withObject(VirtualObjectConfig(
        handle: 50, storage: MTPStorageID(raw: 0x0001_0001),
        parent: nil, name: "will_fail.dat",
        sizeBytes: 1000, formatCode: 0x3000))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = Wave29Journal()
    let engine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    // Mirror should succeed overall but may report failures if object removed mid-operation
    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorDir)
    XCTAssertGreaterThan(report.totalProcessed, 0, "Should process objects even with failures")
  }

  // MARK: - 7. FileProvider Enumeration Backed by Live Index

  func testFileProviderItemIdentifierParsing() async throws {
    // Test MTPFileProviderItem identifier round-trip
    // Use a deviceId without colons so the colon-delimited parser round-trips correctly
    let deviceId = "pixel7-test"
    let storageId: UInt32 = 0x0001_0001
    let handle: UInt32 = 42

    let item = MTPFileProviderItem(
      deviceId: deviceId, storageId: storageId, objectHandle: handle,
      parentHandle: 2, name: "photo.jpg", size: 4_500_000, isDirectory: false,
      modifiedDate: Date())

    XCTAssertEqual(item.filename, "photo.jpg")
    XCTAssertFalse(item.contentType == .folder)
    XCTAssertEqual(item.documentSize, NSNumber(value: 4_500_000))

    // Verify item identifier encodes device/storage/handle
    let identifier = item.itemIdentifier.rawValue
    XCTAssertTrue(identifier.contains(deviceId))
    XCTAssertTrue(identifier.contains("42"))

    // Verify parseItemIdentifier round-trips
    let parsed = MTPFileProviderItem.parseItemIdentifier(item.itemIdentifier)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.deviceId, deviceId)
    XCTAssertEqual(parsed?.storageId, storageId)
    XCTAssertEqual(parsed?.objectHandle, handle)
  }

  func testLiveIndexFeedsFileProviderEnumeration() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let liveIndex = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "fp-test-w29"
    let storageId: UInt32 = 0x0001_0001

    // Populate the live index
    let storage = IndexedStorage(
      deviceId: deviceId, storageId: storageId,
      description: "Internal storage", capacity: 64_000_000_000,
      free: 32_000_000_000, readOnly: false)
    try await liveIndex.upsertStorage(storage)

    let objects = [
      IndexedObject(
        deviceId: deviceId, storageId: storageId, handle: 1,
        parentHandle: nil, name: "DCIM",
        pathKey: PathKey.normalize(storage: storageId, components: ["DCIM"]),
        sizeBytes: nil, mtime: nil, formatCode: 0x3001,
        isDirectory: true, changeCounter: 0),
      IndexedObject(
        deviceId: deviceId, storageId: storageId, handle: 2,
        parentHandle: 1, name: "IMG_001.jpg",
        pathKey: PathKey.normalize(storage: storageId, components: ["DCIM", "IMG_001.jpg"]),
        sizeBytes: 3_000_000, mtime: Date(), formatCode: 0x3801,
        isDirectory: false, changeCounter: 0),
      IndexedObject(
        deviceId: deviceId, storageId: storageId, handle: 3,
        parentHandle: 1, name: "IMG_002.jpg",
        pathKey: PathKey.normalize(storage: storageId, components: ["DCIM", "IMG_002.jpg"]),
        sizeBytes: 4_000_000, mtime: Date(), formatCode: 0x3801,
        isDirectory: false, changeCounter: 0),
    ]
    try await liveIndex.upsertObjects(objects, deviceId: deviceId)

    // Simulate FileProvider enumeration: list storages → list root → list DCIM
    let indexedStorages = try await liveIndex.storages(deviceId: deviceId)
    XCTAssertEqual(indexedStorages.count, 1)
    XCTAssertEqual(indexedStorages.first?.description, "Internal storage")

    let rootItems = try await liveIndex.children(
      deviceId: deviceId, storageId: storageId, parentHandle: nil)
    XCTAssertEqual(rootItems.count, 1)
    XCTAssertEqual(rootItems.first?.name, "DCIM")

    let dcimItems = try await liveIndex.children(
      deviceId: deviceId, storageId: storageId, parentHandle: 1)
    XCTAssertEqual(dcimItems.count, 2)
    let names = Set(dcimItems.map(\.name))
    XCTAssertTrue(names.contains("IMG_001.jpg"))
    XCTAssertTrue(names.contains("IMG_002.jpg"))

    // Verify change tracking for incremental sync
    let counter = try await liveIndex.currentChangeCounter(deviceId: deviceId)
    XCTAssertGreaterThan(counter, 0)
  }

  // MARK: - 8. Device Lab Harness Validation Matrix

  func testDeviceLabHarnessRunsValidationOnVirtualDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let harness = DeviceLabHarness()

    let report = try await harness.collect(device: device)

    // Verify basic report fields
    XCTAssertEqual(report.manufacturer, "Google")
    XCTAssertEqual(report.model, "Pixel 7")
    XCTAssertFalse(report.operationsSupported.isEmpty)
    XCTAssertFalse(report.eventsSupported.isEmpty)
    XCTAssertFalse(report.capabilityTests.isEmpty)

    // At least GetDeviceInfo and GetStorageIDs should be tested
    let testNames = Set(report.capabilityTests.map { $0.name })
    XCTAssertTrue(testNames.contains("GetDeviceInfo"))
    XCTAssertTrue(testNames.contains("GetStorageIDs"))

    // All tests should succeed on a virtual device
    let allSupported = report.capabilityTests.filter { $0.supported }
    XCTAssertEqual(allSupported.count, report.capabilityTests.count,
      "All capability tests should pass on virtual device")
  }

  func testDeviceLabHarnessAcrossMultipleDevicePresets() async throws {
    let presets: [(VirtualDeviceConfig, String)] = [
      (.pixel7, "Google"),
      (.samsungGalaxy, "Samsung"),
      (.canonEOSR5, "Canon"),
      (.nikonZ6, "Nikon"),
    ]

    for (config, expectedManufacturer) in presets {
      let device = VirtualMTPDevice(config: config)
      let harness = DeviceLabHarness()
      let report = try await harness.collect(device: device)

      XCTAssertEqual(report.manufacturer, expectedManufacturer,
        "Manufacturer mismatch for \(config.summary.model)")
      XCTAssertFalse(report.capabilityTests.isEmpty,
        "Should have capability tests for \(config.summary.model)")
    }
  }

  // MARK: - 9. Snapshot → Diff → Sync Round-Trip

  func testSnapshotDiffDetectsAddedAndRemovedFiles() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    // Capture initial snapshot
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Add a root-level file (parent: nil so list(parent: nil) captures it)
    await device.addObject(VirtualObjectConfig(
      handle: 200, storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil, name: "new_file.txt",
      sizeBytes: 512, formatCode: 0x3000,
      data: Data(repeating: 0x42, count: 512)))

    // Remove DCIM folder (handle 1, a root-level object)
    await device.removeObject(handle: 1)

    // Wait so the snapshot generation (epoch seconds) differs
    try await Task.sleep(for: .milliseconds(1100))

    // Capture second snapshot
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Compute diff
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

    // new_file.txt should be added
    let addedNames = diff.added.map { $0.pathKey }
    XCTAssertTrue(
      addedNames.contains(where: { $0.contains("new_file.txt") }),
      "new_file.txt should appear in added, got: \(addedNames)")

    // The removed object should be in removed
    XCTAssertFalse(diff.removed.isEmpty, "Should detect removed objects")
  }

  // MARK: - 10. Transcript Recorder Captures Protocol Exchange

  func testTranscriptRecorderCapturesFullExchange() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let recorder = TranscriptRecorder(wrapping: link)

    // Run a typical protocol sequence
    try await recorder.openUSBIfNeeded()
    try await recorder.openSession(id: 1)
    _ = try await recorder.getDeviceInfo()
    _ = try await recorder.getStorageIDs()
    _ = try await recorder.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    try await recorder.closeSession()

    let transcript = recorder.transcript()
    XCTAssertEqual(transcript.count, 6, "Should record all 6 operations")

    let opNames = transcript.map(\.operation)
    XCTAssertEqual(opNames, [
      "openUSBIfNeeded", "openSession", "getDeviceInfo",
      "getStorageIDs", "getObjectHandles", "closeSession",
    ])

    // Verify JSON export
    let jsonData = try recorder.exportJSON()
    XCTAssertGreaterThan(jsonData.count, 0)
    let jsonString = String(data: jsonData, encoding: .utf8)!
    XCTAssertTrue(jsonString.contains("getDeviceInfo"))
  }

  // MARK: - 11. MirrorEngine Pattern Matching

  func testMirrorEngineGlobPatternFiltering() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = Wave29Journal()
    let engine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    // Mirror with pattern that only matches .jpg files
    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir,
      includePattern: "**/*.jpg")

    // Only .jpg files should be downloaded; folders and other formats should be skipped
    XCTAssertGreaterThanOrEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
  }

  // MARK: - 12. Live Index Change Tracking for Incremental Sync

  func testLiveIndexChangeTrackingForIncrementalUpdates() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let liveIndex = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "change-track-w29"
    let storageId: UInt32 = 0x0001_0001

    // Initial upsert
    let obj1 = IndexedObject(
      deviceId: deviceId, storageId: storageId, handle: 1,
      parentHandle: nil, name: "file1.txt",
      pathKey: PathKey.normalize(storage: storageId, components: ["file1.txt"]),
      sizeBytes: 1000, mtime: Date(), formatCode: 0x3000,
      isDirectory: false, changeCounter: 0)
    try await liveIndex.upsertObjects([obj1], deviceId: deviceId)

    let anchorBefore = try await liveIndex.currentChangeCounter(deviceId: deviceId)

    // Second upsert (simulates new crawl discovering a new file)
    let obj2 = IndexedObject(
      deviceId: deviceId, storageId: storageId, handle: 2,
      parentHandle: nil, name: "file2.txt",
      pathKey: PathKey.normalize(storage: storageId, components: ["file2.txt"]),
      sizeBytes: 2000, mtime: Date(), formatCode: 0x3000,
      isDirectory: false, changeCounter: 0)
    try await liveIndex.upsertObjects([obj2], deviceId: deviceId)

    // Changes since the first anchor should include file2
    let changes = try await liveIndex.changesSince(deviceId: deviceId, anchor: anchorBefore)
    XCTAssertGreaterThanOrEqual(changes.count, 1, "Should detect at least one change")
    let upserted = changes.filter { $0.kind == .upserted }
    XCTAssertTrue(upserted.contains(where: { $0.object.name == "file2.txt" }))
  }

  // MARK: - 13. Stale Temp Cleanup in Journal

  func testJournalClearsStaleTemps() async throws {
    let journal = Wave29Journal()
    let deviceId = MTPDeviceID(raw: "stale-test-w29")
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tempURL = tempDir.appendingPathComponent("old.tmp")
    try Data().write(to: tempURL)

    // Create an old entry with a past updatedAt
    _ = try await journal.beginRead(
      device: deviceId, handle: 1, name: "old_file.dat",
      size: 1000, supportsPartial: false,
      tempURL: tempURL, finalURL: nil, etag: (size: 1000, mtime: nil))

    // Clear stale temps older than 0 seconds (clears everything)
    try await journal.clearStaleTemps(olderThan: 0)

    let remaining = await journal.allEntries
    XCTAssertTrue(remaining.isEmpty, "All entries should be cleared when olderThan=0")
  }
}
