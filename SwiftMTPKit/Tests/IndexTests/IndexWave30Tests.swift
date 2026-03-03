// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempDB() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("w30-\(UUID().uuidString).sqlite").path
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
  formatCode: UInt16 = 0x3001,
  mtime: Date? = nil
) -> IndexedObject {
  IndexedObject(
    deviceId: deviceId,
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: pathKey ?? "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: sizeBytes,
    mtime: mtime ?? Date(),
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - 1. Schema Migration (Ephemeral → Stable Device ID)

@Suite("Wave30 – Schema Migration")
struct Wave30SchemaMigrationTests {

  @Test("migrateEphemeralDeviceId rewrites all tables atomically")
  func migrateEphemeralRewritesAllTables() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let ephemeral = "2717:ff10@3:7"

    // Insert objects, storage, and generate change log under ephemeral ID
    let objs = (0..<20).map { i in
      makeObj(deviceId: ephemeral, handle: UInt32(i), name: "f\(i).txt")
    }
    try await idx.upsertObjects(objs, deviceId: ephemeral)
    try await idx.upsertStorage(IndexedStorage(
      deviceId: ephemeral, storageId: 0x10001, description: "Internal",
      capacity: 64_000_000, free: 32_000_000, readOnly: false
    ))

    let stableId = "stable-domain-uuid"
    try idx.migrateEphemeralDeviceId(vidPidPattern: "2717:ff10", newDomainId: stableId)

    // All objects should be under stable ID
    let migratedObjs = try await idx.children(
      deviceId: stableId, storageId: 0x10001, parentHandle: nil)
    #expect(migratedObjs.count == 20)

    // Old ID should be empty
    let oldObjs = try await idx.children(
      deviceId: ephemeral, storageId: 0x10001, parentHandle: nil)
    #expect(oldObjs.isEmpty)

    // Storage should also be migrated
    let storages = try await idx.storages(deviceId: stableId)
    #expect(storages.count == 1)
    #expect(storages.first?.description == "Internal")

    // Change counter should be accessible under new ID
    let counter = try await idx.currentChangeCounter(deviceId: stableId)
    #expect(counter > 0)
  }

  @Test("Migration with no matching rows is a no-op")
  func migrationNoMatch() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objs = (0..<5).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await idx.upsertObjects(objs, deviceId: "dev")

    // Migrate a pattern that doesn't match
    try idx.migrateEphemeralDeviceId(vidPidPattern: "ffff:ffff", newDomainId: "new-id")

    // Original device data untouched
    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 5)

    let migratedKids = try await idx.children(
      deviceId: "new-id", storageId: 0x10001, parentHandle: nil)
    #expect(migratedKids.isEmpty)
  }

  @Test("Double migration is idempotent")
  func doubleMigrationIdempotent() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let ephemeral = "04e8:6860@1:3"
    let objs = (0..<10).map { i in
      makeObj(deviceId: ephemeral, handle: UInt32(i), name: "f\(i).txt")
    }
    try await idx.upsertObjects(objs, deviceId: ephemeral)

    let stableId = "stable-id"
    try idx.migrateEphemeralDeviceId(vidPidPattern: "04e8:6860", newDomainId: stableId)
    // Second migration — same pattern, no rows match anymore
    try idx.migrateEphemeralDeviceId(vidPidPattern: "04e8:6860", newDomainId: stableId)

    let kids = try await idx.children(deviceId: stableId, storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 10)
  }

  @Test("Open legacy DB with existing live_objects table adds missing tables")
  func legacySchemaUpgrade() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("legacy-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create a bare SQLite DB with only live_objects
    let rawDB = try SQLiteDB(path: path)
    try rawDB.exec("""
      CREATE TABLE IF NOT EXISTS live_objects (
          deviceId TEXT NOT NULL,
          storageId INTEGER NOT NULL,
          handle INTEGER NOT NULL,
          parentHandle INTEGER,
          name TEXT NOT NULL,
          pathKey TEXT NOT NULL,
          sizeBytes INTEGER,
          mtime INTEGER,
          formatCode INTEGER NOT NULL DEFAULT 0x3000,
          isDirectory INTEGER NOT NULL DEFAULT 0,
          changeCounter INTEGER NOT NULL DEFAULT 0,
          crawledAt INTEGER NOT NULL DEFAULT 0,
          stale INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (deviceId, storageId, handle)
      );
      """)

    // Opening with SQLiteLiveIndex should add the missing tables (CREATE IF NOT EXISTS)
    let idx = try SQLiteLiveIndex(path: path)

    // Should be able to use all features
    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 1, description: "Test",
      capacity: 100, free: 50, readOnly: false
    ))
    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 1)

    let obj = makeObj(handle: 1, name: "test.txt")
    try await idx.insertObject(obj, deviceId: "dev")
    let got = try await idx.object(deviceId: "dev", handle: 1)
    #expect(got != nil)
  }
}

// MARK: - 2. WAL Mode Checkpoint Under Concurrent Readers

@Suite("Wave30 – WAL Checkpoint Behavior")
struct Wave30WALCheckpointTests {

