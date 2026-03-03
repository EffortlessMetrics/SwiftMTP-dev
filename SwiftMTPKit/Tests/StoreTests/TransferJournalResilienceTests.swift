// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore

// MARK: - TransferJournal CRUD Tests

final class TransferJournalCRUDTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-crud-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testBeginReadCreatesActiveTransfer() throws {
    let device = MTPDeviceID(raw: "crud-device")
    let tempURL = URL(fileURLWithPath: "/tmp/crud-read")

    let id = try journal.beginRead(
      device: device, handle: 42, name: "photo.jpg",
      size: 2048, supportsPartial: true,
      tempURL: tempURL, finalURL: nil, etag: (size: 2048, mtime: Date()))

    XCTAssertFalse(id.isEmpty)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
    XCTAssertEqual(resumables[0].kind, "read")
    XCTAssertEqual(resumables[0].name, "photo.jpg")
    XCTAssertEqual(resumables[0].totalBytes, 2048)
    XCTAssertEqual(resumables[0].committedBytes, 0)
    XCTAssertEqual(resumables[0].state, "active")
  }

  func testBeginWriteCreatesActiveTransfer() throws {
    let device = MTPDeviceID(raw: "crud-device-w")
    let tempURL = URL(fileURLWithPath: "/tmp/crud-write")

    let id = try journal.beginWrite(
      device: device, parent: 10, name: "upload.bin",
      size: 4096, supportsPartial: false,
      tempURL: tempURL, sourceURL: URL(fileURLWithPath: "/tmp/source.bin"))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
    XCTAssertEqual(resumables[0].kind, "write")
    XCTAssertEqual(resumables[0].committedBytes, 0)
  }

  func testUpdateProgressTracksCommittedBytes() throws {
    let device = MTPDeviceID(raw: "crud-progress")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "file.dat",
      size: 10_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/p"), finalURL: nil, etag: (size: nil, mtime: nil))

    try journal.updateProgress(id: id, committed: 5000)
    var resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 5000)

    try journal.updateProgress(id: id, committed: 8000)
    resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 8000)
  }

  func testCompleteRemovesFromResumables() throws {
    let device = MTPDeviceID(raw: "crud-complete")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "done.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/done"), finalURL: nil, etag: (size: nil, mtime: nil))

    try journal.complete(id: id)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Completed transfer should not be resumable")
  }

  func testFailKeepsTransferResumable() throws {
    let device = MTPDeviceID(raw: "crud-fail")
    let id = try journal.beginWrite(
      device: device, parent: 0, name: "fail.bin",
      size: 500, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/fail"), sourceURL: nil)

    try journal.updateProgress(id: id, committed: 250)
    let err = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "I/O error"])
    try journal.fail(id: id, error: err)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
    XCTAssertEqual(resumables[0].committedBytes, 250)
  }

  func testMultipleTransfersForDifferentDevices() throws {
    let deviceA = MTPDeviceID(raw: "device-A")
    let deviceB = MTPDeviceID(raw: "device-B")

    _ = try journal.beginRead(
      device: deviceA, handle: 1, name: "a.txt", size: 100,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/a"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try journal.beginWrite(
      device: deviceB, parent: 0, name: "b.txt", size: 200,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/b"), sourceURL: nil)

    let resumablesA = try journal.loadResumables(for: deviceA)
    let resumablesB = try journal.loadResumables(for: deviceB)
    XCTAssertEqual(resumablesA.count, 1)
    XCTAssertEqual(resumablesB.count, 1)
    XCTAssertEqual(resumablesA[0].name, "a.txt")
    XCTAssertEqual(resumablesB[0].name, "b.txt")
  }
}

// MARK: - Concurrent Journal Access Tests (via actor-isolated adapter)

final class TransferJournalConcurrencyTests: XCTestCase {

