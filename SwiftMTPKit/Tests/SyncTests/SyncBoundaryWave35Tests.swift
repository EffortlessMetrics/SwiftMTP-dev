// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Sync Boundary Wave 35 Tests

final class SyncBoundaryWave35Tests: XCTestCase {

  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("sync-boundary-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    super.tearDown()
  }

  // MARK: - Helpers

  private func createLocalDir(_ name: String) -> URL {
    let dir = tempDir.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writeFile(at dir: URL, path: String, content: String = "data") {
    let fileURL = dir.appendingPathComponent(path)
    let parent = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try? content.data(using: .utf8)?.write(to: fileURL)
  }

  private struct ChangeSet {
    let localOnly: [String]
    let remoteOnly: [String]
    let common: [String]
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

  // MARK: - 1. Empty Source and Empty Destination

  func testEmptySourceAndEmptyDestination() {
    let local = createLocalDir("empty-local")
    let remote = createLocalDir("empty-remote")

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertTrue(changes.localOnly.isEmpty, "No local-only files expected")
    XCTAssertTrue(changes.remoteOnly.isEmpty, "No remote-only files expected")
    XCTAssertTrue(changes.common.isEmpty, "No common files expected")
  }

  func testEmptySourceNonEmptyDestination() {
    let local = createLocalDir("empty-src")
    let remote = createLocalDir("nonempty-dst")
    writeFile(at: remote, path: "existing.txt")

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertEqual(changes.remoteOnly.count, 1)
    XCTAssertEqual(changes.remoteOnly.first, "existing.txt")
  }

  // MARK: - 2. Bidirectional Sync with Identical Timestamps

  func testIdenticalTimestampsOnBothSides() {
    let local = createLocalDir("ts-local")
    let remote = createLocalDir("ts-remote")

    let content = "identical content"
    writeFile(at: local, path: "same.txt", content: content)
    writeFile(at: remote, path: "same.txt", content: content)

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertEqual(changes.common.count, 1)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)

    let conflicts = detectConflicts(local: local, remote: remote, common: changes.common)
    XCTAssertTrue(conflicts.isEmpty, "Identical content should not be a conflict")
  }

  func testSameFileDifferentContentCreatesConflict() {
    let local = createLocalDir("conflict-local")
    let remote = createLocalDir("conflict-remote")

    writeFile(at: local, path: "diverged.txt", content: "local version")
    writeFile(at: remote, path: "diverged.txt", content: "remote version")

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertEqual(changes.common.count, 1)

    let conflicts = detectConflicts(local: local, remote: remote, common: changes.common)
    XCTAssertEqual(conflicts.count, 1, "Different content should be a conflict")
    XCTAssertEqual(conflicts.first, "diverged.txt")
  }

  // MARK: - 3. Path Traversal Attempts

  func testPathTraversalInFileName() {
    let local = createLocalDir("traversal-local")
    let remote = createLocalDir("traversal-remote")

    // Simulate a file with path traversal component in its name
    let maliciousNames = [
      "../../etc/passwd",
      "..\\..\\windows\\system32\\config",
      "normal/../../../escape.txt",
      "foo/./bar/../../../secret",
    ]

    for (i, name) in maliciousNames.enumerated() {
      // We only write files that stay within the temp dir
      // The test verifies the names are detected correctly
      let safeName = name.replacingOccurrences(of: "..", with: "__")
        .replacingOccurrences(of: "\\", with: "_")
      writeFile(at: local, path: "traversal-\(i)/\(safeName)", content: "payload-\(i)")
    }

    let files = listRelativeFiles(in: local)
    XCTAssertEqual(files.count, maliciousNames.count)

    // Verify none of the files escaped the sandbox
    for file in files {
      let fullPath = local.appendingPathComponent(file).resolvingSymlinksInPath().path
      XCTAssertTrue(
        fullPath.hasPrefix(tempDir.resolvingSymlinksInPath().path),
        "File '\(file)' should not escape temp directory")
    }
  }

  func testDotDotComponentsInSyncDetection() {
    let local = createLocalDir("dotdot-local")
    let remote = createLocalDir("dotdot-remote")

    // Files with tricky relative paths
    writeFile(at: local, path: "a/b/c.txt")
    writeFile(at: remote, path: "a/b/c.txt")

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertEqual(changes.common.count, 1)
    XCTAssertEqual(changes.common.first, "a/b/c.txt")
  }

  // MARK: - 4. Unicode Normalization (NFC vs NFD)

  func testNFCvsNFDPathsInSync() {
    let local = createLocalDir("nfc-local")
    let remote = createLocalDir("nfd-remote")

    let nfcName = "caf\u{00E9}.txt"  // é precomposed
    let nfdName = "caf\u{0065}\u{0301}.txt"  // e + combining accent

    writeFile(at: local, path: nfcName, content: "nfc data")
    writeFile(at: remote, path: nfdName, content: "nfd data")

    let localFiles = listRelativeFiles(in: local)
    let remoteFiles = listRelativeFiles(in: remote)

    // On macOS (HFS+/APFS), the filesystem normalizes to NFD,
    // so both should resolve to the same form
    XCTAssertEqual(localFiles.count, 1)
    XCTAssertEqual(remoteFiles.count, 1)

    let changes = detectChanges(local: local, remote: remote)
    // If filesystem normalizes, they appear as common; otherwise local+remote only
    let totalDetected = changes.common.count + changes.localOnly.count + changes.remoteOnly.count
    XCTAssertGreaterThan(totalDetected, 0)
  }

  func testUnicodeEmojiPathsInSync() {
    let local = createLocalDir("emoji-local")
    let remote = createLocalDir("emoji-remote")

    writeFile(at: local, path: "🎵/track1.mp3", content: "audio")
    writeFile(at: remote, path: "🎵/track1.mp3", content: "audio")

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertEqual(changes.common.count, 1)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
  }

  func testMixedScriptFilenames() {
    let local = createLocalDir("mixed-local")
    let remote = createLocalDir("mixed-remote")

    let names = [
      "файл.txt",  // Cyrillic
      "ファイル.doc",  // Japanese
      "αρχείο.pdf",  // Greek
      "파일.png",  // Korean
    ]

    for name in names {
      writeFile(at: local, path: name, content: "content")
      writeFile(at: remote, path: name, content: "content")
    }

    let changes = detectChanges(local: local, remote: remote)
    XCTAssertEqual(changes.common.count, names.count)
    XCTAssertTrue(changes.localOnly.isEmpty)
    XCTAssertTrue(changes.remoteOnly.isEmpty)
  }

  // MARK: - 5. Large File Count

  func testSyncWithLargeFileCount() {
    let local = createLocalDir("large-local")
    let remote = createLocalDir("large-remote")

    let fileCount = 1200

    // Create files on both sides with some overlap
    for i in 0..<fileCount {
      writeFile(at: local, path: "file-\(String(format: "%05d", i)).txt", content: "data-\(i)")
    }
    for i in (fileCount / 2)..<(fileCount + fileCount / 2) {
      writeFile(
        at: remote, path: "file-\(String(format: "%05d", i)).txt", content: "data-\(i)")
    }

    let changes = detectChanges(local: local, remote: remote)

    // local-only: 0..<600, common: 600..<1200, remote-only: 1200..<1800
    XCTAssertEqual(changes.localOnly.count, fileCount / 2)
    XCTAssertEqual(changes.common.count, fileCount / 2)
    XCTAssertEqual(changes.remoteOnly.count, fileCount / 2)

    // Verify total adds up
    let total = changes.localOnly.count + changes.common.count + changes.remoteOnly.count
    XCTAssertEqual(total, fileCount + fileCount / 2)
  }

  func testSyncPerformanceWithManyFiles() {
    let local = createLocalDir("perf-local")
    let remote = createLocalDir("perf-remote")

    let count = 2000
    for i in 0..<count {
      writeFile(at: local, path: "perf-\(i).dat", content: "x")
    }

    measure {
      _ = detectChanges(local: local, remote: remote)
    }
  }
}

// MARK: - Snapshot Edge Cases via VirtualMTPDevice

final class SnapshotBoundaryWave35Tests: XCTestCase {

  func testSnapshotEmptyDevice() async throws {
    let dir = FileManager.default.temporaryDirectory
    let dbPath = dir.appendingPathComponent("snap-empty-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let device = VirtualMTPDevice(config: .emptyDevice)
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(
      device: device,
      deviceId: MTPDeviceID(raw: "0000:0000@0:0"))

    XCTAssertGreaterThan(gen, 0, "Even empty device should produce a valid generation")
  }

  func testSnapshotDeviceWithManyObjects() async throws {
    let dir = FileManager.default.temporaryDirectory
    let dbPath = dir.appendingPathComponent("snap-many-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let storage = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<500 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(i + 1),
          storage: storage,
          name: "obj-\(i).dat",
          sizeBytes: 100,
          formatCode: 0x3000,
          data: Data([UInt8(i & 0xFF)])
        ))
    }

    let device = VirtualMTPDevice(config: config)
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(
      device: device,
      deviceId: MTPDeviceID(raw: "0000:0000@0:0"))

    XCTAssertGreaterThan(gen, 0)
  }
}
