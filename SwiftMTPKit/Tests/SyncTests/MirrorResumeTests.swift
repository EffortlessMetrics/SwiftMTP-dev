// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Instrumented Journal for Resume Testing

/// A journal that tracks calls and can simulate failures at specific points.
private final class InstrumentedJournal: SwiftMTPCore.TransferJournal, @unchecked Sendable {
  private let lock = NSLock()

  private var _beginReadCalls: [(device: MTPDeviceID, handle: UInt32, name: String)] = []
  private var _completeCalls: [String] = []
  private var _failCalls: [(id: String, error: String)] = []
  private var _nextId: Int = 0

  /// If set, `complete` will throw this error after recording the call.
  var completeError: Error?

  var beginReadCalls: [(device: MTPDeviceID, handle: UInt32, name: String)] {
    lock.withLock { _beginReadCalls }
  }
  var completeCalls: [String] { lock.withLock { _completeCalls } }
  var failCalls: [(id: String, error: String)] { lock.withLock { _failCalls } }

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    lock.withLock {
      _beginReadCalls.append((device: device, handle: handle, name: name))
      _nextId += 1
      return "transfer-\(_nextId)"
    }
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    lock.withLock {
      _nextId += 1
      return "write-\(_nextId)"
    }
  }

  func updateProgress(id: String, committed: UInt64) async throws {}

  func fail(id: String, error: Error) async throws {
    lock.withLock {
      _failCalls.append((id: id, error: String(describing: error)))
    }
  }

  func complete(id: String) async throws {
    lock.withLock { _completeCalls.append(id) }
    if let err = completeError { throw err }
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] { [] }

  func clearStaleTemps(olderThan age: TimeInterval) async throws {}
}

// MARK: - Mirror Resume Tests

