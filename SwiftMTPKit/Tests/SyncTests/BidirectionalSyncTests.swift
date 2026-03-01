// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Tests for bidirectional sync edge cases: empty dirs, nested deletions, rename tracking.
final class BidirectionalSyncTests: XCTestCase {
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

  // MARK: - Empty Directory Handling

  func testEmptyDirectoryOnBothSidesProducesNoChanges() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
    XCTAssertTrue(changes.common.isEmpty)
  }

  func testEmptySubdirectoriesDoNotAppearAsChanges() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(
      at: localDir.appendingPathComponent("emptySubDir"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: remoteDir.appendingPathComponent("emptySubDir"), withIntermediateDirectories: true)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    // Only files are tracked, not directories
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
  }

  func testLocalHasEmptyDirRemoteHasFilesInSameDir() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(
      at: localDir.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: remoteDir.appendingPathComponent("DCIM"), withIntermediateDirectories: true)

    try "photo".write(
      to: remoteDir.appendingPathComponent("DCIM/photo.jpg"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertTrue(changes.remoteOnly.contains("DCIM/photo.jpg"))
  }

  // MARK: - Nested Deletion Detection

  func testNestedFileDeletionOnRemote() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(
      at: localDir.appendingPathComponent("A/B/C"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: remoteDir.appendingPathComponent("A/B"), withIntermediateDirectories: true)

    try "deep file".write(
      to: localDir.appendingPathComponent("A/B/C/file.txt"), atomically: true, encoding: .utf8)
    // Remote doesn't have C/file.txt — it was deleted

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertTrue(changes.localOnly.contains("A/B/C/file.txt"))
  }

  func testEntireDirectoryTreeDeletedOnLocal() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: remoteDir.appendingPathComponent("Photos/2024/Jan"), withIntermediateDirectories: true)

    try "jan1".write(
      to: remoteDir.appendingPathComponent("Photos/2024/Jan/img1.jpg"), atomically: true,
      encoding: .utf8)
    try "jan2".write(
      to: remoteDir.appendingPathComponent("Photos/2024/Jan/img2.jpg"), atomically: true,
      encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.remoteOnly.count, 2)
  }

  func testDeeplyNestedStructureMatchesExactly() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")

    let nestedPath = "A/B/C/D/E"
    try FileManager.default.createDirectory(
      at: localDir.appendingPathComponent(nestedPath), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: remoteDir.appendingPathComponent(nestedPath), withIntermediateDirectories: true)

    try "deep".write(
      to: localDir.appendingPathComponent("\(nestedPath)/deep.txt"), atomically: true,
      encoding: .utf8)
    try "deep".write(
      to: remoteDir.appendingPathComponent("\(nestedPath)/deep.txt"), atomically: true,
      encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
    XCTAssertEqual(changes.common.count, 1)
  }

  // MARK: - Rename Tracking

  func testRenamedFileDetectedAsAddAndDelete() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Local has old name, remote has new name (same content)
    let content = "file content"
    try content.write(
      to: localDir.appendingPathComponent("old_name.txt"), atomically: true, encoding: .utf8)
    try content.write(
      to: remoteDir.appendingPathComponent("new_name.txt"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertTrue(changes.localOnly.contains("old_name.txt"))
    XCTAssertTrue(changes.remoteOnly.contains("new_name.txt"))
  }

  func testRenamedFileWithSameContentCanBeLinkedBySizeHash() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let data = Data(repeating: 0xAB, count: 256)
    try data.write(to: localDir.appendingPathComponent("before.bin"))
    try data.write(to: remoteDir.appendingPathComponent("after.bin"))

    let changes = detectChanges(local: localDir, remote: remoteDir)
    // Detect potential rename: localOnly + remoteOnly with same size
    let potentialRenames = findPotentialRenames(
      localDir: localDir, remoteDir: remoteDir,
      localOnly: changes.localOnly, remoteOnly: changes.remoteOnly)

    XCTAssertEqual(potentialRenames.count, 1)
    XCTAssertEqual(potentialRenames.first?.from, "before.bin")
    XCTAssertEqual(potentialRenames.first?.to, "after.bin")
  }

  // MARK: - Mixed Operations

  func testMixedAddDeleteModifyRename() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Common file (no change)
    try "unchanged".write(
      to: localDir.appendingPathComponent("stable.txt"), atomically: true, encoding: .utf8)
    try "unchanged".write(
      to: remoteDir.appendingPathComponent("stable.txt"), atomically: true, encoding: .utf8)

    // Local-only addition
    try "new local".write(
      to: localDir.appendingPathComponent("new_local.txt"), atomically: true, encoding: .utf8)

    // Remote-only addition
    try "new remote".write(
      to: remoteDir.appendingPathComponent("new_remote.txt"), atomically: true, encoding: .utf8)

    // Conflict (both modified)
    try "local mod".write(
      to: localDir.appendingPathComponent("both.txt"), atomically: true, encoding: .utf8)
    try "remote mod".write(
      to: remoteDir.appendingPathComponent("both.txt"), atomically: true, encoding: .utf8)

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertEqual(changes.common.count, 2)  // stable.txt + both.txt
  }

  func testLargeNumberOfFilesDetectedCorrectly() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    for i in 0..<50 {
      try "content-\(i)".write(
        to: localDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
    }
    for i in 25..<75 {
      try "content-\(i)".write(
        to: remoteDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
    }

    let changes = detectChanges(local: localDir, remote: remoteDir)
    XCTAssertEqual(changes.localOnly.count, 25)  // files 0-24
    XCTAssertEqual(changes.remoteOnly.count, 25)  // files 50-74
    XCTAssertEqual(changes.common.count, 25)  // files 25-49
  }

  // MARK: - Helpers

  private struct ChangeSet {
    let localOnly: [String]
    let remoteOnly: [String]
    let common: [String]
  }

  private struct PotentialRename {
    let from: String
    let to: String
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

  private func listRelativeFiles(in directory: URL) -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      files.append(fileURL.path.replacingOccurrences(of: directory.path + "/", with: ""))
    }
    return files
  }
}
