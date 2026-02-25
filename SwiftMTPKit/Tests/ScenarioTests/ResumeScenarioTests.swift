// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPTransportLibUSB
@testable import SwiftMTPTestKit

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

  // MARK: - Fault-injection resume scenario tests

  /// After a pipe stall mid-download, the journal entry is resumable at the committed offset.
  func testInterruptedDownloadIsResumable() async throws {
    let deviceId = MTPDeviceID(raw: "device-fault-resume")
    let tempURL = tempDir.appendingPathComponent("partial.dat")
    let finalURL = tempDir.appendingPathComponent("final.dat")
    let totalSize: UInt64 = 10_000

    let transferId = try await journal.beginRead(
      device: deviceId,
      handle: 0xAAAA,
      name: "large.bin",
      size: totalSize,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: totalSize, mtime: Date())
    )

    // Simulate partial progress before interruption
    try await journal.updateProgress(id: transferId, committed: 3_000)

    // Simulate fault: mark as failed
    try await journal.fail(
      id: transferId, error: NSError(domain: "USB", code: -1, userInfo: nil))

    // The record should still be resumable with the partial offset
    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    let record = try XCTUnwrap(resumables.first)
    XCTAssertEqual(record.id, transferId)
    XCTAssertEqual(record.committedBytes, 3_000)
    XCTAssertEqual(record.state, "failed")
    XCTAssertEqual(record.handle, 0xAAAA)
  }

  /// FaultInjectingLink with a pipeStall fault throws; subsequent call succeeds (retry pattern).
  func testFaultInjectingLinkRetryAfterPipeStall() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .getStorageIDs)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call should fail with the scheduled pipe stall
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected pipe stall error")
    } catch {
      // Expected
    }

    // Second call should succeed (fault is consumed)
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty, "Second call should succeed after fault consumed")
  }

  /// FaultInjectingLink busy-for-N-retries fault fires N times.
  func testFaultInjectingLinkBusyMultipleTimes() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    // busy for 2 retries on executeCommand
    let schedule = FaultSchedule([.busyForRetries(2)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    var failCount = 0
    for _ in 0..<4 {
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
      } catch {
        failCount += 1
      }
    }
    XCTAssertEqual(failCount, 2, "Should fail exactly 2 times (busy)")
  }

  /// A completed transfer is not included in resumables.
  func testCompletedTransferNotResumable() async throws {
    let deviceId = MTPDeviceID(raw: "device-complete")
    let tempURL = tempDir.appendingPathComponent("done_temp.dat")
    let finalURL = tempDir.appendingPathComponent("done_final.dat")

    let id = try await journal.beginRead(
      device: deviceId, handle: 0xBBBB, name: "done.bin", size: 512,
      supportsPartial: false, tempURL: tempURL, finalURL: finalURL,
      etag: (size: 512, mtime: Date()))
    try await journal.complete(id: id)

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(resumables.isEmpty, "Completed transfers should not be resumable")
  }

  /// Multiple sequential interrupted transfers are all resumable independently.
  func testMultipleInterruptedTransfersAreAllResumable() async throws {
    let deviceId = MTPDeviceID(raw: "device-multi-interrupt")
    let count = 5

    var ids: [String] = []
    for i in 0..<count {
      let id = try await journal.beginRead(
        device: deviceId, handle: UInt32(i + 1), name: "f\(i).bin",
        size: UInt64(i * 100 + 100), supportsPartial: true,
        tempURL: tempDir.appendingPathComponent("mi\(i).dat"),
        finalURL: tempDir.appendingPathComponent("mf\(i).dat"),
        etag: (size: UInt64(i * 100 + 100), mtime: Date())
      )
      try await journal.updateProgress(id: id, committed: UInt64(i * 50))
      try await journal.fail(id: id, error: NSError(domain: "T", code: i, userInfo: nil))
      ids.append(id)
    }

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, count, "All \(count) interrupted transfers must be resumable")
    for (idx, record) in resumables.sorted(by: { $0.committedBytes < $1.committedBytes })
      .enumerated()
    {
      XCTAssertEqual(record.committedBytes, UInt64(idx * 50))
      XCTAssertEqual(record.state, "failed")
    }
  }
}
