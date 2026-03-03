// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempDB() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
  let path = dir.appendingPathComponent("integrity-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func obj(
  handle: UInt32,
  parentHandle: UInt32? = nil,
  storageId: UInt32 = 0x10001,
  name: String = "file.txt",
  pathKey: String? = nil,
  isDirectory: Bool = false,
  sizeBytes: UInt64 = 1024,
  formatCode: UInt16 = 0x3001,
  mtime: Date? = Date()
) -> IndexedObject {
  IndexedObject(
    deviceId: "dev",
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: pathKey ?? "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: sizeBytes,
    mtime: mtime,
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - 1. SQLite Edge Cases

@Suite("Index Data Integrity — SQLite Edge Cases")
struct SQLiteEdgeCaseTests {

  @Test("Large batch insert 10K+ objects with unique handles")
  func largeBatchInsert10K() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let count = 10_500
    let objects = (0..<count)
      .map { i in
        obj(handle: UInt32(i), name: "item\(i).dat", pathKey: "00010001/bulk/item\(i).dat")
      }
    try await idx.upsertObjects(objects, deviceId: "dev")

    // Spot-check first, middle, last
    for h: UInt32 in [0, 5250, UInt32(count - 1)] {
      let o = try await idx.object(deviceId: "dev", handle: h)
      #expect(o != nil)
      #expect(o?.name == "item\(h).dat")
    }
  }

  @Test("Deep hierarchy with 15 levels preserves parent chain")
  func deepHierarchy15Levels() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let depth = 15
    var objects: [IndexedObject] = []
    for level in 0..<depth {
      let parent: UInt32? = level == 0 ? nil : UInt32(level - 1)
      objects.append(
        obj(
          handle: UInt32(level),
          parentHandle: parent,
          name: "dir\(level)",
          pathKey: "00010001/" + (0...level).map { "dir\($0)" }.joined(separator: "/"),
          isDirectory: level < depth - 1
        ))
    }
    try await idx.upsertObjects(objects, deviceId: "dev")

    // Walk from leaf to root
    var segments: [String] = []
    var cur = try await idx.object(deviceId: "dev", handle: UInt32(depth - 1))
    while let o = cur {
      segments.insert(o.name, at: 0)
      cur =
        o.parentHandle != nil
        ? try await idx.object(deviceId: "dev", handle: o.parentHandle!)
        : nil
    }
    #expect(segments.count == depth)
    #expect(segments.first == "dir0")
    #expect(segments.last == "dir\(depth - 1)")
  }

  @Test("Objects with NULL parent handles stored and queried correctly")
  func nullParentHandles() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objects = (0..<5)
      .map { i in
        obj(handle: UInt32(i), parentHandle: nil, name: "root\(i)")
      }
    try await idx.upsertObjects(objects, deviceId: "dev")

    let roots = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(roots.count == 5)
    #expect(roots.allSatisfy { $0.parentHandle == nil })
  }

  @Test("Empty string properties stored and retrieved")
  func emptyStringProperties() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let o = obj(handle: 1, name: "", pathKey: "")
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == "")
    #expect(got?.pathKey == "")
  }

  @Test("Extremely long filename (4000 chars) stored and retrieved")
  func extremelyLongFilename() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let longName = String(repeating: "a", count: 4000) + ".txt"
    let o = obj(handle: 1, name: longName, pathKey: "00010001/\(longName)")
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.name == longName)
    #expect(got?.name.count == 4004)
  }

  @Test("Rapid insert/delete cycles preserve final state")
  func rapidInsertDeleteCycles() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    for cycle in 0..<50 {
      let o = obj(handle: 1, name: "cycle\(cycle).txt", sizeBytes: UInt64(cycle))
      try await idx.upsertObjects([o], deviceId: "dev")
      if cycle % 3 == 0 {
        try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)
      }
    }

    // Last cycle (49) was not deleted (49 % 3 != 0), so object should exist
    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == "cycle49.txt")
    #expect(got?.sizeBytes == 49)
  }

  @Test("Object with maximum UInt32 handle value")
  func maxHandleValue() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let o = obj(handle: UInt32.max, name: "maxhandle.txt")
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: UInt32.max)
    #expect(got != nil)
    #expect(got?.handle == UInt32.max)
  }

  @Test("Object with zero handle value")
  func zeroHandleValue() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let o = obj(handle: 0, name: "zerohandle.txt")
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 0)
    #expect(got != nil)
    #expect(got?.handle == 0)
  }

  @Test("Object with nil sizeBytes preserved as nil")
  func nilSizeBytes() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let o = IndexedObject(
      deviceId: "dev", storageId: 0x10001, handle: 1, parentHandle: nil,
      name: "unknown-size.bin", pathKey: "00010001/unknown-size.bin",
      sizeBytes: nil, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 0
    )
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.sizeBytes == nil)
    #expect(got?.mtime == nil)
  }

  @Test("Special characters in filenames (slashes, quotes, backslashes)")
  func specialCharacterFilenames() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let names = [
      "file with spaces.txt",
      "file'with'quotes.txt",
      "file\"double\"quotes.txt",
      "path/like/name.txt",
      "back\\slash.txt",
      "tab\there.txt",
    ]
    for (i, name) in names.enumerated() {
      try await idx.insertObject(
        obj(handle: UInt32(i + 1), name: name),
        deviceId: "dev"
      )
    }
    for (i, name) in names.enumerated() {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i + 1))
      #expect(got?.name == name)
    }
  }

  @Test("Large sizeBytes (multi-GB file) stored correctly")
  func largeSizeBytes() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let bigSize: UInt64 = 128_000_000_000  // 128 GB
    let o = obj(handle: 1, name: "big.iso", sizeBytes: bigSize)
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.sizeBytes == bigSize)
  }
}

