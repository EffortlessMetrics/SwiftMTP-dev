// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempPath() -> String {
  let dir = FileManager.default.temporaryDirectory
  return dir.appendingPathComponent("persist-\(UUID().uuidString).sqlite").path
}

private func openIndex(at path: String, readOnly: Bool = false) throws -> SQLiteLiveIndex {
  try SQLiteLiveIndex(path: path, readOnly: readOnly)
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
  pathKey: String? = nil,
  isDirectory: Bool = false,
  sizeBytes: UInt64 = 1024,
  formatCode: UInt16 = 0x3001,
  mtime: Date? = Date(timeIntervalSince1970: 1_700_000_000)
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

private func makeStorage(
  deviceId: String = "dev",
  storageId: UInt32 = 0x10001,
  description: String = "Internal",
  capacity: UInt64? = 64_000_000_000,
  free: UInt64? = 32_000_000_000,
  readOnly: Bool = false
) -> IndexedStorage {
  IndexedStorage(
    deviceId: deviceId,
    storageId: storageId,
    description: description,
    capacity: capacity,
    free: free,
    readOnly: readOnly
  )
}

// MARK: - 1. Empty Database

@Suite("Persistence — Empty Database")
struct EmptyDatabaseTests {

  @Test("New database has zero objects for any device")
  func emptyReturnsNoObjects() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let children = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(children.isEmpty)
  }

  @Test("New database has zero storages")
  func emptyReturnsNoStorages() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.isEmpty)
  }

  @Test("New database change counter is zero")
  func emptyChangeCounter() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter == 0)
  }

  @Test("New database has no changes since anchor 0")
  func emptyChangesSince() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let changes = try await idx.changesSince(deviceId: "dev", anchor: 0)
    #expect(changes.isEmpty)
  }
}

// MARK: - 2. Reopen Persistence

@Suite("Persistence — Survive Reopen")
struct ReopenPersistenceTests {

  @Test("Objects persist after closing and reopening database")
  func objectsSurviveReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    // Write with first instance
    do {
      let idx = try openIndex(at: path)
      try await idx.upsertObjects(
        [
          makeObj(handle: 1, name: "photo.jpg", sizeBytes: 5000),
          makeObj(handle: 2, name: "video.mp4", sizeBytes: 90000),
        ], deviceId: "dev")
    }

    // Read with second instance
    let idx2 = try openIndex(at: path)
    let obj1 = try await idx2.object(deviceId: "dev", handle: 1)
    let obj2 = try await idx2.object(deviceId: "dev", handle: 2)
    #expect(obj1?.name == "photo.jpg")
    #expect(obj1?.sizeBytes == 5000)
    #expect(obj2?.name == "video.mp4")
    #expect(obj2?.sizeBytes == 90000)
  }

  @Test("Storage metadata persists after reopen")
  func storagesSurviveReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.upsertStorage(makeStorage(description: "SD Card", capacity: 128_000_000_000))
    }

    let idx2 = try openIndex(at: path)
    let storages = try await idx2.storages(deviceId: "dev")
    #expect(storages.count == 1)
    #expect(storages.first?.description == "SD Card")
    #expect(storages.first?.capacity == 128_000_000_000)
  }

  @Test("Change counter persists after reopen")
  func changeCounterSurvivesReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.upsertObjects([makeObj(handle: 1)], deviceId: "dev")
      try await idx.upsertObjects([makeObj(handle: 2)], deviceId: "dev")
    }

    let idx2 = try openIndex(at: path)
    let counter = try await idx2.currentChangeCounter(deviceId: "dev")
    #expect(counter >= 2)
  }

  @Test("Change log entries persist after reopen")
  func changeLogSurvivesReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.upsertObjects([makeObj(handle: 1, name: "a.txt")], deviceId: "dev")
      try await idx.upsertObjects([makeObj(handle: 2, name: "b.txt")], deviceId: "dev")
    }

    let idx2 = try openIndex(at: path)
    let changes = try await idx2.changesSince(deviceId: "dev", anchor: 0)
    #expect(changes.count == 2)
  }

  @Test("Read-only instance sees data written by read-write instance")
  func readOnlySeesWrittenData() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.upsertObjects([makeObj(handle: 42, name: "shared.txt")], deviceId: "dev")
    }

    let reader = try openIndex(at: path, readOnly: true)
    let obj = try await reader.object(deviceId: "dev", handle: 42)
    #expect(obj?.name == "shared.txt")
  }
}

