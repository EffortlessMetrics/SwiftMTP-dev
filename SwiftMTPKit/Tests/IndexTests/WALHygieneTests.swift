// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SQLite3
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempPath(_ label: String = "wal") -> String {
  let dir = FileManager.default.temporaryDirectory
  return dir.appendingPathComponent("\(label)-\(UUID().uuidString).sqlite").path
}

private func cleanup(_ path: String) {
  for suffix in ["", "-wal", "-shm"] {
    try? FileManager.default.removeItem(atPath: path + suffix)
  }
}

private func makeObj(
  handle: UInt32,
  name: String = "file.txt",
  storageId: UInt32 = 0x10001,
  parentHandle: UInt32? = nil
) -> IndexedObject {
  IndexedObject(
    deviceId: "dev",
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: 1024,
    mtime: Date(timeIntervalSince1970: 1_700_000_000),
    formatCode: 0x3001,
    isDirectory: false,
    changeCounter: 0
  )
}

private func queryPragma(_ db: SQLiteDB, _ pragma: String) throws -> String? {
  try db.withStatement("PRAGMA \(pragma);") { stmt in
    guard try db.step(stmt) else { return nil }
    return db.colText(stmt, 0)
  }
}

private func queryPragmaInt(_ db: SQLiteDB, _ pragma: String) throws -> Int64? {
  try db.withStatement("PRAGMA \(pragma);") { stmt in
    guard try db.step(stmt) else { return nil }
    return db.colInt64(stmt, 0)
  }
}

// MARK: - WAL Journal Mode

@Suite("WAL Hygiene — Journal Mode")
struct WALJournalModeTests {

  @Test("journal_mode is WAL after opening")
  func journalModeIsWAL() throws {
    let path = makeTempPath("jm")
    defer { cleanup(path) }
    let db = try SQLiteDB(path: path)
    let mode = try queryPragma(db, "journal_mode")
    #expect(mode == "wal")
  }

  @Test("synchronous mode is NORMAL")
  func synchronousModeIsNormal() throws {
    let path = makeTempPath("sync")
    defer { cleanup(path) }
    let db = try SQLiteDB(path: path)
    // PRAGMA synchronous returns integer: 0=OFF, 1=NORMAL, 2=FULL, 3=EXTRA
    let value = try queryPragmaInt(db, "synchronous")
    #expect(value == 1, "Expected synchronous=NORMAL (1), got \(String(describing: value))")
  }

  @Test("journal_mode persists after close and reopen")
  func journalModePersistsAfterReopen() throws {
    let path = makeTempPath("jm-persist")
    defer { cleanup(path) }
    // First open sets WAL
    _ = try SQLiteDB(path: path)
    // Reopen — WAL should persist
    let db2 = try SQLiteDB(path: path)
    let mode = try queryPragma(db2, "journal_mode")
    #expect(mode == "wal")
  }
}

// MARK: - WAL Checkpoint

@Suite("WAL Hygiene — Checkpoint")
struct WALCheckpointTests {

  @Test("WAL checkpoint succeeds after many writes")
  func checkpointAfterManyWrites() async throws {
    let path = makeTempPath("ckpt")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)

    // Perform many individual writes to grow the WAL
    for i: UInt32 in 0..<200 {
      let obj = makeObj(handle: i, name: "file\(i).txt")
      try await idx.upsertObjects([obj], deviceId: "dev")
    }

    // WAL file should exist and have data
    let walPath = path + "-wal"
    let walExists = FileManager.default.fileExists(atPath: walPath)
    #expect(walExists, "WAL file should exist after writes")

    // Checkpoint should succeed
    let db = idx.database
    try db.exec("PRAGMA wal_checkpoint(TRUNCATE);")

    // After TRUNCATE checkpoint, WAL file size should be 0 or very small
    let walAttrs = try? FileManager.default.attributesOfItem(atPath: walPath)
    let walSize = walAttrs?[.size] as? UInt64 ?? 0
    #expect(walSize == 0, "WAL should be truncated after TRUNCATE checkpoint, size=\(walSize)")
  }

  @Test("WAL file size doesn't grow unbounded with periodic checkpoints")
  func walSizeBoundedWithCheckpoints() async throws {
    let path = makeTempPath("walsize")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)
    let walPath = path + "-wal"
    let db = idx.database

    // Write 100 objects, checkpoint, record WAL size
    for i: UInt32 in 0..<100 {
      try await idx.upsertObjects([makeObj(handle: i, name: "a\(i).txt")], deviceId: "dev")
    }
    try db.exec("PRAGMA wal_checkpoint(TRUNCATE);")
    let sizeAfterFirst = (try? FileManager.default.attributesOfItem(atPath: walPath))?[.size]
      as? UInt64 ?? 0

    // Write 100 more, checkpoint again
    for i: UInt32 in 100..<200 {
      try await idx.upsertObjects([makeObj(handle: i, name: "b\(i).txt")], deviceId: "dev")
    }
    try db.exec("PRAGMA wal_checkpoint(TRUNCATE);")
    let sizeAfterSecond = (try? FileManager.default.attributesOfItem(atPath: walPath))?[.size]
      as? UInt64 ?? 0

    // Both should be truncated (0 bytes)
    #expect(sizeAfterFirst == 0, "WAL should be 0 after first checkpoint")
    #expect(sizeAfterSecond == 0, "WAL should be 0 after second checkpoint")
  }
}

