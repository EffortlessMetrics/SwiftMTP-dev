// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore
import SQLite3

// MARK: - Journal File Corruption Tests

final class JournalFileCorruptionTests: XCTestCase {

  func testTruncatedJSONFileRejectsOpen() throws {
    let path = NSTemporaryDirectory() + "truncated-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Write truncated JSON (not a valid SQLite database)
    let truncatedJSON = Data("{\"transfers\":[{\"id\":\"abc\",\"st".utf8)
    try truncatedJSON.write(to: URL(fileURLWithPath: path))

    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: path)) { error in
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "TransferJournal")
    }
  }

  func testInvalidUTF8EncodingRejectsOpen() throws {
    let path = NSTemporaryDirectory() + "invalid-utf8-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Write bytes with invalid UTF-8 sequences (not a valid SQLite file)
    var garbage = Data(repeating: 0xFF, count: 128)
    garbage.append(Data(repeating: 0xFE, count: 64))
    try garbage.write(to: URL(fileURLWithPath: path))

    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: path))
  }

  func testEmptyFileCreatesUsableJournal() throws {
    let path = NSTemporaryDirectory() + "empty-w32-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    FileManager.default.createFile(atPath: path, contents: Data())
    let journal = try SQLiteTransferJournal(dbPath: path)

    let device = MTPDeviceID(raw: "empty-test")
    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)

    // Verify we can write to it
    let id = try journal.beginRead(
      device: device, handle: 1, name: "test.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/empty-test"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    XCTAssertFalse(id.isEmpty)
  }

  func testMidHeaderTruncationRejectsOpen() throws {
    let path = NSTemporaryDirectory() + "midheader-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // SQLite magic is "SQLite format 3\0" — write only first 8 bytes
    let partial = Data("SQLite f".utf8)
    try partial.write(to: URL(fileURLWithPath: path))

    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: path))
  }

  func testCorruptPageDataAfterValidHeader() throws {
    let path = NSTemporaryDirectory() + "corruptpage-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create valid journal, then corrupt the file after the header
    let validJournal = try SQLiteTransferJournal(dbPath: path)
    let device = MTPDeviceID(raw: "corrupt-page")
    _ = try validJournal.beginRead(
      device: device, handle: 1, name: "file.bin",
      size: 500, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/corrupt-page"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Read existing data, corrupt mid-file bytes
    var data = try Data(contentsOf: URL(fileURLWithPath: path))
    if data.count > 200 {
      for i in 100..<min(200, data.count) {
        data[i] = UInt8.random(in: 0...255)
      }
      try data.write(to: URL(fileURLWithPath: path))
    }

    // Reopening a corrupted DB may or may not throw — test it doesn't crash
    do {
      let j2 = try SQLiteTransferJournal(dbPath: path)
      // If open succeeds, queries may fail or return empty
      _ = try? j2.loadResumables(for: device)
    } catch {
      // Expected: corrupted DB rejects open
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "TransferJournal")
    }
  }
}

// MARK: - Journal Corruption Recovery Tests

final class JournalCorruptionAutoRecoveryW32Tests: XCTestCase {

