// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore
import SwiftMTPTestKit

// MARK: - In-Memory Journal for Testing

/// Minimal in-memory TransferJournal used only in reconcile tests.
private actor InMemoryJournal: TransferJournal {
  private struct Entry {
    var record: TransferRecord
  }

  private var entries: [String: Entry] = [:]

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    let id = UUID().uuidString
    let rec = TransferRecord(
      id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil, name: name,
      totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: finalURL, state: "active", updatedAt: Date()
    )
    entries[id] = Entry(record: rec)
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    let id = UUID().uuidString
    let rec = TransferRecord(
      id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent, name: name,
      totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: sourceURL, state: "active", updatedAt: Date()
    )
    entries[id] = Entry(record: rec)
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {
    guard let e = entries[id] else { return }
    let r = e.record
    entries[id] = Entry(
      record: TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: committed, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: r.state,
        updatedAt: Date(), remoteHandle: r.remoteHandle, contentHash: r.contentHash
      ))
  }

  func fail(id: String, error: Error) async throws {
    guard let e = entries[id] else { return }
    let r = e.record
    entries[id] = Entry(
      record: TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: "failed",
        updatedAt: Date(), remoteHandle: r.remoteHandle, contentHash: r.contentHash
      ))
  }

  func complete(id: String) async throws {
    guard let e = entries[id] else { return }
    let r = e.record
    entries[id] = Entry(
      record: TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: "done",
        updatedAt: Date(), remoteHandle: r.remoteHandle, contentHash: r.contentHash
      ))
  }

  func recordRemoteHandle(id: String, handle: UInt32) async throws {
    guard let e = entries[id] else { return }
    let r = e.record
    entries[id] = Entry(
      record: TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: r.state,
        updatedAt: Date(), remoteHandle: handle, contentHash: r.contentHash
      ))
  }

  func addContentHash(id: String, hash: String) async throws {
    guard let e = entries[id] else { return }
    let r = e.record
    entries[id] = Entry(
      record: TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: r.state,
        updatedAt: Date(), remoteHandle: r.remoteHandle, contentHash: hash
      ))
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    entries.values.map(\.record)
      .filter {
        $0.deviceId == device && ($0.state == "active" || $0.state == "paused")
      }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {}

  func remoteHandle(for id: String) -> UInt32? {
    entries[id]?.record.remoteHandle
  }

  func contentHash(for id: String) -> String? {
    entries[id]?.record.contentHash
  }
}

// MARK: - StoreAdapter recordRemoteHandle Tests

final class TransferJournalReconcileTests: XCTestCase {