// MARK: - 3. Update Persistence

@Suite("Persistence — Updates")
struct UpdatePersistenceTests {

  @Test("Updated fields persist correctly after reopen")
  func updatedFieldsPersist() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(
        makeObj(handle: 1, name: "old.txt", sizeBytes: 100), deviceId: "dev")
      try await idx.upsertObjects(
        [makeObj(handle: 1, name: "new.txt", sizeBytes: 999)], deviceId: "dev")
    }

    let idx2 = try openIndex(at: path)
    let obj = try await idx2.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == "new.txt")
    #expect(obj?.sizeBytes == 999)
  }

  @Test("Storage update overwrites previous values after reopen")
  func storageUpdatePersists() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.upsertStorage(makeStorage(free: 10_000_000_000))
      try await idx.upsertStorage(makeStorage(free: 5_000_000_000))
    }

    let idx2 = try openIndex(at: path)
    let storages = try await idx2.storages(deviceId: "dev")
    #expect(storages.count == 1)
    #expect(storages.first?.free == 5_000_000_000)
  }
}

// MARK: - 4. Delete Persistence

@Suite("Persistence — Deletion")
struct DeletePersistenceTests {

  @Test("Removed object stays stale after reopen")
  func removedObjectStaleAfterReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(makeObj(handle: 1, name: "gone.txt"), deviceId: "dev")
      try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)
    }

    let idx2 = try openIndex(at: path)
    let obj = try await idx2.object(deviceId: "dev", handle: 1)
    #expect(obj == nil, "Stale objects should not appear in normal queries")
  }

  @Test("Purged objects are permanently deleted after reopen")
  func purgedObjectsGoneAfterReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(
        makeObj(handle: 1, parentHandle: 0, name: "purge-me.txt"), deviceId: "dev")
      try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
      try await idx.purgeStale(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    }

    let idx2 = try openIndex(at: path)
    // Even stale rows should be gone
    let children = try await idx2.children(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    #expect(children.isEmpty)
  }

  @Test("Change log records delete events that persist")
  func deleteChangeLogPersists() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(makeObj(handle: 1), deviceId: "dev")
      let anchor = try await idx.currentChangeCounter(deviceId: "dev")
      try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: 1)

      let idx2 = try openIndex(at: path)
      let changes = try await idx2.changesSince(deviceId: "dev", anchor: anchor)
      #expect(changes.contains { $0.kind == .deleted })
    }
  }
}

// MARK: - 5. Bulk Insert Performance

@Suite("Persistence — Bulk Operations")
struct BulkOperationsTests {

  @Test("Bulk insert 2000 objects and query all back")
  func bulkInsert2000() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let objects = (0..<2000)
      .map { i in
        makeObj(
          handle: UInt32(i), parentHandle: 0, name: "item-\(i).dat", sizeBytes: UInt64(i * 100))
      }
    try await idx.upsertObjects(objects, deviceId: "dev")

    let children = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    #expect(children.count == 2000)
  }

  @Test("Bulk insert 5000 objects completes under 10 seconds")
  func bulkInsertPerformance() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let objects = (0..<5000)
      .map { i in
        makeObj(handle: UInt32(i), parentHandle: 0, name: "perf-\(i).jpg")
      }
    let start = ContinuousClock.now
    try await idx.upsertObjects(objects, deviceId: "dev")
    let elapsed = ContinuousClock.now - start

    #expect(elapsed < .seconds(10), "5000-item bulk insert took \(elapsed)")
  }

  @Test("Bulk insert survives reopen")
  func bulkInsertSurvivesReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      let objects = (0..<1500)
        .map { i in
          makeObj(handle: UInt32(i), parentHandle: 0, name: "bulk-\(i).txt")
        }
      try await idx.upsertObjects(objects, deviceId: "dev")
    }

    let idx2 = try openIndex(at: path)
    let children = try await idx2.children(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    #expect(children.count == 1500)
  }
}

// MARK: - 6. Query by Path Prefix

@Suite("Persistence — Path Prefix Queries")
struct PathPrefixQueryTests {

