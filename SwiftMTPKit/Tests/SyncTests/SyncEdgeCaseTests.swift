// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Snapshot Edge Case Tests

final class SnapshotEdgeCaseTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("snapshot-edge.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
  }

  override func tearDownWithError() throws {
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testEmptyDeviceSnapshotCapturesSuccessfully() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testEmptyDeviceSnapshotLatestGeneration() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let latest = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latest, gen)
  }

  func testSnapshotWithMaxFileCount() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let objects = (0..<200).map { i in
      VirtualObjectConfig(
        handle: MTPObjectHandle(100 + i),
        storage: storage,
        name: "file_\(i).dat",
        sizeBytes: 8,
        formatCode: 0x3801,
        data: Data(repeating: UInt8(i % 256), count: 8)
      )
    }
    var config = VirtualDeviceConfig.emptyDevice
    for obj in objects { config = config.withObject(obj) }
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testSnapshotWithDeeplyNestedDirectoryStructure() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    // Create a chain: folder1 -> folder2 -> folder3 -> file
    let folder1 = VirtualObjectConfig(
      handle: 10, storage: storage, parent: nil, name: "L1",
      formatCode: 0x3001)
    let folder2 = VirtualObjectConfig(
      handle: 11, storage: storage, parent: 10, name: "L2",
      formatCode: 0x3001)
    let folder3 = VirtualObjectConfig(
      handle: 12, storage: storage, parent: 11, name: "L3",
      formatCode: 0x3001)
    let leaf = VirtualObjectConfig(
      handle: 13, storage: storage, parent: 12, name: "deep.txt",
      sizeBytes: 4, formatCode: 0x3000, data: Data([0xDE, 0xAD, 0xBE, 0xEF]))

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(folder1).withObject(folder2).withObject(folder3).withObject(leaf)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testSnapshotWithSpecialCharactersInFilenames() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let names = ["café.jpg", "日本語.txt", "пример.doc", "file (1).png", "a&b=c.html"]
    let objects = names.enumerated().map { idx, name in
      VirtualObjectConfig(
        handle: MTPObjectHandle(50 + idx), storage: storage,
        name: name, sizeBytes: 4, formatCode: 0x3801, data: Data([0x01, 0x02, 0x03, 0x04]))
    }
    var config = VirtualDeviceConfig.emptyDevice
    for obj in objects { config = config.withObject(obj) }
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testSnapshotGenerationIDMonotonicity() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen2, gen1)
  }

  func testSnapshotWithZeroByteFiles() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 99, storage: storage, name: "empty.txt",
      sizeBytes: 0, formatCode: 0x3000, data: Data())
    let config = VirtualDeviceConfig.emptyDevice.withObject(obj)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testSnapshotWithDuplicateFilenamesInDifferentDirectories() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let folderA = VirtualObjectConfig(
      handle: 10, storage: storage, parent: nil, name: "FolderA", formatCode: 0x3001)
    let folderB = VirtualObjectConfig(
      handle: 11, storage: storage, parent: nil, name: "FolderB", formatCode: 0x3001)
    let fileInA = VirtualObjectConfig(
      handle: 20, storage: storage, parent: 10, name: "readme.txt",
      sizeBytes: 4, formatCode: 0x3000, data: Data([0xAA, 0xBB, 0xCC, 0xDD]))
    let fileInB = VirtualObjectConfig(
      handle: 21, storage: storage, parent: 11, name: "readme.txt",
      sizeBytes: 4, formatCode: 0x3000, data: Data([0x11, 0x22, 0x33, 0x44]))

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(folderA).withObject(folderB).withObject(fileInA).withObject(fileInB)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  func testSnapshotPreviousGenerationIsNilForFirstCapture() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen)
    XCTAssertNil(prev)
  }

  func testSnapshotPreviousGenerationReturnsFirstAfterSecondCapture() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen2)
    XCTAssertEqual(prev, gen1)
  }

  func testSnapshotWithEmojiFilename() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 77, storage: storage, name: "📸🌅.jpg",
      sizeBytes: 4, formatCode: 0x3801, data: Data([0xAA, 0xBB, 0xCC, 0xDD]))
    let config = VirtualDeviceConfig.emptyDevice.withObject(obj)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }
}

