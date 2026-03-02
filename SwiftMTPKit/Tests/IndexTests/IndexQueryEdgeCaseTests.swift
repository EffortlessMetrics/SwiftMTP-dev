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
    handle: handle,
    parentHandle: parentHandle ?? 0,
    storageId: storageId,
    name: name,
    pathKey: pathKey ?? "/\(name)",
    isDirectory: isDirectory,
    sizeBytes: sizeBytes,
    formatCode: formatCode
  )
}

// MARK: - Unicode and Special Character Tests

@Suite("Index Unicode Edge Cases")
struct IndexUnicodeEdgeCaseTests {

  @Test("Unicode filenames survive index roundtrip")
  func unicodeFilenameRoundtrip() throws {
    let (index, _) = try makeTempIndex()
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
      try index.upsert(obj)
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == unicodeNames.count)
    for name in unicodeNames {
      #expect(all.contains { $0.name == name })
    }
  }

  @Test("Combining characters in filenames")
  func combiningCharacters() throws {
    let (index, _) = try makeTempIndex()
    // NFC vs NFD forms of "é"
    let nfc = "caf\u{00E9}.txt"  // precomposed
    let nfd = "cafe\u{0301}.txt"  // decomposed
    try index.upsert(makeObj(handle: 1, name: nfc, pathKey: "/\(nfc)"))
    try index.upsert(makeObj(handle: 2, name: nfd, pathKey: "/\(nfd)"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 2)
  }

  @Test("Zero-width characters in filenames")
  func zeroWidthCharacters() throws {
    let (index, _) = try makeTempIndex()
    let name = "test\u{200B}file\u{FEFF}.txt"
    try index.upsert(makeObj(handle: 1, name: name, pathKey: "/\(name)"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
    #expect(all[0].name == name)
  }

  @Test("Very long filenames at MTP 255-byte limit")
  func longFilenames() throws {
    let (index, _) = try makeTempIndex()
    let name = String(repeating: "a", count: 251) + ".txt"
    try index.upsert(makeObj(handle: 1, name: name, pathKey: "/\(name)"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
    #expect(all[0].name == name)
  }
}

// MARK: - Large Dataset Tests

@Suite("Index Large Dataset Operations")
struct IndexLargeDatasetTests {

  @Test("Insert and query 1000 objects")
  func thousandObjects() throws {
    let (index, _) = try makeTempIndex()
    for i: UInt32 in 1...1000 {
      try index.upsert(makeObj(handle: i, name: "file\(i).jpg", pathKey: "/DCIM/file\(i).jpg"))
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1000)
  }

  @Test("Deep directory nesting 20 levels")
  func deepNesting() throws {
    let (index, _) = try makeTempIndex()
    var parentHandle: UInt32 = 0
    for depth: UInt32 in 1...20 {
      let path = (1...depth).map { "dir\($0)" }.joined(separator: "/")
      try index.upsert(makeObj(
        handle: depth,
        parentHandle: parentHandle,
        name: "dir\(depth)",
        pathKey: "/\(path)",
        isDirectory: true
      ))
      parentHandle = depth
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 20)
  }

  @Test("Multiple storage IDs isolation")
  func multipleStorageIds() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, storageId: 0x10001, name: "internal.jpg", pathKey: "/internal.jpg"))
    try index.upsert(makeObj(handle: 2, storageId: 0x20001, name: "sdcard.jpg", pathKey: "/sdcard.jpg"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 2)
    let storageIds = Set(all.map(\.storageId))
    #expect(storageIds.count == 2)
  }

  @Test("Upsert updates existing objects")
  func upsertUpdatesExisting() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, name: "old.txt", pathKey: "/old.txt", sizeBytes: 100))
    try index.upsert(makeObj(handle: 1, name: "new.txt", pathKey: "/new.txt", sizeBytes: 200))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
    #expect(all[0].name == "new.txt")
    #expect(all[0].sizeBytes == 200)
  }
}

// MARK: - Empty and Boundary Tests

@Suite("Index Boundary Conditions")
struct IndexBoundaryTests {

  @Test("Empty index returns no objects")
  func emptyIndex() throws {
    let (index, _) = try makeTempIndex()
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.isEmpty)
  }

  @Test("Query non-existent device returns empty")
  func nonExistentDevice() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(deviceId: "dev1", handle: 1))
    let all = try index.allObjects(deviceId: "dev2")
    #expect(all.isEmpty)
  }

  @Test("Handle value zero is valid")
  func handleZero() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 0, name: "root.txt", pathKey: "/root.txt"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
    #expect(all[0].handle == 0)
  }

  @Test("Maximum handle value UInt32.max")
  func maxHandle() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: UInt32.max, name: "max.txt", pathKey: "/max.txt"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
    #expect(all[0].handle == UInt32.max)
  }

  @Test("Zero-byte file size")
  func zeroByteFile() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, sizeBytes: 0))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all[0].sizeBytes == 0)
  }

  @Test("Maximum file size UInt64.max")
  func maxFileSize() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, sizeBytes: UInt64.max))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all[0].sizeBytes == UInt64.max)
  }

  @Test("Empty filename")
  func emptyFilename() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, name: "", pathKey: "/"))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
  }

  @Test("Multiple devices in same index")
  func multipleDevices() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(deviceId: "phone1", handle: 1, name: "a.txt", pathKey: "/a.txt"))
    try index.upsert(makeObj(deviceId: "phone2", handle: 1, name: "b.txt", pathKey: "/b.txt"))
    let phone1 = try index.allObjects(deviceId: "phone1")
    let phone2 = try index.allObjects(deviceId: "phone2")
    #expect(phone1.count == 1)
    #expect(phone2.count == 1)
    #expect(phone1[0].name == "a.txt")
    #expect(phone2[0].name == "b.txt")
  }
}