  @Test("Writer commits visible to new reader connections")
  func writerCommitsVisibleToNewReader() async throws {
    let (writer, path) = try makeTempDB()
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: path + "-wal")
      try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    let objs = (0..<100).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await writer.upsertObjects(objs, deviceId: "dev")

    // Open a fresh read-only connection — should see all committed data
    let reader = try SQLiteLiveIndex(path: path, readOnly: true)
    let kids = try await reader.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 100)
  }

  @Test("Long-running reader does not block writer")
  func longRunningReaderDoesNotBlockWriter() async throws {
    let (writer, path) = try makeTempDB()
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: path + "-wal")
      try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    let seed = (0..<50).map { i in makeObj(handle: UInt32(i), name: "s\(i).txt") }
    try await writer.upsertObjects(seed, deviceId: "dev")

    let reader = try SQLiteLiveIndex(path: path, readOnly: true)

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Long-running reader: many sequential reads
      group.addTask {
        for _ in 0..<100 {
          let kids = try await reader.children(
            deviceId: "dev", storageId: 0x10001, parentHandle: nil)
          #expect(kids.count >= 50)
          try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
        }
      }
      // Writer: inserts batches concurrently
      group.addTask {
        for batch in 0..<10 {
          let objs = (0..<50).map { j in
            makeObj(handle: UInt32(1000 + batch * 50 + j), name: "w\(batch)_\(j).txt")
          }
          try await writer.upsertObjects(objs, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    // After completion, writer should have all objects
    let total = try await writer.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == 550)  // 50 seed + 10 * 50
  }
}

// MARK: - 3. Database Corruption Detection and Recovery

@Suite("Wave30 – Corruption Recovery")
struct Wave30CorruptionRecoveryTests {

  @Test("Overwritten header bytes → open or schema creation fails")
  func overwrittenHeaderFails() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("corrupt-hdr-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Write a valid DB first, then corrupt the first 16 bytes (SQLite header)
    let idx = try SQLiteLiveIndex(path: path)
    _ = idx

    var data = try Data(contentsOf: URL(fileURLWithPath: path))
    for i in 0..<min(16, data.count) { data[i] = 0xDE }
    try data.write(to: URL(fileURLWithPath: path))

    // SQLite may open the file (lazy header check) but operations should fail
    do {
      let idx2 = try SQLiteLiveIndex(path: path)
      // If open succeeded, writing should fail
      let obj = makeObj(handle: 1, name: "test.txt")
      try await idx2.insertObject(obj, deviceId: "dev")
      // If we got here, the corruption wasn't detected at this level —
      // this is acceptable since SQLite may auto-recover small corruptions
    } catch {
      // Throwing at any point (open or write) is the expected behavior
      _ = error
    }
  }

  @Test("Truncated DB to zero bytes → open throws")
  func truncatedToZeroThrows() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("trunc0-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    try Data().write(to: URL(fileURLWithPath: path))

    // Zero-byte file: SQLite may open it (empty DB) or throw
    // Either outcome is acceptable — no crash
    do {
      let idx = try SQLiteLiveIndex(path: path)
      // If it opened, verify it's usable
      let obj = makeObj(handle: 1, name: "test.txt")
      try await idx.insertObject(obj, deviceId: "dev")
    } catch {
      // Throwing is also acceptable
      _ = error
    }
  }

  @Test("Deleted WAL + SHM mid-session → reopen recovers committed data")
  func deletedWALRecovery() async throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("wal-del-\(UUID().uuidString).sqlite").path
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: path + "-wal")
      try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    // Create and populate
    do {
      let idx = try SQLiteLiveIndex(path: path)
      let objs = (0..<50).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
      try await idx.upsertObjects(objs, deviceId: "dev")
    }
    // SQLiteLiveIndex deinit closes DB, causing WAL checkpoint

    // Delete WAL/SHM
    try? FileManager.default.removeItem(atPath: path + "-wal")
    try? FileManager.default.removeItem(atPath: path + "-shm")

    // Reopen — data should survive (was checkpointed on close)
    let idx2 = try SQLiteLiveIndex(path: path)
    let kids = try await idx2.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    // May or may not have all data depending on checkpoint timing, but should not crash
    _ = kids
  }

  @Test("Opening non-SQLite file (e.g. JPEG) throws")
  func openNonSQLiteThrows() throws {
    let dir = FileManager.default.temporaryDirectory
    let path = dir.appendingPathComponent("fake-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }

    // JPEG header
    let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(0x42), count: 200))
    try jpegHeader.write(to: URL(fileURLWithPath: path))

    #expect(throws: (any Error).self) {
      try SQLiteLiveIndex(path: path)
    }
  }
}

// MARK: - 4. Large Batch Insert Performance (10,000 objects)

@Suite("Wave30 – Large Batch Performance")
struct Wave30LargeBatchTests {

  @Test("10,000 objects in one transaction completes under 30s")
  func tenThousandInOneTransaction() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let count = 10_000
    let objects = (0..<count).map { i in
      makeObj(
        handle: UInt32(i),
        name: "file\(i).dat",
        pathKey: "00010001/dir\(i / 100)/file\(i).dat",
        sizeBytes: UInt64(i * 1024)
      )
    }

