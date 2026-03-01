// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Tests for the glob pattern matching logic in MirrorEngine.
final class GlobPatternTests: XCTestCase {
  private var mirrorEngine: MirrorEngine!
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let dbPath = tempDirectory.appendingPathComponent("glob-tests.sqlite").path
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    mirrorEngine = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Single Wildcard (*)

  func testSingleStarMatchesAnyExtension() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/Camera/*"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/video.mp4", pattern: "DCIM/Camera/*"))
  }

  func testSingleStarDoesNotMatchNestedPath() {
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/sub/photo.jpg", pattern: "DCIM/Camera/*"))
  }

  func testSingleStarWithExtensionFilter() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/Camera/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.png", pattern: "DCIM/Camera/*.jpg"))
  }

  // MARK: - Double Star (**)

  func testDoubleStarMatchesAllPaths() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/any/path/file.txt", pattern: "**"))
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/a", pattern: "**"))
  }

  func testDoubleStarWithSuffix() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "**/*.jpg"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/deep/nested/path/photo.jpg", pattern: "**/*.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.png", pattern: "**/*.jpg"))
  }

  func testDoubleStarWithPrefix() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/**"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/sub/photo.jpg", pattern: "DCIM/**"))
    XCTAssertFalse(mirrorEngine.matchesPattern("00010001/Music/song.mp3", pattern: "DCIM/**"))
  }

  func testDoubleStarWithLeadingSlash() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "/DCIM/**"))
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/anything.txt", pattern: "/**"))
  }

  // MARK: - Exact Match

  func testExactFileNameMatch() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern(
        "00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/Camera/photo.jpg"))
    XCTAssertFalse(
      mirrorEngine.matchesPattern(
        "00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/Camera/other.jpg"))
  }

  // MARK: - Case Insensitivity

  func testPatternMatchingIsCaseInsensitive() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/PHOTO.JPG", pattern: "DCIM/Camera/*.jpg"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/dcim/camera/photo.jpg", pattern: "DCIM/Camera/*.jpg"))
  }

  // MARK: - Special Characters

  func testPatternWithDotsInExtension() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern(
        "00010001/files/document.tar.gz", pattern: "files/document.tar.gz"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/files/document.tar.gz", pattern: "files/*"))
  }

  func testPatternWithParentheses() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera (1)/photo.jpg", pattern: "DCIM/**/*.jpg"))
  }

  // MARK: - Edge Cases

  func testEmptyPathKeyDoesNotMatch() {
    // Storage-only path key with no components
    XCTAssertFalse(mirrorEngine.matchesPattern("00010001", pattern: "DCIM/**"))
  }

  func testPatternMatchesSingleComponentPath() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/file.jpg", pattern: "*.jpg"))
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/file.jpg", pattern: "**/*.jpg"))
  }

  // MARK: - pathKeyToLocalURL

  func testPathKeyToLocalURLBasic() {
    let url = mirrorEngine.pathKeyToLocalURL("00010001/DCIM/photo.jpg", root: tempDirectory)
    XCTAssertTrue(url.path.hasSuffix("/DCIM/photo.jpg"))
  }

  func testPathKeyToLocalURLStorageOnly() {
    let url = mirrorEngine.pathKeyToLocalURL("00010001", root: tempDirectory)
    XCTAssertEqual(url, tempDirectory)
  }
}
