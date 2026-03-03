// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTestKit

// MARK: - Wave 35: Deep Device Compatibility Tests

/// Research-grade compatibility tests validating quirk matching, extension
/// negotiation, and storage topology edge cases across diverse device profiles.
final class DeviceCompatibilityWave35Tests: XCTestCase {

  // MARK: - Helpers

  private func makeDevice(
    manufacturer: String = "TestVendor",
    model: String = "TestDevice",
    vid: UInt16 = 0xAAAA,
    pid: UInt16 = 0xBBBB,
    operationsSupported: Set<UInt16> = Set(
      [0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100B, 0x100C, 0x100D]
        .map { UInt16($0) }),
    eventsSupported: Set<UInt16> = Set([0x4002, 0x4003].map { UInt16($0) }),
    storages: [VirtualStorageConfig] = [],
    objects: [VirtualObjectConfig] = []
  ) -> VirtualMTPDevice {
    let deviceId = MTPDeviceID(raw: "\(String(format: "%04x", vid)):\(String(format: "%04x", pid))@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId,
      manufacturer: manufacturer,
      model: model,
      vendorID: vid,
      productID: pid,
      bus: 1,
      address: 1
    )
    let info = MTPDeviceInfo(
      manufacturer: manufacturer,
      model: model,
      version: "1.0",
      serialNumber: "W35-TEST",
      operationsSupported: operationsSupported,
      eventsSupported: eventsSupported
    )
    let config = VirtualDeviceConfig(
      deviceId: deviceId,
      summary: summary,
      info: info,
      storages: storages,
      objects: objects
    )
    return VirtualMTPDevice(config: config)
  }

  private func listAll(
    device: VirtualMTPDevice, parent: MTPObjectHandle?, in storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var results: [MTPObjectInfo] = []
    for try await batch in device.list(parent: parent, in: storage) {
      results.append(contentsOf: batch)
    }
    return results
  }

  // MARK: - 1. Multi-Storage Devices

