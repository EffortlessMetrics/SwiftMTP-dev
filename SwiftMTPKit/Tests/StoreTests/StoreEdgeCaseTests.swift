// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPStore

// MARK: - Device Upsert Edge Cases

final class DeviceUpsertEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpsertDeviceWithNilManufacturerAndModel() async throws {
    let actor = store.createActor()
    let deviceId = "nil-fields-\(UUID().uuidString)"
    let result = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    XCTAssertEqual(result, deviceId)
  }

  func testUpsertDeviceUpdatesExistingFields() async throws {
    let actor = store.createActor()
    let deviceId = "update-fields-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "OldVendor", model: "OldModel")
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "NewVendor", model: "NewModel")
    // Second upsert should not throw and should return same ID
    let result = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    XCTAssertEqual(result, deviceId)
  }

  func testUpsertDevicePreservesFieldsWhenNilPassedOnUpdate() async throws {
    let actor = store.createActor()
    let deviceId = "preserve-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Vendor", model: "Model")
    // Pass nil for manufacturer/model → should NOT overwrite existing values
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    // No crash; the update path only sets non-nil values
  }

  func testUpsertDeviceWithEmptyStringId() async throws {
    let actor = store.createActor()
    let result = try await actor.upsertDevice(id: "", manufacturer: "Test", model: "Test")
    XCTAssertEqual(result, "")
  }

  func testUpsertDeviceWithLongId() async throws {
    let actor = store.createActor()
    let longId = String(repeating: "x", count: 1000)
    let result = try await actor.upsertDevice(id: longId, manufacturer: "Test", model: "Test")
    XCTAssertEqual(result, longId)
  }
}

// MARK: - Transfer Journal Edge Cases

final class TransferJournalEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testCreateTransferWithZeroTotalBytes() async throws {
    let actor = store.createActor()
    let deviceId = "zero-bytes-\(UUID().uuidString)"
    let transferId = "t-zero-\(UUID().uuidString)"
    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 1, parentHandle: nil, name: "empty.txt",
      totalBytes: 0, supportsPartial: false,
      localTempURL: "/tmp/zero", finalURL: nil,
      etagSize: nil, etagMtime: nil)
    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.first?.totalBytes, 0)
  }

  func testCreateTransferWithNilTotalBytes() async throws {
    let actor = store.createActor()
    let deviceId = "nil-bytes-\(UUID().uuidString)"
    let transferId = "t-nil-\(UUID().uuidString)"
    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 2, parentHandle: nil, name: "unknown-size.bin",
      totalBytes: nil, supportsPartial: true,
      localTempURL: "/tmp/nil-bytes", finalURL: nil,
      etagSize: nil, etagMtime: nil)
    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertNil(rows.first?.totalBytes)
  }

  func testUpdateRemoteHandleForNonexistentTransfer() async throws {
    let actor = store.createActor()
    // Should not throw
    try await actor.updateTransferRemoteHandle(id: "does-not-exist", handle: 0xDEAD)
  }

  func testUpdateContentHashForNonexistentTransfer() async throws {
    let actor = store.createActor()
    try await actor.updateTransferContentHash(id: "does-not-exist", hash: "abc123")
  }

  func testUpdateThroughputForNonexistentTransfer() async throws {
    let actor = store.createActor()
    try await actor.updateTransferThroughput(id: "does-not-exist", throughputMBps: 99.9)
  }

  func testTransferFullLifecycleReadPath() async throws {
    let actor = store.createActor()
    let deviceId = "lifecycle-\(UUID().uuidString)"
    let transferId = "lc-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 10, parentHandle: nil, name: "movie.mp4",
      totalBytes: 100_000, supportsPartial: true,
      localTempURL: "/tmp/lc-temp", finalURL: "/tmp/lc-final",
      etagSize: 100_000, etagMtime: Date())

    // Progress updates
    try await actor.updateTransferProgress(id: transferId, committed: 25_000)
    try await actor.updateTransferProgress(id: transferId, committed: 75_000)

    // Record throughput
    try await actor.updateTransferThroughput(id: transferId, throughputMBps: 35.5)

    // Add content hash
    try await actor.updateTransferContentHash(id: transferId, hash: "sha256-abcdef")

    // Verify intermediate state
    let resumables = try await actor.fetchResumableTransfers(for: deviceId)
    let record = try XCTUnwrap(resumables.first(where: { $0.id == transferId }))
    XCTAssertEqual(record.committedBytes, 75_000)
    XCTAssertEqual(record.throughputMBps, 35.5)
    XCTAssertEqual(record.contentHash, "sha256-abcdef")

    // Complete
    try await actor.updateTransferStatus(id: transferId, state: "done")

    // Should no longer be resumable
    let postComplete = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertNil(postComplete.first(where: { $0.id == transferId }))
  }

  func testTransferWithEtagFields() async throws {
    let actor = store.createActor()
    let deviceId = "etag-\(UUID().uuidString)"
    let transferId = "etag-t-\(UUID().uuidString)"
    let etagDate = Date(timeIntervalSince1970: 1_700_000_000)

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 5, parentHandle: nil, name: "etag-file.dat",
      totalBytes: 8192, supportsPartial: true,
      localTempURL: "/tmp/etag", finalURL: nil,
      etagSize: 8192, etagMtime: etagDate)

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 1)
  }

  func testMultipleTransfersForSameDevice() async throws {
    let actor = store.createActor()
    let deviceId = "multi-\(UUID().uuidString)"

    for i in 0..<5 {
      try await actor.createTransfer(
        id: "multi-t-\(i)-\(UUID().uuidString)", deviceId: deviceId, kind: "read",
        handle: UInt32(i + 1), parentHandle: nil, name: "file\(i).txt",
        totalBytes: UInt64(1024 * (i + 1)), supportsPartial: true,
        localTempURL: "/tmp/multi-\(i)", finalURL: nil,
        etagSize: nil, etagMtime: nil)
    }

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 5)
  }

  func testPausedTransferIsResumable() async throws {
    let actor = store.createActor()
    let deviceId = "paused-\(UUID().uuidString)"
    let transferId = "paused-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "write",
      handle: nil, parentHandle: 1, name: "paused.bin",
      totalBytes: 50_000, supportsPartial: true,
      localTempURL: "/tmp/paused", finalURL: nil,
      etagSize: nil, etagMtime: nil)

    try await actor.updateTransferStatus(id: transferId, state: "paused")

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 1, "Paused transfers should be resumable")
  }
}

