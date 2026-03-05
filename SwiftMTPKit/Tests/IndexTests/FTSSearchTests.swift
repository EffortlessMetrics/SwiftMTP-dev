// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("fts-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func makeObj(
  handle: UInt32,
  parentHandle: UInt32? = nil,
  storageId: UInt32 = 0x10001,
  name: String = "file.txt",
  pathKey: String? = nil,
  isDirectory: Bool = false,
  sizeBytes: UInt64 = 1024,
  formatCode: UInt16 = 0x3001
) -> IndexedObject {
  IndexedObject(
    deviceId: "dev",
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: pathKey ?? "00010001/\(name)",
    sizeBytes: sizeBytes,
    mtime: Date(),
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - FTS5 Query Escaping

@Suite("FTS5 Query Escaping")
struct FTSEscapingTests {

  @Test("Empty query returns empty string")
  func emptyQuery() {
    #expect(SQLiteLiveIndex.escapeFTS5Query("") == "")
    #expect(SQLiteLiveIndex.escapeFTS5Query("   ") == "")
  }

  @Test("Simple term is quoted")
  func simpleTerm() {
    #expect(SQLiteLiveIndex.escapeFTS5Query("photo") == "\"photo\"")
  }

  @Test("Prefix star is preserved outside quotes")
  func prefixStar() {
    #expect(SQLiteLiveIndex.escapeFTS5Query("IMG*") == "\"IMG\"*")
  }

  @Test("Internal double quotes are escaped")
  func internalQuotes() {
    #expect(SQLiteLiveIndex.escapeFTS5Query("my\"file") == "\"my\"\"file\"")
  }

  @Test("Special FTS5 characters are neutralized by quoting")
  func specialCharacters() {
    let result = SQLiteLiveIndex.escapeFTS5Query("AND OR NOT")
    #expect(result == "\"AND OR NOT\"")
  }
}

// MARK: - FTS5 Search Integration

@Suite("FTS5 Search")
struct FTSSearchTests {

  @Test("Basic filename search finds matching objects")
  func basicSearch() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "vacation_photo.jpg", pathKey: "DCIM/vacation_photo.jpg"),
      makeObj(handle: 2, name: "work_doc.pdf", pathKey: "Documents/work_doc.pdf"),
      makeObj(handle: 3, name: "photo_album.zip", pathKey: "Downloads/photo_album.zip"),
    ], deviceId: "dev")

    let results = try await idx.searchByFilename(deviceId: "dev", query: "photo")
    #expect(results.count == 2)
    let names = Set(results.map(\.name))
    #expect(names.contains("vacation_photo.jpg"))
    #expect(names.contains("photo_album.zip"))
  }

  @Test("Prefix search with wildcard")
  func prefixSearch() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "IMG_0001.jpg", pathKey: "DCIM/IMG_0001.jpg"),
      makeObj(handle: 2, name: "IMG_0002.jpg", pathKey: "DCIM/IMG_0002.jpg"),
      makeObj(handle: 3, name: "screenshot.png", pathKey: "DCIM/screenshot.png"),
    ], deviceId: "dev")

    let results = try await idx.searchByFilename(deviceId: "dev", query: "IMG*")
    #expect(results.count == 2)
  }

  @Test("Search returns empty for no matches")
  func emptyResults() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "readme.txt"),
    ], deviceId: "dev")

    let results = try await idx.searchByFilename(deviceId: "dev", query: "nonexistent")
    #expect(results.isEmpty)
  }

  @Test("Search with empty query returns empty")
  func emptyQuery() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "file.txt"),
    ], deviceId: "dev")

    let results = try await idx.searchByFilename(deviceId: "dev", query: "")
    #expect(results.isEmpty)
  }

  @Test("Search excludes stale (deleted) objects")
  func excludesStale() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "photo.jpg", pathKey: "DCIM/photo.jpg"),
      makeObj(handle: 2, name: "photo_old.jpg", pathKey: "DCIM/photo_old.jpg"),
    ], deviceId: "dev")

    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 2)

    let results = try await idx.searchByFilename(deviceId: "dev", query: "photo")
    #expect(results.count == 1)
    #expect(results.first?.handle == 1)
  }

  @Test("Search after upsert reflects updated name")
  func searchAfterUpdate() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "old_name.txt", pathKey: "root/old_name.txt"),
    ], deviceId: "dev")

    // Rename via upsert
    try await idx.upsertObjects([
      makeObj(handle: 1, name: "new_name.txt", pathKey: "root/new_name.txt"),
    ], deviceId: "dev")

    let oldResults = try await idx.searchByFilename(deviceId: "dev", query: "old_name")
    #expect(oldResults.isEmpty)

    let newResults = try await idx.searchByFilename(deviceId: "dev", query: "new_name")
    #expect(newResults.count == 1)
  }

  @Test("Path search finds objects by directory")
  func pathSearch() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "photo1.jpg", pathKey: "DCIM/Camera/photo1.jpg"),
      makeObj(handle: 2, name: "photo2.jpg", pathKey: "DCIM/Camera/photo2.jpg"),
      makeObj(handle: 3, name: "notes.txt", pathKey: "Documents/notes.txt"),
    ], deviceId: "dev")

    let results = try await idx.searchByPath(deviceId: "dev", query: "DCIM")
    #expect(results.count == 2)
  }

  @Test("Search scoped to device ID")
  func deviceScoped() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "shared.txt", pathKey: "root/shared.txt"),
    ], deviceId: "dev")

    // Insert object for different device directly
    let obj2 = IndexedObject(
      deviceId: "other-dev",
      storageId: 0x10001,
      handle: 2,
      parentHandle: nil,
      name: "shared.txt",
      pathKey: "root/shared.txt",
      sizeBytes: 512,
      mtime: Date(),
      formatCode: 0x3001,
      isDirectory: false,
      changeCounter: 0
    )
    try await idx.upsertObjects([obj2], deviceId: "other-dev")

    let devResults = try await idx.searchByFilename(deviceId: "dev", query: "shared")
    #expect(devResults.count == 1)
    #expect(devResults.first?.deviceId == "dev")

    let otherResults = try await idx.searchByFilename(deviceId: "other-dev", query: "shared")
    #expect(otherResults.count == 1)
    #expect(otherResults.first?.deviceId == "other-dev")
  }

  @Test("Search with special characters is safe")
  func specialCharacters() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "file (1).txt", pathKey: "root/file (1).txt"),
      makeObj(handle: 2, name: "file [copy].txt", pathKey: "root/file [copy].txt"),
    ], deviceId: "dev")

    // These should not crash — FTS5 special chars are safely escaped
    let r1 = try await idx.searchByFilename(deviceId: "dev", query: "file (1)")
    #expect(!r1.isEmpty)

    let r2 = try await idx.searchByFilename(deviceId: "dev", query: "AND OR NOT")
    #expect(r2.isEmpty)
  }

  @Test("Limit parameter caps results")
  func limitResults() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    var objects: [IndexedObject] = []
    for i: UInt32 in 1...20 {
      objects.append(makeObj(handle: i, name: "photo_\(i).jpg", pathKey: "DCIM/photo_\(i).jpg"))
    }
    try await idx.upsertObjects(objects, deviceId: "dev")

    let results = try await idx.searchByFilename(deviceId: "dev", query: "photo", limit: 5)
    #expect(results.count == 5)
  }

  @Test("Rebuild FTS index succeeds")
  func rebuildIndex() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([
      makeObj(handle: 1, name: "test.jpg", pathKey: "DCIM/test.jpg"),
    ], deviceId: "dev")

    // Should not throw
    try idx.rebuildFTSIndex()

    // Search should still work after rebuild
    let results = try await idx.searchByFilename(deviceId: "dev", query: "test")
    #expect(results.count == 1)
  }
}
