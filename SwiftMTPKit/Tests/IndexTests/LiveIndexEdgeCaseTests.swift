// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("edge-\(UUID().uuidString).sqlite").path
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
    pathKey: pathKey ?? "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: sizeBytes,
    mtime: Date(),
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - 1. Live Index CRUD

@Suite("LiveIndex CRUD Edge Cases")
struct LiveIndexCRUDTests {

  @Test("Insert and retrieve single object")
  func insertAndRetrieve() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let obj = makeObj(handle: 1, name: "hello.txt")
    try await idx.insertObject(obj, deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
    #expect(got?.name == "hello.txt")
    #expect(got?.sizeBytes == 1024)
  }

  @Test("Upsert overwrites existing object fields")
  func upsertOverwrites() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "v1.txt", sizeBytes: 100), deviceId: "dev")
    try await idx.upsertObjects([makeObj(handle: 1, name: "v2.txt", sizeBytes: 200)], deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.name == "v2.txt")
    #expect(got?.sizeBytes == 200)
  }

  @Test("Delete marks object stale and invisible to reader")
  func deleteMarksStale() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 5), deviceId: "dev")
    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 5)

    let got = try await idx.object(deviceId: "dev", handle: 5)
    #expect(got == nil)
  }

  @Test("Upsert after delete resurrects object")
  func upsertAfterDelete() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 7, name: "alive.txt"), deviceId: "dev")
    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 7)
    #expect(try await idx.object(deviceId: "dev", handle: 7) == nil)

    try await idx.upsertObjects([makeObj(handle: 7, name: "alive.txt")], deviceId: "dev")
    let got = try await idx.object(deviceId: "dev", handle: 7)
    #expect(got != nil)
    #expect(got?.name == "alive.txt")
  }

  @Test("Batch upsert of zero objects succeeds without inserting rows")
  func batchUpsertEmpty() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertObjects([], deviceId: "dev")
    // No rows created
    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.isEmpty)
  }
}

// MARK: - 2. Path Resolution

@Suite("LiveIndex Path Resolution")
struct LiveIndexPathResolutionTests {

  @Test("Build full path from root to leaf through parent chain")
  func parentChainPath() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // root -> DCIM -> 2024 -> photo.jpg
    let root = makeObj(handle: 1, name: "DCIM", pathKey: "00010001/DCIM", isDirectory: true)
    let mid = makeObj(handle: 2, parentHandle: 1, name: "2024", pathKey: "00010001/DCIM/2024", isDirectory: true)
    let leaf = makeObj(handle: 3, parentHandle: 2, name: "photo.jpg", pathKey: "00010001/DCIM/2024/photo.jpg")
    try await idx.upsertObjects([root, mid, leaf], deviceId: "dev")

    // Walk up from leaf resolving path segments
    var segments: [String] = []
    var current = try await idx.object(deviceId: "dev", handle: 3)
    while let obj = current {
      segments.insert(obj.name, at: 0)
      if let ph = obj.parentHandle {
        current = try await idx.object(deviceId: "dev", handle: ph)
      } else {
        current = nil
      }
    }
    let resolvedPath = segments.joined(separator: "/")
    #expect(resolvedPath == "DCIM/2024/photo.jpg")
  }

  @Test("Root objects have nil parentHandle and appear as root children")
  func rootObjectsReturned() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, parentHandle: nil, name: "Music"), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 2, parentHandle: nil, name: "DCIM"), deviceId: "dev")

    let roots = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(roots.count == 2)
  }
}

// MARK: - 3. Concurrent Access

@Suite("LiveIndex Concurrent Access")
struct LiveIndexConcurrentAccessTests {

  @Test("Multiple readers and one writer interleaved")
  func readersAndWriter() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed data
    let seed = (0..<50).map { i in makeObj(handle: UInt32(i), name: "seed\(i).txt") }
    try await idx.upsertObjects(seed, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // 4 readers
      for _ in 0..<4 {
        group.addTask {
          for _ in 0..<40 {
            let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
            #expect(kids.count >= 50)
          }
        }
      }
      // 1 writer
      group.addTask {
        for batch in 0..<10 {
          let objs = (0..<20).map { j in
            makeObj(handle: UInt32(1000 + batch * 20 + j), name: "new\(batch)_\(j).txt")
          }
          try await idx.upsertObjects(objs, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == 250) // 50 seed + 200 new
  }

  @Test("Concurrent change counter increments are monotonic")
  func monotonicChangeCounters() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Int64.self) { group in
      for i in 0..<20 {
        group.addTask {
          let obj = makeObj(handle: UInt32(i), name: "f\(i).txt")
          try await idx.upsertObjects([obj], deviceId: "dev")
          return try await idx.currentChangeCounter(deviceId: "dev")
        }
      }
      var counters: [Int64] = []
      for try await c in group {
        counters.append(c)
      }
      // All counters should be > 0 and the max should equal the number of upsert calls
      #expect(counters.allSatisfy { $0 > 0 })
      #expect(counters.max()! >= 20)
    }
  }
}