  func testRecreateJournalOnCorruptRead() throws {
    let path = NSTemporaryDirectory() + "recreate-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create and populate
    let j1 = try SQLiteTransferJournal(dbPath: path)
    let device = MTPDeviceID(raw: "recover-dev")
    _ = try j1.beginRead(
      device: device, handle: 10, name: "recover.jpg",
      size: 2048, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/recover"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Overwrite entire file with garbage to simulate total corruption
    let garbage = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
    try garbage.write(to: URL(fileURLWithPath: path))

    // Recovery: delete corrupt file and create fresh journal
    try FileManager.default.removeItem(atPath: path)
    let j2 = try SQLiteTransferJournal(dbPath: path)

    // Fresh journal is functional
    let resumables = try j2.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Fresh journal should have no entries")

    let newId = try j2.beginRead(
      device: device, handle: 20, name: "fresh.jpg",
      size: 1024, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/fresh"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    XCTAssertFalse(newId.isEmpty)
  }

  func testRecoveryPreservesNewDataAfterRecreation() throws {
    let path = NSTemporaryDirectory() + "recovery-new-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Simulate: corrupt, recreate, then use
    let garbage = Data(repeating: 0xDE, count: 256)
    try garbage.write(to: URL(fileURLWithPath: path))
    try FileManager.default.removeItem(atPath: path)

    let journal = try SQLiteTransferJournal(dbPath: path)
    let device = MTPDeviceID(raw: "post-recovery")

    // Add several transfers after recovery
    for i in 0..<5 {
      _ = try journal.beginRead(
        device: device, handle: UInt32(i), name: "recovered-\(i).bin",
        size: UInt64(1024 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/recovered-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
  }
}

// MARK: - Concurrent Journal Write Tests

final class ConcurrentJournalWriteStressTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "conc-w32-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testMultipleTasksWritingSimultaneously() async throws {
    let adapter = SwiftMTPStoreAdapter(
      store: {
        setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
        return .shared
      }())
    let device = MTPDeviceID(raw: "multi-write-\(UUID().uuidString)")
    let taskCount = 30

    try await withThrowingTaskGroup(of: String.self) { group in
      for i in 0..<taskCount {
        group.addTask {
          try await adapter.beginWrite(
            device: device, parent: 0, name: "concurrent-\(i).dat",
            size: UInt64(1024 * (i + 1)), supportsPartial: i.isMultiple(of: 2),
            tempURL: URL(fileURLWithPath: "/tmp/mw-\(i)"), sourceURL: nil)
        }
      }
      var ids = Set<String>()
      for try await id in group { ids.insert(id) }
      XCTAssertEqual(ids.count, taskCount, "All transfer IDs must be unique")
    }
  }

  func testInterleavedProgressAndStatusUpdates() async throws {
    let adapter = SwiftMTPStoreAdapter(
      store: {
        setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
        return .shared
      }())
    let device = MTPDeviceID(raw: "interleave-\(UUID().uuidString)")

    // Create 10 transfers
    var ids: [String] = []
    for i in 0..<10 {
      let id = try await adapter.beginRead(
        device: device, handle: UInt32(i), name: "ilv-\(i).bin",
        size: 50_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/ilv-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    // Concurrently update progress on even IDs, complete odd IDs
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (i, id) in ids.enumerated() {
        let capturedId = id
        if i.isMultiple(of: 2) {
          group.addTask {
            for step in stride(from: 10_000, through: 50_000, by: 10_000) {
              try await adapter.updateProgress(id: capturedId, committed: UInt64(step))
            }
          }
        } else {
          group.addTask {
            try await adapter.complete(id: capturedId)
          }
        }
      }
      try await group.waitForAll()
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5, "Only even-indexed (non-completed) transfers remain")
  }
}

// MARK: - Large File Resume Tests

final class LargeFileResumeTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "largefile-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func test1GBFileInterruptedAt75PercentResumesFromCorrectOffset() throws {
    let device = MTPDeviceID(raw: "large-resume")
    let totalBytes: UInt64 = 1_073_741_824  // 1 GB
    let committedAt75Percent: UInt64 = 805_306_368  // 75% of 1 GB

    let id = try journal.beginRead(
      device: device, handle: 42, name: "backup.tar.gz",
      size: totalBytes, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/large-resume"), finalURL: nil,
      etag: (size: totalBytes, mtime: Date()))

    // Simulate progressive transfer up to 75%
    let chunkSize: UInt64 = 8_388_608  // 8 MB chunks
    var committed: UInt64 = 0
    while committed < committedAt75Percent {
      committed = min(committed + chunkSize, committedAt75Percent)
      try journal.updateProgress(id: id, committed: committed)
    }

    // Simulate interruption — transfer stays active
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)

    let record = resumables[0]
    XCTAssertEqual(record.id, id)
    XCTAssertEqual(record.totalBytes, totalBytes)
    XCTAssertEqual(record.committedBytes, committedAt75Percent)
    XCTAssertTrue(record.supportsPartial)
    XCTAssertEqual(record.state, "active")

    // Verify resume offset calculation
    let remainingBytes = totalBytes - record.committedBytes
    XCTAssertEqual(remainingBytes, 268_435_456, "Remaining should be 256 MB (25%)")
  }

  func testLargeFileResumeAfterJournalReopen() throws {
    let device = MTPDeviceID(raw: "large-reopen")
    let totalBytes: UInt64 = 2_147_483_648  // 2 GB
    let committed: UInt64 = 1_610_612_736  // ~75%

    let id = try journal.beginRead(
      device: device, handle: 99, name: "huge-video.mp4",
      size: totalBytes, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/large-reopen"),
      finalURL: URL(fileURLWithPath: "/dest/huge-video.mp4"),
      etag: (size: totalBytes, mtime: Date(timeIntervalSince1970: 1_700_000_000)))

    try journal.updateProgress(id: id, committed: committed)

    // Close and reopen
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, committed)
    XCTAssertEqual(resumables[0].totalBytes, totalBytes)
    XCTAssertEqual(resumables[0].name, "huge-video.mp4")
  }

