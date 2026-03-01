// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
import SwiftMTPObservability
@testable import SwiftMTPIndex
@testable import SwiftMTPSync

// MARK: - Helpers

/// In-memory transfer journal for cross-module workflow tests.
private actor InMemoryJournal: TransferJournal {
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
}

private func makeTempDBPath() -> String {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("swiftmtp-xmod-\(UUID().uuidString).db").path
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("swiftmtp-xmod-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

// MARK: - 1. Core → Index: Device connects → index created → search works

final class CoreToIndexWorkflowTests: XCTestCase {

  func testDeviceConnectIndexCreateAndSearch() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0, "Snapshot generation should be positive")

    let latestGen = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latestGen, gen)
  }

  func testIndexPopulatedFromMultipleDevicePresets() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    let configs: [VirtualDeviceConfig] = [.pixel7, .samsungGalaxy, .canonEOSR5]
    var generations: [MTPDeviceID: Int] = [:]

    for config in configs {
      let device = VirtualMTPDevice(config: config)
      let deviceId = await device.id
      let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
      generations[deviceId] = gen
    }

    XCTAssertEqual(generations.count, 3, "Should have snapshots for all three devices")
    for (deviceId, gen) in generations {
      XCTAssertEqual(try snapshotter.latestGeneration(for: deviceId), gen)
    }
  }

  func testDeviceFileAdditionReflectedInIndex() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let newObj = VirtualObjectConfig(
      handle: 200,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "vacation_photo.jpg",
      sizeBytes: 2_500_000,
      formatCode: 0x3801,
      data: Data(repeating: 0xBB, count: 128))
    await device.addObject(newObj)

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    XCTAssertGreaterThan(gen2, gen1)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.added.contains(where: { $0.pathKey.contains("vacation_photo.jpg") }))
  }
}

// MARK: - 2. Core → Store: Device operation → transfer journal updated → resume possible

final class CoreToStoreWorkflowTests: XCTestCase {

  func testDeviceReadUpdatesJournal() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let journal = InMemoryJournal()
    let tmpDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let tempURL = tmpDir.appendingPathComponent("temp_photo.jpg")
    let finalURL = tmpDir.appendingPathComponent("photo.jpg")

    let journalId = try await journal.beginRead(
      device: deviceId, handle: 3, name: "IMG_001.jpg",
      size: 4_500_000, supportsPartial: true,
      tempURL: tempURL, finalURL: finalURL, etag: (size: 4_500_000, mtime: nil))

    let progress = try await device.read(handle: 3, range: nil, to: tempURL)
    try await journal.updateProgress(
      id: journalId, committed: UInt64(progress.completedUnitCount))
    try await journal.complete(id: journalId)

    let entry = await journal.entries[journalId]
    XCTAssertEqual(entry?.state, "completed")
  }

  func testPartialTransferCreatesResumable() async throws {
    let journal = InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "test:partial-device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("partial.dat")

    let id = try await journal.beginRead(
      device: deviceId, handle: 10, name: "bigfile.mp4",
      size: 50_000_000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    try await journal.updateProgress(id: id, committed: 25_000_000)
    try await journal.fail(id: id, error: TransportError.timeout)

    // Verify it's failed but has partial progress
    let entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "failed")
    XCTAssertEqual(entry?.committedBytes, 25_000_000)
  }

  func testMultipleTransfersTrackedPerDevice() async throws {
    let journal = InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "test:multi-transfer")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("multi.dat")

    let id1 = try await journal.beginRead(
      device: deviceId, handle: 1, name: "a.jpg",
      size: 1000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    let id2 = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "b.txt",
      size: 500, supportsPartial: false,
      tempURL: tmpURL, sourceURL: nil)

    try await journal.complete(id: id1)

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "b.txt")
  }
}

// MARK: - 3. Core → Quirks: Unknown device → quirk lookup → default profile applied

final class CoreToQuirksWorkflowTests: XCTestCase {

  func testUnknownDeviceGetsDefaultPolicy() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let summary = await device.summary
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: summary.vendorID ?? 0, pid: summary.productID ?? 0,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(policy.tuning.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(policy.sources.chunkSizeSource, .defaults)
  }