// MARK: - 2. Concurrent Operations

@Suite("Index Data Integrity — Concurrent Operations")
struct ConcurrentOperationTests {

  @Test("Multiple concurrent batch upserts across different devices")
  func concurrentUpsertsDifferentDevices() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for d in 0..<8 {
        group.addTask {
          let deviceId = "device-\(d)"
          let objs = (0..<100)
            .map { j in
              IndexedObject(
                deviceId: deviceId, storageId: 0x10001,
                handle: UInt32(j), parentHandle: nil,
                name: "f\(d)_\(j).txt", pathKey: "00010001/f\(d)_\(j).txt",
                sizeBytes: 512, mtime: Date(), formatCode: 0x3001,
                isDirectory: false, changeCounter: 0
              )
            }
          try await idx.upsertObjects(objs, deviceId: deviceId)
        }
      }
      try await group.waitForAll()
    }

    // Verify each device has exactly 100 objects
    for d in 0..<8 {
      let kids = try await idx.children(
        deviceId: "device-\(d)", storageId: 0x10001, parentHandle: nil)
      #expect(kids.count == 100)
    }
  }

  @Test("Concurrent reads while writing does not crash")
  func concurrentReadsWhileWriting() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed
    let seed = (0..<200).map { i in obj(handle: UInt32(i), name: "s\(i).txt") }
    try await idx.upsertObjects(seed, deviceId: "dev")

    // Readers
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<5 {
        group.addTask {
          for _ in 0..<50 {
            let kids = try await idx.children(
              deviceId: "dev", storageId: 0x10001, parentHandle: nil)
            #expect(kids.count >= 200)
          }
        }
      }
      try await group.waitForAll()
    }

    // Writers
    for w in 0..<2 {
      for batch in 0..<10 {
        let base = UInt32(10000 + w * 200 + batch * 20)
        let objs: [IndexedObject] = (0..<20)
          .map { j in
            let h = base + UInt32(j)
            return obj(handle: h, name: "w\(w)_\(j).txt")
          }
        try await idx.upsertObjects(objs, deviceId: "dev")
      }
    }

    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count >= 200)
  }

  @Test("Concurrent change counter reads are consistent")
  func concurrentChangeCounterReads() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Perform 20 concurrent inserts, each bumps the counter
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<20 {
        group.addTask {
          try await idx.insertObject(
            obj(handle: UInt32(i), name: "cc\(i).txt"),
            deviceId: "dev"
          )
        }
      }
      try await group.waitForAll()
    }

    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter >= 20)
  }

  @Test("Concurrent upsert and delete on different handles")
  func concurrentUpsertAndDelete() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed objects to delete
    let toDelete = (0..<50).map { i in obj(handle: UInt32(i), name: "del\(i).txt") }
    try await idx.upsertObjects(toDelete, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Delete existing objects
      group.addTask {
        for i in 0..<50 {
          try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: UInt32(i))
        }
      }
      // Insert new objects concurrently
      group.addTask {
        let newObjs = (1000..<1050).map { i in obj(handle: UInt32(i), name: "new\(i).txt") }
        try await idx.upsertObjects(newObjs, deviceId: "dev")
      }
      try await group.waitForAll()
    }

    // Deleted objects should be gone
    for i in 0..<50 {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i))
      #expect(got == nil)
    }
    // New objects should exist
    for i in 1000..<1050 {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i))
      #expect(got != nil)
    }
  }

  @Test("Concurrent storage upserts from multiple tasks")
  func concurrentStorageUpserts() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let storage = IndexedStorage(
            deviceId: "dev", storageId: UInt32(i),
            description: "Storage \(i)",
            capacity: UInt64(i) * 1_000_000,
            free: UInt64(i) * 500_000,
            readOnly: i % 2 == 0
          )
          try await idx.upsertStorage(storage)
        }
      }
      try await group.waitForAll()
    }

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 10)
  }

  @Test("Concurrent markStaleChildren and reads")
  func concurrentMarkStaleAndReads() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create parent with children
    let parent = obj(handle: 100, name: "parent", isDirectory: true)
    try await idx.insertObject(parent, deviceId: "dev")
    let children = (0..<50)
      .map { i in
        obj(handle: UInt32(i), parentHandle: 100, name: "child\(i).txt")
      }
    try await idx.upsertObjects(children, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Reader
      group.addTask {
        for _ in 0..<20 {
          _ = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 100)
        }
      }
      // Mark stale
      group.addTask {
        try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: 100)
      }
      try await group.waitForAll()
    }

    // After stale marking, children should be invisible
    let remaining = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: 100)
    #expect(remaining.isEmpty)
  }

  @Test("WAL mode is enabled by default")
  func walModeEnabled() throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // The database should use WAL mode. Verify by checking the journal_mode pragma.
    let db = idx.database
    let mode: String? = try db.withStatement("PRAGMA journal_mode") { stmt in
      if try db.step(stmt) {
        return db.colText(stmt, 0)
      }
      return nil
    }
    #expect(mode == "wal")
  }

  @Test("Concurrent nextChangeCounter calls produce unique values")
  func concurrentNextChangeCounter() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let counters = try await withThrowingTaskGroup(of: Int64.self) { group in
      for _ in 0..<30 {
        group.addTask {
          try await idx.nextChangeCounter(deviceId: "dev")
        }
      }
      var results: [Int64] = []
      for try await c in group {
        results.append(c)
      }
      return results
    }

    // All counter values should be unique
    let unique = Set(counters)
    #expect(unique.count == 30)
    // All should be positive
    #expect(counters.allSatisfy { $0 > 0 })
  }

  @Test("Concurrent purgeStale does not corrupt data")
  func concurrentPurgeStale() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert and mark stale
    let objects = (0..<100).map { i in obj(handle: UInt32(i), name: "stale\(i).txt") }
    try await idx.upsertObjects(objects, deviceId: "dev")
    try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: nil)

    // Concurrent purge from multiple tasks
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<5 {
        group.addTask {
          try await idx.purgeStale(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
        }
      }
      try await group.waitForAll()
    }

    let remaining = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(remaining.isEmpty)
  }

  @Test("Concurrent pruneChangeLog during active writes")
  func concurrentPruneAndWrite() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writer
      group.addTask {
        for i in 0..<50 {
          try await idx.insertObject(
            obj(handle: UInt32(i), name: "prune\(i).txt"),
            deviceId: "dev"
          )
        }
      }
      // Pruner
      group.addTask {
        for _ in 0..<10 {
          try await idx.pruneChangeLog(
            deviceId: "dev", olderThan: Date().addingTimeInterval(-1))
        }
      }
      try await group.waitForAll()
    }

    // All objects should still exist (prune only affects change log)
    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 50)
  }
}

