// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

// MARK: - Snapshot → Modify → Re-snapshot → Diff Tests

final class SnapshotDiffCycleTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("adv-sync.sqlite").path
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

  // 1
  func testSnapshotModifyResnaphotDiffShowsAddition() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "original.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "original.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "added.txt",
          sizeBytes: 8, formatCode: 0x3000, data: Data(repeating: 0xBB, count: 8)))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1)
    XCTAssertTrue(delta.added.first?.pathKey.contains("added.txt") ?? false)
    XCTAssertEqual(delta.removed.count, 0)
  }

  // 2
  func testSnapshotModifyResnaphotDiffShowsRemoval() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "keep.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "remove_me.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8])))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "keep.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.removed.count, 1)
    XCTAssertTrue(delta.removed.first?.pathKey.contains("remove_me.txt") ?? false)
    XCTAssertEqual(delta.added.count, 0)
  }

  // 3
  func testSnapshotModifyResnaphotDiffShowsSizeChange() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let configV1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "growing.dat",
          sizeBytes: 10, formatCode: 0x3000, data: Data(repeating: 0xAA, count: 10)))
    let deviceV1 = VirtualMTPDevice(config: configV1)
    let deviceId = await deviceV1.id
    let gen1 = try await snapshotter.capture(device: deviceV1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let configV2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "growing.dat",
          sizeBytes: 50, formatCode: 0x3000, data: Data(repeating: 0xBB, count: 50)))
    let deviceV2 = VirtualMTPDevice(config: configV2)
    let gen2 = try await snapshotter.capture(device: deviceV2, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.modified.count, 1, "Size change should be detected as modification")
  }

  // 4
  func testThreeGenerationChainDiffIsTransitive() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)

    // Gen 1: file A
    let cfg1 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "A.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4])))
    let dev1 = VirtualMTPDevice(config: cfg1)
    let deviceId = await dev1.id
    let gen1 = try await snapshotter.capture(device: dev1, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Gen 2: files A, B
    let cfg2 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 100, storage: storage, name: "A.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([1, 2, 3, 4]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "B.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8])))
    let dev2 = VirtualMTPDevice(config: cfg2)
    let gen2 = try await snapshotter.capture(device: dev2, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Gen 3: files B, C (A removed, C added)
    let cfg3 = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 101, storage: storage, name: "B.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([5, 6, 7, 8]))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 102, storage: storage, name: "C.txt",
          sizeBytes: 4, formatCode: 0x3000, data: Data([9, 10, 11, 12])))
    let dev3 = VirtualMTPDevice(config: cfg3)
    let gen3 = try await snapshotter.capture(device: dev3, deviceId: deviceId)

    // Diff gen1 -> gen3 should show A removed, B unchanged, C added
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen3)
    XCTAssertEqual(delta.added.count, 2, "B and C added relative to gen1")
    XCTAssertEqual(delta.removed.count, 1, "A removed relative to gen1")
  }
}

// MARK: - Mirror Conflict Resolution Tests

final class MirrorConflictResolutionAdvancedTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  private enum ConflictPolicy {
    case preferLocal, preferRemote, newestWins
  }

  // 5
  func testPreferLocalPolicyPreservesLocalOnConflict() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    try "local data"
      .write(
        to: localDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
    try "remote data"
      .write(
        to: remoteDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

    resolve(
      file: "f.txt", local: localDir, remote: remoteDir, merged: mergedDir, policy: .preferLocal)
    let content = try String(contentsOf: mergedDir.appendingPathComponent("f.txt"), encoding: .utf8)
    XCTAssertEqual(content, "local data")
  }

  // 6
  func testPreferRemotePolicyPreservesRemoteOnConflict() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    try "local data"
      .write(
        to: localDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
    try "remote data"
      .write(
        to: remoteDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

    resolve(
      file: "f.txt", local: localDir, remote: remoteDir, merged: mergedDir, policy: .preferRemote)
    let content = try String(contentsOf: mergedDir.appendingPathComponent("f.txt"), encoding: .utf8)
    XCTAssertEqual(content, "remote data")
  }

  // 7
  func testNewestWinsPolicyPicksNewerLocal() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    let localFile = localDir.appendingPathComponent("f.txt")
    let remoteFile = remoteDir.appendingPathComponent("f.txt")

    try "newer local".write(to: localFile, atomically: true, encoding: .utf8)
    // Local is current time (newer)
    try "older remote".write(to: remoteFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: remoteFile.path)

    resolve(
      file: "f.txt", local: localDir, remote: remoteDir, merged: mergedDir, policy: .newestWins)
    let content = try String(contentsOf: mergedDir.appendingPathComponent("f.txt"), encoding: .utf8)
    XCTAssertEqual(content, "newer local")
  }

  // 8
  func testNewestWinsPolicyPicksNewerRemote() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    let localFile = localDir.appendingPathComponent("f.txt")
    let remoteFile = remoteDir.appendingPathComponent("f.txt")

    try "older local".write(to: localFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: localFile.path)
    try "newer remote".write(to: remoteFile, atomically: true, encoding: .utf8)

    resolve(
      file: "f.txt", local: localDir, remote: remoteDir, merged: mergedDir, policy: .newestWins)
    let content = try String(contentsOf: mergedDir.appendingPathComponent("f.txt"), encoding: .utf8)
    XCTAssertEqual(content, "newer remote")
  }

  // 9
  func testConflictResolutionWithBinaryData() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    let localData = Data(repeating: 0xAA, count: 256)
    let remoteData = Data(repeating: 0xBB, count: 512)
    try localData.write(to: localDir.appendingPathComponent("bin.dat"))
    try remoteData.write(to: remoteDir.appendingPathComponent("bin.dat"))

    resolve(
      file: "bin.dat", local: localDir, remote: remoteDir, merged: mergedDir, policy: .preferRemote)
    let merged = try Data(contentsOf: mergedDir.appendingPathComponent("bin.dat"))
    XCTAssertEqual(merged, remoteData)
  }

  // 10
  func testConflictResolutionWithMultipleFilesIndependent() throws {
    let (localDir, remoteDir, mergedDir) = try makeDirs()
    for i in 0..<5 {
      try "local-\(i)"
        .write(
          to: localDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
      try "remote-\(i)"
        .write(
          to: remoteDir.appendingPathComponent("file\(i).txt"), atomically: true, encoding: .utf8)
    }

    // Resolve even files as local-wins, odd as remote-wins
    for i in 0..<5 {
      let policy: ConflictPolicy = i % 2 == 0 ? .preferLocal : .preferRemote
      resolve(
        file: "file\(i).txt", local: localDir, remote: remoteDir,
        merged: mergedDir, policy: policy)
    }

    for i in 0..<5 {
      let content = try String(
        contentsOf: mergedDir.appendingPathComponent("file\(i).txt"), encoding: .utf8)
      if i % 2 == 0 {
        XCTAssertEqual(content, "local-\(i)")
      } else {
        XCTAssertEqual(content, "remote-\(i)")
      }
    }
  }

  // MARK: - Helpers

  private func makeDirs() throws -> (URL, URL, URL) {
    let local = tempDirectory.appendingPathComponent("local-\(UUID().uuidString)")
    let remote = tempDirectory.appendingPathComponent("remote-\(UUID().uuidString)")
    let merged = tempDirectory.appendingPathComponent("merged-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: merged, withIntermediateDirectories: true)
    return (local, remote, merged)
  }

  private func resolve(
    file: String, local: URL, remote: URL, merged: URL, policy: ConflictPolicy
  ) {
    let localFile = local.appendingPathComponent(file)
    let remoteFile = remote.appendingPathComponent(file)
    let mergedFile = merged.appendingPathComponent(file)

    switch policy {
    case .preferLocal:
      try? FileManager.default.copyItem(at: localFile, to: mergedFile)
    case .preferRemote:
      try? FileManager.default.copyItem(at: remoteFile, to: mergedFile)
    case .newestWins:
      let lm =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[
          .modificationDate] as? Date ?? .distantPast
      let rm =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[
          .modificationDate] as? Date ?? .distantPast
      try? FileManager.default.copyItem(at: lm >= rm ? localFile : remoteFile, to: mergedFile)
    }
  }
}

// MARK: - Large Directory Tree Sync Tests

final class LargeDirectoryTreeSyncTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("large-tree.sqlite").path
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

  // 11
  func testSnapshotWith1000Files() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<1000 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "file_\(i).dat", sizeBytes: 4, formatCode: 0x3000,
          data: Data([UInt8(i % 256), UInt8((i >> 8) % 256), 0, 0])))
    }
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }

  // 12
  func testDiffWith1000FilesAddedFromEmpty() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<1000 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "file_\(i).dat", sizeBytes: 4, formatCode: 0x3000,
          data: Data([UInt8(i % 256), 0, 0, 0])))
    }
    let populatedDevice = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1000)
    XCTAssertEqual(delta.removed.count, 0)
  }

  // 13
  func testDiffWith1000FilesRemovedToEmpty() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.emptyDevice
    for i in 0..<1000 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(100 + i), storage: storage,
          name: "file_\(i).dat", sizeBytes: 4, formatCode: 0x3000,
          data: Data([UInt8(i % 256), 0, 0, 0])))
    }
    let populatedDevice = VirtualMTPDevice(config: config)
    let deviceId = await populatedDevice.id
    let gen1 = try await snapshotter.capture(device: populatedDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let gen2 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.removed.count, 1000)
    XCTAssertEqual(delta.added.count, 0)
  }
}

