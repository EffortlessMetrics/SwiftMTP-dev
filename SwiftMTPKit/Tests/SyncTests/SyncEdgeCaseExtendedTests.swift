// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Simultaneous Modification Conflict Tests

/// Tests for conflict resolution when both sides are modified simultaneously.
final class SimultaneousModificationConflictTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  func testSimultaneousModificationsOnMultipleFilesDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Simulate both sides modifying the same set of files at nearly the same time
    for i in 0..<10 {
      try "local-edit-\(i)".write(
        to: localDir.appendingPathComponent("shared_\(i).txt"), atomically: true, encoding: .utf8)
      try "remote-edit-\(i)".write(
        to: remoteDir.appendingPathComponent("shared_\(i).txt"), atomically: true, encoding: .utf8)
    }

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 10, "All simultaneously modified files should be conflicts")
  }

  func testMixedConflictAndNonConflictFiles() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Files with identical content — no conflict
    try "same content".write(
      to: localDir.appendingPathComponent("identical.txt"), atomically: true, encoding: .utf8)
    try "same content".write(
      to: remoteDir.appendingPathComponent("identical.txt"), atomically: true, encoding: .utf8)

    // Files with different content — conflict
    try "local change".write(
      to: localDir.appendingPathComponent("diverged.txt"), atomically: true, encoding: .utf8)
    try "remote change".write(
      to: remoteDir.appendingPathComponent("diverged.txt"), atomically: true, encoding: .utf8)

    // File only on local — not a conflict, just local-only
    try "new local".write(
      to: localDir.appendingPathComponent("local_only.txt"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first, "diverged.txt")
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertTrue(changes.localOnly.contains("local_only.txt"))
  }

  func testConflictWithBinaryContentDifference() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Same size but different binary content
    try Data(repeating: 0xAA, count: 256).write(
      to: localDir.appendingPathComponent("firmware.bin"))
    try Data(repeating: 0xBB, count: 256).write(
      to: remoteDir.appendingPathComponent("firmware.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 1, "Same-size binary files with different content are conflicts")
  }

  func testConflictResolutionLocalWinsWithMultipleFiles() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    let files = ["alpha.txt", "beta.txt", "gamma.txt"]
    for file in files {
      try "local-\(file)".write(
        to: localDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
      try "remote-\(file)".write(
        to: remoteDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    for file in files {
      resolveConflict(
        file: file, localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
        strategy: .localWins)
    }

    for file in files {
      let merged = try String(
        contentsOf: mergedDir.appendingPathComponent(file), encoding: .utf8)
      XCTAssertEqual(merged, "local-\(file)")
    }
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

// MARK: - Mirror Resume After Interrupted Transfer Tests

/// Tests for partial mirror state and resume scenarios.
final class MirrorResumeInterruptionTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  private let storage = MTPStorageID(raw: 0x0001_0001)

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("resume-test.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    mirrorEngine = nil
    diffEngine = nil
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testMirrorAfterPartialLocalFilesExist() async throws {
    // Simulate partial mirror: some files already on disk from a previous run
    let output = tempDirectory.appendingPathComponent("partial-mirror")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    // Pre-create one file to simulate a partial download from a prior mirror
    let existingFile = output.appendingPathComponent("already_here.jpg")
    try Data(repeating: 0xCD, count: 32).write(to: existingFile)

    // Device has two files: already_here.jpg + new_file.jpg
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: "already_here.jpg", sizeBytes: 32, formatCode: 0x3801,
          data: Data(repeating: 0xCD, count: 32))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, parent: nil,
          name: "new_file.jpg", sizeBytes: 16, formatCode: 0x3801,
          data: Data(repeating: 0xEF, count: 16)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)

    // Both files processed (downloaded or re-downloaded)
    XCTAssertEqual(report.totalProcessed, 2)
    XCTAssertEqual(report.failed, 0)
  }

  func testMirrorRerunOnSameDeviceStateIsIdempotent() async throws {
    let output = tempDirectory.appendingPathComponent("idempotent-mirror")
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: "stable.jpg", sizeBytes: 8, formatCode: 0x3801,
          data: Data(repeating: 0xAA, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    // First mirror
    let report1 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report1.downloaded, 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second mirror with same device state — diff should be empty
    let report2 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report2.totalProcessed, 0, "Re-mirror of unchanged device should process 0 files")
  }

  func testMirrorWithFilterSkipsNonMatchingFiles() async throws {
    let output = tempDirectory.appendingPathComponent("filtered-mirror")
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: "photo.jpg", sizeBytes: 8, formatCode: 0x3801,
          data: Data(repeating: 0xAA, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, parent: nil,
          name: "readme.txt", sizeBytes: 8, formatCode: 0x3000,
          data: Data(repeating: 0xBB, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output, includePattern: "**/*.jpg")

    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.skipped, 1, "Non-matching file should be skipped")
  }
}

// MARK: - Large Directory Tree Diff Tests

/// Tests for diff correctness on larger directory structures.
final class LargeDirectoryTreeDiffTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  private let storage = MTPStorageID(raw: 0x0001_0001)

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("large-tree.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
  }

  override func tearDownWithError() throws {
    diffEngine = nil
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testDiffWith500FilesAllAdded() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<500 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "file_\(String(format: "%04d", i)).dat", sizeBytes: 4,
          formatCode: 0x3801, data: Data([0x01, 0x02, 0x03, 0x04])))
    }
    let populatedDevice = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 500, "All 500 files should be added")
    XCTAssertEqual(delta.removed.count, 0)
    XCTAssertEqual(delta.modified.count, 0)
    XCTAssertEqual(delta.totalChanges, 500)
  }

  func testDiffWith500FilesAllRemoved() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<500 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "file_\(String(format: "%04d", i)).dat", sizeBytes: 4,
          formatCode: 0x3801, data: Data([0x01, 0x02, 0x03, 0x04])))
    }
    let populatedDevice = VirtualMTPDevice(config: config)
    let deviceId = await populatedDevice.id
    let gen1 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let gen2 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.removed.count, 500, "All 500 files should be removed")
    XCTAssertEqual(delta.added.count, 0)
  }

  func testDiffWithMixedAdditionsRemovalsAndModifications() async throws {
    // V1: 20 flat files
    var configV1 = VirtualDeviceConfig.emptyDevice
    for i in 0..<20 {
      configV1 = configV1.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "photo_\(i).jpg", sizeBytes: 8, formatCode: 0x3801,
          data: Data(repeating: UInt8(i), count: 8)))
    }
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // V2: keep first 10, remove last 10, add 5 new, modify handle 100 by size
    var configV2 = VirtualDeviceConfig.emptyDevice

    // Modify first file by changing size
    configV2 = configV2.withObject(
      VirtualObjectConfig(
        handle: MTPObjectHandle(100), storage: storage,
        name: "photo_0.jpg", sizeBytes: 16, formatCode: 0x3801,
        data: Data(repeating: 0xFF, count: 16)))

    // Keep files 1-9 unchanged
    for i in 1..<10 {
      configV2 = configV2.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "photo_\(i).jpg", sizeBytes: 8, formatCode: 0x3801,
          data: Data(repeating: UInt8(i), count: 8)))
    }
    // Files 10-19 removed (not added to configV2)

    // Add 5 new files
    for i in 0..<5 {
      configV2 = configV2.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(200 + i), storage: storage,
          name: "new_photo_\(i).jpg", sizeBytes: 8, formatCode: 0x3801,
          data: Data(repeating: 0xCC, count: 8)))
    }

    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

    XCTAssertEqual(delta.added.count, 5, "5 new photos should be added")
    XCTAssertEqual(delta.removed.count, 10, "10 photos should be removed")
    XCTAssertEqual(delta.modified.count, 1, "1 photo should be modified (size changed)")
  }
}