// MARK: - Concurrent Readers/Writers

@Suite("WAL Hygiene — Concurrency")
struct WALConcurrencyTests {

  @Test("Concurrent read during write sees consistent state")
  func concurrentReadDuringWrite() async throws {
    let path = makeTempPath("crw")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)

    // Seed with initial data
    let initial = (0..<10).map { makeObj(handle: UInt32($0), name: "init\($0).txt") }
    try await idx.upsertObjects(initial, deviceId: "dev")

    // Open a second read-only connection
    let reader = try SQLiteLiveIndex(path: path, readOnly: true)

    // Read snapshot before concurrent writes
    let before = try await reader.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(before.count == 10)

    // Write more objects on the writer
    let extra = (10..<20).map { makeObj(handle: UInt32($0), name: "extra\($0).txt") }
    try await idx.upsertObjects(extra, deviceId: "dev")

    // Reader should eventually see the new data (WAL allows this once the read transaction ends)
    let after = try await reader.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(after.count == 20)
  }

  @Test("Multiple simultaneous readers don't block each other")
  func multipleReadersNoBlocking() async throws {
    let path = makeTempPath("mreader")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)

    // Seed data
    let objs = (0..<50).map { makeObj(handle: UInt32($0), name: "r\($0).txt") }
    try await idx.upsertObjects(objs, deviceId: "dev")

    // Open multiple readers
    let reader1 = try SQLiteLiveIndex(path: path, readOnly: true)
    let reader2 = try SQLiteLiveIndex(path: path, readOnly: true)
    let reader3 = try SQLiteLiveIndex(path: path, readOnly: true)

    // All readers query concurrently
    async let r1 = reader1.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    async let r2 = reader2.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    async let r3 = reader3.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)

    let (c1, c2, c3) = try await (r1, r2, r3)
    #expect(c1.count == 50)
    #expect(c2.count == 50)
    #expect(c3.count == 50)
  }

  @Test("Write during read doesn't corrupt reader's view")
  func writeDuringReadNoCorruption() async throws {
    let path = makeTempPath("wdr")
    defer { cleanup(path) }
    let writer = try SQLiteLiveIndex(path: path)

    // Seed
    let seed = (0..<20).map { makeObj(handle: UInt32($0), name: "s\($0).txt") }
    try await writer.upsertObjects(seed, deviceId: "dev")

    let reader = try SQLiteLiveIndex(path: path, readOnly: true)

    // Perform interleaved read and write operations
    async let readResult = reader.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    async let writeResult: Void = writer.upsertObjects(
      (20..<40).map { makeObj(handle: UInt32($0), name: "w\($0).txt") },
      deviceId: "dev")

    let (items, _) = try await (readResult, writeResult)

    // Reader should see either the pre-write or post-write state, never partial
    #expect(items.count == 20 || items.count == 40,
      "Reader saw \(items.count) objects — expected 20 or 40 (never partial)")
  }
}

// MARK: - Database Recovery

@Suite("WAL Hygiene — Recovery")
struct WALRecoveryTests {

  @Test("Database recovers after close and reopen cycle")
  func closeReopenCycle() async throws {
    let path = makeTempPath("reopen")
    defer { cleanup(path) }

    // Write data, then let the index go out of scope
    do {
      let idx = try SQLiteLiveIndex(path: path)
      let objs = (0..<25).map { makeObj(handle: UInt32($0), name: "c\($0).txt") }
      try await idx.upsertObjects(objs, deviceId: "dev")
    }

    // Reopen and verify all data is intact
    let idx2 = try SQLiteLiveIndex(path: path)
    let objects = try await idx2.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(objects.count == 25)
  }