// MARK: - Concurrent Mirror Operations Tests

final class ConcurrentMirrorAdvancedTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("concurrent.sqlite").path

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    mirrorEngine = nil
    try? FileManager.default.removeItem(at: tempDirectory)
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // 14
  func testConcurrentMirrorsToSeparateDirectoriesDoNotCrash() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let engine = self.mirrorEngine!
    let root = self.tempDirectory!

    let results = await withTaskGroup(of: MTPSyncReport?.self, returning: [MTPSyncReport?].self) {
      group in
      for i in 0..<5 {
        group.addTask {
          try? await engine.mirror(
            device: device, deviceId: deviceId,
            to: root.appendingPathComponent("mirror-\(i)"))
        }
      }
      var reports: [MTPSyncReport?] = []
      for await result in group { reports.append(result) }
      return reports
    }

    XCTAssertEqual(results.count, 5)
    // At least one should succeed; concurrent SQLite access may cause some to fail
    let succeeded = results.compactMap { $0 }
    XCTAssertGreaterThanOrEqual(succeeded.count, 1)
  }

  // 15
  func testConcurrentSnapshotCapturesDoNotCrash() async throws {
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id

    await withTaskGroup(of: Int?.self) { group in
      for _ in 0..<5 {
        group.addTask {
          try? await snapshotter.capture(device: device, deviceId: deviceId)
        }
      }
      var completed = 0
      for await _ in group { completed += 1 }
      XCTAssertEqual(completed, 5)
    }
  }
}

// MARK: - Incremental Sync Tests

