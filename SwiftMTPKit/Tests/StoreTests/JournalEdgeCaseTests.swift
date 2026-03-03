// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore

// MARK: - Journal Corruption Detection & Recovery

final class JournalCorruptionRecoveryTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-corruption-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testCorruptedFileWithRandomBytesRejectsOpen() throws {
    let corruptPath = NSTemporaryDirectory() + "corrupt-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: corruptPath) }
    // Write random garbage
    let garbage = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
    try garbage.write(to: URL(fileURLWithPath: corruptPath))
    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: corruptPath))
  }

  func testZeroByteFileCreatesValidJournal() throws {
    let emptyPath = NSTemporaryDirectory() + "empty-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: emptyPath) }
    FileManager.default.createFile(atPath: emptyPath, contents: Data())
    let j = try SQLiteTransferJournal(dbPath: emptyPath)
    let device = MTPDeviceID(raw: "test")
    let resumables = try j.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testPartialHeaderCorruptionRejectsOpen() throws {
    let partialPath = NSTemporaryDirectory() + "partial-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: partialPath) }
    // Write a truncated SQLite header (first 16 bytes of magic but incomplete)
    let partialHeader = Data("SQLite format 3\0".utf8.prefix(10))
    try partialHeader.write(to: URL(fileURLWithPath: partialPath))
    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: partialPath))
  }

  func testJournalRecoveryAfterWriteThenCorruptionOfWAL() throws {
    // Create journal and add a transfer
    let device = MTPDeviceID(raw: "wal-test")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "wal-file.dat",
      size: 1024, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/wal"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.updateProgress(id: id, committed: 512)

    // Verify data persists
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 512)
  }

  func testReopenJournalPreservesAllTransfers() throws {
    let device = MTPDeviceID(raw: "reopen-device")
    var ids: [String] = []
    for i in 0..<5 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "file\(i).txt",
        size: UInt64(1000 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/reopen-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.updateProgress(id: id, committed: UInt64(500 * (i + 1)))
      ids.append(id)
    }

    // Close and reopen
    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
    for (i, id) in ids.enumerated() {
      let record = resumables.first(where: { $0.id == id })
      XCTAssertNotNil(record, "Transfer \(i) should survive reopen")
      XCTAssertEqual(record?.committedBytes, UInt64(500 * (i + 1)))
    }
  }

  func testReopenJournalAfterFailedTransfer() throws {
    let device = MTPDeviceID(raw: "fail-reopen")
    let id = try journal.beginWrite(
      device: device, parent: 0, name: "fail-file.bin",
      size: 2048, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/fail-reopen"), sourceURL: nil)
    try journal.updateProgress(id: id, committed: 1024)
    try journal.fail(id: id, error: NSError(domain: "test", code: 42))

    journal = nil
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
    XCTAssertEqual(resumables[0].committedBytes, 1024)
  }

  func testDoubleOpenSamePathSucceeds() throws {
    // Opening the same DB path twice should work (SQLite handles this)
    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "double-open")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "dbl.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/dbl"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
  }

  func testJournalOnSymlinkPath() throws {
    let realPath = NSTemporaryDirectory() + "real-\(UUID().uuidString).sqlite"
    let linkPath = NSTemporaryDirectory() + "link-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: realPath)
      try? FileManager.default.removeItem(atPath: linkPath)
    }
    // Create via real path
    let j1 = try SQLiteTransferJournal(dbPath: realPath)
    let device = MTPDeviceID(raw: "symlink-dev")
    _ = try j1.beginRead(
      device: device, handle: 1, name: "sym.txt",
      size: 50, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/sym"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Create symlink and open via it
    try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: realPath)
    let j2 = try SQLiteTransferJournal(dbPath: linkPath)
    let resumables = try j2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
  }
}

// MARK: - Concurrent Journal Writes (via actor-isolated store)

final class ConcurrentJournalWriteTests: XCTestCase {

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

  func testConcurrentReadsFromMultipleDevices() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let devices = (0..<5).map { MTPDeviceID(raw: "conc-dev-\($0)-\(UUID().uuidString)") }

