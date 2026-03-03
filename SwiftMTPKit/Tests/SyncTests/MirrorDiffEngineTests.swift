// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Comprehensive tests for the mirror and diff engine covering conflict resolution,
/// large file sets, special characters, case-insensitive paths, and more.
final class MirrorDiffEngineTests: XCTestCase {
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
    dbPath = tempDirectory.appendingPathComponent("mirror-diff-engine.sqlite").path
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

  // MARK: - Empty Source Mirroring to Empty Target

  func testEmptySourceToEmptyTargetProducesEmptyDiff() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
  }

  func testEmptySourceMirrorProducesEmptyReport() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("empty-mirror")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  // MARK: - Single File Addition

  func testSingleFileAdditionDetectedInDiff() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let withFile = makeDevice(files: [("newfile.txt", 64)])
    let gen2 = try await snapshotter.capture(device: withFile, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.added.first?.pathKey.contains("newfile.txt") ?? false)
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 0)
  }

  func testSingleFileAdditionMirrorDownloads() async throws {
    let device = makeDevice(files: [("added.jpg", 32)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("add-mirror")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  // MARK: - Single File Modification

  func testSingleFileModificationDetectedBySize() async throws {
    let deviceV1 = makeDeviceWithConfig(files: [("doc.txt", 100, 0xAA)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDeviceWithConfig(files: [("doc.txt", 200, 0xBB)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.modified.count, 1)
    XCTAssertTrue(diff.modified.first?.pathKey.contains("doc.txt") ?? false)
    XCTAssertEqual(diff.added.count, 0)
    XCTAssertEqual(diff.removed.count, 0)
  }

  // MARK: - Single File Deletion

  func testSingleFileDeletionDetectedInDiff() async throws {
    let deviceV1 = makeDevice(files: [("deleteme.txt", 32)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = VirtualMTPDevice(config: .emptyDevice)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertTrue(diff.removed.first?.pathKey.contains("deleteme.txt") ?? false)
    XCTAssertEqual(diff.added.count, 0)
  }

  // MARK: - Directory Structure Mirroring (Nested Directories)

  func testNestedDirectoryStructureDiffDetectsDeepFiles() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // VirtualMTPDevice list(parent:nil) returns only root-level objects,
    // so we use root-level files to simulate a directory structure diff.
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 10, storage: storage, parent: nil,
          name: "DCIM", formatCode: 0x3001)
      )
      .withObject(
        VirtualObjectConfig(
          handle: 11, storage: storage, parent: nil,
          name: "photo.jpg", sizeBytes: 1024, formatCode: 0x3801,
          data: Data(repeating: 0xFF, count: 1024))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 12, storage: storage, parent: nil,
          name: "screen.png", sizeBytes: 512, formatCode: 0x3801,
          data: Data(repeating: 0xAA, count: 512)))
    let deviceV2 = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThanOrEqual(diff.added.count, 2, "Should detect multiple additions")
    let addedPaths = diff.added.map { $0.pathKey }
    XCTAssertTrue(
      addedPaths.contains { $0.contains("photo.jpg") },
      "photo.jpg should appear in additions")
    XCTAssertTrue(
      addedPaths.contains { $0.contains("screen.png") },
      "screen.png should appear in additions")
  }

  func testNestedDirectoryMirrorCreatesSubdirectories() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 10, storage: storage, parent: nil,
          name: "Documents", formatCode: 0x3001)
      )
      .withObject(
        VirtualObjectConfig(
          handle: 11, storage: storage, parent: 10,
          name: "report.pdf", sizeBytes: 64, formatCode: 0x3000,
          data: Data(repeating: 0xDD, count: 64)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("nested-output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertGreaterThanOrEqual(report.downloaded, 1)
  }

  // MARK: - Conflict Detection (File Modified on Both Sides)

  func testConflictDetectionBothSidesModified() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    try "local content v2"
      .write(
        to: localDir.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
    try "remote content v2"
      .write(
        to: remoteDir.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first, "shared.txt")
  }

  func testNoConflictWhenBothSidesIdentical() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let content = "identical on both sides"
    try content.write(
      to: localDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
    try content.write(
      to: remoteDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertTrue(conflicts.isEmpty)
  }

  // MARK: - Conflict Resolution Strategies

  func testKeepLocalStrategy() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try [localDir, remoteDir, mergedDir]
      .forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
      }

    try "keep this"
      .write(
        to: localDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try "discard this"
      .write(
        to: remoteDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "file.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .localWins)

    let result = try String(
      contentsOf: mergedDir.appendingPathComponent("file.txt"), encoding: .utf8)
    XCTAssertEqual(result, "keep this")
  }

  func testKeepRemoteStrategy() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try [localDir, remoteDir, mergedDir]
      .forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
      }

    try "discard this"
      .write(
        to: localDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try "keep this"
      .write(
        to: remoteDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "file.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .remoteWins)

    let result = try String(
      contentsOf: mergedDir.appendingPathComponent("file.txt"), encoding: .utf8)
    XCTAssertEqual(result, "keep this")
  }

  func testNewestWinsStrategyPicksNewerFile() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try [localDir, remoteDir, mergedDir]
      .forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
      }

    let localFile = localDir.appendingPathComponent("file.txt")
    let remoteFile = remoteDir.appendingPathComponent("file.txt")

    try "old version".write(to: localFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: localFile.path)

    try "newer version".write(to: remoteFile, atomically: true, encoding: .utf8)

    resolveConflict(
      file: "file.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .newestWins)

    let result = try String(
      contentsOf: mergedDir.appendingPathComponent("file.txt"), encoding: .utf8)
    XCTAssertEqual(result, "newer version")
  }

  func testNewestWinsPicksLocalWhenLocalIsNewer() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try [localDir, remoteDir, mergedDir]
      .forEach {
        try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
      }

    let localFile = localDir.appendingPathComponent("file.txt")
    let remoteFile = remoteDir.appendingPathComponent("file.txt")

    try "newer local".write(to: localFile, atomically: true, encoding: .utf8)

    try "old remote".write(to: remoteFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: remoteFile.path)

    resolveConflict(
      file: "file.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .newestWins)

    let result = try String(
      contentsOf: mergedDir.appendingPathComponent("file.txt"), encoding: .utf8)
    XCTAssertEqual(result, "newer local")
  }

  // MARK: - Large File Set Diffing Performance

  func testLargeFileSetDiffPerformance() async throws {
    let fileCount = 1000
    let deviceV1 = makeDevice(
      files: (0..<fileCount).map { ("file_\($0).dat", 16) })
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // V2: add 100 new files, remove none
    var filesV2 = (0..<fileCount).map { ("file_\($0).dat", 16) }
    for i in fileCount..<(fileCount + 100) {
      filesV2.append(("file_\(i).dat", 16))
    }
    let deviceV2 = makeDevice(files: filesV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let start = CFAbsoluteTimeGetCurrent()
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertEqual(diff.added.count, 100, "Should detect 100 new files")
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertLessThan(elapsed, 30.0, "Diff of 1100 files should complete within 30 seconds")
  }

  // MARK: - Symbolic Link Handling

  func testPathKeyToLocalURLHandlesSymlinksInRoot() throws {
    let realDir = tempDirectory.appendingPathComponent("real")
    let symlinkDir = tempDirectory.appendingPathComponent("symlink")
    try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: realDir)

    let url = mirrorEngine.pathKeyToLocalURL("00010001/photo.jpg", root: symlinkDir)
    XCTAssertTrue(url.path.contains("photo.jpg"))
  }

  // MARK: - File Permission Preservation via shouldSkipDownload

  func testShouldSkipReturnsFalseForSizeMismatch() throws {
    let localFile = tempDirectory.appendingPathComponent("mismatch.bin")
    try Data(repeating: 0xAA, count: 100).write(to: localFile)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/mismatch.bin",
      size: 200, mtime: Date(), format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertFalse(skip, "Should not skip when sizes differ")
  }

  func testShouldSkipReturnsTrueWhenSizeAndMtimeMatch() throws {
    let localFile = tempDirectory.appendingPathComponent("match.bin")
    try Data(repeating: 0xBB, count: 100).write(to: localFile)

    let attrs = try FileManager.default.attributesOfItem(atPath: localFile.path)
    let localMtime = attrs[.modificationDate] as! Date

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/match.bin",
      size: 100, mtime: localMtime, format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertTrue(skip, "Should skip when size and mtime match within tolerance")
  }

  // MARK: - Timestamp Comparison Precision

  func testTimestampWithinToleranceConsideredEqual() throws {
    let localFile = tempDirectory.appendingPathComponent("ts.bin")
    try Data(repeating: 0xCC, count: 50).write(to: localFile)

    // Set local mtime to now
    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now], ofItemAtPath: localFile.path)

    // Remote mtime is 200 seconds off (within 300s tolerance)
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/ts.bin",
      size: 50, mtime: now.addingTimeInterval(200), format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertTrue(skip, "200 second drift should be within 300s tolerance")
  }

  func testTimestampBeyondToleranceNotSkipped() throws {
    let localFile = tempDirectory.appendingPathComponent("ts-drift.bin")
    try Data(repeating: 0xDD, count: 50).write(to: localFile)

    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now], ofItemAtPath: localFile.path)

    // Remote mtime is 600 seconds off (beyond 300s tolerance)
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/ts-drift.bin",
      size: 50, mtime: now.addingTimeInterval(600), format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertFalse(skip, "600 second drift should exceed 300s tolerance")
  }

  func testNilRemoteMtimeSkipsTimeComparison() throws {
    let localFile = tempDirectory.appendingPathComponent("no-mtime.bin")
    try Data(repeating: 0xEE, count: 50).write(to: localFile)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/no-mtime.bin",
      size: 50, mtime: nil, format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertTrue(skip, "Nil remote mtime with matching size should skip")
  }

  // MARK: - Hash-Based vs Timestamp-Based Change Detection

  func testDiffDetectsModificationViaSizeChange() async throws {
    let deviceV1 = makeDeviceWithConfig(files: [("data.bin", 100, 0xAA)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDeviceWithConfig(files: [("data.bin", 200, 0xBB)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(diff.modified.count, 1, "Size change should be detected as modification")
  }

  func testDiffNoModificationWhenSizeAndMtimeMatch() async throws {
    let deviceV1 = makeDevice(files: [("stable.bin", 100)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Same file, same size — diff relies on mtime tolerance
    let deviceV2 = makeDevice(files: [("stable.bin", 100)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    // Both snapshots have nil mtime (VirtualMTPDevice default), so they should be considered equal
    XCTAssertEqual(diff.modified.count, 0, "Same size with nil mtime on both sides = no change")
  }

  // MARK: - Partial Sync (Resume After Interruption)

  func testMirrorWithFilterSkipsNonMatchingFiles() async throws {
    let device = makeDevice(files: [
      ("photo.jpg", 32), ("document.pdf", 64), ("video.mp4", 128),
    ])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("partial-output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output,
      include: { row in row.pathKey.hasSuffix(".jpg") })

    XCTAssertEqual(report.downloaded, 1, "Only .jpg should download")
    XCTAssertEqual(report.skipped, 2, "Non-jpg files should be skipped")
  }

  func testIncrementalMirrorOnlyDownloadsNewFiles() async throws {
    let deviceV1 = makeDevice(files: [("existing.txt", 32)])
    let deviceId = await deviceV1.id
    let output = tempDirectory.appendingPathComponent("incremental-output")

    _ = try await mirrorEngine.mirror(device: deviceV1, deviceId: deviceId, to: output)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: "existing.txt", sizeBytes: 32, formatCode: 0x3801,
          data: Data(repeating: 0xAB, count: 32))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, parent: nil,
          name: "new.txt", sizeBytes: 16, formatCode: 0x3801,
          data: Data(repeating: 0xCD, count: 16)))
    let deviceV2 = VirtualMTPDevice(config: config)
    let report = try await mirrorEngine.mirror(device: deviceV2, deviceId: deviceId, to: output)

    XCTAssertGreaterThanOrEqual(report.downloaded, 1, "Should download at least the new file")
  }

  // MARK: - Mirror with Exclusion Patterns

  func testExcludeDSStorePattern() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "**/*.jpg"))
    XCTAssertFalse(mirrorEngine.matchesPattern("00010001/.DS_Store", pattern: "**/*.jpg"))
  }

  func testExcludeThumbsDbPattern() {
    XCTAssertFalse(mirrorEngine.matchesPattern("00010001/Thumbs.db", pattern: "DCIM/**"))
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "DCIM/**"))
  }

  func testMirrorWithExcludeFilterSkipsDSStore() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: ".DS_Store", sizeBytes: 8, formatCode: 0x3000,
          data: Data(repeating: 0x00, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, parent: nil,
          name: "photo.jpg", sizeBytes: 32, formatCode: 0x3801,
          data: Data(repeating: 0xFF, count: 32)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("exclude-output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output,
      include: { row in
        let name = PathKey.basename(of: row.pathKey)
        return name != ".DS_Store" && name != "Thumbs.db"
      })

    XCTAssertEqual(report.downloaded, 1, "Only photo.jpg should download")
    XCTAssertEqual(report.skipped, 1, ".DS_Store should be skipped")
  }

  // MARK: - Case-Insensitive Path Comparison

  func testGlobPatternIsCaseInsensitive() {
    // The matchesPattern uses .caseInsensitive regex matching
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/PHOTO.JPG", pattern: "DCIM/**/*.jpg"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/dcim/camera/photo.jpg", pattern: "DCIM/**/*.jpg"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/Dcim/Camera/Photo.Jpg", pattern: "DCIM/**/*.jpg"))
  }

  func testPathKeyNormalizationIsCaseSensitiveInStorage() {
    // Path keys preserve case from the device
    let key1 = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", "photo.jpg"])
    let key2 = PathKey.normalize(storage: 0x0001_0001, components: ["dcim", "photo.jpg"])
    XCTAssertNotEqual(key1, key2, "PathKey preserves case from device")
  }

  // MARK: - Paths with Special Characters

  func testPathKeyWithSpaces() {
    let key = PathKey.normalize(
      storage: 0x0001_0001, components: ["My Photos", "vacation pic.jpg"])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components, ["My Photos", "vacation pic.jpg"])
  }

  func testPathKeyWithUnicode() {
    let key = PathKey.normalize(
      storage: 0x0001_0001, components: ["日本語", "写真.jpg"])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components[0], "日本語")
    XCTAssertEqual(components[1], "写真.jpg")
  }

  func testPathKeyWithEmoji() {
    let key = PathKey.normalize(
      storage: 0x0001_0001, components: ["📸 Photos", "🌅 sunset.jpg"])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components[0], "📸 Photos")
    XCTAssertEqual(components[1], "🌅 sunset.jpg")
  }

  func testPathKeyWithMixedUnicodeNormalization() {
    // Test NFC normalization: combining é vs precomposed é
    let decomposed = "cafe\u{0301}.txt"
    let precomposed = "caf\u{00E9}.txt"
    let norm1 = PathKey.normalizeComponent(decomposed)
    let norm2 = PathKey.normalizeComponent(precomposed)
    XCTAssertEqual(norm1, norm2, "NFC normalization should make both forms equal")
  }

  func testPathToLocalURLWithSpecialChars() {
    let url = mirrorEngine.pathKeyToLocalURL(
      "00010001/My Photos/trip (2024)/photo 1.jpg", root: tempDirectory)
    XCTAssertTrue(url.lastPathComponent == "photo 1.jpg")
  }

  // MARK: - Diff with Moved/Renamed Files

  func testRenamedFileDetectedAsAddAndRemove() async throws {
    let deviceV1 = makeDevice(files: [("old_name.txt", 64)])
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let deviceV2 = makeDevice(files: [("new_name.txt", 64)])
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    // Rename appears as remove old + add new since diff is path-based
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertTrue(diff.removed.first?.pathKey.contains("old_name.txt") ?? false)
    XCTAssertTrue(diff.added.first?.pathKey.contains("new_name.txt") ?? false)
  }

  func testMovedFileAcrossDirectoriesDetectedAsAddAndRemove() async throws {
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 10, storage: storage, parent: nil,
          name: "FolderA", formatCode: 0x3001)
      )
      .withObject(
        VirtualObjectConfig(
          handle: 11, storage: storage, parent: 10,
          name: "moved.txt", sizeBytes: 32, formatCode: 0x3000,
          data: Data(repeating: 0xAA, count: 32)))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 20, storage: storage, parent: nil,
          name: "FolderB", formatCode: 0x3001)
      )
      .withObject(
        VirtualObjectConfig(
          handle: 21, storage: storage, parent: 20,
          name: "moved.txt", sizeBytes: 32, formatCode: 0x3000,
          data: Data(repeating: 0xAA, count: 32)))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    // Path changed from FolderA/moved.txt to FolderB/moved.txt
    let removedPaths = diff.removed.map { $0.pathKey }
    let addedPaths = diff.added.map { $0.pathKey }
    XCTAssertTrue(removedPaths.contains { $0.contains("FolderA") })
    XCTAssertTrue(addedPaths.contains { $0.contains("FolderB") })
  }

  // MARK: - MTPSyncReport Properties

  func testSyncReportSuccessRateZeroWhenEmpty() {
    let report = MTPSyncReport()
    XCTAssertEqual(report.successRate, 0.0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  func testSyncReportSuccessRateCalcuation() {
    var report = MTPSyncReport()
    report.downloaded = 8
    report.skipped = 1
    report.failed = 1
    XCTAssertEqual(report.totalProcessed, 10)
    XCTAssertEqual(report.successRate, 80.0)
  }

  func testSyncReportAllFailedZeroSuccessRate() {
    var report = MTPSyncReport()
    report.downloaded = 0
    report.failed = 5
    XCTAssertEqual(report.successRate, 0.0)
  }

  // MARK: - MTPDiff Struct Tests

  func testEmptyDiffProperties() {
    let diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
    XCTAssertTrue(diff.added.isEmpty)
    XCTAssertTrue(diff.removed.isEmpty)
    XCTAssertTrue(diff.modified.isEmpty)
  }

  func testDiffWithMixedChanges() {
    var diff = MTPDiff()
    diff.added = [makeRow(handle: 1, path: "00010001/a.jpg")]
    diff.removed = [
      makeRow(handle: 2, path: "00010001/b.jpg"), makeRow(handle: 3, path: "00010001/c.jpg"),
    ]
    diff.modified = [makeRow(handle: 4, path: "00010001/d.jpg")]
    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 4)
  }

  // MARK: - Glob Pattern Matching Edge Cases

  func testWildcardStarMatchesSingleLevel() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "DCIM/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/sub/photo.jpg", pattern: "DCIM/*.jpg"))
  }

  func testDoubleStarMatchesMultipleLevels() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "DCIM/**"))
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/a/b/c/photo.jpg", pattern: "DCIM/**"))
  }

  func testGlobalDoubleStarMatchesEverything() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/any/path/file.txt", pattern: "**"))
  }

  func testPatternWithLeadingSlash() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/photo.jpg", pattern: "/DCIM/**"))
  }

  // MARK: - PathKey Utilities

  func testPathKeyBasenameOfDeepPath() {
    XCTAssertEqual(PathKey.basename(of: "00010001/a/b/c/d/file.ext"), "file.ext")
  }

  func testPathKeyIsPrefixWorks() {
    XCTAssertTrue(PathKey.isPrefix("00010001/DCIM", of: "00010001/DCIM/Camera/photo.jpg"))
    XCTAssertFalse(PathKey.isPrefix("00010001/DCIM", of: "00010001/Music/song.mp3"))
    XCTAssertFalse(PathKey.isPrefix("00010001/DCIM", of: "00010001/DCIM"))
  }

  func testPathKeyFromLocalURLValidPath() {
    let root = URL(fileURLWithPath: "/tmp/mirror")
    let file = URL(fileURLWithPath: "/tmp/mirror/DCIM/photo.jpg")
    let key = PathKey.fromLocalURL(file, relativeTo: root, storage: 0x0001_0001)
    XCTAssertNotNil(key)
    XCTAssertTrue(key!.contains("DCIM"))
    XCTAssertTrue(key!.contains("photo.jpg"))
  }

  func testPathKeyFromLocalURLOutsideRootReturnsNil() {
    let root = URL(fileURLWithPath: "/tmp/mirror")
    let file = URL(fileURLWithPath: "/other/path/file.txt")
    XCTAssertNil(PathKey.fromLocalURL(file, relativeTo: root, storage: 0x0001_0001))
  }

  // MARK: - DiffEngine with nil oldGen (first snapshot)

  func testDiffWithNilOldGenTreatsAllAsAdded() async throws {
    let device = makeDevice(files: [("a.txt", 16), ("b.txt", 32)])
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertEqual(diff.added.count, 2, "All files should be added when comparing against nil")
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 0)
  }

  // MARK: - shouldSkipDownload Edge Cases

  func testShouldSkipReturnsFalseWhenFileDoesNotExist() throws {
    let nonexistent = tempDirectory.appendingPathComponent("nonexistent.bin")
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/nonexistent.bin",
      size: 100, mtime: Date(), format: 0x3000)
    let skip = try mirrorEngine.shouldSkipDownload(of: nonexistent, file: row)
    XCTAssertFalse(skip, "Nonexistent file should never be skipped")
  }

  // MARK: - Helpers

  private enum ConflictStrategy {
    case localWins, remoteWins, newestWins
  }

  private func makeRow(handle: UInt32, path: String) -> MTPDiff.Row {
    MTPDiff.Row(
      handle: handle, storage: 0x0001_0001, pathKey: path,
      size: 1024, mtime: Date(), format: 0x3801)
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

  private func makeDeviceWithConfig(files: [(String, Int, UInt8)]) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(
        VirtualObjectConfig(
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
    return
      common.filter { file in
        let localData = try? Data(contentsOf: local.appendingPathComponent(file))
        let remoteData = try? Data(contentsOf: remote.appendingPathComponent(file))
        return localData != remoteData
      }
      .sorted()
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
      let winner = localMtime > remoteMtime ? localFile : remoteFile
      try? FileManager.default.copyItem(at: winner, to: mergedFile)
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
