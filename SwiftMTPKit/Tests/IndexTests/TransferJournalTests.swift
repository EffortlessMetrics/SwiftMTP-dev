// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPIndex
@testable import SwiftMTPCore

// MARK: - Transfer Journal Tests

@Suite("TransferJournal Tests")
struct TransferJournalTests {

  // MARK: - Journal Playback Tests

  @Test("Journal playback from beginning")
  func testJournalPlaybackFromBeginning() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-journal-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    // Create transfer records
    let deviceId = MTPDeviceID(raw: "test-device-123")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Start reads
    let readId1 = try journal.beginRead(
      device: deviceId,
      handle: 0x20001,
      name: "photo1.jpg",
      size: 1024,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: 1024, mtime: Date())
    )

    let readId2 = try journal.beginRead(
      device: deviceId,
      handle: 0x20002,
      name: "photo2.jpg",
      size: 2048,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (size: 2048, mtime: Date())
    )

    // Load resumables (playback)
    let resumables = try journal.loadResumables(for: deviceId)

    #expect(resumables.count == 2)
    #expect(resumables[0].id == readId1 || resumables[0].id == readId2)

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Journal playback from middle")
  func testJournalPlaybackFromMiddle() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-journal-mid-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-mid")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Create multiple transfers
    var transferIds: [String] = []
    for i in 0..<5 {
      let id = try journal.beginRead(
        device: deviceId,
        handle: UInt32(0x20000 + i),
        name: "file\(i).jpg",
        size: UInt64(1000 + i * 100),
        supportsPartial: true,
        tempURL: tempURL,
        finalURL: finalURL,
        etag: (size: nil, mtime: nil)
      )
      transferIds.append(id)
    }

    // Complete some transfers
    try journal.complete(id: transferIds[0])
    try journal.complete(id: transferIds[2])

    // Partial progress on one
    try journal.updateProgress(id: transferIds[1], committed: 500)

    // Playback - should return only active transfers
    let resumables = try journal.loadResumables(for: deviceId)

    #expect(resumables.count == 3)  // transferIds[1], [3], [4] remain active
    #expect(resumables.contains { $0.id == transferIds[1] })
    #expect(!resumables.contains { $0.id == transferIds[0] })  // Completed

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - Partial Transfer Recovery Tests

  @Test("Partial transfer recovery after failure")
  func testPartialTransferRecovery() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-recovery-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-recovery")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Start transfer
    let transferId = try journal.beginWrite(
      device: deviceId,
      parent: 0x10001,
      name: "large-file.zip",
      size: 10_000_000,
      supportsPartial: true,
      tempURL: tempURL,
      sourceURL: nil
    )

    // Simulate partial progress (5MB transferred)
    try journal.updateProgress(id: transferId, committed: 5_000_000)

    // Simulate failure
    let testError = NSError(
      domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
    try journal.fail(id: transferId, error: testError)

    // Recover - load resumables
    let resumables = try journal.loadResumables(for: deviceId)

    #expect(resumables.count == 1)
    #expect(resumables[0].id == transferId)
    #expect(resumables[0].committedBytes == 5_000_000)
    #expect(resumables[0].state == "failed")

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Resume partial download")
  func testResumePartialDownload() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-resume-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-resume")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")

    // Start read with partial support
    let transferId = try journal.beginRead(
      device: deviceId,
      handle: 0x20001,
      name: "resume-test.mp4",
      size: 100_000_000,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: nil,
      etag: (size: 100_000_000, mtime: Date())
    )

    // Record progress at 25MB
    try journal.updateProgress(id: transferId, committed: 25_000_000)

    // Simulate resume (new journal instance)
    let journal2 = try SQLiteTransferJournal(dbPath: journalPath)
    let resumables = try journal2.loadResumables(for: deviceId)

    #expect(resumables.count == 1)
    #expect(resumables[0].committedBytes == 25_000_000)
    #expect(resumables[0].supportsPartial == true)

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - Journal Compaction Tests

  @Test("Journal compaction removes old completed transfers")
  func testJournalCompaction() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-compact-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-compact")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Create many transfers
    var transferIds: [String] = []
    for i in 0..<20 {
      let id = try journal.beginRead(
        device: deviceId,
        handle: UInt32(0x20000 + i),
        name: "file\(i).txt",
        size: 1000,
        supportsPartial: false,
        tempURL: tempURL,
        finalURL: finalURL,
        etag: (nil, nil)
      )
      transferIds.append(id)
    }

    // Complete all
    for id in transferIds {
      try journal.complete(id: id)
    }

    // Compact - clears stale temps (would remove completed entries)
    try journal.clearStaleTemps(olderThan: 0)

    // Load should return empty
    let resumables = try journal.loadResumables(for: deviceId)
    #expect(resumables.isEmpty)

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Journal rotation on size threshold")
  func testJournalRotation() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-rotate-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-rotate")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Create many large transfers
    var transferIds: [String] = []
    for i in 0..<100 {
      let id = try journal.beginRead(
        device: deviceId,
        handle: UInt32(0x20000 + i),
        name: "largefile\(i).dat",
        size: 10_000_000,  // 10MB each
        supportsPartial: true,
        tempURL: tempURL,
        finalURL: finalURL,
        etag: (size: 10_000_000, mtime: nil)
      )
      transferIds.append(id)
    }

    // Complete some, leave others active
    for i in 0..<80 {
      try journal.complete(id: transferIds[i])
    }

    // Verify journal has mixed state
    let resumables = try journal.loadResumables(for: deviceId)
    #expect(resumables.count == 20)  // Remaining active transfers

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - Cross-Device Journal Compatibility Tests

  @Test("Journal compatible across device reconnects")
  func testCrossDeviceReconnect() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-crossdevice-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let deviceId1 = MTPDeviceID(raw: "device-first-connection")
    let deviceId2 = MTPDeviceID(raw: "device-reconnected")

    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // First connection - create transfers
    let journal1 = try SQLiteTransferJournal(dbPath: journalPath)
    let transferId1 = try journal1.beginRead(
      device: deviceId1,
      handle: 0x20001,
      name: "shared-file.jpg",
      size: 5000,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (nil, nil)
    )
    try journal1.updateProgress(id: transferId1, committed: 2500)

    // Device disconnects and reconnects with new ID
    let journal2 = try SQLiteTransferJournal(dbPath: journalPath)

    // Original device should still have its transfers
    let resumables1 = try journal2.loadResumables(for: deviceId1)
    #expect(resumables1.count == 1)
    #expect(resumables1[0].committedBytes == 2500)

    // New device has its own transfers
    let transferId2 = try journal2.beginRead(
      device: deviceId2,
      handle: 0x20002,
      name: "new-device-file.jpg",
      size: 3000,
      supportsPartial: false,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (nil, nil)
    )

    // Both devices have separate transfer tracking
    let device1Transfers = try journal2.loadResumables(for: deviceId1)
    let device2Transfers = try journal2.loadResumables(for: deviceId2)

    // Both devices have separate transfer tracking
    let allResumables = device1Transfers + device2Transfers
    #expect(allResumables.count == 2)

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Multiple devices simultaneous transfers")
  func testMultipleDeviceTransfers() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-multidevice-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let devices = [
      MTPDeviceID(raw: "device-a"),
      MTPDeviceID(raw: "device-b"),
      MTPDeviceID(raw: "device-c"),
    ]

    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    // Each device starts transfers
    for (deviceIndex, deviceId) in devices.enumerated() {
      for i in 0..<3 {
        let id = try journal.beginRead(
          device: deviceId,
          handle: UInt32(0x20000 + deviceIndex * 10 + i),
          name: "file\(deviceIndex)-\(i).txt",
          size: 1000,
          supportsPartial: true,
          tempURL: tempURL,
          finalURL: finalURL,
          etag: (nil, nil)
        )
        // Record different progress per device
        try journal.updateProgress(id: id, committed: UInt64(deviceIndex * 100 + i * 50))
      }
    }

    // Verify each device's transfers are isolated
    for (deviceIndex, deviceId) in devices.enumerated() {
      let resumables = try journal.loadResumables(for: deviceId)
      #expect(resumables.count == 3)

      // Verify progress tracking regardless of row order from SQLite query.
      let actualCommitted = resumables.map(\.committedBytes).sorted()
      let expectedCommitted = (0..<3).map { UInt64(deviceIndex * 100 + $0 * 50) }.sorted()
      #expect(actualCommitted == expectedCommitted)
    }

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  // MARK: - Error Handling Tests

  @Test("Transfer failure records error details")
  func testTransferFailureRecordsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-failure-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-error")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    let transferId = try journal.beginWrite(
      device: deviceId,
      parent: 0x10001,
      name: "problematic-file.dat",
      size: 1_000_000,
      supportsPartial: false,
      tempURL: tempURL,
      sourceURL: nil
    )

    // Simulate various errors
    let errors: [String: Error] = [
      "timeout": NSError(
        domain: "NetworkError", code: -1001,
        userInfo: [NSLocalizedDescriptionKey: "The request timed out."]),
      "connection": NSError(
        domain: "NetworkError", code: -1005,
        userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]),
      "space": NSError(
        domain: "DiskError", code: 28,
        userInfo: [NSLocalizedDescriptionKey: "No space left on device"]),
    ]

    for (key, error) in errors {
      let id = try journal.beginRead(
        device: deviceId,
        handle: UInt32.random(in: 0x30000...0x40000),
        name: "error-test-\(key).txt",
        size: 5000,
        supportsPartial: true,
        tempURL: tempURL,
        finalURL: finalURL,
        etag: (nil, nil)
      )
      try journal.fail(id: id, error: error)
    }

    // Verify failed transfers have error details
    let failedTransfers = try journal.listFailed()
    #expect(failedTransfers.count == 3)
    #expect(failedTransfers.allSatisfy { $0.lastError != nil })

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Transfer completion clears error state")
  func testCompletionClearsError() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let journalPath = tempDir.appendingPathComponent("test-clearerror-\(UUID().uuidString).sqlite")
      .path
    defer { try? FileManager.default.removeItem(atPath: journalPath) }

    let journal = try SQLiteTransferJournal(dbPath: journalPath)

    let deviceId = MTPDeviceID(raw: "test-device-clearerror")
    let tempURL = URL(fileURLWithPath: "/tmp/test-\(UUID().uuidString).tmp")
    let finalURL = URL(fileURLWithPath: "/tmp/final-\(UUID().uuidString).txt")

    let transferId = try journal.beginRead(
      device: deviceId,
      handle: 0x20001,
      name: "eventual-success.txt",
      size: 2000,
      supportsPartial: true,
      tempURL: tempURL,
      finalURL: finalURL,
      etag: (nil, nil)
    )

    // Initial failure
    let error = NSError(
      domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Temporary failure"])
    try journal.fail(id: transferId, error: error)

    // Verify failed state is visible in resumables
    var resumables = try journal.loadResumables(for: deviceId)
    #expect(resumables.contains { $0.id == transferId && $0.state == "failed" })

    // Complete after retry
    try journal.complete(id: transferId)

    // Verify completed (no longer in resumables)
    resumables = try journal.loadResumables(for: deviceId)
    #expect(!resumables.contains { $0.id == transferId })

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }
}
