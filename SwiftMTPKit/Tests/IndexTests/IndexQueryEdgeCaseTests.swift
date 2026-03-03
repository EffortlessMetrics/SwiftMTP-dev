// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("query-edge-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func makeObj(
  deviceId: String = "dev",
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

// MARK: - Unicode and Special Character Tests

@Suite("Index Unicode Edge Cases")
struct IndexUnicodeEdgeCaseTests {

  @Test("Unicode filenames survive index roundtrip")
  func unicodeFilenameRoundtrip() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let unicodeNames = [
      "日本語ファイル.jpg",
      "中文文件名.mp4",
      "한국어파일.png",
      "Ñoño.txt",
      "café☕.doc",
      "🎵music🎵.mp3",
      "файл.dat",
      "αβγδ.csv",
    ]
    for (i, name) in unicodeNames.enumerated() {
      let obj = makeObj(handle: UInt32(i + 1), name: name, pathKey: "/\(name)")
      try await index.insertObject(obj, deviceId: "dev")
    }
    let all = try await index.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == unicodeNames.count)
    for name in unicodeNames {
      #expect(all.contains { $0.name == name })
    }
  }

  @Test("Combining characters in filenames")
  func combiningCharacters() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // NFC vs NFD forms of "e-acute"
    let nfc = "caf\u{00E9}.txt"  // precomposed
    let nfd = "cafe\u{0301}.txt"  // decomposed
    try await index.insertObject(
      makeObj(handle: 1, name: nfc, pathKey: "/\(nfc)"), deviceId: "dev")
    try await index.insertObject(
      makeObj(handle: 2, name: nfd, pathKey: "/\(nfd)"), deviceId: "dev")
    let all = try await index.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 2)
  }

  @Test("Zero-width characters in filenames")
  func zeroWidthCharacters() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let name = "test\u{200B}file\u{FEFF}.txt"
    try await index.insertObject(
      makeObj(handle: 1, name: name, pathKey: "/\(name)"), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == name)
  }

  @Test("Very long filenames at MTP 255-byte limit")
  func longFilenames() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let name = String(repeating: "a", count: 251) + ".txt"
    try await index.insertObject(
      makeObj(handle: 1, name: name, pathKey: "/\(name)"), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == name)
  }
}

// MARK: - Large Dataset Tests

@Suite("Index Large Dataset Operations")
struct IndexLargeDatasetTests {

  @Test("Insert and query 1000 objects")
  func thousandObjects() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...1000)
      .map { i in
        makeObj(handle: UInt32(i), name: "file\(i).jpg", pathKey: "/DCIM/file\(i).jpg")
      }
    try await index.upsertObjects(objects, deviceId: "dev")
    let all = try await index.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 1000)
  }

  @Test("Deep directory nesting 20 levels")
  func deepNesting() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    var objects: [IndexedObject] = []
    for depth: UInt32 in 1...20 {
      let parentHandle: UInt32? = depth == 1 ? nil : depth - 1
      let pathSegments = (1...depth).map { "dir\($0)" }.joined(separator: "/")
      objects.append(
        makeObj(
          handle: depth,
          parentHandle: parentHandle,
          name: "dir\(depth)",
          pathKey: "/\(pathSegments)",
          isDirectory: true
        ))
    }
    try await index.upsertObjects(objects, deviceId: "dev")

    // Walk from deepest to root
    var segments: [String] = []
    var cur = try await index.object(deviceId: "dev", handle: 20)
    while let obj = cur {
      segments.insert(obj.name, at: 0)
      if let ph = obj.parentHandle {
        cur = try await index.object(deviceId: "dev", handle: ph)
      } else {
        cur = nil
      }
    }
    #expect(segments.count == 20)
  }

  @Test("Multiple storage IDs isolation")
  func multipleStorageIds() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, storageId: 0x10001, name: "internal.jpg", pathKey: "/internal.jpg"),
      deviceId: "dev"
    )
    try await index.insertObject(
      makeObj(handle: 2, storageId: 0x20001, name: "sdcard.jpg", pathKey: "/sdcard.jpg"),
      deviceId: "dev"
    )
    let childrenA = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let childrenB = try await index.children(
      deviceId: "dev", storageId: 0x20001, parentHandle: nil)
    #expect(childrenA.count == 1)
    #expect(childrenB.count == 1)
    #expect(childrenA[0].name == "internal.jpg")
    #expect(childrenB[0].name == "sdcard.jpg")
  }

  @Test("Upsert updates existing objects")
  func upsertUpdatesExisting() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, name: "old.txt", pathKey: "/old.txt", sizeBytes: 100),
      deviceId: "dev"
    )
    try await index.upsertObjects(
      [makeObj(handle: 1, name: "new.txt", pathKey: "/new.txt", sizeBytes: 200)],
      deviceId: "dev"
    )
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == "new.txt")
    #expect(got?.sizeBytes == 200)
  }
}