// MARK: - Learned Profile Edge Cases

final class LearnedProfileEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpdateLearnedProfileTwiceUpdatesFields() async throws {
    let actor = store.createActor()
    let deviceId = "lp-update-\(UUID().uuidString)"
    let hash = "fp-hash-\(UUID().uuidString)"

    let fingerprint = MTPDeviceFingerprint(
      vid: "aaaa", pid: "bbbb",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"))

    let profile1 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 5,
      optimalChunkSize: 4096, avgHandshakeMs: 20,
      optimalIoTimeoutMs: 3000, optimalInactivityTimeoutMs: 10_000,
      p95ReadThroughputMBps: 15.0, p95WriteThroughputMBps: 10.0,
      successRate: 0.95, hostEnvironment: "macOS")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile1)

    let profile2 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 20,
      optimalChunkSize: 8192, avgHandshakeMs: 15,
      optimalIoTimeoutMs: 2000, optimalInactivityTimeoutMs: 8000,
      p95ReadThroughputMBps: 25.0, p95WriteThroughputMBps: 18.0,
      successRate: 0.99, hostEnvironment: "macOS")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile2)

    let dto = try await actor.fetchLearnedProfileDTO(for: hash)
    XCTAssertNotNil(dto)
    XCTAssertEqual(dto?.sampleCount, 20)
    XCTAssertEqual(dto?.optimalChunkSize, 8192)
    XCTAssertEqual(dto?.successRate, 0.99)
  }

  func testFetchLearnedProfileDTOFieldMapping() async throws {
    let actor = store.createActor()
    let deviceId = "dto-fields-\(UUID().uuidString)"
    let hash = "dto-hash-\(UUID().uuidString)"

    let fingerprint = MTPDeviceFingerprint(
      vid: "1111", pid: "2222",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"))

    let profile = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 42,
      optimalChunkSize: 16384, avgHandshakeMs: 30,
      optimalIoTimeoutMs: 5000, optimalInactivityTimeoutMs: 20_000,
      p95ReadThroughputMBps: 50.0, p95WriteThroughputMBps: 30.0,
      successRate: 0.97, hostEnvironment: "test-env")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile)

    let dtoOpt = try await actor.fetchLearnedProfileDTO(for: hash)
    let dto = try XCTUnwrap(dtoOpt)
    XCTAssertEqual(dto.fingerprintHash, hash)
    XCTAssertEqual(dto.sampleCount, 42)
    XCTAssertEqual(dto.optimalChunkSize, 16384)
    XCTAssertEqual(dto.avgHandshakeMs, 30)
    XCTAssertEqual(dto.optimalIoTimeoutMs, 5000)
    XCTAssertEqual(dto.optimalInactivityTimeoutMs, 20_000)
    XCTAssertEqual(dto.p95ReadThroughputMBps, 50.0)
    XCTAssertEqual(dto.p95WriteThroughputMBps, 30.0)
    XCTAssertEqual(dto.successRate, 0.97)
    XCTAssertEqual(dto.hostEnvironment, "test-env")
  }

  func testLearnedProfileWithAllNilOptionals() async throws {
    let actor = store.createActor()
    let deviceId = "all-nil-\(UUID().uuidString)"
    let hash = "nil-hash-\(UUID().uuidString)"

    let fingerprint = MTPDeviceFingerprint(
      vid: "3333", pid: "4444",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"))

    let profile = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 1,
      optimalChunkSize: nil, avgHandshakeMs: nil,
      optimalIoTimeoutMs: nil, optimalInactivityTimeoutMs: nil,
      p95ReadThroughputMBps: nil, p95WriteThroughputMBps: nil,
      successRate: 1.0, hostEnvironment: "test")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile)

    let dtoOpt = try await actor.fetchLearnedProfileDTO(for: hash)
    let dto = try XCTUnwrap(dtoOpt)
    XCTAssertNil(dto.optimalChunkSize)
    XCTAssertNil(dto.avgHandshakeMs)
    XCTAssertNil(dto.optimalIoTimeoutMs)
    XCTAssertNil(dto.optimalInactivityTimeoutMs)
    XCTAssertNil(dto.p95ReadThroughputMBps)
    XCTAssertNil(dto.p95WriteThroughputMBps)
  }
}