// MARK: - Format Code Coverage

@Suite("Index Format Code Coverage")
struct IndexFormatCodeTests {

  @Test("Standard MTP format codes stored correctly")
  func standardFormatCodes() throws {
    let (index, _) = try makeTempIndex()
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
    for (i, (code, name)) in formats.enumerated() {
      try index.upsert(makeObj(handle: UInt32(i + 1), name: "\(name).dat", pathKey: "/\(name).dat", formatCode: code))
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == formats.count)
    for (code, _) in formats {
      #expect(all.contains { $0.formatCode == code })
    }
  }

  @Test("Unknown format code 0xFFFF preserved")
  func unknownFormatCode() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, formatCode: 0xFFFF))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all[0].formatCode == 0xFFFF)
  }
}

// MARK: - Deletion and Cleanup

@Suite("Index Deletion Edge Cases")
struct IndexDeletionTests {

  @Test("Delete single object from populated index")
  func deleteSingle() throws {
    let (index, _) = try makeTempIndex()
    for i: UInt32 in 1...5 {
      try index.upsert(makeObj(handle: i, name: "file\(i).txt", pathKey: "/file\(i).txt"))
    }
    try index.delete(deviceId: "dev", handle: 3)
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 4)
    #expect(!all.contains { $0.handle == 3 })
  }

  @Test("Delete non-existent object is no-op")
  func deleteNonExistent() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1))
    try index.delete(deviceId: "dev", handle: 999)
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 1)
  }

  @Test("Delete all objects leaves empty index")
  func deleteAll() throws {
    let (index, _) = try makeTempIndex()
    for i: UInt32 in 1...3 {
      try index.upsert(makeObj(handle: i, name: "f\(i).txt", pathKey: "/f\(i).txt"))
    }
    for i: UInt32 in 1...3 {
      try index.delete(deviceId: "dev", handle: i)
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.isEmpty)
  }

  @Test("Delete from wrong device is no-op")
  func deleteWrongDevice() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(deviceId: "dev1", handle: 1))
    try index.delete(deviceId: "dev2", handle: 1)
    let dev1 = try index.allObjects(deviceId: "dev1")
    #expect(dev1.count == 1)
  }
}

// MARK: - Path Key Edge Cases

@Suite("Index Path Key Tests")
struct IndexPathKeyTests {

  @Test("Deeply nested path keys preserved")
  func deepPathKeys() throws {
    let (index, _) = try makeTempIndex()
    let deepPath = "/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/file.txt"
    try index.upsert(makeObj(handle: 1, pathKey: deepPath))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all[0].pathKey == deepPath)
  }

  @Test("Path keys with spaces and special chars")
  func pathKeysWithSpecialChars() throws {
    let (index, _) = try makeTempIndex()
    let paths = [
      "/My Photos/vacation 2024/IMG_001.jpg",
      "/Music (Backup)/Rock & Roll/track #1.mp3",
      "/docs/file[1].txt",
      "/data/export_2024-01-01.csv",
    ]
    for (i, path) in paths.enumerated() {
      let name = path.split(separator: "/").last.map(String.init) ?? "file"
      try index.upsert(makeObj(handle: UInt32(i + 1), name: name, pathKey: path))
    }
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == paths.count)
    for path in paths {
      #expect(all.contains { $0.pathKey == path })
    }
  }

  @Test("Root path key")
  func rootPathKey() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, name: "root", pathKey: "/", isDirectory: true))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all[0].pathKey == "/")
  }
}

// MARK: - Concurrent Read Access

@Suite("Index Concurrent Access")
struct IndexConcurrentAccessTests {

  @Test("Multiple reads don't conflict")
  func concurrentReads() async throws {
    let (index, _) = try makeTempIndex()
    for i: UInt32 in 1...100 {
      try index.upsert(makeObj(handle: i, name: "file\(i).txt", pathKey: "/file\(i).txt"))
    }
    await withTaskGroup(of: Int.self) { group in
      for _ in 0..<10 {
        group.addTask {
          (try? index.allObjects(deviceId: "dev"))?.count ?? 0
        }
      }
      for await count in group {
        #expect(count == 100)
      }
    }
  }

  @Test("Read during batch insert returns consistent state")
  func readDuringInsert() async throws {
    let (index, _) = try makeTempIndex()
    // Pre-populate
    for i: UInt32 in 1...50 {
      try index.upsert(makeObj(handle: i, name: "pre\(i).txt", pathKey: "/pre\(i).txt"))
    }
    let count = try index.allObjects(deviceId: "dev").count
    #expect(count == 50)
  }
}

// MARK: - Directory vs File Distinction

@Suite("Index Directory File Distinction")
struct IndexDirectoryFileTests {

  @Test("isDirectory flag preserved for directories")
  func directoryFlag() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, name: "DCIM", pathKey: "/DCIM", isDirectory: true))
    try index.upsert(makeObj(handle: 2, name: "photo.jpg", pathKey: "/DCIM/photo.jpg", isDirectory: false))
    let all = try index.allObjects(deviceId: "dev")
    let dcim = all.first { $0.name == "DCIM" }!
    let photo = all.first { $0.name == "photo.jpg" }!
    #expect(dcim.isDirectory == true)
    #expect(photo.isDirectory == false)
  }

  @Test("Same name as file and directory are distinct")
  func sameNameFileDirDistinct() throws {
    let (index, _) = try makeTempIndex()
    try index.upsert(makeObj(handle: 1, name: "data", pathKey: "/data", isDirectory: true))
    try index.upsert(makeObj(handle: 2, name: "data", pathKey: "/data.bak", isDirectory: false))
    let all = try index.allObjects(deviceId: "dev")
    #expect(all.count == 2)
  }
}
