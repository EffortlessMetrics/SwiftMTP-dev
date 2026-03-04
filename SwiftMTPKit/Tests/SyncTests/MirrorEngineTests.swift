// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPTestKit

final class MirrorEngineTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("sync.sqlite").path

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

  func testMirrorOnEmptyDeviceProducesEmptyReport() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(
      device: device,
      deviceId: deviceId,
      to: tempDirectory
    )

    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.skipped, 0)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  func testPathKeyToLocalURL() {
    let localURL = mirrorEngine.pathKeyToLocalURL(
      "0x00010001/DCIM/Camera/photo.jpg", root: tempDirectory)
    XCTAssertTrue(localURL.path.hasSuffix("/DCIM/Camera/photo.jpg"))
  }

  func testGlobPatternMatching() {
    XCTAssertTrue(
      mirrorEngine.matchesPattern("0x00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/**"))
    XCTAssertTrue(
      mirrorEngine.matchesPattern("0x00010001/DCIM/Camera/photo.jpg", pattern: "DCIM/*/*.jpg"))
    XCTAssertFalse(mirrorEngine.matchesPattern("0x00010001/Music/song.mp3", pattern: "DCIM/**"))
  }

  func testSyncReportSuccessRate() {
    var report = MTPSyncReport()
    XCTAssertEqual(report.successRate, 0.0)

    report.downloaded = 3
    report.skipped = 1
    report.failed = 1
    XCTAssertEqual(report.totalProcessed, 5)
    XCTAssertEqual(report.successRate, 60.0)
  }

  // MARK: - Format Filter Tests

  func testFormatFilterAllPassesEverything() {
    let filter = MTPFormatFilter.all
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.undefined))
  }

  func testFormatFilterCategoryImages() {
    let filter = MTPFormatFilter.category(.images)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.heif))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp4Container))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.text))
  }

  func testFormatFilterCategoryAudio() {
    let filter = MTPFormatFilter.category(.audio)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.flac))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.wav))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp4Container))
  }

  func testFormatFilterCategoryVideo() {
    let filter = MTPFormatFilter.category(.video)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp4Container))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.avi))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mkv))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.exifJPEG))
  }

  func testFormatFilterCategoryDocuments() {
    let filter = MTPFormatFilter.category(.documents)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.text))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.msWordDocument))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.exifJPEG))
  }

  func testFormatFilterIncludingExtensions() {
    let filter = MTPFormatFilter.including(extensions: ["jpg", "png", "heic"])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.heif))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp4Container))
  }

  func testFormatFilterExcludingExtensions() {
    let filter = MTPFormatFilter.excluding(extensions: ["mp4", "avi"])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp4Container))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.avi))
  }

  func testFormatFilterExcludeTakesPrecedenceOverInclude() {
    // If a code is in both include and exclude, exclude wins
    let filter = MTPFormatFilter(
      includeCodes: [PTPObjectFormat.exifJPEG, PTPObjectFormat.png],
      excludeCodes: [PTPObjectFormat.png]
    )
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.png))
  }

  func testFormatFilterExtensionsWithDotPrefix() {
    let filter = MTPFormatFilter.including(extensions: [".jpg", ".png"])
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  func testFormatCategoryAllPassesEverything() {
    let filter = MTPFormatFilter.category(.all)
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.undefined))
  }

  func testMTPFormatCategoryIsCaseIterable() {
    XCTAssertEqual(MTPFormatCategory.allCases.count, 5)
  }
}
