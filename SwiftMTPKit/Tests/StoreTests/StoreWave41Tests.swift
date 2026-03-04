// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SQLite3
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore

// MARK: - Wave 41: Journal WAL Mode

final class JournalWALModeTests: XCTestCase {

  private var journal: SQLiteTransferJournal!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "wal-test-\(UUID().uuidString).sqlite"
    journal = try SQLiteTransferJournal(dbPath: dbPath)
  }

  override func tearDown() {
    journal = nil
    if let dbPath { try? FileManager.default.removeItem(atPath: dbPath) }
    try? FileManager.default.removeItem(atPath: dbPath + "-wal")
    try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    super.tearDown()
  }

  func testWALModeActiveOnFileBased() throws {
    // Verify journal_mode is WAL by querying the database directly
    var db: OpaquePointer?
    defer { if db != nil { sqlite3_close(db) } }
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
      XCTFail("Could not open database")
      return
    }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &stmt, nil) == SQLITE_OK else {
      XCTFail("Could not prepare PRAGMA")
      return
    }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else {
      XCTFail("No row returned")
      return
    }
    let mode = String(cString: sqlite3_column_text(stmt, 0))
    XCTAssertEqual(mode, "wal", "File-based journal should use WAL mode")
  }

  func testWALFilesCreatedOnDisk() throws {
    // After journal init, WAL and SHM files should exist
    let device = MTPDeviceID(raw: "wal-device")
    _ = try journal.beginRead(
      device: device, handle: 1, name: "wal-test.jpg",
      size: 1024, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/wal-test"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    let walExists = FileManager.default.fileExists(atPath: dbPath + "-wal")
    let shmExists = FileManager.default.fileExists(atPath: dbPath + "-shm")
    // WAL/SHM files are created by SQLite when WAL mode is active
    XCTAssertTrue(walExists || shmExists, "WAL or SHM file should exist for WAL mode journal")
  }

  func testConcurrentReadersWithWAL() throws {
    let device = MTPDeviceID(raw: "wal-concurrent")
    let id = try journal.beginRead(
      device: device, handle: 1, name: "concurrent.bin",
      size: 2048, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/wal-concurrent"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    // Open a second reader connection while first is active
    let journal2 = try SQLiteTransferJournal(dbPath: dbPath)

    // The second journal's init calls markOrphanedTransfers, so active → failed
    let resumables = try journal2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id)
  }

  func testWALSurvivesMultipleReopens() throws {
    let device = MTPDeviceID(raw: "wal-reopen")
    for i in 0..<3 {
      let j = try SQLiteTransferJournal(dbPath: dbPath)
      _ = try j.beginRead(
        device: device, handle: UInt32(i + 100), name: "reopen-\(i).bin",
        size: 512, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/wal-reopen-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    // Verify all are present (orphaned to failed)
    let finalJournal = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try finalJournal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 3, "All transfers should survive multiple reopens")
  }
}

// MARK: - Wave 41: Orphan Detection

final class JournalOrphanDetectionTests: XCTestCase {

  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "orphan-test-\(UUID().uuidString).sqlite"
  }

  override func tearDown() {
    if let dbPath {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }
    super.tearDown()
  }

  func testActiveTransfersMarkedOrphanedOnReopen() throws {
    let device = MTPDeviceID(raw: "orphan-device")

    // Create journal and add active transfers
    var journal: SQLiteTransferJournal! = try SQLiteTransferJournal(dbPath: dbPath)
    let id1 = try journal.beginRead(
      device: device, handle: 1, name: "active1.jpg",
      size: 1000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/orphan1"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    let id2 = try journal.beginWrite(
      device: device, parent: 0, name: "active2.bin",
      size: 2000, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan2"), sourceURL: nil)
    try journal.updateProgress(id: id1, committed: 500)
    try journal.updateProgress(id: id2, committed: 1000)

    // Simulate crash by dropping reference without completing
    journal = nil

    // Reopen — markOrphanedTransfers should run
    let reopened = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try reopened.loadResumables(for: device)

    XCTAssertEqual(resumables.count, 2)
    for record in resumables {
      XCTAssertEqual(record.state, "failed", "Active transfer \(record.id) should be marked failed")
    }

    // Verify committed bytes are preserved
    let r1 = resumables.first(where: { $0.id == id1 })
    XCTAssertEqual(r1?.committedBytes, 500, "Committed bytes should be preserved after orphan mark")
    let r2 = resumables.first(where: { $0.id == id2 })
    XCTAssertEqual(r2?.committedBytes, 1000)
  }

  func testCompletedTransfersNotAffectedByOrphanDetection() throws {
    let device = MTPDeviceID(raw: "orphan-complete")
    var journal: SQLiteTransferJournal! = try SQLiteTransferJournal(dbPath: dbPath)

    let doneId = try journal.beginRead(
      device: device, handle: 1, name: "done.jpg",
      size: 500, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan-done"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.complete(id: doneId)

    let activeId = try journal.beginRead(
      device: device, handle: 2, name: "active.jpg",
      size: 500, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan-active"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    journal = nil
    let reopened = try SQLiteTransferJournal(dbPath: dbPath)

    // Completed transfers should NOT appear in resumables
    let resumables = try reopened.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, activeId)
    XCTAssertEqual(resumables[0].state, "failed")
  }

  func testFailedTransfersRemainFailedAfterOrphanDetection() throws {
    let device = MTPDeviceID(raw: "orphan-failed")
    var journal: SQLiteTransferJournal! = try SQLiteTransferJournal(dbPath: dbPath)

    let failedId = try journal.beginRead(
      device: device, handle: 1, name: "failed.jpg",
      size: 500, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/orphan-fail"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.fail(id: failedId, error: NSError(domain: "test", code: 1))

    journal = nil
    let reopened = try SQLiteTransferJournal(dbPath: dbPath)

    let resumables = try reopened.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].state, "failed")
  }

  func testOrphanDetectionWithEmptyJournal() throws {
    // Create and immediately reopen — no crash
    var journal: SQLiteTransferJournal! = try SQLiteTransferJournal(dbPath: dbPath)
    journal = nil
    let reopened = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "empty-orphan")
    let resumables = try reopened.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty)
  }

  func testOrphanDetectionAcrossMultipleDevices() throws {
    let dev1 = MTPDeviceID(raw: "orphan-dev1")
    let dev2 = MTPDeviceID(raw: "orphan-dev2")

    var journal: SQLiteTransferJournal! = try SQLiteTransferJournal(dbPath: dbPath)
    let id1 = try journal.beginRead(
      device: dev1, handle: 1, name: "dev1.jpg",
      size: 100, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan-d1"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    let id2 = try journal.beginRead(
      device: dev2, handle: 1, name: "dev2.jpg",
      size: 200, supportsPartial: false,
      tempURL: URL(fileURLWithPath: "/tmp/orphan-d2"), finalURL: nil,
      etag: (size: nil, mtime: nil))

    journal = nil
    let reopened = try SQLiteTransferJournal(dbPath: dbPath)

    let r1 = try reopened.loadResumables(for: dev1)
    let r2 = try reopened.loadResumables(for: dev2)
    XCTAssertEqual(r1.count, 1)
    XCTAssertEqual(r2.count, 1)
    XCTAssertEqual(r1[0].state, "failed")
    XCTAssertEqual(r2[0].state, "failed")
  }
}