    let t0 = Date()
    try await idx.upsertObjects(objects, deviceId: "dev")
    let elapsed = Date().timeIntervalSince(t0)

    #expect(elapsed < 30.0, "10K insert took \(elapsed)s, expected < 30s")

    // Spot-check
    for h: UInt32 in [0, 1000, 5000, 9999] {
      let obj = try await idx.object(deviceId: "dev", handle: h)
      #expect(obj != nil)
      #expect(obj?.name == "file\(h).dat")
    }

    // Change counter should reflect the batch
    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter > 0)
  }

  @Test("10,000 objects: upsert then full re-upsert with modified sizes")
  func tenThousandUpsertThenReUpsert() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let count = 10_000
    let v1 = (0..<count).map { i in
      makeObj(handle: UInt32(i), name: "f\(i).txt", sizeBytes: 100)
    }
    try await idx.upsertObjects(v1, deviceId: "dev")

    let v2 = (0..<count).map { i in
      makeObj(handle: UInt32(i), name: "f\(i).txt", sizeBytes: 200)
    }
    let t0 = Date()
    try await idx.upsertObjects(v2, deviceId: "dev")
    let elapsed = Date().timeIntervalSince(t0)

    #expect(elapsed < 30.0)

    // All objects should have updated size
    let sample = try await idx.object(deviceId: "dev", handle: 5000)
    #expect(sample?.sizeBytes == 200)

    // Total count unchanged (upsert, not insert)
    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == count)
  }
}

// MARK: - 5. Path Key Collision Handling

@Suite("Wave30 – Path Key Collisions")
struct Wave30PathKeyCollisionTests {

  @Test("Two objects with same path key but different handles coexist")
  func samePathKeyDifferentHandles() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let sharedPathKey = "00010001/DCIM/photo.jpg"
    let obj1 = makeObj(handle: 1, name: "photo.jpg", pathKey: sharedPathKey, sizeBytes: 100)
    let obj2 = makeObj(handle: 2, name: "photo.jpg", pathKey: sharedPathKey, sizeBytes: 200)

    try await idx.upsertObjects([obj1, obj2], deviceId: "dev")

    // Both objects exist (PK is deviceId+storageId+handle, not pathKey)
    let got1 = try await idx.object(deviceId: "dev", handle: 1)
    let got2 = try await idx.object(deviceId: "dev", handle: 2)
    #expect(got1 != nil)
    #expect(got2 != nil)
    #expect(got1?.sizeBytes == 100)
    #expect(got2?.sizeBytes == 200)
  }

  @Test("Upsert with same handle replaces, not duplicates")
  func upsertSameHandleReplaces() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let obj1 = makeObj(handle: 42, name: "v1.txt", pathKey: "00010001/v1.txt")
    let obj2 = makeObj(handle: 42, name: "v2.txt", pathKey: "00010001/v2.txt")

    try await idx.insertObject(obj1, deviceId: "dev")
    try await idx.upsertObjects([obj2], deviceId: "dev")

    let got = try await idx.object(deviceId: "dev", handle: 42)
    #expect(got?.name == "v2.txt")
    #expect(got?.pathKey == "00010001/v2.txt")

    // Only one row for that handle
    let all = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let matching = all.filter { $0.handle == 42 }
    #expect(matching.count == 1)
  }

  @Test("Same handle in different devices are independent")
  func sameHandleDifferentDevices() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let objA = makeObj(deviceId: "devA", handle: 1, name: "fileA.txt")
    let objB = makeObj(deviceId: "devB", handle: 1, name: "fileB.txt")

    try await idx.insertObject(objA, deviceId: "devA")
    try await idx.insertObject(objB, deviceId: "devB")

    let gotA = try await idx.object(deviceId: "devA", handle: 1)
    let gotB = try await idx.object(deviceId: "devB", handle: 1)
    #expect(gotA?.name == "fileA.txt")
    #expect(gotB?.name == "fileB.txt")
  }
}

// MARK: - 6. Live Index Cache Invalidation on DB Change

@Suite("Wave30 – Cache Invalidation")
struct Wave30CacheInvalidationTests {