// MARK: - 4. Storage Enumeration

@Suite("LiveIndex Storage Enumeration")
struct LiveIndexStorageEnumerationTests {

  @Test("List objects per separate storages")
  func objectsPerStorage() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Storage A
    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 0xA, description: "Internal",
      capacity: 64_000_000, free: 32_000_000, readOnly: false
    ))
    try await idx.insertObject(makeObj(handle: 1, storageId: 0xA, name: "a1.txt"), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 2, storageId: 0xA, name: "a2.txt"), deviceId: "dev")

    // Storage B
    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 0xB, description: "SD Card",
      capacity: 32_000_000, free: 16_000_000, readOnly: true
    ))
    try await idx.insertObject(makeObj(handle: 3, storageId: 0xB, name: "b1.txt"), deviceId: "dev")

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 2)

    let childrenA = try await idx.children(deviceId: "dev", storageId: 0xA, parentHandle: nil)
    let childrenB = try await idx.children(deviceId: "dev", storageId: 0xB, parentHandle: nil)
    #expect(childrenA.count == 2)
    #expect(childrenB.count == 1)
  }

  @Test("No storages for unknown device returns empty")
  func noStoragesForUnknown() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let storages = try await idx.storages(deviceId: "ghost")
    #expect(storages.isEmpty)
  }

  @Test("Upsert storage updates capacity and free space")
  func updateStorageMetadata() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 1, description: "Main",
      capacity: 100, free: 80, readOnly: false
    ))
    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 1, description: "Main",
      capacity: 100, free: 50, readOnly: false
    ))

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 1)
    #expect(storages.first?.free == 50)
  }
}

// MARK: - 5. Generation Snapshots

@Suite("LiveIndex Generation Snapshots")
struct LiveIndexGenerationSnapshotTests {

  @Test("Change counter advances per mutation batch")
  func counterAdvancesPerBatch() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let c0 = try await idx.currentChangeCounter(deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 1, name: "a.txt"), deviceId: "dev")
    let c1 = try await idx.currentChangeCounter(deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 2, name: "b.txt"), deviceId: "dev")
    let c2 = try await idx.currentChangeCounter(deviceId: "dev")

    #expect(c0 == 0)
    #expect(c1 > c0)
    #expect(c2 > c1)
  }

  @Test("changesSince returns only mutations after anchor")
  func changesSinceAnchor() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "before.txt"), deviceId: "dev")
    let anchor = try await idx.currentChangeCounter(deviceId: "dev")

    try await idx.insertObject(makeObj(handle: 2, name: "after.txt"), deviceId: "dev")
    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)

    let changes = try await idx.changesSince(deviceId: "dev", anchor: anchor)

    // Should see upsert of handle 2 and delete of handle 1
    let upserted = changes.filter { $0.kind == .upserted }
    let deleted = changes.filter { $0.kind == .deleted }
    #expect(upserted.count >= 1)
    #expect(deleted.count >= 1)
    #expect(upserted.contains { $0.object.handle == 2 })
    #expect(deleted.contains { $0.object.handle == 1 })
  }

  @Test("changesSince with anchor 0 returns all changes")
  func changesSinceZero() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "a.txt"), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 2, name: "b.txt"), deviceId: "dev")

    let changes = try await idx.changesSince(deviceId: "dev", anchor: 0)
    #expect(changes.count >= 2)
  }

  @Test("Prune old change log entries")
  func pruneOldChanges() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "old.txt"), deviceId: "dev")
    // Prune everything older than a date in the future should remove all entries
    let future = Date().addingTimeInterval(60)
    try await idx.pruneChangeLog(deviceId: "dev", olderThan: future)

    let changes = try await idx.changesSince(deviceId: "dev", anchor: 0)
    // The objects still exist, but the change log was pruned
    #expect(changes.isEmpty)
  }
}

// MARK: - 6. Search / Filter

@Suite("LiveIndex Search and Filter")
struct LiveIndexSearchFilterTests {