  var adapter: SwiftMTPStoreAdapter!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    adapter = SwiftMTPStoreAdapter(store: .shared)
  }

  override func tearDown() {
    adapter = nil
    super.tearDown()
  }

  // MARK: - recordRemoteHandle Tests

  func testRecordRemoteHandlePersists() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-rh")
    let tempURL = URL(fileURLWithPath: "/tmp/test_write_rh")

    let transferId = try await adapter.beginWrite(
      device: deviceId, parent: 100, name: "file.jpg", size: 4096,
      supportsPartial: false, tempURL: tempURL, sourceURL: nil
    )

    try await adapter.recordRemoteHandle(id: transferId, handle: 0xABCD)

    let resumables = try await adapter.loadResumables(for: deviceId)
    let record = try XCTUnwrap(resumables.first(where: { $0.id == transferId }))
    XCTAssertEqual(record.remoteHandle, 0xABCD)
  }

  func testRecordRemoteHandleCanBeUpdated() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-rh2")
    let tempURL = URL(fileURLWithPath: "/tmp/test_write_rh2")

    let transferId = try await adapter.beginWrite(
      device: deviceId, parent: 200, name: "video.mp4", size: 1024 * 1024,
      supportsPartial: false, tempURL: tempURL, sourceURL: nil
    )

    try await adapter.recordRemoteHandle(id: transferId, handle: 0x1111)
    try await adapter.recordRemoteHandle(id: transferId, handle: 0x2222)

    let resumables = try await adapter.loadResumables(for: deviceId)
    let record = try XCTUnwrap(resumables.first(where: { $0.id == transferId }))
    XCTAssertEqual(record.remoteHandle, 0x2222)
  }

  func testAddContentHashPersists() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-ch")
    let tempURL = URL(fileURLWithPath: "/tmp/test_write_ch")

    let transferId = try await adapter.beginWrite(
      device: deviceId, parent: 300, name: "doc.pdf", size: 2048,
      supportsPartial: false, tempURL: tempURL, sourceURL: nil
    )

    let hash = "a3f1b2c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567"
    try await adapter.addContentHash(id: transferId, hash: hash)

    let resumables = try await adapter.loadResumables(for: deviceId)
    let record = try XCTUnwrap(resumables.first(where: { $0.id == transferId }))
    XCTAssertEqual(record.contentHash, hash)
  }

  func testRemoteHandleNilByDefault() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-rh-nil")
    let tempURL = URL(fileURLWithPath: "/tmp/test_write_rh_nil")

    let transferId = try await adapter.beginWrite(
      device: deviceId, parent: 400, name: "image.png", size: 512,
      supportsPartial: false, tempURL: tempURL, sourceURL: nil
    )

    let resumables = try await adapter.loadResumables(for: deviceId)
    let record = try XCTUnwrap(resumables.first(where: { $0.id == transferId }))
    XCTAssertNil(record.remoteHandle)
    XCTAssertNil(record.contentHash)
  }

  // MARK: - reconcilePartialWrites Tests

  func testReconcilePartialWritesDeletesPartialObject() async throws {
    // Use the emptyDevice config and get its actual deviceId.
    let config = VirtualDeviceConfig.emptyDevice
    let deviceId = config.deviceId
    let partialHandle: MTPObjectHandle = 42
    let expectedSize: UInt64 = 10_000

    // Build a virtual device that has a partial object (size < expected).
    let storage = config.storages[0].id
    let configWithObj = config.withObject(
      VirtualObjectConfig(
        handle: partialHandle,
        storage: storage,
        parent: nil,
        name: "upload.bin",
        data: Data(repeating: 0xAB, count: 100)  // 100 bytes < 10_000 expected
      )
    )
    let device = VirtualMTPDevice(config: configWithObj)

    // Build a journal with a write record pointing at the partial handle.
    let journal = InMemoryJournal()
    let tid = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "upload.bin", size: expectedSize,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/x"), sourceURL: nil
    )
    try await journal.recordRemoteHandle(id: tid, handle: partialHandle)

    await reconcilePartialWrites(journal: journal, device: device)

    // The partial object should have been deleted.
    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "delete" }))
  }

  func testReconcilePartialWritesSkipsCompleteObject() async throws {
    let config = VirtualDeviceConfig.emptyDevice
    let deviceId = config.deviceId
    let completeHandle: MTPObjectHandle = 99
    let expectedSize: UInt64 = 50

    // Build a virtual device with a complete object (size == expected).
    let storage = config.storages[0].id
    let configWithObj = config.withObject(
      VirtualObjectConfig(
        handle: completeHandle,
        storage: storage,
        parent: nil,
        name: "complete.txt",
        data: Data(repeating: 0x00, count: Int(expectedSize))  // exactly expectedSize bytes
      )
    )
    let device = VirtualMTPDevice(config: configWithObj)

    let journal = InMemoryJournal()
    let tid = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "complete.txt", size: expectedSize,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/y"), sourceURL: nil
    )
    try await journal.recordRemoteHandle(id: tid, handle: completeHandle)

    await reconcilePartialWrites(journal: journal, device: device)

    // No delete should have been called.
    let ops = await device.operations
    XCTAssertFalse(ops.contains(where: { $0.operation == "delete" }))
  }

  func testReconcilePartialWritesSkipsRecordsWithoutRemoteHandle() async throws {
    let config = VirtualDeviceConfig.emptyDevice
    let deviceId = config.deviceId

    let storage = config.storages[0].id
    let configWithObj = config.withObject(
      VirtualObjectConfig(
        handle: 77,
        storage: storage,
        parent: nil,
        name: "other.txt",
        data: Data("hello".utf8)
      )
    )
    let device = VirtualMTPDevice(config: configWithObj)

    let journal = InMemoryJournal()
    _ = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "pending.txt", size: 1000,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/z"), sourceURL: nil
    )
    // Do NOT call recordRemoteHandle.

    await reconcilePartialWrites(journal: journal, device: device)

    // No delete should be triggered because there is no remoteHandle.
    let ops = await device.operations
    XCTAssertFalse(ops.contains(where: { $0.operation == "delete" }))
  }

  // MARK: - InMemoryJournal recordRemoteHandle Tests

  func testInMemoryJournalRecordRemoteHandle() async throws {
    let journal = InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "mem-device")
    let tid = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "f.bin", size: 100,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/f"), sourceURL: nil
    )
    try await journal.recordRemoteHandle(id: tid, handle: 0xBEEF)
    let h = await journal.remoteHandle(for: tid)
    XCTAssertEqual(h, 0xBEEF)
  }

  func testInMemoryJournalAddContentHash() async throws {
    let journal = InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "mem-device-ch")
    let tid = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "g.bin", size: 200,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/g"), sourceURL: nil
    )
    let sha = "deadbeef1234"
    try await journal.addContentHash(id: tid, hash: sha)
    let h = await journal.contentHash(for: tid)
    XCTAssertEqual(h, sha)
  }
}