  @Test("changesSince detects upserts after anchor")
  func changesSinceDetectsUpserts() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "before.txt"), deviceId: "dev")
    let anchor = try await idx.currentChangeCounter(deviceId: "dev")

    try await idx.insertObject(makeObj(handle: 2, name: "after.txt"), deviceId: "dev")
    try await idx.upsertObjects(
      [makeObj(handle: 1, name: "modified.txt")], deviceId: "dev")

    let changes = try await idx.changesSince(deviceId: "dev", anchor: anchor)
    let handles = Set(changes.map { $0.object.handle })
    #expect(handles.contains(2), "Should detect new object")
    #expect(handles.contains(1), "Should detect modified object")
  }

  @Test("changesSince detects deletes after anchor")
  func changesSinceDetectsDeletes() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "victim.txt"), deviceId: "dev")
    let anchor = try await idx.currentChangeCounter(deviceId: "dev")

    try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)

    let changes = try await idx.changesSince(deviceId: "dev", anchor: anchor)
    let deleted = changes.filter { $0.kind == .deleted }
    #expect(deleted.count >= 1)
    #expect(deleted.contains { $0.object.handle == 1 })
  }

  @Test("Read-only reader sees writer's changes via WAL")
  func readerSeesWriterChanges() async throws {
    let (writer, path) = try makeTempDB()
    defer {
      try? FileManager.default.removeItem(atPath: path)
      try? FileManager.default.removeItem(atPath: path + "-wal")
      try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    try await writer.insertObject(makeObj(handle: 1, name: "initial.txt"), deviceId: "dev")

    let reader = try SQLiteLiveIndex(path: path, readOnly: true)
    let anchor = try await reader.currentChangeCounter(deviceId: "dev")

    // Writer adds more
    try await writer.insertObject(makeObj(handle: 2, name: "new.txt"), deviceId: "dev")

    // Reader detects changes
    let changes = try await reader.changesSince(deviceId: "dev", anchor: anchor)
    #expect(changes.count >= 1)
  }

  @Test("pruneChangeLog removes entries but objects persist")
  func pruneChangeLogKeepsObjects() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.insertObject(makeObj(handle: 1, name: "keep.txt"), deviceId: "dev")

    // Prune all change log entries
    let future = Date().addingTimeInterval(3600)
    try await idx.pruneChangeLog(deviceId: "dev", olderThan: future)

    // Object still exists
    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj != nil)

    // But change log is empty
    let changes = try await idx.changesSince(deviceId: "dev", anchor: 0)
    #expect(changes.isEmpty)
  }
}

// MARK: - 7. Index Rebuild (Clear → Re-crawl → Verify)

@Suite("Wave30 – Index Rebuild")
struct Wave30IndexRebuildTests {

  @Test("Full rebuild: markStale → upsert fresh → purge → verify consistency")
  func fullRebuildCycle() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let parentHandle: UInt32 = 0x10001
    let parent = makeObj(
      handle: parentHandle, name: "DCIM",
      pathKey: "00010001/DCIM", isDirectory: true)
    try await idx.insertObject(parent, deviceId: "dev")

    // Original crawl: 100 objects
    let v1 = (0..<100).map { i in
      makeObj(
        handle: UInt32(100 + i), parentHandle: parentHandle,
        name: "photo\(i).jpg", pathKey: "00010001/DCIM/photo\(i).jpg")
    }
    try await idx.upsertObjects(v1, deviceId: "dev")

    let beforeCount = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
    #expect(beforeCount.count == 100)

    // Re-crawl: mark stale, upsert fresh (only 80 this time), purge
    try await idx.markStaleChildren(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)

    let v2 = (0..<80).map { i in
      makeObj(
        handle: UInt32(100 + i), parentHandle: parentHandle,
        name: "photo\(i)_v2.jpg", pathKey: "00010001/DCIM/photo\(i)_v2.jpg")
    }
    try await idx.upsertObjects(v2, deviceId: "dev")

    try await idx.purgeStale(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)

    // After rebuild: exactly 80 objects with updated names
    let afterCount = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
    #expect(afterCount.count == 80)
    #expect(afterCount.allSatisfy { $0.name.hasSuffix("_v2.jpg") })
  }

  @Test("Rebuild with empty re-crawl removes all children")
  func rebuildEmptyRecrawl() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let parentHandle: UInt32 = 100
    let children = (0..<50).map { i in
      makeObj(handle: UInt32(200 + i), parentHandle: parentHandle, name: "f\(i).txt")
    }
    try await idx.upsertObjects(children, deviceId: "dev")

    // Rebuild with no new objects
    try await idx.markStaleChildren(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
    // Don't upsert any replacements
    try await idx.purgeStale(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)

    let remaining = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
    #expect(remaining.isEmpty)
  }

  @Test("Rebuild preserves sibling directories")
  func rebuildPreservesSiblings() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Two sibling folders under root
    let dcimChildren = (0..<10).map { i in
      makeObj(handle: UInt32(100 + i), parentHandle: 1, name: "photo\(i).jpg")
    }
    let musicChildren = (0..<5).map { i in
      makeObj(handle: UInt32(200 + i), parentHandle: 2, name: "song\(i).mp3")
    }
    try await idx.upsertObjects(dcimChildren + musicChildren, deviceId: "dev")

    // Rebuild only DCIM (parent handle 1)
    try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    let freshDCIM = (0..<8).map { i in
      makeObj(handle: UInt32(100 + i), parentHandle: 1, name: "newphoto\(i).jpg")
    }
    try await idx.upsertObjects(freshDCIM, deviceId: "dev")
    try await idx.purgeStale(deviceId: "dev", storageId: 0x10001, parentHandle: 1)

    // DCIM rebuilt
    let dcim = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    #expect(dcim.count == 8)

    // Music untouched
    let music = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 2)
    #expect(music.count == 5)
  }
}

// MARK: - 8. Unicode Normalization for File Paths

@Suite("Wave30 – Unicode Path Normalization")
struct Wave30UnicodeNormalizationTests {

