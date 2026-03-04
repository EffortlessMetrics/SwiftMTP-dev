// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("boundary-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func makeObj(
  deviceId: String = "dev-boundary",
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
    deviceId: deviceId,
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: pathKey ?? "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: sizeBytes,
    mtime: Date(),
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - 1. Empty Database

@Suite("IndexBoundary – Empty Database")
struct IndexBoundaryEmptyDatabaseTests {

  @Test("Query children on empty database returns empty array")
  func emptyDatabaseChildren() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let children = try await idx.children(
      deviceId: "nonexistent", storageId: 0x10001, parentHandle: nil)
    #expect(children.isEmpty)
  }

  @Test("Query object by handle on empty database returns nil")
  func emptyDatabaseObjectLookup() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let obj = try await idx.object(deviceId: "nonexistent", handle: 0x12345)
    #expect(obj == nil)
  }

  @Test("Change counter on empty database returns zero or valid value")
  func emptyDatabaseChangeCounter() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let counter = try await idx.currentChangeCounter(deviceId: "nonexistent")
    #expect(counter >= 0)
  }
}

// MARK: - 2. Concurrent Read While Writing

@Suite("IndexBoundary – Concurrent Read/Write")
struct IndexBoundaryConcurrentTests {

  @Test("Concurrent readers do not see partial writes")
  func concurrentReadDuringWrite() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let batchSize = 50
    let objects = (0..<batchSize)
      .map { i in
        makeObj(handle: UInt32(i + 1), name: "concurrent-\(i).txt")
      }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writer: insert batch
      group.addTask {
        try await idx.upsertObjects(objects, deviceId: "dev-boundary")
      }

      // Readers: query repeatedly during writes
      for _ in 0..<5 {
        group.addTask {
          let children = try await idx.children(
            deviceId: "dev-boundary", storageId: 0x10001, parentHandle: nil)
          // Should see either 0 (before write) or all 50 (after write), never partial
          #expect(children.count == 0 || children.count == batchSize)
        }
      }

      try await group.waitForAll()
    }
  }
}

// MARK: - 3. SQL Injection Attempts

@Suite("IndexBoundary – SQL Injection Safety")
struct IndexBoundarySQLInjectionTests {

  @Test("Object name with SQL injection attempt is stored safely")
  func sqlInjectionInName() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let maliciousName = "'; DROP TABLE live_objects; --"
    let obj = makeObj(handle: 1, name: maliciousName, pathKey: "00010001/\(maliciousName)")
    try await idx.upsertObjects([obj], deviceId: "dev-boundary")

    let retrieved = try await idx.object(deviceId: "dev-boundary", handle: 1)
    #expect(retrieved != nil)
    #expect(retrieved?.name == maliciousName)
  }

  @Test("Path key with SQL injection is handled safely")
  func sqlInjectionInPathKey() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let maliciousPath = "00010001/\" OR 1=1; --"
    let obj = makeObj(handle: 2, name: "test.txt", pathKey: maliciousPath)
    try await idx.upsertObjects([obj], deviceId: "dev-boundary")

    let retrieved = try await idx.object(deviceId: "dev-boundary", handle: 2)
    #expect(retrieved != nil)
    #expect(retrieved?.pathKey == maliciousPath)
  }

  @Test("Device ID with SQL metacharacters is safe")
  func sqlInjectionInDeviceId() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let maliciousDeviceId = "dev'; DELETE FROM live_objects WHERE '1'='1"
    let obj = makeObj(deviceId: maliciousDeviceId, handle: 1)
    try await idx.upsertObjects([obj], deviceId: maliciousDeviceId)

    let retrieved = try await idx.object(deviceId: maliciousDeviceId, handle: 1)
    #expect(retrieved != nil)
  }
}

// MARK: - 4. Deep Path Hierarchies

@Suite("IndexBoundary – Deep Paths")
struct IndexBoundaryDeepPathTests {

  @Test("Index supports 100+ level deep path hierarchy")
  func deepPathHierarchy() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let depth = 120
    var objects: [IndexedObject] = []
    var pathAccum = "00010001"