  /// Devices like cameras often expose internal + SD card storages.
  /// Verify correct enumeration and independent per-storage access.
  func testMultiStorageEnumerationAndIndependentAccess() async throws {
    let internal1 = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal storage",
      capacityBytes: 64 * 1024 * 1024 * 1024,
      freeBytes: 32 * 1024 * 1024 * 1024
    )
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 128 * 1024 * 1024 * 1024,
      freeBytes: 96 * 1024 * 1024 * 1024
    )
    let internalFile = VirtualObjectConfig(
      handle: 1, storage: internal1.id, parent: nil,
      name: "internal_photo.jpg", sizeBytes: 4096, formatCode: 0x3801,
      data: Data(repeating: 0xFF, count: 4096)
    )
    let sdFile = VirtualObjectConfig(
      handle: 2, storage: sdCard.id, parent: nil,
      name: "sd_video.mp4", sizeBytes: 8192, formatCode: 0x300B,
      data: Data(repeating: 0xAA, count: 8192)
    )
    let device = makeDevice(
      manufacturer: "Canon", model: "EOS R5",
      storages: [internal1, sdCard],
      objects: [internalFile, sdFile]
    )

    // Verify both storages are reported
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    XCTAssertEqual(storages[0].description, "Internal storage")
    XCTAssertEqual(storages[1].description, "SD Card")

    // Verify objects are isolated per storage
    let internalObjs = try await listAll(device: device, parent: nil, in: internal1.id)
    XCTAssertEqual(internalObjs.count, 1)
    XCTAssertEqual(internalObjs.first?.name, "internal_photo.jpg")

    let sdObjs = try await listAll(device: device, parent: nil, in: sdCard.id)
    XCTAssertEqual(sdObjs.count, 1)
    XCTAssertEqual(sdObjs.first?.name, "sd_video.mp4")

    // Verify cross-storage isolation: listing internal storage must not return SD objects
    let internalNames = Set(internalObjs.map(\.name))
    XCTAssertFalse(internalNames.contains("sd_video.mp4"))
  }

  /// Triple-storage device (internal + SD + CF) — tests beyond typical dual-storage.
  func testTripleStorageTopology() async throws {
    let storageA = VirtualStorageConfig(id: MTPStorageID(raw: 0x0001_0001), description: "Internal")
    let storageB = VirtualStorageConfig(id: MTPStorageID(raw: 0x0002_0001), description: "SD Slot")
    let storageC = VirtualStorageConfig(id: MTPStorageID(raw: 0x0003_0001), description: "CF Slot")
    let device = makeDevice(
      manufacturer: "Nikon", model: "Z9",
      storages: [storageA, storageB, storageC]
    )

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 3)
    let ids = Set(storages.map(\.id.raw))
    XCTAssertEqual(ids, [0x0001_0001, 0x0002_0001, 0x0003_0001])
  }

  // MARK: - 2. No-Storage Device (Xiaomi ff40 Scenario)

  /// Some Android devices report 0 storages when MTP is not fully initialized.
  /// Verify graceful handling without crashes or hangs.
  func testZeroStorageDeviceGracefulHandling() async throws {
    let device = makeDevice(
      manufacturer: "Xiaomi", model: "Mi Note 2",
      vid: 0x2717, pid: 0xFF40,
      storages: []
    )

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 0, "Device with no storages should return empty array")

    // Listing objects on a non-existent storage should yield nothing (not crash)
    let phantom = MTPStorageID(raw: 0x0001_0001)
    let objects = try await listAll(device: device, parent: nil, in: phantom)
    XCTAssertTrue(objects.isEmpty, "Listing on non-existent storage should return empty results")
  }

  // MARK: - 3. Read-Only Storage

  /// SD cards or locked devices may report read-only storage.
  /// Verify the storage info correctly reflects the read-only flag.
  func testReadOnlyStorageReportsCorrectly() async throws {
    let roStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Locked SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 0,
      isReadOnly: true
    )
    let device = makeDevice(storages: [roStorage])

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    XCTAssertTrue(storages[0].isReadOnly, "Locked SD card must report isReadOnly = true")
    XCTAssertEqual(storages[0].freeBytes, 0, "Read-only storage should report 0 free bytes")
  }

  /// Mixed topology: writable internal + read-only SD card.
  func testMixedReadWriteAndReadOnlyStorages() async throws {
    let rw = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal",
      capacityBytes: 64_000_000_000, freeBytes: 32_000_000_000, isReadOnly: false
    )
    let ro = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card (locked)",
      capacityBytes: 32_000_000_000, freeBytes: 0, isReadOnly: true
    )
    let device = makeDevice(
      manufacturer: "Canon", model: "EOS R6",
      storages: [rw, ro]
    )

    let storages = try await device.storages()
    let writableCount = storages.filter { !$0.isReadOnly }.count
    let readOnlyCount = storages.filter { $0.isReadOnly }.count
    XCTAssertEqual(writableCount, 1)
    XCTAssertEqual(readOnlyCount, 1)
  }

  // MARK: - 4. Camera PTP Extensions

  /// PTP-only cameras support a minimal operation set without MTP extensions
  /// like GetPartialObject64 or SendObjectPropList.
  func testPTPOnlyDeviceLacksAndroidMTPExtensions() async throws {
    // Minimal PTP operation set (no MTP vendor extensions)
    let ptpOps: Set<UInt16> = Set([
      0x1001,  // GetDeviceInfo
      0x1002,  // OpenSession
      0x1003,  // CloseSession
      0x1004,  // GetStorageIDs
      0x1005,  // GetStorageInfo
      0x1007,  // GetObjectHandles
      0x1008,  // GetObjectInfo
      0x1009,  // GetObject
      0x100C,  // SendObjectInfo
      0x100D,  // SendObject
      0x100B,  // DeleteObject
    ].map { UInt16($0) })

    let device = makeDevice(
      manufacturer: "Canon", model: "EOS Rebel T7",
      vid: 0x04A9, pid: 0x3139,
      operationsSupported: ptpOps
    )
    let info = try await device.info

    // PTP-only should NOT support Android MTP extensions
    XCTAssertFalse(info.operationsSupported.contains(0x95C4), "PTP device should not support GetPartialObject64")
    XCTAssertFalse(info.operationsSupported.contains(0x95C1), "PTP device should not support SendPartialObject")
    XCTAssertFalse(info.operationsSupported.contains(0x9805), "PTP device should not support GetObjectPropList")

    // PTP-only must still support core operations
    XCTAssertTrue(info.operationsSupported.contains(0x1009), "PTP device must support GetObject")
    XCTAssertTrue(info.operationsSupported.contains(0x100C), "PTP device must support SendObjectInfo")
    XCTAssertTrue(info.operationsSupported.contains(0x100D), "PTP device must support SendObject")
  }

  /// Nikon PTP device with capture-specific extensions but no MTP partial transfers.
  func testNikonPTPWithCaptureExtensions() async throws {
    let nikonOps: Set<UInt16> = Set([
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009,
      0x100B, 0x100C, 0x100D,
      0x9001,  // Nikon capture
      0x9003,  // Nikon get preview
    ].map { UInt16($0) })

    let device = makeDevice(
      manufacturer: "Nikon", model: "Z6III",
      vid: 0x04B0, pid: 0x0410,
      operationsSupported: nikonOps
    )
    let info = try await device.info

    // Vendor extensions present
    XCTAssertTrue(info.operationsSupported.contains(0x9001))
    XCTAssertTrue(info.operationsSupported.contains(0x9003))

    // MTP Android extensions absent
    XCTAssertFalse(info.operationsSupported.contains(0x95C4))
    XCTAssertFalse(info.operationsSupported.contains(0x95C1))
  }

  // MARK: - 5. Android MTP Extensions

  /// Full Android MTP device with vendor-specific extensions including
  /// partial object transfer and property list enumeration.
  func testAndroidDeviceWithFullMTPExtensions() async throws {
    let androidOps: Set<UInt16> = Set([
      // Core PTP
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009,
      0x100B, 0x100C, 0x100D, 0x100E,
      // MTP extensions
      0x101B,  // GetPartialObject (32-bit)
      0x9805,  // GetObjectPropList
      0x9806,  // SetObjectPropValue
      0x95C1,  // SendPartialObject
      0x95C4,  // GetPartialObject64
    ].map { UInt16($0) })

    let device = makeDevice(
      manufacturer: "Google", model: "Pixel 7",
      vid: 0x18D1, pid: 0x4EE1,
      operationsSupported: androidOps
    )
    let info = try await device.info

    // Partial read: 64-bit preferred over 32-bit
    XCTAssertTrue(info.operationsSupported.contains(0x95C4), "Pixel 7 should support GetPartialObject64")
    XCTAssertTrue(info.operationsSupported.contains(0x101B), "Pixel 7 should support GetPartialObject (32)")
    XCTAssertTrue(info.operationsSupported.contains(0x95C1), "Pixel 7 should support SendPartialObject")
    XCTAssertTrue(info.operationsSupported.contains(0x9805), "Pixel 7 should support GetObjectPropList")
  }

  /// Samsung devices sometimes support MTP but not partial write.
  func testSamsungMTPWithoutPartialWrite() async throws {
    let samsungOps: Set<UInt16> = Set([
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009,
      0x100B, 0x100C, 0x100D,
      0x101B,  // GetPartialObject (32)
      0x9805,  // GetObjectPropList
    ].map { UInt16($0) })

    let device = makeDevice(
      manufacturer: "Samsung", model: "Galaxy S7",
      vid: 0x04E8, pid: 0x6860,
      operationsSupported: samsungOps
    )
    let info = try await device.info

    XCTAssertTrue(info.operationsSupported.contains(0x9805), "Samsung should support GetObjectPropList")
    XCTAssertFalse(info.operationsSupported.contains(0x95C1), "Samsung S7 should NOT support SendPartialObject")
    XCTAssertFalse(info.operationsSupported.contains(0x95C4), "Samsung S7 should NOT support GetPartialObject64")
  }

  // MARK: - 6. Quirk Matching for Unusual USB Descriptors

  /// Exact VID:PID match should return the correct quirk entry.
  func testQuirkMatchExactVIDPID() {
    let quirk = DeviceQuirk(
      id: "test-device-1234",
      vid: 0x1234, pid: 0x5678,
      ioTimeoutMs: 5000
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let result = db.match(vid: 0x1234, pid: 0x5678, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.id, "test-device-1234")
    XCTAssertEqual(result?.ioTimeoutMs, 5000)
  }

  /// Non-standard interface class/subclass (e.g., vendor-specific 0xFF) should
  /// match a quirk that specifies those descriptor fields.
  func testQuirkMatchWithNonStandardInterfaceDescriptors() {
    let standardQuirk = DeviceQuirk(
      id: "standard-mtp",
      vid: 0xAAAA, pid: 0xBBBB,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01,
      ioTimeoutMs: 3000
    )
    let vendorQuirk = DeviceQuirk(
      id: "vendor-specific",
      vid: 0xAAAA, pid: 0xBBBB,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00,
      ioTimeoutMs: 10000
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [standardQuirk, vendorQuirk])

    // Vendor-specific interface class should match the vendor quirk
    let result = db.match(
      vid: 0xAAAA, pid: 0xBBBB, bcdDevice: nil,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00
    )
    XCTAssertEqual(result?.id, "vendor-specific")
    XCTAssertEqual(result?.ioTimeoutMs, 10000)
  }

  /// When bcdDevice is specified in quirk, it should take precedence over generic VID:PID match.
  func testQuirkMatchBcdDeviceSpecificity() {
    let genericQuirk = DeviceQuirk(
      id: "generic",
      vid: 0x2717, pid: 0xFF10,
      ioTimeoutMs: 3000
    )
    let specificQuirk = DeviceQuirk(
      id: "specific-revision",
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: 0x0200,
      ioTimeoutMs: 8000
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [genericQuirk, specificQuirk])

    // With matching bcdDevice, should prefer the specific quirk
    let result = db.match(
      vid: 0x2717, pid: 0xFF10, bcdDevice: 0x0200,
      ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertEqual(result?.id, "specific-revision")
    XCTAssertEqual(result?.ioTimeoutMs, 8000)
  }

  /// VID:PID mismatch should return nil even if other fields match.
  func testQuirkMatchReturnsNilForUnknownDevice() {
    let quirk = DeviceQuirk(id: "known-device", vid: 0x1111, pid: 0x2222)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let result = db.match(vid: 0x9999, pid: 0x8888, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result, "Unknown VID:PID must not match any quirk")
  }

  // MARK: - 7. Timeout Scaling

  /// Quirk-specified I/O and handshake timeouts should be applied correctly.
  func testQuirkTimeoutValuesArePreserved() {
    let quirk = DeviceQuirk(
      id: "slow-device",
      vid: 0xDEAD, pid: 0xBEEF,
      ioTimeoutMs: 15000,
      handshakeTimeoutMs: 30000,
      overallDeadlineMs: 120_000
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let result = db.match(vid: 0xDEAD, pid: 0xBEEF, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.ioTimeoutMs, 15000, "I/O timeout must match quirk specification")
    XCTAssertEqual(result?.handshakeTimeoutMs, 30000, "Handshake timeout must match quirk specification")
    XCTAssertEqual(result?.overallDeadlineMs, 120_000, "Overall deadline must match quirk specification")
  }

  /// Quirk with stabilization delays for post-claim and post-probe phases.
  func testQuirkStabilizationDelays() {
    let quirk = DeviceQuirk(
      id: "needs-stabilize",
      vid: 0x2A70, pid: 0xF003,
      stabilizeMs: 500,
      postClaimStabilizeMs: 1000,
      postProbeStabilizeMs: 200
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let result = db.match(vid: 0x2A70, pid: 0xF003, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.stabilizeMs, 500)
    XCTAssertEqual(result?.postClaimStabilizeMs, 1000)
    XCTAssertEqual(result?.postProbeStabilizeMs, 200)
  }

  /// Quirk hooks with busy backoff configuration.
  func testQuirkBusyBackoffHook() {
    let hook = QuirkHook(
      phase: .onDeviceBusy,
      busyBackoff: QuirkHook.BusyBackoff(retries: 5, baseMs: 200, jitterPct: 0.1)
    )
    let quirk = DeviceQuirk(
      id: "busy-device",
      vid: 0xBBBB, pid: 0xCCCC,
      hooks: [hook]
    )
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let result = db.match(vid: 0xBBBB, pid: 0xCCCC, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.hooks?.count, 1)
    XCTAssertEqual(result?.hooks?.first?.phase, .onDeviceBusy)
    XCTAssertEqual(result?.hooks?.first?.busyBackoff?.retries, 5)
    XCTAssertEqual(result?.hooks?.first?.busyBackoff?.baseMs, 200)
  }

  // MARK: - 8. Object Format Edge Cases

  /// Test listing objects with unusual format codes (RAW, DNG, MP4 variants).
  func testUnusualObjectFormatCodes() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal"
    )
    let rawFile = VirtualObjectConfig(
      handle: 1, storage: storage.id, parent: nil,
      name: "photo.cr3", sizeBytes: 25_000_000,
      formatCode: 0xB104,  // Canon RAW
      data: Data(repeating: 0x01, count: 64)
    )
    let dngFile = VirtualObjectConfig(
      handle: 2, storage: storage.id, parent: nil,
      name: "photo.dng", sizeBytes: 30_000_000,
      formatCode: 0xB811,  // DNG
      data: Data(repeating: 0x02, count: 64)
    )
    let heifFile = VirtualObjectConfig(
      handle: 3, storage: storage.id, parent: nil,
      name: "photo.heif", sizeBytes: 5_000_000,
      formatCode: 0xB802,  // HEIF
      data: Data(repeating: 0x03, count: 64)
    )
    let mp4Variant = VirtualObjectConfig(
      handle: 4, storage: storage.id, parent: nil,
      name: "video.3gp", sizeBytes: 10_000_000,
      formatCode: 0xB984,  // 3GP
      data: Data(repeating: 0x04, count: 64)
    )
    let undefinedFormat = VirtualObjectConfig(
      handle: 5, storage: storage.id, parent: nil,
      name: "unknown.xyz", sizeBytes: 1024,
      formatCode: 0x3000,  // Undefined
      data: Data(repeating: 0x05, count: 64)
    )

    let device = makeDevice(
      manufacturer: "Canon", model: "EOS R5",
      storages: [storage],
      objects: [rawFile, dngFile, heifFile, mp4Variant, undefinedFormat]
    )

    let allObjects = try await listAll(device: device, parent: nil, in: storage.id)
    XCTAssertEqual(allObjects.count, 5)

    // Verify format codes are preserved through the virtual device
    let formatCodes = Set(allObjects.map(\.formatCode))
    XCTAssertTrue(formatCodes.contains(0xB104), "Canon RAW format should be preserved")
    XCTAssertTrue(formatCodes.contains(0xB811), "DNG format should be preserved")
    XCTAssertTrue(formatCodes.contains(0xB802), "HEIF format should be preserved")
    XCTAssertTrue(formatCodes.contains(0xB984), "3GP format should be preserved")
    XCTAssertTrue(formatCodes.contains(0x3000), "Undefined format should be preserved")
  }

  /// PTPObjectFormat.forFilename should map common extensions correctly and
  /// fall back to 0x3000 for unknown extensions.
  func testPTPObjectFormatMapping() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpeg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380B)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300B)
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
    XCTAssertEqual(PTPObjectFormat.forFilename("notes.txt"), 0x3004)

    // Unknown extensions should map to Undefined (0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename("archive.tar.gz"), 0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.cr3"), 0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.dng"), 0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.3gp"), 0x3000)
  }

  /// Objects with the association format code (0x3001) must report as folders.
  func testFolderFormatCodeIdentification() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal"
    )
    let folder = VirtualObjectConfig(
      handle: 1, storage: storage.id, parent: nil,
      name: "DCIM", formatCode: 0x3001
    )
    let file = VirtualObjectConfig(
      handle: 2, storage: storage.id, parent: 1,
      name: "photo.jpg", formatCode: 0x3801,
      data: Data(repeating: 0xFF, count: 100)
    )
    let device = makeDevice(storages: [storage], objects: [folder, file])

    let rootObjs = try await listAll(device: device, parent: nil, in: storage.id)
    XCTAssertEqual(rootObjs.count, 1)
    XCTAssertEqual(rootObjs.first?.formatCode, 0x3001, "Folder must have association format code")

    let childObjs = try await listAll(device: device, parent: 1, in: storage.id)
    XCTAssertEqual(childObjs.count, 1)
    XCTAssertEqual(childObjs.first?.formatCode, 0x3801, "JPEG file must have EXIF/JPEG format code")
  }

  // MARK: - 9. Quirk Flags Behavioral Validation

  /// QuirkFlags should correctly encode transport and protocol-level behavior.
  func testQuirkFlagsRoundTrip() {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.requiresKernelDetach = false
    flags.needsLongerOpenTimeout = true
    flags.requiresSessionBeforeDeviceInfo = true
    flags.supportsPartialRead64 = false

    let quirk = DeviceQuirk(
      id: "flagged-device",
      vid: 0x1234, pid: 0x5678,
      flags: flags
    )

    XCTAssertTrue(quirk.flags?.resetOnOpen ?? false)
    XCTAssertFalse(quirk.flags?.requiresKernelDetach ?? true)
    XCTAssertTrue(quirk.flags?.needsLongerOpenTimeout ?? false)
    XCTAssertTrue(quirk.flags?.requiresSessionBeforeDeviceInfo ?? false)
    XCTAssertFalse(quirk.flags?.supportsPartialRead64 ?? true)
  }

  /// DeviceQuirk resolvedFlags() should provide correct defaults.
  func testResolvedFlagsDefaults() {
    let quirk = DeviceQuirk(id: "minimal", vid: 0x1111, pid: 0x2222)
    let resolved = quirk.resolvedFlags()

    // Default flags
    XCTAssertFalse(resolved.resetOnOpen)
    XCTAssertTrue(resolved.requiresKernelDetach)
    XCTAssertTrue(resolved.supportsPartialRead64)
  }
}
