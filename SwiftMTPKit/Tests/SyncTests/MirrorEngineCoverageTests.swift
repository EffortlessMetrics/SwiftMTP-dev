// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

final class MirrorEngineCoverageTests: XCTestCase {
  private var tempDirectory: URL!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let dbPath = tempDirectory.appendingPathComponent("mirror-coverage.sqlite").path
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

  func testMirrorIncludePatternDownloadsMatchingFile() async throws {
    let device = makeSingleFileDevice(name: "photo.jpg", bytes: Data(repeating: 0xAB, count: 16))
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(
      device: device,
      deviceId: deviceId,
      to: tempDirectory,
      includePattern: "**/*.jpg"
    )

    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("photo.jpg").path)
    )
  }

  func testMirrorCountsDownloadedWhenLocalFileAlreadyCurrent() async throws {
    let existingFile = tempDirectory.appendingPathComponent("photo.jpg")
    try Data(repeating: 0xCD, count: 16).write(to: existingFile)

    let device = makeSingleFileDevice(name: "photo.jpg", bytes: Data(repeating: 0xCD, count: 16))
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(
      device: device,
      deviceId: deviceId,
      to: tempDirectory
    )

    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  func testShouldSkipDownloadReturnsFalseWhenMtimeDriftsBeyondTolerance() throws {
    let localURL = tempDirectory.appendingPathComponent("stale.jpg")
    try Data(repeating: 0xEF, count: 16).write(to: localURL)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 0)],
      ofItemAtPath: localURL.path
    )

    let row = MTPDiff.Row(
      handle: 10,
      storage: 0x0001_0001,
      pathKey: "00010001/stale.jpg",
      size: 16,
      mtime: Date(),
      format: 0x3801
    )

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertFalse(shouldSkip)
  }

  func testShouldSkipDownloadReturnsFalseOnSizeMismatch() throws {
    // Create a local file with different size than the remote record
    let localURL = tempDirectory.appendingPathComponent("size-mismatch.jpg")
    try Data(repeating: 0xAA, count: 100).write(to: localURL)  // 100 bytes locally

    let row = MTPDiff.Row(
      handle: 99,
      storage: 0x0001_0001,
      pathKey: "00010001/size-mismatch.jpg",
      size: 200,  // remote claims 200 bytes — mismatch
      mtime: Date(),
      format: 0x3801
    )

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertFalse(shouldSkip, "should not skip when sizes differ")
  }

  func testShouldSkipDownloadReturnsFalseOnTimestampTooOld() throws {
    // Create a local file whose mtime differs from the remote by > 5 minutes
    let localURL = tempDirectory.appendingPathComponent("time-mismatch.jpg")
    let payload = Data(repeating: 0xBB, count: 64)
    try payload.write(to: localURL)
    // Set local mtime to exactly the same size so size check passes
    let staleDate = Date(timeIntervalSinceNow: -3600)  // 1 hour ago
    try FileManager.default.setAttributes(
      [.modificationDate: staleDate], ofItemAtPath: localURL.path)

    let row = MTPDiff.Row(
      handle: 98,
      storage: 0x0001_0001,
      pathKey: "00010001/time-mismatch.jpg",
      size: UInt64(payload.count),  // sizes match
      mtime: Date(),  // remote says "now" — diff > 5 min
      format: 0x3801
    )

    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertFalse(shouldSkip, "should not skip when timestamps differ by > 5 minutes")
  }

  func testGlobDoubleStarCanFailWhenSuffixDoesNotMatch() {
    XCTAssertFalse(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "**/*.png"))
  }

  func testGlobPatternAcceptsLeadingSlash() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "/DCIM/**"))
  }

  func testGlobPatternDoubleStarWithLeadingSlashMatchesEverything() {
    XCTAssertTrue(mirrorEngine.matchesPattern("00010001/DCIM/Camera/photo.jpg", pattern: "/**"))
  }

  private func makeSingleFileDevice(name: String, bytes: Data) -> VirtualMTPDevice {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 42,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: name,
          sizeBytes: UInt64(bytes.count),
          formatCode: 0x3801,
          data: bytes
        )
      )
    return VirtualMTPDevice(config: config)
  }
}