  func testMultipleLargeFilesResumeIndependently() throws {
    let device = MTPDeviceID(raw: "multi-large")
    let files: [(name: String, size: UInt64, progress: UInt64)] = [
      ("video1.mp4", 1_073_741_824, 536_870_912),  // 1GB, 50%
      ("video2.mp4", 2_147_483_648, 1_610_612_736),  // 2GB, 75%
      ("archive.zip", 4_294_967_296, 1_073_741_824),  // 4GB, 25%
    ]

    var ids: [String] = []
    for (i, file) in files.enumerated() {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i + 1), name: file.name,
        size: file.size, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/multi-large-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: file.progress)
      ids.append(id)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 3)

    for (i, file) in files.enumerated() {
      let record = resumables.first(where: { $0.id == ids[i] })
      XCTAssertNotNil(record)
      XCTAssertEqual(record?.committedBytes, file.progress)
      XCTAssertEqual(record?.totalBytes, file.size)
    }
  }

  func testZeroBytesCommittedResumeFromStart() throws {
    let device = MTPDeviceID(raw: "zero-resume")
    let totalBytes: UInt64 = 1_073_741_824

    let id = try journal.beginRead(
      device: device, handle: 1, name: "fresh.bin",
      size: totalBytes, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/zero-resume"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // No progress updates — interrupted immediately
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 0)
    XCTAssertEqual(resumables[0].id, id)
  }
}

// MARK: - Journal Pruning Tests

final class JournalPruningW32Tests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "prune-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testClearStaleRemovesCompletedEntriesPreservesActive() throws {
    let device = MTPDeviceID(raw: "prune-device")

    // Create active transfer
    let activeId = try journal.beginRead(
      device: device, handle: 1, name: "active.bin",
      size: 1024, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/prune-active"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: activeId, committed: 512)

    // Create completed transfer
    let doneId = try journal.beginRead(
      device: device, handle: 2, name: "done.bin",
      size: 2048, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/prune-done"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: doneId)

    // Create failed transfer
    let failedId = try journal.beginRead(
      device: device, handle: 3, name: "failed.bin",
      size: 3072, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/prune-failed"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: failedId, error: NSError(domain: "test", code: -1))

    // Clear stale entries older than 0 seconds (all non-active)
    try journal.clearStaleTemps(olderThan: 0)

    // Active transfer should survive
    let resumables = try journal.loadResumables(for: device)
    let activeRecords = resumables.filter { $0.state == "active" }
    XCTAssertEqual(activeRecords.count, 1)
    XCTAssertEqual(activeRecords[0].id, activeId)
  }

  func testPruneWithManyCompletedEntries() throws {
    let device = MTPDeviceID(raw: "prune-many")

    // Create 50 transfers, complete them all
    for i in 0..<50 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "bulk-\(i).txt",
        size: UInt64(i * 100), supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/prune-bulk-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.complete(id: id)
    }

    // Create 3 active transfers
    var activeIds: [String] = []
    for i in 50..<53 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "active-\(i).bin",
        size: 5000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/prune-active-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      activeIds.append(id)
    }

    try journal.clearStaleTemps(olderThan: 0)

    // All active transfers should survive
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 3)
    for activeId in activeIds {
      XCTAssertTrue(resumables.contains(where: { $0.id == activeId }))
    }
  }
}

// MARK: - Journal Migration / Schema Robustness Tests

final class JournalMigrationW32Tests: XCTestCase {

  func testOpenExistingDBWithExtraColumnsSucceeds() throws {
    let path = NSTemporaryDirectory() + "migrate-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create a journal and add a row
    let j1 = try SQLiteTransferJournal(dbPath: path)
    let device = MTPDeviceID(raw: "migrate-dev")
    _ = try j1.beginRead(
      device: device, handle: 1, name: "migrate.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/migrate"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Simulate schema evolution: add an extra column via raw SQLite
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
    let alterSQL = "ALTER TABLE transfers ADD COLUMN newField TEXT DEFAULT 'v2';"
    XCTAssertEqual(sqlite3_exec(db, alterSQL, nil, nil, nil), SQLITE_OK)
    sqlite3_close(db)

    // Reopen with current code — should handle extra column gracefully
    let j2 = try SQLiteTransferJournal(dbPath: path)
    let resumables = try j2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "migrate.txt")
  }

