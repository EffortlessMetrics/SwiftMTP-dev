// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPCLI

// MARK: - SearchCommand Tests

@MainActor
final class SearchCommandTests: XCTestCase {

  // MARK: - FTS5 Query Escaping

  func testEscapeFTS5QuerySimple() {
    let result = SQLiteLiveIndex.escapeFTS5Query("photo")
    XCTAssertEqual(result, "\"photo\"")
  }

  func testEscapeFTS5QueryPrefixWildcard() {
    let result = SQLiteLiveIndex.escapeFTS5Query("IMG*")
    XCTAssertEqual(result, "\"IMG\"*")
  }

  func testEscapeFTS5QueryEmpty() {
    let result = SQLiteLiveIndex.escapeFTS5Query("")
    XCTAssertEqual(result, "")
  }

  func testEscapeFTS5QueryWhitespace() {
    let result = SQLiteLiveIndex.escapeFTS5Query("   ")
    XCTAssertEqual(result, "")
  }

  func testEscapeFTS5QueryWithQuotes() {
    let result = SQLiteLiveIndex.escapeFTS5Query("my \"file\"")
    XCTAssertEqual(result, "\"my \"\"file\"\"\"")
  }

  // MARK: - Search Help Text

  func testSearchHelpDoesNotCrash() {
    // Verify help can be called without errors
    SearchCommand.printSearchHelp()
  }

  // MARK: - SQLiteLiveIndex Search Integration

  func testSearchByFilenameReturnsResults() async throws {
    let tmp = NSTemporaryDirectory() + "search_test_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let obj = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 42,
      parentHandle: nil, name: "vacation_photo.jpg",
      pathKey: "/DCIM/vacation_photo.jpg",
      sizeBytes: 1024, mtime: Date(), formatCode: 0x3801,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: obj.deviceId)

    let results = try await index.searchByFilename(
      deviceId: "dev1", query: "vacation", limit: 50)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.name, "vacation_photo.jpg")
    XCTAssertEqual(results.first?.handle, 42)
  }

  func testSearchByPathReturnsResults() async throws {
    let tmp = NSTemporaryDirectory() + "search_path_test_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let obj = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 10,
      parentHandle: nil, name: "IMG_001.jpg",
      pathKey: "/DCIM/Camera/IMG_001.jpg",
      sizeBytes: 2048, mtime: nil, formatCode: 0x3801,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: obj.deviceId)

    let results = try await index.searchByPath(
      deviceId: "dev1", query: "DCIM", limit: 50)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.pathKey, "/DCIM/Camera/IMG_001.jpg")
  }

  func testSearchByFilenameEmptyQuery() async throws {
    let tmp = NSTemporaryDirectory() + "search_empty_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let results = try await index.searchByFilename(
      deviceId: "dev1", query: "", limit: 50)
    XCTAssertTrue(results.isEmpty)
  }

  func testSearchByFilenameNoMatch() async throws {
    let tmp = NSTemporaryDirectory() + "search_nomatch_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let obj = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 5,
      parentHandle: nil, name: "report.pdf",
      pathKey: "/Documents/report.pdf",
      sizeBytes: 4096, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: obj.deviceId)

    let results = try await index.searchByFilename(
      deviceId: "dev1", query: "nonexistent", limit: 50)
    XCTAssertTrue(results.isEmpty)
  }

  func testSearchRespectsLimit() async throws {
    let tmp = NSTemporaryDirectory() + "search_limit_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    for i in 0..<10 {
      let obj = IndexedObject(
        deviceId: "dev1", storageId: 1, handle: UInt32(i + 1),
        parentHandle: nil, name: "photo_\(i).jpg",
        pathKey: "/DCIM/photo_\(i).jpg",
        sizeBytes: 1024, mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 1)
      try await index.upsertObjects([obj], deviceId: obj.deviceId)
    }

    let results = try await index.searchByFilename(
      deviceId: "dev1", query: "photo", limit: 3)
    XCTAssertEqual(results.count, 3)
  }

  func testSearchPrefixMatch() async throws {
    let tmp = NSTemporaryDirectory() + "search_prefix_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let obj = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 1,
      parentHandle: nil, name: "IMG_20240101.jpg",
      pathKey: "/DCIM/IMG_20240101.jpg",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3801,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj], deviceId: obj.deviceId)

    let results = try await index.searchByFilename(
      deviceId: "dev1", query: "IMG*", limit: 50)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.name, "IMG_20240101.jpg")
  }

  func testSearchScopesToDeviceId() async throws {
    let tmp = NSTemporaryDirectory() + "search_scope_\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let index = try SQLiteLiveIndex(path: tmp)
    let obj1 = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 1,
      parentHandle: nil, name: "shared.txt",
      pathKey: "/shared.txt",
      sizeBytes: 100, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 1)
    let obj2 = IndexedObject(
      deviceId: "dev2", storageId: 1, handle: 2,
      parentHandle: nil, name: "shared.txt",
      pathKey: "/shared.txt",
      sizeBytes: 200, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 1)
    try await index.upsertObjects([obj1], deviceId: obj1.deviceId)
    try await index.upsertObjects([obj2], deviceId: obj2.deviceId)

    let dev1Results = try await index.searchByFilename(
      deviceId: "dev1", query: "shared", limit: 50)
    XCTAssertEqual(dev1Results.count, 1)
    XCTAssertEqual(dev1Results.first?.deviceId, "dev1")

    let dev2Results = try await index.searchByFilename(
      deviceId: "dev2", query: "shared", limit: 50)
    XCTAssertEqual(dev2Results.count, 1)
    XCTAssertEqual(dev2Results.first?.deviceId, "dev2")
  }
}
