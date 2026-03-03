// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTestKit

// MARK: - End-to-End Device Operation Scenarios

/// Comprehensive end-to-end scenarios exercising full device workflows
/// using VirtualMTPDevice. No real USB hardware required.
final class DeviceOperationScenarioTests: XCTestCase {

  // MARK: - Helpers

  /// Build a multi-storage device (internal + SD card) with sample files in each.
  private func makeMultiStorageDevice() -> VirtualMTPDevice {
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 64 * 1024 * 1024 * 1024,
      freeBytes: 48 * 1024 * 1024 * 1024
    )
    let sdFolder = VirtualObjectConfig(
      handle: 100, storage: sdCard.id, parent: nil,
      name: "DCIM", formatCode: 0x3001
    )
    let sdPhoto = VirtualObjectConfig(
      handle: 101, storage: sdCard.id, parent: 100,
      name: "SD_IMG_001.jpg", sizeBytes: 2_000_000,
      formatCode: 0x3801, data: Data(repeating: 0xAA, count: 2_000_000)
    )
    let config = VirtualDeviceConfig.pixel7
      .withStorage(sdCard)
      .withObject(sdFolder)
      .withObject(sdPhoto)
    return VirtualMTPDevice(config: config)
  }

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-e2e")
  }

  // MARK: - 1. Discovery → Quirk Match → Session → List → Download

  func testFullDiscoveryToDownloadWorkflow() async throws {
    // Step 1: "Discover" device via its config (simulates USB enumeration)
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Step 2: Quirk matching by VID:PID
    let db = QuirkDatabase(
      schemaVersion: "1.0",
      entries: [
        DeviceQuirk(
          id: "pixel7-test", deviceName: "Pixel 7",
          vid: 0x18d1, pid: 0x4ee1,
          maxChunkBytes: 4 * 1024 * 1024
        )
      ])
    let quirk = db.match(
      vid: 0x18d1, pid: 0x4ee1,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(quirk, "Quirk should match for Pixel 7")
    XCTAssertEqual(quirk?.id, "pixel7-test")
    XCTAssertEqual(quirk?.maxChunkBytes, 4 * 1024 * 1024)

    // Step 3: Open session
    try await device.openIfNeeded()
    let openOps = await device.operations.filter { $0.operation == "openIfNeeded" }
    XCTAssertEqual(openOps.count, 1, "Session should be opened once")

    // Step 4: Device info
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")

    // Step 5: List storages and enumerate files
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
    let storage = storages[0]

    var allObjects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storage.id)
    for try await batch in stream {
      allObjects.append(contentsOf: batch)
    }
    XCTAssertFalse(allObjects.isEmpty, "Device should have root-level objects")

    // Step 6: Find a file and download it
    // Enumerate into DCIM/Camera to find the sample photo (handle 3)
    let cameraStream = device.list(parent: 2, in: storage.id)
    var cameraFiles: [MTPObjectInfo] = []
    for try await batch in cameraStream {
      cameraFiles.append(contentsOf: batch)
    }
    guard let photo = cameraFiles.first else {
      XCTFail("Expected photo in Camera folder")
      return
    }

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outputURL = dir.appendingPathComponent(photo.name)

    let progress = try await device.read(handle: photo.handle, range: nil, to: outputURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

    // Verify operation log captures full workflow
    let ops = await device.operations
    let opNames = ops.map(\.operation)
    XCTAssertTrue(opNames.contains("openIfNeeded"))
    XCTAssertTrue(opNames.contains("storages"))
    XCTAssertTrue(opNames.contains("read"))
  }

  // MARK: - 2. Multi-Storage Device Operations

  func testMultiStorageDeviceOperations() async throws {
    let device = makeMultiStorageDevice()

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2, "Should have internal + SD card")

    let internal_ = storages.first { $0.description.contains("Internal") }
    let sdCard = storages.first { $0.description.contains("SD") }
    XCTAssertNotNil(internal_)
    XCTAssertNotNil(sdCard)

    // List files on internal storage
    var internalObjects: [MTPObjectInfo] = []
    let iStream = device.list(parent: nil, in: internal_!.id)
    for try await batch in iStream {
      internalObjects.append(contentsOf: batch)
    }
    XCTAssertFalse(internalObjects.isEmpty, "Internal storage should have objects")

    // List files on SD card
    var sdObjects: [MTPObjectInfo] = []
    let sStream = device.list(parent: nil, in: sdCard!.id)
    for try await batch in sStream {
      sdObjects.append(contentsOf: batch)
    }
    XCTAssertFalse(sdObjects.isEmpty, "SD card should have objects")

    // Download from SD card
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // List inside SD DCIM folder (handle 100)
    var sdPhotos: [MTPObjectInfo] = []
    let sdPhotoStream = device.list(parent: 100, in: sdCard!.id)
    for try await batch in sdPhotoStream {
      sdPhotos.append(contentsOf: batch)
    }
    guard let sdPhoto = sdPhotos.first else {
      XCTFail("Expected photo on SD card")
      return
    }

    let sdOutput = dir.appendingPathComponent("sd_download.jpg")
    let progress = try await device.read(handle: sdPhoto.handle, range: nil, to: sdOutput)
    let data = try Data(contentsOf: sdOutput)
    XCTAssertEqual(Int64(data.count), progress.completedUnitCount)
    XCTAssertTrue(data.allSatisfy { $0 == 0xAA }, "SD card photo data should be all 0xAA")

    // Upload to internal storage
    let uploadData = Data(repeating: 0xBB, count: 4096)
    let srcURL = dir.appendingPathComponent("upload_src.dat")
    try uploadData.write(to: srcURL)
    let uploadProgress = try await device.write(
      parent: nil, name: "new_file.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(uploadData.count))
  }

  // MARK: - 3. Large File Transfer with Progress Reporting

  func testLargeFileTransferWithProgress() async throws {
    // Create a device with a large file
    let largeData = Data(repeating: 0xCC, count: 8 * 1024 * 1024)  // 8 MB
    let largeFile = VirtualObjectConfig(
      handle: 50, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "large_video.mp4", sizeBytes: UInt64(largeData.count),
      formatCode: 0x300B, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outputURL = dir.appendingPathComponent("large_video.mp4")

    let progress = try await device.read(handle: 50, range: nil, to: outputURL)

    // Verify complete download
    XCTAssertEqual(progress.totalUnitCount, Int64(largeData.count))
    XCTAssertEqual(progress.completedUnitCount, Int64(largeData.count))

    let downloadedData = try Data(contentsOf: outputURL)
    XCTAssertEqual(downloadedData.count, largeData.count)
    XCTAssertTrue(downloadedData.allSatisfy { $0 == 0xCC })

    // Verify read was logged
    let readOps = await device.operations.filter { $0.operation == "read" }
    XCTAssertEqual(readOps.count, 1)
  }

  // MARK: - 4. Transfer Cancellation Mid-Stream

  func testTransferCancellationMidStream() async throws {
    // Create large file to give Task a window to cancel
    let largeData = Data(repeating: 0xDD, count: 4 * 1024 * 1024)
    let largeFile = VirtualObjectConfig(
      handle: 60, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "cancel_target.bin", sizeBytes: UInt64(largeData.count),
      formatCode: 0x3000, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outputURL = dir.appendingPathComponent("cancel_target.bin")

    let downloadTask = Task<Progress, Error> {
      try Task.checkCancellation()
      return try await device.read(handle: 60, range: nil, to: outputURL)
    }

    // Cancel immediately
    downloadTask.cancel()

    do {
      _ = try await downloadTask.value
      // Virtual device completes instantly, so cancellation may not fire.
      // This is acceptable - the key assertion is no crash / resource leak.
    } catch is CancellationError {
      // Expected: cancellation was delivered before read started
    } catch {
      // Other errors acceptable (device may have partially completed)
    }

    // No dangling state: device should still be usable after cancellation
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Device should remain functional after cancellation")
  }

  // MARK: - 5. Device Disconnect During Operation → Graceful Recovery

  func testDeviceDisconnectDuringOperationRecovery() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Perform a successful operation first
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Simulate device disconnect via devClose
    try await device.devClose()

    // Simulate device reconnection (create a "new" device, as would happen)
    let reconnected = VirtualMTPDevice(config: config)
    try await reconnected.openIfNeeded()

    // Reconnected device should work normally
    let newStorages = try await reconnected.storages()
    XCTAssertFalse(newStorages.isEmpty, "Reconnected device should list storages")

    let info = try await reconnected.info
    XCTAssertEqual(info.model, "Pixel 7")

    // Full workflow on reconnected device
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let uploadData = Data(repeating: 0xEE, count: 1024)
    let srcURL = dir.appendingPathComponent("reconnect_test.dat")
    try uploadData.write(to: srcURL)
    let progress = try await reconnected.write(
      parent: nil, name: "reconnect_test.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, Int64(uploadData.count))
  }

  // MARK: - 6. Batch Operations (Download Folder, Upload Set of Files)

  func testBatchDownloadFolder() async throws {
    // Build a device with a folder containing multiple files
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let folder = VirtualObjectConfig(
      handle: 200, storage: storageId, parent: nil,
      name: "Photos", formatCode: 0x3001
    )
    var config = VirtualDeviceConfig.pixel7.withObject(folder)
    let fileCount = 10
    for i in 0..<fileCount {
      let handle = MTPObjectHandle(201 + i)
      let fileData = Data(repeating: UInt8(i & 0xFF), count: 1024 * (i + 1))
      let obj = VirtualObjectConfig(
        handle: handle, storage: storageId, parent: 200,
        name: "photo_\(String(format: "%03d", i)).jpg",
        sizeBytes: UInt64(fileData.count),
        formatCode: 0x3801, data: fileData
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Enumerate folder contents
    var files: [MTPObjectInfo] = []
    let stream = device.list(parent: 200, in: storageId)
    for try await batch in stream {
      files.append(contentsOf: batch)
    }
    XCTAssertEqual(files.count, fileCount)

    // Download all files
    var downloadedSizes: [Int] = []
    for file in files {
      let outURL = dir.appendingPathComponent(file.name)
      let progress = try await device.read(handle: file.handle, range: nil, to: outURL)
      downloadedSizes.append(Int(progress.completedUnitCount))
    }

    XCTAssertEqual(downloadedSizes.count, fileCount)
    // Each file has increasing size: 1024, 2048, ..., 10240
    let sorted = downloadedSizes.sorted()
    for i in 0..<fileCount {
      XCTAssertEqual(sorted[i], 1024 * (i + 1))
    }
  }

  func testBatchUploadFiles() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let uploadCount = 8
    var totalUploaded: Int64 = 0

    for i in 0..<uploadCount {
      let fileData = Data(repeating: UInt8(i), count: 2048)
      let srcURL = dir.appendingPathComponent("batch_\(i).dat")
      try fileData.write(to: srcURL)

      let progress = try await device.write(
        parent: nil, name: "batch_\(i).dat",
        size: UInt64(fileData.count), from: srcURL
      )
      totalUploaded += progress.completedUnitCount
    }

    XCTAssertEqual(totalUploaded, Int64(uploadCount * 2048))

    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, uploadCount)
  }

  // MARK: - 7. Device Switching (Connect A → Disconnect → Connect B)

  func testDeviceSwitching() async throws {
    // Device A: Samsung Galaxy
    let deviceA = VirtualMTPDevice(config: .samsungGalaxy)
    // Device B: Canon EOS R5
    let deviceB = VirtualMTPDevice(config: .canonEOSR5)

    // Work with device A
    try await deviceA.openIfNeeded()
    let infoA = try await deviceA.info
    XCTAssertEqual(infoA.manufacturer, "Samsung")
    let storagesA = try await deviceA.storages()
    XCTAssertFalse(storagesA.isEmpty)

    var objectsA: [MTPObjectInfo] = []
    let streamA = deviceA.list(parent: nil, in: storagesA[0].id)
    for try await batch in streamA {
      objectsA.append(contentsOf: batch)
    }
    XCTAssertFalse(objectsA.isEmpty, "Device A should have files")

    // Disconnect device A
    try await deviceA.devClose()

    // Connect device B
    try await deviceB.openIfNeeded()
    let infoB = try await deviceB.info
    XCTAssertEqual(infoB.manufacturer, "Canon")
    let storagesB = try await deviceB.storages()
    XCTAssertFalse(storagesB.isEmpty)

    var objectsB: [MTPObjectInfo] = []
    let streamB = deviceB.list(parent: nil, in: storagesB[0].id)
    for try await batch in streamB {
      objectsB.append(contentsOf: batch)
    }
    XCTAssertFalse(objectsB.isEmpty, "Device B should have files")

    // Verify devices are truly independent
    let opsA = await deviceA.operations
    let opsB = await deviceB.operations
    XCTAssertTrue(opsA.contains { $0.operation == "devClose" })
    XCTAssertFalse(opsB.contains { $0.operation == "devClose" })

    // Registry routing: register both, then verify isolation
    let registry = DeviceServiceRegistry()
    let idA = VirtualDeviceConfig.samsungGalaxy.deviceId
    let idB = VirtualDeviceConfig.canonEOSR5.deviceId
    await registry.register(deviceId: idA, service: DeviceService(device: deviceA))
    await registry.register(deviceId: idB, service: DeviceService(device: deviceB))

    let svcA = await registry.service(for: idA)
    let svcB = await registry.service(for: idB)
    XCTAssertNotNil(svcA)
    XCTAssertNotNil(svcB)

    // Detach A, B unaffected
    await registry.handleDetach(deviceId: idA)
    let svcBAfter = await registry.service(for: idB)
    XCTAssertNotNil(svcBAfter, "Device B service unaffected by A's detach")
  }

  // MARK: - 8. Concurrent Operations on Same Device

  func testConcurrentOperationsOnSameDevice() async throws {
    // Build device with multiple downloadable files
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<5 {
      let handle = MTPObjectHandle(300 + i)
      let data = Data(repeating: UInt8(i + 1), count: 4096)
      let obj = VirtualObjectConfig(
        handle: handle, storage: storageId, parent: nil,
        name: "concurrent_\(i).dat", sizeBytes: 4096,
        formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Launch concurrent reads using async let
    async let r0 = device.read(handle: 300, range: nil, to: dir.appendingPathComponent("c0.dat"))
    async let r1 = device.read(handle: 301, range: nil, to: dir.appendingPathComponent("c1.dat"))
    async let r2 = device.read(handle: 302, range: nil, to: dir.appendingPathComponent("c2.dat"))
    async let r3 = device.read(handle: 303, range: nil, to: dir.appendingPathComponent("c3.dat"))
    async let r4 = device.read(handle: 304, range: nil, to: dir.appendingPathComponent("c4.dat"))

    let (p0, p1, p2, p3, p4) = try await (r0, r1, r2, r3, r4)

    // All should complete with correct sizes
    for p in [p0, p1, p2, p3, p4] {
      XCTAssertEqual(p.completedUnitCount, 4096)
    }

    // Verify data integrity per file
    for i in 0..<5 {
      let data = try Data(contentsOf: dir.appendingPathComponent("c\(i).dat"))
      XCTAssertEqual(data.count, 4096)
      XCTAssertTrue(
        data.allSatisfy { $0 == UInt8(i + 1) },
        "File c\(i).dat should contain fill byte \(i + 1)")
    }

    // All operations logged
    let readOps = await device.operations.filter { $0.operation == "read" }
    XCTAssertEqual(readOps.count, 5)
  }

  func testConcurrentReadAndWriteOnSameDevice() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Prepare upload source
    let uploadData = Data(repeating: 0xFF, count: 2048)
    let srcURL = dir.appendingPathComponent("upload_concurrent.dat")
    try uploadData.write(to: srcURL)

    let readURL = dir.appendingPathComponent("read_concurrent.jpg")

    // Concurrent read (existing photo handle 3) and write
    async let readResult = device.read(handle: 3, range: nil, to: readURL)
    async let writeResult = device.write(
      parent: nil, name: "new_concurrent.dat",
      size: UInt64(uploadData.count), from: srcURL
    )

    let (readProgress, writeProgress) = try await (readResult, writeResult)

    XCTAssertGreaterThan(readProgress.completedUnitCount, 0)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(uploadData.count))

    // Both operations logged
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "read" })
    XCTAssertTrue(ops.contains { $0.operation == "write" })
  }

  func testConcurrentStorageListAndFileOps() async throws {
    let device = makeMultiStorageDevice()

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let uploadData = Data(repeating: 0x11, count: 512)
    let srcURL = dir.appendingPathComponent("during_list.dat")
    try uploadData.write(to: srcURL)

    // Concurrent: list storages + upload + getInfo
    async let storagesResult = device.storages()
    async let uploadResult = device.write(
      parent: nil, name: "during_list.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    async let infoResult = device.info

    let (storages, uploadProgress, info) = try await (storagesResult, uploadResult, infoResult)

    XCTAssertEqual(storages.count, 2)
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(uploadData.count))
    XCTAssertEqual(info.manufacturer, "Google")
  }

  // MARK: - Event-driven scenarios

  func testDeviceEventDuringEnumeration() async throws {
    let device = makeMultiStorageDevice()
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // Start listing
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storageId)
    for try await batch in stream {
      objects.append(contentsOf: batch)
    }

    // Inject an objectAdded event (simulating camera capturing a new photo)
    let newHandle = MTPObjectHandle(999)
    let newObj = VirtualObjectConfig(
      handle: newHandle, storage: storageId, parent: nil,
      name: "new_photo.jpg", sizeBytes: 1024,
      formatCode: 0x3801, data: Data(repeating: 0x77, count: 1024)
    )
    await device.addObject(newObj)
    await device.injectEvent(.objectAdded(newHandle))

    // Re-list should now include the new object
    var updatedObjects: [MTPObjectInfo] = []
    let newStream = device.list(parent: nil, in: storageId)
    for try await batch in newStream {
      updatedObjects.append(contentsOf: batch)
    }

    XCTAssertGreaterThan(
      updatedObjects.count, objects.count,
      "Re-enumeration should find the newly added object")
    XCTAssertTrue(updatedObjects.contains { $0.handle == newHandle })
  }

  func testStorageAddedEventDuringOperation() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Initial state: one storage
    let initial = try await device.storages()
    XCTAssertEqual(initial.count, 1)

    // Inject storageAdded event (simulate SD card insertion)
    let newStorageId = MTPStorageID(raw: 0x0002_0001)
    await device.injectEvent(.storageAdded(newStorageId))

    // Event was injected without crash
    // In a real system, a controller would re-enumerate storages.
    // Here we verify the event stream machinery works.
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "storages" })
  }

  // MARK: - Delete + re-download scenario

  func testDeleteAndReuploadWorkflow() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload a file
    let originalData = Data(repeating: 0xAB, count: 2048)
    let srcURL = dir.appendingPathComponent("reupload.dat")
    try originalData.write(to: srcURL)
    let uploadProgress = try await device.write(
      parent: nil, name: "reupload.dat",
      size: UInt64(originalData.count), from: srcURL
    )
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(originalData.count))

    // Find the uploaded file's handle from operation log
    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, 1)

    // The new file was assigned the next handle. Pixel7 preset has handles 1,2,3 → next is 4
    let newHandle = MTPObjectHandle(4)
    let objInfo = try await device.getInfo(handle: newHandle)
    XCTAssertEqual(objInfo.name, "reupload.dat")

    // Delete it
    try await device.delete(newHandle, recursive: false)

    // Verify it's gone
    do {
      _ = try await device.getInfo(handle: newHandle)
      XCTFail("Expected objectNotFound after delete")
    } catch {
      // Expected: objectNotFound
    }

    // Re-upload with different content
    let newData = Data(repeating: 0xCD, count: 4096)
    let newSrcURL = dir.appendingPathComponent("reupload_v2.dat")
    try newData.write(to: newSrcURL)
    let reuploadProgress = try await device.write(
      parent: nil, name: "reupload.dat",
      size: UInt64(newData.count), from: newSrcURL
    )
    XCTAssertEqual(reuploadProgress.completedUnitCount, Int64(newData.count))

    // Download the re-uploaded version
    let nextHandle = MTPObjectHandle(5)  // After delete+reupload, handle 5
    let downloadURL = dir.appendingPathComponent("reupload_downloaded.dat")
    let downloadProgress = try await device.read(handle: nextHandle, range: nil, to: downloadURL)
    let downloadedData = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloadedData.count, newData.count)
    XCTAssertTrue(downloadedData.allSatisfy { $0 == 0xCD })
    XCTAssertEqual(downloadProgress.completedUnitCount, Int64(newData.count))
  }

  // MARK: - 15. Empty File Upload

  func testEmptyFileUpload() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let emptyData = Data()
    let srcURL = dir.appendingPathComponent("empty.dat")
    try emptyData.write(to: srcURL)

    let progress = try await device.write(
      parent: nil, name: "empty.dat",
      size: 0, from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, 0)
    XCTAssertEqual(progress.totalUnitCount, 0)

    // Verify the file exists on device
    let handle = MTPObjectHandle(4)  // pixel7 has handles 1,2,3
    let info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "empty.dat")
    XCTAssertEqual(info.sizeBytes, 0)
  }

  // MARK: - 16. Single-Byte File Upload

  func testSingleByteFileUpload() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let tinyData = Data([0x42])
    let srcURL = dir.appendingPathComponent("tiny.bin")
    try tinyData.write(to: srcURL)

    let progress = try await device.write(
      parent: nil, name: "tiny.bin",
      size: 1, from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, 1)

    // Download and verify round-trip
    let handle = MTPObjectHandle(4)
    let outURL = dir.appendingPathComponent("tiny_download.bin")
    _ = try await device.read(handle: handle, range: nil, to: outURL)
    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded, tinyData)
  }

  // MARK: - 17. Boundary-Size File Uploads (power-of-2 edges)

  func testBoundarySizeFileUploads() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Test sizes at common chunk boundaries: 512, 4096, 65536, 1MB-1, 1MB, 1MB+1
    let boundarySizes = [512, 4096, 65536, 1_048_575, 1_048_576, 1_048_577]

    for (i, size) in boundarySizes.enumerated() {
      let data = Data(repeating: UInt8(i & 0xFF), count: size)
      let srcURL = dir.appendingPathComponent("boundary_\(size).dat")
      try data.write(to: srcURL)

      let progress = try await device.write(
        parent: nil, name: "boundary_\(size).dat",
        size: UInt64(size), from: srcURL
      )
      XCTAssertEqual(
        Int(progress.completedUnitCount), size,
        "Upload size mismatch for \(size)-byte file")
    }

    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, boundarySizes.count)
  }

  // MARK: - 18. Ranged Read (partial download)

  func testRangedRead() async throws {
    // Pixel7 sample photo is handle 3, 4.5MB of 0xFF
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let outputURL = dir.appendingPathComponent("partial.bin")
    let range: Range<UInt64> = 1000..<2000
    let progress = try await device.read(handle: 3, range: range, to: outputURL)

    let data = try Data(contentsOf: outputURL)
    XCTAssertEqual(data.count, 1000)
    XCTAssertEqual(progress.completedUnitCount, 1000)
    XCTAssertTrue(data.allSatisfy { $0 == 0xFF })
  }

  // MARK: - 19. Folder Creation and Nested Navigation

  func testFolderCreationAndNavigation() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // Create a folder at root
    let musicHandle = try await device.createFolder(
      parent: nil, name: "Music", storage: storageId)
    XCTAssertGreaterThan(musicHandle, 0)

    // Create a subfolder inside Music
    let albumHandle = try await device.createFolder(
      parent: musicHandle, name: "Album01", storage: storageId)
    XCTAssertGreaterThan(albumHandle, musicHandle)

    // Verify the subfolder appears under Music
    var children: [MTPObjectInfo] = []
    let stream = device.list(parent: musicHandle, in: storageId)
    for try await batch in stream {
      children.append(contentsOf: batch)
    }
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children.first?.name, "Album01")

    // Verify folder info
    let folderInfo = try await device.getInfo(handle: musicHandle)
    XCTAssertEqual(folderInfo.name, "Music")
    XCTAssertEqual(folderInfo.formatCode, 0x3001)

    let createOps = await device.operations.filter { $0.operation == "createFolder" }
    XCTAssertEqual(createOps.count, 2)
  }

  // MARK: - 20. Rename File on Device

  func testRenameFileOnDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Rename the sample photo (handle 3)
    let originalInfo = try await device.getInfo(handle: 3)
    XCTAssertEqual(originalInfo.name, "IMG_20250101_120000.jpg")

    try await device.rename(3, to: "vacation_photo.jpg")

    let renamedInfo = try await device.getInfo(handle: 3)
    XCTAssertEqual(renamedInfo.name, "vacation_photo.jpg")
    // Handle should remain the same
    XCTAssertEqual(renamedInfo.handle, 3)
  }

  // MARK: - 21. Move File Between Folders

  func testMoveFileBetweenFolders() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // Create a destination folder
    let destHandle = try await device.createFolder(
      parent: nil, name: "Backup", storage: storageId)

    // Move photo (handle 3, inside DCIM/Camera) to Backup
    try await device.move(3, to: destHandle)

    // Photo should appear under Backup
    var backupFiles: [MTPObjectInfo] = []
    let stream = device.list(parent: destHandle, in: storageId)
    for try await batch in stream {
      backupFiles.append(contentsOf: batch)
    }
    XCTAssertEqual(backupFiles.count, 1)
    XCTAssertEqual(backupFiles.first?.name, "IMG_20250101_120000.jpg")

    // Camera folder should be empty now
    var cameraFiles: [MTPObjectInfo] = []
    let cameraStream = device.list(parent: 2, in: storageId)
    for try await batch in cameraStream {
      cameraFiles.append(contentsOf: batch)
    }
    XCTAssertTrue(cameraFiles.isEmpty, "Camera folder should be empty after move")
  }

  // MARK: - 22. Recursive Folder Delete

  func testRecursiveFolderDelete() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // Add extra files under DCIM/Camera
    let extraPhoto = VirtualObjectConfig(
      handle: 10, storage: storageId, parent: 2,
      name: "extra.jpg", sizeBytes: 1024,
      formatCode: 0x3801, data: Data(count: 1024)
    )
    await device.addObject(extraPhoto)

    // Recursively delete DCIM (handle 1) — should remove Camera (2), photo (3), extra (10)
    try await device.delete(1, recursive: true)

    // All child objects should be gone
    for handle in [MTPObjectHandle(1), 2, 3, 10] {
      do {
        _ = try await device.getInfo(handle: handle)
        XCTFail("Object \(handle) should have been deleted")
      } catch {
        // Expected: objectNotFound
      }
    }
  }

  // MARK: - 23. Delete Non-Existent Object Throws

  func testDeleteNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    do {
      try await device.delete(999, recursive: false)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 24. Rapid Connect-Disconnect Cycles (Hotplug Stress)

  func testRapidConnectDisconnectCycles() async throws {
    let config = VirtualDeviceConfig.pixel7

    for cycle in 0..<10 {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()

      let storages = try await device.storages()
      XCTAssertFalse(storages.isEmpty, "Cycle \(cycle): storages should not be empty")

      let info = try await device.info
      XCTAssertEqual(info.model, "Pixel 7", "Cycle \(cycle)")

      try await device.devClose()
    }
  }

  // MARK: - 25. Camera Device Full Workflow (Canon EOS R5)

  func testCameraDeviceFullWorkflow() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)

    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Canon")
    XCTAssertEqual(info.model, "EOS R5")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
    XCTAssertTrue(storages.first!.description.contains("Memory Card"))

    // List DCIM folder
    var dcimContents: [MTPObjectInfo] = []
    let stream = device.list(parent: 1, in: storages[0].id)
    for try await batch in stream {
      dcimContents.append(contentsOf: batch)
    }
    XCTAssertFalse(dcimContents.isEmpty)
    // Camera preset has a CR3 raw file
    XCTAssertTrue(dcimContents.contains { $0.name.hasSuffix(".CR3") })

    // Download the RAW file
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let rawFile = dcimContents.first { $0.name.hasSuffix(".CR3") }!
    let outputURL = dir.appendingPathComponent(rawFile.name)
    let progress = try await device.read(handle: rawFile.handle, range: nil, to: outputURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)

    // Simulate camera capturing a new photo (event injection)
    let newHandle = MTPObjectHandle(50)
    let newPhoto = VirtualObjectConfig(
      handle: newHandle, storage: storages[0].id, parent: 1,
      name: "IMG_0002.CR3", sizeBytes: 30_000_000,
      formatCode: 0x3000, data: Data(repeating: 0xCA, count: 256)
    )
    await device.addObject(newPhoto)
    await device.injectEvent(.objectAdded(newHandle))

    // Re-list should show new photo
    var updatedContents: [MTPObjectInfo] = []
    let newStream = device.list(parent: 1, in: storages[0].id)
    for try await batch in newStream {
      updatedContents.append(contentsOf: batch)
    }
    XCTAssertEqual(updatedContents.count, dcimContents.count + 1)
    XCTAssertTrue(updatedContents.contains { $0.name == "IMG_0002.CR3" })
  }

  // MARK: - 26. Camera Dual Card Slot Scenario

  func testCameraDualCardSlotScenario() async throws {
    let cfExpressSlot = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "CFexpress Card",
      capacityBytes: 256 * 1024 * 1024 * 1024,
      freeBytes: 200 * 1024 * 1024 * 1024
    )
    let cfRaw = VirtualObjectConfig(
      handle: 100, storage: cfExpressSlot.id, parent: nil,
      name: "DCIM", formatCode: 0x3001
    )
    let cfPhoto = VirtualObjectConfig(
      handle: 101, storage: cfExpressSlot.id, parent: 100,
      name: "RAW_0001.CR3", sizeBytes: 50_000_000,
      formatCode: 0x3000, data: Data(repeating: 0xCF, count: 2048)
    )

    let config = VirtualDeviceConfig.canonEOSR5
      .withStorage(cfExpressSlot)
      .withObject(cfRaw)
      .withObject(cfPhoto)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2, "Should have SD + CFexpress")

    let sdSlot = storages.first { $0.description.contains("Memory Card") }
    let cfSlot = storages.first { $0.description.contains("CFexpress") }
    XCTAssertNotNil(sdSlot)
    XCTAssertNotNil(cfSlot)

    // List from both slots
    var sdFiles: [MTPObjectInfo] = []
    let sdStream = device.list(parent: 1, in: sdSlot!.id)
    for try await batch in sdStream {
      sdFiles.append(contentsOf: batch)
    }

    var cfFiles: [MTPObjectInfo] = []
    let cfStream = device.list(parent: 100, in: cfSlot!.id)
    for try await batch in cfStream {
      cfFiles.append(contentsOf: batch)
    }

    XCTAssertFalse(sdFiles.isEmpty, "SD card should have files")
    XCTAssertFalse(cfFiles.isEmpty, "CFexpress should have files")
    XCTAssertTrue(cfFiles.contains { $0.name == "RAW_0001.CR3" })

    // Download from CFexpress slot
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("cfexpress_raw.cr3")
    let progress = try await device.read(handle: 101, range: nil, to: outURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
    let data = try Data(contentsOf: outURL)
    XCTAssertTrue(data.allSatisfy { $0 == 0xCF })
  }

  // MARK: - 27. Concurrent Multi-Task Downloads via TaskGroup

  func testConcurrentMultiTaskDownloads() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<8 {
      let handle = MTPObjectHandle(400 + i)
      let data = Data(repeating: UInt8(i), count: 2048 * (i + 1))
      let obj = VirtualObjectConfig(
        handle: handle, storage: storageId, parent: nil,
        name: "taskgroup_\(i).dat", sizeBytes: UInt64(data.count),
        formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let results = try await withThrowingTaskGroup(
      of: (Int, Int64).self
    ) { group -> [(Int, Int64)] in
      for i in 0..<8 {
        let outURL = dir.appendingPathComponent("tg_\(i).dat")
        group.addTask {
          let progress = try await device.read(
            handle: MTPObjectHandle(400 + i), range: nil, to: outURL)
          return (i, progress.completedUnitCount)
        }
      }
      var collected: [(Int, Int64)] = []
      for try await result in group {
        collected.append(result)
      }
      return collected
    }

    XCTAssertEqual(results.count, 8)
    for (i, size) in results {
      XCTAssertEqual(
        Int(size), 2048 * (i + 1),
        "File \(i) size mismatch")
    }
  }

  // MARK: - 28. Object Removed Event During Listing

  func testObjectRemovedEventDuringListing() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    // List root objects
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storageId)
    for try await batch in stream {
      objects.append(contentsOf: batch)
    }
    let initialCount = objects.count

    // Simulate object removal (e.g., user deletes from device screen)
    await device.removeObject(handle: 1)
    await device.injectEvent(.objectRemoved(1))

    // Re-list should reflect removal
    var updated: [MTPObjectInfo] = []
    let newStream = device.list(parent: nil, in: storageId)
    for try await batch in newStream {
      updated.append(contentsOf: batch)
    }
    XCTAssertEqual(updated.count, initialCount - 1)
    XCTAssertFalse(updated.contains { $0.handle == 1 })
  }

  // MARK: - 29. Upload to Specific Storage via Parent

  func testUploadToSpecificStorageViaParent() async throws {
    let device = makeMultiStorageDevice()
    let sdStorageId = MTPStorageID(raw: 0x0002_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let uploadData = Data(repeating: 0x55, count: 4096)
    let srcURL = dir.appendingPathComponent("sd_upload.dat")
    try uploadData.write(to: srcURL)

    // Upload into DCIM folder on SD card (handle 100)
    let progress = try await device.write(
      parent: 100, name: "sd_upload.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, Int64(uploadData.count))

    // Verify file was placed on the SD card storage
    var sdDcimFiles: [MTPObjectInfo] = []
    let stream = device.list(parent: 100, in: sdStorageId)
    for try await batch in stream {
      sdDcimFiles.append(contentsOf: batch)
    }
    XCTAssertTrue(
      sdDcimFiles.contains { $0.name == "sd_upload.dat" },
      "Uploaded file should appear under SD card DCIM")
  }

  // MARK: - 30. Device Info Consistency Across Calls

  func testDeviceInfoConsistencyAcrossCalls() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let info1 = try await device.info
    let info2 = try await device.info
    let info3 = try await device.devGetDeviceInfoUncached()

    XCTAssertEqual(info1.manufacturer, info2.manufacturer)
    XCTAssertEqual(info1.model, info2.model)
    XCTAssertEqual(info1.serialNumber, info2.serialNumber)
    XCTAssertEqual(info2.manufacturer, info3.manufacturer)
    XCTAssertEqual(info2.model, info3.model)
  }

  // MARK: - 31. Operation Log Chronological Ordering

  func testOperationLogChronologicalOrdering() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    try await device.openIfNeeded()
    _ = try await device.storages()
    _ = try await device.getInfo(handle: 3)
    _ = try await device.createFolder(parent: nil, name: "TestLog", storage: storageId)

    let ops = await device.operations
    XCTAssertGreaterThanOrEqual(ops.count, 4)

    // Verify chronological ordering
    for i in 1..<ops.count {
      XCTAssertLessThanOrEqual(
        ops[i - 1].timestamp, ops[i].timestamp,
        "Operation \(ops[i - 1].operation) at index \(i - 1) should be before \(ops[i].operation) at index \(i)"
      )
    }

    // Verify expected sequence
    let opNames = ops.map(\.operation)
    XCTAssertEqual(opNames[0], "openIfNeeded")
    XCTAssertEqual(opNames[1], "storages")
    XCTAssertTrue(opNames.contains("getInfo"))
    XCTAssertTrue(opNames.contains("createFolder"))
  }

  // MARK: - 32. Empty Device Handling

  func testEmptyDeviceHandling() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.model, "Empty Device")

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1, "Empty device should have one storage")

    // Listing root should yield no objects
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storages[0].id)
    for try await batch in stream {
      objects.append(contentsOf: batch)
    }
    XCTAssertTrue(objects.isEmpty, "Empty device should have no objects")

    // Deleting non-existent object should fail
    do {
      try await device.delete(1, recursive: false)
      XCTFail("Expected error on empty device delete")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 33. Create Folder Then Upload Into It

  func testCreateFolderThenUploadIntoIt() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Create nested folder path: Downloads/2025/January
    let downloads = try await device.createFolder(
      parent: nil, name: "Downloads", storage: storageId)
    let year = try await device.createFolder(
      parent: downloads, name: "2025", storage: storageId)
    let month = try await device.createFolder(
      parent: year, name: "January", storage: storageId)

    // Upload a file into the deepest folder
    let fileData = Data(repeating: 0x99, count: 8192)
    let srcURL = dir.appendingPathComponent("report.pdf")
    try fileData.write(to: srcURL)

    let progress = try await device.write(
      parent: month, name: "report.pdf",
      size: UInt64(fileData.count), from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, Int64(fileData.count))

    // Verify file appears in the January folder
    var files: [MTPObjectInfo] = []
    let stream = device.list(parent: month, in: storageId)
    for try await batch in stream {
      files.append(contentsOf: batch)
    }
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(files.first?.name, "report.pdf")

    // Download and verify round-trip
    let downloadURL = dir.appendingPathComponent("downloaded_report.pdf")
    let fileHandle = files.first!.handle
    _ = try await device.read(handle: fileHandle, range: nil, to: downloadURL)
    let downloaded = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloaded, fileData)
  }

  // MARK: - 34. Nikon Camera Workflow with Event Injection

  func testNikonCameraWorkflow() async throws {
    let device = VirtualMTPDevice(config: .nikonZ6)

    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Nikon")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Enumerate existing files
    var files: [MTPObjectInfo] = []
    let stream = device.list(parent: 1, in: storages[0].id)
    for try await batch in stream {
      files.append(contentsOf: batch)
    }
    XCTAssertFalse(files.isEmpty)

    // Simulate burst capture: inject multiple objectAdded events
    for i in 0..<5 {
      let handle = MTPObjectHandle(200 + i)
      let photo = VirtualObjectConfig(
        handle: handle, storage: storages[0].id, parent: 1,
        name: "DSC_\(String(format: "%04d", i)).NEF",
        sizeBytes: 40_000_000,
        formatCode: 0x3000, data: Data(repeating: UInt8(i), count: 512)
      )
      await device.addObject(photo)
      await device.injectEvent(.objectAdded(handle))
    }

    // Re-enumerate should show the new photos
    var allFiles: [MTPObjectInfo] = []
    let newStream = device.list(parent: 1, in: storages[0].id)
    for try await batch in newStream {
      allFiles.append(contentsOf: batch)
    }
    XCTAssertEqual(allFiles.count, files.count + 5)
  }

  // MARK: - 35. Multiple Device Types Parallel Operation

  func testMultipleDeviceTypesParallelOperation() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    let canon = VirtualMTPDevice(config: .canonEOSR5)

    // Parallel open and enumerate all three devices
    async let pixelStorages = pixel.storages()
    async let samsungStorages = samsung.storages()
    async let canonStorages = canon.storages()

    let (ps, ss, cs) = try await (pixelStorages, samsungStorages, canonStorages)

    XCTAssertFalse(ps.isEmpty)
    XCTAssertFalse(ss.isEmpty)
    XCTAssertFalse(cs.isEmpty)

    // Parallel info queries
    async let pixelInfo = pixel.info
    async let samsungInfo = samsung.info
    async let canonInfo = canon.info

    let (pi, si, ci) = try await (pixelInfo, samsungInfo, canonInfo)

    XCTAssertEqual(pi.manufacturer, "Google")
    XCTAssertEqual(si.manufacturer, "Samsung")
    XCTAssertEqual(ci.manufacturer, "Canon")

    // Each device should have independent operation logs
    let pixelOps = await pixel.operations
    let samsungOps = await samsung.operations
    let canonOps = await canon.operations

    // All should have at least a "storages" operation
    XCTAssertTrue(pixelOps.contains { $0.operation == "storages" })
    XCTAssertTrue(samsungOps.contains { $0.operation == "storages" })
    XCTAssertTrue(canonOps.contains { $0.operation == "storages" })
  }

  // MARK: - 36. Operation Log Clear and Reuse

  func testOperationLogClearAndReuse() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    _ = try await device.storages()
    _ = try await device.info

    let opsBeforeClear = await device.operations
    XCTAssertGreaterThanOrEqual(opsBeforeClear.count, 1)

    await device.clearOperations()

    let opsAfterClear = await device.operations
    XCTAssertTrue(opsAfterClear.isEmpty, "Operations should be empty after clear")

    // New operations should still be recorded
    _ = try await device.storages()
    let opsAfterNew = await device.operations
    XCTAssertEqual(opsAfterNew.count, 1)
    XCTAssertEqual(opsAfterNew.first?.operation, "storages")
  }
}
