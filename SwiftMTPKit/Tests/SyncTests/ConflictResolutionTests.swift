// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Tests for conflict resolution scenarios during sync operations.
final class ConflictResolutionTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - ConflictResolutionStrategy Enum

  func testStrategyRawValues() {
    XCTAssertEqual(ConflictResolutionStrategy.newerWins.rawValue, "newer-wins")
    XCTAssertEqual(ConflictResolutionStrategy.localWins.rawValue, "local-wins")
    XCTAssertEqual(ConflictResolutionStrategy.deviceWins.rawValue, "device-wins")
    XCTAssertEqual(ConflictResolutionStrategy.keepBoth.rawValue, "keep-both")
    XCTAssertEqual(ConflictResolutionStrategy.skip.rawValue, "skip")
    XCTAssertEqual(ConflictResolutionStrategy.ask.rawValue, "ask")
  }

  func testStrategyFromRawValue() {
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "newer-wins"), .newerWins)
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "local-wins"), .localWins)
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "device-wins"), .deviceWins)
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "keep-both"), .keepBoth)
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "skip"), .skip)
    XCTAssertEqual(ConflictResolutionStrategy(rawValue: "ask"), .ask)
    XCTAssertNil(ConflictResolutionStrategy(rawValue: "invalid"))
  }

  func testAllCasesCount() {
    XCTAssertEqual(ConflictResolutionStrategy.allCases.count, 6)
  }

  // MARK: - ConflictResolutionRecord

  func testConflictResolutionRecordInit() {
    let record = ConflictResolutionRecord(
      pathKey: "65537/DCIM/photo.jpg",
      strategy: .newerWins,
      outcome: .keptDevice)
    XCTAssertEqual(record.pathKey, "65537/DCIM/photo.jpg")
    XCTAssertEqual(record.strategy, .newerWins)
    XCTAssertEqual(record.outcome, .keptDevice)
  }

  // MARK: - ConflictOutcome

  func testConflictOutcomeRawValues() {
    XCTAssertEqual(ConflictOutcome.keptLocal.rawValue, "kept-local")
    XCTAssertEqual(ConflictOutcome.keptDevice.rawValue, "kept-device")
    XCTAssertEqual(ConflictOutcome.keptBoth.rawValue, "kept-both")
    XCTAssertEqual(ConflictOutcome.skipped.rawValue, "skipped")
    XCTAssertEqual(ConflictOutcome.pending.rawValue, "pending")
  }

  // MARK: - MTPSyncReport Conflict Tracking

  func testSyncReportTracksConflicts() {
    var report = MTPSyncReport()
    XCTAssertEqual(report.conflictsDetected, 0)
    XCTAssertTrue(report.conflictResolutions.isEmpty)

    report.conflictsDetected = 3
    report.conflictResolutions.append(
      ConflictResolutionRecord(pathKey: "a", strategy: .skip, outcome: .skipped))
    XCTAssertEqual(report.conflictsDetected, 3)
    XCTAssertEqual(report.conflictResolutions.count, 1)
  }

  // MARK: - Same File Modified Both Sides

  func testBothSidesModifiedSameFileDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Both sides have the same filename but different content
    try "local version A"
      .write(
        to: localDir.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
    try "remote version B"
      .write(
        to: remoteDir.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts.first, "conflict.txt")
  }

  func testBothSidesIdenticalFileNoConflict() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let content = "identical content"
    try content.write(
      to: localDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
    try content.write(
      to: remoteDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertTrue(conflicts.isEmpty)
  }

  func testMultipleConflictsDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    for i in 1...5 {
      try "local-\(i)"
        .write(
          to: localDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
      try "remote-\(i)"
        .write(
          to: remoteDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
    }

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 5)
  }

  // MARK: - Deletion vs Modification Conflicts

  func testLocalDeletedRemoteModifiedDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // File exists only on remote (deleted on local)
    try "remote modified"
      .write(
        to: remoteDir.appendingPathComponent("deleted_locally.txt"), atomically: true,
        encoding: .utf8
      )

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertTrue(changes.remoteOnly.contains("deleted_locally.txt"))
  }

  func testRemoteDeletedLocalModifiedDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // File exists only locally (deleted on remote)
    try "local modified"
      .write(
        to: localDir.appendingPathComponent("deleted_remotely.txt"), atomically: true,
        encoding: .utf8
      )

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertTrue(changes.localOnly.contains("deleted_remotely.txt"))
  }

  func testBothSidesDeletedNoConflict() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Neither side has the file — no conflict
    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
    XCTAssertTrue(changes.common.isEmpty)
  }

  // MARK: - Conflict Resolution Strategy: Local Wins

  func testLocalWinsStrategyPreservesLocalVersion() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    try "local wins"
      .write(
        to: localDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try "remote version"
      .write(
        to: remoteDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "doc.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .localWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("doc.txt"), encoding: .utf8)
    XCTAssertEqual(merged, "local wins")
  }

  // MARK: - Conflict Resolution Strategy: Remote Wins

  func testRemoteWinsStrategyPreservesRemoteVersion() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    try "local version"
      .write(
        to: localDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try "remote wins"
      .write(
        to: remoteDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "doc.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .remoteWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("doc.txt"), encoding: .utf8)
    XCTAssertEqual(merged, "remote wins")
  }

  // MARK: - Conflict Resolution Strategy: Newest Wins

  func testNewestWinsPicksNewerFile() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    let localFile = localDir.appendingPathComponent("doc.txt")
    let remoteFile = remoteDir.appendingPathComponent("doc.txt")

    try "old local".write(to: localFile, atomically: true, encoding: .utf8)
    // Set local file to old date
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: localFile.path)

    try "newer remote".write(to: remoteFile, atomically: true, encoding: .utf8)
    // Remote file has current date (newer)

    resolveConflict(
      file: "doc.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .newestWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("doc.txt"), encoding: .utf8)
    XCTAssertEqual(merged, "newer remote")
  }

  // MARK: - Keep Both Strategy

  func testKeepBothCreatesDeviceSuffixedCopy() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    try "local data"
      .write(to: localDir.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)
    try "device data"
      .write(to: remoteDir.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "photo.jpg", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .keepBoth)

    // Both files should exist in merged dir
    let localCopy = try String(
      contentsOf: mergedDir.appendingPathComponent("photo-local.jpg"), encoding: .utf8)
    let deviceCopy = try String(
      contentsOf: mergedDir.appendingPathComponent("photo-device.jpg"), encoding: .utf8)
    XCTAssertEqual(localCopy, "local data")
    XCTAssertEqual(deviceCopy, "device data")
  }

  // MARK: - Skip Strategy

  func testSkipStrategyProducesNoMergedFile() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    let mergedDir = tempDirectory.appendingPathComponent("merged")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: mergedDir, withIntermediateDirectories: true)

    try "local"
      .write(to: localDir.appendingPathComponent("skip.txt"), atomically: true, encoding: .utf8)
    try "remote"
      .write(to: remoteDir.appendingPathComponent("skip.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "skip.txt", localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir,
      strategy: .skip)

    XCTAssertFalse(
      FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent("skip.txt").path))
  }

  // MARK: - Conflict with Size-Only Change

  func testSizeDifferenceDetectedAsConflict() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    try Data(repeating: 0xAA, count: 100).write(to: localDir.appendingPathComponent("data.bin"))
    try Data(repeating: 0xBB, count: 200).write(to: remoteDir.appendingPathComponent("data.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 1)
  }

  func testEmptyFileConflictWithNonEmpty() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    try Data().write(to: localDir.appendingPathComponent("empty.bin"))
    try Data(repeating: 0xFF, count: 10).write(to: remoteDir.appendingPathComponent("empty.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    let conflicts = detectConflicts(local: localDir, remote: remoteDir, common: changes.common)

    XCTAssertEqual(conflicts.count, 1)
  }

  // MARK: - MTPConflictInfo

  func testMTPConflictInfoInit() {
    let info = MTPConflictInfo(
      pathKey: "65537/DCIM/photo.jpg", handle: 42,
      deviceSize: 1024, deviceMtime: Date(),
      localSize: 2048, localMtime: Date(timeIntervalSinceNow: -600))
    XCTAssertEqual(info.pathKey, "65537/DCIM/photo.jpg")
    XCTAssertEqual(info.handle, 42)
    XCTAssertEqual(info.deviceSize, 1024)
    XCTAssertEqual(info.localSize, 2048)
  }

  // MARK: - Helpers

  private enum ConflictStrategy {
    case localWins, remoteWins, newestWins, keepBoth, skip
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
    case .keepBoth:
      let ext = (file as NSString).pathExtension
      let base = (file as NSString).deletingPathExtension
      let localName = ext.isEmpty ? "\(base)-local" : "\(base)-local.\(ext)"
      let deviceName = ext.isEmpty ? "\(base)-device" : "\(base)-device.\(ext)"
      try? FileManager.default.copyItem(
        at: localFile, to: mergedDir.appendingPathComponent(localName))
      try? FileManager.default.copyItem(
        at: remoteFile, to: mergedDir.appendingPathComponent(deviceName))
    case .skip:
      break  // Do nothing
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