// MARK: - Wave 41: Schema Migration

final class JournalSchemaMigrationTests: XCTestCase {

  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    dbPath = NSTemporaryDirectory() + "migrate-test-\(UUID().uuidString).sqlite"
  }

  override func tearDown() {
    if let dbPath {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }
    super.tearDown()
  }

  func testMigrationAddsNewColumnsToOldSchema() throws {
    // Create a database with the original schema (no throughputMBps, remoteHandle, contentHash)
    var db: OpaquePointer?
    defer { if db != nil { sqlite3_close(db) } }
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
      XCTFail("Could not create database")
      return
    }
    let createSQL = """
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
      """
    var errMsg: UnsafeMutablePointer<CChar>?
    sqlite3_exec(db, createSQL, nil, nil, &errMsg)
    if let errMsg { sqlite3_free(errMsg) }

    // Insert a row using old schema
    let insertSQL = """
      INSERT INTO transfers (id, deviceId, kind, handle, name, totalBytes, committedBytes,
        supportsPartial, localTempURL, state, updatedAt)
      VALUES ('old-xfer', 'migrate-dev', 'read', 42, 'old.jpg', 5000, 2500, 1,
        '/tmp/old', 'active', \(Int64(Date().timeIntervalSince1970)))
      """
    sqlite3_exec(db, insertSQL, nil, nil, &errMsg)
    if let errMsg { sqlite3_free(errMsg) }
    sqlite3_close(db)
    db = nil

    // Open with SQLiteTransferJournal — migration should add new columns
    let journal = try SQLiteTransferJournal(dbPath: dbPath)

    // The old active transfer should be orphaned
    let device = MTPDeviceID(raw: "migrate-dev")
    let resumables = try journal.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "old.jpg")
    XCTAssertEqual(resumables[0].committedBytes, 2500)

    // Verify new columns work: create a new transfer and use new fields
    let newId = try journal.beginRead(
      device: device, handle: 99, name: "new.jpg",
      size: 8000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: "/tmp/new"), finalURL: nil,
      etag: (size: nil, mtime: nil))
    try journal.recordThroughput(id: newId, throughputMBps: 42.5)
    try journal.recordRemoteHandle(id: newId, handle: 123)
    try journal.addContentHash(id: newId, hash: "abc123def456")

    let active = try journal.listActive()
    let newRecord = active.first(where: { $0.id == newId })
    XCTAssertNotNil(newRecord)
  }

  func testMigrationIsIdempotent() throws {
    // Create journal, close, reopen multiple times — migration should not fail
    for _ in 0..<5 {
      let j = try SQLiteTransferJournal(dbPath: dbPath)
      let device = MTPDeviceID(raw: "idempotent-dev")
      _ = try j.beginRead(
        device: device, handle: 1, name: "idem.bin",
        size: 100, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/idem"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }
    // If we get here without throwing, migration is idempotent
    let final_ = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try final_.loadResumables(for: MTPDeviceID(raw: "idempotent-dev"))
    XCTAssertFalse(resumables.isEmpty)
  }

  func testOldSchemaDataPreservedAfterMigration() throws {
    // Create DB with old schema and multiple rows
    var db: OpaquePointer?
    defer { if db != nil { sqlite3_close(db) } }
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
      XCTFail("Could not create database")
      return
    }
    let now = Int64(Date().timeIntervalSince1970)
    let sql = """
      PRAGMA journal_mode=WAL;
      CREATE TABLE transfers (
        id TEXT PRIMARY KEY, deviceId TEXT NOT NULL, kind TEXT NOT NULL,
        handle INTEGER, parentHandle INTEGER, pathKey TEXT, name TEXT,
        totalBytes INTEGER, committedBytes INTEGER NOT NULL DEFAULT 0,
        supportsPartial INTEGER NOT NULL DEFAULT 0, etag_size INTEGER,
        etag_mtime INTEGER, localTempURL TEXT, finalURL TEXT,
        state TEXT NOT NULL, lastError TEXT, updatedAt INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_transfers_state ON transfers(state, updatedAt);
      CREATE INDEX IF NOT EXISTS idx_transfers_device_state ON transfers(deviceId, state);
      INSERT INTO transfers VALUES('r1','dev-m','read',10,NULL,NULL,'a.jpg',1000,500,1,NULL,NULL,'/tmp/a',NULL,'failed','timeout',\(now));
      INSERT INTO transfers VALUES('r2','dev-m','write',NULL,5,NULL,'b.bin',2000,0,0,NULL,NULL,'/tmp/b',NULL,'done',NULL,\(now));
      INSERT INTO transfers VALUES('r3','dev-m','read',20,NULL,NULL,'c.png',3000,1500,1,NULL,NULL,'/tmp/c',NULL,'active',NULL,\(now));
      """
    var errMsg: UnsafeMutablePointer<CChar>?
    sqlite3_exec(db, sql, nil, nil, &errMsg)
    if let errMsg { sqlite3_free(errMsg) }
    sqlite3_close(db)
    db = nil

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "dev-m")
    let resumables = try journal.loadResumables(for: device)

    // r1 (failed) + r3 (active→orphaned to failed) should be resumable; r2 (done) excluded
    XCTAssertEqual(resumables.count, 2)
    let ids = Set(resumables.map(\.id))
    XCTAssertTrue(ids.contains("r1"))
    XCTAssertTrue(ids.contains("r3"))
    // r1 should still be failed with original error
    let r1 = resumables.first(where: { $0.id == "r1" })
    XCTAssertEqual(r1?.state, "failed")
    XCTAssertEqual(r1?.committedBytes, 500)
    // r3 should now be failed (orphaned)
    let r3 = resumables.first(where: { $0.id == "r3" })
    XCTAssertEqual(r3?.state, "failed")
    XCTAssertEqual(r3?.committedBytes, 1500)
  }
}