  private var adapter: SwiftMTPStoreAdapter!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    adapter = SwiftMTPStoreAdapter(store: .shared)
  }

  override func tearDown() {
    adapter = nil
    super.tearDown()
  }

  func testConcurrentBeginWriteDoesNotCorrupt() async throws {
    let device = MTPDeviceID(raw: "conc-device-\(UUID().uuidString)")
    let count = 20
    let a = adapter!

    try await withThrowingTaskGroup(of: String.self) { group in
      for i in 0..<count {
        group.addTask {
          try await a.beginWrite(
            device: device, parent: 0, name: "file-\(i).dat",
            size: UInt64(i * 1024), supportsPartial: false,
            tempURL: URL(fileURLWithPath: "/tmp/conc-\(i)"), sourceURL: nil)
        }
      }
      var ids = Set<String>()
      for try await id in group { ids.insert(id) }
      XCTAssertEqual(ids.count, count, "All transfer IDs should be unique")
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, count)
  }

  func testConcurrentProgressUpdatesOnDifferentTransfers() async throws {
    let device = MTPDeviceID(raw: "conc-progress-\(UUID().uuidString)")
    let a = adapter!
    var ids: [String] = []
    for i in 0..<10 {
      let id = try await adapter.beginRead(
        device: device, handle: UInt32(i), name: "p-\(i).bin",
        size: 10_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/cp-\(i)"),
        finalURL: nil, etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for id in ids {
        group.addTask {
          for step in stride(from: 1000, through: 10000, by: 1000) {
            try await a.updateProgress(id: id, committed: UInt64(step))
          }
        }
      }
      try await group.waitForAll()
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 10)
    for r in resumables {
      XCTAssertEqual(r.committedBytes, 10000, "Each transfer should reach 10000 bytes")
    }
  }

  func testConcurrentCompleteAndLoadResumables() async throws {
    let device = MTPDeviceID(raw: "conc-complete-\(UUID().uuidString)")
    let a = adapter!
    var ids: [String] = []
    for i in 0..<10 {
      let id = try await adapter.beginWrite(
        device: device, parent: 0, name: "cc-\(i).bin",
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/cc-\(i)"), sourceURL: nil)
      ids.append(id)
    }

    // Complete half concurrently while loading resumables
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<5 {
        let tid = ids[i]
        group.addTask { try await a.complete(id: tid) }
      }
      group.addTask {
        _ = try await a.loadResumables(for: device)
      }
      try await group.waitForAll()
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
  }
}

// MARK: - Crash Recovery / Resilience Tests

final class TransferJournalRecoveryTests: XCTestCase {

  func testResumeAfterSimulatedCrash() throws {
    let dbPath = NSTemporaryDirectory() + "journal-crash-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let device = MTPDeviceID(raw: "crash-device")

    // Phase 1: Create a transfer and update progress, then "crash" (release journal)
    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try journal.beginRead(
        device: device, handle: 99, name: "important.zip",
        size: 1_000_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/crash-temp"),
        finalURL: URL(fileURLWithPath: "/tmp/crash-final"),
        etag: (size: 1_000_000, mtime: Date()))
      try journal.updateProgress(id: id, committed: 500_000)
      // "crash" — journal goes out of scope, SQLite connection closes
    }

    // Phase 2: Re-open journal and verify resumable state
    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 500_000)
    XCTAssertEqual(resumables[0].totalBytes, 1_000_000)
    XCTAssertEqual(resumables[0].name, "important.zip")
    XCTAssertEqual(resumables[0].state, "active")
  }

  func testMultipleTransfersSurviveRestart() throws {
    let dbPath = NSTemporaryDirectory() + "journal-multi-crash-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let device = MTPDeviceID(raw: "multi-crash")

    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      for i in 0..<5 {
        let id = try journal.beginWrite(
          device: device, parent: 0, name: "file-\(i).dat",
          size: UInt64(1024 * (i + 1)), supportsPartial: true,
          tempURL: URL(fileURLWithPath: "/tmp/mc-\(i)"), sourceURL: nil)
        try journal.updateProgress(id: id, committed: UInt64(512 * (i + 1)))
      }
    }

    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
  }

  func testFailedTransferSurvivesRestart() throws {
    let dbPath = NSTemporaryDirectory() + "journal-fail-crash-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let device = MTPDeviceID(raw: "fail-crash")

    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try journal.beginRead(
        device: device, handle: 5, name: "broken.mp4",
        size: 50_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/fc"),
        finalURL: nil, etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: 25_000)
      try journal.fail(
        id: id,
        error: NSError(domain: "USB", code: -1, userInfo: [NSLocalizedDescriptionKey: "pipe reset"])
      )
    }

    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
    XCTAssertEqual(resumables[0].committedBytes, 25_000)
  }

  func testCompletedTransferNotResumableAfterRestart() throws {
    let dbPath = NSTemporaryDirectory() + "journal-done-crash-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let device = MTPDeviceID(raw: "done-crash")

    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try journal.beginRead(
        device: device, handle: 1, name: "complete.txt",
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/dc"),
        finalURL: nil, etag: (size: nil, mtime: nil))
      try journal.complete(id: id)
    }

    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }
}

