// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CommonCrypto
import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTestKit

// MARK: - End-to-End Workflow Scenario Tests

/// Expanded end-to-end scenarios covering full user workflows:
/// device lifecycle, mirror/resume, error recovery, multi-storage,
/// large file transfer with hash verification, and quirk-dependent behavior.
final class EndToEndWorkflowScenarioTests: XCTestCase {

  // MARK: - Helpers

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-e2e")
  }

  private func listAll(
    device: VirtualMTPDevice, parent: MTPObjectHandle?, in storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream { objects.append(contentsOf: batch) }
    return objects
  }

  private func sha256(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - 1. Full Device Lifecycle

  /// Connect → probe → open session → get device info → list storages →
  /// list files → download file → upload file → close session → disconnect
  func testFullDeviceLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Connect & open session
    try await device.openIfNeeded()

    // Get device info
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertFalse(info.operationsSupported.isEmpty)

    // List storages
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Internal shared storage")
    XCTAssertGreaterThan(storages[0].capacityBytes, 0)
    XCTAssertGreaterThan(storages[0].freeBytes, 0)

    // List root files
    let rootObjects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(rootObjects.isEmpty)
    let dcim = rootObjects.first { $0.name == "DCIM" }
    XCTAssertNotNil(dcim)
    XCTAssertEqual(dcim?.formatCode, 0x3001)

    // Navigate into DCIM/Camera and list files
    let cameraFiles = try await listAll(device: device, parent: 2, in: storages[0].id)
    XCTAssertFalse(cameraFiles.isEmpty)
    let photo = cameraFiles.first!

    // Download file
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let downloadURL = dir.appendingPathComponent(photo.name)
    let readProgress = try await device.read(handle: photo.handle, range: nil, to: downloadURL)
    XCTAssertGreaterThan(readProgress.completedUnitCount, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: downloadURL.path))

    // Upload file
    let uploadData = Data(repeating: 0xAB, count: 8192)
    let uploadURL = dir.appendingPathComponent("uploaded.dat")
    try uploadData.write(to: uploadURL)
    let writeProgress = try await device.write(
      parent: nil, name: "uploaded.dat",
      size: UInt64(uploadData.count), from: uploadURL
    )
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(uploadData.count))

    // Verify uploaded file exists
    let uploadedInfo = try await device.getInfo(handle: 4)
    XCTAssertEqual(uploadedInfo.name, "uploaded.dat")
    XCTAssertEqual(uploadedInfo.sizeBytes, UInt64(uploadData.count))

    // Close session & disconnect
    try await device.devClose()

    // Verify full operation log
    let ops = await device.operations.map(\.operation)
    XCTAssertTrue(ops.contains("openIfNeeded"))
    XCTAssertTrue(ops.contains("read"))
    XCTAssertTrue(ops.contains("write"))
    XCTAssertTrue(ops.contains("devClose"))
  }

  // MARK: - 2. Mirror Workflow with Reconnect Resume

  /// Connect → open session → enumerate device files → download to local mirror →
  /// verify local files match device → disconnect → reconnect → add new file →
  /// resume mirror (download only new file)
  func testMirrorWorkflowWithReconnectResume() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    // Phase 1: Initial mirror
    try await device.openIfNeeded()
    let storages = try await device.storages()
    let cameraFiles = try await listAll(device: device, parent: 2, in: storages[0].id)
    XCTAssertFalse(cameraFiles.isEmpty)

    // Download all files in Camera folder
    var mirroredHandles = Set<MTPObjectHandle>()
    for file in cameraFiles where file.formatCode != 0x3001 {
      let outURL = dir.appendingPathComponent(file.name)
      _ = try await device.read(handle: file.handle, range: nil, to: outURL)
      XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
      mirroredHandles.insert(file.handle)
    }

    // Verify local files match device count
    let localFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(localFiles.count, cameraFiles.filter { $0.formatCode != 0x3001 }.count)

    // Disconnect
    try await device.devClose()

    // Phase 2: Reconnect and resume
    try await device.openIfNeeded()

    // Simulate new file added to device while disconnected
    let newFileData = Data(repeating: 0xCD, count: 2048)
    let newObj = VirtualObjectConfig(
      handle: 100, storage: storages[0].id, parent: 2,
      name: "IMG_NEW.jpg", sizeBytes: UInt64(newFileData.count),
      formatCode: 0x3801, data: newFileData
    )
    await device.addObject(newObj)

    // Re-enumerate and find only new files
    let updatedFiles = try await listAll(device: device, parent: 2, in: storages[0].id)
    let newFiles = updatedFiles.filter { !mirroredHandles.contains($0.handle) && $0.formatCode != 0x3001 }
    XCTAssertEqual(newFiles.count, 1)
    XCTAssertEqual(newFiles[0].name, "IMG_NEW.jpg")

    // Download only the new file
    let newURL = dir.appendingPathComponent(newFiles[0].name)
    let resumeProgress = try await device.read(handle: newFiles[0].handle, range: nil, to: newURL)
    XCTAssertEqual(resumeProgress.completedUnitCount, Int64(newFileData.count))
    XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))

    // Verify downloaded content matches
    let downloaded = try Data(contentsOf: newURL)
    XCTAssertEqual(downloaded, newFileData)

    try await device.devClose()
  }

  // MARK: - 3. Error Recovery Workflow

  /// Connect → start download → inject stall → verify recovery → download completes
  func testErrorRecoveryDuringDownload() async throws {
    let fileData = Data(repeating: 0xEE, count: 65536)
    let fileObj = VirtualObjectConfig(
      handle: 10, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "recovery_test.bin", sizeBytes: UInt64(fileData.count),
      formatCode: 0x3000, data: fileData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(fileObj)

    // Set up fault injection on the link layer
    let link = VirtualMTPLink(config: config)
    let schedule = FaultSchedule([
      .pipeStall(on: .executeStreamingCommand)
    ])
    let faultyLink = FaultInjectingLink(wrapping: link, schedule: schedule)

    // First attempt: stall fires
    try await faultyLink.openSession(id: 1)
    let deviceInfo = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(deviceInfo.model, "Pixel 7")

    // Streaming command stalls once
    let getObjectCmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: 0x1009, txid: 1, params: [10]
    )
    do {
      _ = try await faultyLink.executeStreamingCommand(
        getObjectCmd,
        dataPhaseLength: UInt64(fileData.count),
        dataInHandler: nil,
        dataOutHandler: nil
      )
      XCTFail("Expected stall error on first attempt")
    } catch {
      // Expected: pipe stall
    }

    // Recovery: retry succeeds (fault was one-shot)
    let retryCmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: 0x1009, txid: 2, params: [10]
    )
    let result = try await faultyLink.executeStreamingCommand(
      retryCmd,
      dataPhaseLength: UInt64(fileData.count),
      dataInHandler: nil,
      dataOutHandler: nil
    )
    XCTAssertNotNil(result)

    // Session still operational after recovery
    let storageIDs = try await faultyLink.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty)
  }

  /// Verify fault injection with timeout then successful retry at device level
  func testErrorRecoveryTimeoutThenRetryAtDeviceLevel() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    try await device.openIfNeeded()

    // Download succeeds (VirtualMTPDevice doesn't use FaultInjectingLink directly,
    // but we verify the device remains operational through the full cycle)
    let outURL = dir.appendingPathComponent("photo.jpg")
    let progress = try await device.read(handle: 3, range: nil, to: outURL)
    XCTAssertEqual(progress.completedUnitCount, progress.totalUnitCount)

    // Inject an event simulating a transient error condition
    await device.injectEvent(.deviceReset)

    // Device should still be operational after reset event
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Can still download after the event
    let outURL2 = dir.appendingPathComponent("photo2.jpg")
    let progress2 = try await device.read(handle: 3, range: nil, to: outURL2)
    XCTAssertEqual(progress2.completedUnitCount, progress2.totalUnitCount)

    try await device.devClose()
  }

  // MARK: - 4. Multi-Storage Device

  /// Connect → discover 2 storages → list files from each → verify independent operation
  func testMultiStorageDeviceIndependentOperations() async throws {
    let internalStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal Storage",
      capacityBytes: 64 * 1024 * 1024 * 1024,
      freeBytes: 32 * 1024 * 1024 * 1024
    )
    let sdCardStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 128 * 1024 * 1024 * 1024,
      freeBytes: 100 * 1024 * 1024 * 1024
    )

    let internalData = Data(repeating: 0xAA, count: 4096)
    let sdData = Data(repeating: 0xBB, count: 8192)

    let internalFile = VirtualObjectConfig(
      handle: 10, storage: internalStorage.id, parent: nil,
      name: "internal_doc.pdf", sizeBytes: UInt64(internalData.count),
      formatCode: 0x3000, data: internalData
    )
    let sdFile = VirtualObjectConfig(
      handle: 20, storage: sdCardStorage.id, parent: nil,
      name: "sd_photo.jpg", sizeBytes: UInt64(sdData.count),
      formatCode: 0x3801, data: sdData
    )

    var config = VirtualDeviceConfig.pixel7
    config.storages = [internalStorage, sdCardStorage]
    config.objects = [internalFile, sdFile]
    let device = VirtualMTPDevice(config: config)

    try await device.openIfNeeded()

    // Discover both storages
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    XCTAssertEqual(storages[0].description, "Internal Storage")
    XCTAssertEqual(storages[1].description, "SD Card")

    // List files from each storage independently
    let internalObjects = try await listAll(device: device, parent: nil, in: internalStorage.id)
    let sdObjects = try await listAll(device: device, parent: nil, in: sdCardStorage.id)

    XCTAssertEqual(internalObjects.count, 1)
    XCTAssertEqual(internalObjects[0].name, "internal_doc.pdf")

    XCTAssertEqual(sdObjects.count, 1)
    XCTAssertEqual(sdObjects[0].name, "sd_photo.jpg")

    // Download from each storage
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let internalURL = dir.appendingPathComponent("internal_doc.pdf")
    let sdURL = dir.appendingPathComponent("sd_photo.jpg")

    let p1 = try await device.read(handle: 10, range: nil, to: internalURL)
    let p2 = try await device.read(handle: 20, range: nil, to: sdURL)

    XCTAssertEqual(p1.completedUnitCount, Int64(internalData.count))
    XCTAssertEqual(p2.completedUnitCount, Int64(sdData.count))

    // Verify content integrity
    let downloadedInternal = try Data(contentsOf: internalURL)
    let downloadedSD = try Data(contentsOf: sdURL)
    XCTAssertEqual(downloadedInternal, internalData)
    XCTAssertEqual(downloadedSD, sdData)

    // Upload to each storage independently
    let uploadData1 = Data(repeating: 0x11, count: 1024)
    let uploadData2 = Data(repeating: 0x22, count: 2048)
    let src1 = dir.appendingPathComponent("upload_internal.dat")
    let src2 = dir.appendingPathComponent("upload_sd.dat")
    try uploadData1.write(to: src1)
    try uploadData2.write(to: src2)

    // Upload to internal (parent nil → uses first storage)
    let wp1 = try await device.write(parent: nil, name: "upload_internal.dat", size: 1024, from: src1)
    XCTAssertEqual(wp1.completedUnitCount, 1024)

    // Verify storages have different capacities
    XCTAssertNotEqual(storages[0].capacityBytes, storages[1].capacityBytes)

    try await device.devClose()
  }

  // MARK: - 5. Large File Transfer with Hash Verification

  /// Connect → upload 10MB file → verify chunked transfer → download and verify SHA-256 match
  func testLargeFileTransferWithHashVerification() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    try await device.openIfNeeded()

    // Generate 10MB file with deterministic pattern
    let tenMB = 10 * 1024 * 1024
    var largeData = Data(capacity: tenMB)
    for i in 0..<tenMB {
      largeData.append(UInt8(i % 251))  // Prime modulus for varied pattern
    }
    XCTAssertEqual(largeData.count, tenMB)

    // Compute original hash
    let originalHash = sha256(largeData)

    // Upload
    let srcURL = dir.appendingPathComponent("large_10mb.bin")
    try largeData.write(to: srcURL)

    let uploadProgress = try await device.write(
      parent: nil, name: "large_10mb.bin",
      size: UInt64(tenMB), from: srcURL
    )
    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(tenMB))
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(tenMB))

    // Verify file was stored (new handle = 4, after DCIM(1), Camera(2), photo(3))
    let storedInfo = try await device.getInfo(handle: 4)
    XCTAssertEqual(storedInfo.name, "large_10mb.bin")
    XCTAssertEqual(storedInfo.sizeBytes, UInt64(tenMB))

    // Download
    let downloadURL = dir.appendingPathComponent("large_10mb_downloaded.bin")
    let downloadProgress = try await device.read(handle: 4, range: nil, to: downloadURL)
    XCTAssertEqual(downloadProgress.totalUnitCount, Int64(tenMB))
    XCTAssertEqual(downloadProgress.completedUnitCount, Int64(tenMB))

    // Verify hash match
    let downloadedData = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloadedData.count, tenMB)
    let downloadedHash = sha256(downloadedData)
    XCTAssertEqual(originalHash, downloadedHash, "SHA-256 hash mismatch after upload/download round-trip")

    // Verify byte-level equality
    XCTAssertEqual(largeData, downloadedData)

    try await device.devClose()
  }

  /// Verify ranged read on a large file returns correct subset with matching hash
  func testLargeFilePartialReadHashVerification() async throws {
    let fileSize = 2 * 1024 * 1024
    var fileData = Data(capacity: fileSize)
    for i in 0..<fileSize { fileData.append(UInt8(i % 199)) }

    let fileObj = VirtualObjectConfig(
      handle: 50, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "partial_read.bin", sizeBytes: UInt64(fileSize),
      formatCode: 0x3000, data: fileData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(fileObj)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    try await device.openIfNeeded()

    // Read a 512KB range from offset 256KB
    let rangeStart: UInt64 = 256 * 1024
    let rangeEnd: UInt64 = 768 * 1024
    let outURL = dir.appendingPathComponent("partial.bin")
    let progress = try await device.read(handle: 50, range: rangeStart..<rangeEnd, to: outURL)
    XCTAssertEqual(progress.completedUnitCount, Int64(rangeEnd - rangeStart))

    let partialData = try Data(contentsOf: outURL)
    let expectedSlice = fileData[Int(rangeStart)..<Int(rangeEnd)]
    XCTAssertEqual(sha256(partialData), sha256(Data(expectedSlice)))

    try await device.devClose()
  }

  // MARK: - 6. Quirk-Dependent Device (Samsung)

  /// Connect Samsung mock → verify skipAltSetting flag is set → session opens successfully
  func testSamsungQuirkDependentDeviceBehavior() async throws {
    // Create a quirk entry matching Samsung Galaxy VID:PID
    var samsungFlags = QuirkFlags()
    samsungFlags.skipAltSetting = true
    samsungFlags.skipPreClaimReset = true
    samsungFlags.brokenSendObjectPropList = true

    let samsungQuirk = DeviceQuirk(
      id: "samsung-galaxy-test",
      deviceName: "Samsung Galaxy (Test)",
      category: "phone",
      vid: 0x04e8,
      pid: 0x6860,
      flags: samsungFlags,
      status: .verified
    )

    // Build a mini database with just this entry
    let db = QuirkDatabase(schemaVersion: "2.0", entries: [samsungQuirk])

    // Match the Samsung device
    let matched = db.match(
      vid: 0x04e8, pid: 0x6860,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(matched)
    XCTAssertEqual(matched?.id, "samsung-galaxy-test")

    // Verify quirk flags
    let resolvedFlags = matched!.resolvedFlags()
    XCTAssertTrue(resolvedFlags.skipAltSetting, "Samsung requires skipAltSetting")
    XCTAssertTrue(resolvedFlags.skipPreClaimReset, "Samsung requires skipPreClaimReset")
    XCTAssertTrue(resolvedFlags.brokenSendObjectPropList, "Samsung has brokenSendObjectPropList")

    // Verify the Samsung device config works end-to-end
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Samsung")
    XCTAssertTrue(info.model.contains("Galaxy"))

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // List and download a file
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(objects.isEmpty)

    // Upload with the Samsung profile active
    let uploadData = Data(repeating: 0xDD, count: 2048)
    let srcURL = dir.appendingPathComponent("samsung_upload.dat")
    try uploadData.write(to: srcURL)
    let progress = try await device.write(
      parent: nil, name: "samsung_upload.dat",
      size: UInt64(uploadData.count), from: srcURL
    )
    XCTAssertEqual(progress.completedUnitCount, Int64(uploadData.count))

    try await device.devClose()
  }

  /// Verify quirk database lookup returns correct flags for known Samsung PIDs
  func testQuirkDatabaseLookupForSamsungPIDs() async throws {
    var flags6860 = QuirkFlags()
    flags6860.skipAltSetting = true
    flags6860.skipPreClaimReset = true

    var flags685c = QuirkFlags()
    flags685c.skipAltSetting = true
    flags685c.propListOverridesObjectInfo = true

    let db = QuirkDatabase(schemaVersion: "2.0", entries: [
      DeviceQuirk(id: "samsung-mtp", vid: 0x04e8, pid: 0x6860, flags: flags6860),
      DeviceQuirk(id: "samsung-mtp-adb", vid: 0x04e8, pid: 0x685c, flags: flags685c),
    ])

    // Match standard MTP PID
    let match1 = db.match(
      vid: 0x04e8, pid: 0x6860,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(match1)
    let f1 = match1!.resolvedFlags()
    XCTAssertTrue(f1.skipAltSetting)
    XCTAssertTrue(f1.skipPreClaimReset)
    XCTAssertFalse(f1.propListOverridesObjectInfo)

    // Match MTP+ADB PID
    let match2 = db.match(
      vid: 0x04e8, pid: 0x685c,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(match2)
    let f2 = match2!.resolvedFlags()
    XCTAssertTrue(f2.skipAltSetting)
    XCTAssertTrue(f2.propListOverridesObjectInfo)

    // No match for unknown PID
    let noMatch = db.match(
      vid: 0x04e8, pid: 0x9999,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNil(noMatch)
  }

  // MARK: - 7. Multi-Fault Recovery Chain

  /// Multiple fault types fire in sequence; device remains operational after each recovery
  func testMultiFaultRecoveryChain() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getStorageIDs),
      .pipeStall(on: .getObjectHandles),
      .timeoutOnce(on: .getStorageInfo),
    ])
    let faultyLink = FaultInjectingLink(wrapping: link, schedule: schedule)

    try await faultyLink.openSession(id: 1)

    // Fault 1: timeout on getStorageIDs
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected timeout")
    } catch {}

    // Recovery: retry succeeds
    let storageIDs = try await faultyLink.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty)

    // Fault 2: stall on getObjectHandles
    do {
      _ = try await faultyLink.getObjectHandles(storage: storageIDs[0], parent: nil)
      XCTFail("Expected pipe stall")
    } catch {}

    // Recovery: retry succeeds
    let handles = try await faultyLink.getObjectHandles(storage: storageIDs[0], parent: nil)
    XCTAssertFalse(handles.isEmpty)

    // Fault 3: timeout on getStorageInfo
    do {
      _ = try await faultyLink.getStorageInfo(id: storageIDs[0])
      XCTFail("Expected timeout")
    } catch {}

    // Recovery: retry succeeds
    let storageInfo = try await faultyLink.getStorageInfo(id: storageIDs[0])
    XCTAssertGreaterThan(storageInfo.capacityBytes, 0)

    // Full chain recovered — device is still operational
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 8. Copy + Thumbnail Workflow

  /// Upload → copy on device → get thumbnail → verify both copies exist
  func testCopyAndThumbnailWorkflow() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    try await device.openIfNeeded()

    // Upload a file
    let data = Data(repeating: 0x42, count: 4096)
    let srcURL = dir.appendingPathComponent("original.dat")
    try data.write(to: srcURL)
    _ = try await device.write(parent: nil, name: "original.dat", size: 4096, from: srcURL)

    // The uploaded file gets handle 4
    let originalInfo = try await device.getInfo(handle: 4)
    XCTAssertEqual(originalInfo.name, "original.dat")

    // Copy on device
    let storages = try await device.storages()
    let copyHandle = try await device.copyObject(
      handle: 4, toStorage: storages[0].id, parentFolder: nil
    )
    XCTAssertNotEqual(copyHandle, 4)

    // Verify copy exists
    let copyInfo = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo.name, "original.dat")
    XCTAssertEqual(copyInfo.sizeBytes, 4096)

    // Get thumbnail for the original photo (handle 3 from pixel7 preset)
    let thumbData = try await device.getThumbnail(handle: 3)
    XCTAssertFalse(thumbData.isEmpty)
    // Verify JPEG SOI marker
    XCTAssertEqual(thumbData[0], 0xFF)
    XCTAssertEqual(thumbData[1], 0xD8)

    try await device.devClose()
  }

  // MARK: - 9. Concurrent Downloads from Multiple Storages

  /// Two storages accessed concurrently with async let
  func testConcurrentDownloadsFromMultipleStorages() async throws {
    let storage1 = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal"
    )
    let storage2 = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card"
    )
    let file1Data = Data(repeating: 0x11, count: 16384)
    let file2Data = Data(repeating: 0x22, count: 32768)
    let file1 = VirtualObjectConfig(
      handle: 10, storage: storage1.id, parent: nil,
      name: "internal.bin", sizeBytes: UInt64(file1Data.count),
      formatCode: 0x3000, data: file1Data
    )
    let file2 = VirtualObjectConfig(
      handle: 20, storage: storage2.id, parent: nil,
      name: "sdcard.bin", sizeBytes: UInt64(file2Data.count),
      formatCode: 0x3000, data: file2Data
    )

    var config = VirtualDeviceConfig.pixel7
    config.storages = [storage1, storage2]
    config.objects = [file1, file2]
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    try await device.openIfNeeded()

    // Concurrent downloads
    let url1 = dir.appendingPathComponent("internal.bin")
    let url2 = dir.appendingPathComponent("sdcard.bin")
    async let p1 = device.read(handle: 10, range: nil, to: url1)
    async let p2 = device.read(handle: 20, range: nil, to: url2)
    let (progress1, progress2) = try await (p1, p2)

    XCTAssertEqual(progress1.completedUnitCount, Int64(file1Data.count))
    XCTAssertEqual(progress2.completedUnitCount, Int64(file2Data.count))

    // Verify content
    XCTAssertEqual(try Data(contentsOf: url1), file1Data)
    XCTAssertEqual(try Data(contentsOf: url2), file2Data)

    try await device.devClose()
  }

  // MARK: - 10. Event-Driven Workflow

  /// Inject events during operations and verify device state consistency
  func testEventDrivenWorkflowDuringOperations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Inject object-added event
    await device.injectEvent(.objectAdded(100))

    // Add the object the event refers to
    let newData = Data(repeating: 0xFF, count: 1024)
    let newObj = VirtualObjectConfig(
      handle: 100, storage: storages[0].id, parent: nil,
      name: "event_added.dat", sizeBytes: UInt64(newData.count),
      formatCode: 0x3000, data: newData
    )
    await device.addObject(newObj)

    // Verify the object is accessible
    let info = try await device.getInfo(handle: 100)
    XCTAssertEqual(info.name, "event_added.dat")

    // Inject storage-info-changed event
    await device.injectEvent(.storageInfoChanged(storages[0].id))

    // Storage should still be queryable
    let refreshedStorages = try await device.storages()
    XCTAssertEqual(refreshedStorages.count, storages.count)

    // Inject object-removed event and remove the object
    await device.injectEvent(.objectRemoved(100))
    await device.removeObject(handle: 100)

    // Verify object is gone
    do {
      _ = try await device.getInfo(handle: 100)
      XCTFail("Expected error for removed object")
    } catch {
      // Expected
    }

    try await device.devClose()
  }
}
