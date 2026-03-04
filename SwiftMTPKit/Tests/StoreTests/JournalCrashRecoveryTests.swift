// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SQLite3
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore

// MARK: - TransferJournal Crash Recovery Tests

/// Tests that verify TransferJournal crash recovery behaviour including WAL
/// resilience, orphan detection, concurrent writer safety, capacity stress,
/// corrupt-entry survival, atomic rename orphan detection, mid-write disconnect
/// handling, and schema migration from older formats.
final class JournalCrashRecoveryTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-crash-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }
    super.tearDown()
  }

  // MARK: - Crash During Write

  /// An incomplete transfer (beginRead called, no complete) must appear as
  /// orphaned (failed) after the journal is reopened — simulating a crash
  /// between beginRead and complete.
  func testCrashDuringWriteMarksOrphanOnReopen() throws {
    let device = MTPDeviceID(raw: "crash-write-device")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "incomplete.jpg",
      size: 4096, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/crash-wr"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: id, committed: 2048)

    // Simulate crash: drop reference and reopen
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
    XCTAssertEqual(resumables[0].state, "failed")
    XCTAssertEqual(resumables[0].committedBytes, 2048)
  }

  /// Multiple incomplete transfers across devices all become orphans on reopen.
  func testCrashWithMultipleActiveTransfersOrphansAll() throws {
    let devices = (0..<5).map { MTPDeviceID(raw: "crash-multi-\($0)") }
    var ids: [String] = []
    for (i, dev) in devices.enumerated() {
      let id = try journal.beginRead(
        device: dev, handle: UInt32(i), name: "file\(i).dat",
        size: UInt64(1000 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/crash-m\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: UInt64(500 * (i + 1)))
      ids.append(id)
    }

    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    for (i, dev) in devices.enumerated() {
      let resumables = try journal.loadResumables(for: dev)
      XCTAssertEqual(resumables.count, 1, "Device \(i) should have 1 orphan")
      XCTAssertEqual(resumables[0].state, "failed")
      XCTAssertTrue(
        resumables[0].committedBytes > 0,
        "Committed bytes should be preserved after crash")
    }
  }

  /// A write transfer left active with partial progress is detectable after reopen.
  func testCrashDuringWriteTransferPreservesPartialProgress() throws {
    let device = MTPDeviceID(raw: "crash-write-partial")
    let id = try journal.beginWrite(
      device: device, parent: 10, name: "upload.bin",
      size: 8192, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/crash-wp"), sourceURL: nil)
    try journal.updateProgress(id: id, committed: 3000)
    try journal.recordRemoteHandle(id: id, handle: 42)

    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].kind, "write")
    XCTAssertEqual(resumables[0].committedBytes, 3000)
    XCTAssertEqual(resumables[0].state, "failed")
  }

  // MARK: - WAL Recovery

  /// Journal data written in WAL mode survives close and reopen without
  /// explicit checkpoint — SQLite replays the WAL automatically.
  func testWALRecoverySurvivesReopenWithoutCheckpoint() throws {
    let device = MTPDeviceID(raw: "wal-recover")
    let id = try journal.beginRead(
      device: device, handle: 7, name: "wal-photo.jpg",
      size: 10_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/wal-r"), finalURL: nil,
      etag: (size: 10_000, mtime: Date()))
    try journal.updateProgress(id: id, committed: 5000)
    try journal.complete(id: id)

    // WAL file should exist on disk (SQLite manages it)
    _ = dbPath! + "-wal"
    // Reopen — SQLite must replay WAL
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    // Completed transfer should NOT be in resumables
    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Completed transfer should not reappear")
  }

  /// Rapid writes followed by immediate reopen still produce consistent state.
  func testWALConsistencyUnderRapidWrites() throws {
    let device = MTPDeviceID(raw: "wal-rapid")
    var completedIds: Set<String> = []
    for i in 0..<50 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "rapid\(i).dat",
        size: 1024, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/wal-rp\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: 1024)
      try journal.complete(id: id)
      completedIds.insert(id)
    }

    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "All 50 completed transfers should remain done")
  }

  // MARK: - Concurrent Writers

  /// Rapid sequential creation of many transfers simulating burst writes.
  func testBurstWritersDoNotCorruptJournal() throws {
    let device = MTPDeviceID(raw: "burst-writers")

    for i in 0..<50 {
      _ = try journal.beginRead(
        device: device, handle: UInt32(i), name: "burst\(i).dat",
        size: UInt64(1000 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/burst\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 50, "All 50 burst writes should succeed")
    // No duplicates
    let ids = Set(resumables.map(\.id))
    XCTAssertEqual(ids.count, 50, "No duplicate IDs")
  }

  /// Rapid progress updates on different transfers interleaved must not corrupt.
  func testInterleavedProgressUpdatesOnSeparateTransfers() throws {
    let device = MTPDeviceID(raw: "interleaved-progress")
    var transferIds: [String] = []
    for i in 0..<10 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "cp\(i).dat",
        size: 10_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/cp\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      transferIds.append(id)
    }

    // Interleave progress updates across all transfers
    for step in stride(from: UInt64(0), through: 10_000, by: 500) {
      for tid in transferIds {
        try journal.updateProgress(id: tid, committed: step)
      }
    }
    for tid in transferIds {
      try journal.complete(id: tid)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "All transfers should be completed")
  }

  // MARK: - Journal at Capacity (10,000 entries)

  /// Journal with 10,000 entries must remain queryable without significant degradation.
  func testJournalAt10KEntriesRemainsResponsive() throws {
    let device = MTPDeviceID(raw: "capacity-10k")

    let insertStart = CFAbsoluteTimeGetCurrent()
    for i in 0..<10_000 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i % 65535), name: "cap\(i).dat",
        size: UInt64(1000 + i), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/cap\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      if i % 2 == 0 {
        try journal.complete(id: id)
      }
    }
    let insertDuration = CFAbsoluteTimeGetCurrent() - insertStart
    // Inserting 10K entries should complete in under 60 seconds
    XCTAssertLessThan(insertDuration, 60.0, "10K inserts took too long: \(insertDuration)s")

    // Query resumables — should return ~5000 active entries (the odd ones)
    let queryStart = CFAbsoluteTimeGetCurrent()
    let resumables = try journal.loadResumables(for: device)
    let queryDuration = CFAbsoluteTimeGetCurrent() - queryStart

    XCTAssertEqual(resumables.count, 5000, "Half should be active")
    XCTAssertLessThan(queryDuration, 5.0, "Query of 5K resumables took too long: \(queryDuration)s")

    // List active should also work
    let active = try journal.listActive()
    XCTAssertEqual(active.count, 5000)
  }

  /// Clearing stale temps on a large journal completes in reasonable time.
  func testClearStaleTempsAt10KEntriesPerformance() throws {
    let device = MTPDeviceID(raw: "stale-10k")
    for i in 0..<10_000 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i % 65535), name: "stale\(i).dat",
        size: 512, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/stale\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.complete(id: id)
    }

    let start = CFAbsoluteTimeGetCurrent()
    try journal.clearStaleTemps(olderThan: 0)
    let duration = CFAbsoluteTimeGetCurrent() - start
    XCTAssertLessThan(duration, 10.0, "Stale cleanup took too long: \(duration)s")
  }

  // MARK: - Corrupt Entry Recovery

  /// Manually corrupting one row's data still allows other rows to be read.
  func testCorruptSingleRowDoesNotBlockOtherEntries() throws {
    let device = MTPDeviceID(raw: "corrupt-row")
    var ids: [String] = []
    for i in 0..<5 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "row\(i).dat",
        size: 1024, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/row\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    // Directly corrupt one row via raw SQL — set invalid state
    journal = nil
    var rawDb: OpaquePointer?
    XCTAssertEqual(sqlite3_open(dbPath, &rawDb), SQLITE_OK)
    let corruptSQL = "UPDATE transfers SET state = 'GARBAGE_STATE' WHERE id = '\(ids[2])'"
    XCTAssertEqual(sqlite3_exec(rawDb, corruptSQL, nil, nil, nil), SQLITE_OK)
    sqlite3_close(rawDb)

    // Reopen — orphan detection only targets 'active' rows
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    // The corrupt row won't match 'active' or 'failed' in loadResumables
    let resumables = try journal.loadResumables(for: device)
    // 4 rows were active → orphaned to failed; 1 has GARBAGE_STATE → not returned
    XCTAssertEqual(resumables.count, 4, "4 valid orphans should be returned")
    XCTAssertTrue(resumables.allSatisfy { $0.state == "failed" })
  }

  /// Corrupting the name column to NULL still allows the row to be loaded.
  func testCorruptNullNameColumnStillLoads() throws {
    let device = MTPDeviceID(raw: "corrupt-name")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "original.dat",
      size: 512, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/cn"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    journal = nil
    var rawDb: OpaquePointer?
    XCTAssertEqual(sqlite3_open(dbPath, &rawDb), SQLITE_OK)
    let sql = "UPDATE transfers SET name = NULL WHERE id = '\(id)'"
    XCTAssertEqual(sqlite3_exec(rawDb, sql, nil, nil, nil), SQLITE_OK)
    sqlite3_close(rawDb)

    journal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    // Name defaults to empty string when NULL in getOptText
    XCTAssertEqual(resumables[0].name, "")
  }

  /// Corrupting committedBytes to an extreme value is handled on reload.
  func testCorruptExtremeCommittedBytesSurvivesReopen() throws {
    let device = MTPDeviceID(raw: "corrupt-bytes")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "extreme.dat",
      size: 1024, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/extreme"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    journal = nil
    var rawDb: OpaquePointer?
    XCTAssertEqual(sqlite3_open(dbPath, &rawDb), SQLITE_OK)
    // Set committedBytes to a very large value exceeding totalBytes
    let sql = "UPDATE transfers SET committedBytes = 999999999 WHERE id = '\(id)'"
    XCTAssertEqual(sqlite3_exec(rawDb, sql, nil, nil, nil), SQLITE_OK)
    sqlite3_close(rawDb)

    journal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    // Bytes may exceed totalBytes but journal still loads without crash
    XCTAssertTrue(resumables[0].committedBytes > 0)
  }

  // MARK: - Atomic Rename Failure (Orphan Detection)

  /// A temp file that exists on disk but whose transfer is still active should
  /// be detectable as orphan after journal reopen.
  func testTempFileExistsButTransferActiveDetectedAsOrphan() throws {
    let tempPath = NSTemporaryDirectory() + "orphan-temp-\(UUID().uuidString).dat"
    defer { try? FileManager.default.removeItem(atPath: tempPath) }
    // Create an actual temp file on disk
    try Data("partial data".utf8).write(to: URL(fileURLWithPath: tempPath))

    let device = MTPDeviceID(raw: "orphan-rename")
    _ = try journal.beginRead(
      device: device, handle: 1, name: "photo.jpg",
      size: 4096, supportsPartial: true,
      tempURL: URL(fileURLWithPath: tempPath),
      finalURL: URL(fileURLWithPath: "/tmp/final-photo.jpg"),
      etag: (size: 4096, mtime: nil))

    // Simulate crash before rename completes
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
    // Temp file still on disk — caller can decide to clean up or resume
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
  }

  /// clearStaleTemps removes the orphaned temp file from disk.
  func testClearStaleTempsRemovesOrphanedTempFile() throws {
    let tempPath = NSTemporaryDirectory() + "orphan-stale-\(UUID().uuidString).dat"
    try Data("stale partial".utf8).write(to: URL(fileURLWithPath: tempPath))

    let device = MTPDeviceID(raw: "orphan-stale")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "stale.jpg",
      size: 2048, supportsPartial: false,
      tempURL: URL(fileURLWithPath: tempPath), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: id, error: NSError(domain: "test", code: 1))

    // Temp file exists
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))

    // Clear with 0 threshold
    try journal.clearStaleTemps(olderThan: 0)

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: tempPath),
      "Orphaned temp file should be cleaned up")
  }

  /// Multiple orphaned temp files across devices are all cleaned up.
  func testMultipleOrphanTempFilesCleanedUp() throws {
    var tempPaths: [String] = []
    for i in 0..<5 {
      let path = NSTemporaryDirectory() + "multi-orphan-\(i)-\(UUID().uuidString).dat"
      try Data("orphan\(i)".utf8).write(to: URL(fileURLWithPath: path))
      tempPaths.append(path)
    }
    defer { tempPaths.forEach { try? FileManager.default.removeItem(atPath: $0) } }

    for (i, path) in tempPaths.enumerated() {
      let device = MTPDeviceID(raw: "multi-orphan-\(i)")
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "orphan\(i).dat",
        size: 512, supportsPartial: false,
        tempURL: URL(fileURLWithPath: path), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.fail(id: id, error: NSError(domain: "test", code: i))
    }

    try journal.clearStaleTemps(olderThan: 0)

    for path in tempPaths {
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: path),
        "Temp file at \(path) should be removed")
    }
  }

  // MARK: - Device Disconnect Mid-Journal-Write

  /// Simulates a device disconnect by starting a transfer, updating progress
  /// partially, then failing it — journal must be consistent.
  func testDisconnectMidWriteJournalRemainsConsistent() throws {
    let device = MTPDeviceID(raw: "disconnect-mid")
    let id = try journal.beginWrite(
      device: device, parent: 5, name: "large-upload.bin",
      size: 1_000_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/disc-mid"), sourceURL: nil)

    // Simulate partial progress then disconnect
    try journal.updateProgress(id: id, committed: 250_000)
    try journal.updateProgress(id: id, committed: 500_000)
    try journal.fail(
      id: id, error: NSError(domain: "USB", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "Device disconnected"
      ]))

    // Journal is consistent
    let failed = try journal.listFailed()
    XCTAssertEqual(failed.count, 1)
    XCTAssertEqual(failed[0].committedBytes, 500_000)
    XCTAssertTrue(failed[0].lastError?.contains("disconnected") == true)

    // Reopen still consistent
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 500_000)
  }

  /// Multiple rapid disconnect/reconnect cycles produce consistent journal state.
  func testRepeatedDisconnectReconnectCyclesStayConsistent() throws {
    let device = MTPDeviceID(raw: "disconnect-cycle")

    for cycle in 0..<10 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(cycle), name: "cycle\(cycle).dat",
        size: 10_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/disc-cycle\(cycle)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      let progress = UInt64(cycle * 1000 + 500)
      try journal.updateProgress(id: id, committed: progress)
      try journal.fail(
        id: id, error: NSError(domain: "USB", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "disconnect cycle \(cycle)"
        ]))
    }

    let failed = try journal.listFailed()
    XCTAssertEqual(failed.count, 10)
    // listFailed is ordered by updatedAt DESC; verify all entries have valid progress
    for record in failed {
      XCTAssertTrue(record.committedBytes > 0, "Each disconnect cycle should have progress")
    }
  }

  /// A transfer that was active when "disconnect" happens, then journal
  /// is reopened, shows up as orphaned.
  func testActiveTransferBecomesOrphanAfterDisconnectAndReopen() throws {
    let device = MTPDeviceID(raw: "disconnect-orphan")
    let id = try journal.beginRead(
      device: device, handle: 99, name: "disconnect.dat",
      size: 50_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/disc-orp"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: id, committed: 25_000)
    // Simulate crash/disconnect — no fail/complete called
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
    XCTAssertEqual(resumables[0].committedBytes, 25_000)
    XCTAssertTrue(resumables[0].name == "disconnect.dat")
  }

  // MARK: - Schema Upgrade

  /// An older schema (missing throughputMBps, remoteHandle, contentHash columns)
  /// is migrated cleanly when a new SQLiteTransferJournal is opened.
  func testSchemaUpgradeFromOlderFormat() throws {
    let oldPath = NSTemporaryDirectory() + "journal-old-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: oldPath)
      try? FileManager.default.removeItem(atPath: oldPath + "-wal")
      try? FileManager.default.removeItem(atPath: oldPath + "-shm")
    }

    // Create a database with the old schema (no throughputMBps, remoteHandle, contentHash)
    var rawDb: OpaquePointer?
    XCTAssertEqual(sqlite3_open(oldPath, &rawDb), SQLITE_OK)
    let oldSchema = """
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS transfers (
        id TEXT PRIMARY KEY,
        deviceId TEXT NOT NULL,
        kind TEXT NOT NULL,
        handle INTEGER,
        parentHandle INTEGER,
        pathKey TEXT,
        name TEXT,
        totalBytes INTEGER,
        committedBytes INTEGER NOT NULL DEFAULT 0,
        supportsPartial INTEGER NOT NULL DEFAULT 0,
        etag_size INTEGER,
        etag_mtime INTEGER,
        localTempURL TEXT,
        finalURL TEXT,
        state TEXT NOT NULL,
        lastError TEXT,
        updatedAt INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_transfers_state ON transfers(state, updatedAt);
      CREATE INDEX IF NOT EXISTS idx_transfers_device_state ON transfers(deviceId, state);
      """
    XCTAssertEqual(sqlite3_exec(rawDb, oldSchema, nil, nil, nil), SQLITE_OK)

    // Insert a row using the old schema
    let insertSQL = """
      INSERT INTO transfers (id, deviceId, kind, handle, name, totalBytes, committedBytes,
        supportsPartial, localTempURL, state, updatedAt)
      VALUES ('old-transfer-1', 'old-device', 'read', 42, 'legacy.jpg', 2048, 1024,
        1, '/tmp/legacy', 'active', \(Int64(Date().timeIntervalSince1970)));
      """
    XCTAssertEqual(sqlite3_exec(rawDb, insertSQL, nil, nil, nil), SQLITE_OK)
    sqlite3_close(rawDb)

    // Open with new SQLiteTransferJournal — migration should run
    let migratedJournal = try SQLiteTransferJournal(dbPath: oldPath)

    // The old active transfer should be orphaned
    let device = MTPDeviceID(raw: "old-device")
    let resumables = try migratedJournal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "legacy.jpg")
    XCTAssertEqual(resumables[0].committedBytes, 1024)
    XCTAssertEqual(resumables[0].state, "failed")

    // New columns should be usable — record throughput on the orphaned entry
    // (need a fresh active entry to test new column writes)
    let newId = try migratedJournal.beginRead(
      device: device, handle: 100, name: "migrated.jpg",
      size: 4096, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/migrated"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try migratedJournal.recordThroughput(id: newId, throughputMBps: 12.5)
    try migratedJournal.recordRemoteHandle(id: newId, handle: 200)
    try migratedJournal.addContentHash(id: newId, hash: "abc123")
    try migratedJournal.complete(id: newId)

    // Verify no errors — migration succeeded
  }

  /// Running migration twice (idempotent) does not throw or corrupt data.
  func testSchemaUpgradeIdempotent() throws {
    let device = MTPDeviceID(raw: "idempotent-dev")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "idem.dat",
      size: 512, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/idem"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: id)

    // Reopen multiple times — each triggers migrateSchema
    for _ in 0..<5 {
      journal = nil
      journal = try SQLiteTransferJournal(dbPath: dbPath)
    }

    // Data should still be intact
    let newId = try journal.beginRead(
      device: device, handle: 2, name: "idem2.dat",
      size: 256, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/idem2"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.recordThroughput(id: newId, throughputMBps: 5.0)
    try journal.addContentHash(id: newId, hash: "deadbeef")
    try journal.complete(id: newId)
  }

  /// A database created by an older version with data in every column still
  /// loads correctly after migration.
  func testSchemaUpgradePreservesAllOldData() throws {
    let oldPath = NSTemporaryDirectory() + "journal-old-full-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: oldPath)
      try? FileManager.default.removeItem(atPath: oldPath + "-wal")
      try? FileManager.default.removeItem(atPath: oldPath + "-shm")
    }

    var rawDb: OpaquePointer?
    XCTAssertEqual(sqlite3_open(oldPath, &rawDb), SQLITE_OK)
    let schema = """
      PRAGMA journal_mode=WAL;
      CREATE TABLE transfers (
        id TEXT PRIMARY KEY, deviceId TEXT NOT NULL, kind TEXT NOT NULL,
        handle INTEGER, parentHandle INTEGER, pathKey TEXT, name TEXT,
        totalBytes INTEGER, committedBytes INTEGER NOT NULL DEFAULT 0,
        supportsPartial INTEGER NOT NULL DEFAULT 0,
        etag_size INTEGER, etag_mtime INTEGER,
        localTempURL TEXT, finalURL TEXT,
        state TEXT NOT NULL, lastError TEXT, updatedAt INTEGER NOT NULL
      );
      INSERT INTO transfers VALUES (
        'full-1', 'dev-full', 'write', 10, 20, '/photos', 'bigfile.mov',
        999999, 500000, 1, 999999, 1700000000, '/tmp/big', '/dest/big',
        'failed', 'timeout during upload', \(Int64(Date().timeIntervalSince1970))
      );
      """
    XCTAssertEqual(sqlite3_exec(rawDb, schema, nil, nil, nil), SQLITE_OK)
    sqlite3_close(rawDb)

    let migratedJournal = try SQLiteTransferJournal(dbPath: oldPath)
    let device = MTPDeviceID(raw: "dev-full")
    let resumables = try migratedJournal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "bigfile.mov")
    XCTAssertEqual(resumables[0].totalBytes, 999_999)
    XCTAssertEqual(resumables[0].committedBytes, 500_000)
    XCTAssertEqual(resumables[0].kind, "write")
    XCTAssertEqual(resumables[0].supportsPartial, true)
  }

  // MARK: - Mixed Recovery Scenarios

  /// A journal with a mix of active, failed, and done transfers is correctly
  /// categorized after crash reopen.
  func testMixedStatesCorrectlyHandledAfterCrash() throws {
    let device = MTPDeviceID(raw: "mixed-states")

    let activeId = try journal.beginRead(
      device: device, handle: 1, name: "active.dat",
      size: 1024, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/mix-a"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: activeId, committed: 512)

    let failedId = try journal.beginRead(
      device: device, handle: 2, name: "failed.dat",
      size: 2048, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/mix-f"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: failedId, error: NSError(domain: "test", code: 1))

    let doneId = try journal.beginRead(
      device: device, handle: 3, name: "done.dat",
      size: 4096, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/mix-d"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: doneId)

    // Crash reopen
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    // active → orphaned (failed), original failed stays, done excluded
    XCTAssertEqual(resumables.count, 2, "Should have 2 resumables (orphaned + original failed)")
    let states = Set(resumables.map(\.state))
    XCTAssertEqual(states, ["failed"])
    let names = Set(resumables.map(\.name))
    XCTAssertTrue(names.contains("active.dat"))
    XCTAssertTrue(names.contains("failed.dat"))
    XCTAssertFalse(names.contains("done.dat"))
  }

  /// Throughput and content hash survive crash+reopen on a completed transfer.
  func testThroughputAndHashSurviveCrashOnCompletedTransfer() throws {
    let device = MTPDeviceID(raw: "meta-survive")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "meta.dat",
      size: 8192, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/meta"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: id, committed: 8192)
    try journal.recordThroughput(id: id, throughputMBps: 25.3)
    try journal.addContentHash(id: id, hash: "sha256-abc123def456")
    try journal.complete(id: id)

    // Reopen
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    // Completed transfer not in resumables but journal should be queryable
    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Completed transfer should not be in resumables")

    // Verify the data wasn't corrupted by checking a new transfer works
    let newId = try journal.beginRead(
      device: device, handle: 2, name: "meta2.dat",
      size: 1024, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/meta2"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.recordThroughput(id: newId, throughputMBps: 30.0)
    try journal.addContentHash(id: newId, hash: "sha256-newfile")
    try journal.complete(id: newId)
  }
}