// MARK: - Wave 41: Device Tuning Persistence

final class DeviceTuningPersistenceTests: XCTestCase {

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

  private func makeFingerprint(vid: UInt16 = 0x2717, pid: UInt16 = 0xff10) -> MTPDeviceFingerprint {
    MTPDeviceFingerprint.fromUSB(
      vid: vid, pid: pid,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02, epEvt: 0x83)
  }

  private func makeProfile(
    fingerprint: MTPDeviceFingerprint,
    chunkSize: Int? = 524_288,
    handshakeMs: Int? = 150,
    ioTimeout: Int? = 5000,
    inactivityTimeout: Int? = 30000,
    readTP: Double? = 12.5,
    writeTP: Double? = 8.3,
    successRate: Double = 0.95,
    sampleCount: Int = 10
  ) -> LearnedProfile {
    LearnedProfile(
      fingerprint: fingerprint,
      created: Date(timeIntervalSince1970: 1_700_000_000),
      lastUpdated: Date(),
      sampleCount: sampleCount,
      optimalChunkSize: chunkSize,
      avgHandshakeMs: handshakeMs,
      optimalIoTimeoutMs: ioTimeout,
      optimalInactivityTimeoutMs: inactivityTimeout,
      p95ReadThroughputMBps: readTP,
      p95WriteThroughputMBps: writeTP,
      successRate: successRate,
      hostEnvironment: "macOS-test")
  }

