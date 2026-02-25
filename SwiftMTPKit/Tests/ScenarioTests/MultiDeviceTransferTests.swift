// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - Multi-Device Parallel Transfer Tests

/// Tests that verify correct isolation and independent operation of multiple
/// simultaneously connected MTP devices. All tests use VirtualMTPDevice so
/// no real USB hardware is required.
final class MultiDeviceParallelTransferTests: XCTestCase {

  // MARK: - Helpers

  /// Build a deterministic per-device config with unique VID:PID and a
  /// pre-seeded file so reads can be verified.
  private func makeDevice(index: Int) -> (device: VirtualMTPDevice, config: VirtualDeviceConfig) {
    let vid = UInt16(0x2000 + index)
    let pid = UInt16(0x0001)
    let deviceId = MTPDeviceID(
      raw: "\(String(vid, radix: 16)):\(String(pid, radix: 16))@1:\(index)")

    let summary = MTPDeviceSummary(
      id: deviceId,
      manufacturer: "VirtualMFG",
      model: "VirtualDev-\(index)",
      vendorID: vid,
      productID: pid,
      bus: 1,
      address: UInt8(index)
    )
    let info = MTPDeviceInfo(
      manufacturer: "VirtualMFG",
      model: "VirtualDev-\(index)",
      version: "1.0",
      serialNumber: "VIRT00\(index)",
      operationsSupported: Set(
        [0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100B, 0x100C, 0x100D]
          .map { UInt16($0) }),
      eventsSupported: Set([0x4002, 0x4003].map { UInt16($0) })
    )
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal storage device \(index)",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 16 * 1024 * 1024 * 1024
    )
    // Pre-seed a unique file for each device so reads can tell devices apart
    let fileData = Data(repeating: UInt8(index & 0xFF), count: 64 * 1024)
    let seedFile = VirtualObjectConfig(
      handle: MTPObjectHandle(100 + index),
      storage: storage.id,
      parent: nil,
      name: "seed-\(index).dat",
      sizeBytes: UInt64(fileData.count),
      formatCode: 0x3000,
      data: fileData
    )
    let cfg = VirtualDeviceConfig(
      deviceId: deviceId,
      summary: summary,
      info: info,
      storages: [storage],
      objects: [seedFile]
    )
    return (VirtualMTPDevice(config: cfg), cfg)
  }

  // MARK: - Tests

  /// Three devices can each list their own storage independently.
  func testThreeDevicesListStoragesInParallel() async throws {
    let (d1, _) = makeDevice(index: 1)
    let (d2, _) = makeDevice(index: 2)
    let (d3, _) = makeDevice(index: 3)

    async let s1 = d1.storages()
    async let s2 = d2.storages()
    async let s3 = d3.storages()

    let (storages1, storages2, storages3) = try await (s1, s2, s3)

    XCTAssertEqual(storages1.count, 1, "Device 1 storage count")
    XCTAssertEqual(storages2.count, 1, "Device 2 storage count")
    XCTAssertEqual(storages3.count, 1, "Device 3 storage count")

    XCTAssertTrue(storages1[0].description.contains("device 1"))
    XCTAssertTrue(storages2[0].description.contains("device 2"))
    XCTAssertTrue(storages3[0].description.contains("device 3"))
  }

  /// Reads from multiple devices in parallel return the correct per-device data.
  func testParallelReadFromTwoDevicesReturnCorrectData() async throws {
    let (d1, _) = makeDevice(index: 1)
    let (d2, _) = makeDevice(index: 2)

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mtp-multi-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let out1 = tmpDir.appendingPathComponent("d1.dat")
    let out2 = tmpDir.appendingPathComponent("d2.dat")

    // Seed file handle: 100 + device index
    async let p1 = d1.read(handle: 101, range: nil, to: out1)
    async let p2 = d2.read(handle: 102, range: nil, to: out2)

    let (prog1, prog2) = try await (p1, p2)

    // Progress units should be total bytes (64 KB each)
    XCTAssertEqual(prog1.totalUnitCount, 64 * 1024)
    XCTAssertEqual(prog2.totalUnitCount, 64 * 1024)

    let bytes1 = try Data(contentsOf: out1)
    let bytes2 = try Data(contentsOf: out2)

    // Each device wrote its own fill byte
    XCTAssertTrue(bytes1.allSatisfy { $0 == 1 }, "d1 data should be all 0x01")
    XCTAssertTrue(bytes2.allSatisfy { $0 == 2 }, "d2 data should be all 0x02")
  }

  /// Concurrent writes to two devices create isolated object trees.
  func testParallelWriteToTwoDevicesIsolated() async throws {
    let (d1, _) = makeDevice(index: 1)
    let (d2, _) = makeDevice(index: 2)

    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mtp-write-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Write 8 KB of unique data to each device
    let data1 = Data(repeating: 0xAA, count: 8192)
    let data2 = Data(repeating: 0xBB, count: 8192)
    let src1 = tmpDir.appendingPathComponent("src1.dat")
    let src2 = tmpDir.appendingPathComponent("src2.dat")
    try data1.write(to: src1)
    try data2.write(to: src2)

    let storages1 = try await d1.storages()
    let storages2 = try await d2.storages()

    async let w1 = d1.write(parent: nil, name: "upload1.dat", size: 8192, from: src1)
    async let w2 = d2.write(parent: nil, name: "upload2.dat", size: 8192, from: src2)
    let (prog1, prog2) = try await (w1, w2)

    XCTAssertEqual(prog1.totalUnitCount, 8192)
    XCTAssertEqual(prog2.totalUnitCount, 8192)

    let ops1 = await d1.operations.filter { $0.operation == "write" }
    let ops2 = await d2.operations.filter { $0.operation == "write" }

    XCTAssertEqual(ops1.count, 1, "device 1 should have exactly 1 write")
    XCTAssertEqual(ops2.count, 1, "device 2 should have exactly 1 write")
    XCTAssertNotNil(storages1.first)
    XCTAssertNotNil(storages2.first)
  }

  /// DeviceServiceRegistry correctly routes between three registered devices.
  func testRegistryRoutesThreeDevicesIndependently() async throws {
    let (d1, c1) = makeDevice(index: 1)
    let (d2, c2) = makeDevice(index: 2)
    let (d3, c3) = makeDevice(index: 3)

    let id1 = c1.deviceId
    let id2 = c2.deviceId
    let id3 = c3.deviceId

    let registry = DeviceServiceRegistry()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.register(deviceId: id2, service: DeviceService(device: d2))
    await registry.register(deviceId: id3, service: DeviceService(device: d3))

    // Each device resolvable by its own ID
    let found1 = await registry.service(for: id1)
    let found2 = await registry.service(for: id2)
    let found3 = await registry.service(for: id3)

    XCTAssertNotNil(found1)
    XCTAssertNotNil(found2)
    XCTAssertNotNil(found3)

    // Domain mappings are independent
    await registry.registerDomainMapping(deviceId: id1, domainId: "domain-1")
    await registry.registerDomainMapping(deviceId: id2, domainId: "domain-2")
    await registry.registerDomainMapping(deviceId: id3, domainId: "domain-3")

    let resolvedId1 = await registry.deviceId(for: "domain-1")
    let resolvedId2 = await registry.deviceId(for: "domain-2")
    let resolvedId3 = await registry.deviceId(for: "domain-3")

    XCTAssertEqual(resolvedId1, id1)
    XCTAssertEqual(resolvedId2, id2)
    XCTAssertEqual(resolvedId3, id3)
  }

  /// Detach of one device does not affect the service or domain mapping of others.
  func testDetachOneDeviceKeepsOthersIntact() async throws {
    let (d1, c1) = makeDevice(index: 1)
    let (d2, c2) = makeDevice(index: 2)
    let id1 = c1.deviceId
    let id2 = c2.deviceId

    let registry = DeviceServiceRegistry()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.register(deviceId: id2, service: DeviceService(device: d2))
    await registry.registerDomainMapping(deviceId: id1, domainId: "dom-1")
    await registry.registerDomainMapping(deviceId: id2, domainId: "dom-2")

    // Simulate d1 detach
    await registry.handleDetach(deviceId: id1)

    let svc1AfterDetach = await registry.service(for: id1)
    let svc2AfterDetach = await registry.service(for: id2)

    // Registry still holds both services (cache-on-detach policy)
    XCTAssertNotNil(svc1AfterDetach, "d1 service cached on detach")
    XCTAssertNotNil(svc2AfterDetach, "d2 service unaffected")

    // d2 domain still resolves
    let dom2Device = await registry.deviceId(for: "dom-2")
    XCTAssertEqual(dom2Device, id2)
  }

  /// Folder creation on two devices in parallel creates handles only on the target device.
  func testParallelFolderCreationIsolated() async throws {
    let (d1, _) = makeDevice(index: 1)
    let (d2, _) = makeDevice(index: 2)

    let storages1 = try await d1.storages()
    let storages2 = try await d2.storages()

    let sid1 = storages1[0].id
    let sid2 = storages2[0].id

    async let h1 = d1.createFolder(parent: nil, name: "FolderA", storage: sid1)
    async let h2 = d2.createFolder(parent: nil, name: "FolderB", storage: sid2)
    let (handle1, handle2) = try await (h1, h2)

    XCTAssertGreaterThan(handle1, 0)
    XCTAssertGreaterThan(handle2, 0)

    // Folder appears on device 1 but not device 2
    let ops1 = await d1.operations.filter { $0.operation == "createFolder" }
    let ops2 = await d2.operations.filter { $0.operation == "createFolder" }

    XCTAssertEqual(ops1.count, 1, "device 1 has 1 createFolder")
    XCTAssertEqual(ops2.count, 1, "device 2 has 1 createFolder")
    XCTAssertNotEqual(handle1, handle2, "handles are independent per-device")
  }

  /// Deleting an object on device 1 does not remove anything from device 2.
  func testDeleteOnOneDeviceDoesNotAffectOther() async throws {
    let (d1, _) = makeDevice(index: 1)
    let (d2, _) = makeDevice(index: 2)

    // Both start with 1 pre-seeded object (handle 101 / 102)
    let beforeD2 = await d2.operations.count

    // Delete from d1 only
    try await d1.delete(101, recursive: false)

    let deleteOpsD1 = await d1.operations.filter { $0.operation == "delete" }
    let deleteOpsD2 = await d2.operations.filter { $0.operation == "delete" }

    XCTAssertEqual(deleteOpsD1.count, 1)
    XCTAssertEqual(deleteOpsD2.count, 0, "d2 should have 0 deletes")
    let afterD2Count = await d2.operations.count
    XCTAssertEqual(afterD2Count, beforeD2, "d2 operation count unchanged")
  }

  /// FallbackAllFailedError carries full per-rung history for multi-device diagnosis.
  func testFallbackAllFailedErrorDiagnostics() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "device-1-strategy") {
        throw MTPError.busy
      },
      FallbackRung(name: "device-2-strategy") {
        throw MTPError.timeout
      },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Should have thrown")
    } catch let e as FallbackAllFailedError {
      XCTAssertEqual(e.attempts.count, 2)
      XCTAssertEqual(e.attempts[0].name, "device-1-strategy")
      XCTAssertEqual(e.attempts[1].name, "device-2-strategy")
      XCTAssertFalse(e.attempts[0].succeeded)
      XCTAssertFalse(e.attempts[1].succeeded)
      // description should include both rung names
      XCTAssertTrue(e.description.contains("device-1-strategy"))
      XCTAssertTrue(e.description.contains("device-2-strategy"))
    }
  }
}
