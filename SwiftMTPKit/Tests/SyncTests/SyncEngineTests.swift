// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync

final class SyncEngineTests: XCTestCase {
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

  func testEngineInitialization() {
    let engine = MTPSyncEngine()
    XCTAssertNotNil(engine)
  }

  func testChangeDetectionWithEmptyDirectories() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let changes = await detectChanges(local: localDir, remote: remoteDir)

    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
  }

  func testChangeDetectionWithLocalOnlyFile() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let localFile = localDir.appendingPathComponent("local_only.txt")
    try "local".write(to: localFile, atomically: true, encoding: .utf8)

    let changes = await detectChanges(local: localDir, remote: remoteDir)

    XCTAssertEqual(changes.localOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.count, 0)
  }

  func testChangeDetectionWithRemoteOnlyFile() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    let remoteFile = remoteDir.appendingPathComponent("remote_only.txt")
    try "remote".write(to: remoteFile, atomically: true, encoding: .utf8)

    let changes = await detectChanges(local: localDir, remote: remoteDir)

    XCTAssertEqual(changes.localOnly.count, 0)
    XCTAssertEqual(changes.remoteOnly.count, 1)
  }

  private func detectChanges(local: URL, remote: URL) async -> SyncEngineChanges {
    let localFiles = Set(listRelativeFiles(in: local))
    let remoteFiles = Set(listRelativeFiles(in: remote))
    return SyncEngineChanges(
      localOnly: Array(localFiles.subtracting(remoteFiles)).sorted(),
      remoteOnly: Array(remoteFiles.subtracting(localFiles)).sorted()
    )
  }

  private func listRelativeFiles(in directory: URL) -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else {
        continue
      }
      let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
      files.append(relativePath)
    }
    return files
  }
}

private struct SyncEngineChanges {
  let localOnly: [String]
  let remoteOnly: [String]
}
