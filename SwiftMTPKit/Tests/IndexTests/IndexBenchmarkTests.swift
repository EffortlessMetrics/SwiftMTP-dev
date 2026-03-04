// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("bench-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func makeObj(
  handle: UInt32,
  parentHandle: UInt32? = nil,
  storageId: UInt32 = 0x10001,
  name: String = "file.txt",
  isDirectory: Bool = false
) -> IndexedObject {
  IndexedObject(
    deviceId: "dev-bench",
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: 1024,
    mtime: Date(),
    formatCode: isDirectory ? 0x3001 : 0x3000,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - Benchmarks

final class IndexBenchmarkTests: XCTestCase {

  // MARK: - Insert 10,000 objects

  func testBenchmarkBulkInsert10K() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...10_000).map { i in
      makeObj(
        handle: UInt32(i),
        parentHandle: UInt32(i % 100 + 1),
        name: "file-\(i).jpg"
      )
    }

    // Batch insert in chunks to mirror real usage
    let chunkSize = 500
    measure {
      let exp = expectation(description: "insert")
      Task {
        for start in stride(from: 0, to: objects.count, by: chunkSize) {
          let end = min(start + chunkSize, objects.count)
          try await idx.upsertObjects(Array(objects[start..<end]), deviceId: "dev-bench")
        }
        exp.fulfill()
      }
      wait(for: [exp], timeout: 60)
    }
  }

  // MARK: - Query children of a folder with 1,000 children

  func testBenchmarkQueryChildren1K() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create a parent folder and 1,000 children
    let parentHandle: UInt32 = 1
    let folder = makeObj(handle: parentHandle, name: "Photos", isDirectory: true)
    try await idx.upsertObjects([folder], deviceId: "dev-bench")

    let children = (2...1_001).map { i in
      makeObj(
        handle: UInt32(i),
        parentHandle: parentHandle,
        name: "IMG_\(String(format: "%04d", i)).jpg"
      )
    }
    try await idx.upsertObjects(children, deviceId: "dev-bench")

    measure {
      let exp = expectation(description: "children")
      Task {
        let result = try await idx.children(
          deviceId: "dev-bench", storageId: 0x10001, parentHandle: parentHandle)
        XCTAssertEqual(result.count, 1_000)
        exp.fulfill()
      }
      wait(for: [exp], timeout: 10)
    }
  }

  // MARK: - Search by filename pattern across 10,000 objects

  func testBenchmarkSearchByName10K() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...10_000).map { i in
      makeObj(
        handle: UInt32(i),
        parentHandle: 1,
        name: i % 5 == 0 ? "photo-\(i).jpg" : "document-\(i).pdf"
      )
    }
    try await idx.upsertObjects(objects, deviceId: "dev-bench")

    measure {
      let exp = expectation(description: "search")
      Task {
        let results = try await idx.searchByName(
          deviceId: "dev-bench", pattern: "%photo%")
        XCTAssertEqual(results.count, 2_000)
        exp.fulfill()
      }
      wait(for: [exp], timeout: 10)
    }
  }

  // MARK: - Full catalog snapshot (read all 10K objects)

  func testBenchmarkFullCatalogRead10K() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert 100 folders, each with 100 files = 10,100 objects
    var objects: [IndexedObject] = []
    for folder in 0..<100 {
      let fh = UInt32(folder + 1)
      objects.append(makeObj(handle: fh, name: "folder-\(folder)", isDirectory: true))
      for file in 0..<100 {
        let handle = UInt32(101 + folder * 100 + file)
        objects.append(makeObj(handle: handle, parentHandle: fh, name: "file-\(file).dat"))
      }
    }
    try await idx.upsertObjects(objects, deviceId: "dev-bench")

    measure {
      let exp = expectation(description: "snapshot")
      Task {
        var total = 0
        // Enumerate all folders
        let roots = try await idx.children(
          deviceId: "dev-bench", storageId: 0x10001, parentHandle: nil)
        total += roots.count
        for root in roots {
          let kids = try await idx.children(
            deviceId: "dev-bench", storageId: 0x10001, parentHandle: root.handle)
          total += kids.count
        }
        XCTAssertEqual(total, 10_100)
        exp.fulfill()
      }
      wait(for: [exp], timeout: 30)
    }
  }

  // MARK: - changesSince with optimized JOIN

  func testBenchmarkChangesSince() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert 5,000 objects to create change records
    let objects = (1...5_000).map { i in
      makeObj(handle: UInt32(i), parentHandle: 1, name: "change-\(i).dat")
    }
    try await idx.upsertObjects(objects, deviceId: "dev-bench")

    // Now query changes since anchor 0
    measure {
      let exp = expectation(description: "changes")
      Task {
        let changes = try await idx.changesSince(deviceId: "dev-bench", anchor: 0)
        XCTAssertGreaterThan(changes.count, 0)
        exp.fulfill()
      }
      wait(for: [exp], timeout: 30)
    }
  }
}