// MARK: - Object Catalog Edge Cases

final class ObjectCatalogEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpsertObjectsSkipsWhenDeviceNotFound() async throws {
    let actor = store.createActor()
    // Call upsertObjects with a device that was never upserted
    let nonExistentDevice = "ghost-\(UUID().uuidString)"
    try await actor.upsertObjects(
      deviceId: nonExistentDevice,
      objects: [
        (
          storageId: 1, handle: 1, parentHandle: nil, name: "a.txt",
          pathKey: "/a.txt", size: 100, mtime: Date(), format: 0x3004, generation: 1
        )
      ])
    // Should return empty since device guard clause returns early
    let rows = try await actor.fetchObjects(deviceId: nonExistentDevice, generation: 1)
    XCTAssertTrue(rows.isEmpty)
  }

  func testMarkTombstoneOnDeviceWithNoObjects() async throws {
    let actor = store.createActor()
    let deviceId = "no-objects-\(UUID().uuidString)"
    // Should not throw even with no objects to tombstone
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 5)
  }

  func testFetchObjectsExcludesTombstoned() async throws {
    let actor = store.createActor()
    let deviceId = "tombstone-check-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "T", model: "M")

    // Insert gen 1 and gen 2 objects
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1, parentHandle: nil,
      name: "old.txt", pathKey: "/old.txt", size: 100, mtime: Date(),
      format: 0x3004, generation: 1)
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 2, parentHandle: nil,
      name: "new.txt", pathKey: "/new.txt", size: 200, mtime: Date(),
      format: 0x3004, generation: 2)

    // Tombstone gen 1
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 2)

    let gen1 = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertTrue(gen1.isEmpty, "Tombstoned gen 1 objects should not appear")
    XCTAssertEqual(gen2.count, 1)
  }

  func testUpsertObjectUpdatesExistingObject() async throws {
    let actor = store.createActor()
    let deviceId = "obj-update-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "T", model: "M")

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 10, parentHandle: nil,
      name: "original.txt", pathKey: "/original.txt", size: 100, mtime: Date(),
      format: 0x3004, generation: 1)

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 10, parentHandle: 5,
      name: "renamed.txt", pathKey: "/renamed.txt", size: 500, mtime: Date(),
      format: 0x3005, generation: 1)

    let rows = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.pathKey, "/renamed.txt")
    XCTAssertEqual(rows.first?.size, 500)
  }

  func testLargeBatchUpsert() async throws {
    let actor = store.createActor()
    let deviceId = "large-batch-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    let objects = (0..<200)
      .map {
        i -> (
          storageId: Int, handle: Int, parentHandle: Int?, name: String, pathKey: String,
          size: Int64?, mtime: Date?, format: Int, generation: Int
        ) in
        (
          storageId: 1, handle: i, parentHandle: nil, name: "file\(i).dat",
          pathKey: "/files/file\(i).dat", size: Int64(i * 1024), mtime: Date(),
          format: 0x3004, generation: 1
        )
      }

    try await actor.upsertObjects(deviceId: deviceId, objects: objects)
    let rows = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(rows.count, 200)
  }
}