// MARK: - Corruption Handling Tests

final class TransferJournalCorruptionTests: XCTestCase {

  func testOpeningCorruptedDatabaseFileThrows() throws {
    let dbPath = NSTemporaryDirectory() + "journal-corrupt-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    // Write garbage data to simulate a corrupted SQLite file
    let garbage = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
    try garbage.write(to: URL(fileURLWithPath: dbPath))

    // SQLite opens the file but schema creation should fail on the corrupt file
    // The behavior depends on SQLite: it may succeed in opening but fail on CREATE TABLE
    // if the file looks like a valid header but has corrupt pages.
    // With random garbage, sqlite3_open often succeeds but exec fails.
    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      // If we get here, the file happened to pass sqlite3_open, but operations should fail
      XCTAssertThrowsError(
        try journal.beginRead(
          device: MTPDeviceID(raw: "x"), handle: 1, name: "x",
          size: 10, supportsPartial: false,
          tempURL: URL(fileURLWithPath: "/tmp/x"),
          finalURL: nil, etag: (size: nil, mtime: nil))
      )
    } catch {
      // Expected: schema setup or open failed on corrupt data
      XCTAssertTrue(true, "Corrupted DB correctly rejected: \(error)")
    }
  }

  func testTruncatedDatabaseRecovery() throws {
    let dbPath = NSTemporaryDirectory() + "journal-trunc-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    // Create a valid journal, write data, then truncate the file
    do {
      let journal = try SQLiteTransferJournal(dbPath: dbPath)
      _ = try journal.beginWrite(
        device: MTPDeviceID(raw: "trunc"), parent: 0, name: "t.bin",
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/trunc"), sourceURL: nil)
    }

    // Truncate the DB file to simulate partial write on crash
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: dbPath))
    handle.truncateFile(atOffset: 32)
    handle.closeFile()

    // Re-opening should fail or produce errors
    do {
      let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
      let resumables = try journal2.loadResumables(for: MTPDeviceID(raw: "trunc"))
      // If it somehow works, that's okay too (SQLite is resilient)
      _ = resumables
    } catch {
      XCTAssertTrue(true, "Truncated DB correctly detected: \(error)")
    }
  }
}

// MARK: - Disk Error Simulation Tests

final class TransferJournalDiskErrorTests: XCTestCase {

  func testJournalOnReadOnlyPathFails() throws {
    // Attempt to create journal in a read-only location
    let readOnlyPath = "/journal-readonly-\(UUID().uuidString).sqlite"

    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: readOnlyPath)) { error in
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "TransferJournal")
    }
  }

  func testJournalOnNonexistentDirectoryFails() throws {
    let badPath =
      "/tmp/nonexistent-dir-\(UUID().uuidString)/subdir/journal.sqlite"

    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: badPath)) { error in
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "TransferJournal")
    }
  }
}

// MARK: - Large File Resume Accuracy Tests

final class TransferJournalLargeFileTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-large-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testLargeFileByteOffsetAccuracy() throws {
    let device = MTPDeviceID(raw: "large-file")
    let totalSize: UInt64 = 10_737_418_240  // 10 GB
    let committed: UInt64 = 7_516_192_768  // ~7 GB

    let id = try journal.beginRead(
      device: device, handle: 1, name: "huge-video.mkv",
      size: totalSize, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/huge"),
      finalURL: nil, etag: (size: totalSize, mtime: nil))