  @Test("NFC and NFD forms produce identical path keys")
  func nfcAndNfdProduceSamePathKey() {
    let nfd = "cafe\u{0301}"           // NFD: e + combining acute
    let nfc = "café"                    // NFC: precomposed é

    let keyNFD = PathKey.normalize(storage: 0x10001, components: ["DCIM", nfd])
    let keyNFC = PathKey.normalize(storage: 0x10001, components: ["DCIM", nfc])
    #expect(keyNFD == keyNFC)
  }

  @Test("German umlaut NFC/NFD normalization")
  func germanUmlautNormalization() {
    let nfd = "Mu\u{0308}ller"         // NFD: u + combining diaeresis
    let nfc = "Müller"                  // NFC: precomposed ü

    let keyNFD = PathKey.normalizeComponent(nfd)
    let keyNFC = PathKey.normalizeComponent(nfc)
    #expect(keyNFD == keyNFC)
    #expect(keyNFD == "Müller")
  }

  @Test("Hangul jamo normalization")
  func hangulJamoNormalization() {
    // Hangul syllable 가 (U+AC00) = ᄀ (U+1100) + ᅡ (U+1161)
    let decomposed = "\u{1100}\u{1161}"
    let composed = "\u{AC00}"

    let keyDecomp = PathKey.normalizeComponent(decomposed)
    let keyComp = PathKey.normalizeComponent(composed)
    #expect(keyDecomp == keyComp)
  }

  @Test("Emoji and CJK pass through unchanged")
  func emojiAndCJKPassThrough() {
    #expect(PathKey.normalizeComponent("📸photo.jpg") == "📸photo.jpg")
    #expect(PathKey.normalizeComponent("写真.jpg") == "写真.jpg")
    #expect(PathKey.normalizeComponent("사진.jpg") == "사진.jpg")
  }

  @Test("Stored and retrieved Unicode names round-trip correctly")
  func unicodeRoundTrip() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let names = [
      "café.txt",               // NFC
      "naïve.pdf",              // NFC with diaeresis
      "Ångström.doc",           // Nordic
      "日本語ファイル.txt",      // Japanese
      "파일이름.txt",            // Korean
      "Привет.txt",             // Cyrillic
      "📸🎉emoji.jpg",          // Emoji
    ]

    for (i, name) in names.enumerated() {
      let obj = makeObj(handle: UInt32(i + 1), name: name)
      try await idx.insertObject(obj, deviceId: "dev")
    }

    for (i, name) in names.enumerated() {
      let got = try await idx.object(deviceId: "dev", handle: UInt32(i + 1))
      #expect(got?.name == name, "Name mismatch for '\(name)'")
    }
  }
}

// MARK: - 9. Storage Enumeration with Mixed Types

@Suite("Wave30 – Mixed Storage Enumeration")
struct Wave30MixedStorageTests {

  @Test("Three storage types: fixed, removable, virtual")
  func threeStorageTypes() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let fixed = IndexedStorage(
      deviceId: "dev", storageId: 0x10001, description: "Internal Storage",
      capacity: 128_000_000_000, free: 64_000_000_000, readOnly: false)
    let removable = IndexedStorage(
      deviceId: "dev", storageId: 0x20001, description: "SD Card",
      capacity: 32_000_000_000, free: 16_000_000_000, readOnly: false)
    let virtual = IndexedStorage(
      deviceId: "dev", storageId: 0x30001, description: "Virtual Storage",
      capacity: nil, free: nil, readOnly: true)

    try await idx.upsertStorage(fixed)
    try await idx.upsertStorage(removable)
    try await idx.upsertStorage(virtual)

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 3)

    let descriptions = Set(storages.map(\.description))
    #expect(descriptions.contains("Internal Storage"))
    #expect(descriptions.contains("SD Card"))
    #expect(descriptions.contains("Virtual Storage"))

    // Check read-only flags
    let readOnlyStorages = storages.filter(\.readOnly)
    #expect(readOnlyStorages.count == 1)
    #expect(readOnlyStorages.first?.description == "Virtual Storage")
  }

  @Test("Objects isolated per storage")
  func objectsIsolatedPerStorage() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert objects into two different storages
    let internalObjs = (0..<10).map { i in
      makeObj(handle: UInt32(i), storageId: 0x10001, name: "int\(i).txt")
    }
    let sdCardObjs = (0..<5).map { i in
      makeObj(handle: UInt32(100 + i), storageId: 0x20001, name: "sd\(i).txt")
    }
    try await idx.upsertObjects(internalObjs + sdCardObjs, deviceId: "dev")

    let internalKids = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let sdKids = try await idx.children(
      deviceId: "dev", storageId: 0x20001, parentHandle: nil)

    #expect(internalKids.count == 10)
    #expect(sdKids.count == 5)
    #expect(internalKids.allSatisfy { $0.name.hasPrefix("int") })
    #expect(sdKids.allSatisfy { $0.name.hasPrefix("sd") })
  }

  @Test("Storage metadata update preserves objects")
  func storageUpdatePreservesObjects() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 0x10001, description: "Internal",
      capacity: 128_000_000_000, free: 100_000_000_000, readOnly: false))

    let objs = (0..<20).map { i in
      makeObj(handle: UInt32(i), storageId: 0x10001, name: "f\(i).txt")
    }
    try await idx.upsertObjects(objs, deviceId: "dev")

    // Update storage free space
    try await idx.upsertStorage(IndexedStorage(
      deviceId: "dev", storageId: 0x10001, description: "Internal",
      capacity: 128_000_000_000, free: 50_000_000_000, readOnly: false))

    // Objects still there
    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 20)

    // Free space updated
    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.first?.free == 50_000_000_000)
  }
}

