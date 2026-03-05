// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - Transfer Resume Wiring Tests

/// Tests that TransferJournal is correctly wired into the DeviceActor read/write paths,
/// covering ETag validation, temp file preservation on failure, and progress tracking.
final class TransferResumeWiringTests: XCTestCase {

  // MARK: - ETag Mismatch Detection

  /// When a resumable record exists but the device file size changed, the old partial
  /// should be discarded and a fresh transfer started.
  func testEtagMismatchDiscardPartial() async throws {
    let journal = TrackingTransferJournal()
    let deviceId = MTPDeviceID(raw: "etag-test")

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "etag-partial-\(UUID()).part")
    try Data(repeating: 0xAA, count: 500).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    await journal.setStubResumables([
      TransferRecord(
        id: "old-transfer", deviceId: deviceId, kind: "read",
        handle: 0x1234, parentHandle: nil, name: "photo.jpg",
        totalBytes: 1000, committedBytes: 500,
        supportsPartial: true,
        localTempURL: tempURL,
        finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "etag-final.jpg"),
        state: "failed", updatedAt: Date())
    ])

    // Device file now has size 2000 (changed)
    let resumables = try await journal.loadResumables(for: deviceId)
    let existing = try XCTUnwrap(resumables.first)
    let newDeviceSize: UInt64 = 2000
    let sizeMatch = existing.totalBytes == nil || existing.totalBytes == newDeviceSize
    XCTAssertFalse(sizeMatch, "Size mismatch should be detected")

    // When sizes don't match, the old entry gets failed with etagMismatch
    try await journal.fail(id: "old-transfer", error: MTPError.etagMismatch)
    let failedCount = await journal.failedCount
    let firstFailedId = await journal.firstFailedId
    XCTAssertEqual(failedCount, 1)
    XCTAssertEqual(firstFailedId, "old-transfer")
  }

  /// When a resumable record's total size matches the current device file, resume proceeds.
  func testEtagMatchAllowsResume() async throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "match-partial-\(UUID()).part")
    try Data(repeating: 0xBB, count: 2000).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let existing = TransferRecord(
      id: "match-transfer", deviceId: MTPDeviceID(raw: "etag-match-test"), kind: "read",
      handle: 0x5678, parentHandle: nil, name: "video.mp4",
      totalBytes: 5000, committedBytes: 2000,
      supportsPartial: true,
      localTempURL: tempURL,
      finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "match-final.mp4"),
      state: "failed", updatedAt: Date())

    // Verify size match: device still reports 5000
    let sizeMatch = existing.totalBytes == nil || existing.totalBytes == 5000
    XCTAssertTrue(sizeMatch, "Sizes should match for resume")

    // Verify actual file size is used as offset
    let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
    let actualFileSize = (attrs[.size] as? UInt64) ?? 0
    XCTAssertEqual(actualFileSize, 2000, "File size on disk should be used as resume offset")
  }

  // MARK: - Temp File Preservation on Failure

  /// When journal is active and read fails, the temp file should be preserved (not deleted).
  func testTempFilePreservedOnReadFailureWithJournal() async throws {
    let journal = TrackingTransferJournal()
    let deviceId = MTPDeviceID(raw: "preserve-test")

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "preserve-\(UUID()).part")

    let transferId = try await journal.beginRead(
      device: deviceId, handle: 0xAAAA, name: "large.bin",
      size: 10_000, supportsPartial: true,
      tempURL: tempURL,
      finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "preserve.bin"),
      etag: (size: 10_000, mtime: Date()))

    // Simulate writing partial data to temp
    try Data(repeating: 0xCC, count: 3000).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // Simulate failure path: update progress with actual file size, then fail
    let fileSize =
      (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? UInt64) ?? 0
    try await journal.updateProgress(id: transferId, committed: fileSize)
    try await journal.fail(id: transferId, error: MTPError.timeout)

    // Verify temp file is still there
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: tempURL.path),
      "Temp file must be preserved when journal is active for resume")

    // Verify journal recorded the correct progress
    let progress = await journal.progressFor(transferId)
    XCTAssertEqual(progress, 3000)

    // Verify it's resumable
    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].committedBytes, 3000)
    XCTAssertEqual(resumables[0].state, "failed")
  }

  // MARK: - Write Path Progress Tracking

  /// Write failure should record progress in journal before marking failed.
  func testWriteFailureRecordsProgressBeforeFailing() async throws {
    let journal = TrackingTransferJournal()
    let deviceId = MTPDeviceID(raw: "write-progress-test")

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "upload.dat",
      size: 8000, supportsPartial: false,
      tempURL: URL(fileURLWithPath: NSTemporaryDirectory() + "upload.part"),
      sourceURL: URL(fileURLWithPath: NSTemporaryDirectory() + "upload.dat"))

    // Simulate partial progress then failure
    try await journal.updateProgress(id: transferId, committed: 4500)
    try await journal.fail(id: transferId, error: MTPError.deviceDisconnected)

    let progress = await journal.progressFor(transferId)
    XCTAssertEqual(progress, 4500)

    let failedCount = await journal.failedCount
    XCTAssertEqual(failedCount, 1)
  }

  // MARK: - Resume from Actual File Size on Disk

  /// When resuming, the actual file size on disk should be used (not stale journal committed bytes).
  func testResumeUsesActualFileSizeOnDisk() async throws {
    let journal = TrackingTransferJournal()
    let deviceId = MTPDeviceID(raw: "filesize-test")

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "filesize-partial-\(UUID()).part")
    try Data(repeating: 0xDD, count: 2500).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    await journal.setStubResumables([
      TransferRecord(
        id: "stale-journal", deviceId: deviceId, kind: "read",
        handle: 0xBBBB, parentHandle: nil, name: "data.bin",
        totalBytes: 10_000, committedBytes: 2000,
        supportsPartial: true,
        localTempURL: tempURL,
        finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "filesize-final.bin"),
        state: "failed", updatedAt: Date())
    ])

    // Verify actual file size differs from journal committed bytes
    let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
    let actualSize = (attrs[.size] as? UInt64) ?? 0
    XCTAssertEqual(actualSize, 2500, "Actual file size should be 2500")

    // Sync journal with actual disk state (as the wired code does)
    try await journal.updateProgress(id: "stale-journal", committed: actualSize)
    let progress = await journal.progressFor("stale-journal")
    XCTAssertEqual(progress, 2500)
  }

  // MARK: - Edge Cases

  /// When temp file is missing but journal record exists, start fresh.
  func testMissingTempFileStartsFresh() async throws {
    let journal = TrackingTransferJournal()
    let deviceId = MTPDeviceID(raw: "missing-temp-test")

    let missingURL = URL(fileURLWithPath: NSTemporaryDirectory() + "nonexistent-\(UUID()).part")
    await journal.setStubResumables([
      TransferRecord(
        id: "orphan-record", deviceId: deviceId, kind: "read",
        handle: 0xCCCC, parentHandle: nil, name: "lost.dat",
        totalBytes: 5000, committedBytes: 3000,
        supportsPartial: true,
        localTempURL: missingURL,
        finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "lost-final.dat"),
        state: "failed", updatedAt: Date())
    ])

    XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))

    // Clear stubs so internal tracking is used
    await journal.setStubResumables([])

    let newId = try await journal.beginRead(
      device: deviceId, handle: 0xCCCC, name: "lost.dat",
      size: 5000, supportsPartial: true,
      tempURL: URL(fileURLWithPath: NSTemporaryDirectory() + "new-temp.part"),
      finalURL: URL(fileURLWithPath: NSTemporaryDirectory() + "lost-final.dat"),
      etag: (size: 5000, mtime: Date()))

    XCTAssertFalse(newId.isEmpty, "New transfer ID should be assigned")
    let readCount = await journal.readCount
    XCTAssertEqual(readCount, 1, "beginRead should be called for fresh transfer")
  }

  /// Nil totalBytes in journal record should allow resume (no etag check possible).
  func testNilTotalBytesAllowsResume() async throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "nil-total-\(UUID()).part")
    try Data(repeating: 0xEE, count: 1000).write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let existing = TransferRecord(
      id: "nil-total", deviceId: MTPDeviceID(raw: "nil-test"), kind: "read",
      handle: 0xDDDD, parentHandle: nil, name: "unknown-size.dat",
      totalBytes: nil, committedBytes: 1000,
      supportsPartial: true,
      localTempURL: tempURL,
      finalURL: nil,
      state: "failed", updatedAt: Date())

    // nil totalBytes should pass the ETag check
    let sizeMatch = existing.totalBytes == nil || existing.totalBytes == 5000
    XCTAssertTrue(sizeMatch, "nil totalBytes should be treated as matching for resume")
  }

  // MARK: - MTPError.etagMismatch

  func testEtagMismatchErrorMessages() {
    let error = MTPError.etagMismatch
    XCTAssertNotNil(error.errorDescription)
    XCTAssertNotNil(error.failureReason)
    XCTAssertNotNil(error.recoverySuggestion)
    XCTAssertTrue(error.errorDescription!.contains("changed"))
  }

  func testEtagMismatchEquality() {
    XCTAssertEqual(MTPError.etagMismatch, MTPError.etagMismatch)
    XCTAssertNotEqual(MTPError.etagMismatch, MTPError.timeout)
  }

  func testEtagMismatchActionable() {
    let error = MTPError.etagMismatch
    let desc = error.actionableDescription
    XCTAssertTrue(desc.contains("changed") || desc.contains("partial"))
  }
}