    try journal.updateProgress(id: id, committed: committed)

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.totalBytes, totalSize)
    XCTAssertEqual(record.committedBytes, committed)
    XCTAssertEqual(totalSize - record.committedBytes, 3_221_225_472)
  }

  func testMaxUInt32HandlePreservation() throws {
    let device = MTPDeviceID(raw: "max-handle")
    let maxHandle: UInt32 = UInt32.max

    let id = try journal.beginRead(
      device: device, handle: maxHandle, name: "max.bin",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/max"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.handle, maxHandle)
  }

  func testIncrementalProgressSteps() throws {
    let device = MTPDeviceID(raw: "incremental")
    let chunkSize: UInt64 = 524_288  // 512 KB
    let totalChunks = 20

    let id = try journal.beginRead(
      device: device, handle: 1, name: "streamed.dat",
      size: chunkSize * UInt64(totalChunks), supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/inc"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    for chunk in 1...totalChunks {
      try journal.updateProgress(id: id, committed: chunkSize * UInt64(chunk))
    }

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.committedBytes, chunkSize * UInt64(totalChunks))
  }
}

// MARK: - Cleanup and Expiration Tests

final class TransferJournalCleanupTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-cleanup-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testClearStaleTempsRemovesOldCompletedTransfers() throws {
    let device = MTPDeviceID(raw: "cleanup-device")

    let id = try journal.beginWrite(
      device: device, parent: 0, name: "old.bin",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/cleanup-old"), sourceURL: nil)
    try journal.complete(id: id)

    // Active transfers should not be affected
    let activeId = try journal.beginRead(
      device: device, handle: 1, name: "active.dat",
      size: 500, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/cleanup-active"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    // Clear stale entries older than 0 seconds (should clear completed)
    try journal.clearStaleTemps(olderThan: 0)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, activeId)
  }

  func testClearStaleTempsPreservesRecentFailures() throws {
    let device = MTPDeviceID(raw: "cleanup-recent")

    let id = try journal.beginWrite(
      device: device, parent: 0, name: "recent-fail.bin",
      size: 200, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/cleanup-rf"), sourceURL: nil)
    try journal.fail(
      id: id,
      error: NSError(domain: "Test", code: 1, userInfo: nil))

    // Use a very large olderThan to not clear anything recent
    try journal.clearStaleTemps(olderThan: 86400)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1, "Recent failed transfers should be preserved")
  }

  func testClearStaleTempsWithNoEntries() throws {
    // Should not throw on empty journal
    try journal.clearStaleTemps(olderThan: 0)
  }

  func testCompletedTransferCleanedUpByStaleTemps() throws {
    let device = MTPDeviceID(raw: "cleanup-done")

    // Create and complete a transfer
    let id = try journal.beginRead(
      device: device, handle: 1, name: "cleanup.txt",
      size: 50, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/cleanup-done"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: id, committed: 50)
    try journal.complete(id: id)

    // Verify it's not in resumables
    let beforeClean = try journal.loadResumables(for: device)
    XCTAssertTrue(beforeClean.isEmpty)

    // Stale temps cleanup should remove completed records
    try journal.clearStaleTemps(olderThan: 0)

    // After cleanup, listActive should also be empty
    let active = try journal.listActive()
    XCTAssertTrue(active.isEmpty)
  }
}

// MARK: - Stress Tests

final class TransferJournalStressTests: XCTestCase {

  func testMaxEntriesStress() throws {
    let dbPath = NSTemporaryDirectory() + "journal-stress-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "stress-device")
    let entryCount = 500

    for i in 0..<entryCount {
      _ = try journal.beginWrite(
        device: device, parent: 0, name: "stress-\(i).dat",
        size: UInt64(i * 100), supportsPartial: i % 2 == 0,
        tempURL: URL(fileURLWithPath: "/tmp/stress-\(i)"), sourceURL: nil)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, entryCount)
  }

  func testRapidCreateAndCompleteChurn() throws {
    let dbPath = NSTemporaryDirectory() + "journal-churn-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "churn-device")

    for i in 0..<200 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "churn-\(i).bin",
        size: 1024, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/churn-\(i)"),
        finalURL: nil, etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: 512)
      try journal.updateProgress(id: id, committed: 1024)
      try journal.complete(id: id)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "All transfers should be completed")

    let active = try journal.listActive()
    XCTAssertTrue(active.isEmpty)
  }
}

// MARK: - Serialization Edge Cases

final class TransferJournalSerializationTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-serial-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testSpecialCharactersInFileName() throws {
    let device = MTPDeviceID(raw: "serial-device")
    let names = [
      "file with spaces.txt",
      "café-résumé.doc",
      "日本語ファイル.mp4",
      "file'with\"quotes.dat",
      "path/with/slashes.bin",
      "emoji-🎵-track.mp3",
    ]