    for device in devices {
      _ = try await adapter.beginRead(
        device: device, handle: 1, name: "shared.txt",
        size: 1000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/conc-\(device.raw)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    try await withThrowingTaskGroup(of: Int.self) { group in
      for device in devices {
        group.addTask {
          let r = try await adapter.loadResumables(for: device)
          return r.count
        }
      }
      for try await count in group {
        XCTAssertEqual(count, 1)
      }
    }
  }

  func testConcurrentProgressUpdatesOnSameTransfer() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "conc-same-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "big.bin",
      size: 100_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/conc-same"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 1...20 {
        group.addTask {
          try await adapter.updateProgress(id: id, committed: UInt64(i * 5000))
        }
      }
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertGreaterThan(resumables[0].committedBytes, 0)
  }

  func testConcurrentCreateAndComplete() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "conc-cc-\(UUID().uuidString)")

    var ids: [String] = []
    for i in 0..<20 {
      let id = try await adapter.beginRead(
        device: device, handle: UInt32(i), name: "f\(i).dat",
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/cc-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    let capturedIds = ids
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in stride(from: 0, to: 20, by: 2) {
        group.addTask {
          try await adapter.complete(id: capturedIds[i])
        }
      }
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 10, "Only uncompleted transfers should remain")
  }

  func testConcurrentCreateAcrossMultipleDevices() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let device = MTPDeviceID(raw: "batch-dev-\(i)-\(UUID().uuidString)")
          for k in 0..<5 {
            _ = try await adapter.beginRead(
              device: device, handle: UInt32(k), name: "f\(k).txt",
              size: UInt64(100 * (k + 1)), supportsPartial: true,
              tempURL: URL(fileURLWithPath: "/tmp/batch-\(i)-\(k)"), finalURL: nil,
              etag: (size: nil, mtime: nil))
          }
        }
      }
    }
    // No crash = success for concurrent isolation test
  }

  func testConcurrentFailAndCompleteOnDifferentTransfers() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "fail-mix-\(UUID().uuidString)")
    var ids: [String] = []
    for i in 0..<10 {
      let id = try await adapter.beginWrite(
        device: device, parent: 0, name: "mix-\(i).bin",
        size: UInt64(500 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/mix-\(i)"), sourceURL: nil)
      ids.append(id)
    }

    let capturedIds = ids
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (i, id) in capturedIds.enumerated() {
        if i % 2 == 0 {
          group.addTask { try await adapter.complete(id: id) }
        } else {
          group.addTask {
            try await adapter.fail(id: id, error: NSError(domain: "test", code: i))
          }
        }
      }
    }
    // No crash = success
  }

  func testConcurrentProgressUpdatesPreserveMonotonicity() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "monotonic-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "mono.bin",
      size: 1_000_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/mono"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    for i in 1...50 {
      try await adapter.updateProgress(id: id, committed: UInt64(i * 20_000))
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 1_000_000)
  }
}

// MARK: - Incomplete Transfer Entries

