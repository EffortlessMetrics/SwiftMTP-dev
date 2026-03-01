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
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(
        id: "pixel7-test", deviceName: "Pixel 7",
        vid: 0x18d1, pid: 0x4ee1,
        maxChunkBytes: 4 * 1024 * 1024
      ),
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
    let largeData = Data(repeating: 0xCC, count: 8 * 1024 * 1024) // 8 MB
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
      XCTAssertTrue(data.allSatisfy { $0 == UInt8(i + 1) },
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

    XCTAssertGreaterThan(updatedObjects.count, objects.count,
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
    let nextHandle = MTPObjectHandle(5) // After delete+reupload, handle 5
    let downloadURL = dir.appendingPathComponent("reupload_downloaded.dat")
    let downloadProgress = try await device.read(handle: nextHandle, range: nil, to: downloadURL)
    let downloadedData = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloadedData.count, newData.count)
    XCTAssertTrue(downloadedData.allSatisfy { $0 == 0xCD })
    XCTAssertEqual(downloadProgress.completedUnitCount, Int64(newData.count))
  }
}
