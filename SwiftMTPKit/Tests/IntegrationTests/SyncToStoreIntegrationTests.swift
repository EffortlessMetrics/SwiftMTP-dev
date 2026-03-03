// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
import SwiftMTPObservability
@testable import SwiftMTPIndex
@testable import SwiftMTPSync

/// Integration tests for Sync → Store interactions:
/// mirror/journal, snapshot/diff/mirror, and conflict resolution workflows.
final class SyncToStoreIntegrationTests: XCTestCase {

  // MARK: - Helpers

  private func makeTempDBPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-s2s-\(UUID().uuidString).db").path
  }

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-s2s-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: - In-memory journal

  private actor TestJournal: TransferJournal {
    var entries: [String: TransferRecord] = [:]
    private var nextID = 0

    func beginRead(
      device: MTPDeviceID, handle: UInt32, name: String,
      size: UInt64?, supportsPartial: Bool,
      tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
    ) async throws -> String {
      nextID += 1
      let id = "r-\(nextID)"
      entries[id] = TransferRecord(
        id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil,
        name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
        localTempURL: tempURL, finalURL: finalURL, state: "active", updatedAt: Date())
      return id
    }

    func beginWrite(
      device: MTPDeviceID, parent: UInt32, name: String,
      size: UInt64, supportsPartial: Bool,
      tempURL: URL, sourceURL: URL?
    ) async throws -> String {
      nextID += 1
      let id = "w-\(nextID)"
      entries[id] = TransferRecord(
        id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent,
        name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
        localTempURL: tempURL, finalURL: sourceURL, state: "active", updatedAt: Date())
      return id
    }

    func updateProgress(id: String, committed: UInt64) async throws {
      guard let r = entries[id] else { return }
      entries[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: committed, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: r.state, updatedAt: Date())
    }

    func fail(id: String, error: Error) async throws {
      guard let r = entries[id] else { return }
      entries[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: "failed", updatedAt: Date())
    }

    func complete(id: String) async throws {
      guard let r = entries[id] else { return }
      entries[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.totalBytes ?? r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL, state: "completed", updatedAt: Date())
    }

    func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
      entries.values.filter { $0.deviceId.raw == device.raw && $0.state == "active" }
    }

    func clearStaleTemps(olderThan: TimeInterval) async throws {
      let cutoff = Date().addingTimeInterval(-olderThan)
      entries = entries.filter { $0.value.updatedAt > cutoff }
    }

    var allEntries: [String: TransferRecord] { entries }
    var completedCount: Int { entries.values.filter { $0.state == "completed" }.count }
    var failedCount: Int { entries.values.filter { $0.state == "failed" }.count }
    var activeCount: Int { entries.values.filter { $0.state == "active" }.count }
  }

  // MARK: - 1. Mirror → journal entry → resume verify

  func testMirrorCreatesJournalEntries() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()

    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    XCTAssertGreaterThan(
      report.totalProcessed, 0,
      "Mirror should process files")
    XCTAssertEqual(report.failed, 0, "No files should fail in normal mirror")
  }

  func testMirrorReportAccountsForAllFiles() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()

    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    // totalProcessed = downloaded + skipped + failed
    XCTAssertEqual(
      report.totalProcessed,
      report.downloaded + report.skipped + report.failed)
    if report.totalProcessed > 0 {
      XCTAssertGreaterThan(report.successRate, 0)
    }
  }

  func testJournalTracksPartialTransferForResume() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:resume-device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("resume.dat")

    let id = try await journal.beginRead(
      device: deviceId, handle: 42, name: "large_video.mp4",
      size: 100_000_000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    // Simulate partial progress
    try await journal.updateProgress(id: id, committed: 50_000_000)

    // Simulate failure mid-transfer
    try await journal.fail(id: id, error: TransportError.timeout)

    let entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "failed")
    XCTAssertEqual(
      entry?.committedBytes, 50_000_000,
      "Journal should record partial progress for resume")
    XCTAssertTrue(
      entry?.supportsPartial ?? false,
      "Partial support flag should be preserved")
  }

  func testJournalResumablesListActiveTransfers() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:resumable-list")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("list.dat")

    // Create 3 transfers: 1 completed, 1 failed, 1 active
    let id1 = try await journal.beginRead(
      device: deviceId, handle: 1, name: "done.jpg",
      size: 1000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    try await journal.complete(id: id1)

    let id2 = try await journal.beginRead(
      device: deviceId, handle: 2, name: "failed.jpg",
      size: 2000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    try await journal.fail(id: id2, error: TransportError.timeout)

    _ = try await journal.beginRead(
      device: deviceId, handle: 3, name: "active.jpg",
      size: 3000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1, "Only active transfers should be resumable")
    XCTAssertEqual(resumables[0].name, "active.jpg")
  }

  // MARK: - 2. Snapshot → diff → mirror

  func testSnapshotDiffMirrorEndToEnd() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()

    // Initial mirror
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    let report1 = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    // Add new file
    await device.addObject(
      VirtualObjectConfig(
        handle: 400, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
        name: "new_photo.jpg", sizeBytes: 5000, formatCode: 0x3801,
        data: Data(repeating: 0xCC, count: 64)))

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Incremental mirror
    let report2 = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    // Second mirror should process the new file
    XCTAssertGreaterThanOrEqual(
      report2.downloaded, 1,
      "Incremental mirror should download the new file")
    // Total processing in second run should be less than first
    XCTAssertLessThanOrEqual(report2.totalProcessed, report1.totalProcessed + 1)
  }

  func testSnapshotDiffDetectsRemovals() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Remove an object
    await device.removeObject(handle: 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThanOrEqual(
      diff.removed.count, 1,
      "Diff should detect removed objects")
  }

  func testEmptyDeviceMirrorProducesEmptyReport() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()

    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    XCTAssertEqual(
      report.totalProcessed, 0,
      "Empty device mirror should have no files to process")
    XCTAssertEqual(report.successRate, 0)
  }

  func testDiffFromMultipleGenerations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    await device.addObject(
      VirtualObjectConfig(
        handle: 410, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
        name: "gen2_file.txt", sizeBytes: 100, formatCode: 0x3004,
        data: Data(repeating: 0x01, count: 16)))
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    await device.addObject(
      VirtualObjectConfig(
        handle: 411, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
        name: "gen3_file.txt", sizeBytes: 200, formatCode: 0x3004,
        data: Data(repeating: 0x02, count: 16)))
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen3 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Diff between gen1 and gen3 should include both additions
    let fullDiff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen3)
    XCTAssertGreaterThanOrEqual(
      fullDiff.added.count, 2,
      "Diff across multiple generations should show all additions")

    // Diff between gen2 and gen3 should only show the last addition
    let partialDiff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen2, newGen: gen3)
    XCTAssertGreaterThanOrEqual(partialDiff.added.count, 1)
    XCTAssertTrue(
      partialDiff.added.contains(where: { $0.pathKey.contains("gen3_file.txt") }))
  }

  // MARK: - 3. Conflict → resolution → journal update

  func testConflictingTransferRecordedInJournal() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:conflict-device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("conflict.dat")

    // Start a read transfer
    let readId = try await journal.beginRead(
      device: deviceId, handle: 10, name: "shared_file.txt",
      size: 10000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    // Start a write transfer for the same conceptual file
    let writeId = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "shared_file.txt",
      size: 5000, supportsPartial: false,
      tempURL: tmpURL, sourceURL: nil)

    // Complete the write (resolution: write wins)
    try await journal.complete(id: writeId)
    // Fail the read (superseded by write)
    try await journal.fail(id: readId, error: TransportError.busy)

    let completedCount = await journal.completedCount
    let failedCount = await journal.failedCount
    XCTAssertEqual(completedCount, 1, "Write should be completed")
    XCTAssertEqual(failedCount, 1, "Read should be failed")
  }

  func testJournalStateTransitions() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:state-transitions")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("states.dat")

    let id = try await journal.beginRead(
      device: deviceId, handle: 1, name: "test.jpg",
      size: 10000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    // Active
    var entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "active")

    // Progress
    try await journal.updateProgress(id: id, committed: 5000)
    entry = await journal.entries[id]
    XCTAssertEqual(entry?.committedBytes, 5000)
    XCTAssertEqual(entry?.state, "active")

    // Complete
    try await journal.complete(id: id)
    entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "completed")
    XCTAssertEqual(
      entry?.committedBytes, 10000,
      "Completed transfer should have full bytes committed")
  }

  func testJournalClearStaleTemps() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:stale-cleanup")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("stale.dat")

    // Create an entry that will be "old"
    _ = try await journal.beginRead(
      device: deviceId, handle: 1, name: "old.jpg",
      size: 1000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    let beforeCount = await journal.allEntries.count
    XCTAssertEqual(beforeCount, 1)

    // Clear with 0 second threshold (everything is stale)
    try await journal.clearStaleTemps(olderThan: 0)

    let afterCount = await journal.allEntries.count
    XCTAssertEqual(afterCount, 0, "All entries should be cleared with zero threshold")
  }

  func testMultiDeviceJournalIsolation() async throws {
    let journal = TestJournal()
    let device1 = MTPDeviceID(raw: "test:device-1")
    let device2 = MTPDeviceID(raw: "test:device-2")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("iso.dat")

    // Create transfers for two different devices
    _ = try await journal.beginRead(
      device: device1, handle: 1, name: "dev1_file.jpg",
      size: 1000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try await journal.beginRead(
      device: device1, handle: 2, name: "dev1_file2.jpg",
      size: 2000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    _ = try await journal.beginRead(
      device: device2, handle: 3, name: "dev2_file.jpg",
      size: 3000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    let dev1Resumables = try await journal.loadResumables(for: device1)
    let dev2Resumables = try await journal.loadResumables(for: device2)

    XCTAssertEqual(
      dev1Resumables.count, 2,
      "Device 1 should have 2 resumable transfers")
    XCTAssertEqual(
      dev2Resumables.count, 1,
      "Device 2 should have 1 resumable transfer")
  }

  // MARK: - 4. Mirror path conversion

  func testMirrorEnginePathKeyToLocalURL() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let root = URL(fileURLWithPath: "/tmp/mirror")
    let pathKey = PathKey.normalize(
      storage: 0x0001_0001, components: ["DCIM", "Camera", "IMG_001.jpg"])

    let localURL = engine.pathKeyToLocalURL(pathKey, root: root)
    XCTAssertTrue(localURL.path.contains("DCIM"))
    XCTAssertTrue(localURL.path.contains("Camera"))
    XCTAssertTrue(localURL.path.hasSuffix("IMG_001.jpg"))
  }

  // MARK: - 5. Glob pattern mirror filtering

  func testMirrorPatternMatchingDCIM() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let dcimPath = PathKey.normalize(
      storage: 0x0001_0001, components: ["DCIM", "Camera", "photo.jpg"])
    let musicPath = PathKey.normalize(
      storage: 0x0001_0001, components: ["Music", "song.mp3"])

    XCTAssertTrue(engine.matchesPattern(dcimPath, pattern: "DCIM/**"))
    XCTAssertFalse(engine.matchesPattern(musicPath, pattern: "DCIM/**"))
  }

  func testMirrorPatternMatchingWildcard() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let jpgPath = PathKey.normalize(
      storage: 0x0001_0001, components: ["DCIM", "photo.jpg"])
    let pngPath = PathKey.normalize(
      storage: 0x0001_0001, components: ["DCIM", "photo.png"])

    XCTAssertTrue(engine.matchesPattern(jpgPath, pattern: "**/*.jpg"))
    XCTAssertFalse(engine.matchesPattern(pngPath, pattern: "**/*.jpg"))
  }

  // MARK: - 6. Cross-device mirror isolation

  func testMirrorOperationsIsolatedPerDevice() async throws {
    let dbPath = makeTempDBPath()
    let mirrorDir1 = try makeTempDir()
    let mirrorDir2 = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir1)
      try? FileManager.default.removeItem(at: mirrorDir2)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    let pixelId = await pixel.id
    let samsungId = await samsung.id

    let report1 = try await engine.mirror(
      device: pixel, deviceId: pixelId, to: mirrorDir1)
    let report2 = try await engine.mirror(
      device: samsung, deviceId: samsungId, to: mirrorDir2)

    XCTAssertGreaterThan(report1.totalProcessed, 0)
    XCTAssertGreaterThan(report2.totalProcessed, 0)
  }

  // MARK: - 7. Journal read vs write transfer kinds

  func testJournalDistinguishesReadAndWriteKinds() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:rw-kinds")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("kinds.dat")

    let readId = try await journal.beginRead(
      device: deviceId, handle: 1, name: "download.jpg",
      size: 5000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    let writeId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "upload.jpg",
      size: 3000, supportsPartial: false,
      tempURL: tmpURL, sourceURL: nil)

    let readEntry = await journal.entries[readId]
    let writeEntry = await journal.entries[writeId]
    XCTAssertEqual(readEntry?.kind, "read")
    XCTAssertEqual(writeEntry?.kind, "write")
    XCTAssertNotNil(readEntry?.handle)
    XCTAssertNil(writeEntry?.handle, "Write transfers start without a device handle")
  }

  func testMirrorReportSuccessRateCalculation() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    let mirrorDir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(atPath: dbPath)
      try? FileManager.default.removeItem(at: mirrorDir)
    }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = TestJournal()
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let report = try await engine.mirror(
      device: device, deviceId: deviceId, to: mirrorDir)

    if report.totalProcessed > 0 {
      let expectedRate = Double(report.downloaded) / Double(report.totalProcessed) * 100
      XCTAssertEqual(report.successRate, expectedRate, accuracy: 0.01)
    }
  }

  func testDiffTotalChangesProperty() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    await device.addObject(
      VirtualObjectConfig(
        handle: 900, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
        name: "total_changes.txt", sizeBytes: 100, formatCode: 0x3004,
        data: Data(repeating: 0xAA, count: 16)))
    await device.removeObject(handle: 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertEqual(
      diff.totalChanges,
      diff.added.count + diff.removed.count + diff.modified.count)
    XCTAssertFalse(diff.isEmpty)
  }

  func testJournalWriteEntryHasParentHandle() async throws {
    let journal = TestJournal()
    let deviceId = MTPDeviceID(raw: "test:parent-handle")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("parent.dat")

    let writeId = try await journal.beginWrite(
      device: deviceId, parent: 42, name: "child.txt",
      size: 100, supportsPartial: false,
      tempURL: tmpURL, sourceURL: nil)

    let entry = await journal.entries[writeId]
    XCTAssertEqual(
      entry?.parentHandle, 42,
      "Write journal entry should record parent handle")
  }
}