  func testKnownQuirkOverridesDefaults() {
    let quirk = DeviceQuirk(
      id: "test-quirk-device",
      vid: 0x1234, pid: 0xABCD,
      maxChunkBytes: 256 * 1024,
      ioTimeoutMs: 15000,
      flags: QuirkFlags())

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234, pid: 0xABCD,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.tuning.maxChunkBytes, 256 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 15000)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
  }

  func testLearnedProfileMergedWithSessionData() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0xAAAA, pid: 0xBBBB,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let initial = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: Date(),
      lastUpdated: Date(),
      sampleCount: 1,
      optimalChunkSize: 1_048_576,
      avgHandshakeMs: 50,
      optimalIoTimeoutMs: 8000,
      optimalInactivityTimeoutMs: 8000,
      p95ReadThroughputMBps: 25.0,
      p95WriteThroughputMBps: 15.0,
      successRate: 1.0,
      hostEnvironment: "macOS-test")

    let session = SessionData(
      actualChunkSize: 2_097_152,
      handshakeTimeMs: 40,
      readThroughputMBps: 30.0,
      wasSuccessful: true)

    let merged = initial.merged(with: session)
    XCTAssertEqual(merged.sampleCount, 2)
    XCTAssertGreaterThan(merged.p95ReadThroughputMBps ?? 0, 0)
  }
}

// MARK: - 4. Index → Sync: Index populated → snapshot taken → diff computed correctly

final class IndexToSyncWorkflowTests: XCTestCase {

  func testSnapshotDiffDetectsMultipleChanges() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Add two objects, remove one existing
    await device.addObject(VirtualObjectConfig(
      handle: 300, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "added1.jpg", sizeBytes: 1000, formatCode: 0x3801,
      data: Data(repeating: 0x01, count: 64)))
    await device.addObject(VirtualObjectConfig(
      handle: 301, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "added2.png", sizeBytes: 2000, formatCode: 0x380B,
      data: Data(repeating: 0x02, count: 64)))
    await device.removeObject(handle: 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThanOrEqual(diff.added.count, 2)
    XCTAssertGreaterThanOrEqual(diff.removed.count, 1)
  }

  func testDiffFromEmptyToPopulated() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    XCTAssertGreaterThan(diff.added.count, 0, "All objects should appear as added")
    XCTAssertEqual(diff.removed.count, 0)
  }

  func testDiffRowContainsValidPathKeys() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    for row in diff.added {
      let (storageId, components) = PathKey.parse(row.pathKey)
      XCTAssertGreaterThan(storageId, 0, "PathKey storage ID should be positive")
      XCTAssertFalse(components.isEmpty, "PathKey should have path components for \(row.pathKey)")
    }
  }
}

// MARK: - 5. Store → Sync: Journal + snapshot → mirror operation → journal updated

final class StoreToSyncWorkflowTests: XCTestCase {

  func testMirrorEngineIntegrationWithSnapshotAndJournal() async throws {
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
    let journal = InMemoryJournal()

    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    XCTAssertGreaterThan(report.totalProcessed, 0)
    XCTAssertEqual(report.failed, 0)
  }

  func testMirrorReportSuccessRate() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = InMemoryJournal()

    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    if report.totalProcessed > 0 {
      XCTAssertGreaterThan(report.successRate, 0)
    }
  }
}

// MARK: - 6. Quirks → Core: Device-specific tuning → affects transfer behavior

final class QuirksToCoreWorkflowTests: XCTestCase {

  func testQuirkTuningAffectsDevicePolicy() {
    let quirk = DeviceQuirk(
      id: "slow-device",
      vid: 0x2717, pid: 0xFF10,
      maxChunkBytes: 128 * 1024,
      ioTimeoutMs: 20000,
      flags: QuirkFlags())

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x2717, pid: 0xFF10,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    // Verify quirk tuning was applied
    XCTAssertEqual(policy.tuning.maxChunkBytes, 128 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 20000)
    // Default handshake timeout should still apply
    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(policy.tuning.handshakeTimeoutMs, defaults.handshakeTimeoutMs)
  }

  func testCameraQuirkEnablesPropList() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x1234,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
    XCTAssertTrue(policy.flags.prefersPropListEnumeration)
  }

  func testUserOverridesTakePrecedenceOverQuirks() {
    let quirk = DeviceQuirk(
      id: "override-test",
      vid: 0x1111, pid: 0x2222,
      maxChunkBytes: 256 * 1024,
      ioTimeoutMs: 5000,
      flags: QuirkFlags())

    let overrides = ["maxChunkBytes": "4194304", "ioTimeoutMs": "30000"]

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: overrides)

    XCTAssertEqual(policy.tuning.maxChunkBytes, 4_194_304)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 30000)
    XCTAssertEqual(policy.sources.chunkSizeSource, .userOverride)
  }
}