    for i in 0..<depth {
      let handle = UInt32(i + 1)
      let parentHandle: UInt32? = i == 0 ? nil : UInt32(i)
      let name = "dir\(i)"
      pathAccum += "/\(name)"
      objects.append(
        makeObj(
          handle: handle,
          parentHandle: parentHandle,
          name: name,
          pathKey: pathAccum,
          isDirectory: true
        ))
    }

    // Add a leaf file at the deepest level
    let leafPath = pathAccum + "/deep-leaf.txt"
    objects.append(
      makeObj(
        handle: UInt32(depth + 1),
        parentHandle: UInt32(depth),
        name: "deep-leaf.txt",
        pathKey: leafPath
      ))

    try await idx.upsertObjects(objects, deviceId: "dev-boundary")

    // Verify the deepest directory's child is retrievable
    let children = try await idx.children(
      deviceId: "dev-boundary", storageId: 0x10001,
      parentHandle: UInt32(depth))
    #expect(children.count == 1)
    #expect(children.first?.name == "deep-leaf.txt")
  }
}

// MARK: - 5. Special Characters in Filenames

@Suite("IndexBoundary – Special Characters")
struct IndexBoundarySpecialCharTests {

  @Test("Unicode filenames round-trip through index")
  func unicodeFilenames() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let names = [
      "café.jpg",
      "日本語ファイル.txt",
      "Ñoño.mp3",
      "🎵music🎶.wav",
      "Привет.doc",
      "αβγδ.pdf",
      "한국어.png",
    ]

    let objects = names.enumerated()
      .map { i, name in
        makeObj(handle: UInt32(i + 1), name: name, pathKey: "00010001/\(name)")
      }

    try await idx.upsertObjects(objects, deviceId: "dev-boundary")

    for (i, name) in names.enumerated() {
      let obj = try await idx.object(deviceId: "dev-boundary", handle: UInt32(i + 1))
      #expect(obj?.name == name, "Unicode filename '\(name)' should round-trip")
    }
  }

  @Test("Emoji-only filename is stored and retrieved")
  func emojiOnlyFilename() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let emojiName = "🏳️‍🌈🇺🇸🧑‍💻.txt"
    let obj = makeObj(handle: 1, name: emojiName, pathKey: "00010001/\(emojiName)")
    try await idx.upsertObjects([obj], deviceId: "dev-boundary")

    let retrieved = try await idx.object(deviceId: "dev-boundary", handle: 1)
    #expect(retrieved?.name == emojiName)
  }

  @Test("Null byte in filename does not corrupt index")
  func nullByteInFilename() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let nameWithNull = "file\0name.txt"
    let obj = makeObj(handle: 1, name: nameWithNull, pathKey: "00010001/\(nameWithNull)")
    try await idx.upsertObjects([obj], deviceId: "dev-boundary")

    // The index should either store the name faithfully or sanitize it,
    // but must not corrupt other data
    let children = try await idx.children(
      deviceId: "dev-boundary", storageId: 0x10001, parentHandle: nil)
    #expect(children.count == 1)
  }

  @Test("NFC vs NFD combining characters are handled")
  func nfcVsNfdNormalization() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let nfcName = "caf\u{00E9}.txt"  // é as single codepoint (NFC)
    let nfdName = "caf\u{0065}\u{0301}.txt"  // e + combining acute (NFD)

    let obj1 = makeObj(handle: 1, name: nfcName, pathKey: "00010001/\(nfcName)")
    let obj2 = makeObj(handle: 2, name: nfdName, pathKey: "00010001/\(nfdName)")

    try await idx.upsertObjects([obj1, obj2], deviceId: "dev-boundary")

    let retrieved1 = try await idx.object(deviceId: "dev-boundary", handle: 1)
    let retrieved2 = try await idx.object(deviceId: "dev-boundary", handle: 2)
    #expect(retrieved1 != nil)
    #expect(retrieved2 != nil)
  }
}