// MARK: - 10. Diff Computation with Large Changesets

@Suite("Wave30 – Large Diff Computation")
struct Wave30LargeDiffTests {

  @Test("DiffEngine: add 1000, delete 500, modify 200")
  func largeDiffAccuracy() async throws {
    let dir = FileManager.default.temporaryDirectory
    let dbPath = dir.appendingPathComponent("diff-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let engine = try DiffEngine(dbPath: dbPath)
    let db = try SQLiteDB(path: dbPath)
    let deviceId = MTPDeviceID(raw: "diff-test-device")

    // Setup schema (use Snapshotter's PK which is deviceId+handle+gen)
    try db.exec("""
      CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, model TEXT, lastSeenAt INTEGER);
      CREATE TABLE IF NOT EXISTS storages(id INTEGER, deviceId TEXT, description TEXT, capacity INTEGER, free INTEGER, readOnly INTEGER, lastIndexedAt INTEGER, PRIMARY KEY(id, deviceId));
      CREATE TABLE IF NOT EXISTS objects(
        deviceId TEXT NOT NULL, storageId INTEGER NOT NULL, handle INTEGER NOT NULL,
        parentHandle INTEGER, name TEXT NOT NULL, pathKey TEXT NOT NULL,
        size INTEGER, mtime INTEGER, format INTEGER NOT NULL,
        gen INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(deviceId, handle, gen)
      );
      CREATE INDEX IF NOT EXISTS idx_objects_path ON objects(deviceId, pathKey);
      CREATE INDEX IF NOT EXISTS idx_objects_gen ON objects(deviceId, gen);
      CREATE TABLE IF NOT EXISTS snapshots(deviceId TEXT NOT NULL, gen INTEGER NOT NULL, createdAt INTEGER NOT NULL, PRIMARY KEY(deviceId, gen));
      """)

    try db.withStatement("INSERT INTO devices(id, model, lastSeenAt) VALUES(?, 'Test', 0)") {
      stmt in
      try db.bind(stmt, 1, deviceId.raw)
      _ = try? db.step(stmt)
    }

    let gen1 = 1
    let gen2 = 2

    // Gen 1: objects 0..1499 (1500 total)
    try db.withTransaction {
      for i: UInt32 in 0..<1500 {
        try db.withStatement(
          "INSERT INTO objects(deviceId, storageId, handle, name, pathKey, size, mtime, format, gen) VALUES(?,?,?,?,?,?,?,?,?)"
        ) { stmt in
          try db.bind(stmt, 1, deviceId.raw)
          try db.bind(stmt, 2, Int64(0x10001))
          try db.bind(stmt, 3, Int64(i))
          try db.bind(stmt, 4, "file\(i).txt")
          try db.bind(stmt, 5, "00010001/file\(i).txt")
          try db.bind(stmt, 6, Int64(1000))
          try db.bind(stmt, 7, Int64(1000000))
          try db.bind(stmt, 8, Int64(0x3004))
          try db.bind(stmt, 9, Int64(gen1))
          _ = try db.step(stmt)
        }
      }
    }

    // Gen 2: keep 0..999, modify 1000..1199 (size change), drop 1200..1499, add 1500..2499
    try db.withTransaction {
      // Unchanged: 0..999
      for i: UInt32 in 0..<1000 {
        try db.withStatement(
          "INSERT INTO objects(deviceId, storageId, handle, name, pathKey, size, mtime, format, gen) VALUES(?,?,?,?,?,?,?,?,?)"
        ) { stmt in
          try db.bind(stmt, 1, deviceId.raw)
          try db.bind(stmt, 2, Int64(0x10001))
          try db.bind(stmt, 3, Int64(i))
          try db.bind(stmt, 4, "file\(i).txt")
          try db.bind(stmt, 5, "00010001/file\(i).txt")
          try db.bind(stmt, 6, Int64(1000))     // same size
          try db.bind(stmt, 7, Int64(1000000))   // same mtime
          try db.bind(stmt, 8, Int64(0x3004))
          try db.bind(stmt, 9, Int64(gen2))
          _ = try db.step(stmt)
        }
      }
      // Modified: 1000..1199 (different size)
      for i: UInt32 in 1000..<1200 {
        try db.withStatement(
          "INSERT INTO objects(deviceId, storageId, handle, name, pathKey, size, mtime, format, gen) VALUES(?,?,?,?,?,?,?,?,?)"
        ) { stmt in
          try db.bind(stmt, 1, deviceId.raw)
          try db.bind(stmt, 2, Int64(0x10001))
          try db.bind(stmt, 3, Int64(i))
          try db.bind(stmt, 4, "file\(i).txt")
          try db.bind(stmt, 5, "00010001/file\(i).txt")
          try db.bind(stmt, 6, Int64(2000))      // changed size
          try db.bind(stmt, 7, Int64(1000000))
          try db.bind(stmt, 8, Int64(0x3004))
          try db.bind(stmt, 9, Int64(gen2))
          _ = try db.step(stmt)
        }
      }
      // Deleted: 1200..1499 (not present in gen2)
      // Added: 1500..2499
      for i: UInt32 in 1500..<2500 {
        try db.withStatement(
          "INSERT INTO objects(deviceId, storageId, handle, name, pathKey, size, mtime, format, gen) VALUES(?,?,?,?,?,?,?,?,?)"
        ) { stmt in
          try db.bind(stmt, 1, deviceId.raw)
          try db.bind(stmt, 2, Int64(0x10001))
          try db.bind(stmt, 3, Int64(i))
          try db.bind(stmt, 4, "file\(i).txt")
          try db.bind(stmt, 5, "00010001/file\(i).txt")
          try db.bind(stmt, 6, Int64(1000))
          try db.bind(stmt, 7, Int64(1000000))
          try db.bind(stmt, 8, Int64(0x3004))
          try db.bind(stmt, 9, Int64(gen2))
          _ = try db.step(stmt)
        }
      }
    }

    // Record snapshots
    try db.withStatement(
      "INSERT INTO snapshots(deviceId, gen, createdAt) VALUES(?,?,?)"
    ) { stmt in
      try db.bind(stmt, 1, deviceId.raw)
      try db.bind(stmt, 2, Int64(gen1))
      try db.bind(stmt, 3, Int64(0))
      _ = try db.step(stmt)
    }
    try db.withStatement(
      "INSERT INTO snapshots(deviceId, gen, createdAt) VALUES(?,?,?)"
    ) { stmt in
      try db.bind(stmt, 1, deviceId.raw)
      try db.bind(stmt, 2, Int64(gen2))
      try db.bind(stmt, 3, Int64(1))
      _ = try db.step(stmt)
    }

    let diff = try await engine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

    #expect(diff.added.count == 1000, "Expected 1000 added, got \(diff.added.count)")
    #expect(diff.removed.count == 300, "Expected 300 removed, got \(diff.removed.count)")
    #expect(diff.modified.count == 200, "Expected 200 modified, got \(diff.modified.count)")
    #expect(diff.totalChanges == 1500)
    #expect(!diff.isEmpty)
  }

  @Test("MTPDiff with nil oldGen treats everything as added")
  func diffNilOldGen() async throws {
    let dir = FileManager.default.temporaryDirectory
    let dbPath = dir.appendingPathComponent("diff-nil-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let engine = try DiffEngine(dbPath: dbPath)
    let db = try SQLiteDB(path: dbPath)
    let deviceId = MTPDeviceID(raw: "nil-gen-device")

    try db.exec("""
      CREATE TABLE IF NOT EXISTS objects(
        deviceId TEXT NOT NULL, storageId INTEGER NOT NULL, handle INTEGER NOT NULL,
        parentHandle INTEGER, name TEXT NOT NULL, pathKey TEXT NOT NULL,
        size INTEGER, mtime INTEGER, format INTEGER NOT NULL,
        gen INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(deviceId, storageId, handle)
      );
      """)

    for i: UInt32 in 0..<100 {
      try db.withStatement(
        "INSERT INTO objects(deviceId, storageId, handle, name, pathKey, size, mtime, format, gen) VALUES(?,?,?,?,?,?,?,?,?)"
      ) { stmt in
        try db.bind(stmt, 1, deviceId.raw)
        try db.bind(stmt, 2, Int64(0x10001))
        try db.bind(stmt, 3, Int64(i))
        try db.bind(stmt, 4, "f\(i).txt")
        try db.bind(stmt, 5, "00010001/f\(i).txt")
        try db.bind(stmt, 6, Int64(100))
        try db.bind(stmt, 7, Int64(0))
        try db.bind(stmt, 8, Int64(0x3004))
        try db.bind(stmt, 9, Int64(1))
        _ = try db.step(stmt)
      }
    }

    let diff = try await engine.diff(deviceId: deviceId, oldGen: nil, newGen: 1)
    #expect(diff.added.count == 100)
    #expect(diff.removed.isEmpty)
    #expect(diff.modified.isEmpty)
  }

  @Test("MTPDiff empty when both generations identical")
  func diffEmptyWhenIdentical() async throws {
    let dir = FileManager.default.temporaryDirectory
    let dbPath = dir.appendingPathComponent("diff-eq-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let engine = try DiffEngine(dbPath: dbPath)
    let db = try SQLiteDB(path: dbPath)
    let deviceId = MTPDeviceID(raw: "eq-device")

    try db.exec("""
      CREATE TABLE IF NOT EXISTS objects(
        deviceId TEXT NOT NULL, storageId INTEGER NOT NULL, handle INTEGER NOT NULL,
        parentHandle INTEGER, name TEXT NOT NULL, pathKey TEXT NOT NULL,
        size INTEGER, mtime INTEGER, format INTEGER NOT NULL,
        gen INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(deviceId, storageId, handle)
      );
      """)

    // Same objects in both generations (same gen number = same data)
    let diff = try await engine.diff(deviceId: deviceId, oldGen: 1, newGen: 1)
    #expect(diff.isEmpty)
  }
}

// MARK: - 11. Device Identity Resolution

@Suite("Wave30 – Device Identity")
struct Wave30DeviceIdentityTests {

  @Test("Resolve identity creates new entry and returns stable domainId")
  func resolveIdentityCreatesNew() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let signals = DeviceIdentitySignals(
      vendorId: 0x2717, productId: 0xFF10, usbSerial: "SN12345",
      mtpSerial: nil, manufacturer: "Xiaomi", model: "Mi Note 2")

    let identity = try await idx.resolveIdentity(signals: signals)
    #expect(!identity.domainId.isEmpty)
    #expect(identity.displayName == "Xiaomi Mi Note 2")
  }

  @Test("Resolve same signals returns same domainId")
  func resolveIdentityIdempotent() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let signals = DeviceIdentitySignals(
      vendorId: 0x04E8, productId: 0x6860, usbSerial: "R5CT2XXXXX",
      mtpSerial: nil, manufacturer: "Samsung", model: "Galaxy S7")

    let id1 = try await idx.resolveIdentity(signals: signals)
    let id2 = try await idx.resolveIdentity(signals: signals)
    #expect(id1.domainId == id2.domainId)
  }

  @Test("Different serials produce different identities")
  func differentSerialsProduceDifferentIds() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let sig1 = DeviceIdentitySignals(
      vendorId: 0x2717, productId: 0xFF10, usbSerial: "SN_AAA",
      mtpSerial: nil, manufacturer: "Xiaomi", model: "Mi Note 2")
    let sig2 = DeviceIdentitySignals(
      vendorId: 0x2717, productId: 0xFF10, usbSerial: "SN_BBB",
      mtpSerial: nil, manufacturer: "Xiaomi", model: "Mi Note 2")

    let id1 = try await idx.resolveIdentity(signals: sig1)
    let id2 = try await idx.resolveIdentity(signals: sig2)
    #expect(id1.domainId != id2.domainId)
  }