// MARK: - Empty Storage / Zero-File Sync Tests

/// Tests for sync behavior when device has no files.
final class EmptyStorageSyncTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("empty-storage.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    mirrorEngine = nil
    diffEngine = nil
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testEmptyDeviceSnapshotDiffIsEmpty() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertTrue(delta.isEmpty)
    XCTAssertEqual(delta.totalChanges, 0)
  }

  func testEmptyDeviceMirrorReportAllZeros() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("empty-out")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testTransitionFromEmptyToPopulatedDetectsAllAdded() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "first.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "second.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8])))
    let populatedDevice = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 2)
    XCTAssertEqual(delta.removed.count, 0)
  }

  func testTransitionFromPopulatedToEmptyDetectsAllRemoved() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "going_away.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let populatedDevice = VirtualMTPDevice(config: config)
    let deviceId = await populatedDevice.id
    let gen1 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let gen2 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.removed.count, 1)
    XCTAssertEqual(delta.added.count, 0)
  }

  func testEmptyDeviceSyncReportSuccessRateIsZero() {
    var report = MTPSyncReport()
    XCTAssertEqual(report.successRate, 0.0)
    XCTAssertEqual(report.totalProcessed, 0)

    // Even with skips only, rate should still be computed
    report.skipped = 5
    XCTAssertEqual(report.totalProcessed, 5)
    XCTAssertEqual(report.successRate, 0.0, "Skipped files don't count as downloaded")
  }
}

