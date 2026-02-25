// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPTransportLibUSB

final class ResumeScenarioTests: XCTestCase {
  var tempDir: URL!
  var dbPath: String!
  var indexManager: MTPIndexManager!
  var journal: TransferJournal!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftMTPTests")
    try? FileManager.default.removeItem(at: tempDir)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    dbPath = tempDir.appendingPathComponent("test_transfers.db").path
    indexManager = MTPIndexManager(dbPath: dbPath)
    journal = try indexManager.createTransferJournal()
  }

  override func tearDown() async throws {
    try? await journal.clearStaleTemps(olderThan: 0)
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testTransferJournalCRUD() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-123")
    let tempURL = tempDir.appendingPathComponent("temp.dat")
    let finalURL = tempDir.appendingPathComponent("final.dat")

    // Test beginRead
    let transferId = try await journal.beginRead(
      device: deviceId,
      handle: 0x1234,
      name: "test.txt",
      size: 1000,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: 1000, mtime: Date())
    )

    XCTAssertFalse(transferId.isEmpty)

    // Test updateProgress
    try await journal.updateProgress(id: transferId, committed: 500)

    // Test loadResumables
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].id, transferId)
    XCTAssertEqual(records[0].committedBytes, 500)
    XCTAssertEqual(records[0].state, "active")

    // Test complete
    try await journal.complete(id: transferId)

    // Verify completion
    let updatedRecords = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(updatedRecords.count, 0)  // Completed records shouldn't be resumable
  }

  func testTransferJournalWrite() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-456")
    let tempURL = tempDir.appendingPathComponent("upload_temp.dat")
    let sourceURL = tempDir.appendingPathComponent("source.dat")

    // Test beginWrite
    let transferId = try await journal.beginWrite(
      device: deviceId,
      parent: 0x0000,
      name: "upload.txt",
      size: 2000,
      supportsPartial: false,
      tempURL: tempURL,
      sourceURL: sourceURL
    )

    XCTAssertFalse(transferId.isEmpty)

    // Test updateProgress
    try await journal.updateProgress(id: transferId, committed: 1000)

    // Test loadResumables
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].id, transferId)
    XCTAssertEqual(records[0].committedBytes, 1000)
    XCTAssertEqual(records[0].state, "active")
    XCTAssertEqual(records[0].kind, "write")
  }

  func testTransferJournalFailure() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-789")
    let tempURL = tempDir.appendingPathComponent("fail_temp.dat")
    let finalURL = tempDir.appendingPathComponent("fail_final.dat")

    // Test beginRead
    let transferId = try await journal.beginRead(
      device: deviceId,
      handle: 0x5678,
      name: "fail.txt",
      size: 500,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: 500, mtime: Date())
    )

    // Test fail
    let testError = NSError(
      domain: "TestError", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
    try await journal.fail(id: transferId, error: testError)

    // Verify failure state
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(records.count, 1)  // Failed records remain resumable for retry
    XCTAssertEqual(records[0].state, "failed")
  }

  func testClearStaleTemps() async throws {
    let deviceId = MTPDeviceID(raw: "test-device-stale")
    let tempURL = tempDir.appendingPathComponent("stale_temp.dat")
    let finalURL = tempDir.appendingPathComponent("stale_final.dat")

    // Create temp file
    try "stale content".write(to: tempURL, atomically: true, encoding: .utf8)

    // Begin transfer
    let transferId = try await journal.beginRead(
      device: deviceId,
      handle: 0x9999,
      name: "stale.txt",
      size: 100,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: 100, mtime: Date())
    )

    // Mark as failed (to make it clearable)
    try await journal.fail(id: transferId, error: NSError(domain: "TestError", code: 1))

    // Verify temp file exists
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

    // Clear stale temps (with 0 age to clear everything)
    try await journal.clearStaleTemps(olderThan: 0)

    // Verify temp file is gone
    XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))

    // Verify no resumable records remain
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(records.count, 0)
  }

  func testMultipleDevices() async throws {
    let deviceId1 = MTPDeviceID(raw: "device-1")
    let deviceId2 = MTPDeviceID(raw: "device-2")

    // Create transfers for different devices
    let transferId1 = try await journal.beginRead(
      device: deviceId1,
      handle: 0x1111,
      name: "file1.txt",
      size: 100,
      supportsPartial: true,
      tempURL: tempDir.appendingPathComponent("temp1.dat"),
      finalURL: tempDir.appendingPathComponent("final1.dat"),
      etag: (size: 100, mtime: Date())
    )

    let transferId2 = try await journal.beginRead(
      device: deviceId2,
      handle: 0x2222,
      name: "file2.txt",
      size: 200,
      supportsPartial: true,
      tempURL: tempDir.appendingPathComponent("temp2.dat"),
      finalURL: tempDir.appendingPathComponent("final2.dat"),
      etag: (size: 200, mtime: Date())
    )

    // Verify each device sees only its own transfers
    let records1 = try await journal.loadResumables(for: deviceId1)
    XCTAssertEqual(records1.count, 1)
    XCTAssertEqual(records1[0].id, transferId1)

    let records2 = try await journal.loadResumables(for: deviceId2)
    XCTAssertEqual(records2.count, 1)
    XCTAssertEqual(records2[0].id, transferId2)
  }
}