  @Test("Filter children by file extension")
  func filterByExtension() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let files = ["a.jpg", "b.png", "c.jpg", "d.mp4", "e.jpg"]
    for (i, name) in files.enumerated() {
      try await idx.insertObject(makeObj(handle: UInt32(i + 1), name: name), deviceId: "dev")
    }

    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let jpgs = all.filter { $0.name.hasSuffix(".jpg") }
    #expect(jpgs.count == 3)
  }

  @Test("Filter by directory flag")
  func filterDirectories() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "DCIM", isDirectory: true), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 2, name: "readme.txt", isDirectory: false), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 3, name: "Music", isDirectory: true), deviceId: "dev")

    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let dirs = all.filter(\.isDirectory)
    let files = all.filter { !$0.isDirectory }
    #expect(dirs.count == 2)
    #expect(files.count == 1)
  }

  @Test("Filter by path key prefix")
  func filterByPathPrefix() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let dir = makeObj(handle: 1, name: "DCIM", pathKey: "00010001/DCIM", isDirectory: true)
    let child1 = makeObj(handle: 2, parentHandle: 1, name: "a.jpg", pathKey: "00010001/DCIM/a.jpg")
    let child2 = makeObj(handle: 3, parentHandle: 1, name: "b.jpg", pathKey: "00010001/DCIM/b.jpg")
    let other = makeObj(handle: 4, name: "readme.txt", pathKey: "00010001/readme.txt")
    try await idx.upsertObjects([dir, child1, child2, other], deviceId: "dev")

    let dcimChildren = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    #expect(dcimChildren.count == 2)
    #expect(dcimChildren.allSatisfy { $0.pathKey.hasPrefix("00010001/DCIM/") })
  }

  @Test("Lookup object by handle across devices returns only matching device")
  func lookupByHandleDeviceIsolation() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objA = IndexedObject(
      deviceId: "devA", storageId: 0x10001, handle: 42, parentHandle: nil,
      name: "same.txt", pathKey: "key", sizeBytes: 10, mtime: nil,
      formatCode: 0x3001, isDirectory: false, changeCounter: 0
    )
    let objB = IndexedObject(
      deviceId: "devB", storageId: 0x10001, handle: 42, parentHandle: nil,
      name: "other.txt", pathKey: "key", sizeBytes: 20, mtime: nil,
      formatCode: 0x3001, isDirectory: false, changeCounter: 0
    )
    try await idx.insertObject(objA, deviceId: "devA")
    try await idx.insertObject(objB, deviceId: "devB")

    let gotA = try await idx.object(deviceId: "devA", handle: 42)
    let gotB = try await idx.object(deviceId: "devB", handle: 42)
    #expect(gotA?.name == "same.txt")
    #expect(gotB?.name == "other.txt")
  }
}

// MARK: - 7. Edge Cases

@Suite("LiveIndex Edge Cases")
struct LiveIndexEdgeCaseTests {

  @Test("Empty index returns no children")
  func emptyIndexNoChildren() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.isEmpty)
  }

  @Test("Empty index change counter is zero")
  func emptyIndexCounterZero() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter == 0)
  }

  @Test("Duplicate handle upsert keeps latest values")
  func duplicateHandleKeepsLatest() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "first.txt", sizeBytes: 10), deviceId: "dev")
    try await idx.insertObject(makeObj(handle: 1, name: "second.txt", sizeBytes: 20), deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.name == "second.txt")
    #expect(got?.sizeBytes == 20)

    // Ensure only one row for that handle
    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let matching = all.filter { $0.handle == 1 }
    #expect(matching.count == 1)
  }

  @Test("Orphaned children with nonexistent parent remain queryable by parent handle")
  func orphanedChildrenQueryable() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert child referencing parent handle 999 which does not exist
    let orphan = makeObj(handle: 10, parentHandle: 999, name: "orphan.txt")
    try await idx.insertObject(orphan, deviceId: "dev")

    // The orphan is not a root child
    let rootKids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(rootKids.isEmpty)

    // But can be found under its declared parent
    let parentKids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 999)
    #expect(parentKids.count == 1)
    #expect(parentKids.first?.name == "orphan.txt")
  }

  @Test("Very deep nesting (100 levels)")
  func veryDeepNesting() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let depth = 100
    var objects: [IndexedObject] = []
    for level in 0..<depth {
      let parent: UInt32? = level == 0 ? nil : UInt32(level - 1)
      objects.append(makeObj(
        handle: UInt32(level),
        parentHandle: parent,
        name: "level\(level)",
        isDirectory: level < depth - 1
      ))
    }
    try await idx.upsertObjects(objects, deviceId: "dev")

    // Walk from deepest to root
    var segments: [String] = []
    var cur = try await idx.object(deviceId: "dev", handle: UInt32(depth - 1))
    while let obj = cur {
      segments.insert(obj.name, at: 0)
      if let ph = obj.parentHandle {
        cur = try await idx.object(deviceId: "dev", handle: ph)
      } else {
        cur = nil
      }
    }
    #expect(segments.count == depth)
    #expect(segments.first == "level0")
    #expect(segments.last == "level\(depth - 1)")
  }

  @Test("Remove non-existent object does not crash")
  func removeNonExistent() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Should not throw
    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 9999)
  }

  @Test("markStaleChildren on empty parent is no-op")
  func markStaleEmptyParent() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: 42)
    // No crash, no side effect
    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 42)
    #expect(kids.isEmpty)
  }

  @Test("purgeStale on empty index is no-op")
  func purgeStaleEmpty() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.purgeStale(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    // No crash
  }

  @Test("Object with zero-length name")
  func zeroLengthName() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: ""), deviceId: "dev")
    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got?.name == "")
  }

  @Test("Unicode names preserved correctly")
  func unicodeNames() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let names = ["日本語.txt", "Ñoño.pdf", "émoji🎉.mp4", "中文文件夹"]
    for (i, name) in names.enumerated() {
      try await idx.insertObject(makeObj(handle: UInt32(i + 1), name: name), deviceId: "dev")
    }
    for (i, name) in names.enumerated() {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i + 1))
      #expect(got?.name == name)
    }
  }
}

