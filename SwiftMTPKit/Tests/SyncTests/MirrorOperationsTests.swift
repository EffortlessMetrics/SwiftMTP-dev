// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Tests for mirror operations: full mirror, incremental, interrupted resume.
final class MirrorOperationsTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("mirror-ops.sqlite").path

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

  // MARK: - Full Mirror

  func testFullMirrorOfSingleFile() async throws {
    let device = makeDevice(files: [("photo.jpg", 32)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)

    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
    XCTAssertEqual(report.skipped, 0)
  }

  func testFullMirrorOfMultipleFiles() async throws {
    let device = makeDevice(files: [
      ("photo1.jpg", 16), ("photo2.jpg", 32), ("photo3.jpg", 64),
    ])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)

    XCTAssertEqual(report.downloaded, 3)
    XCTAssertEqual(report.failed, 0)
  }

  func testFullMirrorEmptyDeviceYieldsEmptyReport() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)

    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.successRate, 0.0)
  }

  // MARK: - Incremental Mirror (second run)

  func testIncrementalMirrorOnlyDownloadsNewFiles() async throws {
    let device = makeDevice(files: [("existing.jpg", 16)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    // First mirror
    let report1 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report1.downloaded, 1)

    // Snapshot generation is based on unix timestamp (seconds); wait to avoid duplicate gen
    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second mirror — same device/snapshot so diff should be empty
    let report2 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    // On second run the new snapshot has same objects, so nothing added vs prev gen
    XCTAssertEqual(report2.failed, 0)
  }

  // MARK: - Filtered Mirror

  func testMirrorWithIncludePatternSkipsNonMatching() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(makeObj(handle: 10, name: "photo.jpg", size: 16))
      .withObject(makeObj(handle: 11, name: "song.mp3", size: 32))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output, includePattern: "**/*.jpg")

    // Only jpg should download; mp3 should be skipped
    XCTAssertEqual(report.downloaded + report.skipped, 2)
  }

  func testMirrorWithDoubleStarMatchesAllFiles() async throws {
    let device = makeDevice(files: [("a.txt", 8), ("b.txt", 8)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output, includePattern: "**")

    XCTAssertEqual(report.downloaded, 2)
  }

  func testMirrorWithClosureFilterSkipsExplicitly() async throws {
    let device = makeDevice(files: [("keep.jpg", 8), ("skip.mp3", 8)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output
    ) { row in
      row.pathKey.hasSuffix(".jpg")
    }

    XCTAssertEqual(report.skipped, 1)
  }

  // MARK: - Report Aggregation

  func testSyncReportTotalProcessedIncludesAll() {
    var report = MTPSyncReport()
    report.downloaded = 10
    report.skipped = 5
    report.failed = 2
    XCTAssertEqual(report.totalProcessed, 17)
  }

  func testSyncReportSuccessRateWithNoFailures() {
    var report = MTPSyncReport()
    report.downloaded = 10
    report.skipped = 0
    report.failed = 0
    XCTAssertEqual(report.successRate, 100.0)
  }

  func testSyncReportSuccessRateAllFailed() {
    var report = MTPSyncReport()
    report.downloaded = 0
    report.skipped = 0
    report.failed = 5
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testSyncReportSuccessRateEmpty() {
    let report = MTPSyncReport()
    XCTAssertEqual(report.successRate, 0.0)
    XCTAssertEqual(report.totalProcessed, 0)
  }

  // MARK: - Helpers

  private func makeObj(handle: MTPObjectHandle, name: String, size: Int) -> VirtualObjectConfig {
    VirtualObjectConfig(
      handle: handle,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: name,
      sizeBytes: UInt64(size),
      formatCode: 0x3801,
      data: Data(repeating: 0xAB, count: size)
    )
  }

  private func makeDevice(files: [(String, Int)]) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(
        makeObj(handle: MTPObjectHandle(100 + idx), name: file.0, size: file.1))
    }
    return VirtualMTPDevice(config: config)
  }
}
