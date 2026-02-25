// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPIndex

final class DiffEngineIntegrationTests: XCTestCase {

  // MARK: - MTPDiff Tests

  func testMTPDiffEmpty() {
    var diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
    XCTAssertTrue(diff.added.isEmpty)
    XCTAssertTrue(diff.removed.isEmpty)
    XCTAssertTrue(diff.modified.isEmpty)
  }

  func testMTPDiffWithAddedFiles() {
    let addedRows = [
      MTPDiff.Row(
        handle: 0x20001, storage: 0x10001, pathKey: "DCIM/photo1.jpg", size: 1024, mtime: Date(),
        format: 0x3801),
      MTPDiff.Row(
        handle: 0x20002, storage: 0x10001, pathKey: "DCIM/photo2.jpg", size: 2048, mtime: Date(),
        format: 0x3801),
    ]

    var diff = MTPDiff()
    diff.added = addedRows

    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 2)
    XCTAssertEqual(diff.added.count, 2)
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 0)
  }

  func testMTPDiffWithRemovedFiles() {
    let removedRows = [
      MTPDiff.Row(
        handle: 0x20001, storage: 0x10001, pathKey: "DCIM/photo1.jpg", size: 1024, mtime: Date(),
        format: 0x3801)
    ]

    var diff = MTPDiff()
    diff.removed = removedRows

    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 1)
    XCTAssertEqual(diff.added.count, 0)
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertEqual(diff.modified.count, 0)
  }

  func testMTPDiffWithModifiedFiles() {
    let modifiedRows = [
      MTPDiff.Row(
        handle: 0x20001, storage: 0x10001, pathKey: "DCIM/photo1.jpg", size: 2048, mtime: Date(),
        format: 0x3801)
    ]

    var diff = MTPDiff()
    diff.modified = modifiedRows

    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 1)
    XCTAssertEqual(diff.added.count, 0)
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 1)
  }

  func testMTPDiffWithMixedChanges() {
    let addedRows = [
      MTPDiff.Row(
        handle: 0x20004, storage: 0x10001, pathKey: "DCIM/new.jpg", size: 500, mtime: Date(),
        format: 0x3801)
    ]

    let removedRows = [
      MTPDiff.Row(
        handle: 0x20003, storage: 0x10001, pathKey: "DCIM/delete.txt", size: 300, mtime: Date(),
        format: 0x3004)
    ]

    let modifiedRows = [
      MTPDiff.Row(
        handle: 0x20002, storage: 0x10001, pathKey: "DCIM/modify.txt", size: 400, mtime: Date(),
        format: 0x3004)
    ]

    var diff = MTPDiff()
    diff.added = addedRows
    diff.removed = removedRows
    diff.modified = modifiedRows

    XCTAssertFalse(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 3)
    XCTAssertEqual(diff.added.count, 1)
    XCTAssertEqual(diff.removed.count, 1)
    XCTAssertEqual(diff.modified.count, 1)
  }

  // MARK: - MTPDiff.Row Tests

  func testMTPDiffRowInitialization() {
    let row = MTPDiff.Row(
      handle: 0x10001,
      storage: 0x10001,
      pathKey: "DCIM/photo.jpg",
      size: 1024,
      mtime: Date(),
      format: 0x3801
    )

    XCTAssertEqual(row.handle, 0x10001)
    XCTAssertEqual(row.storage, 0x10001)
    XCTAssertEqual(row.pathKey, "DCIM/photo.jpg")
    XCTAssertEqual(row.size, 1024)
    XCTAssertNotNil(row.mtime)
    XCTAssertEqual(row.format, 0x3801)
  }

  func testMTPDiffRowWithNilValues() {
    let row = MTPDiff.Row(
      handle: 0x10001,
      storage: 0x10001,
      pathKey: "DCIM",
      size: nil,
      mtime: nil,
      format: 0x3001
    )

    XCTAssertNil(row.size)
    XCTAssertNil(row.mtime)
  }

  // MARK: - DiffEngine Initialization Tests

  func testDiffEngineInitialization() throws {
    let engine = try DiffEngine(dbPath: ":memory:")
    XCTAssertNotNil(engine)
  }

  func testDiffEngineWithInMemoryPath() throws {
    // ":memory:" should work for SQLite in-memory database
    let engine = try DiffEngine(dbPath: ":memory:")
    XCTAssertNotNil(engine)
  }
}