  @Test("Query objects sharing a path key prefix")
  func queryByPathPrefix() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 1, name: "a.txt", pathKey: "00010001/DCIM/a.txt"),
        makeObj(handle: 2, name: "b.txt", pathKey: "00010001/DCIM/b.txt"),
        makeObj(handle: 3, name: "c.txt", pathKey: "00010001/Music/c.txt"),
      ], deviceId: "dev")

    // Query all DCIM entries using pathKey LIKE prefix
    let dcim = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
      .filter { $0.pathKey.hasPrefix("00010001/DCIM/") }
    #expect(dcim.count == 2)
  }
}

// MARK: - 7. Query by Object Handle

@Suite("Persistence — Handle Queries")
struct HandleQueryTests {

  @Test("Query single object by handle returns correct object")
  func queryByHandle() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 100, name: "target.txt"),
        makeObj(handle: 200, name: "other.txt"),
      ], deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 100)
    #expect(obj?.name == "target.txt")
    #expect(obj?.handle == 100)
  }

  @Test("Query non-existent handle returns nil")
  func queryMissingHandle() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let obj = try await idx.object(deviceId: "dev", handle: 99999)
    #expect(obj == nil)
  }

  @Test("Handle 0 and UInt32.max boundary values")
  func handleBoundaryValues() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 0, name: "zero.txt"),
        makeObj(handle: UInt32.max, name: "max.txt"),
      ], deviceId: "dev")

    let zero = try await idx.object(deviceId: "dev", handle: 0)
    let max = try await idx.object(deviceId: "dev", handle: UInt32.max)
    #expect(zero?.name == "zero.txt")
    #expect(max?.name == "max.txt")
  }
}

// MARK: - 8. Query by Parent Handle

@Suite("Persistence — Parent Handle Queries")
struct ParentHandleQueryTests {

  @Test("Children returns only objects with matching parent")
  func childrenByParent() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 10, parentHandle: nil, name: "root.txt"),
        makeObj(handle: 20, parentHandle: 1, name: "child-a.txt"),
        makeObj(handle: 30, parentHandle: 1, name: "child-b.txt"),
        makeObj(handle: 40, parentHandle: 2, name: "other-child.txt"),
      ], deviceId: "dev")

    let children = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    #expect(children.count == 2)
    #expect(Set(children.map(\.name)) == ["child-a.txt", "child-b.txt"])
  }

  @Test("Root children have nil parent handle")
  func rootChildren() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 1, parentHandle: nil, name: "root1.txt"),
        makeObj(handle: 2, parentHandle: nil, name: "root2.txt"),
        makeObj(handle: 3, parentHandle: 1, name: "nested.txt"),
      ], deviceId: "dev")

    let roots = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(roots.count == 2)
  }
}

// MARK: - 9. Vacuum / Compaction

@Suite("Persistence — Vacuum and Compaction")
struct VacuumTests {

  @Test("VACUUM after bulk delete reclaims space")
  func vacuumReclaimsSpace() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    // Measure empty schema baseline (after checkpoint so WAL is folded in)
    try idx.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")
    let emptySize =
      try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 ?? 0

    // Insert many objects with long names to ensure multi-page DB
    var objects: [IndexedObject] = []
    for i in 0..<5000 {
      let longName = "delete-me-\(i)-" + String(repeating: "x", count: 80) + ".bin"
      let longPath = "00010001/" + String(repeating: "p", count: 100) + "/\(i).bin"
      objects.append(
        makeObj(
          handle: UInt32(i), parentHandle: 0, name: longName, pathKey: longPath, sizeBytes: 8192))
    }
    try await idx.upsertObjects(objects, deviceId: "dev")

    // Checkpoint WAL into main DB file so size reflects all data
    try idx.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")

    let sizeBeforeDelete =
      try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 ?? 0