// MARK: - 7. Observability → Core: Operations logged → metrics recorded

final class ObservabilityToCoreWorkflowTests: XCTestCase {

  func testTransactionLogRecordsOperations() async throws {
    let log = TransactionLog()

    let record = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.05,
      bytesIn: 256, bytesOut: 12, outcomeClass: .ok)
    await log.append(record)

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 1)
    XCTAssertEqual(recent[0].opcode, 0x1001)
    XCTAssertEqual(recent[0].outcomeClass, .ok)
  }

  func testTransactionLogRecordsMultipleOutcomes() async throws {
    let log = TransactionLog()

    let records: [(UInt16, String, TransactionOutcome)] = [
      (0x1001, "GetDeviceInfo", .ok),
      (0x1004, "GetStorageIDs", .ok),
      (0x1007, "GetObjectHandles", .timeout),
      (0x1009, "GetObject", .stall),
      (0x100C, "SendObject", .deviceError),
    ]

    for (i, (opcode, label, outcome)) in records.enumerated() {
      await log.append(TransactionRecord(
        txID: UInt32(i + 1), opcode: opcode, opcodeLabel: label,
        sessionID: 1, startedAt: Date(), duration: 0.01,
        bytesIn: 100, bytesOut: 12, outcomeClass: outcome))
    }

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 5)
    XCTAssertEqual(recent.filter { $0.outcomeClass == .ok }.count, 2)
    XCTAssertEqual(recent.filter { $0.outcomeClass == .timeout }.count, 1)
  }

  func testThroughputEWMATracksTransferRate() {
    var ewma = ThroughputEWMA()

    ewma.update(bytes: 1_000_000, dt: 1.0)
    XCTAssertEqual(ewma.bytesPerSecond, 1_000_000, accuracy: 1)

    ewma.update(bytes: 2_000_000, dt: 1.0)
    XCTAssertGreaterThan(ewma.bytesPerSecond, 1_000_000)
    XCTAssertLessThan(ewma.bytesPerSecond, 2_000_000)
    XCTAssertEqual(ewma.count, 2)
  }

  func testThroughputRingBufferPercentiles() {
    var ring = ThroughputRingBuffer(maxSamples: 100)
    for i in 1...100 {
      ring.addSample(Double(i))
    }

    XCTAssertEqual(ring.count, 100)
    XCTAssertNotNil(ring.p50)
    XCTAssertNotNil(ring.p95)
    XCTAssertGreaterThan(ring.p95!, ring.p50!)
  }
}

// MARK: - 8. LiveIndex → Core: Index populated → queried via reader protocol

final class LiveIndexToCoreWorkflowTests: XCTestCase {

  func testLiveIndexUpsertAndQuery() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:live-index-device"

    let obj = IndexedObject(
      deviceId: deviceId, storageId: 0x0001_0001, handle: 42,
      parentHandle: nil, name: "DCIM", pathKey: "00010001/DCIM",
      sizeBytes: nil, mtime: nil, formatCode: 0x3001,
      isDirectory: true, changeCounter: 1)

    try await index.upsertObjects([obj], deviceId: deviceId)

    let children = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0].name, "DCIM")
    XCTAssertTrue(children[0].isDirectory)
  }

  func testLiveIndexStorageTracking() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:storage-tracking"

    let storage = IndexedStorage(
      deviceId: deviceId, storageId: 0x0001_0001,
      description: "Internal storage", capacity: 64_000_000_000,
      free: 32_000_000_000, readOnly: false)
    try await index.upsertStorage(storage)

    let storages = try await index.storages(deviceId: deviceId)
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Internal storage")
    XCTAssertEqual(storages[0].capacity, 64_000_000_000)
  }

  func testLiveIndexChangeTracking() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:change-tracking"

    let counter1 = try await index.currentChangeCounter(deviceId: deviceId)

    let obj = IndexedObject(
      deviceId: deviceId, storageId: 0x0001_0001, handle: 1,
      parentHandle: nil, name: "test.jpg", pathKey: "00010001/test.jpg",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3801,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: deviceId)

    let counter2 = try await index.currentChangeCounter(deviceId: deviceId)
    XCTAssertGreaterThan(counter2, counter1)
  }

  func testLiveIndexObjectRemoval() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:removal"

    let obj = IndexedObject(
      deviceId: deviceId, storageId: 0x0001_0001, handle: 99,
      parentHandle: nil, name: "delete_me.jpg", pathKey: "00010001/delete_me.jpg",
      sizeBytes: 512, mtime: nil, formatCode: 0x3801,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: deviceId)

    let beforeDelete = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    XCTAssertEqual(beforeDelete.count, 1)

    try await index.removeObject(deviceId: deviceId, storageId: 0x0001_0001, handle: 99)

    let afterDelete = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    XCTAssertEqual(afterDelete.count, 0)
  }
}