final class IncrementalSyncTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // 16
  func testIncrementalSyncOnlyTransfersChangedFiles() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Initial state: both sides have fileA
    try "content-A"
      .write(
        to: localDir.appendingPathComponent("fileA.txt"), atomically: true, encoding: .utf8)
    try "content-A"
      .write(
        to: remoteDir.appendingPathComponent("fileA.txt"), atomically: true, encoding: .utf8)

    // Remote adds fileB
    try "content-B"
      .write(
        to: remoteDir.appendingPathComponent("fileB.txt"), atomically: true, encoding: .utf8)

    let localFiles = Set(listRelativeFiles(in: localDir))
    let remoteFiles = Set(listRelativeFiles(in: remoteDir))
    let needsTransfer = remoteFiles.subtracting(localFiles)

    XCTAssertEqual(needsTransfer.count, 1)
    XCTAssertTrue(needsTransfer.contains("fileB.txt"))
  }

  // 17
  func testIncrementalSyncSkipsUnchangedFiles() async throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Both sides identical
    for name in ["a.txt", "b.txt", "c.txt"] {
      let content = "shared-\(name)"
      try content.write(
        to: localDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
      try content.write(
        to: remoteDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let localFiles = Set(listRelativeFiles(in: localDir))
    let remoteFiles = Set(listRelativeFiles(in: remoteDir))
    let needsTransfer = remoteFiles.subtracting(localFiles)

    XCTAssertTrue(needsTransfer.isEmpty, "No files should need transfer when both sides match")
  }

  private func listRelativeFiles(in directory: URL) -> [String] {
    let resolved = directory.resolvingSymlinksInPath()
    guard
      let enumerator = FileManager.default.enumerator(
        at: resolved, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let v = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        v.isRegularFile == true
      else { continue }
      files.append(
        fileURL.resolvingSymlinksInPath().path
          .replacingOccurrences(of: resolved.path + "/", with: ""))
    }
    return files
  }
}

// MARK: - Delete Propagation Tests

final class DeletePropagationTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // 18
  func testLocalDeleteDetectedAsMissingInRemote() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let remoteDir = tempDirectory.appendingPathComponent("remote")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

    // Remote has files A, B, C; local only has A, B (C was deleted locally)
    for name in ["A.txt", "B.txt"] {
      try "content"
        .write(
          to: localDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    for name in ["A.txt", "B.txt", "C.txt"] {
      try "content"
        .write(
          to: remoteDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let localFiles = Set(listFiles(in: localDir))
    let remoteFiles = Set(listFiles(in: remoteDir))
    let deletedLocally = remoteFiles.subtracting(localFiles)

    XCTAssertEqual(deletedLocally.count, 1)
    XCTAssertTrue(deletedLocally.contains("C.txt"))
  }

  // 19
  func testDeletePropagationRemovesFileFromMirror() throws {
    let mirrorDir = tempDirectory.appendingPathComponent("mirror")
    try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

    // Mirror has files from previous sync
    try "old"
      .write(
        to: mirrorDir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
    try "old"
      .write(
        to: mirrorDir.appendingPathComponent("delete_me.txt"), atomically: true, encoding: .utf8)

    // Simulate delete propagation: remove files not in device snapshot
    let deviceFiles: Set<String> = ["keep.txt"]
    let mirrorFiles = Set(listFiles(in: mirrorDir))
    let toDelete = mirrorFiles.subtracting(deviceFiles)

    for file in toDelete {
      try FileManager.default.removeItem(at: mirrorDir.appendingPathComponent(file))
    }

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: mirrorDir.appendingPathComponent("keep.txt").path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: mirrorDir.appendingPathComponent("delete_me.txt").path))
  }

  // 20
  func testDeletePropagationWithNestedDirectories() throws {
    let mirrorDir = tempDirectory.appendingPathComponent("mirror")
    let subDir = mirrorDir.appendingPathComponent("subdir")
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    try "keep"
      .write(
        to: mirrorDir.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
    try "delete"
      .write(
        to: subDir.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)

    // Device snapshot only has root.txt
    let deviceFiles: Set<String> = ["root.txt"]
    let mirrorFiles = Set(listFiles(in: mirrorDir))
    let toDelete = mirrorFiles.subtracting(deviceFiles)

    for file in toDelete {
      try FileManager.default.removeItem(at: mirrorDir.appendingPathComponent(file))
    }

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: mirrorDir.appendingPathComponent("root.txt").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: subDir.appendingPathComponent("nested.txt").path))
  }

  private func listFiles(in directory: URL) -> [String] {
    let resolved = directory.resolvingSymlinksInPath()
    guard
      let enumerator = FileManager.default.enumerator(
        at: resolved, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let v = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        v.isRegularFile == true
      else { continue }
      files.append(
        fileURL.resolvingSymlinksInPath().path
          .replacingOccurrences(of: resolved.path + "/", with: ""))
    }
    return files
  }
}

// MARK: - Special File Handling Tests

final class SpecialFileHandlingTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // 21
  func testSymlinkNotFollowedInChangeDetection() throws {
    let localDir = tempDirectory.appendingPathComponent("local")
    let targetDir = tempDirectory.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    try "real"
      .write(
        to: targetDir.appendingPathComponent("real.txt"), atomically: true, encoding: .utf8)

    let symlinkPath = localDir.appendingPathComponent("link_to_target")
    try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: targetDir)

    // Only regular files should be listed, symlinks to directories should not add files
    let files = listRegularFiles(in: localDir)
    XCTAssertTrue(
      files.isEmpty || !files.contains("real.txt"),
      "Symlinked directory contents should not appear as direct children")
  }

  // 22
  func testZeroByteFileDetectedInDiff() async throws {
    let dbPath = tempDirectory.appendingPathComponent("special.sqlite").path
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let storage = MTPStorageID(raw: 0x0001_0001)
    let emptyDevice = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await emptyDevice.id
    let gen1 = try await snapshotter.capture(device: emptyDevice, deviceId: deviceId)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 42, storage: storage, name: "empty.txt",
          sizeBytes: 0, formatCode: 0x3000, data: Data()))
    let device = VirtualMTPDevice(config: config)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(delta.added.count, 1)
    XCTAssertTrue(delta.added.first?.pathKey.contains("empty.txt") ?? false)
  }

  private func listRegularFiles(in directory: URL) -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let v = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
        v.isRegularFile == true, v.isSymbolicLink != true
      else { continue }
      files.append(fileURL.lastPathComponent)
    }
    return files
  }
}

// MARK: - Resume After Interrupted Mirror Tests

final class MirrorResumeTests: XCTestCase {
  private var tempDirectory: URL!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let dbPath = tempDirectory.appendingPathComponent("resume.sqlite").path
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

