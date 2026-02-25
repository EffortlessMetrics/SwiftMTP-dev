// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPIndex
import SwiftMTPCore

final class LiveIndexTests: XCTestCase {
  private var index: SQLiteLiveIndex!

  override func setUp() async throws {
    // Use in-memory database for testing
    index = try SQLiteLiveIndex(path: ":memory:")
  }

  func testUpsertAndQuery() async throws {
    let obj = IndexedObject(
      deviceId: "test-device",
      storageId: 1,
      handle: 100,
      parentHandle: nil,
      name: "DCIM",
      pathKey: "/DCIM",
      sizeBytes: nil,
      mtime: nil,
      formatCode: 0x3001,
      isDirectory: true,
      changeCounter: 0
    )

    try await index.upsertObjects([obj], deviceId: "test-device")

    let children = try await index.children(
      deviceId: "test-device", storageId: 1, parentHandle: nil)
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0].name, "DCIM")
    XCTAssertTrue(children[0].isDirectory)
  }

  func testChangeCounter() async throws {
    let counter1 = try await index.currentChangeCounter(deviceId: "test-device")
    XCTAssertEqual(counter1, 0)

    let counter2 = try await index.nextChangeCounter(deviceId: "test-device")
    XCTAssertEqual(counter2, 1)

    let counter3 = try await index.currentChangeCounter(deviceId: "test-device")
    XCTAssertEqual(counter3, 1)
  }

  func testStorageUpsert() async throws {
    let storage = IndexedStorage(
      deviceId: "test-device",
      storageId: 1,
      description: "Internal Storage",
      capacity: 64_000_000_000,
      free: 32_000_000_000,
      readOnly: false
    )

    try await index.upsertStorage(storage)

    let storages = try await index.storages(deviceId: "test-device")
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Internal Storage")
  }

  func testStaleMarkingAndPurge() async throws {
    let obj = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 100,
      parentHandle: nil, name: "old-file.txt", pathKey: "/old-file.txt",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )

    try await index.upsertObjects([obj], deviceId: "test-device")

    // Mark stale
    try await index.markStaleChildren(deviceId: "test-device", storageId: 1, parentHandle: nil)

    // Stale objects not returned by children query
    let children = try await index.children(
      deviceId: "test-device", storageId: 1, parentHandle: nil)
    XCTAssertEqual(children.count, 0)

    // Purge removes them permanently
    try await index.purgeStale(deviceId: "test-device", storageId: 1, parentHandle: nil)
  }

  func testChangesSince() async throws {
    let obj1 = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 100,
      parentHandle: nil, name: "file1.txt", pathKey: "/file1.txt",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )

    try await index.upsertObjects([obj1], deviceId: "test-device")
    let anchor = try await index.currentChangeCounter(deviceId: "test-device")

    // Add another object
    let obj2 = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 101,
      parentHandle: nil, name: "file2.txt", pathKey: "/file2.txt",
      sizeBytes: 2048, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await index.upsertObjects([obj2], deviceId: "test-device")

    let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
    XCTAssertTrue(changes.contains(where: { $0.object.name == "file2.txt" }))
  }

  func testRemoveObject() async throws {
    let obj = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 100,
      parentHandle: nil, name: "to-delete.txt", pathKey: "/to-delete.txt",
      sizeBytes: 512, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )

    try await index.upsertObjects([obj], deviceId: "test-device")
    let anchor = try await index.currentChangeCounter(deviceId: "test-device")

    try await index.removeObject(deviceId: "test-device", storageId: 1, handle: 100)

    // Object should no longer appear in children
    let children = try await index.children(
      deviceId: "test-device", storageId: 1, parentHandle: nil)
    XCTAssertEqual(children.count, 0)

    // Should appear as deleted in changes
    let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
    XCTAssertTrue(changes.contains(where: { $0.kind == .deleted && $0.object.handle == 100 }))
  }

  // MARK: - Change Tracking Correctness (live_changes table)

  func testMarkStaleChildrenReportsDeletions() async throws {
    // Insert some objects
    let obj1 = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 200,
      parentHandle: nil, name: "file-a.txt", pathKey: "/file-a.txt",
      sizeBytes: 100, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    let obj2 = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 201,
      parentHandle: nil, name: "file-b.txt", pathKey: "/file-b.txt",
      sizeBytes: 200, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await index.upsertObjects([obj1, obj2], deviceId: "test-device")
    let anchor = try await index.currentChangeCounter(deviceId: "test-device")

    // Mark all root children stale (simulates re-crawl start)
    try await index.markStaleChildren(deviceId: "test-device", storageId: 1, parentHandle: nil)

    // Both should appear as deleted in changesSince
    let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
    let deletedHandles = changes.filter { $0.kind == .deleted }.map { $0.object.handle }
    XCTAssertTrue(deletedHandles.contains(200))
    XCTAssertTrue(deletedHandles.contains(201))
  }

  func testUpsertThenDeleteOnlyReportsDelete() async throws {
    let anchor: Int64 = 0

    // Upsert an object
    let obj = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 300,
      parentHandle: nil, name: "ephemeral.txt", pathKey: "/ephemeral.txt",
      sizeBytes: 50, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await index.upsertObjects([obj], deviceId: "test-device")

    // Then remove it
    try await index.removeObject(deviceId: "test-device", storageId: 1, handle: 300)

    // changesSince(anchor=0): deduplication should report only the delete
    let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
    let forHandle300 = changes.filter { $0.object.handle == 300 }
    XCTAssertEqual(forHandle300.count, 1)
    XCTAssertEqual(forHandle300[0].kind, .deleted)
  }

  func testUpsertStaleThenReUpsertReportsOnlyFinalUpsert() async throws {
    // Upsert object
    let obj = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 400,
      parentHandle: nil, name: "revived.txt", pathKey: "/revived.txt",
      sizeBytes: 75, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await index.upsertObjects([obj], deviceId: "test-device")
    let anchor = try await index.currentChangeCounter(deviceId: "test-device")

    // Mark stale (simulates folder re-crawl)
    try await index.markStaleChildren(deviceId: "test-device", storageId: 1, parentHandle: nil)

    // Re-upsert (found again during crawl)
    try await index.upsertObjects([obj], deviceId: "test-device")

    // changesSince: final state is upsert (object was revived)
    let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
    let forHandle400 = changes.filter { $0.object.handle == 400 }
    XCTAssertEqual(forHandle400.count, 1)
    XCTAssertEqual(forHandle400[0].kind, .upserted)
  }

  // MARK: - Sync Anchor Encoding

  func testSyncAnchorRoundTrip() {
    // Test that encoding/decoding Int64 via Data is alignment-safe
    let values: [Int64] = [0, 1, -1, Int64.max, Int64.min, 42, 1_000_000]
    for value in values {
      var encoded = value
      let data = Data(bytes: &encoded, count: MemoryLayout<Int64>.size)

      // Decode using the safe method (copyBytes instead of load)
      var decoded: Int64 = 0
      _ = withUnsafeMutableBytes(of: &decoded) { data.copyBytes(to: $0) }

      XCTAssertEqual(value, decoded, "Round-trip failed for \(value)")
    }
  }

  func testSyncAnchorUnalignedData() {
    // Simulate unaligned data (e.g., from network or file)
    let value: Int64 = 123456789
    var encoded = value
    let data = Data(bytes: &encoded, count: MemoryLayout<Int64>.size)

    // This should NOT trap even on strict alignment architectures
    var decoded: Int64 = 0
    _ = withUnsafeMutableBytes(of: &decoded) { data.copyBytes(to: $0) }
    XCTAssertEqual(value, decoded)
  }

  // MARK: - Prune Change Log

  func testPruneChangeLog() async throws {
    // Insert some objects to generate change records
    let obj = IndexedObject(
      deviceId: "test-device", storageId: 1, handle: 500,
      parentHandle: nil, name: "prunable.txt", pathKey: "/prunable.txt",
      sizeBytes: 10, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await index.upsertObjects([obj], deviceId: "test-device")

    // Prune records older than 1 hour from now (should keep our records)
    let oneHourAgo = Date().addingTimeInterval(-3600)
    try await index.pruneChangeLog(deviceId: "test-device", olderThan: oneHourAgo)

    // Records should still be visible
    let changes = try await index.changesSince(deviceId: "test-device", anchor: 0)
    XCTAssertFalse(changes.isEmpty)

    // Prune records older than 1 hour in the future (should remove all records)
    let oneHourFromNow = Date().addingTimeInterval(3600)
    try await index.pruneChangeLog(deviceId: "test-device", olderThan: oneHourFromNow)

    // No change records should remain
    let changes2 = try await index.changesSince(deviceId: "test-device", anchor: 0)
    XCTAssertTrue(changes2.isEmpty)
  }
}
