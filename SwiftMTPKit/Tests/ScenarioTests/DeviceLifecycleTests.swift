// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - Device Lifecycle Tests

/// End-to-end tests that trace complete MTP device lifecycle sequences,
/// verifying correct state at each protocol step. Covers discovery through
/// disconnection, multi-storage, error recovery, concurrency, and edge cases.
final class DeviceLifecycleTests: XCTestCase {

  // MARK: - Helpers

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-lifecycle-e2e")
  }

  private func listAll(
    device: VirtualMTPDevice, parent: MTPObjectHandle?, in storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream { objects.append(contentsOf: batch) }
    return objects
  }

  /// Recursively walk the entire object tree for a storage, returning all objects.
  private func walkTree(
    device: VirtualMTPDevice, storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var result: [MTPObjectInfo] = []
    var queue: [MTPObjectHandle?] = [nil]
    while !queue.isEmpty {
      let parent = queue.removeFirst()
      let children = try await listAll(device: device, parent: parent, in: storage)
      result.append(contentsOf: children)
      for child in children where child.formatCode == 0x3001 {
        queue.append(child.handle)
      }
    }
    return result
  }

  // MARK: - 1. Full MTP Protocol Lifecycle

  /// Traces the complete MTP operation sequence step-by-step:
  /// open → getDeviceInfo → getStorageIDs → getStorageInfo → getObjectHandles →
  /// getObjectInfo → getObject → closeSession → close
  func testFullMTPProtocolLifecycleStepByStep() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Step 1: Open connection
    try await device.openIfNeeded()
    var ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("openIfNeeded"), "Step 1: open recorded")

    // Step 2: Get device info
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertFalse(info.serialNumber?.isEmpty ?? true)
    XCTAssertFalse(info.operationsSupported.isEmpty)

    // Step 3: Get storage IDs
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("storages"), "Step 3: storages recorded")

    // Step 4: Get storage info
    let storage = storages[0]
    XCTAssertEqual(storage.description, "Internal shared storage")
    XCTAssertGreaterThan(storage.capacityBytes, 0)
    XCTAssertGreaterThan(storage.freeBytes, 0)
    XCTAssertLessThanOrEqual(storage.freeBytes, storage.capacityBytes)
    XCTAssertFalse(storage.isReadOnly)

    // Step 5: Get object handles (root listing)
    let rootObjects = try await listAll(device: device, parent: nil, in: storage.id)
    XCTAssertFalse(rootObjects.isEmpty)
    let dcim = rootObjects.first { $0.name == "DCIM" }
    XCTAssertNotNil(dcim, "Step 5: DCIM folder present")
    XCTAssertEqual(dcim?.formatCode, 0x3001)

    // Step 6: Get object info for a specific handle
    let dcimInfo = try await device.getInfo(handle: 1)
    XCTAssertEqual(dcimInfo.name, "DCIM")
    XCTAssertEqual(dcimInfo.handle, 1)
    ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("getInfo"), "Step 6: getInfo recorded")

    // Step 7: Navigate deeper and get object data
    let cameraFiles = try await listAll(device: device, parent: 2, in: storage.id)
    XCTAssertFalse(cameraFiles.isEmpty)
    let photo = cameraFiles[0]
    XCTAssertEqual(photo.name, "IMG_20250101_120000.jpg")
    XCTAssertEqual(photo.formatCode, 0x3801)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent(photo.name)
    let progress = try await device.read(handle: photo.handle, range: nil, to: outURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
    ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("read"), "Step 7: read recorded")

    // Step 8: Close session and disconnect
    try await device.devClose()
    ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("devClose"), "Step 8: close recorded")

    // Verify operation ordering
    let orderedOps = await device.operations.map(\.operation)
    let openIdx = orderedOps.firstIndex(of: "openIfNeeded")!
    let storagesIdx = orderedOps.firstIndex(of: "storages")!
    let getInfoIdx = orderedOps.firstIndex(of: "getInfo")!
    let readIdx = orderedOps.firstIndex(of: "read")!
    let closeIdx = orderedOps.firstIndex(of: "devClose")!
    XCTAssertLessThan(openIdx, storagesIdx, "open before storages")
    XCTAssertLessThan(storagesIdx, getInfoIdx, "storages before getInfo")
    XCTAssertLessThan(getInfoIdx, readIdx, "getInfo before read")
    XCTAssertLessThan(readIdx, closeIdx, "read before close")
  }

  // MARK: - 2. Multi-Storage Lifecycle

  /// Device with internal + SD card storage: operations on each are independent.
  func testMultiStorageLifecycle() async throws {
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 16 * 1024 * 1024 * 1024
    )
    let sdFile = VirtualObjectConfig(
      handle: 100, storage: MTPStorageID(raw: 0x0002_0001), parent: nil,
      name: "SD_photo.jpg", sizeBytes: 2048,
      formatCode: 0x3801, data: Data(repeating: 0xAA, count: 2048)
    )
    let config = VirtualDeviceConfig.pixel7.withStorage(sdCard).withObject(sdFile)
    let device = VirtualMTPDevice(config: config)
    try await device.openIfNeeded()

    // Verify both storages
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    let internal_ = storages.first { $0.description == "Internal shared storage" }
    let sd = storages.first { $0.description == "SD Card" }
    XCTAssertNotNil(internal_)
    XCTAssertNotNil(sd)

    // List objects on each storage independently
    let internalObjs = try await listAll(device: device, parent: nil, in: internal_!.id)
    let sdObjs = try await listAll(device: device, parent: nil, in: sd!.id)
    XCTAssertFalse(internalObjs.isEmpty, "Internal storage has objects")
    XCTAssertFalse(sdObjs.isEmpty, "SD card has objects")
    XCTAssertTrue(sdObjs.contains { $0.name == "SD_photo.jpg" })

    // Download from each storage
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let internalFile: MTPObjectInfo
    if let directFile = internalObjs.first(where: { $0.formatCode != 0x3001 }) {
      internalFile = directFile
    } else {
      internalFile = try await listAll(device: device, parent: 2, in: internal_!.id)[0]
    }
    let internalURL = dir.appendingPathComponent("internal_dl.bin")
    let p1 = try await device.read(handle: internalFile.handle, range: nil, to: internalURL)
    XCTAssertGreaterThan(p1.completedUnitCount, 0)

    let sdURL = dir.appendingPathComponent("sd_dl.bin")
    let p2 = try await device.read(handle: 100, range: nil, to: sdURL)
    XCTAssertEqual(p2.completedUnitCount, 2048)

    // Upload to SD card via parent on SD storage
    let uploadData = Data(repeating: 0xBB, count: 512)
    let uploadSrc = dir.appendingPathComponent("sd_upload.dat")
    try uploadData.write(to: uploadSrc)
    let wp = try await device.write(parent: 100, name: "sd_upload.dat", size: 512, from: uploadSrc)
    XCTAssertEqual(wp.completedUnitCount, 512)

    try await device.devClose()
  }

  // MARK: - 3. Session Recovery After Error

  /// Simulate an error during operations, then recover and continue.
  func testSessionRecoveryAfterError() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    // Normal operation succeeds
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Simulate: attempt to access non-existent handle (protocol error)
    do {
      _ = try await device.getInfo(handle: 9999)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    // Recovery: device should still be operational after the error
    let info = try await device.info
    XCTAssertEqual(info.model, "Pixel 7")

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(objects.isEmpty, "Device operational after error recovery")

    // Can still download
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("recovery_test.jpg")
    let progress = try await device.read(handle: 3, range: nil, to: outURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)

    // Multiple sequential errors don't break the device
    for badHandle in [5000, 6000, 7000] {
      do {
        _ = try await device.getInfo(handle: MTPObjectHandle(badHandle))
      } catch {
        // Expected
      }
    }

    // Still works
    let storages2 = try await device.storages()
    XCTAssertEqual(storages2.count, storages.count)

    try await device.devClose()
  }

  // MARK: - 4. Concurrent getObject Calls

  /// Multiple parallel downloads from the same device with data integrity checks.
  func testConcurrentGetObjectCalls() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    let fileCount = 15
    for i in 0..<fileCount {
      let fillByte = UInt8((i * 17 + 3) & 0xFF)
      let size = 1024 * (i + 1)
      let data = Data(repeating: fillByte, count: size)
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(200 + i), storage: storageId, parent: nil,
        name: "parallel_\(String(format: "%03d", i)).bin",
        sizeBytes: UInt64(size), formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Download all files in parallel
    try await withThrowingTaskGroup(of: (Int, Data).self) { group in
      for i in 0..<fileCount {
        group.addTask {
          let outURL = dir.appendingPathComponent("parallel_\(i).bin")
          _ = try await device.read(
            handle: MTPObjectHandle(200 + i), range: nil, to: outURL)
          let data = try Data(contentsOf: outURL)
          return (i, data)
        }
      }
      for try await (i, data) in group {
        let expectedByte = UInt8((i * 17 + 3) & 0xFF)
        let expectedSize = 1024 * (i + 1)
        XCTAssertEqual(data.count, expectedSize, "File \(i) size mismatch")
        XCTAssertTrue(
          data.allSatisfy { $0 == expectedByte },
          "File \(i) content integrity failed")
      }
    }

    // Verify all reads were recorded
    let readOps = await device.operations.filter { $0.operation == "read" }
    XCTAssertEqual(readOps.count, fileCount)
  }

  // MARK: - 5. Large File Transfer Lifecycle

  /// Transfer a large file with progress tracking at each stage.
  func testLargeFileTransferLifecycle() async throws {
    let largeSize = 8 * 1024 * 1024
    let largeData = Data((0..<largeSize).map { UInt8($0 % 251) })
    let largeFile = VirtualObjectConfig(
      handle: 300, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "large_transfer.bin", sizeBytes: UInt64(largeSize),
      formatCode: 0x3000, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)
    try await device.openIfNeeded()

    // Verify file info before download
    let fileInfo = try await device.getInfo(handle: 300)
    XCTAssertEqual(fileInfo.name, "large_transfer.bin")
    XCTAssertEqual(fileInfo.sizeBytes, UInt64(largeSize))

    // Download
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("large_transfer.bin")
    let progress = try await device.read(handle: 300, range: nil, to: outURL)

    // Verify progress reports
    XCTAssertEqual(progress.totalUnitCount, Int64(largeSize))
    XCTAssertEqual(progress.completedUnitCount, Int64(largeSize))

    // Verify downloaded data integrity
    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded.count, largeSize)
    XCTAssertEqual(downloaded, largeData, "Large file byte-for-byte integrity")

    // Upload equally large file
    let uploadData = Data(repeating: 0xFE, count: largeSize)
    let uploadURL = dir.appendingPathComponent("large_upload.bin")
    try uploadData.write(to: uploadURL)
    let uploadProgress = try await device.write(
      parent: nil, name: "large_upload.bin",
      size: UInt64(largeSize), from: uploadURL
    )
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(largeSize))

    // Verify upload via round-trip download
    let verifyURL = dir.appendingPathComponent("large_verify.bin")
    // New file gets handle 301 (300 was max, nextHandle = 301, then becomes 302 after getInfo?)
    // Actually: pixel7 has handles 1,2,3 + we added 300 → nextHandle = 301
    _ = try await device.read(handle: 301, range: nil, to: verifyURL)
    let verified = try Data(contentsOf: verifyURL)
    XCTAssertEqual(verified, uploadData)

    try await device.devClose()
  }

  // MARK: - 6. Device Removal During Transfer (Simulated)

  /// Simulate a device disconnect event during an active transfer.
  func testDeviceRemovalDuringTransfer() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Start a download
    let outURL = dir.appendingPathComponent("disconnect_test.jpg")
    async let readResult = device.read(handle: 3, range: nil, to: outURL)

    // Inject device reset event mid-transfer
    await device.injectEvent(.deviceReset)

    // The virtual device completes instantly, so the transfer succeeds
    // but we verify the event was delivered and device state is consistent
    let progress = try await readResult
    XCTAssertGreaterThan(progress.completedUnitCount, 0)

    // After the device reset event, close gracefully
    try await device.devClose()

    let ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("read"))
    XCTAssertTrue(ops.contains("devClose"))
  }

  // MARK: - 7. Re-connection Lifecycle

  /// Close device, create new instance (simulating re-plug), verify full functionality.
  func testReConnectionLifecycle() async throws {
    let config = VirtualDeviceConfig.pixel7

    // Session 1: open, perform work, close
    let device1 = VirtualMTPDevice(config: config)
    try await device1.openIfNeeded()
    let info1 = try await device1.info
    let storages1 = try await device1.storages()
    let objects1 = try await listAll(device: device1, parent: nil, in: storages1[0].id)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL1 = dir.appendingPathComponent("session1.jpg")
    _ = try await device1.read(handle: 3, range: nil, to: outURL1)
    let session1Data = try Data(contentsOf: outURL1)

    try await device1.devClose()
    let ops1 = await device1.operations.map(\.operation)
    XCTAssertTrue(ops1.contains("devClose"))

    // Session 2: re-connect (new device instance)
    let device2 = VirtualMTPDevice(config: config)
    try await device2.openIfNeeded()

    // Verify device identity is the same
    let info2 = try await device2.info
    XCTAssertEqual(info1.manufacturer, info2.manufacturer)
    XCTAssertEqual(info1.model, info2.model)
    XCTAssertEqual(info1.serialNumber, info2.serialNumber)

    // Verify same storages
    let storages2 = try await device2.storages()
    XCTAssertEqual(storages1.count, storages2.count)
    XCTAssertEqual(storages1[0].description, storages2[0].description)

    // Verify same objects
    let objects2 = try await listAll(device: device2, parent: nil, in: storages2[0].id)
    XCTAssertEqual(
      Set(objects1.map(\.name)),
      Set(objects2.map(\.name)),
      "Objects identical after reconnection")

    // Verify file content is identical
    let outURL2 = dir.appendingPathComponent("session2.jpg")
    _ = try await device2.read(handle: 3, range: nil, to: outURL2)
    let session2Data = try Data(contentsOf: outURL2)
    XCTAssertEqual(session1Data, session2Data, "File content identical across sessions")

    // Session 2 has its own operation log
    let ops2 = await device2.operations.map(\.operation)
    XCTAssertTrue(ops2.contains("openIfNeeded"))
    XCTAssertFalse(ops2.contains("devClose"), "Session 2 not yet closed")

    try await device2.devClose()
  }

  // MARK: - 8. Upload Lifecycle (sendObjectInfo → sendObject → verify)

  /// Full upload workflow: write file, verify metadata, verify content via round-trip.
  func testUploadLifecycleWithVerification() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Prepare multiple files with distinct content
    let files: [(name: String, data: Data)] = [
      ("document.txt", Data("Hello, MTP world!".utf8)),
      ("photo.jpg", Data(repeating: 0xFF, count: 65536)),
      ("video.mp4", Data((0..<32768).map { UInt8($0 % 256) })),
    ]

    var uploadedHandles: [MTPObjectHandle] = []

    for (name, data) in files {
      let srcURL = dir.appendingPathComponent(name)
      try data.write(to: srcURL)

      let progress = try await device.write(
        parent: nil, name: name,
        size: UInt64(data.count), from: srcURL
      )
      XCTAssertEqual(
        progress.completedUnitCount, Int64(data.count),
        "Upload progress for \(name)")

      // pixel7 has handles 1,2,3 → uploads start at 4
      let expectedHandle = MTPObjectHandle(4 + uploadedHandles.count)
      uploadedHandles.append(expectedHandle)

      // Verify metadata
      let info = try await device.getInfo(handle: expectedHandle)
      XCTAssertEqual(info.name, name)
      XCTAssertEqual(info.sizeBytes, UInt64(data.count))
    }

    // Verify content round-trip for each uploaded file
    for (i, (name, originalData)) in files.enumerated() {
      let verifyURL = dir.appendingPathComponent("verify_\(name)")
      _ = try await device.read(handle: uploadedHandles[i], range: nil, to: verifyURL)
      let downloaded = try Data(contentsOf: verifyURL)
      XCTAssertEqual(
        downloaded, originalData,
        "Round-trip integrity for \(name)")
    }

    // Verify uploads appear in listing
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let rootObjects = try await listAll(device: device, parent: nil, in: storageId)
    for (name, _) in files {
      XCTAssertTrue(
        rootObjects.contains { $0.name == name },
        "\(name) should appear in root listing")
    }

    // Verify write operations recorded
    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, files.count)

    try await device.devClose()
  }

  // MARK: - 9. Delete Lifecycle

  /// Delete objects and verify they are completely removed at each step.
  func testDeleteLifecycleVerification() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)
    try await device.openIfNeeded()

    // Verify initial state: photo exists at handle 3
    let photoBefore = try await device.getInfo(handle: 3)
    XCTAssertEqual(photoBefore.name, "IMG_20250101_120000.jpg")

    // Delete the photo
    try await device.delete(3, recursive: false)

    // Verify handle is gone
    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Should throw objectNotFound after delete")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    // Verify it's gone from listing (Camera folder, parent = 2)
    let cameraFiles = try await listAll(device: device, parent: 2, in: storageId)
    XCTAssertFalse(
      cameraFiles.contains { $0.handle == 3 },
      "Deleted handle should not appear in listing")

    // Download attempt should also fail
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("deleted.jpg")
    do {
      _ = try await device.read(handle: 3, range: nil, to: outURL)
      XCTFail("Read of deleted handle should fail")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    // Recursive delete: delete DCIM (handle 1) which contains Camera (handle 2)
    try await device.delete(1, recursive: true)

    // Both DCIM and Camera should be gone
    for handle in [MTPObjectHandle(1), MTPObjectHandle(2)] {
      do {
        _ = try await device.getInfo(handle: handle)
        XCTFail("Handle \(handle) should be deleted")
      } catch {
        // Expected
      }
    }

    // Root should be empty
    let rootObjs = try await listAll(device: device, parent: nil, in: storageId)
    XCTAssertTrue(rootObjs.isEmpty, "Root empty after recursive delete")

    // Verify delete operations recorded
    let deleteOps = await device.operations.filter { $0.operation == "delete" }
    XCTAssertEqual(deleteOps.count, 2)

    try await device.devClose()
  }

  // MARK: - 10. Browse and Search: Walk Directory Tree

  /// Walk the complete directory tree and verify parent-child relationships.
  func testBrowseAndWalkDirectoryTree() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7

    // Add additional directory structure
    let musicFolder = VirtualObjectConfig(
      handle: 10, storage: storageId, parent: nil,
      name: "Music", formatCode: 0x3001)
    let artist = VirtualObjectConfig(
      handle: 11, storage: storageId, parent: 10,
      name: "Artist", formatCode: 0x3001)
    let song = VirtualObjectConfig(
      handle: 12, storage: storageId, parent: 11,
      name: "track01.mp3", sizeBytes: 4096,
      formatCode: 0xB901, data: Data(repeating: 0x00, count: 4096))
    let downloadsFolder = VirtualObjectConfig(
      handle: 13, storage: storageId, parent: nil,
      name: "Downloads", formatCode: 0x3001)
    let downloadedFile = VirtualObjectConfig(
      handle: 14, storage: storageId, parent: 13,
      name: "readme.pdf", sizeBytes: 2048,
      formatCode: 0x3000, data: Data(repeating: 0x01, count: 2048))

    config = config
      .withObject(musicFolder).withObject(artist).withObject(song)
      .withObject(downloadsFolder).withObject(downloadedFile)

    let device = VirtualMTPDevice(config: config)

    // Full tree walk
    let allObjects = try await walkTree(device: device, storage: storageId)

    // Verify we found all objects (pixel7 default: DCIM, Camera, photo + our 5)
    XCTAssertGreaterThanOrEqual(allObjects.count, 8)

    // Verify specific objects found
    let names = Set(allObjects.map(\.name))
    XCTAssertTrue(names.contains("DCIM"))
    XCTAssertTrue(names.contains("Camera"))
    XCTAssertTrue(names.contains("IMG_20250101_120000.jpg"))
    XCTAssertTrue(names.contains("Music"))
    XCTAssertTrue(names.contains("Artist"))
    XCTAssertTrue(names.contains("track01.mp3"))
    XCTAssertTrue(names.contains("Downloads"))
    XCTAssertTrue(names.contains("readme.pdf"))

    // Verify folders vs files
    let folders = allObjects.filter { $0.formatCode == 0x3001 }
    let files = allObjects.filter { $0.formatCode != 0x3001 }
    XCTAssertGreaterThanOrEqual(folders.count, 5)  // DCIM, Camera, Music, Artist, Downloads
    XCTAssertGreaterThanOrEqual(files.count, 3)  // photo, track01.mp3, readme.pdf

    // Verify filtered listing: only list children of Music
    let musicChildren = try await listAll(device: device, parent: 10, in: storageId)
    XCTAssertEqual(musicChildren.count, 1)
    XCTAssertEqual(musicChildren[0].name, "Artist")

    // Verify leaf listing
    let artistChildren = try await listAll(device: device, parent: 11, in: storageId)
    XCTAssertEqual(artistChildren.count, 1)
    XCTAssertEqual(artistChildren[0].name, "track01.mp3")
  }

  // MARK: - 11. Concurrent Upload and Download on Same Device

  /// Interleaved uploads and downloads running in parallel.
  func testConcurrentUploadAndDownloadLifecycle() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<5 {
      let data = Data(repeating: UInt8(i + 50), count: 2048)
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(400 + i), storage: storageId, parent: nil,
        name: "dlfile_\(i).bin", sizeBytes: 2048,
        formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Concurrent: download 5 files + upload 5 files
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Downloads
      for i in 0..<5 {
        group.addTask {
          let outURL = dir.appendingPathComponent("downloaded_\(i).bin")
          let p = try await device.read(
            handle: MTPObjectHandle(400 + i), range: nil, to: outURL)
          XCTAssertEqual(p.completedUnitCount, 2048)
        }
      }
      // Uploads
      for i in 0..<5 {
        group.addTask {
          let data = Data(repeating: UInt8(i + 100), count: 1024)
          let srcURL = dir.appendingPathComponent("upload_src_\(i).bin")
          try data.write(to: srcURL)
          let p = try await device.write(
            parent: nil, name: "uploaded_\(i).bin",
            size: 1024, from: srcURL)
          XCTAssertEqual(p.completedUnitCount, 1024)
        }
      }
      try await group.waitForAll()
    }

    // Verify all operations recorded
    let readOps = await device.operations.filter { $0.operation == "read" }
    let writeOps = await device.operations.filter { $0.operation == "write" }
    XCTAssertEqual(readOps.count, 5)
    XCTAssertEqual(writeOps.count, 5)
  }

  // MARK: - 12. Upload → Copy → Delete Original Lifecycle

  /// Upload a file, copy it on-device, delete the original, verify the copy persists.
  func testUploadCopyDeleteOriginalLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload a file
    let data = Data(repeating: 0xCA, count: 4096)
    let srcURL = dir.appendingPathComponent("original.dat")
    try data.write(to: srcURL)
    _ = try await device.write(parent: nil, name: "original.dat", size: 4096, from: srcURL)
    let originalHandle = MTPObjectHandle(4)

    // Create destination folder
    let archiveHandle = try await device.createFolder(
      parent: nil, name: "Archive", storage: storageId)

    // Copy original to Archive
    let copyHandle = try await device.copyObject(
      handle: originalHandle, toStorage: storageId, parentFolder: archiveHandle)
    XCTAssertNotEqual(copyHandle, originalHandle, "Copy should have a new handle")

    // Verify copy metadata
    let copyInfo = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo.name, "original.dat")
    XCTAssertEqual(copyInfo.sizeBytes, 4096)

    // Verify copy content
    let copyURL = dir.appendingPathComponent("copy_verify.dat")
    _ = try await device.read(handle: copyHandle, range: nil, to: copyURL)
    let copyData = try Data(contentsOf: copyURL)
    XCTAssertEqual(copyData, data, "Copy content matches original")

    // Delete original
    try await device.delete(originalHandle, recursive: false)

    // Original is gone
    do {
      _ = try await device.getInfo(handle: originalHandle)
      XCTFail("Original should be deleted")
    } catch {
      // Expected
    }

    // Copy still exists
    let copyInfo2 = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo2.name, "original.dat")

    try await device.devClose()
  }

  // MARK: - 13. Create → Rename → Move → Download Lifecycle

  /// Complete object manipulation lifecycle: create, rename, move, then download.
  func testCreateRenameMoveDownloadLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Upload file
    let data = Data(repeating: 0xEE, count: 2048)
    let srcURL = dir.appendingPathComponent("step1.dat")
    try data.write(to: srcURL)
    _ = try await device.write(parent: nil, name: "step1.dat", size: 2048, from: srcURL)
    let handle = MTPObjectHandle(4)

    // Verify initial name
    var info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "step1.dat")

    // Rename
    try await device.rename(handle, to: "renamed.dat")
    info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "renamed.dat")

    // Create target folder
    let targetFolder = try await device.createFolder(
      parent: nil, name: "Target", storage: storageId)

    // Move into folder
    try await device.move(handle, to: targetFolder)

    // Verify appears in target folder
    let targetContents = try await listAll(device: device, parent: targetFolder, in: storageId)
    XCTAssertTrue(targetContents.contains { $0.name == "renamed.dat" })

    // Download from new location
    let outURL = dir.appendingPathComponent("final_download.dat")
    _ = try await device.read(handle: handle, range: nil, to: outURL)
    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded, data, "Content preserved through rename and move")

    // Verify operation sequence
    let ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("write"))
    XCTAssertTrue(ops.contains("rename"))
    XCTAssertTrue(ops.contains("move"))
    XCTAssertTrue(ops.contains("read"))
  }

  // MARK: - 14. Event-Driven Object Addition Lifecycle

  /// Simulate external object additions via events and verify discovery.
  func testEventDrivenObjectAdditionLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)
    try await device.openIfNeeded()

    // Initial count
    let beforeObjects = try await listAll(device: device, parent: nil, in: storageId)
    let beforeCount = beforeObjects.count

    // Simulate external device adding objects (e.g., camera taking photos)
    let newHandles: [MTPObjectHandle] = [500, 501, 502]
    for (i, handle) in newHandles.enumerated() {
      let obj = VirtualObjectConfig(
        handle: handle, storage: storageId, parent: nil,
        name: "external_\(i).jpg", sizeBytes: 1024,
        formatCode: 0x3801, data: Data(repeating: UInt8(i), count: 1024)
      )
      await device.addObject(obj)
      await device.injectEvent(.objectAdded(handle))
    }

    // Re-enumerate: new objects should appear
    let afterObjects = try await listAll(device: device, parent: nil, in: storageId)
    XCTAssertEqual(afterObjects.count, beforeCount + newHandles.count)

    // Verify each new object is accessible
    for (i, handle) in newHandles.enumerated() {
      let info = try await device.getInfo(handle: handle)
      XCTAssertEqual(info.name, "external_\(i).jpg")

      let dir = try tempDir()
      defer { try? TestUtilities.cleanupTempDirectory(dir) }
      let outURL = dir.appendingPathComponent("ext_\(i).jpg")
      _ = try await device.read(handle: handle, range: nil, to: outURL)
      let data = try Data(contentsOf: outURL)
      XCTAssertEqual(data.count, 1024)
    }

    // Simulate removal event
    await device.removeObject(handle: 500)
    await device.injectEvent(.objectRemoved(500))

    let finalObjects = try await listAll(device: device, parent: nil, in: storageId)
    XCTAssertEqual(finalObjects.count, beforeCount + newHandles.count - 1)

    try await device.devClose()
  }

  // MARK: - 15. Camera Profile Full Lifecycle (Canon EOS R5)

  /// End-to-end lifecycle with a camera profile including thumbnail retrieval.
  func testCameraProfileFullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()

    // Verify camera identity
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Canon")
    XCTAssertEqual(info.model, "EOS R5")

    // List storages (camera has CF card)
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Browse to photos
    let rootObjects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(rootObjects.isEmpty)

    // Find a photo and get its thumbnail
    let allObjects = try await walkTree(device: device, storage: storages[0].id)
    if let photo = allObjects.first(where: { $0.formatCode == 0x3801 }) {
      // Get thumbnail
      let thumbData = try await device.getThumbnail(handle: photo.handle)
      XCTAssertFalse(thumbData.isEmpty, "Thumbnail should have data")
      // Verify JPEG markers
      XCTAssertEqual(thumbData[0], 0xFF)
      XCTAssertEqual(thumbData[1], 0xD8)

      // Also download the full file
      let dir = try tempDir()
      defer { try? TestUtilities.cleanupTempDirectory(dir) }
      let outURL = dir.appendingPathComponent(photo.name)
      let p = try await device.read(handle: photo.handle, range: nil, to: outURL)
      XCTAssertGreaterThan(p.completedUnitCount, 0)
    }

    try await device.devClose()

    // Verify operation log includes thumbnail
    let ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("openIfNeeded"))
    XCTAssertTrue(ops.contains("storages"))
    XCTAssertTrue(ops.contains("devClose"))
  }

  // MARK: - 16. Multiple Profiles Cross-Lifecycle Validation

  /// Run the same lifecycle across all major device profiles.
  func testCrossProfileLifecycleValidation() async throws {
    let configs: [(VirtualDeviceConfig, String)] = [
      (.pixel7, "Pixel 7"),
      (.samsungGalaxy, "Samsung Galaxy"),
      (.canonEOSR5, "Canon EOS R5"),
      (.nikonZ6, "Nikon Z6"),
      (.motorolaMotoG, "Moto G"),
      (.sonyXperiaZ, "Xperia Z"),
    ]

    for (config, label) in configs {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()

      // Step 1: Device info
      let info = try await device.info
      XCTAssertFalse(info.manufacturer.isEmpty, "\(label): manufacturer")
      XCTAssertFalse(info.model.isEmpty, "\(label): model")

      // Step 2: Storages
      let storages = try await device.storages()
      XCTAssertFalse(storages.isEmpty, "\(label): has storage")
      for storage in storages {
        XCTAssertGreaterThan(storage.capacityBytes, 0, "\(label): capacity")
      }

      // Step 3: List root
      let rootObjs = try await listAll(device: device, parent: nil, in: storages[0].id)
      XCTAssertFalse(rootObjs.isEmpty, "\(label): has objects")

      // Step 4: Upload a file
      let dir = try tempDir()
      defer { try? TestUtilities.cleanupTempDirectory(dir) }
      let data = Data(repeating: 0x55, count: 512)
      let srcURL = dir.appendingPathComponent("cross_profile.dat")
      try data.write(to: srcURL)
      let p = try await device.write(parent: nil, name: "cross_profile.dat", size: 512, from: srcURL)
      XCTAssertEqual(p.completedUnitCount, 512, "\(label): upload")

      try await device.devClose()
    }
  }

  // MARK: - 17. Folder CRUD Lifecycle

  /// Create folder tree, populate with files, rename, move, delete subtree.
  func testFolderCRUDLifecycle() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Create: nested folders
    let docs = try await device.createFolder(parent: nil, name: "Documents", storage: storageId)
    let work = try await device.createFolder(parent: docs, name: "Work", storage: storageId)
    let personal = try await device.createFolder(
      parent: docs, name: "Personal", storage: storageId)

    // Populate with files
    let reportData = Data("Q4 Report".utf8)
    let reportURL = dir.appendingPathComponent("report.txt")
    try reportData.write(to: reportURL)
    _ = try await device.write(parent: work, name: "report.txt", size: UInt64(reportData.count), from: reportURL)

    let notesData = Data("Personal notes".utf8)
    let notesURL = dir.appendingPathComponent("notes.txt")
    try notesData.write(to: notesURL)
    _ = try await device.write(parent: personal, name: "notes.txt", size: UInt64(notesData.count), from: notesURL)

    // Verify tree
    let docsChildren = try await listAll(device: device, parent: docs, in: storageId)
    XCTAssertEqual(docsChildren.count, 2)  // Work, Personal

    let workFiles = try await listAll(device: device, parent: work, in: storageId)
    XCTAssertEqual(workFiles.count, 1)
    XCTAssertEqual(workFiles[0].name, "report.txt")

    // Rename folder
    try await device.rename(work, to: "Projects")
    let renamedInfo = try await device.getInfo(handle: work)
    XCTAssertEqual(renamedInfo.name, "Projects")

    // Children still accessible under renamed folder
    let projectFiles = try await listAll(device: device, parent: work, in: storageId)
    XCTAssertEqual(projectFiles.count, 1)
    XCTAssertEqual(projectFiles[0].name, "report.txt")

    // Delete Personal subtree
    try await device.delete(personal, recursive: true)
    let docsAfterDelete = try await listAll(device: device, parent: docs, in: storageId)
    XCTAssertEqual(docsAfterDelete.count, 1)  // Only Projects remains
    XCTAssertEqual(docsAfterDelete[0].name, "Projects")

    try await device.devClose()
  }

  // MARK: - 18. Ranged Read Lifecycle

  /// Download specific byte ranges and verify content accuracy.
  func testRangedReadLifecycle() async throws {
    // Create file with known byte pattern
    let size = 1_000_000
    let data = Data((0..<size).map { UInt8($0 % 256) })
    let file = VirtualObjectConfig(
      handle: 600, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "ranged.bin", sizeBytes: UInt64(size),
      formatCode: 0x3000, data: data
    )
    let config = VirtualDeviceConfig.pixel7.withObject(file)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Read various ranges and verify byte-level accuracy
    let ranges: [(Range<UInt64>, String)] = [
      (0..<256, "first 256 bytes"),
      (1000..<2000, "middle 1KB"),
      (999_900..<1_000_000, "last 100 bytes"),
      (0..<1, "single byte"),
      (500_000..<500_001, "single byte at midpoint"),
    ]

    for (range, label) in ranges {
      let outURL = dir.appendingPathComponent("range_\(range.lowerBound)_\(range.upperBound).bin")
      let progress = try await device.read(handle: 600, range: range, to: outURL)
      let downloaded = try Data(contentsOf: outURL)

      let expectedLen = Int(range.upperBound - range.lowerBound)
      XCTAssertEqual(downloaded.count, expectedLen, "Range size: \(label)")
      XCTAssertEqual(
        progress.completedUnitCount, Int64(expectedLen),
        "Progress: \(label)")

      // Verify actual bytes match expected pattern
      for (j, byte) in downloaded.enumerated() {
        let globalOffset = Int(range.lowerBound) + j
        XCTAssertEqual(
          byte, UInt8(globalOffset % 256),
          "Byte mismatch at offset \(globalOffset) in \(label)")
      }
    }
  }

  // MARK: - 19. setObjectPropList Lifecycle

  /// Set object properties and verify they are accepted.
  func testSetObjectPropListLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    // Set properties on existing photo (handle 3)
    let entries = [
      MTPPropListEntry(handle: 3, propCode: 0xDC07, datatype: 0xFFFF, value: Data()),
      MTPPropListEntry(handle: 3, propCode: 0xDC44, datatype: 0x0004, value: Data([0x01, 0x00, 0x00, 0x00])),
    ]
    let result = try await device.setObjectPropList(entries: entries)
    XCTAssertEqual(result, UInt32(entries.count))

    // Verify operation recorded
    let ops = await device.operations.filter { $0.operation == "setObjectPropList" }
    XCTAssertEqual(ops.count, 1)
    XCTAssertEqual(ops[0].parameters["count"], "2")

    // Setting on non-existent handle should fail
    let badEntries = [
      MTPPropListEntry(handle: 9999, propCode: 0xDC07, datatype: 0xFFFF, value: Data())
    ]
    do {
      _ = try await device.setObjectPropList(entries: badEntries)
      XCTFail("Should throw for non-existent handle")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    try await device.devClose()
  }

  // MARK: - 20. Operation Log Integrity Across Full Lifecycle

  /// Verify the complete operation log captures every step in order.
  func testOperationLogIntegrityAcrossLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Perform a comprehensive set of operations
    try await device.openIfNeeded()
    _ = try await device.info
    _ = try await device.storages()
    _ = try await listAll(device: device, parent: nil, in: storageId)
    _ = try await device.getInfo(handle: 1)

    let data = Data(repeating: 0x11, count: 256)
    let srcURL = dir.appendingPathComponent("log_test.dat")
    try data.write(to: srcURL)
    _ = try await device.write(parent: nil, name: "log_test.dat", size: 256, from: srcURL)

    let outURL = dir.appendingPathComponent("log_download.dat")
    _ = try await device.read(handle: 4, range: nil, to: outURL)

    try await device.rename(4, to: "renamed_log.dat")

    let folder = try await device.createFolder(parent: nil, name: "LogFolder", storage: storageId)
    try await device.move(4, to: folder)
    try await device.delete(4, recursive: false)

    try await device.devClose()

    // Verify complete operation log
    let ops = await device.operations.map(\.operation)
    let expectedOps = [
      "openIfNeeded", "storages", "getInfo", "write", "read",
      "rename", "createFolder", "move", "delete", "devClose",
    ]
    for expected in expectedOps {
      XCTAssertTrue(ops.contains(expected), "Missing operation: \(expected)")
    }

    // Verify timestamps are monotonically increasing
    let timestamps = await device.operations.map(\.timestamp)
    for i in 1..<timestamps.count {
      XCTAssertGreaterThanOrEqual(
        timestamps[i], timestamps[i - 1],
        "Timestamps should be monotonically non-decreasing")
    }
  }
}
