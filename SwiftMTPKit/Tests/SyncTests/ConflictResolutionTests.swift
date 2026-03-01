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

  // MARK: - Same File Modified Both Sides

  func testBothSidesModifiedSameFileDetected() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Both sides have the same filename but different content
    try "local version A".write(
      to: localDir.appendingPathComponent("conflict.txt"), atomically: true, encoding: .utf8)
    try "remote version B".write(
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
      try "local-\(i)".write(
        to: localDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
      try "remote-\(i)".write(
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
    try "remote modified".write(
      to: remoteDir.appendingPathComponent("deleted_locally.txt"), atomically: true, encoding: .utf8
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
    try "local modified".write(
      to: localDir.appendingPathComponent("deleted_remotely.txt"), atomically: true, encoding: .utf8
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

    try "local wins".write(
      to: localDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try "remote version".write(
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

    try "local version".write(
      to: localDir.appendingPathComponent("doc.txt"), atomically: true, encoding: .utf8)
    try "remote wins".write(
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