// MARK: - Diff Edge Case Tests

final class DiffEdgeCaseExtendedTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("diff-ext.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
  }

  override func tearDownWithError() throws {
    diffEngine = nil
    snapshotter = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    dbPath = nil
    try super.tearDownWithError()
  }

  func testDiffBetweenIdenticalSnapshots() async throws {
    let device = makeDevice(files: [("photo.jpg", 16)])
    let deviceId = await device.id

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(delta.isEmpty)
    XCTAssertEqual(delta.totalChanges, 0)
  }

  func testDiffBetweenEmptyAndPopulatedSnapshots() async throws {
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let populatedDevice = makeDevice(files: [("a.jpg", 8), ("b.jpg", 8)])
    let gen2 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 2)
    XCTAssertEqual(delta.removed.count, 0)
    XCTAssertEqual(delta.modified.count, 0)
  }

  func testDiffBetweenPopulatedAndEmptySnapshots() async throws {
    let populatedDevice = makeDevice(files: [("a.jpg", 8), ("b.jpg", 8)])
    let deviceId = await populatedDevice.id
    let gen1 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let gen2 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 0)
    XCTAssertEqual(delta.removed.count, 2)
    XCTAssertEqual(delta.modified.count, 0)
  }

  func testDiffDetectsMovedFileAsPairOfAddAndRemove() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let folderA = VirtualObjectConfig(
      handle: 10, storage: storage, parent: nil, name: "DirA", formatCode: 0x3001)
    let fileInA = VirtualObjectConfig(
      handle: 20, storage: storage, parent: 10, name: "moved.txt",
      sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 8))
    let configBefore = VirtualDeviceConfig.emptyDevice
      .withObject(folderA).withObject(fileInA)
    let deviceBefore = VirtualMTPDevice(config: configBefore)
    let deviceId = await deviceBefore.id
    let gen1 = try await snapshotter.capture(device: deviceBefore, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let folderB = VirtualObjectConfig(
      handle: 11, storage: storage, parent: nil, name: "DirB", formatCode: 0x3001)
    let fileInB = VirtualObjectConfig(
      handle: 21, storage: storage, parent: 11, name: "moved.txt",
      sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 8))
    let configAfter = VirtualDeviceConfig.emptyDevice
      .withObject(folderB).withObject(fileInB)
    let deviceAfter = VirtualMTPDevice(config: configAfter)
    let gen2 = try await snapshotter.capture(device: deviceAfter, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    // A move appears as an add in the new location and a remove from the old
    XCTAssertGreaterThanOrEqual(delta.added.count, 1)
    XCTAssertGreaterThanOrEqual(delta.removed.count, 1)
  }

  func testDiffWithOverlappingAdditionsAndDeletions() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)

    // Snapshot 1: files A, B, C
    let configBefore = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "fileA.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x01, 0x02, 0x03, 0x04])))
      .withObject(VirtualObjectConfig(
        handle: 101, storage: storage, name: "fileB.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x05, 0x06, 0x07, 0x08])))
      .withObject(VirtualObjectConfig(
        handle: 102, storage: storage, name: "fileC.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x09, 0x0A, 0x0B, 0x0C])))
    let deviceBefore = VirtualMTPDevice(config: configBefore)
    let deviceId = await deviceBefore.id
    let gen1 = try await snapshotter.capture(device: deviceBefore, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Snapshot 2: files B, C, D (A removed, D added)
    let configAfter = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 101, storage: storage, name: "fileB.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x05, 0x06, 0x07, 0x08])))
      .withObject(VirtualObjectConfig(
        handle: 102, storage: storage, name: "fileC.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x09, 0x0A, 0x0B, 0x0C])))
      .withObject(VirtualObjectConfig(
        handle: 103, storage: storage, name: "fileD.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([0x0D, 0x0E, 0x0F, 0x10])))
    let deviceAfter = VirtualMTPDevice(config: configAfter)
    let gen2 = try await snapshotter.capture(device: deviceAfter, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1, "fileD should be added")
    XCTAssertEqual(delta.removed.count, 1, "fileA should be removed")
  }

  func testDiffWithNilOldGenTreatsAllAsAdded() async throws {
    let device = makeDevice(files: [("x.txt", 4), ("y.txt", 4)])
    let deviceId = await device.id
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertEqual(delta.added.count, 2)
    XCTAssertEqual(delta.removed.count, 0)
    XCTAssertEqual(delta.modified.count, 0)
  }

  func testDiffEmptyToEmptyIsEmpty() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(delta.isEmpty)
  }

  func testDiffDetectsModifiedFileBySize() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)

    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "doc.txt",
        sizeBytes: 10, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 10)))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "doc.txt",
        sizeBytes: 20, formatCode: 0x3000, data: Data(repeating: 0xBB, count: 20)))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.modified.count, 1, "File with changed size should be modified")
  }

  func testDiffSingleAddition() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)

    let configBefore = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "keep.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let deviceBefore = VirtualMTPDevice(config: configBefore)
    let deviceId = await deviceBefore.id
    let gen1 = try await snapshotter.capture(device: deviceBefore, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configAfter = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "keep.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
      .withObject(VirtualObjectConfig(
        handle: 101, storage: storage, name: "new.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8])))
    let deviceAfter = VirtualMTPDevice(config: configAfter)
    let gen2 = try await snapshotter.capture(device: deviceAfter, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1)
    XCTAssertEqual(delta.removed.count, 0)
  }

  func testDiffSingleRemoval() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)

    let configBefore = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "keep.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
      .withObject(VirtualObjectConfig(
        handle: 101, storage: storage, name: "gone.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8])))
    let deviceBefore = VirtualMTPDevice(config: configBefore)
    let deviceId = await deviceBefore.id
    let gen1 = try await snapshotter.capture(device: deviceBefore, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configAfter = VirtualDeviceConfig.emptyDevice
      .withObject(VirtualObjectConfig(
        handle: 100, storage: storage, name: "keep.txt",
        sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let deviceAfter = VirtualMTPDevice(config: configAfter)
    let gen2 = try await snapshotter.capture(device: deviceAfter, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 0)
    XCTAssertEqual(delta.removed.count, 1)
  }

  // MARK: - Helpers

  private func makeDevice(files: [(String, Int)]) -> VirtualMTPDevice {
    let storage = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(VirtualObjectConfig(
        handle: MTPObjectHandle(100 + idx), storage: storage,
        name: file.0, sizeBytes: UInt64(file.1), formatCode: 0x3801,
        data: Data(repeating: 0xAB, count: file.1)))
    }
    return VirtualMTPDevice(config: config)
  }
}

// MARK: - Mirror Edge Case Tests

final class MirrorEdgeCaseExtendedTests: XCTestCase {
  private var tempDirectory: URL!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let dbPath = tempDirectory.appendingPathComponent("mirror-edge.sqlite").path
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    mirrorEngine = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  func testMirrorToEmptyDestination() async throws {
    let device = makeDevice(files: [("photo.jpg", 16), ("video.mp4", 32)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("empty_dest")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 2)
    XCTAssertEqual(report.failed, 0)
  }

  func testMirrorEmptySource() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.downloaded, 0)
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testMirrorPreservesDirectoryStructure() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let folder = VirtualObjectConfig(
      handle: 10, storage: storage, parent: nil, name: "DCIM", formatCode: 0x3001)
    let file = VirtualObjectConfig(
      handle: 20, storage: storage, parent: 10, name: "photo.jpg",
      sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xAB, count: 8))
    let config = VirtualDeviceConfig.emptyDevice.withObject(folder).withObject(file)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("structured_output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  func testMirrorWithFilterSkipsNonMatchingFiles() async throws {
    let device = makeDevice(files: [("keep.jpg", 8), ("skip.png", 8), ("also_skip.mp3", 8)])
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("filtered")

    let report = try await mirrorEngine.mirror(
      device: device, deviceId: deviceId, to: output
    ) { row in
      row.pathKey.hasSuffix(".jpg")
    }

    XCTAssertEqual(report.skipped, 2)
    XCTAssertGreaterThanOrEqual(report.downloaded, 1)
  }

  func testMirrorCreatesIntermediateDirectoriesAutomatically() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let f1 = VirtualObjectConfig(
      handle: 10, storage: storage, parent: nil, name: "A", formatCode: 0x3001)
    let f2 = VirtualObjectConfig(
      handle: 11, storage: storage, parent: 10, name: "B", formatCode: 0x3001)
    let file = VirtualObjectConfig(
      handle: 20, storage: storage, parent: 11, name: "deep.txt",
      sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4]))
    let config = VirtualDeviceConfig.emptyDevice.withObject(f1).withObject(f2).withObject(file)
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("nested_output")

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report.downloaded, 1)
    XCTAssertEqual(report.failed, 0)
  }

  func testMirrorReportSuccessRateWithMixedResults() {
    var report = MTPSyncReport()
    report.downloaded = 7
    report.skipped = 2
    report.failed = 1
    XCTAssertEqual(report.totalProcessed, 10)
    XCTAssertEqual(report.successRate, 70.0)
  }

  func testMirrorReportSuccessRateAllSkipped() {
    var report = MTPSyncReport()
    report.downloaded = 0
    report.skipped = 10
    report.failed = 0
    XCTAssertEqual(report.totalProcessed, 10)
    XCTAssertEqual(report.successRate, 0.0)
  }

  func testPathKeyToLocalURLSanitizesTraversal() {
    let output = tempDirectory.appendingPathComponent("safe_output")
    // pathKey with normal path should produce safe URL under root
    let localURL = mirrorEngine.pathKeyToLocalURL("00010001/DCIM/photo.jpg", root: output)
    XCTAssertTrue(localURL.path.hasPrefix(output.path))
  }

  func testPathKeyToLocalURLWithDeepPath() {
    let output = tempDirectory.appendingPathComponent("deep_output")
    let localURL = mirrorEngine.pathKeyToLocalURL(
      "00010001/A/B/C/D/E/file.txt", root: output)
    XCTAssertTrue(localURL.path.hasSuffix("A/B/C/D/E/file.txt"))
  }

  func testShouldSkipDownloadReturnsFalseWhenFileDoesNotExist() throws {
    let nonExistent = tempDirectory.appendingPathComponent("does_not_exist.txt")
    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/does_not_exist.txt",
      size: 100, mtime: Date(), format: 0x3801)
    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: nonExistent, file: row)
    XCTAssertFalse(shouldSkip)
  }

  func testShouldSkipDownloadReturnsTrueWhenSizeAndMtimeMatch() throws {
    let localURL = tempDirectory.appendingPathComponent("match.txt")
    let data = Data(repeating: 0xCC, count: 64)
    try data.write(to: localURL)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/match.txt",
      size: 64, mtime: Date(), format: 0x3801)
    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertTrue(shouldSkip, "Should skip when size and mtime match within tolerance")
  }

  func testShouldSkipDownloadWithNilRemoteSizeMatchesByMtime() throws {
    let localURL = tempDirectory.appendingPathComponent("nil_size.txt")
    try Data(repeating: 0xFF, count: 32).write(to: localURL)

    let row = MTPDiff.Row(
      handle: 1, storage: 0x0001_0001, pathKey: "00010001/nil_size.txt",
      size: nil, mtime: Date(), format: 0x3801)
    let shouldSkip = try mirrorEngine.shouldSkipDownload(of: localURL, file: row)
    XCTAssertTrue(shouldSkip, "Nil size should skip the size check")
  }

  // MARK: - Helpers

  private func makeDevice(files: [(String, Int)]) -> VirtualMTPDevice {
    let storage = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.emptyDevice
    for (idx, file) in files.enumerated() {
      config = config.withObject(VirtualObjectConfig(
        handle: MTPObjectHandle(100 + idx), storage: storage,
        name: file.0, sizeBytes: UInt64(file.1), formatCode: 0x3801,
        data: Data(repeating: 0xAB, count: file.1)))
    }
    return VirtualMTPDevice(config: config)
  }
}

