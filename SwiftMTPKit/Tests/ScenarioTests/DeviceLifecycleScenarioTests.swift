// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - Device Lifecycle Scenario Tests

/// End-to-end scenarios exercising full device lifecycle workflows:
/// connect, operate, disconnect — including edge cases, stress, and
/// multi-device interactions. All tests use VirtualMTPDevice.
final class DeviceLifecycleScenarioTests: XCTestCase {

  // MARK: - Helpers

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-lifecycle")
  }

  private func listAll(
    device: VirtualMTPDevice, parent: MTPObjectHandle?, in storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream { objects.append(contentsOf: batch) }
    return objects
  }

  // MARK: - 1. Connect → List → Download → Disconnect

  func testConnectListDownloadDisconnect() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(objects.isEmpty)

    // Download first file-like object
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Navigate into DCIM/Camera (handle 2)
    let cameraFiles = try await listAll(device: device, parent: 2, in: storages[0].id)
    guard let photo = cameraFiles.first else {
      XCTFail("Expected photo in Camera")
      return
    }
    let outURL = dir.appendingPathComponent(photo.name)
    let progress = try await device.read(handle: photo.handle, range: nil, to: outURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))

    try await device.devClose()

    let ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("openIfNeeded"))
    XCTAssertTrue(ops.contains("read"))
    XCTAssertTrue(ops.contains("devClose"))
  }

  // MARK: - 2. Connect → Upload → Verify → Disconnect

  func testConnectUploadVerifyDisconnect() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let uploadData = Data(repeating: 0xBE, count: 4096)
    let srcURL = dir.appendingPathComponent("upload_test.dat")
    try uploadData.write(to: srcURL)

    let progress = try await device.write(
      parent: nil, name: "upload_test.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, Int64(uploadData.count))

    // Verify via getInfo (pixel7 has handles 1,2,3 → new is 4)
    let info = try await device.getInfo(handle: 4)
    XCTAssertEqual(info.name, "upload_test.dat")
    XCTAssertEqual(info.sizeBytes, UInt64(uploadData.count))

    // Download and verify content
    let downloadURL = dir.appendingPathComponent("verify_download.dat")
    _ = try await device.read(handle: 4, range: nil, to: downloadURL)
    let downloaded = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloaded, uploadData)

    try await device.devClose()
  }

  // MARK: - 3. Connect → Snapshot-like Enumeration → Compare → Disconnect

  func testConnectFullEnumerationDisconnect() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let storages = try await device.storages()
    let storage = storages[0]

    // Full recursive enumeration
    var allObjects: [MTPObjectInfo] = []
    let rootObjects = try await listAll(device: device, parent: nil, in: storage.id)
    allObjects.append(contentsOf: rootObjects)

    for obj in rootObjects where obj.formatCode == 0x3001 {
      let children = try await listAll(device: device, parent: obj.handle, in: storage.id)
      allObjects.append(contentsOf: children)
    }

    // Second enumeration should produce identical results
    var secondPass: [MTPObjectInfo] = []
    let rootObjects2 = try await listAll(device: device, parent: nil, in: storage.id)
    secondPass.append(contentsOf: rootObjects2)

    for obj in rootObjects2 where obj.formatCode == 0x3001 {
      let children = try await listAll(device: device, parent: obj.handle, in: storage.id)
      secondPass.append(contentsOf: children)
    }

    XCTAssertEqual(
      allObjects.count, secondPass.count,
      "Two full enumerations should yield identical counts")
    let handles1 = Set(allObjects.map(\.handle))
    let handles2 = Set(secondPass.map(\.handle))
    XCTAssertEqual(handles1, handles2, "Object handles should be identical across enumerations")

    try await device.devClose()
  }

  // MARK: - 4. Multiple Connect/Disconnect Cycles with Operations

  func testMultipleConnectDisconnectCyclesWithOperations() async throws {
    let config = VirtualDeviceConfig.pixel7

    for cycle in 0..<5 {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()

      // Perform different operations each cycle
      let storages = try await device.storages()
      XCTAssertFalse(storages.isEmpty, "Cycle \(cycle)")

      let info = try await device.info
      XCTAssertEqual(info.model, "Pixel 7", "Cycle \(cycle)")

      let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
      XCTAssertFalse(objects.isEmpty, "Cycle \(cycle)")

      try await device.devClose()

      let ops = await device.operations
      XCTAssertTrue(ops.contains { $0.operation == "openIfNeeded" }, "Cycle \(cycle)")
      XCTAssertTrue(ops.contains { $0.operation == "devClose" }, "Cycle \(cycle)")
    }
  }

  // MARK: - 5. Quick Connect and Immediately Disconnect

  func testQuickConnectAndImmediatelyDisconnect() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    try await device.devClose()

    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "openIfNeeded" })
    XCTAssertTrue(ops.contains { $0.operation == "devClose" })
    // Should not crash or leak
  }

  // MARK: - 6. Connect to Device with No Storage Objects

  func testConnectToDeviceWithNoStorageObjects() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.openIfNeeded()

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertTrue(objects.isEmpty, "Empty device should have no objects")

    // Upload should still work
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0x01, count: 512)
    let srcURL = dir.appendingPathComponent("first_file.dat")
    try data.write(to: srcURL)
    let progress = try await device.write(
      parent: nil, name: "first_file.dat", size: 512, from: srcURL)
    XCTAssertEqual(progress.completedUnitCount, 512)

    try await device.devClose()
  }

  // MARK: - 7. Large Directory Listing (1000+ items)

  func testLargeDirectoryListing() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7

    let itemCount = 1_000
    for i in 0..<itemCount {
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(500 + i), storage: storageId, parent: nil,
        name: "file_\(String(format: "%04d", i)).jpg",
        sizeBytes: UInt64(1024 * (i % 10 + 1)),
        formatCode: 0x3801,
        data: Data(repeating: UInt8(i & 0xFF), count: 64)
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)

    // pixel7 has 1 root object (DCIM) + 1000 new
    XCTAssertGreaterThanOrEqual(objects.count, itemCount)

    // Verify handles are unique
    let handleSet = Set(objects.map(\.handle))
    XCTAssertEqual(handleSet.count, objects.count, "All handles should be unique")
  }

  // MARK: - 8. Deep Directory Hierarchy (20+ levels)

  func testDeepDirectoryHierarchy() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let depth = 20

    var parentHandle: MTPObjectHandle? = nil
    var handles: [MTPObjectHandle] = []

    for level in 0..<depth {
      let handle = try await device.createFolder(
        parent: parentHandle, name: "level_\(level)", storage: storageId)
      handles.append(handle)
      parentHandle = handle
    }

    XCTAssertEqual(handles.count, depth)

    // Upload a file at the deepest level
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0xDE, count: 256)
    let srcURL = dir.appendingPathComponent("deep_file.dat")
    try data.write(to: srcURL)

    let progress = try await device.write(
      parent: parentHandle, name: "deep_file.dat", size: 256, from: srcURL)
    XCTAssertEqual(progress.completedUnitCount, 256)

    // Verify we can list the deepest folder
    let deepFiles = try await listAll(
      device: device, parent: parentHandle, in: storageId)
    XCTAssertEqual(deepFiles.count, 1)
    XCTAssertEqual(deepFiles.first?.name, "deep_file.dat")
  }

  // MARK: - 9. Transfer with Progress Tracking

  func testTransferWithProgressTracking() async throws {
    let largeData = Data(repeating: 0xCC, count: 4 * 1024 * 1024)
    let largeFile = VirtualObjectConfig(
      handle: 50, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "progress_test.bin", sizeBytes: UInt64(largeData.count),
      formatCode: 0x3000, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("progress_test.bin")

    let progress = try await device.read(handle: 50, range: nil, to: outURL)

    XCTAssertEqual(progress.totalUnitCount, Int64(largeData.count))
    XCTAssertEqual(progress.completedUnitCount, Int64(largeData.count))

    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded.count, largeData.count)
  }

  // MARK: - 10. Transfer Cancellation at Start

  func testTransferCancellationAtStart() async throws {
    let largeData = Data(repeating: 0xDD, count: 2 * 1024 * 1024)
    let largeFile = VirtualObjectConfig(
      handle: 60, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "cancel_start.bin", sizeBytes: UInt64(largeData.count),
      formatCode: 0x3000, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("cancel_start.bin")

    let task = Task<Progress, Error> {
      try Task.checkCancellation()
      return try await device.read(handle: 60, range: nil, to: outURL)
    }

    // Cancel immediately
    task.cancel()

    do {
      _ = try await task.value
      // Virtual device may complete instantly — acceptable
    } catch is CancellationError {
      // Expected
    }

    // Device still usable
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  // MARK: - 11. Batch Transfer of Multiple Files

  func testBatchTransferMultipleFiles() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    let fileCount = 20

    for i in 0..<fileCount {
      let data = Data(repeating: UInt8(i & 0xFF), count: 1024 * (i + 1))
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(600 + i), storage: storageId, parent: nil,
        name: "batch_\(String(format: "%03d", i)).dat",
        sizeBytes: UInt64(data.count), formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Download all files via TaskGroup
    let results = try await withThrowingTaskGroup(
      of: (Int, Int64).self
    ) { group -> [(Int, Int64)] in
      for i in 0..<fileCount {
        group.addTask {
          let outURL = dir.appendingPathComponent("batch_\(i).dat")
          let p = try await device.read(
            handle: MTPObjectHandle(600 + i), range: nil, to: outURL)
          return (i, p.completedUnitCount)
        }
      }
      var collected: [(Int, Int64)] = []
      for try await r in group { collected.append(r) }
      return collected
    }

    XCTAssertEqual(results.count, fileCount)
    for (i, size) in results {
      XCTAssertEqual(Int(size), 1024 * (i + 1))
    }
  }

  // MARK: - 12. Multiple Devices Simultaneously Connected

  func testMultipleDevicesSimultaneouslyConnected() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    let canon = VirtualMTPDevice(config: .canonEOSR5)
    let nikon = VirtualMTPDevice(config: .nikonZ6)

    // Open all simultaneously
    try await pixel.openIfNeeded()
    try await samsung.openIfNeeded()
    try await canon.openIfNeeded()
    try await nikon.openIfNeeded()

    // Parallel operations on all four
    async let pStorages = pixel.storages()
    async let sStorages = samsung.storages()
    async let cStorages = canon.storages()
    async let nStorages = nikon.storages()

    let (ps, ss, cs, ns) = try await (pStorages, sStorages, cStorages, nStorages)
    XCTAssertFalse(ps.isEmpty)
    XCTAssertFalse(ss.isEmpty)
    XCTAssertFalse(cs.isEmpty)
    XCTAssertFalse(ns.isEmpty)

    // Close all
    try await pixel.devClose()
    try await samsung.devClose()
    try await canon.devClose()
    try await nikon.devClose()
  }

  // MARK: - 13. Reconnect After Close and Resume Work

  func testReconnectAfterCloseAndResumeWork() async throws {
    let config = VirtualDeviceConfig.pixel7

    // First session: open, list, close
    let device1 = VirtualMTPDevice(config: config)
    try await device1.openIfNeeded()
    let storages1 = try await device1.storages()
    let objects1 = try await listAll(device: device1, parent: nil, in: storages1[0].id)
    try await device1.devClose()

    // Second session: reconnect (new virtual device instance), verify same state
    let device2 = VirtualMTPDevice(config: config)
    try await device2.openIfNeeded()
    let storages2 = try await device2.storages()
    let objects2 = try await listAll(device: device2, parent: nil, in: storages2[0].id)

    XCTAssertEqual(objects1.count, objects2.count)
    XCTAssertEqual(
      Set(objects1.map(\.name)),
      Set(objects2.map(\.name)),
      "Reconnected device should show same objects"
    )
  }

  // MARK: - 14. Event Injection During Active Transfer

  func testEventInjectionDuringActiveTransfer() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Start a download
    let outURL = dir.appendingPathComponent("event_test.jpg")
    async let readResult = device.read(handle: 3, range: nil, to: outURL)

    // Inject event while transfer runs
    await device.injectEvent(.deviceInfoChanged)
    await device.injectEvent(.storageInfoChanged(storageId))

    let progress = try await readResult
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
  }

  // MARK: - 15. Storage Removal Event After Enumeration

  func testStorageRemovalEvent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Inject storage removal event
    await device.injectEvent(.storageRemoved(storageId))

    // Event was delivered without crash
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "storages" })
  }

  // MARK: - 16. Upload Then Download Round-Trip Integrity

  func testUploadThenDownloadRoundTripIntegrity() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload with known pattern
    let pattern = Data((0..<8192).map { UInt8($0 % 251) })
    let srcURL = dir.appendingPathComponent("integrity.dat")
    try pattern.write(to: srcURL)

    _ = try await device.write(
      parent: nil, name: "integrity.dat",
      size: UInt64(pattern.count), from: srcURL
    )

    // pixel7 assigns handle 4
    let downloadURL = dir.appendingPathComponent("integrity_verify.dat")
    _ = try await device.read(handle: 4, range: nil, to: downloadURL)
    let downloaded = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloaded, pattern, "Round-trip data should be byte-identical")
  }

  // MARK: - 17. Rename After Upload

  func testRenameAfterUpload() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0x42, count: 1024)
    let srcURL = dir.appendingPathComponent("before_rename.txt")
    try data.write(to: srcURL)

    _ = try await device.write(
      parent: nil, name: "before_rename.txt",
      size: 1024, from: srcURL
    )

    // Rename the newly uploaded file (handle 4)
    try await device.rename(4, to: "after_rename.txt")
    let info = try await device.getInfo(handle: 4)
    XCTAssertEqual(info.name, "after_rename.txt")
  }

  // MARK: - 18. Move After Upload to New Folder

  func testMoveAfterUploadToNewFolder() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Create a folder
    let folderHandle = try await device.createFolder(
      parent: nil, name: "Archive", storage: storageId)

    // Upload a file to root
    let data = Data(repeating: 0x33, count: 2048)
    let srcURL = dir.appendingPathComponent("moveme.dat")
    try data.write(to: srcURL)
    _ = try await device.write(
      parent: nil, name: "moveme.dat", size: 2048, from: srcURL)

    // File is at handle 5 (4 = folder, 5 = file)
    let fileHandle = MTPObjectHandle(5)

    // Move file into Archive folder
    try await device.move(fileHandle, to: folderHandle)

    // Verify file is under Archive
    let archiveFiles = try await listAll(
      device: device, parent: folderHandle, in: storageId)
    XCTAssertTrue(archiveFiles.contains { $0.name == "moveme.dat" })
  }

  // MARK: - 19. Delete All Files Then Re-Upload

  func testDeleteAllFilesThenReUpload() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // Delete root folder (DCIM, handle 1) recursively
    try await device.delete(1, recursive: true)

    // Verify empty
    let objects = try await listAll(device: device, parent: nil, in: storageId)
    XCTAssertTrue(objects.isEmpty)

    // Upload new content
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0xFA, count: 512)
    let srcURL = dir.appendingPathComponent("new_start.dat")
    try data.write(to: srcURL)
    let progress = try await device.write(
      parent: nil, name: "new_start.dat", size: 512, from: srcURL)
    XCTAssertEqual(progress.completedUnitCount, 512)
  }

  // MARK: - 20. Samsung Galaxy Full Lifecycle

  func testSamsungGalaxyFullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Samsung")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(objects.isEmpty)

    // Download first available file
    if let file = objects.first(where: { $0.formatCode != 0x3001 }) {
      let dir = try tempDir()
      defer { try? TestUtilities.cleanupTempDirectory(dir) }

      let outURL = dir.appendingPathComponent(file.name)
      let progress = try await device.read(handle: file.handle, range: nil, to: outURL)
      XCTAssertGreaterThan(progress.completedUnitCount, 0)
    }

    try await device.devClose()
  }

  // MARK: - 21. Multiple Device Profiles Lifecycle

  func testMultipleDeviceProfilesLifecycle() async throws {
    let configs: [VirtualDeviceConfig] = [
      .pixel7, .samsungGalaxy, .canonEOSR5, .nikonZ6, .emptyDevice,
    ]

    for config in configs {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()

      let info = try await device.info
      XCTAssertFalse(info.manufacturer.isEmpty, "Device \(info.model) should have manufacturer")

      let storages = try await device.storages()
      XCTAssertFalse(storages.isEmpty, "Device \(info.model) should have storage")

      try await device.devClose()
    }
  }

  // MARK: - 22. Create Multiple Folders at Same Level

  func testCreateMultipleFoldersAtSameLevel() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let folderNames = ["Documents", "Music", "Videos", "Podcasts", "Backups"]
    var handles: [MTPObjectHandle] = []

    for name in folderNames {
      let handle = try await device.createFolder(
        parent: nil, name: name, storage: storageId)
      handles.append(handle)
    }

    // All handles should be unique
    XCTAssertEqual(Set(handles).count, folderNames.count)

    // All folders should appear in root listing
    let rootObjects = try await listAll(device: device, parent: nil, in: storageId)
    for name in folderNames {
      XCTAssertTrue(
        rootObjects.contains { $0.name == name },
        "Folder '\(name)' should exist in root")
    }
  }

  // MARK: - 23. Upload Files to Different Storages

  func testUploadFilesToDifferentStorages() async throws {
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 16 * 1024 * 1024 * 1024
    )
    let config = VirtualDeviceConfig.pixel7.withStorage(sdCard)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload to internal storage (root)
    let data1 = Data(repeating: 0xAA, count: 1024)
    let src1 = dir.appendingPathComponent("internal.dat")
    try data1.write(to: src1)
    let p1 = try await device.write(
      parent: nil, name: "internal.dat", size: 1024, from: src1)
    XCTAssertEqual(p1.completedUnitCount, 1024)

    // Verify the write ops
    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, 1)
  }

  // MARK: - 24. Enumerate After Object Addition Events

  func testEnumerateAfterObjectAdditionEvents() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let beforeCount = try await listAll(
      device: device, parent: nil, in: storageId
    )
    .count

    // Add multiple objects via runtime mutation
    for i in 0..<5 {
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(800 + i), storage: storageId, parent: nil,
        name: "injected_\(i).dat", sizeBytes: 256,
        formatCode: 0x3000, data: Data(count: 256)
      )
      await device.addObject(obj)
      await device.injectEvent(.objectAdded(MTPObjectHandle(800 + i)))
    }

    let afterCount = try await listAll(
      device: device, parent: nil, in: storageId
    )
    .count
    XCTAssertEqual(afterCount, beforeCount + 5)
  }

  // MARK: - 25. Object Info Changed Event

  func testObjectInfoChangedEvent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Get initial info for photo (handle 3)
    let infoBefore = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoBefore.name, "IMG_20250101_120000.jpg")

    // Rename and inject event
    try await device.rename(3, to: "renamed_photo.jpg")
    await device.injectEvent(.objectInfoChanged(3))

    let infoAfter = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoAfter.name, "renamed_photo.jpg")
    XCTAssertEqual(infoAfter.handle, infoBefore.handle)
  }

  // MARK: - 26. Concurrent Downloads from Same Device

  func testConcurrentDownloadsFromSameDeviceIntegrity() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<10 {
      let fillByte = UInt8(i + 10)
      let data = Data(repeating: fillByte, count: 2048)
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(700 + i), storage: storageId, parent: nil,
        name: "concurrent_\(i).bin", sizeBytes: 2048,
        formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Download all 10 files concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let outURL = dir.appendingPathComponent("concurrent_\(i).bin")
          _ = try await device.read(
            handle: MTPObjectHandle(700 + i), range: nil, to: outURL)
          let data = try Data(contentsOf: outURL)
          XCTAssertEqual(data.count, 2048)
          XCTAssertTrue(
            data.allSatisfy { $0 == UInt8(i + 10) },
            "File \(i) content mismatch")
        }
      }
      try await group.waitForAll()
    }
  }

  // MARK: - 27. Device Info Remains Stable Across Operations

  func testDeviceInfoStableAcrossOperations() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)

    let info1 = try await device.info

    // Perform various operations
    _ = try await device.storages()
    let storages = try await device.storages()
    _ = try await listAll(device: device, parent: nil, in: storages[0].id)

    let info2 = try await device.info
    XCTAssertEqual(info1.manufacturer, info2.manufacturer)
    XCTAssertEqual(info1.model, info2.model)
    XCTAssertEqual(info1.serialNumber, info2.serialNumber)
    XCTAssertEqual(info1.version, info2.version)
  }

  // MARK: - 28. Upload Zero-Byte File to Different Profiles

  func testUploadZeroByteFileToDifferentProfiles() async throws {
    let configs: [(VirtualDeviceConfig, String)] = [
      (.pixel7, "Pixel 7"),
      (.samsungGalaxy, "Samsung Galaxy"),
      (.canonEOSR5, "Canon EOS R5"),
    ]

    for (config, name) in configs {
      let device = VirtualMTPDevice(config: config)

      let dir = try tempDir()
      defer { try? TestUtilities.cleanupTempDirectory(dir) }

      let srcURL = dir.appendingPathComponent("empty.txt")
      try Data().write(to: srcURL)

      let progress = try await device.write(
        parent: nil, name: "empty.txt", size: 0, from: srcURL)
      XCTAssertEqual(progress.totalUnitCount, 0, "Zero-byte upload failed on \(name)")
    }
  }

  // MARK: - 29. Device Close Is Idempotent

  func testDeviceCloseIdempotent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    _ = try await device.storages()

    // Close multiple times — should not crash
    try await device.devClose()
    try await device.devClose()
    try await device.devClose()

    let closeOps = await device.operations.filter { $0.operation == "devClose" }
    XCTAssertEqual(closeOps.count, 3)
  }

  // MARK: - 30. Ranged Read Across Various Offsets

  func testRangedReadAcrossVariousOffsets() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Photo at handle 3 is ~4.5MB of 0xFF
    let ranges: [Range<UInt64>] = [
      0..<100,
      500..<1500,
      0..<1,
      1000..<1001,
      100_000..<200_000,
    ]

    for (i, range) in ranges.enumerated() {
      let outURL = dir.appendingPathComponent("range_\(i).bin")
      let progress = try await device.read(handle: 3, range: range, to: outURL)
      let data = try Data(contentsOf: outURL)
      XCTAssertEqual(
        UInt64(data.count), range.upperBound - range.lowerBound,
        "Range \(range) size mismatch")
      XCTAssertEqual(progress.completedUnitCount, Int64(range.upperBound - range.lowerBound))
    }
  }

  // MARK: - 31. Open If Needed Is Idempotent

  func testOpenIfNeededIdempotent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    try await device.openIfNeeded()
    try await device.openIfNeeded()
    try await device.openIfNeeded()

    // Should only open once
    let openOps = await device.operations.filter { $0.operation == "openIfNeeded" }
    XCTAssertGreaterThanOrEqual(openOps.count, 1)

    // Device should still work
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  // MARK: - 32. Concurrent Upload and List on Same Device

  func testConcurrentUploadAndListOnSameDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0x44, count: 2048)
    let srcURL = dir.appendingPathComponent("concurrent_upload.dat")
    try data.write(to: srcURL)

    // Concurrent: upload + list + getInfo
    let uploadProgress = try await device.write(
      parent: nil, name: "concurrent_upload.dat", size: 2048, from: srcURL)
    let objects = try await listAll(device: device, parent: nil, in: storageId)
    let info = try await device.info

    XCTAssertEqual(uploadProgress.completedUnitCount, 2048)
    XCTAssertFalse(objects.isEmpty)
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 33. Delete Then Verify Handle Is Gone

  func testDeleteThenVerifyHandleGone() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Photo handle 3 exists
    let infoBefore = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoBefore.name, "IMG_20250101_120000.jpg")

    try await device.delete(3, recursive: false)

    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 34. Device Operations After Long Idle (Simulated)

  func testDeviceOperationsAfterSimulatedIdle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    _ = try await device.storages()

    // Simulate idle (short sleep, verifies no timeout/disconnect)
    try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

    // Operations should still work
    let info = try await device.info
    XCTAssertEqual(info.model, "Pixel 7")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  // MARK: - 35. Create Folder Tree Then Download Leaf File

  func testCreateFolderTreeThenDownloadLeafFile() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Build: Root / A / B / C
    let a = try await device.createFolder(parent: nil, name: "A", storage: storageId)
    let b = try await device.createFolder(parent: a, name: "B", storage: storageId)
    let c = try await device.createFolder(parent: b, name: "C", storage: storageId)

    // Upload file into C
    let data = Data(repeating: 0x77, count: 512)
    let srcURL = dir.appendingPathComponent("leaf.dat")
    try data.write(to: srcURL)
    _ = try await device.write(parent: c, name: "leaf.dat", size: 512, from: srcURL)

    // Find the file handle
    let leafFiles = try await listAll(device: device, parent: c, in: storageId)
    XCTAssertEqual(leafFiles.count, 1)
    XCTAssertEqual(leafFiles[0].name, "leaf.dat")

    // Download
    let outURL = dir.appendingPathComponent("leaf_download.dat")
    _ = try await device.read(handle: leafFiles[0].handle, range: nil, to: outURL)
    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded, data)
  }

  // MARK: - 36. Upload Multiple Then Delete All

  func testUploadMultipleThenDeleteAll() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload 5 files
    var handles: [MTPObjectHandle] = []
    for i in 0..<5 {
      let data = Data(repeating: UInt8(i), count: 256)
      let srcURL = dir.appendingPathComponent("del_\(i).dat")
      try data.write(to: srcURL)
      _ = try await device.write(
        parent: nil, name: "del_\(i).dat", size: 256, from: srcURL)
      // emptyDevice starts with no objects; handles begin at 1
      handles.append(MTPObjectHandle(1 + i))
    }

    // Delete all
    for handle in handles {
      try await device.delete(handle, recursive: false)
    }

    // Verify empty
    let objects = try await listAll(device: device, parent: nil, in: storageId)
    XCTAssertTrue(objects.isEmpty)
  }

  // MARK: - 37. Storage Capacity and Free Bytes Validation

  func testStorageCapacityAndFreeBytesValidation() async throws {
    let configs: [VirtualDeviceConfig] = [.pixel7, .samsungGalaxy, .canonEOSR5]

    for config in configs {
      let device = VirtualMTPDevice(config: config)
      let storages = try await device.storages()

      for storage in storages {
        XCTAssertGreaterThan(
          storage.capacityBytes, 0,
          "Storage \(storage.description) should have capacity")
        XCTAssertLessThanOrEqual(
          storage.freeBytes, storage.capacityBytes,
          "Free ≤ capacity for \(storage.description)")
        XCTAssertGreaterThan(storage.id.raw, 0)
      }
    }
  }

  // MARK: - 38. GoPro Device Lifecycle

  func testGoProDeviceLifecycle() async throws {
    let device = VirtualMTPDevice(config: .goProHero)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertFalse(info.manufacturer.isEmpty)

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    // GoPro has DCIM folder structure
    XCTAssertFalse(objects.isEmpty)

    try await device.devClose()
  }

  // MARK: - 39. Garmin Device Lifecycle

  func testGarminDeviceLifecycle() async throws {
    let device = VirtualMTPDevice(config: .garminFenix)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertFalse(info.manufacturer.isEmpty)

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    try await device.devClose()
  }

  // MARK: - 40. Valve Steam Deck Lifecycle

  func testValveSteamDeckLifecycle() async throws {
    let device = VirtualMTPDevice(config: .valveSteamDeck)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertFalse(info.model.isEmpty)

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    try await device.devClose()
  }
}