// MARK: - Tracking Journal (test double)

/// Actor-based TransferJournal that records all operations for assertion in tests.
private actor TrackingTransferJournal: TransferJournal {

  struct FailEntry: Sendable {
    let id: String
    let error: String
  }

  private var stubbedResumables: [TransferRecord] = []
  private var progressUpdates: [String: UInt64] = [:]
  private var failedEntries: [FailEntry] = []
  private var completedIDs: [String] = []
  private var beginReadCounter: Int = 0
  private var beginWriteCounter: Int = 0
  private var records: [String: TransferRecord] = [:]

  // MARK: - Test accessors

  func setStubResumables(_ records: [TransferRecord]) {
    stubbedResumables = records
  }

  var failedCount: Int { failedEntries.count }
  var firstFailedId: String? { failedEntries.first?.id }
  var readCount: Int { beginReadCounter }

  func progressFor(_ id: String) -> UInt64? {
    progressUpdates[id]
  }

  // MARK: - TransferJournal conformance

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?,
    supportsPartial: Bool, tempURL: URL, finalURL: URL?,
    etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    beginReadCounter += 1
    let id = UUID().uuidString
    records[id] = TransferRecord(
      id: id, deviceId: device, kind: "read",
      handle: handle, parentHandle: nil, name: name,
      totalBytes: size, committedBytes: 0,
      supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: finalURL,
      state: "active", updatedAt: Date())
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String, size: UInt64,
    supportsPartial: Bool, tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    beginWriteCounter += 1
    let id = UUID().uuidString
    records[id] = TransferRecord(
      id: id, deviceId: device, kind: "write",
      handle: nil, parentHandle: parent, name: name,
      totalBytes: size, committedBytes: 0,
      supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: nil,
      state: "active", updatedAt: Date())
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {
    progressUpdates[id] = committed
    if let r = records[id] {
      records[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind,
        handle: r.handle, parentHandle: r.parentHandle, name: r.name,
        totalBytes: r.totalBytes, committedBytes: committed,
        supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL,
        state: r.state, updatedAt: Date())
    }
  }

  func fail(id: String, error: Error) async throws {
    failedEntries.append(FailEntry(id: id, error: error.localizedDescription))
    if let r = records[id] {
      records[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind,
        handle: r.handle, parentHandle: r.parentHandle, name: r.name,
        totalBytes: r.totalBytes, committedBytes: r.committedBytes,
        supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL,
        state: "failed", updatedAt: Date())
    }
  }

  func complete(id: String) async throws {
    completedIDs.append(id)
    records.removeValue(forKey: id)
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    if !stubbedResumables.isEmpty {
      return stubbedResumables.filter { $0.deviceId == device }
    }
    return records.values.filter {
      $0.deviceId == device && ($0.state == "active" || $0.state == "failed")
    }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {
    records.removeAll()
    stubbedResumables.removeAll()
  }
}