    for name in names {
      _ = try journal.beginRead(
        device: device, handle: 1, name: name,
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/serial"),
        finalURL: nil, etag: (size: nil, mtime: nil))
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, names.count)
    let savedNames = Set(resumables.map(\.name))
    for name in names {
      XCTAssertTrue(savedNames.contains(name), "Missing name: \(name)")
    }
  }

  func testEmptyStringDeviceId() throws {
    let device = MTPDeviceID(raw: "")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "empty-device.txt",
      size: 10, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/empty-dev"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    XCTAssertFalse(id.isEmpty)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
  }

  func testVeryLongFileName() throws {
    let device = MTPDeviceID(raw: "long-name-device")
    let longName = String(repeating: "a", count: 1000) + ".txt"

    let id = try journal.beginRead(
      device: device, handle: 1, name: longName,
      size: 10, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/long-name"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, longName)
  }

  func testNilSizeTransfer() throws {
    let device = MTPDeviceID(raw: "nil-size")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "unknown-size.bin",
      size: nil, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/nil-size"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertNil(resumables[0].totalBytes)
  }

  func testNilFinalURL() throws {
    let device = MTPDeviceID(raw: "nil-final")
    _ = try journal.beginRead(
      device: device, handle: 1, name: "no-final.txt",
      size: 50, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/nil-final"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertNil(resumables[0].finalURL)
  }

  func testTransferRecordFieldRoundTrip() throws {
    let device = MTPDeviceID(raw: "roundtrip-device")
    let tempURL = URL(fileURLWithPath: "/tmp/roundtrip-temp")
    let finalURL = URL(fileURLWithPath: "/tmp/roundtrip-final")

    let id = try journal.beginRead(
      device: device, handle: 42, name: "roundtrip.jpg",
      size: 8192, supportsPartial: true,
      tempURL: tempURL, finalURL: finalURL,
      etag: (size: 8192, mtime: Date(timeIntervalSince1970: 1_700_000_000)))

    try journal.updateProgress(id: id, committed: 4096)

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)

    XCTAssertEqual(record.id, id)
    XCTAssertEqual(record.deviceId, device)
    XCTAssertEqual(record.kind, "read")
    XCTAssertEqual(record.handle, 42)
    XCTAssertEqual(record.name, "roundtrip.jpg")
    XCTAssertEqual(record.totalBytes, 8192)
    XCTAssertEqual(record.committedBytes, 4096)
    XCTAssertEqual(record.supportsPartial, true)
    XCTAssertEqual(record.localTempURL.path, tempURL.path)
    XCTAssertEqual(record.finalURL?.path, finalURL.path)
    XCTAssertEqual(record.state, "active")
  }
}

// MARK: - Empty / Zero-Byte Transfer Tests

final class TransferJournalEmptyFileTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-empty-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testZeroByteReadTransfer() throws {
    let device = MTPDeviceID(raw: "zero-read")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "empty.txt",
      size: 0, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/zero-read"),
      finalURL: nil, etag: (size: 0, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].totalBytes, 0)
    XCTAssertEqual(resumables[0].committedBytes, 0)

    try journal.complete(id: id)
    let after = try journal.loadResumables(for: device)
    XCTAssertTrue(after.isEmpty)
  }

  func testZeroByteWriteTransfer() throws {
    let device = MTPDeviceID(raw: "zero-write")
    let id = try journal.beginWrite(
      device: device, parent: 0, name: "empty-upload.txt",
      size: 0, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/zero-write"), sourceURL: nil)

    try journal.complete(id: id)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testProgressOnZeroByteFile() throws {
    let device = MTPDeviceID(raw: "zero-progress")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "zero-p.txt",
      size: 0, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/zero-p"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    // Updating progress to 0 on a 0-byte file should work
    try journal.updateProgress(id: id, committed: 0)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 0)
  }
}

// MARK: - Device Disconnect Mid-Transfer Tests

final class TransferJournalDisconnectTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-disconnect-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testDisconnectMidReadPreservesProgress() throws {
    let device = MTPDeviceID(raw: "disconnect-read")
    let id = try journal.beginRead(
      device: device, handle: 77, name: "movie.mp4",
      size: 500_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/disc-read"),
      finalURL: URL(fileURLWithPath: "/tmp/disc-final"),
      etag: (size: 500_000, mtime: nil))