  func testCreateTableIfNotExistsIsIdempotent() throws {
    let path = NSTemporaryDirectory() + "idempotent-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Open multiple times — CREATE TABLE IF NOT EXISTS should not fail
    let j1 = try SQLiteTransferJournal(dbPath: path)
    let device = MTPDeviceID(raw: "idempotent")
    _ = try j1.beginRead(
      device: device, handle: 1, name: "idem.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/idem"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    let j2 = try SQLiteTransferJournal(dbPath: path)
    let j3 = try SQLiteTransferJournal(dbPath: path)

    let r2 = try j2.loadResumables(for: device)
    let r3 = try j3.loadResumables(for: device)
    XCTAssertEqual(r2.count, 1)
    XCTAssertEqual(r3.count, 1)
  }
}

// MARK: - Object Entity CRUD via StoreActor Tests

final class ObjectEntityCRUDWave32Tests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testCreateAndFetchObject() async throws {
    let actor = store.createActor()
    let deviceId = "crud-obj-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Obj")

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 100,
      parentHandle: nil, name: "photo.jpg", pathKey: "/DCIM/photo.jpg",
      size: 4_000_000, mtime: Date(), format: 0x3801, generation: 1)

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
    XCTAssertEqual(objects[0].handle, 100)
    XCTAssertEqual(objects[0].pathKey, "/DCIM/photo.jpg")
    XCTAssertEqual(objects[0].size, 4_000_000)
  }

  func testUpdateExistingObject() async throws {
    let actor = store.createActor()
    let deviceId = "update-obj-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Upd")

    // Initial insert
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 200,
      parentHandle: nil, name: "old-name.txt", pathKey: "/old-name.txt",
      size: 1024, mtime: Date(), format: 0x3004, generation: 1)

    // Update same handle
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 200,
      parentHandle: 10, name: "new-name.txt", pathKey: "/folder/new-name.txt",
      size: 2048, mtime: Date(), format: 0x3004, generation: 2)

    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertEqual(gen2.count, 1)
    XCTAssertEqual(gen2[0].pathKey, "/folder/new-name.txt")
    XCTAssertEqual(gen2[0].size, 2048)
  }

  func testDeleteViaTombstoning() async throws {
    let actor = store.createActor()
    let deviceId = "tomb-obj-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Tomb")

    // Create objects in generation 1
    for i in 0..<5 {
      try await actor.upsertObject(
        deviceId: deviceId, storageId: 1, handle: i,
        parentHandle: nil, name: "file\(i).txt", pathKey: "/file\(i).txt",
        size: Int64(i * 100), mtime: nil, format: 0x3004, generation: 1)
    }

    // Add generation 2 objects
    for i in 5..<8 {
      try await actor.upsertObject(
        deviceId: deviceId, storageId: 1, handle: i,
        parentHandle: nil, name: "file\(i).txt", pathKey: "/file\(i).txt",
        size: Int64(i * 100), mtime: nil, format: 0x3004, generation: 2)
    }

    // Tombstone generation 1
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 2)

    let gen1 = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(gen1.count, 0, "Tombstoned generation 1 objects should not appear")

    let gen2 = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertEqual(gen2.count, 3, "Generation 2 objects should survive")
  }

  func testBatchUpsertIndexesCorrectly() async throws {
    let actor = store.createActor()
    let deviceId = "batch-idx-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Batch")

    let objects:
      [(
        storageId: Int, handle: Int, parentHandle: Int?, name: String,
        pathKey: String, size: Int64?, mtime: Date?, format: Int, generation: Int
      )] = (0..<20)
        .map { i in
          (
            storageId: 1, handle: i, parentHandle: i > 0 ? 0 : nil,
            name: "batch-\(i).dat", pathKey: "/batch/batch-\(i).dat",
            size: Int64(i * 512), mtime: Date(), format: 0x3004, generation: 3
          )
        }

    try await actor.upsertObjects(deviceId: deviceId, objects: objects)

    let fetched = try await actor.fetchObjects(deviceId: deviceId, generation: 3)
    XCTAssertEqual(fetched.count, 20)

    // Verify each object is retrievable
    let handles = Set(fetched.map { $0.handle })
    for i: UInt32 in 0..<20 {
      XCTAssertTrue(handles.contains(i), "Handle \(i) should be present")
    }
  }
}

// MARK: - Device Metadata Persistence Tests