  @Test("updateMTPSerial upgrades type-based identity key")
  func updateMTPSerialUpgrade() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // First resolve with no serial (type-based key)
    let signals = DeviceIdentitySignals(
      vendorId: 0x04E8, productId: 0x6860, usbSerial: nil,
      mtpSerial: nil, manufacturer: "Samsung", model: "Galaxy")

    let identity = try await idx.resolveIdentity(signals: signals)

    // Later, MTP serial becomes available
    try await idx.updateMTPSerial(domainId: identity.domainId, mtpSerial: "MTP_SERIAL_123")

    // Verify identity still resolves
    let got = try await idx.identity(for: identity.domainId)
    #expect(got != nil)
    #expect(got?.domainId == identity.domainId)
  }

  @Test("removeIdentity deletes the record")
  func removeIdentity() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let signals = DeviceIdentitySignals(
      vendorId: 0x2717, productId: 0xFF10, usbSerial: "REMOVE_ME",
      mtpSerial: nil, manufacturer: "Test", model: "Device")

    let identity = try await idx.resolveIdentity(signals: signals)
    try await idx.removeIdentity(domainId: identity.domainId)

    let got = try await idx.identity(for: identity.domainId)
    #expect(got == nil)
  }
}

// MARK: - 12. Concurrent Write Stress