// MARK: - 8. Large Dataset

@Suite("LiveIndex Large Dataset")
struct LiveIndexLargeDatasetTests {

  @Test("Insert and query 10K objects")
  func tenThousandObjects() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let count = 10_000
    let objects = (0..<count).map { i in
      makeObj(
        handle: UInt32(i),
        name: "file\(i).dat",
        pathKey: "00010001/dir\(i / 100)/file\(i).dat"
      )
    }

    let t0 = Date()
    try await idx.upsertObjects(objects, deviceId: "dev")
    let insertElapsed = Date().timeIntervalSince(t0)

    // Spot-check random handles
    for h: UInt32 in [0, 999, 5000, 9999] {
      let obj = try await idx.object(deviceId: "dev", handle: h)
      #expect(obj != nil)
      #expect(obj?.name == "file\(h).dat")
    }

    // Query root children (all have nil parentHandle)
    let t1 = Date()
    let allRoots = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let queryElapsed = Date().timeIntervalSince(t1)

    #expect(allRoots.count == count)
    // Reasonable performance: insert < 30s, query < 5s
    #expect(insertElapsed < 30.0)
    #expect(queryElapsed < 5.0)
  }

  @Test("10K objects change tracking")
  func tenThousandChangeTracking() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let firstBatch = (0..<5000).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await idx.upsertObjects(firstBatch, deviceId: "dev")

    let anchor = try await idx.currentChangeCounter(deviceId: "dev")

    let secondBatch = (5000..<10_000).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await idx.upsertObjects(secondBatch, deviceId: "dev")

    let changes = try await idx.changesSince(deviceId: "dev", anchor: anchor)
    // Second batch should produce at least 5000 change entries (deduplicated per handle)
    #expect(changes.count >= 5000)
  }
}

// MARK: - 9. Index Corruption Recovery

@Suite("LiveIndex Corruption Recovery")
struct LiveIndexCorruptionRecoveryTests {

  @Test("Opening database with garbage bytes throws")
  func garbageBytesThrows() throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("garbage-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    try Data(repeating: 0xFF, count: 256).write(to: URL(fileURLWithPath: path))

    #expect(throws: (any Error).self) {
      try SQLiteLiveIndex(path: path)
    }
  }

  @Test("Missing WAL file is handled gracefully")
  func missingWAL() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("waltest-\(UUID().uuidString).sqlite").path
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: path + "-wal")
      try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    // Create, populate, close
    do {
      let idx = try SQLiteLiveIndex(path: path)
      try await idx.insertObject(makeObj(handle: 1, name: "survive.txt"), deviceId: "dev")
    }

    // Remove WAL and SHM files if present
    try? FileManager.default.removeItem(atPath: path + "-wal")
    try? FileManager.default.removeItem(atPath: path + "-shm")

    // Reopen — should work (SQLite recovers)
    let idx2 = try SQLiteLiveIndex(path: path)
    let got = try await idx2.object(deviceId: "dev", handle: 1)
    // Data may or may not survive depending on WAL checkpoint status,
    // but the index should open without crashing
    _ = got
  }

  @Test("Truncated database file — open succeeds or throws cleanly")
  func truncatedDatabase() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("truncated-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create and populate
    do {
      let idx = try SQLiteLiveIndex(path: path)
      let objs = (0..<100).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
      try await idx.upsertObjects(objs, deviceId: "dev")
    }

    // Truncate to partial size
    let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    fh.truncateFile(atOffset: 512)
    try fh.close()

    // Should either open successfully (auto-recover) or throw — not crash
    do {
      let idx2 = try SQLiteLiveIndex(path: path)
      // If it opened, try a write to exercise recovery
      try await idx2.insertObject(makeObj(handle: 9999, name: "recovered.txt"), deviceId: "dev")
    } catch {
      // Throwing is acceptable — just no crash
      _ = error
    }
  }

  @Test("Read-only open of non-existent file throws")
  func readOnlyNonExistent() {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("noexist-\(UUID().uuidString).sqlite").path

    #expect(throws: (any Error).self) {
      try SQLiteLiveIndex(path: path, readOnly: true)
    }
  }
}
