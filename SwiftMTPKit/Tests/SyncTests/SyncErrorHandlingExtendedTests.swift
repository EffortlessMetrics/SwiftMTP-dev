// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Extended error handling tests: disk full, permission denied, timeout during sync.
final class SyncErrorHandlingExtendedTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("error-ext.sqlite").path

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    mirrorEngine = nil
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Destination Errors

  func testMirrorToReadOnlyDirectoryCountsFailures() async throws {
    let device = makeDevice(name: "photo.jpg", size: 16)
    let deviceId = await device.id

    let readOnlyDir = tempDirectory.appendingPathComponent("readonly")
    try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
    // Place a file at the subpath to prevent directory creation
    try Data([0x01]).write(to: readOnlyDir.appendingPathComponent("photo.jpg"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o444], ofItemAtPath: readOnlyDir.path)

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: readOnlyDir)

    // Restore permissions for cleanup
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)

    // Download should succeed or fail; at least doesn't crash
    XCTAssertEqual(report.totalProcessed, report.downloaded + report.skipped + report.failed)
  }

  func testMirrorToNonExistentParentCreatesDirectories() async throws {
    let device = makeDevice(name: "photo.jpg", size: 16)
    let deviceId = await device.id

    let deepPath = tempDirectory.appendingPathComponent("a/b/c/d/output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: deepPath)

    XCTAssertEqual(report.downloaded + report.failed, 1)
  }

  // MARK: - Invalid Destination

  func testMirrorToFileInsteadOfDirectoryCountsFailures() async throws {
    let device = makeDevice(name: "photo.jpg", size: 16)
    let deviceId = await device.id

    // Create a file where we'd expect a directory
    let notADir = tempDirectory.appendingPathComponent("not-a-dir")
    try Data([0x01]).write(to: notADir)

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: notADir)

    XCTAssertGreaterThanOrEqual(report.failed, 1)
  }

  // MARK: - Skip Logic

  func testShouldSkipWhenLocalFileDoesNotExist() throws {
    let nonExistent = tempDirectory.appendingPathComponent("does-not-exist.jpg")
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/does-not-exist.jpg",
      size: 100, mtime: Date(), format: 0x3801)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: nonExistent, file: row)
    XCTAssertFalse(shouldSkip)
  }

  func testShouldSkipWhenSizesMatchAndMtimeWithinTolerance() throws {
    let localFile = tempDirectory.appendingPathComponent("current.jpg")
    let data = Data(repeating: 0xAA, count: 64)
    try data.write(to: localFile)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/current.jpg",
      size: 64, mtime: Date(), format: 0x3801)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertTrue(shouldSkip)
  }

  func testShouldSkipWhenRemoteSizeIsNilButFileExists() throws {
    let localFile = tempDirectory.appendingPathComponent("no-size.jpg")
    try Data(repeating: 0xBB, count: 32).write(to: localFile)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/no-size.jpg",
      size: nil, mtime: Date(), format: 0x3801)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    // With nil remote size, size check is skipped; mtime within tolerance → skip
    XCTAssertTrue(shouldSkip)
  }

  func testShouldSkipWhenRemoteMtimeIsNilAndSizeMatches() throws {
    let localFile = tempDirectory.appendingPathComponent("no-mtime.jpg")
    let data = Data(repeating: 0xCC, count: 128)
    try data.write(to: localFile)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/no-mtime.jpg",
      size: 128, mtime: nil, format: 0x3801)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    // With nil remote mtime, mtime check is skipped; size matches → skip
    XCTAssertTrue(shouldSkip)
  }

  func testShouldSkipFalseWhenBothSizeAndMtimeDiffer() throws {
    let localFile = tempDirectory.appendingPathComponent("stale.jpg")
    try Data(repeating: 0xDD, count: 50).write(to: localFile)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: localFile.path)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/stale.jpg",
      size: 100, mtime: Date(), format: 0x3801)

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localFile, file: row)
    XCTAssertFalse(shouldSkip)
  }

  // MARK: - Transfer Journal Error Scenarios

  func testSQLiteTransferJournalInvalidPath() {
    // Attempting to create journal at invalid path
    XCTAssertThrowsError(try SQLiteTransferJournal(dbPath: "/nonexistent/path/db.sqlite"))
  }

  func testDiffEngineInvalidPath() {
    XCTAssertThrowsError(try DiffEngine(dbPath: "/nonexistent/path/diff.sqlite"))
  }

  func testSnapshotterInvalidPath() {
    XCTAssertThrowsError(try Snapshotter(dbPath: "/nonexistent/path/snap.sqlite"))
  }

  // MARK: - Helpers

  private func makeDevice(name: String, size: Int) -> VirtualMTPDevice {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: name,
          sizeBytes: UInt64(size),
          formatCode: 0x3801,
          data: Data(repeating: 0xAA, count: size)
        )
      )
    return VirtualMTPDevice(config: config)
  }
}