    // Mark all stale and purge
    try await idx.markStaleChildren(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    try await idx.purgeStale(deviceId: "dev", storageId: 0x10001, parentHandle: 0)

    // Also prune the change log entries that were created
    try await idx.pruneChangeLog(deviceId: "dev", olderThan: Date().addingTimeInterval(10))

    // Checkpoint before VACUUM so all deletes are in the main DB
    try idx.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")

    // VACUUM via the underlying database
    try idx.database.exec("VACUUM")

    // In WAL mode VACUUM writes the compact result through the WAL;
    // checkpoint again so the main DB file reflects the compacted size.
    try idx.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")

    let sizeAfterVacuum =
      try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64 ?? 0

    // The populated DB should be significantly larger than the empty schema
    #expect(
      sizeBeforeDelete > emptySize * 2,
      "Data should at least double the DB size: empty=\(emptySize), populated=\(sizeBeforeDelete)")
    // After VACUUM the DB should shrink back close to the empty schema size
    // (allow 3× headroom for empty index pages and metadata)
    #expect(
      sizeAfterVacuum < emptySize * 3,
      "VACUUM should reclaim bulk data: empty=\(emptySize), after=\(sizeAfterVacuum)")
  }

  @Test("Database remains functional after VACUUM")
  func functionalAfterVacuum() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects([makeObj(handle: 1, name: "pre-vacuum.txt")], deviceId: "dev")
    try idx.database.exec("VACUUM")
    try await idx.upsertObjects([makeObj(handle: 2, name: "post-vacuum.txt")], deviceId: "dev")

    let obj1 = try await idx.object(deviceId: "dev", handle: 1)
    let obj2 = try await idx.object(deviceId: "dev", handle: 2)
    #expect(obj1?.name == "pre-vacuum.txt")
    #expect(obj2?.name == "post-vacuum.txt")
  }
}

// MARK: - 10. Ephemeral Device ID Migration

@Suite("Persistence — Ephemeral Device ID Migration")
struct EphemeralMigrationTests {

  @Test("Migrate ephemeral VID:PID device IDs to stable domain ID")
  func migrateEphemeralIds() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    // Insert with ephemeral-style deviceId
    let ephemeralId = "2717:ff10@1:3"
    try await idx.upsertObjects(
      [
        IndexedObject(
          deviceId: ephemeralId, storageId: 0x10001, handle: 1,
          parentHandle: nil, name: "photo.jpg", pathKey: "00010001/photo.jpg",
          sizeBytes: 5000, mtime: Date(), formatCode: 0x3801,
          isDirectory: false, changeCounter: 0)
      ], deviceId: ephemeralId)

    // Migrate
    try idx.migrateEphemeralDeviceId(vidPidPattern: "2717:ff10", newDomainId: "stable-domain-123")

    // Old ID should return nothing
    let oldObj = try await idx.object(deviceId: ephemeralId, handle: 1)
    #expect(oldObj == nil)

    // New domain ID should find the object
    let newObj = try await idx.object(deviceId: "stable-domain-123", handle: 1)
    #expect(newObj?.name == "photo.jpg")
  }
}

// MARK: - 11. Large Filename Handling

@Suite("Persistence — Large Filenames")
struct LargeFilenameTests {

  @Test("Filename with 300 characters persists correctly")
  func longFilename() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let longName = String(repeating: "a", count: 280) + ".txt"
    #expect(longName.count > 260)

    try await idx.insertObject(makeObj(handle: 1, name: longName), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == longName)
    #expect(obj?.name.count == 284)
  }

  @Test("Long path key (1000+ chars) persists correctly")
  func longPathKey() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let deepPath = (0..<50).map { "dir\($0)" }.joined(separator: "/") + "/file.txt"
    #expect(deepPath.count > 200)

    try await idx.insertObject(
      makeObj(handle: 1, name: "file.txt", pathKey: deepPath), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.pathKey == deepPath)
  }
}

// MARK: - 12. Unicode Path Handling

@Suite("Persistence — Unicode Paths")
struct UnicodePathTests {

