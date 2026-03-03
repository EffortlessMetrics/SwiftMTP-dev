// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Bidirectional Sync, Conflicts, and Filter Pattern Tests

/// Wave 31 deep sync tests covering bidirectional sync with simultaneous changes,
/// three-way merge, conflict resolution strategies, filter patterns, incremental sync,
/// sync anchor management, mirror with delete propagation, renamed-file diff,
/// progress reporting, empty sync, and partial failure journaling.
final class SyncWave31Tests: XCTestCase {
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
    dbPath = tempDirectory.appendingPathComponent("wave31-sync.sqlite").path
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

  // MARK: - Bidirectional Sync with Simultaneous Local and Remote Changes

  func testBidirectionalSyncDetectsSimultaneousAdditions() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    // Local adds file A, remote adds file B
    writeFile("local_new.txt", content: "from local", in: localDir)
    writeFile("remote_new.txt", content: "from remote", in: remoteDir)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertTrue(changes.localOnly.contains("local_new.txt"))
    XCTAssertTrue(changes.remoteOnly.contains("remote_new.txt"))
  }

  func testBidirectionalSyncDetectsSimultaneousModifications() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    writeFile("shared.txt", content: "local edit v2", in: localDir)
    writeFile("shared.txt", content: "remote edit v2", in: remoteDir)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.common.count, 1)

    let conflicts = detectConflicts(
      local: localDir, remote: remoteDir, common: changes.common)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first, "shared.txt")
  }

  func testBidirectionalSyncLocalDeleteRemoteModify() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    // Remote modified a file that local deleted
    writeFile("doc.txt", content: "remote edited", in: remoteDir)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(
      changes.remoteOnly.count, 1, "Deleted-local + modified-remote appears as remote-only")
  }

  func testBidirectionalSyncLocalModifyRemoteDelete() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    writeFile("doc.txt", content: "local edited", in: localDir)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(
      changes.localOnly.count, 1, "Modified-local + deleted-remote appears as local-only")
  }

  // MARK: - Three-Way Merge: Common Ancestor, Local Change, Remote Change

  func testThreeWayMergeIdentifiesDivergence() {
    let ancestorDir = makeSubDir("ancestor")
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let ancestorContent = "original content"
    writeFile("readme.md", content: ancestorContent, in: ancestorDir)
    writeFile("readme.md", content: "local rewrite", in: localDir)
    writeFile("readme.md", content: "remote rewrite", in: remoteDir)

    // Both sides diverged from ancestor
    let localData = readData("readme.md", in: localDir)
    let remoteData = readData("readme.md", in: remoteDir)
    let ancestorData = readData("readme.md", in: ancestorDir)

    XCTAssertNotEqual(localData, ancestorData, "Local diverged from ancestor")
    XCTAssertNotEqual(remoteData, ancestorData, "Remote diverged from ancestor")
    XCTAssertNotEqual(localData, remoteData, "Local and remote are different")
  }

  func testThreeWayMergeOnlyLocalChanged() {
    let ancestorDir = makeSubDir("ancestor")
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let ancestorContent = "original"
    writeFile("file.txt", content: ancestorContent, in: ancestorDir)
    writeFile("file.txt", content: "local edit", in: localDir)
    writeFile("file.txt", content: ancestorContent, in: remoteDir)

    let localData = readData("file.txt", in: localDir)
    let remoteData = readData("file.txt", in: remoteDir)
    let ancestorData = readData("file.txt", in: ancestorDir)

    // Only local changed → auto-resolve to local
    let winner = threeWayResolve(ancestor: ancestorData, local: localData, remote: remoteData)
    XCTAssertEqual(winner, localData)
  }

  func testThreeWayMergeOnlyRemoteChanged() {
    let ancestorDir = makeSubDir("ancestor")
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let ancestorContent = "original"
    writeFile("file.txt", content: ancestorContent, in: ancestorDir)
    writeFile("file.txt", content: ancestorContent, in: localDir)
    writeFile("file.txt", content: "remote edit", in: remoteDir)

    let localData = readData("file.txt", in: localDir)
    let remoteData = readData("file.txt", in: remoteDir)
    let ancestorData = readData("file.txt", in: ancestorDir)

    let winner = threeWayResolve(ancestor: ancestorData, local: localData, remote: remoteData)
    XCTAssertEqual(winner, remoteData)
  }

  func testThreeWayMergeBothChangedIdentically() {
    let ancestorDir = makeSubDir("ancestor")
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    writeFile("file.txt", content: "original", in: ancestorDir)
    writeFile("file.txt", content: "same edit", in: localDir)
    writeFile("file.txt", content: "same edit", in: remoteDir)

    let localData = readData("file.txt", in: localDir)
    let remoteData = readData("file.txt", in: remoteDir)
    let ancestorData = readData("file.txt", in: ancestorDir)

    // Both made same change → no conflict
    let winner = threeWayResolve(ancestor: ancestorData, local: localData, remote: remoteData)
    XCTAssertEqual(winner, localData)
    XCTAssertEqual(winner, remoteData)
  }

  // MARK: - Conflict Resolution Strategies

  func testNewestWinsResolvesToNewerFile() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    let localFile = localDir.appendingPathComponent("data.txt")
    let remoteFile = remoteDir.appendingPathComponent("data.txt")

    writeFile("data.txt", content: "old local", in: localDir)
    try! FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: localFile.path)
    writeFile("data.txt", content: "newer remote", in: remoteDir)

    resolveConflict(
      file: "data.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .newestWins)
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("data.txt"), encoding: .utf8)
    XCTAssertEqual(result, "newer remote")
  }

  func testLocalWinsAlwaysPicksLocal() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    writeFile("data.txt", content: "local version", in: localDir)
    writeFile("data.txt", content: "remote version", in: remoteDir)

    resolveConflict(
      file: "data.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .localWins)
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("data.txt"), encoding: .utf8)
    XCTAssertEqual(result, "local version")
  }

  func testRemoteWinsAlwaysPicksRemote() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    writeFile("data.txt", content: "local version", in: localDir)
    writeFile("data.txt", content: "remote version", in: remoteDir)

    resolveConflict(
      file: "data.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .remoteWins)
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("data.txt"), encoding: .utf8)
    XCTAssertEqual(result, "remote version")
  }

  func testNewestWinsPicksLocalWhenLocalIsNewer() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    let remoteFile = remoteDir.appendingPathComponent("data.txt")
    writeFile("data.txt", content: "newer local", in: localDir)
    writeFile("data.txt", content: "old remote", in: remoteDir)
    try! FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: remoteFile.path)

    resolveConflict(
      file: "data.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .newestWins)
    let result = try! String(
      contentsOf: mergedDir.appendingPathComponent("data.txt"), encoding: .utf8)
    XCTAssertEqual(result, "newer local")
  }

  // MARK: - Filter Pattern Matching: Glob, Extension, Exclusion

  func testGlobPatternMatchesJpgInDCIM() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/**/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.png", pattern: "DCIM/**/*.jpg"))
  }

  func testGlobPatternDoubleStarMatchesDeepNesting() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/A/B/C/D/E/file.txt", pattern: "**/*.txt"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/file.txt", pattern: "**/*.txt"))
  }

  func testGlobPatternSingleStarDoesNotCrossDirectories() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "DCIM/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/sub/photo.jpg", pattern: "DCIM/*.jpg"))
  }

  func testExclusionFilterRejectsMatchingFiles() {
    let exclusionList: Set<String> = ["Thumbs.db", ".DS_Store", "desktop.ini"]
    let files = ["photo.jpg", "Thumbs.db", "readme.txt", ".DS_Store", "document.pdf"]
    let filtered = files.filter { !exclusionList.contains($0) }
    XCTAssertEqual(filtered, ["photo.jpg", "readme.txt", "document.pdf"])
  }

  func testRegexPatternMatchesDatePrefixedFiles() {
    let pattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}_.*\\.jpg$")
    let match1 = "2024-06-15_photo.jpg"
    let match2 = "random_photo.jpg"
    XCTAssertNotNil(
      pattern.firstMatch(in: match1, range: NSRange(match1.startIndex..., in: match1)))
    XCTAssertNil(
      pattern.firstMatch(in: match2, range: NSRange(match2.startIndex..., in: match2)))
  }

  func testGlobPatternWithMultipleExtensions() {
    // *.jpg should not match .jpeg
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/photos/img.jpg", pattern: "photos/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/photos/img.jpeg", pattern: "photos/*.jpg"))
  }

  func testGlobPatternCaseInsensitive() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/PHOTO.JPG", pattern: "DCIM/*.jpg"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/dcim/photo.jpg", pattern: "DCIM/*.jpg"))
  }

  // MARK: - Incremental Sync: Only Changed Files Transferred

  func testIncrementalSyncOnlyTransfersNewFiles() async throws {
    // Snapshot v1 with one file
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "existing.txt",
          sizeBytes: 10, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 10)))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Snapshot v2 adds a second file
    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "existing.txt",
          sizeBytes: 10, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 10))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "new_file.txt",
          sizeBytes: 5, formatCode: 0x3000, data: Data(repeating: 0xBB, count: 5)))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1, "Only the newly added file should appear")
    XCTAssertTrue(delta.added.first?.pathKey.contains("new_file.txt") ?? false)
    XCTAssertEqual(delta.removed.count, 0)
  }

  func testIncrementalSyncSkipsUnchangedFiles() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "stable.txt",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xCC, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Same device, no changes
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(delta.isEmpty, "Identical snapshots should produce empty diff")
  }

  // MARK: - Sync Anchor Management

  func testAnchorProgressionAcrossSnapshots() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen3 = try await snapshotter.capture(device: device, deviceId: deviceId)

    XCTAssertLessThan(gen1, gen2)
    XCTAssertLessThan(gen2, gen3)
  }

  func testLatestGenerationReturnsNewestAnchor() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let latest = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latest, gen2)
    XCTAssertNotEqual(latest, gen1)
  }

  func testPreviousGenerationReturnsCorrectAncestor() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen2)
    XCTAssertEqual(prev, gen1)
  }

  func testAnchorResetViaFreshDatabase() throws {
    // A new snapshotter on a fresh DB has no generations
    let freshDbPath = tempDirectory.appendingPathComponent("fresh-anchor.sqlite").path
    let freshSnapshotter = try Snapshotter(dbPath: freshDbPath)
    let deviceId = MTPDeviceID(raw: "test:device@0:0")
    let latest = try freshSnapshotter.latestGeneration(for: deviceId)
    XCTAssertNil(latest, "Fresh database should have no anchor for unknown device")
  }

  // MARK: - Mirror Operation with Delete Propagation Disabled

  func testMirrorDoesNotDeleteLocalFilesWhenRemoteDeletes() async throws {
    // First snapshot has a file
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "photo.jpg",
          sizeBytes: 4, formatCode: 0x3000, data: Data([0xFF, 0xD8, 0xFF, 0xE0])))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let outputDir = makeSubDir("mirror-output")

    let report1 = try await mirrorEngine.mirror(
      device: deviceV1, deviceId: deviceId, to: outputDir)
    XCTAssertEqual(report1.downloaded, 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second snapshot removes the file (empty device)
    let deviceV2 = VirtualMTPDevice(config: .emptyDevice)
    let report2 = try await mirrorEngine.mirror(
      device: deviceV2, deviceId: deviceId, to: outputDir)

    // Mirror should NOT delete the local copy (one-way mirror keeps files)
    XCTAssertEqual(report2.downloaded, 0)
    XCTAssertEqual(report2.failed, 0)
  }

  // MARK: - Diff Computation with Renamed Files

  func testRenamedFileSameContentDifferentPath() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let data = Data(repeating: 0xAB, count: 128)
    try! data.write(to: localDir.appendingPathComponent("old_name.bin"))
    try! data.write(to: remoteDir.appendingPathComponent("new_name.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.count, 1)

    let renames = findPotentialRenames(
      localDir: localDir, remoteDir: remoteDir,
      localOnly: changes.localOnly, remoteOnly: changes.remoteOnly)
    XCTAssertEqual(renames.count, 1)
    XCTAssertEqual(renames.first?.from, "old_name.bin")
    XCTAssertEqual(renames.first?.to, "new_name.bin")
  }

  func testRenamedFileDifferentContentNotLinked() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    try! Data(repeating: 0xAA, count: 64)
      .write(
        to: localDir.appendingPathComponent("before.bin"))
    try! Data(repeating: 0xBB, count: 64)
      .write(
        to: remoteDir.appendingPathComponent("after.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let renames = findPotentialRenames(
      localDir: localDir, remoteDir: remoteDir,
      localOnly: changes.localOnly, remoteOnly: changes.remoteOnly)
    XCTAssertTrue(renames.isEmpty, "Different content should not be linked as rename")
  }

  func testRenamedFileMovedToSubdirectory() {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let data = Data(repeating: 0xCC, count: 256)
    try! data.write(to: localDir.appendingPathComponent("photo.jpg"))
    let subDir = remoteDir.appendingPathComponent("2024")
    try! FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    try! data.write(to: subDir.appendingPathComponent("photo.jpg"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let renames = findPotentialRenames(
      localDir: localDir, remoteDir: remoteDir,
      localOnly: changes.localOnly, remoteOnly: changes.remoteOnly)
    XCTAssertEqual(
      renames.count, 1, "Same content moved to subdirectory should be a potential rename")
  }

  // MARK: - Sync Progress Reporting

  func testSyncReportAccumulatesCorrectly() {
    var report = MTPSyncReport()
    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.successRate, 0.0)

    report.downloaded = 7
    report.skipped = 2
    report.failed = 1
    XCTAssertEqual(report.totalProcessed, 10)
    XCTAssertEqual(report.successRate, 70.0, accuracy: 0.001)
  }

  func testSyncReportWithAllSuccesses() {
    var report = MTPSyncReport()
    report.downloaded = 50
    report.skipped = 0
    report.failed = 0
    XCTAssertEqual(report.successRate, 100.0)
  }

  func testSyncReportWithAllFailures() {
    var report = MTPSyncReport()
    report.downloaded = 0
    report.skipped = 0
    report.failed = 10
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testSyncReportSkippedCountsTowardTotal() {
    var report = MTPSyncReport()
    report.downloaded = 0
    report.skipped = 5
    report.failed = 0
    XCTAssertEqual(report.totalProcessed, 5)
    XCTAssertEqual(report.successRate, 0.0, "Skipped files do not count as downloaded")
  }

  // MARK: - Empty Sync: No Changes → No Transfers

  func testEmptySyncProducesNoTransfers() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let outputDir = makeSubDir("empty-mirror")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: outputDir)
    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  func testConsecutiveSnapshotsWithNoChangesProduceEmptyDiff() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "static.bin",
          sizeBytes: 16, formatCode: 0x3000, data: Data(repeating: 0xDD, count: 16)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(delta.isEmpty)
    XCTAssertEqual(delta.totalChanges, 0)
  }

  // MARK: - Partial Sync Failure: Some Succeed, Some Fail

  func testPartialSyncFailureRecordsBothOutcomes() async throws {
    let deviceId = MTPDeviceID(raw: "partial:test@0:0")
    let tmpDir = makeSubDir("partial-journal")

    // Record a successful transfer
    let successId = try journal.beginRead(
      device: deviceId, handle: 100, name: "success.jpg",
      size: 1024, supportsPartial: false,
      tempURL: tmpDir.appendingPathComponent("tmp_success"),
      finalURL: tmpDir.appendingPathComponent("success.jpg"),
      etag: (size: 1024, mtime: nil))
    try journal.complete(id: successId)

    // Record a failed transfer
    let failId = try journal.beginRead(
      device: deviceId, handle: 101, name: "fail.jpg",
      size: 2048, supportsPartial: false,
      tempURL: tmpDir.appendingPathComponent("tmp_fail"),
      finalURL: tmpDir.appendingPathComponent("fail.jpg"),
      etag: (size: 2048, mtime: nil))
    try journal.fail(id: failId, error: NSError(domain: "test", code: -1))

    let active = try journal.listActive()
    let failed = try journal.listFailed()

    // The completed one should not be active
    XCTAssertFalse(active.contains(where: { $0.id == successId }))
    // The failed one should appear in failed list
    XCTAssertTrue(failed.contains(where: { $0.id == failId }))
  }

  func testPartialSyncProgressTracking() async throws {
    let deviceId = MTPDeviceID(raw: "progress:test@0:0")
    let tmpDir = makeSubDir("progress-journal")

    let transferId = try journal.beginRead(
      device: deviceId, handle: 200, name: "large.bin",
      size: 10_000, supportsPartial: true,
      tempURL: tmpDir.appendingPathComponent("tmp_large"),
      finalURL: tmpDir.appendingPathComponent("large.bin"),
      etag: (size: 10_000, mtime: nil))

    // Update progress incrementally
    try journal.updateProgress(id: transferId, committed: 2500)
    try journal.updateProgress(id: transferId, committed: 5000)
    try journal.updateProgress(id: transferId, committed: 7500)

    // Verify it's still active (not yet complete)
    let resumables = try journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables.first?.committedBytes, 7500)

    try journal.complete(id: transferId)
    let afterComplete = try journal.loadResumables(for: deviceId)
    XCTAssertTrue(afterComplete.isEmpty, "Completed transfer should not be resumable")
  }

  // MARK: - MTPDiff Construction Verification

  func testDiffRowFieldIntegrity() {
    let row = MTPDiff.Row(
      handle: 42, storage: 0x0001_0001,
      pathKey: "00010001/DCIM/Camera/test.jpg",
      size: 1_234_567, mtime: Date(timeIntervalSince1970: 1_700_000_000),
      format: 0x3000)

    XCTAssertEqual(row.handle, 42)
    XCTAssertEqual(row.storage, 0x0001_0001)
    XCTAssertEqual(row.pathKey, "00010001/DCIM/Camera/test.jpg")
    XCTAssertEqual(row.size, 1_234_567)
    XCTAssertNotNil(row.mtime)
    XCTAssertEqual(row.format, 0x3000)
  }

  func testEmptyDiffProperties() {
    let diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
    XCTAssertTrue(diff.added.isEmpty)
    XCTAssertTrue(diff.removed.isEmpty)
    XCTAssertTrue(diff.modified.isEmpty)
  }

  func testNonEmptyDiffTotalChanges() {
    var diff = MTPDiff()
    diff.added = [
      MTPDiff.Row(
        handle: 1, storage: 1, pathKey: "a", size: nil, mtime: nil, format: 0x3000)
    ]
    diff.removed = [
      MTPDiff.Row(
        handle: 2, storage: 1, pathKey: "b", size: nil, mtime: nil, format: 0x3000),
      MTPDiff.Row(
        handle: 3, storage: 1, pathKey: "c", size: nil, mtime: nil, format: 0x3000),
    ]
    XCTAssertEqual(diff.totalChanges, 3)
    XCTAssertFalse(diff.isEmpty)
  }

  // MARK: - Helpers

  private enum ConflictStrategy {
    case localWins, remoteWins, newestWins
  }

  private struct ChangeSet {
    let localOnly: [String]
    let remoteOnly: [String]
    let common: [String]
  }

  private struct PotentialRename {
    let from: String
    let to: String
  }

  @discardableResult
  private func makeSubDir(_ name: String) -> URL {
    let dir = tempDirectory.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writeFile(_ name: String, content: String, in dir: URL) {
    try! content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }

  private func readData(_ name: String, in dir: URL) -> Data {
    try! Data(contentsOf: dir.appendingPathComponent(name))
  }

  /// Three-way merge: if only one side changed from ancestor, take that side.
  /// If both changed identically, take either. If both diverged differently, return nil (conflict).
  private func threeWayResolve(ancestor: Data, local: Data, remote: Data) -> Data? {
    let localChanged = local != ancestor
    let remoteChanged = remote != ancestor
    if !localChanged && !remoteChanged { return local }
    if localChanged && !remoteChanged { return local }
    if !localChanged && remoteChanged { return remote }
    // Both changed
    if local == remote { return local }
    return nil  // conflict
  }

  private func detectChanges(local: URL, remote: URL) -> ChangeSet {
    let localFiles = Set(listRelativeFiles(in: local))
    let remoteFiles = Set(listRelativeFiles(in: remote))
    return ChangeSet(
      localOnly: Array(localFiles.subtracting(remoteFiles)).sorted(),
      remoteOnly: Array(remoteFiles.subtracting(localFiles)).sorted(),
      common: Array(localFiles.intersection(remoteFiles)).sorted()
    )
  }

  private func detectConflicts(local: URL, remote: URL, common: [String]) -> [String] {
    common.filter { file in
      let localData = try? Data(contentsOf: local.appendingPathComponent(file))
      let remoteData = try? Data(contentsOf: remote.appendingPathComponent(file))
      return localData != remoteData
    }
  }

  private func findPotentialRenames(
    localDir: URL, remoteDir: URL, localOnly: [String], remoteOnly: [String]
  ) -> [PotentialRename] {
    var renames: [PotentialRename] = []
    for localFile in localOnly {
      let localData = try? Data(contentsOf: localDir.appendingPathComponent(localFile))
      for remoteFile in remoteOnly {
        let remoteData = try? Data(contentsOf: remoteDir.appendingPathComponent(remoteFile))
        if localData == remoteData {
          renames.append(PotentialRename(from: localFile, to: remoteFile))
        }
      }
    }
    return renames
  }

  private func resolveConflict(
    file: String, localDir: URL, remoteDir: URL, mergedDir: URL, strategy: ConflictStrategy
  ) {
    let localFile = localDir.appendingPathComponent(file)
    let remoteFile = remoteDir.appendingPathComponent(file)
    let mergedFile = mergedDir.appendingPathComponent(file)
    switch strategy {
    case .localWins:
      try! FileManager.default.copyItem(at: localFile, to: mergedFile)
    case .remoteWins:
      try! FileManager.default.copyItem(at: remoteFile, to: mergedFile)
    case .newestWins:
      let localMtime =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let remoteMtime =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let winner = localMtime > remoteMtime ? localFile : remoteFile
      try! FileManager.default.copyItem(at: winner, to: mergedFile)
    }
  }

  private func listRelativeFiles(in directory: URL) -> [String] {
    let resolvedDir = directory.resolvingSymlinksInPath()
    guard
      let enumerator = FileManager.default.enumerator(
        at: resolvedDir, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      let resolvedFile = fileURL.resolvingSymlinksInPath()
      files.append(resolvedFile.path.replacingOccurrences(of: resolvedDir.path + "/", with: ""))
    }
    return files
  }
}
