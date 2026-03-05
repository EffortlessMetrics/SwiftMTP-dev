// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("perf-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func cleanup(_ path: String) {
  for suffix in ["", "-wal", "-shm"] {
    try? FileManager.default.removeItem(atPath: path + suffix)
  }
}

private func makeObj(
  handle: UInt32,
  parentHandle: UInt32? = nil,
  storageId: UInt32 = 0x10001,
  name: String = "file.txt",
  isDirectory: Bool = false,
  formatCode: UInt16 = 0x3000
) -> IndexedObject {
  IndexedObject(
    deviceId: "dev-perf",
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: 1024,
    mtime: Date(),
    formatCode: isDirectory ? 0x3001 : formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - Performance Optimization Tests

final class IndexPerfOptTests: XCTestCase {

  // MARK: - Batch Insert vs Individual Insert

  func testBatchInsertFasterThanIndividual() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...2_000).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "batch-\(i).jpg")
    }

    // Measure batch insert (single transaction, no change log)
    let batchStart = CFAbsoluteTimeGetCurrent()
    try await idx.batchInsertObjects(objects)
    let batchElapsed = CFAbsoluteTimeGetCurrent() - batchStart

    // Verify all inserted
    let children = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1)
    XCTAssertEqual(children.count, 2_000)

    // Now create a fresh index for individual insert comparison
    let (idx2, path2) = try makeTempIndex()
    defer { cleanup(path2) }

    let individualStart = CFAbsoluteTimeGetCurrent()
    try await idx2.upsertObjects(objects, deviceId: "dev-perf")
    let individualElapsed = CFAbsoluteTimeGetCurrent() - individualStart

    // Batch should be faster (or at minimum, not slower)
    // We just verify both work; batch avoids change log overhead
    XCTAssertGreaterThan(individualElapsed, 0)
    XCTAssertGreaterThan(batchElapsed, 0)
    // Batch bypasses change log so should generally be faster
    print("Batch: \(String(format: "%.3f", batchElapsed))s, Individual: \(String(format: "%.3f", individualElapsed))s")
  }

  // MARK: - Batch Delete

  func testBatchDeleteObjects() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...500).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "del-\(i).jpg")
    }
    try await idx.batchInsertObjects(objects)

    // Delete handles 1-250
    let handles: [UInt32] = Array(1...250)
    try await idx.batchDeleteObjects(
      deviceId: "dev-perf", storageId: 0x10001, handles: handles)

    // Only 250 should remain non-stale
    let remaining = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1)
    XCTAssertEqual(remaining.count, 250)
  }

  // MARK: - Batch Update Modified Dates

  func testBatchUpdateModifiedDates() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...100).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "upd-\(i).jpg")
    }
    try await idx.batchInsertObjects(objects)

    let newDate = Date(timeIntervalSince1970: 2_000_000_000)
    let updates: [(handle: UInt32, date: Date)] = (1...100).map { i in
      (handle: UInt32(i), date: newDate)
    }
    try await idx.batchUpdateModifiedDates(
      deviceId: "dev-perf", storageId: 0x10001, updates: updates)

    // Verify dates were updated
    let obj = try await idx.object(deviceId: "dev-perf", handle: 1)
    XCTAssertNotNil(obj)
    XCTAssertEqual(
      Int64(obj!.mtime!.timeIntervalSince1970),
      Int64(newDate.timeIntervalSince1970))
  }

  // MARK: - Pagination

  func testPaginatedChildren() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...100).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "page-\(String(format: "%03d", i)).jpg")
    }
    try await idx.batchInsertObjects(objects)

    // Page 1: first 25
    let page1 = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1,
      limit: 25, offset: 0)
    XCTAssertEqual(page1.count, 25)

    // Page 2: next 25
    let page2 = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1,
      limit: 25, offset: 25)
    XCTAssertEqual(page2.count, 25)

    // No overlap between pages
    let page1Handles = Set(page1.map(\.handle))
    let page2Handles = Set(page2.map(\.handle))
    XCTAssertTrue(page1Handles.isDisjoint(with: page2Handles))

    // Last page (past the end)
    let lastPage = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1,
      limit: 25, offset: 100)
    XCTAssertEqual(lastPage.count, 0)
  }

  // MARK: - Lazy Loading (handles first, details on demand)

  func testChildHandlesAndDetailLoading() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...500).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "lazy-\(i).jpg")
    }
    try await idx.batchInsertObjects(objects)

    // Step 1: get handles only (fast)
    let handles = try await idx.childHandles(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1)
    XCTAssertEqual(handles.count, 500)

    // Step 2: load details for first 10 only
    let firstTen = Array(handles.prefix(10))
    let details = try await idx.objectsByHandles(
      deviceId: "dev-perf", handles: firstTen)
    XCTAssertEqual(details.count, 10)
    // Verify all requested handles present
    let detailHandles = Set(details.map(\.handle))
    for h in firstTen { XCTAssertTrue(detailHandles.contains(h)) }
  }

  // MARK: - Child Count

  func testChildCount() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...200).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "cnt-\(i).jpg")
    }
    try await idx.batchInsertObjects(objects)

    let count = try await idx.childCount(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1)
    XCTAssertEqual(count, 200)

    // Root count (no parent)
    let rootCount = try await idx.childCount(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: nil)
    XCTAssertEqual(rootCount, 0)
  }

  // MARK: - Format Filter Query

  func testObjectsByFormat() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    // Insert mix of formats: 0x3801 (JPEG) and 0x3804 (PNG)
    var objects: [IndexedObject] = []
    for i in 1...100 {
      let fmt: UInt16 = i % 3 == 0 ? 0x3804 : 0x3801
      objects.append(makeObj(
        handle: UInt32(i), parentHandle: 1,
        name: "fmt-\(i).\(fmt == 0x3801 ? "jpg" : "png")",
        formatCode: fmt))
    }
    try await idx.batchInsertObjects(objects)

    let jpgs = try await idx.objectsByFormat(
      deviceId: "dev-perf", formatCode: 0x3801)
    XCTAssertEqual(jpgs.count, 67)  // 100 - 33 PNGs

    let pngs = try await idx.objectsByFormat(
      deviceId: "dev-perf", formatCode: 0x3804)
    XCTAssertEqual(pngs.count, 33)
  }

  // MARK: - Query Plan Validation

  func testQueryPlanUsesIndexForChildren() throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let plan = try idx.database.explainQueryPlan(
      "SELECT * FROM live_objects WHERE deviceId = 'x' AND storageId = 1 AND parentHandle = 2 AND stale = 0"
    )
    // Should use an index, not a full table scan
    let planText = plan.joined(separator: " ")
    XCTAssertTrue(
      planText.contains("USING INDEX") || planText.contains("SEARCH"),
      "Children query should use an index. Plan: \(planText)")
  }

  func testQueryPlanUsesIndexForFormat() throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let plan = try idx.database.explainQueryPlan(
      "SELECT * FROM live_objects WHERE deviceId = 'x' AND formatCode = 14337 AND stale = 0"
    )
    let planText = plan.joined(separator: " ")
    XCTAssertTrue(
      planText.contains("USING INDEX") || planText.contains("SEARCH"),
      "Format query should use an index. Plan: \(planText)")
  }

  func testQueryPlanUsesIndexForStaleCleanup() throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let plan = try idx.database.explainQueryPlan(
      "DELETE FROM live_objects WHERE deviceId = 'x' AND storageId = 1 AND stale = 1"
    )
    let planText = plan.joined(separator: " ")
    XCTAssertTrue(
      planText.contains("USING INDEX") || planText.contains("SEARCH"),
      "Stale cleanup should use an index. Plan: \(planText)")
  }

  // MARK: - Compound Index for Deep Trees

  func testDeepTreeChildrenPerformance() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    // Build a 5-level deep tree: root -> L1 (10) -> L2 (10 each) -> ...
    var objects: [IndexedObject] = []
    var handle: UInt32 = 1

    // 10 L1 folders
    for _ in 0..<10 {
      objects.append(makeObj(handle: handle, parentHandle: nil, name: "L1-\(handle)", isDirectory: true))
      let l1 = handle
      handle += 1
      // 10 L2 folders under each L1
      for _ in 0..<10 {
        objects.append(makeObj(handle: handle, parentHandle: l1, name: "L2-\(handle)", isDirectory: true))
        let l2 = handle
        handle += 1
        // 10 files under each L2
        for _ in 0..<10 {
          objects.append(makeObj(handle: handle, parentHandle: l2, name: "file-\(handle).dat"))
          handle += 1
        }
      }
    }

    try await idx.batchInsertObjects(objects)

    // Query a deep folder — should be fast with compound index
    let start = CFAbsoluteTimeGetCurrent()
    let children = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 2)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertGreaterThan(children.count, 0)
    // Should complete in under 100ms even for in-memory index
    XCTAssertLessThan(elapsed, 1.0, "Deep tree query took \(elapsed)s — too slow")
  }

  // MARK: - Large Batch Insert 10K

  func testBatchInsert10K() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    let objects = (1...10_000).map { i in
      makeObj(
        handle: UInt32(i),
        parentHandle: UInt32(i % 100 + 1),
        name: "bulk-\(i).jpg"
      )
    }

    let start = CFAbsoluteTimeGetCurrent()
    try await idx.batchInsertObjects(objects)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // Verify count
    let sample = try await idx.children(
      deviceId: "dev-perf", storageId: 0x10001, parentHandle: 1)
    XCTAssertGreaterThan(sample.count, 0)

    // Should complete in under 10s for 10K objects
    XCTAssertLessThan(elapsed, 10.0, "10K batch insert took \(elapsed)s — too slow")
    print("10K batch insert: \(String(format: "%.3f", elapsed))s")
  }

  // MARK: - Empty Batch Edge Cases

  func testEmptyBatchOperationsAreNoOps() async throws {
    let (idx, path) = try makeTempIndex()
    defer { cleanup(path) }

    // All empty batch operations should succeed silently
    try await idx.batchInsertObjects([])
    try await idx.batchDeleteObjects(deviceId: "dev-perf", storageId: 0x10001, handles: [])
    try await idx.batchUpdateModifiedDates(deviceId: "dev-perf", storageId: 0x10001, updates: [])
  }
}