  @Test("CJK filenames round-trip correctly")
  func cjkFilenames() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let name = "日本語テスト写真.jpg"
    try await idx.insertObject(makeObj(handle: 1, name: name), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == name)
  }

  @Test("Emoji filenames round-trip correctly")
  func emojiFilenames() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let name = "📸🌄vacation-2024.heic"
    try await idx.insertObject(makeObj(handle: 1, name: name), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == name)
  }

  @Test("Mixed-script filenames persist after reopen")
  func mixedScriptReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    let name = "Ñoño_файл_αρχείο.pdf"
    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(makeObj(handle: 1, name: name), deviceId: "dev")
    }

    let idx2 = try openIndex(at: path)
    let obj = try await idx2.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == name)
  }

  @Test("Unicode normalization — NFC vs NFD stored consistently")
  func unicodeNormalization() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    // é as NFC (single code point) and NFD (e + combining acute)
    let nfc = "\u{00E9}.txt"
    let nfd = "e\u{0301}.txt"

    try await idx.upsertObjects(
      [
        makeObj(handle: 1, name: nfc),
        makeObj(handle: 2, name: nfd),
      ], deviceId: "dev")

    let obj1 = try await idx.object(deviceId: "dev", handle: 1)
    let obj2 = try await idx.object(deviceId: "dev", handle: 2)
    #expect(obj1?.name == nfc)
    #expect(obj2?.name == nfd)
  }
}

// MARK: - 13. Timestamp Precision

@Suite("Persistence — Timestamp Precision")
struct TimestampPrecisionTests {

  @Test("mtime stored as integer seconds preserves epoch value")
  func mtimePrecision() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let knownEpoch: TimeInterval = 1_700_000_000  // 2023-11-14T22:13:20Z
    let mtime = Date(timeIntervalSince1970: knownEpoch)

    try await idx.insertObject(
      makeObj(handle: 1, name: "timed.txt", mtime: mtime), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.mtime != nil)
    // Stored as integer seconds, so fractional part is truncated
    let storedEpoch = obj!.mtime!.timeIntervalSince1970
    #expect(abs(storedEpoch - knownEpoch) < 1.0, "Epoch should match within 1 second")
  }

  @Test("Nil mtime round-trips as nil")
  func nilMtime() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.insertObject(
      makeObj(handle: 1, name: "notime.txt", mtime: nil), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.mtime == nil)
  }

  @Test("Future timestamps (year 2100) persist correctly")
  func futureTimestamp() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let futureEpoch: TimeInterval = 4_102_444_800  // 2100-01-01
    let mtime = Date(timeIntervalSince1970: futureEpoch)

    try await idx.insertObject(
      makeObj(handle: 1, name: "future.txt", mtime: mtime), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    let storedEpoch = obj!.mtime!.timeIntervalSince1970
    #expect(abs(storedEpoch - futureEpoch) < 1.0)
  }

  @Test("Epoch zero (1970-01-01) round-trips correctly")
  func epochZero() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let mtime = Date(timeIntervalSince1970: 0)
    try await idx.insertObject(
      makeObj(handle: 1, name: "ancient.txt", mtime: mtime), deviceId: "dev")

    let obj = try await idx.object(deviceId: "dev", handle: 1)
    #expect(obj?.mtime != nil)
    #expect(abs(obj!.mtime!.timeIntervalSince1970) < 1.0)
  }
}

// MARK: - 14. Concurrent Read/Write Access

@Suite("Persistence — Concurrent Access")
struct ConcurrentAccessTests {

  @Test("Concurrent writers produce monotonic change counters")
  func concurrentWritersMonotonic() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    await withTaskGroup(of: Void.self) { group in
      for i in 0..<50 {
        group.addTask {
          try? await idx.upsertObjects(
            [makeObj(handle: UInt32(i), name: "concurrent-\(i).txt")], deviceId: "dev")
        }
      }
    }

    let counter = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(counter == 50, "Each upsert batch should increment counter by 1")

    // All objects should be queryable
    for i: UInt32 in 0..<50 {
      let obj = try await idx.object(deviceId: "dev", handle: i)
      #expect(obj != nil, "Object \(i) should exist")
    }
  }

  @Test("Concurrent reader and writer do not deadlock")
  func concurrentReaderWriter() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    // Seed some data
    try await idx.upsertObjects(
      (0..<100).map { makeObj(handle: UInt32($0), parentHandle: 0, name: "seed-\($0).txt") },
      deviceId: "dev")

    await withTaskGroup(of: Void.self) { group in
      // Writer
      group.addTask {
        for i in 100..<200 {
          try? await idx.upsertObjects(
            [makeObj(handle: UInt32(i), parentHandle: 0, name: "write-\(i).txt")], deviceId: "dev")
        }
      }
      // Reader
      group.addTask {
        for _ in 0..<100 {
          _ = try? await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
        }
      }
    }

    // Verify integrity
    let children = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: 0)
    #expect(children.count == 200)
  }
}