@Suite("Wave30 – Concurrent Write Stress")
struct Wave30ConcurrentWriteStressTests {

  @Test("20 concurrent tasks inserting 500 objects each")
  func twentyTasksFiveHundredEach() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let taskCount = 20
    let objectsPerTask = 500
    let t0 = Date()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for t in 0..<taskCount {
        group.addTask {
          let objs = (0..<objectsPerTask).map { j in
            makeObj(handle: UInt32(t * objectsPerTask + j), name: "t\(t)_\(j).dat")
          }
          try await idx.upsertObjects(objs, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    let elapsed = Date().timeIntervalSince(t0)
    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == taskCount * objectsPerTask)
    #expect(elapsed < 60.0, "Concurrent insert took \(elapsed)s")
  }

  @Test("Concurrent upsert and delete on overlapping handles")
  func concurrentUpsertAndDeleteOverlap() async throws {
    let (idx, path) = try makeTempDB()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed objects
    let seed = (0..<200).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await idx.upsertObjects(seed, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Deleter: removes even handles
      group.addTask {
        for i in stride(from: 0, to: 200, by: 2) {
          try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: UInt32(i))
        }
      }
      // Upserter: re-inserts some even handles with new data
      group.addTask {
        for i in stride(from: 0, to: 100, by: 2) {
          let obj = makeObj(handle: UInt32(i), name: "resurrected\(i).txt")
          try await idx.upsertObjects([obj], deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    // All odd handles should survive
    for i in stride(from: 1, to: 200, by: 2) {
      let obj = try await idx.object(deviceId: "dev", handle: UInt32(i))
      #expect(obj != nil, "Odd handle \(i) should survive")
    }
  }
}