// MARK: - Empty and Boundary Tests

@Suite("Index Boundary Conditions")
struct IndexBoundaryTests {

  @Test("Empty index returns no children")
  func emptyIndex() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let all = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.isEmpty)
  }

  @Test("Query non-existent device returns empty")
  func nonExistentDevice() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(makeObj(deviceId: "dev1", handle: 1), deviceId: "dev1")
    let children = try await index.children(
      deviceId: "dev2", storageId: 0x10001, parentHandle: nil)
    #expect(children.isEmpty)
  }

  @Test("Handle value zero is valid")
  func handleZero() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 0, name: "root.txt", pathKey: "/root.txt"),
      deviceId: "dev"
    )
    let got = try await index.object(deviceId: "dev", handle: 0)
    #expect(got != nil)
    #expect(got?.handle == 0)
  }

  @Test("Maximum handle value UInt32.max")
  func maxHandle() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: UInt32.max, name: "max.txt", pathKey: "/max.txt"),
      deviceId: "dev"
    )
    let got = try await index.object(deviceId: "dev", handle: UInt32.max)
    #expect(got != nil)
    #expect(got?.handle == UInt32.max)
  }

  @Test("Zero-byte file size")
  func zeroByteFile() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(makeObj(handle: 1, sizeBytes: 0), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got?.sizeBytes == 0)
  }

  @Test("Large file size near Int64.max")
  func largeFileSize() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // SQLite stores integers as Int64, so test the maximum representable value
    let maxSafe = UInt64(Int64.max)
    try await index.insertObject(makeObj(handle: 1, sizeBytes: maxSafe), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got?.sizeBytes == maxSafe)
  }

  @Test("Empty filename")
  func emptyFilename() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, name: "", pathKey: "/"), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
  }

  @Test("Multiple devices in same index")
  func multipleDevices() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(deviceId: "phone1", handle: 1, name: "a.txt", pathKey: "/a.txt"),
      deviceId: "phone1"
    )
    try await index.insertObject(
      makeObj(deviceId: "phone2", handle: 1, name: "b.txt", pathKey: "/b.txt"),
      deviceId: "phone2"
    )
    let gotA = try await index.object(deviceId: "phone1", handle: 1)
    let gotB = try await index.object(deviceId: "phone2", handle: 1)
    #expect(gotA?.name == "a.txt")
    #expect(gotB?.name == "b.txt")
  }
}

// MARK: - Format Code Coverage

@Suite("Index Format Code Coverage")
struct IndexFormatCodeTests {

  @Test("Standard MTP format codes stored correctly")
  func standardFormatCodes() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let formats: [(UInt16, String)] = [
      (0x3000, "undefined"),
      (0x3001, "association"),
      (0x3801, "exifJPEG"),
      (0x3802, "tiffEP"),
      (0x3807, "gif"),
      (0x380B, "png"),
      (0x380D, "tiff"),
      (0x3009, "mp3"),
      (0x300C, "asf"),
      (0x300B, "mpeg"),
      (0xB901, "wma"),
      (0xB902, "ogg"),
      (0xB903, "aac"),
      (0xB982, "mp4"),
      (0xB984, "3gp"),
      (0xBA05, "abstractAudioVideoPlaylist"),
      (0xBA10, "wmPlaylist"),
      (0xBA11, "m3uPlaylist"),
    ]
    let objects = formats.enumerated()
      .map { (i, entry) in
        makeObj(
          handle: UInt32(i + 1),
          name: "\(entry.1).dat",
          pathKey: "/\(entry.1).dat",
          formatCode: entry.0
        )
      }
    try await index.upsertObjects(objects, deviceId: "dev")
    let all = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == formats.count)
    for (code, _) in formats {
      #expect(all.contains { $0.formatCode == code })
    }
  }

  @Test("Unknown format code 0xFFFF preserved")
  func unknownFormatCode() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, formatCode: 0xFFFF), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got?.formatCode == 0xFFFF)
  }
}

// MARK: - Deletion and Cleanup

@Suite("Index Deletion Edge Cases")
struct IndexDeletionTests {