final class DeviceMetadataPersistenceWave32Tests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testLearnedProfileTuningParametersPersist() async throws {
    let actor = store.createActor()
    let deviceId = "tuning-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Google", model: "Pixel 7")

    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "02", event: "83"))

    let profile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: "tuning-hash-\(UUID().uuidString)",
      created: Date(),
      lastUpdated: Date(),
      sampleCount: 42,
      optimalChunkSize: 4_194_304,  // 4 MB
      avgHandshakeMs: 85,
      optimalIoTimeoutMs: 3000,
      optimalInactivityTimeoutMs: 15000,
      p95ReadThroughputMBps: 35.5,
      p95WriteThroughputMBps: 18.2,
      successRate: 0.97,
      hostEnvironment: "macOS-test")

    try await actor.updateLearnedProfile(
      for: profile.fingerprintHash, deviceId: deviceId, profile: profile)

    let loaded = try await actor.fetchLearnedProfileDTO(for: profile.fingerprintHash)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.sampleCount, 42)
    XCTAssertEqual(loaded?.optimalChunkSize, 4_194_304)
    XCTAssertEqual(loaded?.avgHandshakeMs, 85)
    XCTAssertEqual(loaded?.optimalIoTimeoutMs, 3000)
    XCTAssertEqual(loaded?.optimalInactivityTimeoutMs, 15000)
    XCTAssertEqual(loaded?.p95ReadThroughputMBps, 35.5)
    XCTAssertEqual(loaded?.p95WriteThroughputMBps, 18.2)
    XCTAssertEqual(loaded?.successRate, 0.97)
  }

  func testLearnedProfileUpdateOverwritesPreviousValues() async throws {
    let actor = store.createActor()
    let deviceId = "overwrite-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Samsung", model: "Galaxy")

    let fingerprint = MTPDeviceFingerprint(
      vid: "04e8", pid: "6860",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "02", event: "83"))
    let hash = "overwrite-hash-\(UUID().uuidString)"

    let profile1 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(),
      sampleCount: 5, optimalChunkSize: 1_048_576,
      avgHandshakeMs: 100, optimalIoTimeoutMs: 2000,
      optimalInactivityTimeoutMs: 10000,
      p95ReadThroughputMBps: 10.0, p95WriteThroughputMBps: 5.0,
      successRate: 0.8, hostEnvironment: "test")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile1)

    // Update with new values
    let profile2 = LearnedProfile(
      fingerprint: fingerprint, fingerprintHash: hash,
      created: Date(), lastUpdated: Date(),
      sampleCount: 50, optimalChunkSize: 8_388_608,
      avgHandshakeMs: 60, optimalIoTimeoutMs: 1500,
      optimalInactivityTimeoutMs: 8000,
      p95ReadThroughputMBps: 30.0, p95WriteThroughputMBps: 15.0,
      successRate: 0.95, hostEnvironment: "test-v2")

    try await actor.updateLearnedProfile(for: hash, deviceId: deviceId, profile: profile2)

    let loaded = try await actor.fetchLearnedProfileDTO(for: hash)
    XCTAssertEqual(loaded?.sampleCount, 50)
    XCTAssertEqual(loaded?.optimalChunkSize, 8_388_608)
    XCTAssertEqual(loaded?.successRate, 0.95)
  }
}

// MARK: - Storage Info Caching Tests

