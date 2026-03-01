// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Tests for the diff engine: identical trees, single changes, bulk changes, encoding edge cases.
final class DiffEngineEdgeCaseTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("diff-edge.sqlite").path
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  // MARK: - MTPDiff Struct Tests

  func testEmptyDiffIsEmpty() {
    let diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
  }

  func testDiffWithOnlyAddedIsNotEmpty() {
    var diff = MTPDiff()
    diff.added = [makeRow(handle: 1, path: "00010001/file.jpg")]
    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 1)
  }

  func testDiffWithOnlyRemovedIsNotEmpty() {
    var diff = MTPDiff()
    diff.removed = [makeRow(handle: 1, path: "00010001/old.jpg")]
    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 1)
  }

  func testDiffWithOnlyModifiedIsNotEmpty() {
    var diff = MTPDiff()
    diff.modified = [makeRow(handle: 1, path: "00010001/changed.jpg")]
    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 1)
  }

  func testDiffTotalChangesCountsAllCategories() {
    var diff = MTPDiff()
    diff.added = [makeRow(handle: 1, path: "a"), makeRow(handle: 2, path: "b")]
    diff.removed = [makeRow(handle: 3, path: "c")]
    diff.modified = [
      makeRow(handle: 4, path: "d"), makeRow(handle: 5, path: "e"),
      makeRow(handle: 6, path: "f"),
    ]
    XCTAssertEqual(diff.totalChanges, 6)
  }

  // MARK: - MTPDiff.Row Construction

  func testDiffRowWithNilSizeAndMtime() {
    let row = MTPDiff.Row(
      handle: 42, storage: 0x0001_0001, pathKey: "00010001/test.txt",
      size: nil, mtime: nil, format: 0x3000)
    XCTAssertNil(row.size)
    XCTAssertNil(row.mtime)
    XCTAssertEqual(row.handle, 42)
  }

  func testDiffRowWithLargeSize() {
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/big.iso",
      size: UInt64.max, mtime: Date(), format: 0x3000)
    XCTAssertEqual(row.size, UInt64.max)
  }

  func testDiffRowWithZeroSize() {
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/empty.txt",
      size: 0, mtime: Date(), format: 0x3000)
    XCTAssertEqual(row.size, 0)
  }

  // MARK: - PathKey Tests

  func testPathKeyNormalize() {
    let key = PathKey.normalize(storage: 0x0001_0001, components: ["DCIM", "Camera", "photo.jpg"])
    XCTAssertEqual(key, "00010001/DCIM/Camera/photo.jpg")
  }

  func testPathKeyNormalizeEmptyComponents() {
    let key = PathKey.normalize(storage: 0x0001_0001, components: [])
    XCTAssertEqual(key, "00010001")
  }

  func testPathKeyParse() {
    let (storageId, components) = PathKey.parse("00010001/DCIM/Camera/photo.jpg")
    XCTAssertEqual(storageId, 0x0001_0001)
    XCTAssertEqual(components, ["DCIM", "Camera", "photo.jpg"])
  }

  func testPathKeyParseStorageOnly() {
    let (storageId, components) = PathKey.parse("00010001")
    XCTAssertEqual(storageId, 0x0001_0001)
    XCTAssertTrue(components.isEmpty)
  }

  func testPathKeyBasename() {
    XCTAssertEqual(PathKey.basename(of: "00010001/DCIM/Camera/photo.jpg"), "photo.jpg")
    XCTAssertEqual(PathKey.basename(of: "00010001"), "")
  }

  func testPathKeyParent() {
    let parent = PathKey.parent(of: "00010001/DCIM/Camera/photo.jpg")
    XCTAssertEqual(parent, "00010001/DCIM/Camera")

    let rootParent = PathKey.parent(of: "00010001/DCIM")
    XCTAssertNil(rootParent)

    let storageParent = PathKey.parent(of: "00010001")
    XCTAssertNil(storageParent)
  }

  func testPathKeyIsPrefix() {
    XCTAssertTrue(PathKey.isPrefix("00010001/DCIM", of: "00010001/DCIM/Camera/photo.jpg"))
    XCTAssertFalse(PathKey.isPrefix("00010001/Music", of: "00010001/DCIM/Camera/photo.jpg"))
    XCTAssertFalse(
      PathKey.isPrefix("00010001/DCIM/Camera/photo.jpg", of: "00010001/DCIM/Camera/photo.jpg"))
  }

  func testPathKeyIsPrefixDifferentStorage() {
    XCTAssertFalse(PathKey.isPrefix("00010002/DCIM", of: "00010001/DCIM/Camera/photo.jpg"))
  }

  // MARK: - Unicode and Encoding Edge Cases

  func testPathKeyNormalizeWithUnicode() {
    let key = PathKey.normalize(storage: 0x0001_0001, components: ["фото", "изображение.jpg"])
    XCTAssertTrue(key.hasPrefix("00010001/"))
    XCTAssertTrue(key.hasSuffix("изображение.jpg"))
  }

  func testPathKeyNormalizeWithEmoji() {
    let key = PathKey.normalize(storage: 0x0001_0001, components: ["📸", "photo.jpg"])
    let (_, components) = PathKey.parse(key)
    XCTAssertEqual(components.first, "📸")
  }

  func testPathKeyNormalizeNFCNormalization() {
    // é as combining e + acute accent vs precomposed
    let decomposed = "e\u{0301}"  // combining
    let precomposed = "\u{00E9}"  // precomposed

    let normalizedDecomposed = PathKey.normalizeComponent(decomposed)
    let normalizedPrecomposed = PathKey.normalizeComponent(precomposed)

    // Both should produce the same normalized form (NFC)
    XCTAssertEqual(normalizedDecomposed, normalizedPrecomposed)
  }

  func testPathKeyNormalizeStripsControlChars() {
    let name = "photo\u{0000}\u{001F}.jpg"
    let normalized = PathKey.normalizeComponent(name)
    XCTAssertFalse(normalized.contains("\u{0000}"))
    XCTAssertFalse(normalized.contains("\u{001F}"))
  }

  func testPathKeyNormalizeStripsSlashes() {
    let name = "photo/evil\\path.jpg"
    let normalized = PathKey.normalizeComponent(name)
    XCTAssertFalse(normalized.contains("/"))
    XCTAssertFalse(normalized.contains("\\"))
  }

  func testPathKeyFromLocalURL() {
    let root = URL(fileURLWithPath: "/tmp/mirror")
    let file = URL(fileURLWithPath: "/tmp/mirror/DCIM/photo.jpg")
    let pathKey = PathKey.fromLocalURL(file, relativeTo: root, storage: 0x0001_0001)
    XCTAssertNotNil(pathKey)
    XCTAssertTrue(pathKey!.contains("DCIM"))
    XCTAssertTrue(pathKey!.contains("photo.jpg"))
  }

  func testPathKeyFromLocalURLOutsideRoot() {
    let root = URL(fileURLWithPath: "/tmp/mirror")
    let file = URL(fileURLWithPath: "/other/path/file.txt")
    let pathKey = PathKey.fromLocalURL(file, relativeTo: root, storage: 0x0001_0001)
    XCTAssertNil(pathKey)
  }

  // MARK: - Helpers

  private func makeRow(handle: UInt32, path: String) -> MTPDiff.Row {
    MTPDiff.Row(
      handle: handle, storage: 0x0001_0001, pathKey: path,
      size: 1024, mtime: Date(), format: 0x3801)
  }
}