  func testPersistAndLoadTuningProfile() async throws {
    let actor = store.createActor()
    let fp = makeFingerprint()
    let deviceId = "tuning-persist-\(UUID().uuidString)"
    let profile = makeProfile(fingerprint: fp)

    try await actor.upsertDevice(id: deviceId, manufacturer: "Xiaomi", model: "Mi Note 2")
    try await actor.updateLearnedProfile(
      for: fp.hashString, deviceId: deviceId, profile: profile)

    let dto = try await actor.fetchLearnedProfileDTO(for: fp.hashString)
    XCTAssertNotNil(dto)
    XCTAssertEqual(dto?.sampleCount, 10)
    XCTAssertEqual(dto?.optimalChunkSize, 524_288)
    XCTAssertEqual(dto?.avgHandshakeMs, 150)
    XCTAssertEqual(dto?.optimalIoTimeoutMs, 5000)
    XCTAssertEqual(dto?.optimalInactivityTimeoutMs, 30000)
    XCTAssertEqual(dto?.p95ReadThroughputMBps, 12.5)
    XCTAssertEqual(dto?.p95WriteThroughputMBps, 8.3)
    XCTAssertEqual(dto?.successRate, 0.95)
    XCTAssertEqual(dto?.hostEnvironment, "macOS-test")
  }

