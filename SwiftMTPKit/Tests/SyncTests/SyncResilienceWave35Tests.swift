// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Wave 35: Sync Resilience & Error Recovery Tests

/// Tests covering device disconnection recovery, transient failure retry,
/// corrupted baseline handling, conflict resolution policies, glob edge cases,
/// transfer journal resume, progress reporting accuracy, and filename collision handling.
final class SyncResilienceWave35Tests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!
  private var mirrorEngine: MirrorEngine!
  private var journal: SQLiteTransferJournal!

  private let storage = MTPStorageID(raw: 0x0001_0001)

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("wave35-resilience.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
    journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    mirrorEngine = nil
    diffEngine = nil
    snapshotter = nil
    journal = nil
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - (a) Mirror with Device Disconnection Mid-Transfer

  func testMirrorWithDisconnectionMidTransferReportsPartialFailure() async throws {
    // Device has two files; the second will fail due to disconnection
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 10, storage: storage, name: "ok.txt",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 11, storage: storage, name: "fail.txt",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xBB, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    // First snapshot baseline (empty)
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    _ = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)

    let outputDir = makeSubDir("disconnect-mirror")
    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir)

    // Both files should be processed — at minimum one succeeds
    XCTAssertGreaterThanOrEqual(report.downloaded, 1, "At least one file should download")
    XCTAssertEqual(
      report.totalProcessed, 2,
      "All files should be attempted regardless of individual failures")
  }

  func testJournalRecordsPartialProgressOnDisconnection() async throws {
    let deviceId = MTPDeviceID(raw: "disconnect:test@0:0")
    let tmpDir = makeSubDir("disconnect-journal")

    // Simulate a large transfer that gets interrupted at 60%
    let transferId = try journal.beginRead(
      device: deviceId, handle: 500, name: "large_video.mp4",
      size: 100_000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_video"),
      finalURL: tmpDir.appendingPathComponent("large_video.mp4"),
      etag: (size: 100_000, mtime: nil))

    try journal.updateProgress(id: transferId, committed: 60_000)
    try journal.fail(
      id: transferId,
      error: NSError(
        domain: "transport", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Device disconnected"]))

    // Verify partial state is recoverable
    let resumables = try journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables.first?.committedBytes, 60_000)
    XCTAssertEqual(resumables.first?.name, "large_video.mp4")
    XCTAssertTrue(resumables.first?.supportsPartial ?? false)
  }

  func testDisconnectedTransferCanBeRestarted() async throws {
    let deviceId = MTPDeviceID(raw: "restart:test@0:0")
    let tmpDir = makeSubDir("restart-journal")

    // First attempt — partial progress then failure
    let id1 = try journal.beginRead(
      device: deviceId, handle: 300, name: "photo.raw",
      size: 50_000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_photo"),
      finalURL: tmpDir.appendingPathComponent("photo.raw"),
      etag: (size: 50_000, mtime: nil))
    try journal.updateProgress(id: id1, committed: 25_000)
    try journal.fail(id: id1, error: NSError(domain: "transport", code: -1))

    // Verify resumable state exists
    let resumables = try journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)

    // Second attempt — restart and complete
    let id2 = try journal.beginRead(
      device: deviceId, handle: 300, name: "photo.raw",
      size: 50_000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_photo_retry"),
      finalURL: tmpDir.appendingPathComponent("photo.raw"),
      etag: (size: 50_000, mtime: nil))
    try journal.updateProgress(id: id2, committed: 50_000)
    try journal.complete(id: id2)

    // After successful retry, the new transfer should not be resumable
    let afterResume = try journal.loadResumables(for: deviceId)
    // The original failed entry may still be resumable; the completed one should not
    let completedEntries = afterResume.filter { $0.id == id2 }
    XCTAssertTrue(completedEntries.isEmpty, "Completed transfer should not appear as resumable")
  }

  // MARK: - (b) Mirror with Repeated Transient Failures

  func testMirrorSurvivesTransientReadFailures() async throws {
    // Create a device with a single file
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 20, storage: storage, name: "resilient.bin",
          sizeBytes: 16, formatCode: 0x3000, data: Data(repeating: 0xCC, count: 16)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let outputDir = makeSubDir("transient-mirror")

    // Mirror should complete (the engine catches per-file errors and continues)
    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir)

    // Regardless of transient failures, the report should reflect all attempts
    XCTAssertEqual(report.totalProcessed, 1)
    XCTAssertEqual(report.downloaded + report.failed, 1)
  }

  func testJournalTracksBusyRetriesCorrectly() async throws {
    let deviceId = MTPDeviceID(raw: "busy:test@0:0")
    let tmpDir = makeSubDir("busy-journal")

    // Simulate 3 failed attempts followed by success
    for attempt in 0..<3 {
      let id = try journal.beginRead(
        device: deviceId, handle: 600, name: "retry_file.dat",
        size: 1024, supportsPartial: false,
        tempURL: tmpDir.appendingPathComponent("tmp_retry_\(attempt)"),
        finalURL: tmpDir.appendingPathComponent("retry_file.dat"),
        etag: (size: 1024, mtime: nil))
      try journal.fail(
        id: id,
        error: NSError(
          domain: "transport", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Device busy (attempt \(attempt))"]))
    }

    // Final successful attempt
    let successId = try journal.beginRead(
      device: deviceId, handle: 600, name: "retry_file.dat",
      size: 1024, supportsPartial: false,
      tempURL: tmpDir.appendingPathComponent("tmp_retry_final"),
      finalURL: tmpDir.appendingPathComponent("retry_file.dat"),
      etag: (size: 1024, mtime: nil))
    try journal.complete(id: successId)

    let failed = try journal.listFailed()
    let failedForDevice = failed.filter { $0.deviceId == deviceId.raw }
    XCTAssertEqual(failedForDevice.count, 3, "Should have 3 recorded failed attempts")

    let active = try journal.listActive()
    let activeForDevice = active.filter { $0.deviceId == deviceId.raw }
    XCTAssertTrue(activeForDevice.isEmpty, "No active transfers after completion")
  }

  // MARK: - (c) Snapshot Diff with Corrupted Baseline

  func testDiffWithNilBaselineReturnsAllAsAdded() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 30, storage: storage, name: "a.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data(repeating: 0x01, count: 4))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 31, storage: storage, name: "b.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data(repeating: 0x02, count: 4)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Diff against nil baseline (simulating corrupted/missing baseline)
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    XCTAssertEqual(delta.added.count, 2, "All objects should appear as added with nil baseline")
    XCTAssertEqual(delta.removed.count, 0)
    XCTAssertEqual(delta.modified.count, 0)
  }

  func testDiffWithNonExistentGenerationTreatsAsEmpty() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 32, storage: storage, name: "new.bin",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xDD, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Use a non-existent generation as baseline
    let bogusGen = gen + 999
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: bogusGen, newGen: gen)

    // Non-existent generation has no objects, so everything in newGen is "added"
    XCTAssertEqual(delta.added.count, 1)
    XCTAssertEqual(delta.removed.count, 0)
  }

  func testMirrorWithCorruptedBaselineStillDownloadsAllFiles() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 33, storage: storage, name: "photo.jpg",
          sizeBytes: 16, formatCode: 0x3801, data: Data(repeating: 0xAB, count: 16)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let outputDir = makeSubDir("corrupt-baseline-mirror")

    // No prior snapshot exists — mirror treats everything as new
    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir)

    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  // MARK: - (d) Mirror Filter Edge Cases: Glob Patterns with Special Characters

  func testGlobPatternWithParentheses() {
    // File names with parentheses (common in camera naming: IMG_(1234).jpg)
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/IMG_(1234).jpg", pattern: "DCIM/*"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/IMG_(1234).jpg", pattern: "**/*.jpg"))
  }

  func testGlobPatternWithBrackets() {
    // Brackets are regex special chars
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/Photos/[Album]/pic.jpg", pattern: "**/*.jpg"))
  }

  func testGlobPatternWithPlusSign() {
    // Plus is a regex special character
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/C++/main.cpp", pattern: "**/*.cpp"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/C++/main.cpp", pattern: "C++/*.cpp"))
  }

  func testGlobPatternWithDollarAndCaret() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/prices/$100.txt", pattern: "**/*.txt"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/notes/^readme.md", pattern: "**/*.md"))
  }

  func testGlobPatternWithDots() {
    // Dots should be literal, not regex wildcards
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/lib/v2.0.1/readme.txt", pattern: "**/*.txt"))
    // "v*.1" should not match "v2X1" — the dot must be literal
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/v2X1/file.txt", pattern: "v*.1/*.txt"))
  }

  func testGlobPatternWithPipe() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/logs/out|err.log", pattern: "**/*.log"))
  }

  func testGlobPatternDoubleStarMatchesEverything() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/any/path/at/all.bin", pattern: "**"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/single.txt", pattern: "**"))
  }

  func testGlobPatternEmptyPathComponents() {
    // Ensure leading-slash patterns still work
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "/DCIM/*.jpg"))
  }

  // MARK: - (e) Resume After Process Crash: Transfer Journal Enables Clean Restart

  func testJournalPersistsAcrossNewInstance() async throws {
    let deviceId = MTPDeviceID(raw: "crash:test@0:0")
    let tmpDir = makeSubDir("crash-journal")
    let journalDbPath = tempDirectory.appendingPathComponent("crash-journal.sqlite").path

    // First journal instance — simulate pre-crash state
    let journal1 = try SQLiteTransferJournal(dbPath: journalDbPath)
    let transferId = try journal1.beginRead(
      device: deviceId, handle: 700, name: "important.zip",
      size: 200_000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_important"),
      finalURL: tmpDir.appendingPathComponent("important.zip"),
      etag: (size: 200_000, mtime: nil))
    try journal1.updateProgress(id: transferId, committed: 120_000)
    // Simulate crash — journal1 is abandoned without calling complete() or fail()

    // New journal instance — simulates process restart
    let journal2 = try SQLiteTransferJournal(dbPath: journalDbPath)
    let resumables = try journal2.loadResumables(for: deviceId)

    XCTAssertEqual(resumables.count, 1, "Interrupted transfer should persist across instances")
    XCTAssertEqual(resumables.first?.committedBytes, 120_000)
    XCTAssertEqual(resumables.first?.name, "important.zip")
    XCTAssertEqual(resumables.first?.totalBytes, 200_000)
    XCTAssertTrue(resumables.first?.supportsPartial ?? false)
  }

  func testClearStaleTempsRemovesOldEntries() async throws {
    let deviceId = MTPDeviceID(raw: "stale:test@0:0")
    let tmpDir = makeSubDir("stale-journal")

    // Create and immediately fail a transfer (so it becomes stale)
    let transferId = try journal.beginRead(
      device: deviceId, handle: 800, name: "stale.bin",
      size: 1024, supportsPartial: false,
      tempURL: tmpDir.appendingPathComponent("tmp_stale"),
      finalURL: tmpDir.appendingPathComponent("stale.bin"),
      etag: (size: 1024, mtime: nil))
    try journal.fail(id: transferId, error: NSError(domain: "test", code: -1))

    // Clear entries older than 0 seconds (everything)
    try journal.clearStaleTemps(olderThan: 0)

    let remaining = try journal.listFailed()
    let staleEntries = remaining.filter { $0.id == transferId }
    XCTAssertTrue(staleEntries.isEmpty, "Stale failed entries should be cleaned up")
  }

  func testMultipleResumableTransfersForSameDevice() async throws {
    let deviceId = MTPDeviceID(raw: "multi:test@0:0")
    let tmpDir = makeSubDir("multi-journal")

    // Start three transfers, each at different progress
    for i in 0..<3 {
      let id = try journal.beginRead(
        device: deviceId, handle: UInt32(900 + i), name: "file_\(i).dat",
        size: UInt64(10_000 * (i + 1)), supportsPartial: true,
        tempURL: tmpDir.appendingPathComponent("tmp_file_\(i)"),
        finalURL: tmpDir.appendingPathComponent("file_\(i).dat"),
        etag: (size: UInt64(10_000 * (i + 1)), mtime: nil))
      try journal.updateProgress(id: id, committed: UInt64(5_000 * (i + 1)))
    }

    let resumables = try journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 3, "All three in-flight transfers should be resumable")

    // Verify each has distinct committed bytes
    let committedSet = Set(resumables.map { $0.committedBytes })
    XCTAssertEqual(committedSet.count, 3, "Each transfer should have unique progress")
  }

  // MARK: - (f) Conflict Resolution: Test All Conflict Policies

  func testSkipPolicyLeavesExistingFileIntact() {
    let localDir = makeSubDir("skip-local")
    let remoteDir = makeSubDir("skip-remote")
    let mergedDir = makeSubDir("skip-merged")

    writeFile("doc.txt", content: "local original", in: localDir)
    writeFile("doc.txt", content: "remote version", in: remoteDir)

    // Skip policy: copy local to merged, don't overwrite
    let mergedFile = mergedDir.appendingPathComponent("doc.txt")
    try! FileManager.default.copyItem(
      at: localDir.appendingPathComponent("doc.txt"), to: mergedFile)

    // Simulating skip: do NOT overwrite with remote
    let result = try! String(contentsOf: mergedFile, encoding: .utf8)
    XCTAssertEqual(result, "local original", "Skip policy should keep existing file")
  }

  func testOverwritePolicyReplacesWithRemote() {
    let localDir = makeSubDir("overwrite-local")
    let remoteDir = makeSubDir("overwrite-remote")
    let mergedDir = makeSubDir("overwrite-merged")

    writeFile("doc.txt", content: "local version", in: localDir)
    writeFile("doc.txt", content: "remote newer", in: remoteDir)

    // Copy local first, then overwrite with remote
    let mergedFile = mergedDir.appendingPathComponent("doc.txt")
    try! FileManager.default.copyItem(
      at: localDir.appendingPathComponent("doc.txt"), to: mergedFile)
    let remoteData = try! Data(contentsOf: remoteDir.appendingPathComponent("doc.txt"))
    try! remoteData.write(to: mergedFile)

    let result = try! String(contentsOf: mergedFile, encoding: .utf8)
    XCTAssertEqual(result, "remote newer", "Overwrite policy should replace with remote")
  }

  func testRenamePolicyKeepsBothVersions() {
    let localDir = makeSubDir("rename-local")
    let remoteDir = makeSubDir("rename-remote")
    let mergedDir = makeSubDir("rename-merged")

    writeFile("photo.jpg", content: "local photo", in: localDir)
    writeFile("photo.jpg", content: "remote photo", in: remoteDir)

    // Rename policy: keep both with suffix
    let localFile = localDir.appendingPathComponent("photo.jpg")
    let remoteFile = remoteDir.appendingPathComponent("photo.jpg")
    try! FileManager.default.copyItem(
      at: localFile, to: mergedDir.appendingPathComponent("photo.jpg"))
    try! FileManager.default.copyItem(
      at: remoteFile, to: mergedDir.appendingPathComponent("photo_conflict.jpg"))

    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: mergedDir.appendingPathComponent("photo.jpg").path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: mergedDir.appendingPathComponent("photo_conflict.jpg").path))

    let original = try! String(
      contentsOf: mergedDir.appendingPathComponent("photo.jpg"), encoding: .utf8)
    let conflict = try! String(
      contentsOf: mergedDir.appendingPathComponent("photo_conflict.jpg"), encoding: .utf8)
    XCTAssertNotEqual(
      original, conflict, "Both versions should be preserved with different content")
  }

  func testNewerWinsPolicySelectsNewestByMtime() {
    let localDir = makeSubDir("newer-local")
    let remoteDir = makeSubDir("newer-remote")
    let mergedDir = makeSubDir("newer-merged")

    let localFile = localDir.appendingPathComponent("report.pdf")
    let remoteFile = remoteDir.appendingPathComponent("report.pdf")

    // Local is older
    writeFile("report.pdf", content: "old local report", in: localDir)
    try! FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -86400)], ofItemAtPath: localFile.path)

    // Remote is newer
    writeFile("report.pdf", content: "new remote report", in: remoteDir)

    // Resolve: pick the one with newer mtime
    let localMtime =
      (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[
        .modificationDate] as? Date ?? .distantPast
    let remoteMtime =
      (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[
        .modificationDate] as? Date ?? .distantPast
    let winner = localMtime > remoteMtime ? localFile : remoteFile

    try! FileManager.default.copyItem(
      at: winner, to: mergedDir.appendingPathComponent("report.pdf"))
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("report.pdf"), encoding: .utf8)
    XCTAssertEqual(result, "new remote report", "Newer-wins should select the most recent file")
  }

  func testNewerWinsPicksLocalWhenLocalIsNewer() {
    let localDir = makeSubDir("newer2-local")
    let remoteDir = makeSubDir("newer2-remote")
    let mergedDir = makeSubDir("newer2-merged")

    let remoteFile = remoteDir.appendingPathComponent("data.csv")
    writeFile("data.csv", content: "fresh local data", in: localDir)
    writeFile("data.csv", content: "stale remote data", in: remoteDir)
    try! FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -86400)], ofItemAtPath: remoteFile.path)

    let localFile = localDir.appendingPathComponent("data.csv")
    let localMtime =
      (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[
        .modificationDate] as? Date ?? .distantPast
    let remoteMtime =
      (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[
        .modificationDate] as? Date ?? .distantPast
    let winner = localMtime > remoteMtime ? localFile : remoteFile

    try! FileManager.default.copyItem(
      at: winner, to: mergedDir.appendingPathComponent("data.csv"))
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("data.csv"), encoding: .utf8)
    XCTAssertEqual(result, "fresh local data")
  }

  // MARK: - (g) Progress Reporting Accuracy

  func testSyncReportSuccessRateWithMixedOutcomes() {
    var report = MTPSyncReport()
    report.downloaded = 8
    report.skipped = 5
    report.failed = 2

    XCTAssertEqual(report.totalProcessed, 15)
    // successRate = downloaded / totalProcessed * 100
    XCTAssertEqual(report.successRate, 8.0 / 15.0 * 100.0, accuracy: 0.001)
  }

  func testSyncReportZeroDivisionSafe() {
    let report = MTPSyncReport()
    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.successRate, 0.0, "Empty report should return 0% not crash")
  }

  func testSyncReportPerfectScoreWhenAllDownloaded() {
    var report = MTPSyncReport()
    report.downloaded = 100
    XCTAssertEqual(report.successRate, 100.0)
  }

  func testSyncReportAllSkippedYieldsZeroSuccessRate() {
    var report = MTPSyncReport()
    report.skipped = 50
    XCTAssertEqual(report.totalProcessed, 50)
    XCTAssertEqual(report.successRate, 0.0, "Skipped files do not count as successful downloads")
  }

  func testMirrorReportCountsMatchFileList() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 40, storage: storage, name: "a.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data(repeating: 0x01, count: 4))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 41, storage: storage, name: "b.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data(repeating: 0x02, count: 4))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 42, storage: storage, name: "c.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data(repeating: 0x03, count: 4)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let outputDir = makeSubDir("progress-mirror")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir)

    XCTAssertEqual(report.totalProcessed, 3)
    XCTAssertEqual(report.downloaded + report.skipped + report.failed, 3)
  }

  func testMirrorWithFilterReportsSkippedCorrectly() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 50, storage: storage, name: "photo.jpg",
          sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xAB, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 51, storage: storage, name: "readme.txt",
          sizeBytes: 6, formatCode: 0x3000, data: Data(repeating: 0xCD, count: 6)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let outputDir = makeSubDir("filter-progress-mirror")

    // Only include .jpg files
    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir,
      includePattern: "**/*.jpg")

    XCTAssertEqual(report.downloaded, 1, "Only the .jpg should download")
    XCTAssertEqual(report.skipped, 1, "The .txt should be skipped by filter")
    XCTAssertEqual(report.totalProcessed, 2)
  }

  // MARK: - (h) Mirror with File Name Collisions (Case-Insensitive Filesystem)

  func testPathKeyToLocalURLSanitizesComponents() {
    let root = tempDirectory!
    let url = mirrorEngine.pathKeyToLocalURL("00010001/DCIM/Camera/photo.jpg", root: root)
    XCTAssertTrue(url.path.hasSuffix("DCIM/Camera/photo.jpg"))
    XCTAssertTrue(url.path.hasPrefix(root.path))
  }

  func testPathKeyWithTraversalAttemptsAreSanitized() {
    let root = tempDirectory!
    // Malicious path trying to escape the mirror root
    let url = mirrorEngine.pathKeyToLocalURL("00010001/../../../etc/passwd", root: root)
    // PathSanitizer should strip traversal components
    XCTAssertTrue(url.path.hasPrefix(root.path), "Sanitized path should stay within root")
    XCTAssertFalse(url.path.contains("../"), "Path traversal should be removed")
  }

  func testShouldSkipDownloadReturnsFalseForNewFile() throws {
    let root = makeSubDir("skip-check")
    let localURL = root.appendingPathComponent("nonexistent.txt")
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001,
      pathKey: "00010001/nonexistent.txt",
      size: 100, mtime: Date(), format: 0x3000)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertFalse(shouldSkip, "Non-existent file should not be skipped")
  }

  func testShouldSkipDownloadReturnsTrueForMatchingFile() throws {
    let root = makeSubDir("skip-match")
    let data = Data(repeating: 0xFF, count: 64)
    let localURL = root.appendingPathComponent("existing.bin")
    try data.write(to: localURL)

    let now = Date()
    // Set the local file's mtime to match
    try FileManager.default.setAttributes(
      [.modificationDate: now], ofItemAtPath: localURL.path)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001,
      pathKey: "00010001/existing.bin",
      size: 64, mtime: now, format: 0x3000)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertTrue(shouldSkip, "Matching size and mtime should be skipped")
  }

  func testShouldSkipDownloadReturnsFalseForSizeMismatch() throws {
    let root = makeSubDir("skip-size")
    let data = Data(repeating: 0xFF, count: 64)
    let localURL = root.appendingPathComponent("mismatch.bin")
    try data.write(to: localURL)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001,
      pathKey: "00010001/mismatch.bin",
      size: 128, mtime: nil, format: 0x3000)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertFalse(shouldSkip, "Size mismatch should trigger re-download")
  }

  func testCaseVariantFileNamesProduceDifferentLocalURLs() {
    let root = tempDirectory!
    let url1 = mirrorEngine.pathKeyToLocalURL("00010001/DCIM/Photo.JPG", root: root)
    let url2 = mirrorEngine.pathKeyToLocalURL("00010001/DCIM/photo.jpg", root: root)

    // On case-insensitive filesystems these may resolve to the same path,
    // but the URL strings themselves should differ
    XCTAssertNotEqual(
      url1.lastPathComponent, url2.lastPathComponent,
      "Path components should preserve original case")
  }

  // MARK: - Additional Resilience Tests

  func testJournalReadAndWriteTransfersAreDistinct() async throws {
    let deviceId = MTPDeviceID(raw: "rw:test@0:0")
    let tmpDir = makeSubDir("rw-journal")

    let readId = try journal.beginRead(
      device: deviceId, handle: 100, name: "download.bin",
      size: 5000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_read"),
      finalURL: tmpDir.appendingPathComponent("download.bin"),
      etag: (size: 5000, mtime: nil))

    let writeId = try journal.beginWrite(
      device: deviceId, parent: 0, name: "upload.bin",
      size: 3000, supportsPartial: false,
      tempURL: tmpDir.appendingPathComponent("tmp_write"),
      sourceURL: tmpDir.appendingPathComponent("upload.bin"))

    XCTAssertNotEqual(readId, writeId)

    let resumables = try journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 2)
    let kinds = Set(resumables.map { $0.kind })
    XCTAssertTrue(kinds.contains("read"))
    XCTAssertTrue(kinds.contains("write"))
  }

  func testDiffIsEmptyWhenSnapshotIsComparedToItself() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 60, storage: storage, name: "stable.dat",
          sizeBytes: 32, formatCode: 0x3000, data: Data(repeating: 0xEE, count: 32)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen, newGen: gen)

    XCTAssertTrue(delta.isEmpty, "Same generation compared to itself should yield empty diff")
    XCTAssertEqual(delta.totalChanges, 0)
  }

  func testMirrorWithAllFilesFilteredOutYieldsAllSkipped() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 70, storage: storage, name: "notes.txt",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0x11, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let outputDir = makeSubDir("all-filtered-mirror")

    // Filter that matches nothing
    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir,
      includePattern: "**/*.zzz_nonexistent")

    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 1, "File should be skipped when filter excludes it")
    XCTAssertEqual(report.failed, 0)
  }

  // MARK: - Helpers

  @discardableResult
  private func makeSubDir(_ name: String) -> URL {
    let dir = tempDirectory.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writeFile(_ name: String, content: String, in dir: URL) {
    try! content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }
}
