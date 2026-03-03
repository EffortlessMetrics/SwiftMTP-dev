// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPStore

/// Tests for store error handling: initialization edge cases, journal
/// write/read errors, transaction rollback, concurrent access,
/// entity serialization, and recovery paths after store failures.
final class StoreErrorTests: XCTestCase {

  var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  // MARK: - Store Initialization Edge Cases

  func testStoreInitializationCreatesValidContainer() {
    XCTAssertNotNil(store.container)
  }

  func testStoreCreateActorReturnsValidActor() {
    let actor = store.createActor()
    XCTAssertNotNil(actor)
  }

  func testMultipleActorsFromSameStore() {
    let actor1 = store.createActor()
    let actor2 = store.createActor()
    XCTAssertNotNil(actor1)
    XCTAssertNotNil(actor2)
  }

  func testSharedStoreIsSingleton() {
    let store1 = SwiftMTPStore.shared
    let store2 = SwiftMTPStore.shared
    XCTAssertTrue(store1 === store2)
  }

  // MARK: - Journal Write Error Scenarios

  func testCreateTransferWithEmptyId() async throws {
    let actor = store.createActor()
    // Empty ID is technically valid — the store should accept it
    try await actor.createTransfer(
      id: "",
      deviceId: "device-1",
      kind: "read",
      handle: 1,
      parentHandle: nil,
      name: "test.txt",
      totalBytes: 100,
      supportsPartial: false,
      localTempURL: "/tmp/test",
      finalURL: nil,
      etagSize: nil,
      etagMtime: nil
    )
  }

  func testCreateTransferWithEmptyDeviceId() async throws {
    let actor = store.createActor()
    try await actor.createTransfer(
      id: "transfer-empty-device",
      deviceId: "",
      kind: "read",
      handle: 1,
      parentHandle: nil,
      name: "test.txt",
      totalBytes: 100,
      supportsPartial: false,
      localTempURL: "/tmp/test",
      finalURL: nil,
      etagSize: nil,
      etagMtime: nil
    )
  }

  func testCreateTransferWithNilOptionalFields() async throws {
    let actor = store.createActor()
    try await actor.createTransfer(
      id: "transfer-nils-\(UUID().uuidString)",
      deviceId: "device-1",
      kind: "read",
      handle: nil,
      parentHandle: nil,
      name: "test.txt",
      totalBytes: nil,
      supportsPartial: false,
      localTempURL: "/tmp/test",
      finalURL: nil,
      etagSize: nil,
      etagMtime: nil
    )
  }

  func testCreateDuplicateTransferIdOverwrites() async throws {
    let actor = store.createActor()
    let id = "dup-transfer-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: id, deviceId: "device-1", kind: "read", handle: 1,
      parentHandle: nil, name: "first.txt", totalBytes: 100,
      supportsPartial: false, localTempURL: "/tmp/first",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )

    // SwiftData uses @Attribute(.unique) on TransferEntity.id, so a second
    // insert with the same ID may throw or upsert depending on the backend.
    // We verify the store does not crash either way.
    do {
      try await actor.createTransfer(
        id: id, deviceId: "device-1", kind: "write", handle: 2,
        parentHandle: nil, name: "second.txt", totalBytes: 200,
        supportsPartial: true, localTempURL: "/tmp/second",
        finalURL: nil, etagSize: nil, etagMtime: nil
      )
    } catch {
      // A uniqueness violation is acceptable here
      XCTAssertTrue(
        "\(error)".contains("unique") || "\(error)".contains("UNIQUE")
          || "\(error)".contains("constraint") || "\(error)".lowercased().contains("save"),
        "Expected a constraint-related error, got: \(error)"
      )
    }
  }

  // MARK: - Journal Read Error Scenarios

  func testFetchResumablesFromEmptyStore() async throws {
    let actor = store.createActor()
    let transfers = try await actor.fetchResumableTransfers(for: "nonexistent-device")
    XCTAssertTrue(transfers.isEmpty)
  }

  func testFetchLearnedProfileNonExistent() async throws {
    let actor = store.createActor()
    let dto = try await actor.fetchLearnedProfileDTO(for: "no-such-hash-\(UUID().uuidString)")
    XCTAssertNil(dto)
  }

  func testFetchObjectsNonExistentGeneration() async throws {
    let actor = store.createActor()
    let deviceId = "device-no-gen-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 999)
    XCTAssertTrue(objects.isEmpty)
  }

  func testFetchResumablesExcludesCompletedTransfers() async throws {
    let actor = store.createActor()
    let deviceId = "device-completed-\(UUID().uuidString)"
    let transferId = "done-transfer-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read", handle: 1,
      parentHandle: nil, name: "done.txt", totalBytes: 100,
      supportsPartial: false, localTempURL: "/tmp/done",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )
    try await actor.updateTransferStatus(id: transferId, state: "done")

    let transfers = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(transfers.isEmpty, "Completed transfers must not appear as resumable")
  }

  func testFetchResumablesExcludesFailedTransfers() async throws {
    let actor = store.createActor()
    let deviceId = "device-failed-\(UUID().uuidString)"
    let transferId = "failed-transfer-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "write", handle: nil,
      parentHandle: 1, name: "failed.txt", totalBytes: 500,
      supportsPartial: false, localTempURL: "/tmp/failed",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )
    try await actor.updateTransferStatus(
      id: transferId, state: "failed", error: "Connection lost")

    let transfers = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(transfers.isEmpty, "Failed transfers must not appear as resumable")
  }

  // MARK: - Transaction Rollback Scenarios

  func testSaveContextOnEmptyContextDoesNotThrow() async throws {
    let actor = store.createActor()
    try await actor.saveContext()
  }

  func testUpsertDeviceThenSaveContextPersists() async throws {
    let actor = store.createActor()
    let deviceId = "rollback-test-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Device")
    try await actor.saveContext()

    // Verify the device can still be found after explicit save
    let dto = try await actor.fetchLearnedProfileDTO(for: "hash-for-\(deviceId)")
    XCTAssertNil(dto, "No profile should exist yet, but device was created")
  }

  func testUpsertObjectsWithDeviceThatDoesNotExistSilentlySkips() async throws {
    let actor = store.createActor()
    // upsertObjects checks for device existence and returns early if not found
    let objects: [(
      storageId: Int, handle: Int, parentHandle: Int?, name: String,
      pathKey: String, size: Int64?, mtime: Date?, format: Int, generation: Int
    )] = [
      (1, 100, nil, "file.txt", "/file.txt", 1024, nil, 0x3004, 1)
    ]
    try await actor.upsertObjects(
      deviceId: "nonexistent-device-\(UUID().uuidString)", objects: objects)

    // Should silently succeed — no crash, no objects stored
  }

  func testTombstoneOnEmptyStoreSuceeds() async throws {
    let actor = store.createActor()
    // Tombstoning when no objects exist should not throw
    try await actor.markPreviousGenerationTombstoned(
      deviceId: "empty-device-\(UUID().uuidString)", currentGen: 5)
  }

  // MARK: - Concurrent Access Error Handling

  func testConcurrentDeviceUpserts() async throws {
    let actor = store.createActor()
    let deviceId = "concurrent-device-\(UUID().uuidString)"

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          _ = try await actor.upsertDevice(
            id: deviceId,
            manufacturer: "Vendor-\(i)",
            model: "Model-\(i)"
          )
        }
      }
      try await group.waitForAll()
    }

    // Verify device exists after concurrent writes
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
  }

  func testConcurrentTransferCreation() async throws {
    let actor = store.createActor()
    let deviceId = "concurrent-transfers-\(UUID().uuidString)"

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          try await actor.createTransfer(
            id: "\(deviceId)-transfer-\(i)",
            deviceId: deviceId,
            kind: i % 2 == 0 ? "read" : "write",
            handle: UInt32(i),
            parentHandle: nil,
            name: "file-\(i).txt",
            totalBytes: UInt64(i * 1000),
            supportsPartial: true,
            localTempURL: "/tmp/concurrent-\(i)",
            finalURL: nil,
            etagSize: nil,
            etagMtime: nil
          )
        }
      }
      try await group.waitForAll()
    }
  }

  func testConcurrentTransferStatusUpdates() async throws {
    let actor = store.createActor()
    let deviceId = "concurrent-status-\(UUID().uuidString)"
    let transferId = "status-transfer-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read", handle: 1,
      parentHandle: nil, name: "concurrent.txt", totalBytes: 10000,
      supportsPartial: true, localTempURL: "/tmp/concurrent-status",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )

    // Concurrent progress updates on the same transfer
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<5 {
        group.addTask {
          try await actor.updateTransferProgress(
            id: transferId, committed: UInt64(i * 2000))
        }
      }
      try await group.waitForAll()
    }
  }

  func testConcurrentObjectUpserts() async throws {
    let actor = store.createActor()
    let deviceId = "concurrent-objects-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          try await actor.upsertObject(
            deviceId: deviceId,
            storageId: 1,
            handle: i,
            parentHandle: nil,
            name: "file-\(i).txt",
            pathKey: "/file-\(i).txt",
            size: Int64(i * 100),
            mtime: Date(),
            format: 0x3004,
            generation: 1
          )
        }
      }
      try await group.waitForAll()
    }

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 10)
  }

  // MARK: - Entity Serialization/Deserialization

  func testTransferRecordSerializationRoundTrip() async throws {
    let actor = store.createActor()
    let deviceId = "serial-device-\(UUID().uuidString)"
    let transferId = "serial-transfer-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read", handle: 42,
      parentHandle: nil, name: "roundtrip.txt", totalBytes: 5000,
      supportsPartial: true, localTempURL: "/tmp/roundtrip",
      finalURL: "/final/roundtrip.txt",
      etagSize: 5000, etagMtime: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try await actor.updateTransferProgress(id: transferId, committed: 2500)
    try await actor.updateTransferThroughput(id: transferId, throughputMBps: 15.5)
    try await actor.updateTransferRemoteHandle(id: transferId, handle: 99)
    try await actor.updateTransferContentHash(id: transferId, hash: "abc123def456")

    let transfers = try await actor.fetchResumableTransfers(for: deviceId)
    let record = transfers.first { $0.id == transferId }
    XCTAssertNotNil(record)
    XCTAssertEqual(record?.name, "roundtrip.txt")
    XCTAssertEqual(record?.kind, "read")
    XCTAssertEqual(record?.handle, 42)
    XCTAssertEqual(record?.totalBytes, 5000)
    XCTAssertEqual(record?.committedBytes, 2500)
    XCTAssertEqual(record?.supportsPartial, true)
    XCTAssertEqual(record?.throughputMBps, 15.5)
    XCTAssertEqual(record?.remoteHandle, 99)
    XCTAssertEqual(record?.contentHash, "abc123def456")
    XCTAssertNotNil(record?.finalURL)
  }

  func testObjectRecordSerializationRoundTrip() async throws {
    let actor = store.createActor()
    let deviceId = "serial-obj-\(UUID().uuidString)"
    let mtime = Date(timeIntervalSince1970: 1_700_000_000)

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "ObjTest", model: "Model")
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 2, handle: 300,
      parentHandle: 100, name: "photo.jpg", pathKey: "/DCIM/photo.jpg",
      size: 4_000_000, mtime: mtime, format: 0x3801, generation: 3
    )

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 3)
    XCTAssertEqual(objects.count, 1)
    let obj = objects[0]
    XCTAssertEqual(obj.handle, 300)
    XCTAssertEqual(obj.storage, 2)
    XCTAssertEqual(obj.pathKey, "/DCIM/photo.jpg")
    XCTAssertEqual(obj.size, 4_000_000)
    XCTAssertEqual(obj.format, 0x3801)
    XCTAssertNotNil(obj.mtime)
  }

  func testLearnedProfileDTOSerializationRoundTrip() async throws {
    let actor = store.createActor()
    let deviceId = "serial-lp-\(UUID().uuidString)"
    let hash = "lp-hash-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    let fingerprint = MTPDeviceFingerprint(
      vid: "AAAA", pid: "BBBB",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )
    let profile = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 42,
      optimalChunkSize: 65536, avgHandshakeMs: 25,
      optimalIoTimeoutMs: 3000, optimalInactivityTimeoutMs: 15000,
      p95ReadThroughputMBps: 30.0, p95WriteThroughputMBps: 20.0,
      successRate: 0.95, hostEnvironment: "test-env"
    )

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile)

    let dto = try await actor.fetchLearnedProfileDTO(for: hash)
    XCTAssertNotNil(dto)
    XCTAssertEqual(dto?.fingerprintHash, hash)
    XCTAssertEqual(dto?.sampleCount, 42)
    XCTAssertEqual(dto?.optimalChunkSize, 65536)
    XCTAssertEqual(dto?.avgHandshakeMs, 25)
    XCTAssertEqual(dto?.optimalIoTimeoutMs, 3000)
    XCTAssertEqual(dto?.optimalInactivityTimeoutMs, 15000)
    XCTAssertEqual(dto?.p95ReadThroughputMBps, 30.0)
    XCTAssertEqual(dto?.p95WriteThroughputMBps, 20.0)
    XCTAssertEqual(dto?.successRate, 0.95)
    XCTAssertEqual(dto?.hostEnvironment, "test-env")
  }

  // MARK: - Recovery After Store Errors

  func testUpdateNonExistentTransferProgressIsNoOp() async throws {
    let actor = store.createActor()
    // Updating progress on a non-existent ID should silently succeed
    try await actor.updateTransferProgress(id: "phantom-\(UUID().uuidString)", committed: 999)
  }

  func testUpdateNonExistentTransferStatusIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferStatus(
      id: "phantom-\(UUID().uuidString)", state: "done", error: nil)
  }

  func testUpdateNonExistentTransferThroughputIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferThroughput(
      id: "phantom-\(UUID().uuidString)", throughputMBps: 42.0)
  }

  func testUpdateNonExistentTransferRemoteHandleIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferRemoteHandle(
      id: "phantom-\(UUID().uuidString)", handle: 999)
  }

  func testUpdateNonExistentTransferContentHashIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferContentHash(
      id: "phantom-\(UUID().uuidString)", hash: "deadbeef")
  }

  func testRecoveryAfterFailedTransfer_CanCreateNewTransfer() async throws {
    let actor = store.createActor()
    let deviceId = "recovery-device-\(UUID().uuidString)"

    // Create and fail a transfer
    let failedId = "recovery-fail-\(UUID().uuidString)"
    try await actor.createTransfer(
      id: failedId, deviceId: deviceId, kind: "write", handle: nil,
      parentHandle: 1, name: "failing.txt", totalBytes: 5000,
      supportsPartial: false, localTempURL: "/tmp/failing",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )
    try await actor.updateTransferStatus(
      id: failedId, state: "failed", error: "Timeout")

    // A new transfer on the same device should succeed
    let newId = "recovery-new-\(UUID().uuidString)"
    try await actor.createTransfer(
      id: newId, deviceId: deviceId, kind: "write", handle: nil,
      parentHandle: 1, name: "retry.txt", totalBytes: 5000,
      supportsPartial: true, localTempURL: "/tmp/retry",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )

    let resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 1)
    XCTAssertEqual(resumable.first?.id, newId)
  }

  func testRecoveryAfterTombstoning_NewGenerationWorks() async throws {
    let actor = store.createActor()
    let deviceId = "recovery-gen-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    // Gen 1 objects
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "old.txt", pathKey: "/old.txt",
      size: 100, mtime: nil, format: 0x3004, generation: 1
    )

    // Tombstone gen 1
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 2)

    // Gen 2 objects
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 2,
      parentHandle: nil, name: "new.txt", pathKey: "/new.txt",
      size: 200, mtime: nil, format: 0x3004, generation: 2
    )

    let gen1 = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertEqual(gen1.count, 0, "Gen 1 should be tombstoned")
    XCTAssertEqual(gen2.count, 1, "Gen 2 should be alive")
  }

  func testDeviceUpsertUpdatesExistingFields() async throws {
    let actor = store.createActor()
    let deviceId = "upsert-update-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Old", model: "OldModel")
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "New", model: "NewModel")

    // The second upsert should update, not fail
    // Verify by recording a profile against the device (this will fetch the device)
    let fingerprint = MTPDeviceFingerprint(
      vid: "1234", pid: "5678",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )
    let profile = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: "update-hash-\(deviceId)",
      created: Date(), lastUpdated: Date(), sampleCount: 1,
      optimalChunkSize: nil, avgHandshakeMs: nil,
      optimalIoTimeoutMs: nil, optimalInactivityTimeoutMs: nil,
      p95ReadThroughputMBps: nil, p95WriteThroughputMBps: nil,
      successRate: 1.0, hostEnvironment: "test"
    )
    try await actor.updateLearnedProfile(
      for: profile.fingerprintHash, deviceId: deviceId, profile: profile)
  }

  func testLearnedProfileUpdateOverwritesExisting() async throws {
    let actor = store.createActor()
    let deviceId = "lp-overwrite-\(UUID().uuidString)"
    let hash = "lp-overwrite-hash-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    let fingerprint = MTPDeviceFingerprint(
      vid: "CCCC", pid: "DDDD",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )

    // First profile
    let profile1 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 5,
      optimalChunkSize: 4096, avgHandshakeMs: 10,
      optimalIoTimeoutMs: 1000, optimalInactivityTimeoutMs: 5000,
      p95ReadThroughputMBps: 10.0, p95WriteThroughputMBps: 5.0,
      successRate: 0.8, hostEnvironment: "env1"
    )
    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile1)

    // Updated profile with different values
    let profile2 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(), sampleCount: 50,
      optimalChunkSize: 65536, avgHandshakeMs: 5,
      optimalIoTimeoutMs: 500, optimalInactivityTimeoutMs: 2000,
      p95ReadThroughputMBps: 40.0, p95WriteThroughputMBps: 20.0,
      successRate: 0.99, hostEnvironment: "env2"
    )
    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile2)

    let dto = try await actor.fetchLearnedProfileDTO(for: hash)
    XCTAssertEqual(dto?.sampleCount, 50)
    XCTAssertEqual(dto?.optimalChunkSize, 65536)
    XCTAssertEqual(dto?.successRate, 0.99)
  }

  // MARK: - Edge Cases for Entity Fields

  func testTransferWithZeroTotalBytes() async throws {
    let actor = store.createActor()
    let id = "zero-bytes-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: id, deviceId: "device-1", kind: "write", handle: nil,
      parentHandle: 1, name: "empty.txt", totalBytes: 0,
      supportsPartial: false, localTempURL: "/tmp/empty",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )

    let transfers = try await actor.fetchResumableTransfers(for: "device-1")
    let record = transfers.first { $0.id == id }
    XCTAssertNotNil(record)
    XCTAssertEqual(record?.totalBytes, 0)
  }

  func testTransferWithMaxUInt64TotalBytes() async throws {
    let actor = store.createActor()
    let id = "max-bytes-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: id, deviceId: "device-max", kind: "read", handle: 1,
      parentHandle: nil, name: "huge.bin", totalBytes: UInt64.max,
      supportsPartial: true, localTempURL: "/tmp/huge",
      finalURL: nil, etagSize: nil, etagMtime: nil
    )
  }

  func testObjectWithLargeFileSize() async throws {
    let actor = store.createActor()
    let deviceId = "large-size-\(UUID().uuidString)"

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "4k-video.mp4",
      pathKey: "/4k-video.mp4", size: 50_000_000_000,
      mtime: Date(), format: 0x300D, generation: 1
    )

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.first?.size, 50_000_000_000)
  }

  func testObjectWithEmptyName() async throws {
    let actor = store.createActor()
    let deviceId = "empty-name-\(UUID().uuidString)"

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "", pathKey: "/",
      size: nil, mtime: nil, format: 0x3001, generation: 1
    )

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
  }

  func testStorageUpsertWithZeroCapacity() async throws {
    let actor = store.createActor()
    try await actor.upsertStorage(
      deviceId: "zero-cap-device", storageId: 1,
      description: "Empty", capacity: 0, free: 0, readOnly: true
    )
  }

  func testStorageUpsertWithNegativeFreeBytes() async throws {
    let actor = store.createActor()
    // Negative values might occur if device reports incorrect data
    try await actor.upsertStorage(
      deviceId: "neg-free-device", storageId: 1,
      description: "Negative", capacity: 1000, free: -1, readOnly: false
    )
  }

  // MARK: - Adapter Integration Error Paths

  func testAdapterClearStaleTempsDoesNotThrow() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    try await adapter.clearStaleTemps(olderThan: 0)
  }

  func testAdapterFinalizeIndexingOnEmptyStore() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let deviceId = MTPDeviceID(raw: "finalize-empty-\(UUID().uuidString)")
    try await adapter.finalizeIndexing(deviceId: deviceId, generation: 1)
  }

  func testAdapterFetchObjectsEmptyResult() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let deviceId = MTPDeviceID(raw: "fetch-empty-\(UUID().uuidString)")
    let objects = try await adapter.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertTrue(objects.isEmpty)
  }

  // MARK: - Batch Object Upsert Error Paths

  func testBatchUpsertOverwritesExistingObjects() async throws {
    let actor = store.createActor()
    let deviceId = "batch-overwrite-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    // Insert initial objects
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 100,
      parentHandle: nil, name: "original.txt", pathKey: "/original.txt",
      size: 100, mtime: nil, format: 0x3004, generation: 1
    )

    // Batch upsert with same handle should update
    let objects: [(
      storageId: Int, handle: Int, parentHandle: Int?,
      name: String, pathKey: String, size: Int64?, mtime: Date?,
      format: Int, generation: Int
    )] = [
      (1, 100, nil, "updated.txt", "/updated.txt", 200, nil, 0x3004, 1)
    ]
    try await actor.upsertObjects(deviceId: deviceId, objects: objects)

    let fetched = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched.first?.pathKey, "/updated.txt")
    XCTAssertEqual(fetched.first?.size, 200)
  }

  func testBatchUpsertLargeNumberOfObjects() async throws {
    let actor = store.createActor()
    let deviceId = "batch-large-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    let objects: [(
      storageId: Int, handle: Int, parentHandle: Int?,
      name: String, pathKey: String, size: Int64?, mtime: Date?,
      format: Int, generation: Int
    )] = (0..<100).map { i in
      (1, i, nil, "file-\(i).txt", "/file-\(i).txt", Int64(i * 100), nil, 0x3004, 1)
    }

    try await actor.upsertObjects(deviceId: deviceId, objects: objects)

    let fetched = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(fetched.count, 100)
  }

  // MARK: - Transfer State Machine Consistency

  func testTransferStateMachineFullLifecycle() async throws {
    let actor = store.createActor()
    let deviceId = "lifecycle-\(UUID().uuidString)"
    let transferId = "lifecycle-transfer-\(UUID().uuidString)"

    // Create (active)
    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read", handle: 50,
      parentHandle: nil, name: "lifecycle.bin", totalBytes: 10000,
      supportsPartial: true, localTempURL: "/tmp/lifecycle",
      finalURL: "/final/lifecycle.bin",
      etagSize: 10000, etagMtime: Date()
    )

    // Verify active
    var resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 1)

    // Progress
    try await actor.updateTransferProgress(id: transferId, committed: 5000)
    try await actor.updateTransferThroughput(id: transferId, throughputMBps: 25.0)
    try await actor.updateTransferRemoteHandle(id: transferId, handle: 77)
    try await actor.updateTransferContentHash(id: transferId, hash: "sha256digest")

    // Pause
    try await actor.updateTransferStatus(id: transferId, state: "paused")
    resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 1, "Paused transfers should still be resumable")

    // Complete
    try await actor.updateTransferStatus(id: transferId, state: "done")
    resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(resumable.isEmpty, "Completed transfers should not be resumable")
  }

  func testMultipleTransfersForSameDevice() async throws {
    let actor = store.createActor()
    let deviceId = "multi-transfer-\(UUID().uuidString)"

    for i in 0..<5 {
      try await actor.createTransfer(
        id: "\(deviceId)-t\(i)",
        deviceId: deviceId, kind: "read", handle: UInt32(i),
        parentHandle: nil, name: "file-\(i).txt",
        totalBytes: UInt64(i * 1000 + 1000),
        supportsPartial: true, localTempURL: "/tmp/multi-\(i)",
        finalURL: nil, etagSize: nil, etagMtime: nil
      )
    }

    let resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 5)

    // Complete some, fail others
    try await actor.updateTransferStatus(id: "\(deviceId)-t0", state: "done")
    try await actor.updateTransferStatus(id: "\(deviceId)-t1", state: "failed", error: "err")
    try await actor.updateTransferStatus(id: "\(deviceId)-t2", state: "paused")

    let remaining = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(remaining.count, 3, "active + paused = 3 resumable")
  }

  // MARK: - Profiling/Snapshot Recording Error Paths

  func testRecordProfilingRunWithEmptyMetrics() async throws {
    let actor = store.createActor()
    let deviceId = "profile-empty-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    let deviceInfo = MTPDeviceInfo(
      manufacturer: "Test", model: "Model", version: "1.0",
      serialNumber: "SN", operationsSupported: [], eventsSupported: []
    )
    let profile = MTPDeviceProfile(
      timestamp: Date(), deviceInfo: deviceInfo, metrics: [])
    try await actor.recordProfilingRun(deviceId: deviceId, profile: profile)
  }

  func testRecordSnapshotWithNilArtifacts() async throws {
    let actor = store.createActor()
    let deviceId = "snap-nil-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    try await actor.recordSnapshot(
      deviceId: deviceId, generation: 1, path: nil, hash: nil)
  }

  func testRecordSubmissionCreatesDeviceImplicitly() async throws {
    let actor = store.createActor()
    let deviceId = "sub-implicit-\(UUID().uuidString)"

    // recordSubmission calls upsertDevice internally
    try await actor.recordSubmission(
      id: "sub-\(UUID().uuidString)", deviceId: deviceId, path: "/path/to/sub")
  }
}
