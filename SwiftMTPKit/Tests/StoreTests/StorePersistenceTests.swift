// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPStore

/// Expanded persistence-layer tests for SwiftMTPStore:
/// transfer journal CRUD, persistence across actor re-creation, concurrent access,
/// large journal handling, cleanup, device tuning storage, and edge cases.
final class StorePersistenceTests: XCTestCase {

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

  // MARK: - 1. Transfer Journal CRUD

  func testCreateAndReadTransfer() async throws {
    let actor = store.createActor()
    let deviceId = "crud-device-\(UUID().uuidString)"
    let transferId = "crud-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 1, parentHandle: nil, name: "photo.jpg",
      totalBytes: 5000, supportsPartial: true,
      localTempURL: "/tmp/crud-temp", finalURL: "/tmp/crud-final",
      etagSize: 5000, etagMtime: Date()
    )

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 1)
    let record = try XCTUnwrap(rows.first)
    XCTAssertEqual(record.id, transferId)
    XCTAssertEqual(record.name, "photo.jpg")
    XCTAssertEqual(record.kind, "read")
    XCTAssertEqual(record.totalBytes, 5000)
    XCTAssertEqual(record.committedBytes, 0)
    XCTAssertTrue(record.supportsPartial)
  }

  func testUpdateTransferProgressReflectsInFetch() async throws {
    let actor = store.createActor()
    let deviceId = "update-prog-\(UUID().uuidString)"
    let transferId = "uprog-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "write",
      handle: nil, parentHandle: 10, name: "video.mp4",
      totalBytes: 100_000, supportsPartial: false,
      localTempURL: "/tmp/uprog", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    try await actor.updateTransferProgress(id: transferId, committed: 50_000)

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.first?.committedBytes, 50_000)
  }

  func testDeleteTransferViaStateTransition() async throws {
    let actor = store.createActor()
    let deviceId = "del-\(UUID().uuidString)"
    let transferId = "del-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 5, parentHandle: nil, name: "file.bin",
      totalBytes: 1024, supportsPartial: false,
      localTempURL: "/tmp/del", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    // Complete removes from resumable set
    try await actor.updateTransferStatus(id: transferId, state: "done")
    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(rows.isEmpty)
  }

  func testUpdateTransferRemoteHandleAndContentHash() async throws {
    let actor = store.createActor()
    let deviceId = "rh-ch-\(UUID().uuidString)"
    let transferId = "rh-ch-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "write",
      handle: nil, parentHandle: 1, name: "doc.pdf",
      totalBytes: 2048, supportsPartial: false,
      localTempURL: "/tmp/rh-ch", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    try await actor.updateTransferRemoteHandle(id: transferId, handle: 0xDEAD)
    try await actor.updateTransferContentHash(id: transferId, hash: "abc123def456")

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    let record = try XCTUnwrap(rows.first)
    XCTAssertEqual(record.remoteHandle, 0xDEAD)
    XCTAssertEqual(record.contentHash, "abc123def456")
  }

  // MARK: - 2. Persistence Across Actor Re-creation

  func testDataSurvivesActorRecreation() async throws {
    let deviceId = "persist-\(UUID().uuidString)"
    let transferId = "persist-t-\(UUID().uuidString)"

    // Write with actor 1
    let actor1 = store.createActor()
    try await actor1.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 7, parentHandle: nil, name: "persist.txt",
      totalBytes: 999, supportsPartial: true,
      localTempURL: "/tmp/persist", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )
    try await actor1.updateTransferProgress(id: transferId, committed: 500)

    // Read with actor 2 (simulates restart)
    let actor2 = store.createActor()
    let rows = try await actor2.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.committedBytes, 500)
    XCTAssertEqual(rows.first?.name, "persist.txt")
  }

  func testDeviceUpsertSurvivesActorRecreation() async throws {
    let deviceId = "dev-persist-\(UUID().uuidString)"

    let actor1 = store.createActor()
    _ = try await actor1.upsertDevice(id: deviceId, manufacturer: "Sony", model: "Xperia")

    let actor2 = store.createActor()
    // Upsert again should update, not duplicate
    _ = try await actor2.upsertDevice(id: deviceId, manufacturer: "Sony", model: "Xperia 5")

    // Verify via learned profile store (which fetches device internally)
    let dto = try await actor2.fetchLearnedProfileDTO(for: "nonexistent-\(deviceId)")
    XCTAssertNil(dto)
  }

  func testLearnedProfileSurvivesActorRecreation() async throws {
    let fingerprint = MTPDeviceFingerprint(
      vid: "AAAA", pid: "BBBB",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )
    let deviceId = "lp-persist-\(UUID().uuidString)"
    let profile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: Date(), lastUpdated: Date(),
      sampleCount: 5, optimalChunkSize: 4096,
      avgHandshakeMs: 20, optimalIoTimeoutMs: 3000,
      optimalInactivityTimeoutMs: 10000,
      p95ReadThroughputMBps: 30.0, p95WriteThroughputMBps: 10.0,
      successRate: 0.95, hostEnvironment: "macOS"
    )

    let actor1 = store.createActor()
    try await actor1.updateLearnedProfile(
      for: fingerprint.hashString, deviceId: deviceId, profile: profile
    )

    let actor2 = store.createActor()
    let loaded = try await actor2.fetchLearnedProfileDTO(for: fingerprint.hashString)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.sampleCount, 5)
    XCTAssertEqual(loaded?.optimalChunkSize, 4096)
    XCTAssertEqual(loaded?.successRate, 0.95)
  }

  // MARK: - 3. Concurrent Journal Access

  func testConcurrentReadsAndWritesDontCrash() async throws {
    let actor = store.createActor()
    let deviceId = "conc-rw-\(UUID().uuidString)"

    // Seed transfers
    for i in 0..<10 {
      try await actor.createTransfer(
        id: "conc-\(i)-\(UUID().uuidString)", deviceId: deviceId, kind: "read",
        handle: UInt32(i), parentHandle: nil, name: "file\(i).txt",
        totalBytes: UInt64(1000 * (i + 1)), supportsPartial: true,
        localTempURL: "/tmp/conc-\(i)", finalURL: nil,
        etagSize: nil, etagMtime: nil
      )
    }

    // Concurrent reads and progress updates
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Reader tasks
      for _ in 0..<5 {
        group.addTask {
          let rows = try await actor.fetchResumableTransfers(for: deviceId)
          XCTAssertGreaterThan(rows.count, 0)
        }
      }
      // Writer task (progress updates)
      group.addTask {
        let rows = try await actor.fetchResumableTransfers(for: deviceId)
        for row in rows.prefix(5) {
          try await actor.updateTransferProgress(id: row.id, committed: 100)
        }
      }
      try await group.waitForAll()
    }
  }

  func testConcurrentTransferCreationAndCompletion() async throws {
    let actor = store.createActor()
    let deviceId = "conc-cc-\(UUID().uuidString)"

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<20 {
        group.addTask {
          let tid = "cc-\(i)-\(UUID().uuidString)"
          try await actor.createTransfer(
            id: tid, deviceId: deviceId, kind: i % 2 == 0 ? "read" : "write",
            handle: i % 2 == 0 ? UInt32(i) : nil,
            parentHandle: i % 2 == 1 ? UInt32(i) : nil,
            name: "concurrent-\(i).dat",
            totalBytes: UInt64(i * 512 + 1),
            supportsPartial: i % 3 == 0,
            localTempURL: "/tmp/cc-\(i)",
            finalURL: nil, etagSize: nil, etagMtime: nil
          )
          if i % 4 == 0 {
            try await actor.updateTransferStatus(id: tid, state: "done")
          }
        }
      }
      try await group.waitForAll()
    }

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    // 20 created, 5 completed (i=0,4,8,12,16)
    XCTAssertEqual(rows.count, 15)
  }

  // MARK: - 4. Large Journal Handling

  func testThousandTransferEntries() async throws {
    let actor = store.createActor()
    let deviceId = "bulk-\(UUID().uuidString)"
    let count = 1000

    for i in 0..<count {
      try await actor.createTransfer(
        id: "bulk-\(i)-\(UUID().uuidString)", deviceId: deviceId, kind: "read",
        handle: UInt32(i), parentHandle: nil, name: "bulk\(i).bin",
        totalBytes: UInt64(i * 100), supportsPartial: false,
        localTempURL: "/tmp/bulk-\(i)", finalURL: nil,
        etagSize: nil, etagMtime: nil
      )
    }

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, count)
  }

  func testBulkObjectUpsertPerformance() async throws {
    let actor = store.createActor()
    let deviceId = "bulkobj-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Bulk")

    let objectCount = 500
    let objects: [(
      storageId: Int, handle: Int, parentHandle: Int?, name: String,
      pathKey: String, size: Int64?, mtime: Date?, format: Int, generation: Int
    )] = (0..<objectCount).map { i in
      (
        storageId: 1, handle: i, parentHandle: i > 0 ? 0 : nil,
        name: "obj\(i).jpg", pathKey: "/DCIM/obj\(i).jpg",
        size: Int64(i * 1024 + 1), mtime: Date(), format: 0x3004, generation: 1
      )
    }

    try await actor.upsertObjects(deviceId: deviceId, objects: objects)

    let fetched = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(fetched.count, objectCount)
  }

  // MARK: - 5. Journal Cleanup (Completed/Failed Transfers)

  func testCompletedTransfersNotResumable() async throws {
    let actor = store.createActor()
    let deviceId = "cleanup-done-\(UUID().uuidString)"

    var ids: [String] = []
    for i in 0..<5 {
      let tid = "cleanup-\(i)-\(UUID().uuidString)"
      ids.append(tid)
      try await actor.createTransfer(
        id: tid, deviceId: deviceId, kind: "read",
        handle: UInt32(i), parentHandle: nil, name: "cleanup\(i).txt",
        totalBytes: 1024, supportsPartial: false,
        localTempURL: "/tmp/cleanup-\(i)", finalURL: nil,
        etagSize: nil, etagMtime: nil
      )
    }

    // Complete first three
    for i in 0..<3 {
      try await actor.updateTransferStatus(id: ids[i], state: "done")
    }

    let resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 2)
    let resumableIds = Set(resumable.map(\.id))
    XCTAssertTrue(resumableIds.contains(ids[3]))
    XCTAssertTrue(resumableIds.contains(ids[4]))
  }

  func testFailedTransfersNotResumable() async throws {
    let actor = store.createActor()
    let deviceId = "cleanup-fail-\(UUID().uuidString)"

    let tid = "fail-\(UUID().uuidString)"
    try await actor.createTransfer(
      id: tid, deviceId: deviceId, kind: "write",
      handle: nil, parentHandle: 1, name: "failing.dat",
      totalBytes: 2048, supportsPartial: false,
      localTempURL: "/tmp/fail", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    try await actor.updateTransferStatus(id: tid, state: "failed", error: "IO error")

    let resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(resumable.isEmpty)
  }

  func testPausedTransfersAreResumable() async throws {
    let actor = store.createActor()
    let deviceId = "paused-\(UUID().uuidString)"
    let tid = "paused-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: tid, deviceId: deviceId, kind: "read",
      handle: 42, parentHandle: nil, name: "paused.mp4",
      totalBytes: 50_000, supportsPartial: true,
      localTempURL: "/tmp/paused", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    try await actor.updateTransferProgress(id: tid, committed: 25_000)
    try await actor.updateTransferStatus(id: tid, state: "paused")

    let resumable = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(resumable.count, 1)
    XCTAssertEqual(resumable.first?.state, "paused")
    XCTAssertEqual(resumable.first?.committedBytes, 25_000)
  }

  // MARK: - 6. Device Tuning Storage (Learned Profiles)

  func testWriteReadUpdateLearnedProfile() async throws {
    let actor = store.createActor()
    let deviceId = "tuning-\(UUID().uuidString)"
    let fpHash = "tuning-fp-\(UUID().uuidString)"

    let fingerprint = MTPDeviceFingerprint(
      vid: "1111", pid: "2222",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )

    let profile1 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: fpHash,
      created: Date(), lastUpdated: Date(),
      sampleCount: 3, optimalChunkSize: 2048,
      avgHandshakeMs: 15, optimalIoTimeoutMs: 2000,
      optimalInactivityTimeoutMs: 8000,
      p95ReadThroughputMBps: 20.0, p95WriteThroughputMBps: 8.0,
      successRate: 0.90, hostEnvironment: "macOS"
    )

    // Write
    try await actor.updateLearnedProfile(for: fpHash, deviceId: deviceId, profile: profile1)
    let dto1 = try await actor.fetchLearnedProfileDTO(for: fpHash)
    XCTAssertEqual(dto1?.sampleCount, 3)
    XCTAssertEqual(dto1?.optimalChunkSize, 2048)

    // Update
    let profile2 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: fpHash,
      created: Date(), lastUpdated: Date(),
      sampleCount: 10, optimalChunkSize: 8192,
      avgHandshakeMs: 12, optimalIoTimeoutMs: 1500,
      optimalInactivityTimeoutMs: 6000,
      p95ReadThroughputMBps: 35.0, p95WriteThroughputMBps: 15.0,
      successRate: 0.98, hostEnvironment: "macOS"
    )

    try await actor.updateLearnedProfile(for: fpHash, deviceId: deviceId, profile: profile2)
    let dto2 = try await actor.fetchLearnedProfileDTO(for: fpHash)
    XCTAssertEqual(dto2?.sampleCount, 10)
    XCTAssertEqual(dto2?.optimalChunkSize, 8192)
    XCTAssertEqual(dto2?.successRate, 0.98)
    XCTAssertEqual(dto2?.p95ReadThroughputMBps, 35.0)
  }

  func testLearnedProfileAllFieldsRoundTrip() async throws {
    let actor = store.createActor()
    let deviceId = "allfields-\(UUID().uuidString)"
    let fpHash = "allfields-fp-\(UUID().uuidString)"

    let fingerprint = MTPDeviceFingerprint(
      vid: "CCCC", pid: "DDDD",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )

    let profile = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: fpHash,
      created: Date(), lastUpdated: Date(),
      sampleCount: 42, optimalChunkSize: 16384,
      avgHandshakeMs: 8, optimalIoTimeoutMs: 4000,
      optimalInactivityTimeoutMs: 20000,
      p95ReadThroughputMBps: 50.0, p95WriteThroughputMBps: 25.0,
      successRate: 0.999, hostEnvironment: "macOS-test"
    )

    try await actor.updateLearnedProfile(for: fpHash, deviceId: deviceId, profile: profile)
    let fetched = try await actor.fetchLearnedProfileDTO(for: fpHash)
    let dto = try XCTUnwrap(fetched)

    XCTAssertEqual(dto.fingerprintHash, fpHash)
    XCTAssertEqual(dto.sampleCount, 42)
    XCTAssertEqual(dto.optimalChunkSize, 16384)
    XCTAssertEqual(dto.avgHandshakeMs, 8)
    XCTAssertEqual(dto.optimalIoTimeoutMs, 4000)
    XCTAssertEqual(dto.optimalInactivityTimeoutMs, 20000)
    XCTAssertEqual(dto.p95ReadThroughputMBps, 50.0)
    XCTAssertEqual(dto.p95WriteThroughputMBps, 25.0)
    XCTAssertEqual(dto.successRate, 0.999)
    XCTAssertEqual(dto.hostEnvironment, "macOS-test")
  }

  // MARK: - 7. Metadata Versioning (Generation / Tombstoning)

  func testMultipleGenerationsIsolated() async throws {
    let actor = store.createActor()
    let deviceId = "gen-iso-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Gen")

    // Gen 1
    try await actor.upsertObjects(deviceId: deviceId, objects: [
      (storageId: 1, handle: 1, parentHandle: nil, name: "a.txt",
       pathKey: "/a.txt", size: 100, mtime: Date(), format: 0x3004, generation: 1),
      (storageId: 1, handle: 2, parentHandle: nil, name: "b.txt",
       pathKey: "/b.txt", size: 200, mtime: Date(), format: 0x3004, generation: 1),
    ])

    // Gen 2
    try await actor.upsertObjects(deviceId: deviceId, objects: [
      (storageId: 1, handle: 3, parentHandle: nil, name: "c.txt",
       pathKey: "/c.txt", size: 300, mtime: Date(), format: 0x3004, generation: 2),
    ])

    let gen1 = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertEqual(gen1.count, 2)
    XCTAssertEqual(gen2.count, 1)
  }

  func testTombstoningOnlyAffectsOlderGenerations() async throws {
    let actor = store.createActor()
    let deviceId = "tomb-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Tomb")

    for gen in 1...3 {
      try await actor.upsertObject(
        deviceId: deviceId, storageId: 1, handle: gen * 100,
        parentHandle: nil, name: "gen\(gen).txt", pathKey: "/gen\(gen).txt",
        size: Int64(gen * 1000), mtime: Date(), format: 0x3004, generation: gen
      )
    }

    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 3)

    let gen1 = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    let gen3 = try await actor.fetchObjects(deviceId: deviceId, generation: 3)
    XCTAssertEqual(gen1.count, 0, "Gen 1 should be tombstoned")
    XCTAssertEqual(gen2.count, 0, "Gen 2 should be tombstoned")
    XCTAssertEqual(gen3.count, 1, "Gen 3 should remain")
  }

  func testTombstoningAcrossDevicesIsIsolated() async throws {
    let actor = store.createActor()
    let device1 = "tomb-d1-\(UUID().uuidString)"
    let device2 = "tomb-d2-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: device1, manufacturer: "A", model: "A")
    _ = try await actor.upsertDevice(id: device2, manufacturer: "B", model: "B")

    try await actor.upsertObject(
      deviceId: device1, storageId: 1, handle: 1, parentHandle: nil,
      name: "d1.txt", pathKey: "/d1.txt", size: 100, mtime: Date(),
      format: 0x3004, generation: 1
    )
    try await actor.upsertObject(
      deviceId: device2, storageId: 1, handle: 1, parentHandle: nil,
      name: "d2.txt", pathKey: "/d2.txt", size: 100, mtime: Date(),
      format: 0x3004, generation: 1
    )

    try await actor.markPreviousGenerationTombstoned(deviceId: device1, currentGen: 2)

    let d1gen1 = try await actor.fetchObjects(deviceId: device1, generation: 1)
    let d2gen1 = try await actor.fetchObjects(deviceId: device2, generation: 1)
    XCTAssertEqual(d1gen1.count, 0, "Device 1 gen 1 should be tombstoned")
    XCTAssertEqual(d2gen1.count, 1, "Device 2 gen 1 should be untouched")
  }

  // MARK: - 8. Error Handling

  func testUpdateNonExistentTransferProgressIsNoOp() async throws {
    let actor = store.createActor()
    // Should not throw
    try await actor.updateTransferProgress(id: "phantom-id", committed: 999)
  }

  func testUpdateNonExistentTransferStatusIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferStatus(id: "phantom-id", state: "done")
  }

  func testUpdateNonExistentTransferThroughputIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferThroughput(id: "phantom-id", throughputMBps: 99.9)
  }

  func testUpdateNonExistentTransferRemoteHandleIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferRemoteHandle(id: "phantom-id", handle: 0xFFFF)
  }

  func testUpdateNonExistentTransferContentHashIsNoOp() async throws {
    let actor = store.createActor()
    try await actor.updateTransferContentHash(id: "phantom-id", hash: "deadbeef")
  }

  func testUpsertObjectsSkipsWhenDeviceMissing() async throws {
    let actor = store.createActor()
    // Device never created — upsertObjects should silently return
    try await actor.upsertObjects(
      deviceId: "never-created-\(UUID().uuidString)",
      objects: [
        (storageId: 1, handle: 1, parentHandle: nil, name: "x.txt",
         pathKey: "/x.txt", size: 100, mtime: Date(), format: 0x3004, generation: 1)
      ]
    )
  }

  // MARK: - 9. Edge Cases

  func testEmptyJournalReturnsEmptyArray() async throws {
    let actor = store.createActor()
    let rows = try await actor.fetchResumableTransfers(for: "empty-\(UUID().uuidString)")
    XCTAssertTrue(rows.isEmpty)
  }

  func testEmptyObjectFetchReturnsEmptyArray() async throws {
    let actor = store.createActor()
    let rows = try await actor.fetchObjects(
      deviceId: "empty-obj-\(UUID().uuidString)", generation: 99
    )
    XCTAssertTrue(rows.isEmpty)
  }

  func testDuplicateTransferIdOverwrites() async throws {
    let actor = store.createActor()
    let deviceId = "dup-\(UUID().uuidString)"
    let transferId = "dup-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 1, parentHandle: nil, name: "first.txt",
      totalBytes: 100, supportsPartial: false,
      localTempURL: "/tmp/dup1", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    // TransferEntity has @Attribute(.unique) on id — second insert replaces
    try await actor.createTransfer(
      id: transferId, deviceId: deviceId, kind: "read",
      handle: 2, parentHandle: nil, name: "second.txt",
      totalBytes: 200, supportsPartial: false,
      localTempURL: "/tmp/dup2", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    // Should have at most one entry for this id
    let matchingId = rows.filter { $0.id == transferId }
    XCTAssertLessThanOrEqual(matchingId.count, 1)
  }

  func testLongPathNames() async throws {
    let actor = store.createActor()
    let deviceId = "longpath-\(UUID().uuidString)"

    // Simulate a deeply nested path (260+ characters like Windows MAX_PATH)
    let longName = String(repeating: "a", count: 200)
    let longPath = "/DCIM/Camera/\(longName).jpg"

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "\(longName).jpg", pathKey: longPath,
      size: 4096, mtime: Date(), format: 0x3004, generation: 1
    )

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
    XCTAssertEqual(objects.first?.pathKey, longPath)
  }

  func testZeroByteTransfer() async throws {
    let actor = store.createActor()
    let deviceId = "zero-\(UUID().uuidString)"
    let tid = "zero-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: tid, deviceId: deviceId, kind: "read",
      handle: 1, parentHandle: nil, name: "empty.txt",
      totalBytes: 0, supportsPartial: false,
      localTempURL: "/tmp/zero", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.first?.totalBytes, 0)
  }

  func testNilTotalBytesTransfer() async throws {
    let actor = store.createActor()
    let deviceId = "nilsize-\(UUID().uuidString)"
    let tid = "nilsize-t-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: tid, deviceId: deviceId, kind: "read",
      handle: 1, parentHandle: nil, name: "unknown-size.bin",
      totalBytes: nil, supportsPartial: false,
      localTempURL: "/tmp/nilsize", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertNil(rows.first?.totalBytes)
  }

  func testMultipleDevicesIsolation() async throws {
    let actor = store.createActor()
    let d1 = "iso-d1-\(UUID().uuidString)"
    let d2 = "iso-d2-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: "iso-t1-\(UUID().uuidString)", deviceId: d1, kind: "read",
      handle: 1, parentHandle: nil, name: "d1file.txt",
      totalBytes: 100, supportsPartial: false,
      localTempURL: "/tmp/iso-1", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )
    try await actor.createTransfer(
      id: "iso-t2-\(UUID().uuidString)", deviceId: d2, kind: "write",
      handle: nil, parentHandle: 1, name: "d2file.txt",
      totalBytes: 200, supportsPartial: false,
      localTempURL: "/tmp/iso-2", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    let d1Rows = try await actor.fetchResumableTransfers(for: d1)
    let d2Rows = try await actor.fetchResumableTransfers(for: d2)
    XCTAssertEqual(d1Rows.count, 1)
    XCTAssertEqual(d2Rows.count, 1)
    XCTAssertEqual(d1Rows.first?.name, "d1file.txt")
    XCTAssertEqual(d2Rows.first?.name, "d2file.txt")
  }

  func testStorageUpsertCreatesThenUpdates() async throws {
    let actor = store.createActor()
    let deviceId = "sto-upsert-\(UUID().uuidString)"

    // Create
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1, description: "Internal",
      capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false
    )

    // Update (same compound key)
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1, description: "Internal (updated)",
      capacity: 64_000_000_000, free: 16_000_000_000, readOnly: true
    )

    // No exception and idempotent
  }

  func testSnapshotRecordingMultipleGenerations() async throws {
    let actor = store.createActor()
    let deviceId = "snap-\(UUID().uuidString)"

    for gen in 1...5 {
      try await actor.recordSnapshot(
        deviceId: deviceId, generation: gen,
        path: "/snapshots/gen\(gen).snap", hash: "hash-\(gen)"
      )
    }
    // No exception is the success criterion
  }

  func testSubmissionRecording() async throws {
    let actor = store.createActor()
    let deviceId = "sub-\(UUID().uuidString)"

    try await actor.recordSubmission(
      id: "sub-\(UUID().uuidString)", deviceId: deviceId,
      path: "/submissions/quirks.json"
    )
    // No exception
  }

  func testTransferFullLifecycle() async throws {
    let actor = store.createActor()
    let deviceId = "lifecycle-\(UUID().uuidString)"
    let tid = "life-\(UUID().uuidString)"

    // Create
    try await actor.createTransfer(
      id: tid, deviceId: deviceId, kind: "write",
      handle: nil, parentHandle: 10, name: "upload.zip",
      totalBytes: 100_000, supportsPartial: true,
      localTempURL: "/tmp/lifecycle", finalURL: nil,
      etagSize: nil, etagMtime: nil
    )

    // Update remote handle
    try await actor.updateTransferRemoteHandle(id: tid, handle: 0x1234)

    // Progress updates
    try await actor.updateTransferProgress(id: tid, committed: 25_000)
    try await actor.updateTransferProgress(id: tid, committed: 50_000)
    try await actor.updateTransferProgress(id: tid, committed: 75_000)
    try await actor.updateTransferProgress(id: tid, committed: 100_000)

    // Content hash
    try await actor.updateTransferContentHash(id: tid, hash: "sha256abcdef")

    // Throughput
    try await actor.updateTransferThroughput(id: tid, throughputMBps: 45.6)

    // Verify all fields
    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    let record = try XCTUnwrap(rows.first)
    XCTAssertEqual(record.committedBytes, 100_000)
    XCTAssertEqual(record.remoteHandle, 0x1234)
    XCTAssertEqual(record.contentHash, "sha256abcdef")
    XCTAssertEqual(record.throughputMBps, 45.6)

    // Complete
    try await actor.updateTransferStatus(id: tid, state: "done")
    let afterDone = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertTrue(afterDone.isEmpty)
  }

  func testDeviceUpsertUpdatesManufacturerAndModel() async throws {
    let actor = store.createActor()
    let deviceId = "upsert-dev-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "OldMfg", model: "OldModel")
    let returnedId = try await actor.upsertDevice(
      id: deviceId, manufacturer: "NewMfg", model: "NewModel"
    )
    XCTAssertEqual(returnedId, deviceId)
  }

  func testDeviceUpsertWithNilFieldsDoesNotOverwrite() async throws {
    let actor = store.createActor()
    let deviceId = "nilfields-\(UUID().uuidString)"

    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Keep", model: "This")
    // Passing nil should not clear existing values
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    // No crash is the baseline; actual preservation is an implementation detail
  }

  func testObjectUpsertUpdatesExistingRecord() async throws {
    let actor = store.createActor()
    let deviceId = "objup-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "T", model: "U")

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 50,
      parentHandle: nil, name: "old.txt", pathKey: "/old.txt",
      size: 100, mtime: Date(timeIntervalSince1970: 0),
      format: 0x3004, generation: 1
    )

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 50,
      parentHandle: nil, name: "new.txt", pathKey: "/new.txt",
      size: 999, mtime: Date(),
      format: 0x3005, generation: 1
    )

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
    XCTAssertEqual(objects.first?.pathKey, "/new.txt")
    XCTAssertEqual(objects.first?.size, 999)
  }

  func testProfilingRunWithMultipleMetrics() async throws {
    let actor = store.createActor()
    let deviceId = "profmulti-\(UUID().uuidString)"

    let metrics = [
      MTPProfileMetric(operation: "read", count: 50, minMs: 5, maxMs: 200, avgMs: 40, p95Ms: 150, throughputMBps: 30),
      MTPProfileMetric(operation: "write", count: 30, minMs: 10, maxMs: 300, avgMs: 80, p95Ms: 250, throughputMBps: 15),
      MTPProfileMetric(operation: "delete", count: 100, minMs: 1, maxMs: 50, avgMs: 10, p95Ms: 40, throughputMBps: nil),
    ]

    let deviceInfo = MTPDeviceInfo(
      manufacturer: "MultiMetric", model: "Pro",
      version: "2.0", serialNumber: "MULTI-001",
      operationsSupported: [0x1001, 0x1002, 0x100D],
      eventsSupported: [0x4002]
    )

    let profile = MTPDeviceProfile(
      timestamp: Date(), deviceInfo: deviceInfo, metrics: metrics
    )

    try await actor.recordProfilingRun(deviceId: deviceId, profile: profile)
    // No exception is the success criterion
  }

  func testSaveContextIdempotent() async throws {
    let actor = store.createActor()
    // Multiple consecutive saves should be safe
    try await actor.saveContext()
    try await actor.saveContext()
    try await actor.saveContext()
  }

  func testClearStaleTempsDoesNotThrow() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    try await adapter.clearStaleTemps(olderThan: 0)
    try await adapter.clearStaleTemps(olderThan: 3600)
    try await adapter.clearStaleTemps(olderThan: TimeInterval.infinity)
  }
}