  func testLoadMissingProfileReturnsNil() async throws {
    let actor = store.createActor()
    let dto = try await actor.fetchLearnedProfileDTO(for: "nonexistent-fingerprint-hash")
    XCTAssertNil(dto)
  }

  func testUpdateExistingProfile() async throws {
    let actor = store.createActor()
    let fp = makeFingerprint()
    let deviceId = "tuning-update-\(UUID().uuidString)"

    let initial = makeProfile(fingerprint: fp, chunkSize: 262_144, sampleCount: 5)
    try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    try await actor.updateLearnedProfile(for: fp.hashString, deviceId: deviceId, profile: initial)

    let updated = makeProfile(fingerprint: fp, chunkSize: 1_048_576, sampleCount: 15)
    try await actor.updateLearnedProfile(for: fp.hashString, deviceId: deviceId, profile: updated)

    let dto = try await actor.fetchLearnedProfileDTO(for: fp.hashString)
    XCTAssertEqual(dto?.optimalChunkSize, 1_048_576, "Update should overwrite chunk size")
    XCTAssertEqual(dto?.sampleCount, 15, "Update should overwrite sample count")
  }

  func testProfileWithAllNilOptionals() async throws {
    let actor = store.createActor()
    let fp = makeFingerprint(vid: 0x04e8, pid: 0x6860)
    let deviceId = "tuning-nil-\(UUID().uuidString)"

    let profile = makeProfile(
      fingerprint: fp,
      chunkSize: nil, handshakeMs: nil, ioTimeout: nil,
      inactivityTimeout: nil, readTP: nil, writeTP: nil)
    try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)
    try await actor.updateLearnedProfile(for: fp.hashString, deviceId: deviceId, profile: profile)