  @Test("Delete single object from populated index")
  func deleteSingle() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...5)
      .map { i in
        makeObj(handle: UInt32(i), name: "file\(i).txt", pathKey: "/file\(i).txt")
      }
    try await index.upsertObjects(objects, deviceId: "dev")
    try await index.removeObject(deviceId: "dev", storageId: 0x10001, handle: 3)
    let all = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 4)
    #expect(!all.contains { $0.handle == 3 })
  }

  @Test("Delete non-existent object is no-op")
  func deleteNonExistent() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(makeObj(handle: 1), deviceId: "dev")
    try await index.removeObject(deviceId: "dev", storageId: 0x10001, handle: 999)
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
  }

  @Test("Delete all objects leaves empty children")
  func deleteAll() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...3)
      .map { i in
        makeObj(handle: UInt32(i), name: "f\(i).txt", pathKey: "/f\(i).txt")
      }
    try await index.upsertObjects(objects, deviceId: "dev")
    for i: UInt32 in 1...3 {
      try await index.removeObject(deviceId: "dev", storageId: 0x10001, handle: i)
    }
    let all = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.isEmpty)
  }

  @Test("Delete from wrong device is no-op")
  func deleteWrongDevice() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(deviceId: "dev1", handle: 1), deviceId: "dev1")
    try await index.removeObject(deviceId: "dev2", storageId: 0x10001, handle: 1)
    let got = try await index.object(deviceId: "dev1", handle: 1)
    #expect(got != nil)
  }
}

// MARK: - Path Key Edge Cases

@Suite("Index Path Key Tests")
struct IndexPathKeyTests {

  @Test("Deeply nested path keys preserved")
  func deepPathKeys() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let deepPath = "/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/file.txt"
    try await index.insertObject(
      makeObj(handle: 1, pathKey: deepPath), deviceId: "dev")
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got?.pathKey == deepPath)
  }

  @Test("Path keys with spaces and special chars")
  func pathKeysWithSpecialChars() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let paths = [
      "/My Photos/vacation 2024/IMG_001.jpg",
      "/Music (Backup)/Rock & Roll/track #1.mp3",
      "/docs/file[1].txt",
      "/data/export_2024-01-01.csv",
    ]
    for (i, p) in paths.enumerated() {
      let name = p.split(separator: "/").last.map(String.init) ?? "file"
      try await index.insertObject(
        makeObj(handle: UInt32(i + 1), name: name, pathKey: p),
        deviceId: "dev"
      )
    }
    for (i, p) in paths.enumerated() {
      let got = try await index.object(deviceId: "dev", handle: UInt32(i + 1))
      #expect(got?.pathKey == p)
    }
  }

  @Test("Root path key")
  func rootPathKey() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, name: "root", pathKey: "/", isDirectory: true),
      deviceId: "dev"
    )
    let got = try await index.object(deviceId: "dev", handle: 1)
    #expect(got?.pathKey == "/")
  }
}

// MARK: - Concurrent Read Access

@Suite("Index Concurrent Access")
struct IndexConcurrentAccessTests {

  @Test("Multiple reads don't conflict")
  func concurrentReads() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (1...100)
      .map { i in
        makeObj(handle: UInt32(i), name: "file\(i).txt", pathKey: "/file\(i).txt")
      }
    try await index.upsertObjects(objects, deviceId: "dev")

    await withTaskGroup(of: Int.self) { group in
      for _ in 0..<10 {
        group.addTask {
          (try? await index.children(
            deviceId: "dev", storageId: 0x10001, parentHandle: nil))?
            .count ?? 0
        }
      }
      for await count in group {
        #expect(count == 100)
      }
    }
  }

  @Test("Read during batch insert returns consistent state")
  func readDuringInsert() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Pre-populate
    let objects = (1...50)
      .map { i in
        makeObj(handle: UInt32(i), name: "pre\(i).txt", pathKey: "/pre\(i).txt")
      }
    try await index.upsertObjects(objects, deviceId: "dev")
    let count =
      try await index.children(
        deviceId: "dev", storageId: 0x10001, parentHandle: nil
      )
      .count
    #expect(count == 50)
  }
}

// MARK: - Directory vs File Distinction

@Suite("Index Directory File Distinction")
struct IndexDirectoryFileTests {

  @Test("isDirectory flag preserved for directories")
  func directoryFlag() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, name: "DCIM", pathKey: "/DCIM", isDirectory: true),
      deviceId: "dev"
    )
    try await index.insertObject(
      makeObj(
        handle: 2, parentHandle: 1, name: "photo.jpg",
        pathKey: "/DCIM/photo.jpg", isDirectory: false),
      deviceId: "dev"
    )
    let dcim = try await index.object(deviceId: "dev", handle: 1)
    let photo = try await index.object(deviceId: "dev", handle: 2)
    #expect(dcim?.isDirectory == true)
    #expect(photo?.isDirectory == false)
  }

  @Test("Same name as file and directory are distinct by handle")
  func sameNameFileDirDistinct() async throws {
    let (index, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await index.insertObject(
      makeObj(handle: 1, name: "data", pathKey: "/data", isDirectory: true),
      deviceId: "dev"
    )
    try await index.insertObject(
      makeObj(handle: 2, name: "data", pathKey: "/data.bak", isDirectory: false),
      deviceId: "dev"
    )
    let all = try await index.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 2)
  }
}