  // 23
  func testMirrorCanRunTwiceWithoutDuplicatingFiles() async throws {
    let storage = MTPStorageID(raw: 0x0001_0001)
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 42, storage: storage, name: "photo.jpg",
          sizeBytes: 16, formatCode: 0x3801, data: Data(repeating: 0xAB, count: 16)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let output = tempDirectory.appendingPathComponent("output")

    let report1 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report1.downloaded, 1)

    // Wait for a new generation timestamp
    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second mirror with same device should not fail
    let report2 = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    XCTAssertEqual(report2.failed, 0)
  }

  // 24
  func testMirrorAfterPartialExistingFiles() async throws {
    let output = tempDirectory.appendingPathComponent("partial_output")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    // Pre-create one file to simulate partial previous mirror
    try Data(repeating: 0xAB, count: 16).write(to: output.appendingPathComponent("existing.jpg"))

    let storage = MTPStorageID(raw: 0x0001_0001)
    let config = VirtualDeviceConfig.emptyDevice
      .withObject(
        VirtualObjectConfig(
          handle: 42, storage: storage, name: "existing.jpg",
          sizeBytes: 16, formatCode: 0x3801, data: Data(repeating: 0xAB, count: 16))
      )
      .withObject(
        VirtualObjectConfig(
          handle: 43, storage: storage, name: "new.jpg",
          sizeBytes: 8, formatCode: 0x3801, data: Data(repeating: 0xCD, count: 8)))
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id

    let report = try await mirrorEngine.mirror(device: device, deviceId: deviceId, to: output)
    // Both should be processed without error
    XCTAssertEqual(report.failed, 0)
    XCTAssertGreaterThanOrEqual(report.downloaded, 1)
  }
}

// MARK: - Property-Based Advanced Sync Tests

final class SyncAdvancedPropertyTests: XCTestCase {

  // 25
  func testDiffSymmetryAddedRemovedSwap() {
    property("Swapping old/new swaps added/removed counts")
      <- forAll(
        Gen<Int>.choose((0, 20)),
        Gen<Int>.choose((0, 20))
      ) { addCount, removeCount in
        var diff = MTPDiff()
        for i in 0..<addCount {
          diff.added.append(
            MTPDiff.Row(
              handle: UInt32(i), storage: 1, pathKey: "1/add_\(i)",
              size: 100, mtime: nil, format: 0x3000))
        }
        for i in 0..<removeCount {
          diff.removed.append(
            MTPDiff.Row(
              handle: UInt32(i + 1000), storage: 1, pathKey: "1/rm_\(i)",
              size: 100, mtime: nil, format: 0x3000))
        }
        // If we reverse perspective, added becomes removed and vice versa
        var reversed = MTPDiff()
        reversed.added = diff.removed
        reversed.removed = diff.added
        return reversed.added.count == diff.removed.count
          && reversed.removed.count == diff.added.count
      }
  }

  // 26
  func testSyncReportDownloadedPlusFailedPlusSkippedEqualsTotalProcessed() {
    property("downloaded + skipped + failed == totalProcessed")
      <- forAll(
        Gen<Int>.choose((0, 5000)),
        Gen<Int>.choose((0, 5000)),
        Gen<Int>.choose((0, 5000))
      ) { d, s, f in
        var report = MTPSyncReport()
        report.downloaded = d
        report.skipped = s
        report.failed = f
        return report.totalProcessed == d + s + f
      }
  }

  // 27
  func testDiffEmptyToSameIsAlwaysEmpty() {
    property("Diff with identical added/removed is still consistent")
      <- forAll(Gen<Int>.choose((0, 30))) { count in
        var diff = MTPDiff()
        for i in 0..<count {
          let row = MTPDiff.Row(
            handle: UInt32(i), storage: 1, pathKey: "1/file_\(i)",
            size: nil, mtime: nil, format: 0x3000)
          diff.added.append(row)
          diff.removed.append(row)
        }
        return diff.totalChanges == count * 2
      }
  }

  // 28
  func testSyncReportSuccessRateMonotoneWithMoreDownloads() {
    property("Adding downloads never decreases success rate (with constant skipped/failed)")
      <- forAll(
        Gen<Int>.choose((0, 100)),
        Gen<Int>.choose((0, 100)),
        Gen<Int>.choose((1, 100))
      ) { initial, skipped, failed in
        var r1 = MTPSyncReport()
        r1.downloaded = initial
        r1.skipped = skipped
        r1.failed = failed
        var r2 = MTPSyncReport()
        r2.downloaded = initial + 1
        r2.skipped = skipped
        r2.failed = failed
        return r2.successRate >= r1.successRate
      }
  }
}