    let dto = try await actor.fetchLearnedProfileDTO(for: fp.hashString)
    XCTAssertNotNil(dto)
    XCTAssertNil(dto?.optimalChunkSize)
    XCTAssertNil(dto?.avgHandshakeMs)
    XCTAssertNil(dto?.optimalIoTimeoutMs)
    XCTAssertNil(dto?.optimalInactivityTimeoutMs)
    XCTAssertNil(dto?.p95ReadThroughputMBps)
    XCTAssertNil(dto?.p95WriteThroughputMBps)
  }

  func testAdaptiveTuningMerge() {
    let fp = makeFingerprint()
    let initial = makeProfile(
      fingerprint: fp, chunkSize: 262_144, handshakeMs: 200,
      readTP: 10.0, writeTP: 5.0, successRate: 1.0, sampleCount: 4)

    let sessionData = SessionData(
      actualChunkSize: 524_288,
      handshakeTimeMs: 100,
      readThroughputMBps: 15.0,
      writeThroughputMBps: 8.0,
      wasSuccessful: true)

    let merged = initial.merged(with: sessionData)
    XCTAssertEqual(merged.sampleCount, 5)
    XCTAssertEqual(
      merged.optimalChunkSize, 524_288, "Chunk size should be updated to session value")
    // Weighted average: (200 * 4/5) + (100 * 1/5) = 160 + 20 = 180
    XCTAssertEqual(merged.avgHandshakeMs, 180)
    // Read TP: (10.0 * 4/5) + (15.0 * 1/5) = 8.0 + 3.0 = 11.0
    XCTAssertEqual(merged.p95ReadThroughputMBps!, 11.0, accuracy: 0.01)
    // Write TP: (5.0 * 4/5) + (8.0 * 1/5) = 4.0 + 1.6 = 5.6
    XCTAssertEqual(merged.p95WriteThroughputMBps!, 5.6, accuracy: 0.01)
    // Success rate: (1.0 * 4/5) + (1.0 * 1/5) = 1.0
    XCTAssertEqual(merged.successRate, 1.0, accuracy: 0.01)
  }

  func testAdaptiveTuningMergeWithFailedSession() {
    let fp = makeFingerprint()
    let initial = makeProfile(
      fingerprint: fp, successRate: 1.0, sampleCount: 9)

    let failedSession = SessionData(wasSuccessful: false)
    let merged = initial.merged(with: failedSession)

    XCTAssertEqual(merged.sampleCount, 10)
    // Success rate: (1.0 * 9/10) + (0.0 * 1/10) = 0.9
    XCTAssertEqual(merged.successRate, 0.9, accuracy: 0.01)
  }

  func testTuningProfileSurvivesActorRecreation() async throws {
    let fp = makeFingerprint()
    let deviceId = "tuning-survive-\(UUID().uuidString)"
    let profile = makeProfile(fingerprint: fp)

    // Write with one actor
    let actor1 = store.createActor()
    try await actor1.upsertDevice(id: deviceId, manufacturer: "Test", model: "Device")
    try await actor1.updateLearnedProfile(for: fp.hashString, deviceId: deviceId, profile: profile)

    // Read with a fresh actor
    let actor2 = store.createActor()
    let dto = try await actor2.fetchLearnedProfileDTO(for: fp.hashString)
    XCTAssertNotNil(dto)
    XCTAssertEqual(dto?.optimalChunkSize, 524_288)
    XCTAssertEqual(dto?.sampleCount, 10)
  }

  func testMultipleDeviceTuningProfiles() async throws {
    let actor = store.createActor()

    let fp1 = makeFingerprint(vid: 0x2717, pid: 0xff10)
    let fp2 = makeFingerprint(vid: 0x04e8, pid: 0x6860)
    let dev1 = "multi-tuning-1-\(UUID().uuidString)"
    let dev2 = "multi-tuning-2-\(UUID().uuidString)"

    let profile1 = makeProfile(fingerprint: fp1, chunkSize: 262_144)
    let profile2 = makeProfile(fingerprint: fp2, chunkSize: 1_048_576)

    try await actor.upsertDevice(id: dev1, manufacturer: "Xiaomi", model: "Mi Note 2")
    try await actor.upsertDevice(id: dev2, manufacturer: "Samsung", model: "Galaxy S7")
    try await actor.updateLearnedProfile(for: fp1.hashString, deviceId: dev1, profile: profile1)
    try await actor.updateLearnedProfile(for: fp2.hashString, deviceId: dev2, profile: profile2)

    let dto1 = try await actor.fetchLearnedProfileDTO(for: fp1.hashString)
    let dto2 = try await actor.fetchLearnedProfileDTO(for: fp2.hashString)
    XCTAssertEqual(dto1?.optimalChunkSize, 262_144)
    XCTAssertEqual(dto2?.optimalChunkSize, 1_048_576)
  }
}

// MARK: - Wave 41: Object Catalog Tombstoning

final class ObjectCatalogTombstoneTests: XCTestCase {

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

  func testTombstoneOrphansFromOlderGeneration() async throws {
    let actor = store.createActor()
    let deviceId = "tomb-device-\(UUID().uuidString)"
    try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    // Insert objects in generation 1
    for i in 1...5 {
      try await actor.upsertObject(
        deviceId: deviceId, storageId: 1, handle: i, parentHandle: nil,
        name: "gen1-\(i).jpg", pathKey: "/gen1-\(i).jpg", size: Int64(i * 100),
        mtime: nil, format: 0x3801, generation: 1)
    }

    // Insert objects in generation 2 (only 3 of 5 remain)
    for i in 1...3 {
      try await actor.upsertObject(
        deviceId: deviceId, storageId: 1, handle: i + 10, parentHandle: nil,
        name: "gen2-\(i).jpg", pathKey: "/gen2-\(i).jpg", size: Int64(i * 200),
        mtime: nil, format: 0x3801, generation: 2)
    }

    // Tombstone generation 1
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 2)

    // Gen 1 objects should be tombstoned (not returned)
    let gen1Objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertTrue(gen1Objects.isEmpty, "Generation 1 objects should be tombstoned")