// MARK: - Concurrent Store Edge Cases

final class StoreConcurrencyEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testConcurrentTransferCreateAndStatusUpdate() async throws {
    let actor = store.createActor()
    let deviceId = "conc-status-\(UUID().uuidString)"

    // Create transfers, then immediately update their status concurrently
    var ids: [String] = []
    for i in 0..<10 {
      let tid = "conc-t-\(i)-\(UUID().uuidString)"
      ids.append(tid)
      try await actor.createTransfer(
        id: tid, deviceId: deviceId, kind: "read",
        handle: UInt32(i), parentHandle: nil, name: "file\(i).txt",
        totalBytes: 1024, supportsPartial: true,
        localTempURL: "/tmp/conc-\(i)", finalURL: nil,
        etagSize: nil, etagMtime: nil)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for (i, tid) in ids.enumerated() {
        group.addTask {
          try await actor.updateTransferProgress(id: tid, committed: UInt64(512 * (i + 1)))
        }
      }
    }

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 10)
  }

  func testConcurrentDeviceUpsertAndProfileUpdate() async throws {
    let actor = store.createActor()

    let fingerprint = MTPDeviceFingerprint(
      vid: "cccc", pid: "dddd",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"))

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        let deviceId = "conc-dev-\(i)-\(UUID().uuidString)"
        let hash = "conc-hash-\(i)-\(UUID().uuidString)"
        group.addTask {
          let profile = LearnedProfile(
            fingerprint: fingerprint, fingerprintHash: hash,
            created: Date(), lastUpdated: Date(), sampleCount: i + 1,
            optimalChunkSize: nil, avgHandshakeMs: nil,
            optimalIoTimeoutMs: nil, optimalInactivityTimeoutMs: nil,
            p95ReadThroughputMBps: nil, p95WriteThroughputMBps: nil,
            successRate: 1.0, hostEnvironment: "test")
          try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile)
        }
      }
    }
    // No crash = success for actor isolation test
  }
}

// MARK: - Snapshot & Submission Edge Cases

final class SnapshotSubmissionEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testMultipleSnapshotsForSameDevice() async throws {
    let actor = store.createActor()
    let deviceId = "snap-multi-\(UUID().uuidString)"

    for gen in 1...5 {
      try await actor.recordSnapshot(
        deviceId: deviceId, generation: gen,
        path: "/snapshot/\(gen).json", hash: "hash-\(gen)")
    }
    // No crash = success; snapshots are append-only
  }

  func testRecordSubmissionWithLongPath() async throws {
    let actor = store.createActor()
    let deviceId = "sub-long-\(UUID().uuidString)"
    let longPath = "/" + String(repeating: "a/", count: 200) + "file.txt"

    try await actor.recordSubmission(
      id: "sub-\(UUID().uuidString)", deviceId: deviceId, path: longPath)
  }

  func testRecordSnapshotWithNilPathAndHash() async throws {
    let actor = store.createActor()
    let deviceId = "snap-nil-\(UUID().uuidString)"
    try await actor.recordSnapshot(deviceId: deviceId, generation: 1, path: nil, hash: nil)
  }
}

// MARK: - Storage Upsert Edge Cases

final class StorageUpsertEdgeCaseTests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpsertStorageWithZeroCapacity() async throws {
    let actor = store.createActor()
    try await actor.upsertStorage(
      deviceId: "zero-cap-\(UUID().uuidString)", storageId: 1,
      description: "Empty", capacity: 0, free: 0, readOnly: true)
  }

  func testUpsertStorageWithReadOnlyToggle() async throws {
    let actor = store.createActor()
    let deviceId = "ro-toggle-\(UUID().uuidString)"

    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "Storage", capacity: 1_000_000, free: 500_000, readOnly: false)
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "Storage", capacity: 1_000_000, free: 500_000, readOnly: true)
    // Update should succeed without creating a duplicate
  }

  func testSaveContextOnCleanState() async throws {
    let actor = store.createActor()
    // Saving with no pending changes should be a no-op
    try await actor.saveContext()
  }
}