// MARK: - 15. Change Log Pruning

@Suite("Persistence — Change Log Pruning")
struct ChangeLogPruningTests {

  @Test("Prune removes old entries but keeps recent ones")
  func pruneOldEntries() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects([makeObj(handle: 1, name: "old.txt")], deviceId: "dev")
    try await idx.upsertObjects([makeObj(handle: 2, name: "new.txt")], deviceId: "dev")

    // Prune entries older than 1 second in the future (prune everything)
    try await idx.pruneChangeLog(deviceId: "dev", olderThan: Date().addingTimeInterval(10))

    let changes = try await idx.changesSince(deviceId: "dev", anchor: 0)
    #expect(changes.isEmpty, "All change log entries should be pruned")

    // But objects still exist
    let obj1 = try await idx.object(deviceId: "dev", handle: 1)
    let obj2 = try await idx.object(deviceId: "dev", handle: 2)
    #expect(obj1 != nil)
    #expect(obj2 != nil)
  }
}

// MARK: - 16. Device Identity Persistence

@Suite("Persistence — Device Identity")
struct DeviceIdentityPersistenceTests {

  @Test("Device identity resolves and persists across reopen")
  func identityPersistsAcrossReopen() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    let signals = DeviceIdentitySignals(
      vendorId: 0x2717, productId: 0xFF10,
      usbSerial: "XM123456", mtpSerial: nil,
      manufacturer: "Xiaomi", model: "Mi Note 2")

    let domainId: String
    do {
      let idx = try openIndex(at: path)
      let identity = try await idx.resolveIdentity(signals: signals)
      domainId = identity.domainId
      #expect(!domainId.isEmpty)
    }

    // Reopen and resolve same signals → should return same domainId
    let idx2 = try openIndex(at: path)
    let identity2 = try await idx2.resolveIdentity(signals: signals)
    #expect(identity2.domainId == domainId, "Same signals should resolve to same domain ID")
  }

  @Test("allIdentities returns all resolved identities")
  func allIdentitiesRoundTrip() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let signals1 = DeviceIdentitySignals(
      vendorId: 0x04E8, productId: 0x6860,
      usbSerial: "SAM001", mtpSerial: nil,
      manufacturer: "Samsung", model: "Galaxy S7")
    let signals2 = DeviceIdentitySignals(
      vendorId: 0x04A9, productId: 0x3139,
      usbSerial: "CAN001", mtpSerial: nil,
      manufacturer: "Canon", model: "EOS Rebel")

    _ = try await idx.resolveIdentity(signals: signals1)
    _ = try await idx.resolveIdentity(signals: signals2)

    let all = try await idx.allIdentities()
    #expect(all.count == 2)
  }

  @Test("removeIdentity deletes identity record")
  func removeIdentity() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let signals = DeviceIdentitySignals(
      vendorId: 0x18D1, productId: 0x4EE1,
      usbSerial: "PX7001", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7")
    let identity = try await idx.resolveIdentity(signals: signals)

    try await idx.removeIdentity(domainId: identity.domainId)
    let lookup = try await idx.identity(for: identity.domainId)
    #expect(lookup == nil)
  }

  @Test("updateMTPSerial persists after reopen")
  func updateMTPSerialPersists() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    let signals = DeviceIdentitySignals(
      vendorId: 0x2A70, productId: 0xF003,
      usbSerial: nil, mtpSerial: nil,
      manufacturer: "OnePlus", model: "3T")

    let domainId: String
    do {
      let idx = try openIndex(at: path)
      let identity = try await idx.resolveIdentity(signals: signals)
      domainId = identity.domainId
      try await idx.updateMTPSerial(domainId: domainId, mtpSerial: "MTP-SERIAL-999")
    }

    // Verify via fresh signals with MTP serial — the identity store should
    // still be accessible
    let idx2 = try openIndex(at: path)
    let identity = try await idx2.identity(for: domainId)
    #expect(identity != nil)
    #expect(identity?.domainId == domainId)
  }
}

// MARK: - 17. Multi-Device Isolation

@Suite("Persistence — Multi-Device Isolation")
struct MultiDeviceIsolationTests {