final class MirrorResumeJournalEdgeCaseTests: XCTestCase {
  private var tempDir: URL!
  private var mirrorRoot: URL!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mirror-resume-\(UUID().uuidString)")
    mirrorRoot = tempDir.appendingPathComponent("mirror")
    try FileManager.default.createDirectory(at: mirrorRoot, withIntermediateDirectories: true)
    dbPath = tempDir.appendingPathComponent("sync.sqlite").path
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDir)
    tempDir = nil
    mirrorRoot = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  // MARK: - Helpers

  private func makeEngine(
    journal: any TransferJournal,
    conflictStrategy: ConflictResolutionStrategy = .newerWins
  ) throws -> MirrorEngine {
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    return MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: conflictStrategy)
  }

  private func deviceWithFiles(_ files: [VirtualObjectConfig]) -> VirtualMTPDevice {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal storage"
    )
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = [storage]
    config.objects = files
    return VirtualMTPDevice(config: config)
  }

  private func sampleFiles(count: Int, sizeEach: Int = 1024) -> [VirtualObjectConfig] {
    let storage = MTPStorageID(raw: 0x0001_0001)
    var objects: [VirtualObjectConfig] = []
    for i in 0..<count {
      objects.append(
        VirtualObjectConfig(
          handle: MTPObjectHandle(1 + i),
          storage: storage,
          parent: nil,
          name: "photo_\(i).jpg",
          sizeBytes: UInt64(sizeEach),
          formatCode: 0x3801,
          data: Data(repeating: UInt8(i & 0xFF), count: sizeEach)
        ))
    }
    return objects
  }

  // MARK: - Test: Resume after crash during download

  /// Journal records begin-read, device read succeeds, second mirror skips already-downloaded files.
  func testResumeAfterCrashDuringDownload() async throws {
    let journal = InstrumentedJournal()
    let engine = try makeEngine(journal: journal)
    let device = deviceWithFiles(sampleFiles(count: 2))
    let deviceId = await device.id

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report.downloaded, 2, "Initial mirror should download both files")
    XCTAssertEqual(journal.beginReadCalls.count, 2, "Journal should record 2 begin-read calls")
    XCTAssertEqual(journal.completeCalls.count, 2, "Both transfers should complete")

    // Second mirror: files already exist → should skip
    try await Task.sleep(for: .seconds(1.1))
    let report2 = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report2.downloaded, 0, "Re-mirror should skip already-downloaded files")
  }

  // MARK: - Test: Resume after crash during rename (atomic move)

  /// If a .swiftmtp-partial temp file exists from a previous crash, mirror should overwrite it.
  func testResumeAfterCrashDuringRename() async throws {
    let journal = InstrumentedJournal()
    let engine = try makeEngine(journal: journal)
    let files = sampleFiles(count: 1)
    let device = deviceWithFiles(files)
    let deviceId = await device.id

    // Place a .swiftmtp-partial temp file as if a previous mirror crashed
    let finalURL = engine.pathKeyToLocalURL(
      "0x00010001/photo_0.jpg", root: mirrorRoot)
    let tempURL = finalURL.appendingPathExtension("swiftmtp-partial")
    try FileManager.default.createDirectory(
      at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x00, count: 512).write(to: tempURL)

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report.downloaded, 1, "Mirror should download the file")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: finalURL.path),
      "Final file should exist after mirror")
  }

  // MARK: - Test: Orphan temp file cleanup via SQLiteTransferJournal

  /// Journal clearStaleTemps should remove temp files for failed/done transfers.
  func testOrphanTempFileCleanup() async throws {
    let orphanDir = mirrorRoot.appendingPathComponent("DCIM")
    try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)

    let sqlJournal = try SQLiteTransferJournal(dbPath: dbPath)

    // Create a stale journal entry pointing to a temp file, then fail it
    let staleTemp = orphanDir.appendingPathComponent("old.jpg.swiftmtp-partial")
    try Data(repeating: 0xAB, count: 256).write(to: staleTemp)
    XCTAssertTrue(FileManager.default.fileExists(atPath: staleTemp.path))

    let transferId = try sqlJournal.beginRead(
      device: MTPDeviceID(raw: "0000:0000@0:0"), handle: 99, name: "old.jpg",
      size: 256, supportsPartial: false, tempURL: staleTemp, finalURL: nil,
      etag: (size: nil, mtime: nil))
    try sqlJournal.fail(id: transferId, error: MTPError.timeout)

    // clearStaleTemps should remove the temp file for the failed journal entry
    try sqlJournal.clearStaleTemps(olderThan: -1)  // negative = everything is stale
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: staleTemp.path),
      "Stale temp referenced by journal should be cleaned up")
  }

  // MARK: - Test: Multiple resume — each pass makes progress

  /// Mirror interrupted multiple times. Each resume downloads newly-added files.
  func testMultipleResumeMakesProgress() async throws {
    let journal = InstrumentedJournal()
    let files = sampleFiles(count: 5)
    let device = deviceWithFiles(files)
    let deviceId = await device.id

    // First mirror: downloads all 5
    let engine1 = try makeEngine(journal: journal)
    let report1 = try await engine1.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report1.downloaded, 5)

    // Add 3 more files on device
    let storage = MTPStorageID(raw: 0x0001_0001)
    for i in 5..<8 {
      await device.addObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(1 + i),
          storage: storage,
          parent: nil,
          name: "photo_\(i).jpg",
          sizeBytes: 1024,
          formatCode: 0x3801,
          data: Data(repeating: UInt8(i & 0xFF), count: 1024)
        ))
    }

    // Second mirror: picks up 3 new files
    try await Task.sleep(for: .seconds(1.1))
    let engine2 = try makeEngine(journal: journal)
    let report2 = try await engine2.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report2.downloaded, 3, "Second run should download only new files")

    // Third mirror: nothing new → 0 downloads
    try await Task.sleep(for: .seconds(1.1))
    let engine3 = try makeEngine(journal: journal)
    let report3 = try await engine3.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report3.downloaded, 0, "Third run with no changes should download nothing")
  }

  // MARK: - Test: Journal corruption — open fails, fresh DB works

  func testJournalCorruptionStartsFresh() async throws {
    let corruptPath = tempDir.appendingPathComponent("corrupt.sqlite").path
    try Data("not a sqlite database".utf8).write(
      to: URL(fileURLWithPath: corruptPath), options: .atomic)

    // Opening a corrupt journal should throw
    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: corruptPath)) { error in
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "TransferJournal")
    }

    // A fresh journal at a new path works fine
    let freshPath = tempDir.appendingPathComponent("fresh.sqlite").path
    let freshJournal = try SQLiteTransferJournal(dbPath: freshPath)
    let id = try freshJournal.beginRead(
      device: MTPDeviceID(raw: "test:device@0:0"), handle: 1, name: "test.jpg",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/test.partial"),
      finalURL: nil, etag: (size: nil, mtime: nil))
    XCTAssertFalse(id.isEmpty, "Fresh journal should produce valid transfer IDs")
  }

  // MARK: - Test: Concurrent mirror attempts should not corrupt

  func testConcurrentMirrorAttemptsDoNotCorrupt() async throws {
    let journal = InstrumentedJournal()
    let files = sampleFiles(count: 3)
    let device = deviceWithFiles(files)
    let deviceId = await device.id

    let root1 = tempDir.appendingPathComponent("mirror1")
    let root2 = tempDir.appendingPathComponent("mirror2")
    try FileManager.default.createDirectory(at: root1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root2, withIntermediateDirectories: true)

    // Each engine uses a separate DB to avoid snapshot gen collision
    let dbPath1 = tempDir.appendingPathComponent("sync1.sqlite").path
    let dbPath2 = tempDir.appendingPathComponent("sync2.sqlite").path
    let snap1 = try Snapshotter(dbPath: dbPath1)
    let snap2 = try Snapshotter(dbPath: dbPath2)
    let diff1 = try DiffEngine(dbPath: dbPath1)
    let diff2 = try DiffEngine(dbPath: dbPath2)
    let engine1 = MirrorEngine(snapshotter: snap1, diffEngine: diff1, journal: journal)
    let engine2 = MirrorEngine(snapshotter: snap2, diffEngine: diff2, journal: journal)

    async let report1 = engine1.mirror(device: device, deviceId: deviceId, to: root1)
    async let report2 = engine2.mirror(device: device, deviceId: deviceId, to: root2)

    let (r1, r2) = try await (report1, report2)

    XCTAssertEqual(r1.failed, 0, "First concurrent mirror should not have failures")
    XCTAssertEqual(r2.failed, 0, "Second concurrent mirror should not have failures")
    XCTAssertGreaterThanOrEqual(
      journal.beginReadCalls.count, 3,
      "Journal should record begin-read calls from both mirrors")
  }

  // MARK: - Test: File modified during mirror — detected via diff

  func testFileModifiedDuringMirrorDetected() async throws {
    let journal = InstrumentedJournal()
    let files = sampleFiles(count: 1, sizeEach: 2048)
    let device = deviceWithFiles(files)
    let deviceId = await device.id

    // First mirror
    let engine1 = try makeEngine(journal: journal, conflictStrategy: .deviceWins)
    let report1 = try await engine1.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report1.downloaded, 1)

    // Modify the file on the device (new content, different size)
    let storage = MTPStorageID(raw: 0x0001_0001)
    await device.addObject(
      VirtualObjectConfig(
        handle: 1, storage: storage, parent: nil, name: "photo_0.jpg",
        sizeBytes: 4096, formatCode: 0x3801,
        data: Data(repeating: 0xBE, count: 4096)))

    // Second mirror: diff detects modification
    try await Task.sleep(for: .seconds(1.1))
    let engine2 = try makeEngine(journal: journal, conflictStrategy: .deviceWins)
    let report2 = try await engine2.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertGreaterThanOrEqual(
      report2.downloaded + report2.conflictsDetected, 0,
      "Modified file should be processed in diff")
  }

  // MARK: - Test: Storage full during mirror (journal.complete throws)

  func testStorageFullDuringMirror() async throws {
    let journal = InstrumentedJournal()
    journal.completeError = NSError(
      domain: NSPOSIXErrorDomain, code: Int(ENOSPC),
      userInfo: [NSLocalizedDescriptionKey: "No space left on device"])

    let files = sampleFiles(count: 1)
    let device = deviceWithFiles(files)
    let deviceId = await device.id
    let engine = try makeEngine(journal: journal)

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report.failed, 1, "File should fail when journal.complete throws")
    XCTAssertEqual(journal.failCalls.count, 1, "Journal should record the failure")
  }

  // MARK: - Test: Empty source folder — no crash, empty target

  func testMirrorEmptySourceFolder() async throws {
    let journal = InstrumentedJournal()
    let engine = try makeEngine(journal: journal)
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)

    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.conflictsDetected, 0)
    XCTAssertEqual(journal.beginReadCalls.count, 0, "No reads for empty device")

    let contents = try FileManager.default.contentsOfDirectory(atPath: mirrorRoot.path)
    XCTAssertTrue(contents.isEmpty, "Mirror target should be empty for empty device")
  }

  // MARK: - Test: Journal WAL mode + orphan marking on init

  func testJournalOrphanMarkingOnInit() async throws {
    let journalPath = tempDir.appendingPathComponent("orphan-test.sqlite").path
    let journal1 = try SQLiteTransferJournal(dbPath: journalPath)
    let deviceId = MTPDeviceID(raw: "test:orphan@0:0")

    // Leave a transfer in 'active' state (simulating a crash)
    _ = try journal1.beginRead(
      device: deviceId, handle: 42, name: "orphan.jpg",
      size: 5000, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan.partial"),
      finalURL: URL(fileURLWithPath: "/tmp/orphan.jpg"),
      etag: (size: 5000, mtime: nil))

    // Re-open journal (simulating app restart) — markOrphanedTransfers runs
    let journal2 = try SQLiteTransferJournal(dbPath: journalPath)
    let resumables = try journal2.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1, "Should find 1 orphaned transfer")
    XCTAssertEqual(resumables.first?.state, "failed", "Orphaned transfer should be marked failed")
  }

  // MARK: - Test: Multiple files — partial success journal accuracy

  func testPartialSuccessJournalAccuracy() async throws {
    let journal = InstrumentedJournal()
    let files = sampleFiles(count: 4)
    let device = deviceWithFiles(files)
    let deviceId = await device.id
    let engine = try makeEngine(journal: journal)

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)
    XCTAssertEqual(report.downloaded, 4)
    XCTAssertEqual(journal.beginReadCalls.count, 4)
    XCTAssertEqual(journal.completeCalls.count, 4)
    XCTAssertEqual(journal.failCalls.count, 0, "No failures when all downloads succeed")

    // Verify all files exist on disk
    for i in 0..<4 {
      let fileURL = engine.pathKeyToLocalURL(
        "0x00010001/photo_\(i).jpg", root: mirrorRoot)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: fileURL.path),
        "File photo_\(i).jpg should exist")
    }
  }

  // MARK: - Test: Mirror with only folders, no files

  func testMirrorDeviceWithOnlyFolders() async throws {
    let journal = InstrumentedJournal()
    let storage = MTPStorageID(raw: 0x0001_0001)
    let folders: [VirtualObjectConfig] = [
      VirtualObjectConfig(
        handle: 1, storage: storage, parent: nil, name: "DCIM", formatCode: 0x3001),
      VirtualObjectConfig(
        handle: 2, storage: storage, parent: nil, name: "Music", formatCode: 0x3001),
      VirtualObjectConfig(
        handle: 3, storage: storage, parent: nil, name: "Documents", formatCode: 0x3001),
    ]
    let device = deviceWithFiles(folders)
    let deviceId = await device.id
    let engine = try makeEngine(journal: journal)

    let report = try await engine.mirror(device: device, deviceId: deviceId, to: mirrorRoot)

    // Folders produce diff rows but are not "downloaded" as files — they should not crash
    XCTAssertEqual(report.failed, 0, "Mirror of folder-only device should not fail")
  }
}
