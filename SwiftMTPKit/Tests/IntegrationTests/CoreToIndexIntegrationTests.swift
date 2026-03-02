// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
@testable import SwiftMTPIndex

/// Integration tests for Core → Index interactions:
/// device listing, index building, querying, update propagation, and cleanup.
final class CoreToIndexIntegrationTests: XCTestCase {

  // MARK: - Helpers

  private func makeTempDBPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-c2i-\(UUID().uuidString).db").path
  }

  // MARK: - 1. Device list → index build → query

  func testDeviceListBuildsIndexAndQueryReturnsResults() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    // Build index via snapshot
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)

    // Query: diff from empty → current should list all device objects
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertGreaterThan(diff.added.count, 0, "Index query should return device objects")
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 0)
  }

  func testMultipleDevicesIndexedIndependently() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    let pixelId = await pixel.id
    let samsungId = await samsung.id

    let genPixel = try await snapshotter.capture(device: pixel, deviceId: pixelId)
    let genSamsung = try await snapshotter.capture(device: samsung, deviceId: samsungId)

    let diffPixel = try await diffEngine.diff(deviceId: pixelId, oldGen: nil, newGen: genPixel)
    let diffSamsung = try await diffEngine.diff(
      deviceId: samsungId, oldGen: nil, newGen: genSamsung)

    // Each device's index should be independent
    XCTAssertGreaterThan(diffPixel.added.count, 0)
    XCTAssertGreaterThan(diffSamsung.added.count, 0)
    // Verify independence: the two device snapshots are stored separately
    XCTAssertEqual(try snapshotter.latestGeneration(for: pixelId) != nil, true)
    XCTAssertEqual(try snapshotter.latestGeneration(for: samsungId) != nil, true)
  }

  func testCameraDeviceIndexedWithPhotoFormats() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    XCTAssertGreaterThan(diff.added.count, 0, "Camera should have indexable objects")
    // Camera objects should have non-zero handles
    for row in diff.added {
      XCTAssertGreaterThan(row.handle, 0)
    }
  }

  // MARK: - 2. File change → index update → verify

  func testFileAdditionReflectedInIndexDiff() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Add a new file to the device
    await device.addObject(VirtualObjectConfig(
      handle: 500, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "new_document.pdf", sizeBytes: 1_234_567, formatCode: 0x3000,
      data: Data(repeating: 0xDD, count: 64)))

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.added.contains(where: { $0.pathKey.contains("new_document.pdf") }),
      "Added file should appear in diff")
  }

  func testFileRemovalReflectedInIndexDiff() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Remove an existing object
    await device.removeObject(handle: 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThanOrEqual(diff.removed.count, 1, "Removed file should appear in diff")
  }

  func testMultipleFileChangesTrackedCorrectly() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Add three files
    for i in 0..<3 {
      await device.addObject(VirtualObjectConfig(
        handle: UInt32(600 + i), storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
        name: "batch_\(i).txt", sizeBytes: UInt64(100 * (i + 1)), formatCode: 0x3004,
        data: Data(repeating: UInt8(i), count: 32)))
    }

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThanOrEqual(diff.added.count, 3,
      "All three added files should appear in the diff")
  }

  // MARK: - 3. Device disconnect → index cleanup

  func testDisconnectedDeviceIndexRemainsQueryable() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Simulate disconnect: device is gone but index DB remains
    let latestGen = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latestGen, gen,
      "Index should remain queryable after device disconnect")

    let diffEngine = try DiffEngine(dbPath: dbPath)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertGreaterThan(diff.added.count, 0,
      "Index data should survive device disconnect")
  }

  func testReconnectedDeviceSnapshotUpdatesIndex() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    // First connection
    let device1 = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device1.id
    let gen1 = try await snapshotter.capture(device: device1, deviceId: deviceId)

    // Simulate reconnection with same device ID but new content
    let device2 = VirtualMTPDevice(config: .pixel7)
    await device2.addObject(VirtualObjectConfig(
      handle: 700, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "new_after_reconnect.jpg", sizeBytes: 5000, formatCode: 0x3801,
      data: Data(repeating: 0xEE, count: 64)))

    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device2, deviceId: deviceId)

    XCTAssertGreaterThan(gen2, gen1, "Reconnection should create a new generation")
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.added.contains(where: { $0.pathKey.contains("new_after_reconnect.jpg") }))
  }

  func testEmptyDeviceDisconnectProducesCleanIndex() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diffEngine = try DiffEngine(dbPath: dbPath)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)
    XCTAssertTrue(diff.isEmpty, "Empty device should produce an empty index diff")
  }

  // MARK: - 4. Concurrent index/transfer operations

  func testConcurrentSnapshotsFromDifferentDevices() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    let canon = VirtualMTPDevice(config: .canonEOSR5)
    let pixelId = await pixel.id
    let samsungId = await samsung.id
    let canonId = await canon.id

    // Run snapshots concurrently
    async let genPixel = snapshotter.capture(device: pixel, deviceId: pixelId)
    async let genSamsung = snapshotter.capture(device: samsung, deviceId: samsungId)
    async let genCanon = snapshotter.capture(device: canon, deviceId: canonId)

    let results = try await [genPixel, genSamsung, genCanon]
    for gen in results {
      XCTAssertGreaterThan(gen, 0, "All concurrent snapshots should succeed")
    }
  }

  func testConcurrentIndexReadAndWrite() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:concurrent-rw"

    // Write some initial objects
    let objects = (1...5).map { i in
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: UInt32(i),
        parentHandle: nil, name: "file_\(i).jpg", pathKey: "00010001/file_\(i).jpg",
        sizeBytes: UInt64(i * 1000), mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 1)
    }
    try await index.upsertObjects(objects, deviceId: deviceId)

    // Concurrent read and write
    async let readResult = index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    async let writeResult: () = index.upsertObjects([
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: 100,
        parentHandle: nil, name: "concurrent_add.jpg", pathKey: "00010001/concurrent_add.jpg",
        sizeBytes: 5000, mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 2)
    ], deviceId: deviceId)

    let children = try await readResult
    try await writeResult
    XCTAssertGreaterThanOrEqual(children.count, 5,
      "Concurrent read should see at least initial objects")
  }

  func testSequentialSnapshotsMonotonicallyIncrease() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    var generations: [Int] = []
    for i in 0..<3 {
      if i > 0 {
        await device.addObject(VirtualObjectConfig(
          handle: UInt32(800 + i), storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
          name: "seq_\(i).txt", sizeBytes: 100, formatCode: 0x3004,
          data: Data(repeating: UInt8(i), count: 16)))
        try await Task.sleep(nanoseconds: 1_100_000_000)
      }
      let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
      generations.append(gen)
    }

    for i in 1..<generations.count {
      XCTAssertGreaterThan(generations[i], generations[i - 1],
        "Snapshot generations must monotonically increase")
    }
  }

  // MARK: - 5. LiveIndex upsert/query integration

  func testLiveIndexBatchUpsertAndChildQuery() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:batch-upsert"

    let dcim = IndexedObject(
      deviceId: deviceId, storageId: 0x0001_0001, handle: 1,
      parentHandle: nil, name: "DCIM", pathKey: "00010001/DCIM",
      sizeBytes: nil, mtime: nil, formatCode: 0x3001,
      isDirectory: true, changeCounter: 1)

    let photos = (10...14).map { i in
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: UInt32(i),
        parentHandle: 1, name: "IMG_\(i).jpg", pathKey: "00010001/DCIM/IMG_\(i).jpg",
        sizeBytes: UInt64(i * 1000), mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 1)
    }

    try await index.upsertObjects([dcim] + photos, deviceId: deviceId)

    let children = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: 1)
    XCTAssertEqual(children.count, 5, "Should have 5 photos under DCIM")
    XCTAssertTrue(children.allSatisfy { !$0.isDirectory })
  }

  func testLiveIndexChangeCounterIncrements() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:change-counter-inc"

    let counter1 = try await index.currentChangeCounter(deviceId: deviceId)

    try await index.upsertObjects([
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: 1,
        parentHandle: nil, name: "a.jpg", pathKey: "00010001/a.jpg",
        sizeBytes: 100, mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 1)
    ], deviceId: deviceId)

    let counter2 = try await index.currentChangeCounter(deviceId: deviceId)
    XCTAssertGreaterThan(counter2, counter1)

    try await index.upsertObjects([
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: 2,
        parentHandle: nil, name: "b.jpg", pathKey: "00010001/b.jpg",
        sizeBytes: 200, mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 2)
    ], deviceId: deviceId)

    let counter3 = try await index.currentChangeCounter(deviceId: deviceId)
    XCTAssertGreaterThan(counter3, counter2,
      "Each upsert should increment the change counter")
  }

  func testLiveIndexRemoveAndVerify() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:remove-verify"

    // Insert then remove
    try await index.upsertObjects([
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: 50,
        parentHandle: nil, name: "temp.dat", pathKey: "00010001/temp.dat",
        sizeBytes: 512, mtime: nil, formatCode: 0x3000,
        isDirectory: false, changeCounter: 1)
    ], deviceId: deviceId)

    let before = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    XCTAssertEqual(before.count, 1)

    try await index.removeObject(deviceId: deviceId, storageId: 0x0001_0001, handle: 50)

    let after = try await index.children(
      deviceId: deviceId, storageId: 0x0001_0001, parentHandle: nil)
    XCTAssertEqual(after.count, 0, "Object should be removed from index")
  }

  func testLiveIndexStorageUpsertAndQuery() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:storage-upsert"

    let storage1 = IndexedStorage(
      deviceId: deviceId, storageId: 0x0001_0001,
      description: "Internal storage", capacity: 128_000_000_000,
      free: 64_000_000_000, readOnly: false)
    let storage2 = IndexedStorage(
      deviceId: deviceId, storageId: 0x0002_0001,
      description: "SD Card", capacity: 32_000_000_000,
      free: 16_000_000_000, readOnly: false)

    try await index.upsertStorage(storage1)
    try await index.upsertStorage(storage2)

    let storages = try await index.storages(deviceId: deviceId)
    XCTAssertEqual(storages.count, 2)
    XCTAssertTrue(storages.contains(where: { $0.description == "Internal storage" }))
    XCTAssertTrue(storages.contains(where: { $0.description == "SD Card" }))
  }

  // MARK: - 6. PathKey round-trip through index

  func testPathKeyRoundTripThroughIndex() async throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let index = try SQLiteLiveIndex(path: dbPath)
    let deviceId = "test:pathkey-roundtrip"

    let pathKey = PathKey.normalize(
      storage: 0x0001_0001, components: ["DCIM", "Camera", "IMG_001.jpg"])

    try await index.upsertObjects([
      IndexedObject(
        deviceId: deviceId, storageId: 0x0001_0001, handle: 42,
        parentHandle: nil, name: "IMG_001.jpg", pathKey: pathKey,
        sizeBytes: 4096, mtime: nil, formatCode: 0x3801,
        isDirectory: false, changeCounter: 1)
    ], deviceId: deviceId)

    let obj = try await index.object(deviceId: deviceId, handle: 42)
    XCTAssertNotNil(obj)

    let (storageId, components) = PathKey.parse(obj!.pathKey)
    XCTAssertEqual(storageId, 0x0001_0001)
    XCTAssertEqual(components, ["DCIM", "Camera", "IMG_001.jpg"])
  }

  // MARK: - 7. Diff path keys are parseable

  func testAllDiffRowPathKeysAreParseable() async throws {
    let configs: [VirtualDeviceConfig] = [.pixel7, .samsungGalaxy, .canonEOSR5]
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    for config in configs {
      let device = VirtualMTPDevice(config: config)
      let deviceId = await device.id
      let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
      let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

      for row in diff.added {
        let (storageId, components) = PathKey.parse(row.pathKey)
        XCTAssertGreaterThan(storageId, 0, "PathKey storage should be positive for \(config)")
        XCTAssertFalse(components.isEmpty,
          "PathKey should have components for \(row.pathKey)")
      }
    }
  }

  // MARK: - 8. Snapshot generation tracking

  func testLatestGenerationMatchesLastCapture() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let latest = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latest, gen)
  }

  func testPreviousGenerationReturnsPriorSnapshot() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let prev = try snapshotter.previousGeneration(for: deviceId, before: gen2)
    XCTAssertEqual(prev, gen1, "Previous generation should be the first snapshot")
  }

  func testNonExistentDeviceHasNoGeneration() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)

    let fakeId = MTPDeviceID(raw: "nonexistent:device")
    let latest = try snapshotter.latestGeneration(for: fakeId)
    XCTAssertNil(latest, "Non-existent device should have no generation")
  }

  // MARK: - 9. Diff isEmpty property

  func testDiffIsEmptyWhenNoChanges() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }
    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
    try await Task.sleep(nanoseconds: 1_100_000_000)
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertTrue(diff.isEmpty, "Unchanged device should produce empty diff")
    XCTAssertEqual(diff.totalChanges, 0)
  }
}