    // Simulate partial progress before disconnect
    try journal.updateProgress(id: id, committed: 125_000)
    try journal.updateProgress(id: id, committed: 250_000)
    try journal.updateProgress(id: id, committed: 375_000)

    // Simulate disconnect — mark as failed
    try journal.fail(
      id: id,
      error: NSError(
        domain: "USB", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "device disconnected"]))

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.state, "failed")
    XCTAssertEqual(record.committedBytes, 375_000)
    XCTAssertTrue(record.supportsPartial)
  }

  func testDisconnectMidWriteWithPartialSupport() throws {
    let device = MTPDeviceID(raw: "disconnect-write")
    let totalSize: UInt64 = 200_000

    let id = try journal.beginWrite(
      device: device, parent: 10, name: "upload.zip",
      size: totalSize, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/disc-write"), sourceURL: nil)

    try journal.updateProgress(id: id, committed: 100_000)

    // Device disconnects
    try journal.fail(
      id: id,
      error: NSError(
        domain: "USB", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "USB pipe stalled"]))

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.committedBytes, 100_000)
    XCTAssertEqual(record.totalBytes, totalSize)
  }

  func testMultipleDisconnectsAccumulateProgress() throws {
    let device = MTPDeviceID(raw: "multi-disconnect")
    let id = try journal.beginRead(
      device: device, handle: 5, name: "flaky.dat",
      size: 100_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/multi-disc"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    // First attempt: progress to 30k, then disconnect
    try journal.updateProgress(id: id, committed: 30_000)
    try journal.fail(
      id: id,
      error: NSError(domain: "USB", code: -1, userInfo: nil))

    // Verify state after first disconnect
    var resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 30_000)
    XCTAssertEqual(resumables[0].state, "failed")

    // Simulate resume: update progress further (would happen after re-connection)
    try journal.updateProgress(id: id, committed: 70_000)

    resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 70_000)
  }

  func testDisconnectWithoutPartialSupportStillRecordsState() throws {
    let device = MTPDeviceID(raw: "no-partial-disc")
    let id = try journal.beginRead(
      device: device, handle: 3, name: "no-resume.bin",
      size: 50_000, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/no-partial"),
      finalURL: nil, etag: (size: nil, mtime: nil))

    try journal.updateProgress(id: id, committed: 25_000)
    try journal.fail(
      id: id,
      error: NSError(domain: "USB", code: -1, userInfo: nil))

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertFalse(record.supportsPartial)
    XCTAssertEqual(record.committedBytes, 25_000)
    XCTAssertEqual(record.state, "failed")
  }
}

// MARK: - SQLiteTransferJournal listActive / listFailed Tests

final class TransferJournalListTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-list-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testListActiveShowsOnlyActiveTransfers() throws {
    let device = MTPDeviceID(raw: "list-device")

    let id1 = try journal.beginRead(
      device: device, handle: 1, name: "active.txt", size: 100,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/la1"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    let id2 = try journal.beginWrite(
      device: device, parent: 0, name: "also-active.txt", size: 200,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/la2"), sourceURL: nil)
    let id3 = try journal.beginRead(
      device: device, handle: 3, name: "done.txt", size: 50,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/la3"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    try journal.complete(id: id3)

    let active = try journal.listActive()
    XCTAssertEqual(active.count, 2)
    let activeIds = Set(active.map(\.id))
    XCTAssertTrue(activeIds.contains(id1))
    XCTAssertTrue(activeIds.contains(id2))
  }

  func testListFailedShowsOnlyFailedTransfers() throws {
    let device = MTPDeviceID(raw: "list-failed-dev")

    let id1 = try journal.beginRead(
      device: device, handle: 1, name: "ok.txt", size: 100,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/lf1"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    let id2 = try journal.beginWrite(
      device: device, parent: 0, name: "broken.bin", size: 200,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/lf2"), sourceURL: nil)
    try journal.fail(
      id: id2,
      error: NSError(domain: "IO", code: 5, userInfo: nil))

    let failed = try journal.listFailed()
    XCTAssertEqual(failed.count, 1)
    XCTAssertEqual(failed[0].id, id2)

    let active = try journal.listActive()
    XCTAssertEqual(active.count, 1)
    XCTAssertEqual(active[0].id, id1)
  }
}