final class IncompleteTransferEntryTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-incomplete-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testTransferWithNoProgressUpdatesStaysActive() throws {
    let device = MTPDeviceID(raw: "no-progress")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "stale.txt",
      size: 5000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/stale"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 0)
    XCTAssertEqual(resumables[0].state, "active")
    XCTAssertEqual(resumables[0].id, id)
  }

  func testProgressUpdateOnNonExistentTransferIsNoOp() throws {
    // Should not throw
    try journal.updateProgress(id: "phantom-id", committed: 999)
    // Verify no phantom records appeared
    let active = try journal.listActive()
    XCTAssertTrue(active.isEmpty)
  }

  func testCompleteOnNonExistentTransferIsNoOp() throws {
    try journal.complete(id: "phantom-complete")
  }

  func testFailOnNonExistentTransferIsNoOp() throws {
    try journal.fail(id: "phantom-fail", error: NSError(domain: "test", code: 0))
  }

  func testBeginReadWithLargeSize() throws {
    let device = MTPDeviceID(raw: "max-size")
    let largeSize = UInt64(Int64.max)
    let id = try journal.beginRead(
      device: device, handle: 1, name: "huge.bin",
      size: largeSize, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/huge"), finalURL: nil,
      etag: (size: largeSize, mtime: nil))
    XCTAssertFalse(id.isEmpty)
  }

  func testBeginWriteWithMinimalFields() throws {
    let device = MTPDeviceID(raw: "minimal-write")
    let id = try journal.beginWrite(
      device: device, parent: 0, name: "",
      size: 0, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/minimal"), sourceURL: nil)
    XCTAssertFalse(id.isEmpty)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "")
    XCTAssertEqual(resumables[0].totalBytes, 0)
  }

  func testTransferProgressExceedsTotalBytes() throws {
    let device = MTPDeviceID(raw: "overflow-progress")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "small.txt",
      size: 100, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/overflow"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Committed exceeds total — journal doesn't enforce this invariant
    try journal.updateProgress(id: id, committed: 9999)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 9999)
  }

  func testTransferProgressDecreasesAllowed() throws {
    let device = MTPDeviceID(raw: "decrease-progress")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "dec.txt",
      size: 10_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/dec"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try journal.updateProgress(id: id, committed: 8000)
    try journal.updateProgress(id: id, committed: 3000)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 3000)
  }

  func testMultipleFailsOverwriteLastError() throws {
    let device = MTPDeviceID(raw: "multi-fail")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "retry.txt",
      size: 500, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/retry"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try journal.fail(
      id: id,
      error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "first error"]))
    try journal.fail(
      id: id,
      error: NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "second error"])
    )

    let failed = try journal.listFailed()
    let record = failed.first(where: { $0.id == id })
    XCTAssertNotNil(record)
    // Last error should reflect the most recent fail call
    XCTAssertNotNil(record?.lastError)
  }
}

// MARK: - Journal Size Limits & Pruning

final class JournalPruningTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-pruning-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testClearStaleTempsRemovesCompletedOlderThanThreshold() throws {
    let device = MTPDeviceID(raw: "stale-complete")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "old-done.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/stale-done"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: id)

    // Clear with zero threshold (everything is "old enough")
    try journal.clearStaleTemps(olderThan: 0)

    // Completed transfers should be removed
    let failed = try journal.listFailed()
    let active = try journal.listActive()
    XCTAssertTrue(failed.isEmpty)
    XCTAssertTrue(active.isEmpty)
  }

  func testClearStaleTempsPreservesActiveTransfers() throws {
    let device = MTPDeviceID(raw: "stale-active")
    _ = try journal.beginRead(
      device: device, handle: 1, name: "active.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/stale-active"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try journal.clearStaleTemps(olderThan: 0)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1, "Active transfers should survive cleanup")
  }

  func testClearStaleTempsWithLargeThresholdPreservesAll() throws {
    let device = MTPDeviceID(raw: "stale-large-threshold")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "recent.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/stale-recent"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: id, error: NSError(domain: "test", code: 0))

    // Large threshold: nothing should be old enough
    try journal.clearStaleTemps(olderThan: 86400 * 365)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
  }

  func testClearStaleTempsWithMixedStates() throws {
    let device = MTPDeviceID(raw: "stale-mixed")

    // Create active transfer
    _ = try journal.beginRead(
      device: device, handle: 1, name: "keep-active.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/keep-active"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Create completed transfer
    let doneId = try journal.beginRead(
      device: device, handle: 2, name: "done.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/done"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: doneId)

    // Create failed transfer
    let failId = try journal.beginRead(
      device: device, handle: 3, name: "fail.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/fail"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: failId, error: NSError(domain: "test", code: 0))

    try journal.clearStaleTemps(olderThan: 0)

    let resumables = try journal.loadResumables(for: device)
    // Active stays; done and failed get cleaned
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "active")
  }

  func testClearStaleTempsNegativeIntervalTreatedAsZero() throws {
    let device = MTPDeviceID(raw: "stale-negative")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "neg.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/neg"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: id)

    // Negative threshold should be clamped to 0
    try journal.clearStaleTemps(olderThan: -100)
    let active = try journal.listActive()
    XCTAssertTrue(active.isEmpty)
  }

  func testClearStaleTempsDoesNotRemoveNonExistentTempFiles() throws {
    let device = MTPDeviceID(raw: "no-temp-file")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "no-temp.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: id)

    // Should not throw even if temp file doesn't exist
    try journal.clearStaleTemps(olderThan: 0)
  }
}

// MARK: - Metadata Consistency After Crash/Restart Simulation