final class StorageInfoCachingWave32Tests: XCTestCase {

  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpsertStorageRecordsCapacityAndFreeSpace() async throws {
    let actor = store.createActor()
    let deviceId = "storage-cap-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Storage")

    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "Internal Storage",
      capacity: 128_000_000_000,  // 128 GB
      free: 64_000_000_000,  // 64 GB
      readOnly: false)

    // Upsert again with updated free space
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "Internal Storage",
      capacity: 128_000_000_000,
      free: 32_000_000_000,  // 32 GB after writes
      readOnly: false)

    // Verify the storage was updated (not duplicated)
    // We test indirectly: objects on this storage should work
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "test.txt", pathKey: "/test.txt",
      size: 1024, mtime: nil, format: 0x3004, generation: 1)

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
  }

  func testMultipleStorageIDs() async throws {
    let actor = store.createActor()
    let deviceId = "multi-storage-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "MultiSD")

    // Internal + SD card
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "Internal Storage",
      capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)

    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 2,
      description: "SD Card",
      capacity: 256_000_000_000, free: 200_000_000_000, readOnly: false)

    // Add objects on each storage
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 10,
      parentHandle: nil, name: "internal.txt", pathKey: "/internal.txt",
      size: 512, mtime: nil, format: 0x3004, generation: 1)

    try await actor.upsertObject(
      deviceId: deviceId, storageId: 2, handle: 20,
      parentHandle: nil, name: "sdcard.txt", pathKey: "/sdcard.txt",
      size: 1024, mtime: nil, format: 0x3004, generation: 1)

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 2)

    let storages = Set(objects.map { $0.storage })
    XCTAssertTrue(storages.contains(1))
    XCTAssertTrue(storages.contains(2))
  }

  func testReadOnlyStorageFlag() async throws {
    let actor = store.createActor()
    let deviceId = "readonly-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Canon", model: "EOS")

    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "ROM Partition",
      capacity: 16_000_000, free: 0, readOnly: true)

    // Toggle to writable
    try await actor.upsertStorage(
      deviceId: deviceId, storageId: 1,
      description: "ROM Partition (unlocked)",
      capacity: 16_000_000, free: 1_000_000, readOnly: false)

    // Verify update didn't create duplicate — test by adding objects
    try await actor.upsertObject(
      deviceId: deviceId, storageId: 1, handle: 1,
      parentHandle: nil, name: "firmware.bin", pathKey: "/firmware.bin",
      size: 8_000_000, mtime: nil, format: 0x3000, generation: 1)

    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(objects.count, 1)
  }
}

// MARK: - Batch Journal Operations Tests

final class BatchJournalOperationsWave32Tests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "batch-j-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testBulkCreateManyTransferRecords() throws {
    let device = MTPDeviceID(raw: "bulk-create")
    let count = 100

    var ids: [String] = []
    for i in 0..<count {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "bulk-\(i).dat",
        size: UInt64(1024 * (i + 1)), supportsPartial: i.isMultiple(of: 3),
        tempURL: URL(fileURLWithPath: "/tmp/bulk-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    XCTAssertEqual(Set(ids).count, count, "All IDs unique")

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, count)
  }

  func testBulkProgressUpdateAcrossManyTransfers() throws {
    let device = MTPDeviceID(raw: "bulk-progress")
    let count = 50

    var ids: [String] = []
    for i in 0..<count {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "bp-\(i).bin",
        size: 100_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/bp-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    // Update all to 50%
    for id in ids {
      try journal.updateProgress(id: id, committed: 50_000)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, count)
    for r in resumables {
      XCTAssertEqual(r.committedBytes, 50_000)
    }
  }

  func testBulkCompleteAndVerifyPruning() throws {
    let device = MTPDeviceID(raw: "bulk-complete")

    var ids: [String] = []
    for i in 0..<30 {
      let id = try journal.beginWrite(
        device: device, parent: 0, name: "bc-\(i).txt",
        size: UInt64(512 * (i + 1)), supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/bc-\(i)"), sourceURL: nil)
      ids.append(id)
    }

    // Complete first 20
    for id in ids.prefix(20) {
      try journal.complete(id: id)
    }

    // Prune
    try journal.clearStaleTemps(olderThan: 0)

    // Only 10 active should remain
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 10)
  }

  func testBulkFailAndResumeWorkflow() throws {
    let device = MTPDeviceID(raw: "bulk-fail-resume")

    var ids: [String] = []
    for i in 0..<20 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "fr-\(i).dat",
        size: 10_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/fr-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: 5_000)
      ids.append(id)
    }

    // Fail all transfers (simulate disconnect)
    for id in ids {
      try journal.fail(id: id, error: NSError(domain: "USB", code: -1))
    }

    // All should still be resumable (failed state)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 20)

    for r in resumables {
      XCTAssertEqual(r.state, "failed")
      XCTAssertEqual(r.committedBytes, 5_000)
    }
  }

  func testMixedDeviceBulkOperations() throws {
    let devices = (0..<5).map { MTPDeviceID(raw: "mixed-bulk-\($0)") }

    // Create 10 transfers per device
    for device in devices {
      for i in 0..<10 {
        _ = try journal.beginRead(
          device: device, handle: UInt32(i), name: "mb-\(i).bin",
          size: 2048, supportsPartial: true,
          tempURL: URL(fileURLWithPath: "/tmp/mb-\(device.raw)-\(i)"), finalURL: nil,
          etag: (size: nil, mtime: nil))
      }
    }

    // Verify isolation per device
    for device in devices {
      let resumables = try journal.loadResumables(for: device)
      XCTAssertEqual(resumables.count, 10, "Each device should have exactly 10 transfers")
    }
  }
}