    // Gen 2 objects should remain
    let gen2Objects = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
    XCTAssertEqual(gen2Objects.count, 3)
  }

  func testTombstoneOnDeviceWithNoObjects() async throws {
    let actor = store.createActor()
    let deviceId = "tomb-empty-\(UUID().uuidString)"
    try await actor.upsertDevice(id: deviceId, manufacturer: nil, model: nil)

    // Should not throw on empty catalog
    try await actor.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 1)
    let objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertTrue(objects.isEmpty)
  }

  func testTombstoneDoesNotAffectOtherDevices() async throws {
    let actor = store.createActor()
    let dev1 = "tomb-iso-1-\(UUID().uuidString)"
    let dev2 = "tomb-iso-2-\(UUID().uuidString)"
    try await actor.upsertDevice(id: dev1, manufacturer: nil, model: nil)
    try await actor.upsertDevice(id: dev2, manufacturer: nil, model: nil)

    try await actor.upsertObject(
      deviceId: dev1, storageId: 1, handle: 1, parentHandle: nil,
      name: "dev1.jpg", pathKey: "/dev1.jpg", size: 100, mtime: nil,
      format: 0x3801, generation: 1)
    try await actor.upsertObject(
      deviceId: dev2, storageId: 1, handle: 1, parentHandle: nil,
      name: "dev2.jpg", pathKey: "/dev2.jpg", size: 200, mtime: nil,
      format: 0x3801, generation: 1)

    // Tombstone only dev1
    try await actor.markPreviousGenerationTombstoned(deviceId: dev1, currentGen: 2)

    let d1Objects = try await actor.fetchObjects(deviceId: dev1, generation: 1)
    let d2Objects = try await actor.fetchObjects(deviceId: dev2, generation: 1)
    XCTAssertTrue(d1Objects.isEmpty, "dev1 gen 1 should be tombstoned")
    XCTAssertEqual(d2Objects.count, 1, "dev2 gen 1 should be unaffected")
  }
}

// MARK: - Wave 41: Journal File Persistence

final class JournalFilePersistenceTests: XCTestCase {

  func testDataSurvivesCloseAndReopen() throws {
    let dbPath = NSTemporaryDirectory() + "persist-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    let device = MTPDeviceID(raw: "persist-device")

    // Session 1: create transfers and update progress
    do {
      let j = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try j.beginRead(
        device: device, handle: 42, name: "persist.jpg",
        size: 10_000, supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/persist"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try j.updateProgress(id: id, committed: 5000)
      try j.recordThroughput(id: id, throughputMBps: 15.5)
      try j.recordRemoteHandle(id: id, handle: 99)
      try j.addContentHash(id: id, hash: "sha256-abc123")
    }

    // Session 2: reopen and verify
    let j2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try j2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 1)
    let record = resumables[0]
    XCTAssertEqual(record.name, "persist.jpg")
    XCTAssertEqual(record.committedBytes, 5000)
    XCTAssertEqual(record.state, "failed")  // orphaned on reopen
    XCTAssertTrue(record.supportsPartial)
  }

  func testCompletedTransferPersists() throws {
    let dbPath = NSTemporaryDirectory() + "persist-done-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    let device = MTPDeviceID(raw: "persist-done-dev")
    do {
      let j = try SQLiteTransferJournal(dbPath: dbPath)
      let id = try j.beginRead(
        device: device, handle: 1, name: "done.jpg",
        size: 1000, supportsPartial: false,
        tempURL: URL(fileURLWithPath: "/tmp/persist-done"), finalURL: nil,
        etag: (size: nil, mtime: nil))
      try j.updateProgress(id: id, committed: 1000)
      try j.complete(id: id)
    }

    // Reopen — completed should NOT be resumable but should exist in DB
    let j2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try j2.loadResumables(for: device)
    XCTAssertTrue(resumables.isEmpty, "Completed transfers should not be resumable")
  }