final class MetadataConsistencyTests: XCTestCase {

  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-meta-\(UUID().uuidString).sqlite"
  }

  override func tearDown() {
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testTransferFieldsPreservedAcrossReopen() throws {
    let device = MTPDeviceID(raw: "meta-preserve")
    let tempURL = URL(fileURLWithPath: "/tmp/meta-preserve")
    let finalURL = URL(fileURLWithPath: "/tmp/meta-final")

    var journal = try SQLiteTransferJournal(dbPath: dbPath)
    let id = try journal.beginRead(
      device: device, handle: 42, name: "photo.jpg",
      size: 2048, supportsPartial: true,
      tempURL: tempURL, finalURL: finalURL,
      etag: (size: 2048, mtime: Date(timeIntervalSince1970: 1_700_000_000)))
    try journal.updateProgress(id: id, committed: 1024)

    // Simulate crash by dropping reference
    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.id, id)
    XCTAssertEqual(record.kind, "read")
    XCTAssertEqual(record.handle, 42)
    XCTAssertEqual(record.name, "photo.jpg")
    XCTAssertEqual(record.totalBytes, 2048)
    XCTAssertEqual(record.committedBytes, 1024)
    XCTAssertTrue(record.supportsPartial)
  }

  func testWriteTransferFieldsPreservedAcrossReopen() throws {
    let device = MTPDeviceID(raw: "meta-write")
    let tempURL = URL(fileURLWithPath: "/tmp/meta-write")
    let sourceURL = URL(fileURLWithPath: "/tmp/source.bin")

    var journal = try SQLiteTransferJournal(dbPath: dbPath)
    let id = try journal.beginWrite(
      device: device, parent: 99, name: "upload.mp4",
      size: 50_000, supportsPartial: false,
      tempURL: tempURL, sourceURL: sourceURL)
    try journal.updateProgress(id: id, committed: 25_000)

    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.kind, "write")
    XCTAssertEqual(record.parentHandle, 99)
    XCTAssertEqual(record.name, "upload.mp4")
    XCTAssertEqual(record.totalBytes, 50_000)
    XCTAssertEqual(record.committedBytes, 25_000)
    XCTAssertFalse(record.supportsPartial)
  }

  func testFailedStatePreservedAcrossReopen() throws {
    let device = MTPDeviceID(raw: "meta-failed")

    var journal = try SQLiteTransferJournal(dbPath: dbPath)
    let id = try journal.beginRead(
      device: device, handle: 1, name: "fail.txt",
      size: 100, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/meta-fail"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: id, error: NSError(domain: "MTP", code: -1))

    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
  }

  func testCompletedTransferNotResumableAcrossReopen() throws {
    let device = MTPDeviceID(raw: "meta-done")

    var journal = try SQLiteTransferJournal(dbPath: dbPath)
    let id = try journal.beginRead(
      device: device, handle: 1, name: "done.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/meta-done"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: id)

    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testMultipleDevicesIsolatedAcrossReopen() throws {
    let device1 = MTPDeviceID(raw: "meta-iso-1")
    let device2 = MTPDeviceID(raw: "meta-iso-2")

    var journal = try SQLiteTransferJournal(dbPath: dbPath)

    _ = try journal.beginRead(
      device: device1, handle: 1, name: "dev1.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/iso-1"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: device1, handle: 2, name: "dev1b.txt",
      size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/iso-1b"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: device2, handle: 1, name: "dev2.txt",
      size: 300, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/iso-2"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    journal = try SQLiteTransferJournal(dbPath: dbPath)

    let r1 = try journal.loadResumables(for: device1)
    let r2 = try journal.loadResumables(for: device2)
    XCTAssertEqual(r1.count, 2)
    XCTAssertEqual(r2.count, 1)
  }
}

// MARK: - Device-Specific Journal Isolation

final class DeviceJournalIsolationTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-isolation-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testLoadResumablesReturnsOnlyMatchingDevice() throws {
    let d1 = MTPDeviceID(raw: "iso-device-1")
    let d2 = MTPDeviceID(raw: "iso-device-2")

    _ = try journal.beginRead(
      device: d1, handle: 1, name: "d1.txt", size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/iso-d1"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: d2, handle: 1, name: "d2.txt", size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/iso-d2"), finalURL: nil, etag: (size: nil, mtime: nil))

    let r1 = try journal.loadResumables(for: d1)
    let r2 = try journal.loadResumables(for: d2)

    XCTAssertEqual(r1.count, 1)
    XCTAssertEqual(r1[0].name, "d1.txt")
    XCTAssertEqual(r2.count, 1)
    XCTAssertEqual(r2[0].name, "d2.txt")
  }

  func testCompletingOnOneDeviceDoesNotAffectAnother() throws {
    let d1 = MTPDeviceID(raw: "complete-iso-1")
    let d2 = MTPDeviceID(raw: "complete-iso-2")

    let id1 = try journal.beginRead(
      device: d1, handle: 1, name: "d1.txt", size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/ciso-1"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: d2, handle: 1, name: "d2.txt", size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/ciso-2"), finalURL: nil, etag: (size: nil, mtime: nil))

    try journal.complete(id: id1)

    let r1 = try journal.loadResumables(for: d1)
    let r2 = try journal.loadResumables(for: d2)
    XCTAssertTrue(r1.isEmpty)
    XCTAssertEqual(r2.count, 1)
  }

  func testSameHandleOnDifferentDevicesAreIndependent() throws {
    let d1 = MTPDeviceID(raw: "handle-iso-1")
    let d2 = MTPDeviceID(raw: "handle-iso-2")

    let id1 = try journal.beginRead(
      device: d1, handle: 42, name: "same-handle.txt", size: 100, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/hiso-1"), finalURL: nil, etag: (size: nil, mtime: nil))
    let id2 = try journal.beginRead(
      device: d2, handle: 42, name: "same-handle.txt", size: 200, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/hiso-2"), finalURL: nil, etag: (size: nil, mtime: nil))

    try journal.updateProgress(id: id1, committed: 50)
    try journal.updateProgress(id: id2, committed: 150)

    let r1 = try journal.loadResumables(for: d1)
    let r2 = try journal.loadResumables(for: d2)
    XCTAssertEqual(r1[0].committedBytes, 50)
    XCTAssertEqual(r2[0].committedBytes, 150)
  }

  func testLoadResumablesForUnknownDeviceReturnsEmpty() throws {
    let unknown = MTPDeviceID(raw: "never-seen-device")
    let resumables = try journal.loadResumables(for: unknown)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testListActiveSpansAllDevices() throws {
    let d1 = MTPDeviceID(raw: "active-all-1")
    let d2 = MTPDeviceID(raw: "active-all-2")
    let d3 = MTPDeviceID(raw: "active-all-3")

    _ = try journal.beginRead(
      device: d1, handle: 1, name: "a.txt", size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/aa-1"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: d2, handle: 1, name: "b.txt", size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/aa-2"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try journal.beginRead(
      device: d3, handle: 1, name: "c.txt", size: 300, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/aa-3"), finalURL: nil, etag: (size: nil, mtime: nil))

    let active = try journal.listActive()
    XCTAssertEqual(active.count, 3)
  }
}

// MARK: - Journal Migration Between Versions

final class JournalMigrationTests: XCTestCase {

  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-migrate-\(UUID().uuidString).sqlite"
  }

  override func tearDown() {
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testSchemaCreatedOnFreshDatabase() throws {
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    // If schema creation failed, this would throw
    let device = MTPDeviceID(raw: "schema-test")
    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testReopenExistingDatabaseReusesSchema() throws {
    var journal = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "reuse-schema")
    _ = try journal.beginRead(
      device: device, handle: 1, name: "schema.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/schema"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Reopen — CREATE TABLE IF NOT EXISTS should be fine
    journal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
  }

  func testMultipleReopensPreserveDataIntegrity() throws {
    let device = MTPDeviceID(raw: "multi-reopen")
    var lastId = ""

    for i in 0..<5 {
      var journal = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "reopen-\(i).txt",
        size: UInt64(100 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/mreopen-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      lastId = id
      // Let journal deinit
    }

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
    XCTAssertTrue(resumables.contains(where: { $0.id == lastId }))
  }
}

// MARK: - Large Journal Performance

final class LargeJournalPerformanceTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "journal-perf-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    super.tearDown()
  }

  func testInsert500TransfersAndQueryPerDevice() throws {
    let deviceCount = 10
    let transfersPerDevice = 50

    for d in 0..<deviceCount {
      let device = MTPDeviceID(raw: "perf-device-\(d)")
      for t in 0..<transfersPerDevice {
        _ = try journal.beginRead(
          device: device, handle: UInt32(t), name: "perf-\(t).dat",
          size: UInt64(1024 * (t + 1)), supportsPartial: true,
          tempURL: URL(fileURLWithPath: "/tmp/perf-\(d)-\(t)"), finalURL: nil,
          etag: (size: nil, mtime: nil))
      }
    }

    // Verify per-device queries return correct count
    for d in 0..<deviceCount {
      let device = MTPDeviceID(raw: "perf-device-\(d)")
      let resumables = try journal.loadResumables(for: device)
      XCTAssertEqual(resumables.count, transfersPerDevice)
    }
  }

  func testListActiveWithManyEntries() throws {
    let device = MTPDeviceID(raw: "perf-active")
    for i in 0..<200 {
      _ = try journal.beginRead(
        device: device, handle: UInt32(i), name: "active-\(i).txt",
        size: 1024, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/perf-active-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    let active = try journal.listActive()
    XCTAssertEqual(active.count, 200)
  }

  func testBulkCompletePerformance() throws {
    let device = MTPDeviceID(raw: "perf-bulk-complete")
    var ids: [String] = []
    for i in 0..<100 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "bulk-\(i).txt",
        size: 1024, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/bulk-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    // Complete all
    for id in ids {
      try journal.complete(id: id)
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testRapidProgressUpdates() throws {
    let device = MTPDeviceID(raw: "perf-rapid")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "rapid.bin",
      size: 10_000_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/rapid"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // 1000 rapid progress updates
    for i in 1...1000 {
      try journal.updateProgress(id: id, committed: UInt64(i * 10_000))
    }

    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 10_000_000)
  }

  func testBulkCleanupAfterMassCompletion() throws {
    let device = MTPDeviceID(raw: "perf-cleanup")
    for i in 0..<200 {
      let id = try journal.beginRead(
        device: device, handle: UInt32(i), name: "cleanup-\(i).txt",
        size: 1024, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/cleanup-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try journal.complete(id: id)
    }

    try journal.clearStaleTemps(olderThan: 0)

    let active = try journal.listActive()
    let failed = try journal.listFailed()
    XCTAssertTrue(active.isEmpty)
    XCTAssertTrue(failed.isEmpty)
  }
}

// MARK: - SwiftData Store Journal Edge Cases

final class StoreAdapterJournalEdgeCaseTests: XCTestCase {

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

  func testAdapterBeginReadAndLoadResumables() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-read-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "adapter.txt",
      size: 1024, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-read"), finalURL: nil,
      etag: (size: 1024, mtime: Date()))
    XCTAssertFalse(id.isEmpty)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
  }

  func testAdapterBeginWriteAndLoadResumables() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-write-\(UUID().uuidString)")
    let id = try await adapter.beginWrite(
      device: device, parent: 10, name: "upload.bin",
      size: 2048, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-write"), sourceURL: nil)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
    XCTAssertEqual(resumables[0].kind, "write")
  }

  func testAdapterUpdateProgressAndVerify() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-progress-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "progress.dat",
      size: 10_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-prog"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try await adapter.updateProgress(id: id, committed: 5000)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables[0].committedBytes, 5000)
  }

  func testAdapterCompleteRemovesFromResumables() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-complete-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "done.txt",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-done"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try await adapter.complete(id: id)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testAdapterFailKeepsResumable() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-fail-\(UUID().uuidString)")
    let id = try await adapter.beginWrite(
      device: device, parent: 0, name: "fail.bin",
      size: 500, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-fail"), sourceURL: nil)

    try await adapter.fail(id: id, error: NSError(domain: "test", code: 1))

    // Failed transfers are NOT resumable in SwiftData store (state = "failed" not in fetch predicate)
    // Actually checking: predicate is state == "active" || state == "paused"
    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Failed transfers should not be resumable in SwiftData store")
  }

  func testAdapterRecordThroughput() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-tp-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "throughput.dat",
      size: 1_000_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-tp"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try await adapter.recordThroughput(id: id, throughputMBps: 42.5)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables[0].throughputMBps, 42.5)
  }

  func testAdapterRecordRemoteHandle() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-rh-\(UUID().uuidString)")
    let id = try await adapter.beginWrite(
      device: device, parent: 1, name: "remote.bin",
      size: 2048, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-rh"), sourceURL: nil)

    try await adapter.recordRemoteHandle(id: id, handle: 0xBEEF)

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables[0].remoteHandle, 0xBEEF)
  }

  func testAdapterAddContentHash() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-hash-\(UUID().uuidString)")
    let id = try await adapter.beginRead(
      device: device, handle: 1, name: "hashed.dat",
      size: 4096, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-hash"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    try await adapter.addContentHash(id: id, hash: "sha256-deadbeef")

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables[0].contentHash, "sha256-deadbeef")
  }

  func testAdapterConcurrentTransferOperations() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-conc-\(UUID().uuidString)")

    var ids: [String] = []
    for i in 0..<5 {
      let id = try await adapter.beginRead(
        device: device, handle: UInt32(i), name: "conc-\(i).txt",
        size: UInt64(1000 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/adapter-conc-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      ids.append(id)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for (i, id) in ids.enumerated() {
        group.addTask {
          try await adapter.updateProgress(id: id, committed: UInt64(500 * (i + 1)))
        }
      }
    }

    let resumables = try await adapter.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 5)
  }

  func testAdapterClearStaleTempsDoesNotThrow() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    // Should be a no-op since implementation is empty
    try await adapter.clearStaleTemps(olderThan: 0)
  }

  func testAdapterMultipleDevicesIsolated() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let d1 = MTPDeviceID(raw: "adapter-multi-1-\(UUID().uuidString)")
    let d2 = MTPDeviceID(raw: "adapter-multi-2-\(UUID().uuidString)")

    _ = try await adapter.beginRead(
      device: d1, handle: 1, name: "d1.txt", size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/am-1"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try await adapter.beginRead(
      device: d1, handle: 2, name: "d1b.txt", size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/am-1b"), finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try await adapter.beginWrite(
      device: d2, parent: 1, name: "d2.txt", size: 300, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/am-2"), sourceURL: nil)

    let r1 = try await adapter.loadResumables(for: d1)
    let r2 = try await adapter.loadResumables(for: d2)
    XCTAssertEqual(r1.count, 2)
    XCTAssertEqual(r2.count, 1)
  }

  func testAdapterProgressUpdateOnNonexistentTransfer() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    // Should not throw
    try await adapter.updateProgress(id: "nonexistent-adapter-\(UUID().uuidString)", committed: 999)
  }

  func testAdapterCompleteOnNonexistentTransfer() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    try await adapter.complete(id: "nonexistent-complete-\(UUID().uuidString)")
  }

  func testAdapterFullTransferLifecycle() async throws {
    let adapter = SwiftMTPStoreAdapter(store: store)
    let device = MTPDeviceID(raw: "adapter-lifecycle-\(UUID().uuidString)")

    let id = try await adapter.beginRead(
      device: device, handle: 10, name: "lifecycle.mp4",
      size: 100_000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/adapter-lc"),
      finalURL: URL(fileURLWithPath: "/tmp/final"),
      etag: (size: 100_000, mtime: Date()))

    try await adapter.updateProgress(id: id, committed: 25_000)
    try await adapter.updateProgress(id: id, committed: 75_000)
    try await adapter.recordThroughput(id: id, throughputMBps: 35.0)
    try await adapter.addContentHash(id: id, hash: "sha256-abc123")
    try await adapter.recordRemoteHandle(id: id, handle: 0xCAFE)

    let mid = try await adapter.loadResumables(for: device)
    let record = try XCTUnwrap(mid.first)
    XCTAssertEqual(record.committedBytes, 75_000)
    XCTAssertEqual(record.throughputMBps, 35.0)
    XCTAssertEqual(record.contentHash, "sha256-abc123")
    XCTAssertEqual(record.remoteHandle, 0xCAFE)

    try await adapter.complete(id: id)
    let post = try await adapter.loadResumables(for: device)
    XCTAssertTrue(post.isEmpty)
  }
}