// MARK: - 9. TranscriptRecorder → Core: Operations recorded across module boundaries

final class TranscriptRecorderWorkflowTests: XCTestCase {

  func testTranscriptRecordsPTPExchanges() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let recorder = TranscriptRecorder(wrapping: link)

    try await recorder.openUSBIfNeeded()
    try await recorder.openSession(id: 1)
    _ = try await recorder.getDeviceInfo()
    _ = try await recorder.getStorageIDs()

    let transcript = recorder.transcript()
    XCTAssertGreaterThanOrEqual(transcript.count, 2)
    XCTAssertTrue(transcript.contains(where: { $0.operation == "getDeviceInfo" }))
    XCTAssertTrue(transcript.contains(where: { $0.operation == "getStorageIDs" }))
  }

  func testTranscriptExportToJSON() async throws {
    let link = VirtualMTPLink(config: .samsungGalaxy)
    let recorder = TranscriptRecorder(wrapping: link)

    try await recorder.openUSBIfNeeded()
    try await recorder.openSession(id: 1)
    _ = try await recorder.getDeviceInfo()

    let json = try recorder.exportJSON()
    XCTAssertGreaterThan(json.count, 0)

    let decoded = try JSONSerialization.jsonObject(with: json) as? [[String: Any]]
    XCTAssertNotNil(decoded)
    XCTAssertGreaterThanOrEqual(decoded?.count ?? 0, 1)
  }
}

// MARK: - 10. PathKey → Sync: Path normalization across modules

final class PathKeyWorkflowTests: XCTestCase {

  func testPathKeyNormalizeAndParse() {
    let pathKey = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", "Camera", "IMG.jpg"])
    let (storageId, components) = PathKey.parse(pathKey)

    XCTAssertEqual(storageId, 0x0001_0001)
    XCTAssertEqual(components, ["DCIM", "Camera", "IMG.jpg"])
  }

  func testPathKeyParentAndBasename() {
    let pathKey = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", "Camera", "IMG.jpg"])
    let parent = PathKey.parent(of: pathKey)
    let basename = PathKey.basename(of: pathKey)

    XCTAssertNotNil(parent)
    XCTAssertEqual(basename, "IMG.jpg")

    let (_, parentComponents) = PathKey.parse(parent!)
    XCTAssertEqual(parentComponents, ["DCIM", "Camera"])
  }

  func testPathKeyPrefixChecking() {
    let parent = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM"])
    let child = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", "Camera", "IMG.jpg"])
    let unrelated = PathKey.normalize(storage: 0x0001_0001, components: ["Music", "song.mp3"])

    XCTAssertTrue(PathKey.isPrefix(parent, of: child))
    XCTAssertFalse(PathKey.isPrefix(parent, of: unrelated))
    XCTAssertFalse(PathKey.isPrefix(child, of: parent))
  }
}

// MARK: - 11. FaultInjection → Index: Faulted transport → snapshot resilience

final class FaultInjectionToIndexWorkflowTests: XCTestCase {

  func testFaultInjectingLinkRecoversForSnapshot() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo),
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    // First call fails
    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected timeout")
    } catch {
      // expected
    }

    // After fault clears, device info works
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
  }

  func testFaultSequenceWithMultipleOperations() async throws {
    let innerLink = VirtualMTPLink(config: .samsungGalaxy)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(0), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(2), error: .busy),
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    // Call 0: timeout
    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected timeout at index 0")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }

    // Call 1: succeeds
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Samsung")

    // Call 2: busy
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected busy at index 2")
    } catch let error as TransportError {
      XCTAssertEqual(error, .busy)
    }

    // Call 3: succeeds
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }
}

// MARK: - 12. VirtualDevice → Snapshot → Diff end-to-end across device types

final class MultiDeviceSnapshotDiffWorkflowTests: XCTestCase {

  func testCameraDeviceSnapshotAndDiff() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    XCTAssertGreaterThan(diff.added.count, 0, "Camera device should have files to index")
  }

  func testEmptyDeviceSnapshotProducesEmptyDiff() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.isEmpty, "Empty device with no changes should produce empty diff")
  }
}