// MARK: - Unicode Filename Sync Tests

/// Tests for sync handling of Unicode filenames including CJK, emoji, and accented characters.
final class UnicodeFilenameSyncTests: XCTestCase {
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
    dbPath = tempDirectory.appendingPathComponent("unicode-sync.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    mirrorEngine = nil
    diffEngine = nil
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testSnapshotWithCJKFilenames() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "写真.jpg",
          sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xAA, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "사진.png",
          sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xBB, count: 8))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 102, storage: storage, name: "照片.tiff",
          sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xCC, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0, "Snapshot with CJK filenames should succeed")
  }

  func testDiffWithEmojiFilenames() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "📷_sunset.jpg",
          sizeBytes: 4, formatCode: 0x3801, data: Data([0x01, 0x02, 0x03, 0x04]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "🎵_track01.mp3",
          sizeBytes: 4, formatCode: 0x3009, data: Data([0x05, 0x06, 0x07, 0x08])))
    let withEmoji = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: withEmoji, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 2, "Emoji-named files should appear as additions")
  }

  func testMirrorWithAccentedFilenames() async throws {
    let output = tempDirectory.appendingPathComponent("accented-mirror")
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, parent: nil,
          name: "café_résumé.txt", sizeBytes: 8, formatCode: 0x3000,
          data: Data(repeating: 0xDD, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  func testDiffWithMixedScriptFilenames() async throws {
    let names = [
      "Ñoño.doc",
      "Ünïcödé.pdf",
      "Привет.txt",
      "مرحبا.html",
      "こんにちは.xml",
    ]

    var config = VirtualDeviceConfig.emptyDevice
    for (i, name) in names.enumerated() {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: name, sizeBytes: 4, formatCode: 0x3000,
          data: Data([0x01, 0x02, 0x03, 0x04])))
    }
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    XCTAssertEqual(delta.added.count, names.count, "All mixed-script filenames should appear")
  }

  func testGlobPatternMatchesUnicodeFilenames() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/写真.jpg", pattern: "**/*.jpg"),
      "Glob should match CJK filename with .jpg extension")
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/café.txt", pattern: "**/*.txt"),
      "Glob should match accented filename with .txt extension")
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/📷_sunset.jpg", pattern: "**/*.png"),
      "Glob should not match .jpg file against .png pattern")
  }

  func testConflictDetectionWithUnicodeFilenames() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    try "local café".write(
      to: localDir.appendingPathComponent("café.txt"), atomically: true, encoding: .utf8)
    try "remote café".write(
      to: remoteDir.appendingPathComponent("café.txt"), atomically: true, encoding: .utf8)

    let localFiles = Set(listRelativeFiles(in: localDir))
    let remoteFiles = Set(listRelativeFiles(in: remoteDir))
    let common = Array(localFiles.intersection(remoteFiles))

    let conflicts = common.filter { file in
      let localData = try? Data(contentsOf: localDir.appendingPathComponent(file))
      let remoteData = try? Data(contentsOf: remoteDir.appendingPathComponent(file))
      return localData != remoteData
    }

    XCTAssertEqual(conflicts.count, 1, "Unicode filename conflict should be detected")
  }

  // MARK: - Helpers

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