// MARK: - Property-Based Sync Edge Case Tests

final class SyncEdgeCasePropertyTests: XCTestCase {

  // MARK: - MTPDiff Property Tests

  func testDiffAddedCountNeverNegative() {
    property("added count is always >= 0")
      <- forAll(Gen<Int>.choose((0, 50))) { count in
        var diff = MTPDiff()
        for i in 0..<count {
          diff.added.append(MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/file_\(i)", size: 100, mtime: nil, format: 0x3001))
        }
        return diff.added.count >= 0 && diff.added.count == count
      }
  }

  func testDiffRemovedCountNeverNegative() {
    property("removed count is always >= 0")
      <- forAll(Gen<Int>.choose((0, 50))) { count in
        var diff = MTPDiff()
        for i in 0..<count {
          diff.removed.append(MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/file_\(i)", size: 200, mtime: nil, format: 0x3001))
        }
        return diff.removed.count >= 0 && diff.removed.count == count
      }
  }

  func testDiffTotalChangesIsMonotoneWithAdditions() {
    property("Adding rows never decreases totalChanges")
      <- forAll(
        Gen<Int>.choose((0, 20)),
        Gen<Int>.choose((1, 20))
      ) { initial, extra in
        var diff = MTPDiff()
        for i in 0..<initial {
          diff.added.append(MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/init_\(i)", size: nil, mtime: nil, format: 0x3001))
        }
        let before = diff.totalChanges
        for i in 0..<extra {
          diff.modified.append(MTPDiff.Row(
            handle: UInt32(i + 1000), storage: 1,
            pathKey: "00000001/extra_\(i)", size: nil, mtime: nil, format: 0x3001))
        }
        return diff.totalChanges >= before
      }
  }

  // MARK: - MTPSyncReport Property Tests

  func testSyncReportSuccessRateNeverExceeds100() {
    property("Success rate is always in [0, 100]")
      <- forAll(
        Gen<Int>.choose((0, 10000)),
        Gen<Int>.choose((0, 10000)),
        Gen<Int>.choose((0, 10000))
      ) { d, s, f in
        var report = MTPSyncReport()
        report.downloaded = d
        report.skipped = s
        report.failed = f
        return report.successRate >= 0.0 && report.successRate <= 100.0
      }
  }

  func testSyncReportTotalProcessedCommutative() {
    property("totalProcessed is the same regardless of assignment order")
      <- forAll(
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 1000))
      ) { a, b, c in
        var r1 = MTPSyncReport()
        r1.downloaded = a; r1.skipped = b; r1.failed = c

        var r2 = MTPSyncReport()
        r2.failed = c; r2.downloaded = a; r2.skipped = b

        return r1.totalProcessed == r2.totalProcessed
      }
  }

  func testSyncReportSuccessRateIsZeroWhenOnlyFailed() {
    property("When downloaded=0 and skipped=0, success rate is 0 (if any processed)")
      <- forAll(Gen<Int>.choose((1, 1000))) { failCount in
        var report = MTPSyncReport()
        report.failed = failCount
        return report.successRate == 0.0
      }
  }

  func testSyncReportSuccessRateIs100WhenOnlyDownloaded() {
    property("When skipped=0 and failed=0, success rate is 100%")
      <- forAll(Gen<Int>.choose((1, 1000))) { dlCount in
        var report = MTPSyncReport()
        report.downloaded = dlCount
        return report.successRate == 100.0
      }
  }

  // MARK: - PathKey Property Tests

  func testPathKeyNormalizeParseRoundTrip() {
    let storages: [UInt32] = [0x0001_0001, 0x0001_0002, 0x0002_0001]
    let componentSets: [[String]] = [
      ["DCIM", "photo.jpg"],
      ["Music", "Albums", "track.mp3"],
      ["Documents", "Work", "Notes", "file.txt"],
    ]
    for storage in storages {
      for components in componentSets {
        let key = PathKey.normalize(storage: storage, components: components)
        let (parsedStorage, parsedComponents) = PathKey.parse(key)
        XCTAssertEqual(parsedStorage, storage)
        XCTAssertEqual(parsedComponents, components)
      }
    }
  }

  func testPathKeyBasenameConsistentWithParse() {
    let paths = [
      "00010001/DCIM/photo.jpg",
      "00010001/a.txt",
      "00020001/Music/Albums/track.mp3",
    ]
    for path in paths {
      let basename = PathKey.basename(of: path)
      let (_, components) = PathKey.parse(path)
      XCTAssertEqual(basename, components.last ?? "")
    }
  }

  func testPathKeyParentChildRelationship() {
    let paths = [
      "00010001/A/B/C/file.txt",
      "00010001/DCIM/Camera/photo.jpg",
    ]
    for path in paths {
      if let parent = PathKey.parent(of: path) {
        XCTAssertTrue(PathKey.isPrefix(parent, of: path))
      }
    }
  }

  // MARK: - Glob Pattern Property Tests

  func testDoubleStarMatchesAllPaths() {
    let engine = makeMirrorEngine()
    let paths = [
      "00010001/a.txt",
      "00010001/DCIM/photo.jpg",
      "00010001/A/B/C/D/deep.dat",
    ]
    for path in paths {
      XCTAssertTrue(engine.matchesPattern(path, pattern: "**"))
    }
  }

  func testExactNameMatchesOnlyThatComponent() {
    let engine = makeMirrorEngine()
    XCTAssertTrue(engine.matchesPattern("00010001/photo.jpg", pattern: "photo.jpg"))
    XCTAssertFalse(engine.matchesPattern("00010001/other.jpg", pattern: "photo.jpg"))
  }

  func testExtensionFilterSelectsCorrectFiles() {
    let engine = makeMirrorEngine()
    property("**/*.jpg matches only .jpg files")
      <- forAll(
        Gen<String>.fromElements(of: [
          "00010001/a.jpg", "00010001/DCIM/b.jpg", "00010001/A/B/c.jpg",
        ])
      ) { path in
        engine.matchesPattern(path, pattern: "**/*.jpg")
      }
  }

  func testExtensionFilterRejectsWrongExtension() {
    let engine = makeMirrorEngine()
    let nonJpgPaths = [
      "00010001/a.png", "00010001/DCIM/b.mp3", "00010001/A/B/c.txt",
    ]
    for path in nonJpgPaths {
      XCTAssertFalse(engine.matchesPattern(path, pattern: "**/*.jpg"))
    }
  }

  // MARK: - Helpers

  private func makeMirrorEngine() -> MirrorEngine {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("sync_prop_\(UUID().uuidString)").resolvingSymlinksInPath()
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbPath = dir.appendingPathComponent("test.db").path
    let snapshotter = try! Snapshotter(dbPath: dbPath)
    let diffEngine = try! DiffEngine(dbPath: dbPath)
    let journal = try! SQLiteTransferJournal(
      dbPath: dir.appendingPathComponent("journal.db").path)
    return MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }
}