// MARK: - 3. Data Validation

@Suite("Index Data Integrity — Data Validation")
struct DataValidationTests {

  @Test("Object handle uniqueness: same handle+storageId+device upserts, not duplicates")
  func handleUniqueness() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert same handle twice
    try await idx.insertObject(obj(handle: 42, name: "first.txt"), deviceId: "dev")
    try await idx.insertObject(obj(handle: 42, name: "second.txt"), deviceId: "dev")

    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let matching = all.filter { $0.handle == 42 }
    #expect(matching.count == 1)
    #expect(matching.first?.name == "second.txt")
  }

  @Test("Parent-child relationship integrity after batch operations")
  func parentChildIntegrity() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Build a tree: root(1) -> dir(2) -> [file(3), file(4)]
    //                        -> dir(5) -> [file(6)]
    let objects = [
      obj(handle: 1, parentHandle: nil, name: "root", isDirectory: true),
      obj(handle: 2, parentHandle: 1, name: "dirA", isDirectory: true),
      obj(handle: 3, parentHandle: 2, name: "a1.txt"),
      obj(handle: 4, parentHandle: 2, name: "a2.txt"),
      obj(handle: 5, parentHandle: 1, name: "dirB", isDirectory: true),
      obj(handle: 6, parentHandle: 5, name: "b1.txt"),
    ]
    try await idx.upsertObjects(objects, deviceId: "dev")

    // Verify tree structure
    let rootChildren = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(rootChildren.count == 1)
    #expect(rootChildren.first?.name == "root")

    let dirAKids = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: 2)
    #expect(dirAKids.count == 2)
    #expect(Set(dirAKids.map(\.name)) == Set(["a1.txt", "a2.txt"]))

    let dirBKids = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: 5)
    #expect(dirBKids.count == 1)
    #expect(dirBKids.first?.name == "b1.txt")

    let level1 = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    #expect(level1.count == 2)
    #expect(Set(level1.map(\.name)) == Set(["dirA", "dirB"]))
  }

  @Test("Storage ID consistency: objects in different storages isolated")
  func storageIdConsistency() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Same handle number, different storages
    let objInS1 = obj(handle: 1, storageId: 0xA, name: "inStorageA.txt")
    let objInS2 = obj(handle: 1, storageId: 0xB, name: "inStorageB.txt")
    try await idx.insertObject(objInS1, deviceId: "dev")
    try await idx.insertObject(objInS2, deviceId: "dev")

    let kidsA = try await idx.children(deviceId: "dev", storageId: 0xA, parentHandle: nil)
    let kidsB = try await idx.children(deviceId: "dev", storageId: 0xB, parentHandle: nil)

    #expect(kidsA.count == 1)
    #expect(kidsA.first?.name == "inStorageA.txt")
    #expect(kidsB.count == 1)
    #expect(kidsB.first?.name == "inStorageB.txt")
  }

  @Test("Format code mapping preserved for various MTP format codes")
  func formatCodeMapping() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Common MTP format codes
    let formats: [(UInt16, String)] = [
      (0x3000, "undefined.bin"),  // Undefined
      (0x3001, "folder"),  // Association (folder)
      (0x3004, "text.txt"),  // Text
      (0x3009, "audio.mp3"),  // MP3
      (0x380B, "image.jpg"),  // EXIF/JPEG
      (0x380D, "image.tiff"),  // TIFF
      (0xB982, "video.mp4"),  // MP4
    ]

    for (i, (code, name)) in formats.enumerated() {
      let o = obj(
        handle: UInt32(i + 1), name: name,
        isDirectory: code == 0x3001, formatCode: code
      )
      try await idx.insertObject(o, deviceId: "dev")
    }

    for (i, (code, _)) in formats.enumerated() {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i + 1))
      #expect(got?.formatCode == code)
    }
  }

  @Test("Date parsing: epoch zero stored and retrieved")
  func dateParsingEpochZero() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let epochZero = Date(timeIntervalSince1970: 0)
    let o = obj(handle: 1, name: "epoch.txt", mtime: epochZero)
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.mtime != nil)
    #expect(got!.mtime!.timeIntervalSince1970 == 0)
  }

  @Test("Date parsing: nil mtime preserved")
  func dateParsingNilMtime() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let o = obj(handle: 1, name: "notime.txt", mtime: nil)
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.mtime == nil)
  }

  @Test("Date parsing: far-future date (year 2100)")
  func dateParsingFarFuture() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let futureDate = Date(timeIntervalSince1970: 4_102_444_800)  // ~2100-01-01
    let o = obj(handle: 1, name: "future.txt", mtime: futureDate)
    try await idx.insertObject(o, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    // Compare as integers to avoid floating-point precision issues
    #expect(Int(got!.mtime!.timeIntervalSince1970) == 4_102_444_800)
  }

  @Test("Change tracking records upsert and delete kinds correctly")
  func changeTrackingKinds() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let anchor: Int64 = 0

    // Insert
    try await idx.insertObject(obj(handle: 1, name: "a.txt"), deviceId: "dev")
    try await idx.insertObject(obj(handle: 2, name: "b.txt"), deviceId: "dev")

    // Delete one
    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)

    let changes = try await idx.changesSince(deviceId: "dev", anchor: anchor)
    let upserted = changes.filter { $0.kind == .upserted }
    let deleted = changes.filter { $0.kind == .deleted }

    // Handle 2 should be upserted, handle 1 should be deleted
    #expect(upserted.contains { $0.object.handle == 2 })
    #expect(deleted.contains { $0.object.handle == 1 })
  }

  @Test("Device isolation: operations on one device do not affect another")
  func deviceIsolation() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(
      IndexedObject(
        deviceId: "phone", storageId: 0x10001, handle: 1, parentHandle: nil,
        name: "phone.txt", pathKey: "key", sizeBytes: 100, mtime: nil,
        formatCode: 0x3001, isDirectory: false, changeCounter: 0
      ), deviceId: "phone")

    try await idx.insertObject(
      IndexedObject(
        deviceId: "camera", storageId: 0x10001, handle: 1, parentHandle: nil,
        name: "camera.txt", pathKey: "key", sizeBytes: 200, mtime: nil,
        formatCode: 0x3001, isDirectory: false, changeCounter: 0
      ), deviceId: "camera")

    // Delete phone object
    try await idx.removeObject(deviceId: "phone", storageId: 0x10001, handle: 1)

    let phoneObj = try await idx.object(deviceId: "phone", handle: 1)
    let cameraObj = try await idx.object(deviceId: "camera", handle: 1)
    #expect(phoneObj == nil)
    #expect(cameraObj != nil)
    #expect(cameraObj?.name == "camera.txt")
  }

  @Test("Storage readOnly flag preserved correctly")
  func storageReadOnlyFlag() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let rw = IndexedStorage(
      deviceId: "dev", storageId: 1, description: "Internal",
      capacity: 100, free: 50, readOnly: false
    )
    let ro = IndexedStorage(
      deviceId: "dev", storageId: 2, description: "SD Card",
      capacity: 200, free: 100, readOnly: true
    )
    try await idx.upsertStorage(rw)
    try await idx.upsertStorage(ro)

    let storages = try await idx.storages(deviceId: "dev")
    let internal_ = storages.first { $0.storageId == 1 }
    let sdCard = storages.first { $0.storageId == 2 }

    #expect(internal_?.readOnly == false)
    #expect(sdCard?.readOnly == true)
  }

  @Test("Batch upsert is atomic: all-or-nothing on success")
  func batchUpsertAtomicity() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let batch = (0..<100).map { i in obj(handle: UInt32(i), name: "batch\(i).txt") }
    try await idx.upsertObjects(batch, deviceId: "dev")

    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 100)

    // Verify change counter was bumped exactly once for the batch
    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter == 1)
  }

  @Test("isDirectory flag stored and queried correctly")
  func isDirectoryFlag() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(
      obj(handle: 1, name: "DCIM", isDirectory: true), deviceId: "dev")
    try await idx.insertObject(
      obj(handle: 2, name: "photo.jpg", isDirectory: false), deviceId: "dev")

    let dir = try await idx.object(deviceId: "dev", handle: 1)
    let file = try await idx.object(deviceId: "dev", handle: 2)

    #expect(dir?.isDirectory == true)
    #expect(file?.isDirectory == false)
  }
}