  func testLargeJournalPersistsEfficiently() throws {
    let dbPath = NSTemporaryDirectory() + "persist-large-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    let device = MTPDeviceID(raw: "persist-large")
    let count = 200
    var ids: [String] = []

    do {
      let j = try SQLiteTransferJournal(dbPath: dbPath)
      for i in 0..<count {
        let id = try j.beginRead(
          device: device, handle: UInt32(i), name: "file-\(i).bin",
          size: UInt64(1000 * (i + 1)), supportsPartial: true,
          tempURL: URL(fileURLWithPath: "/tmp/large-\(i)"), finalURL: nil,
          etag: (size: nil, mtime: nil))
        try j.updateProgress(id: id, committed: UInt64(500 * (i + 1)))
        ids.append(id)
      }
    }

    let j2 = try SQLiteTransferJournal(dbPath: dbPath)
    let resumables = try j2.loadResumables(for: device)
    XCTAssertEqual(resumables.count, count)
  }

  func testMultipleJournalInstancesConcurrentReads() throws {
    // WAL allows concurrent readers on separate connections
    let dbPath = NSTemporaryDirectory() + "persist-multi-\(UUID().uuidString).sqlite"
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(atPath: dbPath + "-wal")
      try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    let writer = try SQLiteTransferJournal(dbPath: dbPath)
    let device = MTPDeviceID(raw: "multi-instance")

    // Write 10 entries sequentially
    for i in 0..<10 {
      _ = try writer.beginRead(
        device: device, handle: UInt32(i), name: "multi-\(i).bin",
        size: UInt64(1000 * (i + 1)), supportsPartial: true,
        tempURL: URL(fileURLWithPath: "/tmp/multi-\(i)"), finalURL: nil,
        etag: (size: nil, mtime: nil))
    }

    // Open a second reader connection and verify reads succeed
    let reader = try SQLiteTransferJournal(dbPath: dbPath)
    // The reader's init orphans active→failed; both states are resumable
    let resumables = try reader.loadResumables(for: device)
    XCTAssertEqual(resumables.count, 10, "All entries should be readable from second connection")
  }
}

// MARK: - Wave 41: Store Concurrent Access

final class StoreWave41ConcurrencyTests: XCTestCase {

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

  func testConcurrentTransferLifecycles() async throws {
    let actor = store.createActor()
    let deviceId = "conc-lifecycle-\(UUID().uuidString)"

    // Create 20 transfers concurrently
    try await withThrowingTaskGroup(of: String.self) { group in
      for i in 0..<20 {
        group.addTask {
          let id = "conc-\(i)-\(UUID().uuidString)"
          try await actor.createTransfer(
            id: id, deviceId: deviceId, kind: i % 2 == 0 ? "read" : "write",
            handle: UInt32(i), parentHandle: nil, name: "conc-\(i).bin",
            totalBytes: UInt64(1000 * (i + 1)), supportsPartial: true,
            localTempURL: "/tmp/conc-\(i)", finalURL: nil,
            etagSize: nil, etagMtime: nil)
          return id
        }
      }

      var ids: [String] = []
      for try await id in group {
        ids.append(id)
      }
      XCTAssertEqual(ids.count, 20)

      // Verify all created
      let resumables = try await actor.fetchResumableTransfers(for: deviceId)
      XCTAssertEqual(resumables.count, 20)
    }
  }

  func testConcurrentProfileAndTransferWrites() async throws {
    let deviceId = "conc-mix-\(UUID().uuidString)"
    let actor = store.createActor()
    try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Device")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Transfer writes
      for i in 0..<5 {
        group.addTask {
          try await actor.createTransfer(
            id: "mix-xfer-\(i)-\(UUID().uuidString)", deviceId: deviceId, kind: "read",
            handle: UInt32(i), parentHandle: nil, name: "mix-\(i).bin",
            totalBytes: 1000, supportsPartial: false,
            localTempURL: "/tmp/mix-\(i)", finalURL: nil,
            etagSize: nil, etagMtime: nil)
        }
      }

      // Snapshot writes
      for i in 0..<5 {
        group.addTask {
          try await actor.recordSnapshot(
            deviceId: deviceId, generation: i, path: "/snap/\(i)", hash: "hash-\(i)")
        }
      }

      try await group.waitForAll()
    }

    let transfers = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(transfers.count, 5)
  }
}