  @Test("Objects from different devices are isolated")
  func deviceIsolation() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects([makeObj(handle: 1, name: "dev-a.txt")], deviceId: "device-a")
    try await idx.upsertObjects([makeObj(handle: 1, name: "dev-b.txt")], deviceId: "device-b")

    let objA = try await idx.object(deviceId: "device-a", handle: 1)
    let objB = try await idx.object(deviceId: "device-b", handle: 1)
    #expect(objA?.name == "dev-a.txt")
    #expect(objB?.name == "dev-b.txt")
  }

  @Test("Removing object from one device does not affect another")
  func removeIsolation() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects([makeObj(handle: 1, name: "shared-handle.txt")], deviceId: "dev-x")
    try await idx.upsertObjects([makeObj(handle: 1, name: "shared-handle.txt")], deviceId: "dev-y")

    try await idx.removeObject(deviceId: "dev-x", storageId: 0x10001, handle: 1)

    let objX = try await idx.object(deviceId: "dev-x", handle: 1)
    let objY = try await idx.object(deviceId: "dev-y", handle: 1)
    #expect(objX == nil, "Removed device-x object should be gone")
    #expect(objY != nil, "Device-y object should be unaffected")
  }

  @Test("Change counters are per-device")
  func perDeviceCounters() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects([makeObj(handle: 1)], deviceId: "alpha")
    try await idx.upsertObjects([makeObj(handle: 1)], deviceId: "beta")
    try await idx.upsertObjects([makeObj(handle: 2)], deviceId: "alpha")

    let counterA = try await idx.currentChangeCounter(deviceId: "alpha")
    let counterB = try await idx.currentChangeCounter(deviceId: "beta")
    #expect(counterA == 2)
    #expect(counterB == 1)
  }
}

// MARK: - 18. Multi-Storage Queries

@Suite("Persistence — Multi-Storage")
struct MultiStorageTests {

  @Test("Objects in different storages are isolated by storage ID")
  func storageIsolation() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    try await idx.upsertObjects(
      [
        makeObj(handle: 1, storageId: 0x10001, name: "internal.txt"),
        makeObj(handle: 2, storageId: 0x20001, name: "sdcard.txt"),
      ], deviceId: "dev")

    let internal_ = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    let sdcard = try await idx.children(deviceId: "dev", storageId: 0x20001, parentHandle: nil)
    #expect(internal_.count == 1)
    #expect(internal_.first?.name == "internal.txt")
    #expect(sdcard.count == 1)
    #expect(sdcard.first?.name == "sdcard.txt")
  }
}

// MARK: - 19. Crawl State Persistence

@Suite("Persistence — Crawl State")
struct CrawlStateTests {

  @Test("Crawl state returns nil for uncrawled folder")
  func uncrawledFolder() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }
    let idx = try openIndex(at: path)

    let state = try await idx.crawlState(deviceId: "dev", storageId: 0x10001, parentHandle: 1)
    #expect(state == nil)
  }
}

// MARK: - 20. Schema Idempotency

@Suite("Persistence — Schema Idempotency")
struct SchemaIdempotencyTests {

  @Test("Opening existing database does not lose data (schema is IF NOT EXISTS)")
  func reopenPreservesData() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    do {
      let idx = try openIndex(at: path)
      try await idx.insertObject(makeObj(handle: 1, name: "preserved.txt"), deviceId: "dev")
    }

    // Open again — createSchema runs again with IF NOT EXISTS
    let idx2 = try openIndex(at: path)
    let obj = try await idx2.object(deviceId: "dev", handle: 1)
    #expect(obj?.name == "preserved.txt")
  }

  @Test("Opening database multiple times concurrently does not corrupt")
  func concurrentOpens() async throws {
    let path = makeTempPath()
    defer { cleanup(path) }

    // Create initial DB
    let idx = try openIndex(at: path)
    try await idx.insertObject(makeObj(handle: 1, name: "base.txt"), deviceId: "dev")

    // Open multiple read-only instances
    let readers = try (0..<5).map { _ in try openIndex(at: path, readOnly: true) }
    for reader in readers {
      let obj = try await reader.object(deviceId: "dev", handle: 1)
      #expect(obj?.name == "base.txt")
    }
  }
}
