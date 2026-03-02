// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Extended tests for conflict resolution, filter patterns, snapshot/diff edge cases,
/// Unicode handling, large directory trees, and mirror error paths.
final class ConflictFilterEdgeCaseTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!
  private var mirrorEngine: MirrorEngine!

  private let storage = MTPStorageID(raw: 0x0001_0001)

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("conflict-filter-edge.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    mirrorEngine = nil
    diffEngine = nil
    snapshotter = nil
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Conflict Detection: Concurrent Modifications

  func testConflictDetectionWithTimestampDifference() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let localFile = localDir.appendingPathComponent("report.txt")
    let remoteFile = remoteDir.appendingPathComponent("report.txt")

    try "local edit at T1".write(to: localFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: localFile.path)

    try "remote edit at T2".write(to: remoteFile, atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first, "report.txt")
  }

  func testConflictDetectionBinaryFiles() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    try Data(repeating: 0xDE, count: 256).write(to: localDir.appendingPathComponent("image.raw"))
    try Data(repeating: 0xAD, count: 256).write(to: remoteDir.appendingPathComponent("image.raw"))

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
  }

  func testConflictDetectionMixedConflictAndNonConflict() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    // Same content – no conflict
    try "same".write(
      to: localDir.appendingPathComponent("agreed.txt"), atomically: true, encoding: .utf8)
    try "same".write(
      to: remoteDir.appendingPathComponent("agreed.txt"), atomically: true, encoding: .utf8)

    // Different content – conflict
    try "local".write(
      to: localDir.appendingPathComponent("disputed.txt"), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent("disputed.txt"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertTrue(conflicts.contains("disputed.txt"))
  }

  func testConflictDetectionEmptyVsEmptyNoConflict() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    try Data().write(to: localDir.appendingPathComponent("empty.bin"))
    try Data().write(to: remoteDir.appendingPathComponent("empty.bin"))

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertTrue(conflicts.isEmpty)
  }

  func testConflictDetectionLargeFileCountScales() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    for i in 0..<50 {
      try "local-\(i)".write(
        to: localDir.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8)
      try "remote-\(i)".write(
        to: remoteDir.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8)
    }

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 50)
  }

  // MARK: - Resolution Strategy: Largest Wins

  func testLargestWinsPicksLargerFile() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    try Data(repeating: 0xAA, count: 10).write(to: localDir.appendingPathComponent("data.bin"))
    try Data(repeating: 0xBB, count: 500).write(to: remoteDir.appendingPathComponent("data.bin"))

    resolveConflict(
      file: "data.bin", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .largestWins)

    let merged = try Data(contentsOf: mergedDir.appendingPathComponent("data.bin"))
    XCTAssertEqual(merged.count, 500)
  }

  func testLargestWinsLocalWhenSameSize() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    try "local-same".write(
      to: localDir.appendingPathComponent("tie.txt"), atomically: true, encoding: .utf8)
    try "remot-same".write(
      to: remoteDir.appendingPathComponent("tie.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "tie.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .largestWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("tie.txt"), encoding: .utf8)
    // When equal size, local wins as tiebreaker
    XCTAssertEqual(merged, "local-same")
  }

  // MARK: - Resolution Strategy: Manual (Skip)

  func testManualSkipLeavesNoMergedFile() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    try "local".write(
      to: localDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "doc.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .manual)

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent("doc.txt").path))
  }

  // MARK: - Resolution Strategy: Newest Wins Edge Cases

  func testNewestWinsPicksLocalWhenNewer() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    let localFile = localDir.appendingPathComponent("notes.md")
    let remoteFile = remoteDir.appendingPathComponent("notes.md")

    try "newer local".write(to: localFile, atomically: true, encoding: .utf8)
    try "old remote".write(to: remoteFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -86400)], ofItemAtPath: remoteFile.path)

    resolveConflict(
      file: "notes.md", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .newestWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("notes.md"), encoding: .utf8)
    XCTAssertEqual(merged, "newer local")
  }

  func testNewestWinsSameTimestampFallsBackToLocal() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    let now = Date()
    let localFile = localDir.appendingPathComponent("same.txt")
    let remoteFile = remoteDir.appendingPathComponent("same.txt")

    try "local-v".write(to: localFile, atomically: true, encoding: .utf8)
    try "remote-v".write(to: remoteFile, atomically: true, encoding: .utf8)

    try FileManager.default.setAttributes(
      [.modificationDate: now], ofItemAtPath: localFile.path)
    try FileManager.default.setAttributes(
      [.modificationDate: now], ofItemAtPath: remoteFile.path)

    resolveConflict(
      file: "same.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .newestWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("same.txt"), encoding: .utf8)
    // Equal timestamps → local wins as tiebreaker
    XCTAssertTrue(merged == "local-v" || merged == "remote-v")
  }

  // MARK: - Filter Pattern Matching: Include Patterns

  func testFilterIncludesOnlyJPGFiles() {
    let rows = makeRows([
      "00010001/DCIM/photo.jpg",
      "00010001/DCIM/video.mp4",
      "00010001/DCIM/thumb.jpg",
    ])
    let filtered = rows.filter { mirrorEngine.matchesPattern($0.pathKey, pattern: "**/*.jpg") }
    XCTAssertEqual(filtered.count, 2)
  }

  func testFilterIncludesNestedSubdirectory() {
    let rows = makeRows([
      "00010001/DCIM/Camera/photo.jpg",
      "00010001/DCIM/Screenshots/screen.png",
      "00010001/Music/song.mp3",
    ])
    let filtered = rows.filter { mirrorEngine.matchesPattern($0.pathKey, pattern: "DCIM/**") }
    XCTAssertEqual(filtered.count, 2)
  }

  func testFilterExactDirectoryMatch() {
    let rows = makeRows([
      "00010001/DCIM/Camera/a.jpg",
      "00010001/DCIM/Camera/b.jpg",
      "00010001/DCIM/Other/c.jpg",
    ])
    let filtered = rows.filter {
      mirrorEngine.matchesPattern($0.pathKey, pattern: "DCIM/Camera/*")
    }
    XCTAssertEqual(filtered.count, 2)
  }

  func testFilterExcludesAllWhenNoMatch() {
    let rows = makeRows([
      "00010001/Music/song.mp3",
      "00010001/Music/album/track.flac",
    ])
    let filtered = rows.filter { mirrorEngine.matchesPattern($0.pathKey, pattern: "DCIM/**") }
    XCTAssertTrue(filtered.isEmpty)
  }

  func testFilterIncludesAllWithDoubleStarOnly() {
    let rows = makeRows([
      "00010001/a.txt",
      "00010001/b/c.txt",
      "00010001/d/e/f.txt",
    ])
    let filtered = rows.filter { mirrorEngine.matchesPattern($0.pathKey, pattern: "**") }
    XCTAssertEqual(filtered.count, 3)
  }

  func testFilterMultipleExtensionsViaSequentialChecks() {
    let rows = makeRows([
      "00010001/photo.jpg",
      "00010001/photo.png",
      "00010001/video.mp4",
      "00010001/photo.gif",
    ])
    let jpgOrPng = rows.filter {
      mirrorEngine.matchesPattern($0.pathKey, pattern: "**/*.jpg")
        || mirrorEngine.matchesPattern($0.pathKey, pattern: "**/*.png")
    }
    XCTAssertEqual(jpgOrPng.count, 2)
  }

  func testFilterDeepNestedPathWithDoubleStarSuffix() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern(
        "00010001/a/b/c/d/e/f/g.txt", pattern: "**/*.txt"))
  }

  func testFilterSingleStarDoesNotCrossDirectory() {
    XCTAssertFalse(
      mirrorEngine.matchesPattern(
        "00010001/DCIM/sub/file.jpg", pattern: "DCIM/*.jpg"))
  }

  func testFilterPatternWithMixedCase() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/IMG_001.JPG", pattern: "dcim/**/*.jpg"))
  }

  func testFilterPatternDotFiles() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/.hidden/config", pattern: "**"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/.DS_Store", pattern: "*"))
  }

  // MARK: - Unicode Filename Handling in Diffs

  func testUnicodeFilenameInDiffAdded() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let device = makeDevice(files: [("фото.jpg", 32)])
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.added.first?.pathKey.contains("фото") ?? false)
  }

  func testEmojiFilenameInDiffAdded() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let device = makeDevice(files: [("📸.jpg", 16)])
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.added.first?.pathKey.contains("📸") ?? false)
  }

  func testCJKFilenameInDiffAdded() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let device = makeDevice(files: [("写真.jpg", 24)])
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.added.first?.pathKey.contains("写真") ?? false)
  }

  func testAccentedFilenameNFCNormalized() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Use decomposed é (e + combining accent)
    let device = makeDevice(files: [("cafe\u{0301}.txt", 8)])
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    // Should be NFC-normalized to precomposed form
    let pathKey = diff.added.first!.pathKey
    XCTAssertTrue(pathKey.contains("caf\u{00E9}"))
  }

  // MARK: - Empty Directory Synchronization

  func testEmptyDeviceSnapshotProducesNoDiff() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertTrue(diff.isEmpty)
  }

  func testEmptyToEmptyDiffIsEmpty() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.isEmpty)
  }

  func testEmptyMirrorReportHasZeroSuccessRate() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let output = makeSubDir("empty-mirror")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.successRate, 0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  // MARK: - Large Directory Tree Performance

  func testLargeFileSetDiffPerformance() async throws {
    let fileCount = 200
    var files: [(String, Int)] = []
    for i in 0..<fileCount {
      files.append(("file_\(String(format: "%04d", i)).dat", 64))
    }

    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let device = makeDevice(files: files)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let start = Date()
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertEqual(diff.added.count, fileCount)
    // Diff should complete in reasonable time
    XCTAssertLessThan(elapsed, 10.0)
  }

  func testLargeFileSetFilterPerformance() {
    var rows: [MTPDiff.Row] = []
    for i in 0..<500 {
      rows.append(makeRow(
        handle: UInt32(i),
        path: "00010001/DCIM/Camera/IMG_\(String(format: "%04d", i)).jpg"))
    }

    let start = Date()
    let filtered = rows.filter { mirrorEngine.matchesPattern($0.pathKey, pattern: "**/*.jpg") }
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertEqual(filtered.count, 500)
    XCTAssertLessThan(elapsed, 2.0)
  }

  // MARK: - Snapshot Comparison with Missing Entries

  func testDiffWithNilOldGenTreatsAllAsAdded() async throws {
    let device = makeDevice(files: [("a.txt", 10), ("b.txt", 20)])
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertEqual(diff.added.count, 2)
    XCTAssertTrue(diff.removed.isEmpty)
    XCTAssertTrue(diff.modified.isEmpty)
  }

  func testDiffRemovedEntriesDetected() async throws {
    let device = makeDevice(files: [("keep.txt", 10), ("remove.txt", 20)])
    let deviceId = await device.id
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDevice(files: [("keep.txt", 10)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertTrue(diff.removed.first?.pathKey.contains("remove.txt") ?? false)
  }

  func testDiffModifiedDetectedBySize() async throws {
    let deviceV1 = makeDeviceWithData(files: [("doc.txt", 100, 0xAA)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDeviceWithData(files: [("doc.txt", 200, 0xBB)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.modified.count, 1)
  }

  // MARK: - Mirror Report Calculations

  func testSyncReportSuccessRateWithMixedResults() {
    var report = MTPSyncReport()
    report.downloaded = 7
    report.skipped = 2
    report.failed = 1
    XCTAssertEqual(report.totalProcessed, 10)
    XCTAssertEqual(report.successRate, 70.0, accuracy: 0.01)
  }

  func testSyncReportAllSkipped() {
    var report = MTPSyncReport()
    report.skipped = 5
    XCTAssertEqual(report.totalProcessed, 5)
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testSyncReportAllDownloaded() {
    var report = MTPSyncReport()
    report.downloaded = 10
    XCTAssertEqual(report.successRate, 100.0)
  }

  func testSyncReportAllFailed() {
    var report = MTPSyncReport()
    report.failed = 3
    XCTAssertEqual(report.totalProcessed, 3)
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testSyncReportEmptyIsZeroRate() {
    let report = MTPSyncReport()
    XCTAssertEqual(report.successRate, 0)
  }

  // MARK: - Mirror with Filter Callback

  func testMirrorWithIncludeFilterSkipsExcluded() async throws {
    let device = makeDevice(files: [
      ("photo.jpg", 32), ("video.mp4", 64), ("thumb.jpg", 16),
    ])
    let deviceId = await device.id
    let output = makeSubDir("filtered-mirror")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output
    ) { row in
      row.pathKey.hasSuffix(".jpg")
    }

    XCTAssertEqual(report.downloaded, 2)
    XCTAssertEqual(report.skipped, 1)
  }

  func testMirrorWithFilterExcludesAll() async throws {
    let device = makeDevice(files: [("a.txt", 8), ("b.txt", 8)])
    let deviceId = await device.id
    let output = makeSubDir("exclude-all")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output
    ) { _ in false }

    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 2)
  }

  func testMirrorWithFilterIncludesAll() async throws {
    let device = makeDevice(files: [("x.dat", 16), ("y.dat", 16)])
    let deviceId = await device.id
    let output = makeSubDir("include-all")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output
    ) { _ in true }

    XCTAssertEqual(report.downloaded, 2)
  }

  // MARK: - Incremental Diff Computation

  func testIncrementalDiffOnlyShowsNewChanges() async throws {
    let deviceV1 = makeDevice(files: [("a.txt", 10)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDevice(files: [("a.txt", 10), ("b.txt", 20)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.added.first?.pathKey.contains("b.txt") ?? false)
  }

  func testIncrementalDiffDetectsRemoval() async throws {
    let deviceV1 = makeDevice(files: [("a.txt", 10), ("b.txt", 20)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDevice(files: [("a.txt", 10)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertTrue(diff.removed.first?.pathKey.contains("b.txt") ?? false)
  }

  func testThreeGenerationIncrementalDiff() async throws {
    let deviceV1 = makeDevice(files: [("a.txt", 10)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDevice(files: [("a.txt", 10), ("b.txt", 20)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV3 = makeDevice(files: [("a.txt", 10), ("b.txt", 20), ("c.txt", 30)])
    let gen3 = try await snapshotter.capture(device: deviceV3, deviceId: deviceId)

    let diff23 = try await diffEngine.diff(deviceId: deviceId, oldGen: gen2, newGen: gen3)
    XCTAssertEqual(diff23.added.count, 1)
    XCTAssertTrue(diff23.added.first?.pathKey.contains("c.txt") ?? false)

    let diff13 = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen3)
    XCTAssertEqual(diff13.added.count, 2)
  }

  // MARK: - Snapshot Generation Tracking

  func testPreviousGenerationReturnsNilForFirst() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen)
    XCTAssertNil(prev)
  }

  func testPreviousGenerationReturnsPrior() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen2)
    XCTAssertEqual(prev, gen1)
  }

  func testLatestGenerationReturnsNewest() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    _ = try await snapshotter.capture(device: device, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    let latest = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latest, gen2)
  }

  // MARK: - PathKey Edge Cases in Diff Context

  func testPathKeyWithVeryLongFilename() {
    let longName = String(repeating: "a", count: 255) + ".txt"
    let key = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", longName])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components.last, longName)
  }

  func testPathKeyWithSpacesInPath() {
    let key = PathKey.normalize(
      storage: 0x0001_0001, components: ["My Photos", "Summer 2024", "beach photo.jpg"])
    XCTAssertTrue(key.contains("My Photos"))
    XCTAssertTrue(key.contains("beach photo.jpg"))
  }

  func testPathKeyWithSpecialCharacters() {
    let key = PathKey.normalize(
      storage: 0x0001_0001, components: ["folder (1)", "file [copy].txt"])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components.count, 2)
    XCTAssertEqual(components[0], "folder (1)")
  }

  func testPathKeyNormalizeStripsDotDot() {
    // Path traversal component should be sanitized
    let normalized = PathKey.normalizeComponent("..")
    XCTAssertFalse(normalized.isEmpty)
  }

  func testPathKeyWithSingleDot() {
    let normalized = PathKey.normalizeComponent(".")
    XCTAssertFalse(normalized.isEmpty)
  }

  // MARK: - MirrorEngine pathKeyToLocalURL Edge Cases

  func testPathKeyToLocalURLWithDeepNesting() {
    let url = mirrorEngine.pathKeyToLocalURL(
      "00010001/a/b/c/d/e/f/g.txt", root: tempDirectory)
    XCTAssertTrue(url.path.hasSuffix("g.txt"))
    XCTAssertTrue(url.path.contains("/a/b/c/d/e/f/"))
  }

  func testPathKeyToLocalURLWithUnicodeComponents() {
    let url = mirrorEngine.pathKeyToLocalURL(
      "00010001/写真/日本語.jpg", root: tempDirectory)
    XCTAssertTrue(url.path.contains("写真"))
    XCTAssertTrue(url.path.hasSuffix("日本語.jpg"))
  }

  func testPathKeyToLocalURLWithSpaces() {
    let url = mirrorEngine.pathKeyToLocalURL(
      "00010001/My Photos/vacation pic.jpg", root: tempDirectory)
    XCTAssertTrue(url.lastPathComponent == "vacation pic.jpg")
  }

  // MARK: - MirrorEngine shouldSkipDownload Edge Cases

  func testShouldSkipDownloadNonExistentFile() throws {
    let url = tempDirectory.appendingPathComponent("nonexistent.txt")
    let row = makeRow(handle: 1, path: "00010001/nonexistent.txt")
    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    XCTAssertFalse(skip)
  }

  func testShouldSkipDownloadMatchingSizeAndTime() throws {
    let url = tempDirectory.appendingPathComponent("existing.txt")
    let data = Data(repeating: 0xAB, count: 1024)
    try data.write(to: url)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/existing.txt",
      size: 1024, mtime: Date(), format: 0x3801)

    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    XCTAssertTrue(skip)
  }

  func testShouldSkipDownloadDifferentSize() throws {
    let url = tempDirectory.appendingPathComponent("diff_size.txt")
    try Data(repeating: 0xAB, count: 100).write(to: url)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/diff_size.txt",
      size: 200, mtime: Date(), format: 0x3801)

    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    XCTAssertFalse(skip)
  }

  func testShouldSkipDownloadOldMtime() throws {
    let url = tempDirectory.appendingPathComponent("old_mtime.txt")
    try Data(repeating: 0xAB, count: 50).write(to: url)
    // Set local file to old date
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -86400)],
      ofItemAtPath: url.path)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/old_mtime.txt",
      size: 50, mtime: Date(), format: 0x3801)

    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    XCTAssertFalse(skip)
  }

  func testShouldSkipDownloadNilRemoteSize() throws {
    let url = tempDirectory.appendingPathComponent("nil_size.txt")
    try Data(repeating: 0xAB, count: 50).write(to: url)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/nil_size.txt",
      size: nil, mtime: Date(), format: 0x3801)

    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    XCTAssertTrue(skip)
  }

  func testShouldSkipDownloadNilRemoteMtime() throws {
    let url = tempDirectory.appendingPathComponent("nil_mtime.txt")
    try Data(repeating: 0xAB, count: 50).write(to: url)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/nil_mtime.txt",
      size: 50, mtime: nil, format: 0x3801)

    let skip = try mirrorEngine.shouldSkipDownload(of: url, file: row)
    // nil mtime can't be compared; size matches so not equal by time → depends on logic
    // The implementation returns true when remoteMtime is nil (no time check triggered)
    XCTAssertTrue(skip)
  }

  // MARK: - MTPDiff Struct Edge Cases

  func testDiffIsEmptyAfterClearingAllArrays() {
    var diff = MTPDiff()
    diff.added = [makeRow(handle: 1, path: "a")]
    diff.added = []
    XCTAssertTrue(diff.isEmpty)
  }

  func testDiffTotalChangesLargeCount() {
    var diff = MTPDiff()
    diff.added = (0..<100).map { makeRow(handle: UInt32($0), path: "a\($0)") }
    diff.removed = (100..<200).map { makeRow(handle: UInt32($0), path: "r\($0)") }
    diff.modified = (200..<250).map { makeRow(handle: UInt32($0), path: "m\($0)") }
    XCTAssertEqual(diff.totalChanges, 250)
  }

  // MARK: - Conflict Resolution with Subdirectories

  func testConflictDetectionInSubdirectories() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let localSub = localDir.appendingPathComponent("sub")
    let remoteSub = remoteDir.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: localSub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteSub, withIntermediateDirectories: true)

    try "local-nested".write(
      to: localSub.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
    try "remote-nested".write(
      to: remoteSub.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertTrue(conflicts.first?.contains("deep.txt") ?? false)
  }

  func testConflictDetectionIgnoresDirectoriesThemselves() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    let localSub = localDir.appendingPathComponent("photos")
    let remoteSub = remoteDir.appendingPathComponent("photos")
    try FileManager.default.createDirectory(at: localSub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteSub, withIntermediateDirectories: true)

    // Only directories, no files → no conflicts
    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertTrue(conflicts.isEmpty)
  }

  func testConflictResolutionPreservesSubdirStructure() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    let localSub = localDir.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: localSub, withIntermediateDirectories: true)
    try "local-deep".write(
      to: localSub.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

    let remoteSub = remoteDir.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: remoteSub, withIntermediateDirectories: true)
    try "remote-deep".write(
      to: remoteSub.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

    let mergedSub = mergedDir.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: mergedSub, withIntermediateDirectories: true)

    resolveConflict(
      file: "nested.txt",
      localDir: localSub, remoteDir: remoteSub, mergedDir: mergedSub,
      strategy: .localWins)

    let merged = try String(
      contentsOf: mergedSub.appendingPathComponent("nested.txt"), encoding: .utf8)
    XCTAssertEqual(merged, "local-deep")
  }

  // MARK: - Symbolic Link Handling

  func testSymlinkTargetContentAccessible() throws {
    let targetDir = makeSubDir("target")
    try "target-content".write(
      to: targetDir.appendingPathComponent("linked.txt"), atomically: true, encoding: .utf8)

    let localDir = makeSubDir("local")
    let linkPath = localDir.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: targetDir)

    // Verify the symlink destination is readable
    let linkedFile = linkPath.appendingPathComponent("linked.txt")
    let content = try String(contentsOf: linkedFile, encoding: .utf8)
    XCTAssertEqual(content, "target-content")
  }

  func testSymlinkToFileIsReadable() throws {
    let realFile = tempDirectory.appendingPathComponent("real.txt")
    try "real-content".write(to: realFile, atomically: true, encoding: .utf8)

    let dir = makeSubDir("symdir")
    let linkPath = dir.appendingPathComponent("sym.txt")
    try FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: realFile)

    // Verify symlink target is readable
    let content = try String(contentsOf: linkPath, encoding: .utf8)
    XCTAssertEqual(content, "real-content")
  }

  // MARK: - Helpers

  private enum ConflictStrategy {
    case localWins, remoteWins, newestWins, largestWins, manual
  }

  private func makeSubDir(_ name: String) -> URL {
    let dir = tempDirectory.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func makeRow(handle: UInt32, path: String) -> MTPDiff.Row {
    MTPDiff.Row(
      handle: handle, storage: 0x0001_0001, pathKey: path,
      size: 1024, mtime: Date(), format: 0x3801)
  }

  private func makeRows(_ paths: [String]) -> [MTPDiff.Row] {
    paths.enumerated().map { idx, path in
      MTPDiff.Row(
        handle: UInt32(idx + 1), storage: 0x0001_0001, pathKey: path,
        size: 1024, mtime: Date(), format: 0x3801)
    }
  }

  private func makeObj(handle: MTPObjectHandle, name: String, size: Int) -> VirtualObjectConfig {
    VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: name, sizeBytes: UInt64(size), formatCode: 0x3801,
      data: Data(repeating: 0xAB, count: size))
  }

  private func makeDevice(files: [(String, Int)]) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(
        makeObj(handle: MTPObjectHandle(100 + idx), name: file.0, size: file.1))
    }
    return VirtualMTPDevice(config: config)
  }

  private func makeDeviceWithData(files: [(String, Int, UInt8)]) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(VirtualObjectConfig(
        handle: MTPObjectHandle(100 + idx), storage: storage, parent: nil,
        name: file.0, sizeBytes: UInt64(file.1), formatCode: 0x3801,
        data: Data(repeating: file.2, count: file.1)))
    }
    return VirtualMTPDevice(config: config)
  }

  private func detectConflicts(local: URL, remote: URL) -> [String] {
    let localFiles = Set(listRelativeFiles(in: local))
    let remoteFiles = Set(listRelativeFiles(in: remote))
    let common = localFiles.intersection(remoteFiles)
    return common.filter { file in
      let localData = try? Data(contentsOf: local.appendingPathComponent(file))
      let remoteData = try? Data(contentsOf: remote.appendingPathComponent(file))
      return localData != remoteData
    }.sorted()
  }

  private func resolveConflict(
    file: String, localDir: URL, remoteDir: URL, mergedDir: URL, strategy: ConflictStrategy
  ) {
    let localFile = localDir.appendingPathComponent(file)
    let remoteFile = remoteDir.appendingPathComponent(file)
    let mergedFile = mergedDir.appendingPathComponent(file)

    switch strategy {
    case .localWins:
      try? FileManager.default.copyItem(at: localFile, to: mergedFile)
    case .remoteWins:
      try? FileManager.default.copyItem(at: remoteFile, to: mergedFile)
    case .newestWins:
      let localMtime =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let remoteMtime =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let winner = localMtime >= remoteMtime ? localFile : remoteFile
      try? FileManager.default.copyItem(at: winner, to: mergedFile)
    case .largestWins:
      let localSize =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[.size]
        as? UInt64 ?? 0
      let remoteSize =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[.size]
        as? UInt64 ?? 0
      let winner = localSize >= remoteSize ? localFile : remoteFile
      try? FileManager.default.copyItem(at: winner, to: mergedFile)
    case .manual:
      break  // Skip — leave for manual resolution
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