  @Test("Database file integrity after rapid open-close cycles")
  func rapidOpenCloseCycles() async throws {
    let path = makeTempPath("rapid")
    defer { cleanup(path) }

    // Perform many open/write/close cycles
    for cycle in 0..<10 {
      let idx = try SQLiteLiveIndex(path: path)
      let base = UInt32(cycle * 5)
      let objs = (base..<(base + 5)).map {
        makeObj(handle: $0, name: "cyc\(cycle)_\($0).txt")
      }
      try await idx.upsertObjects(objs, deviceId: "dev")
    }

    // Final open should see all 50 objects
    let idx = try SQLiteLiveIndex(path: path)
    let all = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(all.count == 50)

    // Integrity check should pass
    let ok = try queryPragma(idx.database, "integrity_check")
    #expect(ok == "ok", "integrity_check failed: \(ok ?? "nil")")
  }

  @Test("WAL recovery with orphaned WAL file")
  func orphanedWALRecovery() async throws {
    let path = makeTempPath("orphan")
    let walPath = path + "-wal"
    defer { cleanup(path) }

    // Create db and write some data
    do {
      let idx = try SQLiteLiveIndex(path: path)
      let objs = (0..<10).map { makeObj(handle: UInt32($0), name: "o\($0).txt") }
      try await idx.upsertObjects(objs, deviceId: "dev")
    }

    // Verify WAL or SHM files may exist; simulate "crash" by just reopening
    // SQLite automatically replays the WAL on open
    let walExisted = FileManager.default.fileExists(atPath: walPath)
    // Whether WAL exists depends on auto-checkpoint; either way, reopen should work

    let idx2 = try SQLiteLiveIndex(path: path)
    let objects = try await idx2.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(objects.count == 10,
      "Expected 10 objects after WAL recovery, walExisted=\(walExisted)")
  }
}

// MARK: - FTS5 Consistency with WAL

@Suite("WAL Hygiene — FTS5 Consistency")
struct WALFTS5Tests {

  @Test("FTS5 index stays consistent across WAL writes")
  func fts5ConsistentWithWALWrites() async throws {
    let path = makeTempPath("fts5")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)

    // Insert objects with searchable names
    let objs = [
      makeObj(handle: 1, name: "vacation_photo.jpg"),
      makeObj(handle: 2, name: "vacation_video.mp4"),
      makeObj(handle: 3, name: "work_document.pdf"),
      makeObj(handle: 4, name: "vacation_notes.txt"),
    ]
    try await idx.upsertObjects(objs, deviceId: "dev")

    // FTS5 search should find the vacation files
    let results = try await idx.searchByFilename(deviceId: "dev", query: "vacation")
    #expect(results.count == 3, "Expected 3 vacation files, got \(results.count)")

    // Upsert more objects and verify FTS stays in sync
    let more = [
      makeObj(handle: 5, name: "vacation_sunset.png"),
      makeObj(handle: 6, name: "birthday_cake.jpg"),
    ]
    try await idx.upsertObjects(more, deviceId: "dev")

    let results2 = try await idx.searchByFilename(deviceId: "dev", query: "vacation")
    #expect(results2.count == 4, "Expected 4 vacation files after upsert, got \(results2.count)")
  }

  @Test("FTS5 consistent after checkpoint")
  func fts5ConsistentAfterCheckpoint() async throws {
    let path = makeTempPath("fts5ckpt")
    defer { cleanup(path) }
    let idx = try SQLiteLiveIndex(path: path)

    let objs = [
      makeObj(handle: 1, name: "report_q1.xlsx"),
      makeObj(handle: 2, name: "report_q2.xlsx"),
      makeObj(handle: 3, name: "summary.docx"),
    ]
    try await idx.upsertObjects(objs, deviceId: "dev")

    // Checkpoint
    try idx.database.exec("PRAGMA wal_checkpoint(TRUNCATE);")

    // FTS should still work after checkpoint
    let results = try await idx.searchByFilename(deviceId: "dev", query: "report")
    #expect(results.count == 2)

    // Add more data after checkpoint
    try await idx.upsertObjects(
      [makeObj(handle: 4, name: "report_q3.xlsx")], deviceId: "dev")

    let results2 = try await idx.searchByFilename(deviceId: "dev", query: "report")
    #expect(results2.count == 3)
  }

  @Test("FTS5 readable from separate WAL reader connection")
  func fts5ReadableFromReaderConnection() async throws {
    let path = makeTempPath("fts5reader")
    defer { cleanup(path) }
    let writer = try SQLiteLiveIndex(path: path)

    let objs = [
      makeObj(handle: 1, name: "photo_beach.jpg"),
      makeObj(handle: 2, name: "photo_mountain.jpg"),
    ]
    try await writer.upsertObjects(objs, deviceId: "dev")

    // Open read-only connection
    let reader = try SQLiteLiveIndex(path: path, readOnly: true)
    let results = try await reader.searchByFilename(deviceId: "dev", query: "photo")
    #expect(results.count == 2)
  }
}
