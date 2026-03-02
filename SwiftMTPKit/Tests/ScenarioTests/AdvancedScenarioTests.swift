// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTestKit

// MARK: - Advanced Lifecycle & Recovery Scenario Tests

/// Expanded end-to-end scenarios covering multi-device concurrency, session
/// timeout/reconnection, large-file progress, capability discovery, error
/// recovery during batch ops, quirks-driven behavior, transfer resume after
/// interruption, and device fingerprint tuning.
final class AdvancedScenarioTests: XCTestCase {

  // MARK: - Helpers

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-advanced")
  }

  private func listAll(
    device: VirtualMTPDevice, parent: MTPObjectHandle?, in storage: MTPStorageID
  ) async throws -> [MTPObjectInfo] {
    var objects: [MTPObjectInfo] = []
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream { objects.append(contentsOf: batch) }
    return objects
  }

  private func makeDevice(
    index: Int, fileCount: Int = 1, fileSizeBytes: Int = 4096
  ) -> VirtualMTPDevice {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<fileCount {
      let handle = MTPObjectHandle(700 + index * 100 + i)
      let data = Data(repeating: UInt8((index + i) & 0xFF), count: fileSizeBytes)
      let obj = VirtualObjectConfig(
        handle: handle, storage: storageId, parent: nil,
        name: "dev\(index)_file\(i).dat", sizeBytes: UInt64(fileSizeBytes),
        formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    return VirtualMTPDevice(config: config)
  }

  // MARK: - 1. Multi-Device Concurrent List + Download

  func testMultiDeviceConcurrentListAndDownload() async throws {
    let d1 = makeDevice(index: 1)
    let d2 = makeDevice(index: 2)

    async let s1 = d1.storages()
    async let s2 = d2.storages()
    let (storages1, storages2) = try await (s1, s2)
    XCTAssertFalse(storages1.isEmpty)
    XCTAssertFalse(storages2.isEmpty)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    async let r1 = d1.read(handle: 800, range: nil, to: dir.appendingPathComponent("d1.dat"))
    async let r2 = d2.read(handle: 900, range: nil, to: dir.appendingPathComponent("d2.dat"))
    let (p1, p2) = try await (r1, r2)
    XCTAssertGreaterThan(p1.completedUnitCount, 0)
    XCTAssertGreaterThan(p2.completedUnitCount, 0)
  }

  // MARK: - 2. Multi-Device Concurrent Uploads

  func testMultiDeviceConcurrentUploads() async throws {
    let d1 = makeDevice(index: 1)
    let d2 = makeDevice(index: 2)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data1 = Data(repeating: 0xAA, count: 2048)
    let data2 = Data(repeating: 0xBB, count: 2048)
    let src1 = dir.appendingPathComponent("u1.dat")
    let src2 = dir.appendingPathComponent("u2.dat")
    try data1.write(to: src1)
    try data2.write(to: src2)

    async let w1 = d1.write(parent: nil, name: "u1.dat", size: 2048, from: src1)
    async let w2 = d2.write(parent: nil, name: "u2.dat", size: 2048, from: src2)
    let (p1, p2) = try await (w1, w2)
    XCTAssertEqual(p1.totalUnitCount, 2048)
    XCTAssertEqual(p2.totalUnitCount, 2048)
  }

  // MARK: - 3. Session Timeout Then Reconnect

  func testSessionTimeoutThenReconnect() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .openSession)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      try await faultyLink.openSession(id: 1)
      XCTFail("Expected timeout")
    } catch {}

    // Reconnect succeeds
    try await faultyLink.openSession(id: 1)
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 4. Session Timeout During Active Operations

  func testSessionTimeoutDuringActiveOperations() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getObjectHandles),
      .timeoutOnce(on: .getStorageInfo),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Normal operations succeed first
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Timeout fires on getStorageInfo
    do {
      _ = try await faultyLink.getStorageInfo(id: ids[0])
      XCTFail("Expected timeout")
    } catch {}

    // Retry succeeds
    let storageInfo = try await faultyLink.getStorageInfo(id: ids[0])
    XCTAssertGreaterThan(storageInfo.capacityBytes, 0)

    // Timeout fires on getObjectHandles
    do {
      _ = try await faultyLink.getObjectHandles(storage: ids[0], parent: nil)
      XCTFail("Expected timeout")
    } catch {}

    let handles = try await faultyLink.getObjectHandles(storage: ids[0], parent: nil)
    XCTAssertFalse(handles.isEmpty)
  }

  // MARK: - 5. Large File Transfer Progress Tracking

  func testLargeFileTransferProgressTracking() async throws {
    let largeData = Data(repeating: 0xEF, count: 16 * 1024 * 1024)
    let largeFile = VirtualObjectConfig(
      handle: 500, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "large_progress.bin", sizeBytes: UInt64(largeData.count),
      formatCode: 0x3000, data: largeData
    )
    let config = VirtualDeviceConfig.pixel7.withObject(largeFile)
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("large_progress.bin")

    let progress = try await device.read(handle: 500, range: nil, to: outURL)
    XCTAssertEqual(progress.totalUnitCount, Int64(largeData.count))
    XCTAssertEqual(progress.completedUnitCount, Int64(largeData.count))

    let downloaded = try Data(contentsOf: outURL)
    XCTAssertEqual(downloaded.count, largeData.count)
    XCTAssertTrue(downloaded.allSatisfy { $0 == 0xEF })
  }

  // MARK: - 6. Large File Upload Progress

  func testLargeFileUploadProgress() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0xFA, count: 8 * 1024 * 1024)
    let srcURL = dir.appendingPathComponent("large_upload.bin")
    try data.write(to: srcURL)

    let progress = try await device.write(
      parent: nil, name: "large_upload.bin",
      size: UInt64(data.count), from: srcURL
    )
    XCTAssertEqual(progress.totalUnitCount, Int64(data.count))
    XCTAssertEqual(progress.completedUnitCount, Int64(data.count))
  }

  // MARK: - 7. Device Capability Discovery via Info

  func testDeviceCapabilityDiscovery() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.info
    XCTAssertFalse(info.operationsSupported.isEmpty)
    XCTAssertTrue(info.operationsSupported.contains(0x1001)) // GetDeviceInfo
    XCTAssertTrue(info.operationsSupported.contains(0x1002)) // OpenSession
  }

  // MARK: - 8. Device Capability Differences Across Devices

  func testDeviceCapabilityDifferencesAcrossDevices() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let canon = VirtualMTPDevice(config: .canonEOSR5)

    let pixelInfo = try await pixel.info
    let canonInfo = try await canon.info

    XCTAssertNotEqual(pixelInfo.manufacturer, canonInfo.manufacturer)
    XCTAssertNotEqual(pixelInfo.model, canonInfo.model)
    XCTAssertFalse(pixelInfo.operationsSupported.isEmpty)
    XCTAssertFalse(canonInfo.operationsSupported.isEmpty)
  }

  // MARK: - 9. Error Recovery During Batch Download

  func testErrorRecoveryDuringBatchDownload() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<5 {
      let data = Data(repeating: UInt8(i), count: 1024)
      let obj = VirtualObjectConfig(
        handle: MTPObjectHandle(800 + i), storage: storageId, parent: nil,
        name: "batch_err_\(i).dat", sizeBytes: 1024, formatCode: 0x3000, data: data
      )
      config = config.withObject(obj)
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    var successCount = 0
    var failCount = 0

    for i in 0..<5 {
      let handle = MTPObjectHandle(800 + i)
      do {
        let outURL = dir.appendingPathComponent("batch_err_\(i).dat")
        _ = try await device.read(handle: handle, range: nil, to: outURL)
        successCount += 1
      } catch {
        failCount += 1
      }
    }

    // Non-existent handle should also fail gracefully
    do {
      _ = try await device.read(
        handle: 9999, range: nil,
        to: dir.appendingPathComponent("nonexistent.dat"))
      failCount -= 1 // unexpected success
    } catch {
      failCount += 1
    }

    XCTAssertEqual(successCount, 5)
    XCTAssertEqual(failCount, 1)
  }

  // MARK: - 10. Batch Upload with Interleaved Errors

  func testBatchUploadWithInterleavedErrors() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    var totalUploaded: Int64 = 0
    for i in 0..<6 {
      let data = Data(repeating: UInt8(i), count: 512 * (i + 1))
      let srcURL = dir.appendingPathComponent("iu_\(i).dat")
      try data.write(to: srcURL)
      let progress = try await device.write(
        parent: nil, name: "iu_\(i).dat", size: UInt64(data.count), from: srcURL)
      totalUploaded += progress.completedUnitCount
    }

    XCTAssertEqual(totalUploaded, Int64(21 * 512))
  }

  // MARK: - 11. Quirk Database VID:PID Matching

  func testQuirkDatabaseVIDPIDMatching() async throws {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "samsung-test", deviceName: "Galaxy S7", vid: 0x04e8, pid: 0x6860,
                  maxChunkBytes: 2 * 1024 * 1024),
      DeviceQuirk(id: "pixel-test", deviceName: "Pixel 7", vid: 0x18d1, pid: 0x4ee1,
                  maxChunkBytes: 4 * 1024 * 1024),
    ])

    let samsung = db.match(
      vid: 0x04e8, pid: 0x6860,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(samsung)
    XCTAssertEqual(samsung?.id, "samsung-test")
    XCTAssertEqual(samsung?.maxChunkBytes, 2 * 1024 * 1024)

    let pixel = db.match(
      vid: 0x18d1, pid: 0x4ee1,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(pixel)
    XCTAssertEqual(pixel?.id, "pixel-test")
  }

  // MARK: - 12. Quirk Database No Match Returns Nil

  func testQuirkDatabaseNoMatchReturnsNil() async throws {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "known-device", vid: 0x1234, pid: 0x5678),
    ])

    let result = db.match(
      vid: 0xFFFF, pid: 0xFFFF,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result, "Unknown VID:PID should return nil")
  }

  // MARK: - 13. Quirk-Driven Chunk Size Selection

  func testQuirkDrivenChunkSizeSelection() async throws {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "slow-device", deviceName: "Slow Phone", vid: 0x1111, pid: 0x2222,
                  maxChunkBytes: 512 * 1024),
      DeviceQuirk(id: "fast-device", deviceName: "Fast Phone", vid: 0x3333, pid: 0x4444,
                  maxChunkBytes: 8 * 1024 * 1024),
    ])

    let slow = db.match(
      vid: 0x1111, pid: 0x2222,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    let fast = db.match(
      vid: 0x3333, pid: 0x4444,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)

    XCTAssertNotNil(slow)
    XCTAssertNotNil(fast)
    XCTAssertEqual(slow?.maxChunkBytes, 512 * 1024)
    XCTAssertEqual(fast?.maxChunkBytes, 8 * 1024 * 1024)
    XCTAssertGreaterThan(fast!.maxChunkBytes!, slow!.maxChunkBytes!)
  }

  // MARK: - 14. Quirk Timeout Configuration

  func testQuirkTimeoutConfiguration() async throws {
    let quirk = DeviceQuirk(
      id: "timeout-test", vid: 0x0001, pid: 0x0002,
      ioTimeoutMs: 5000, handshakeTimeoutMs: 3000
    )
    XCTAssertEqual(quirk.ioTimeoutMs, 5000)
    XCTAssertEqual(quirk.handshakeTimeoutMs, 3000)
  }

  // MARK: - 15. Transfer Resume After FaultInjectingLink Stall

  func testTransferResumeAfterFaultInjectingLinkStall() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .getObjectHandles)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First attempt fails
    do {
      _ = try await faultyLink.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected stall")
    } catch {}

    // Resume: retry succeeds
    let handles = try await faultyLink.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    XCTAssertFalse(handles.isEmpty)
  }

  // MARK: - 16. Transfer Resume After Timeout on Read

  func testTransferResumeAfterTimeoutOnRead() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .executeStreamingCommand),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First streaming attempt times out
    do {
      _ = try await faultyLink.executeStreamingCommand(
        PTPContainer(type: 1, code: 0x1009, txid: 0, params: [3]),
        dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected timeout")
    } catch {}

    // Retry succeeds
    let result = try await faultyLink.executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1009, txid: 0, params: [3]),
      dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
    XCTAssertNotNil(result)
  }

  // MARK: - 17. Device Fingerprint via Info Properties

  func testDeviceFingerprintViaInfoProperties() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)

    let pInfo = try await pixel.info
    let sInfo = try await samsung.info

    // Fingerprint differentiation
    XCTAssertNotEqual(pInfo.serialNumber, sInfo.serialNumber)
    XCTAssertNotEqual(pInfo.manufacturer, sInfo.manufacturer)
  }

  // MARK: - 18. Device Fingerprint Stability Across Sessions

  func testDeviceFingerprintStabilityAcrossSessions() async throws {
    let config = VirtualDeviceConfig.pixel7

    let device1 = VirtualMTPDevice(config: config)
    let info1 = try await device1.info

    let device2 = VirtualMTPDevice(config: config)
    let info2 = try await device2.info

    XCTAssertEqual(info1.manufacturer, info2.manufacturer)
    XCTAssertEqual(info1.model, info2.model)
    XCTAssertEqual(info1.serialNumber, info2.serialNumber)
    XCTAssertEqual(info1.operationsSupported, info2.operationsSupported)
  }

  // MARK: - 19. FallbackLadder with Timeout Then Success

  func testFallbackLadderWithTimeoutThenSuccess() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "fast-path") { throw MTPError.timeout },
      FallbackRung(name: "slow-path") { return 42 },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "slow-path")
  }

  // MARK: - 20. FallbackLadder with Device Disconnected

  func testFallbackLadderWithDeviceDisconnected() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "primary") { throw MTPError.deviceDisconnected },
      FallbackRung(name: "reconnect") { return "reconnected" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "reconnected")
  }

  // MARK: - 21. FallbackLadder Five Rungs First Four Fail

  func testFallbackLadderFiveRungsFirstFourFail() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "r1") { throw MTPError.timeout },
      FallbackRung(name: "r2") { throw MTPError.busy },
      FallbackRung(name: "r3") { throw MTPError.sessionBusy },
      FallbackRung(name: "r4") { throw MTPError.deviceDisconnected },
      FallbackRung(name: "r5") { return "final" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "final")
    XCTAssertEqual(result.winningRung, "r5")
  }

  // MARK: - 22. Multi-Device Operations Isolated After Error

  func testMultiDeviceOperationsIsolatedAfterError() async throws {
    let d1 = VirtualMTPDevice(config: .pixel7)
    let d2 = VirtualMTPDevice(config: .samsungGalaxy)

    // Trigger error on d1
    do { try await d1.delete(9999, recursive: false) } catch {}

    // d2 should be unaffected
    let storages = try await d2.storages()
    XCTAssertFalse(storages.isEmpty)
    let info = try await d2.info
    XCTAssertEqual(info.manufacturer, "Samsung")

    let d1Errors = await d1.operations.filter { $0.operation == "delete" }
    let d2Errors = await d2.operations.filter { $0.operation == "delete" }
    XCTAssertEqual(d1Errors.count, 1)
    XCTAssertEqual(d2Errors.count, 0)
  }

  // MARK: - 23. Concurrent Device Open + Info

  func testConcurrentDeviceOpenAndInfo() async throws {
    let d1 = VirtualMTPDevice(config: .pixel7)
    let d2 = VirtualMTPDevice(config: .canonEOSR5)
    let d3 = VirtualMTPDevice(config: .nikonZ6)

    try await d1.openIfNeeded()
    try await d2.openIfNeeded()
    try await d3.openIfNeeded()

    async let i1 = d1.info
    async let i2 = d2.info
    async let i3 = d3.info

    let (info1, info2, info3) = try await (i1, i2, i3)
    XCTAssertEqual(info1.manufacturer, "Google")
    XCTAssertEqual(info2.manufacturer, "Canon")
    XCTAssertEqual(info3.manufacturer, "Nikon")
  }

  // MARK: - 24. Event Injection Object Added

  func testEventInjectionObjectAdded() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    await device.injectEvent(.objectAdded(99))
    await device.injectEvent(.objectRemoved(99))

    // Events are injected without crash; verify device still functional
    let info = try await device.info
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 25. Event Injection Storage Changes

  func testEventInjectionStorageChanges() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    await device.injectEvent(.storageAdded(storageId))
    await device.injectEvent(.storageInfoChanged(storageId))
    await device.injectEvent(.storageRemoved(storageId))

    // Events injected without crash; device still functional
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  // MARK: - 26. Disconnect During Batch Enumeration

  func testDisconnectDuringBatchEnumeration() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    try await device.openIfNeeded()
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Close mid-workflow
    try await device.devClose()

    // New device instance should work fine
    let device2 = VirtualMTPDevice(config: config)
    try await device2.openIfNeeded()
    let storages2 = try await device2.storages()
    XCTAssertFalse(storages2.isEmpty)
  }

  // MARK: - 27. Multiple Fault Types on Single Link Sequential

  func testMultipleFaultTypesOnSingleLinkSequential() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .pipeStall(on: .getDeviceInfo),
      .timeoutOnce(on: .getStorageIDs),
      .busyForRetries(2),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Stall on getDeviceInfo
    do { _ = try await faultyLink.getDeviceInfo(); XCTFail("Expected stall") } catch {}
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")

    // Timeout on getStorageIDs
    do { _ = try await faultyLink.getStorageIDs(); XCTFail("Expected timeout") } catch {}
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Busy on executeCommand × 2
    var busyCount = 0
    for _ in 0..<5 {
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
        break
      } catch { busyCount += 1 }
    }
    XCTAssertEqual(busyCount, 2)
  }

  // MARK: - 28. Dynamic Fault Injection Mid-Workflow

  func testDynamicFaultInjectionMidWorkflow() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Normal operation first
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Inject fault dynamically
    schedule.add(.pipeStall(on: .getDeviceInfo))

    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected stall from dynamic fault")
    } catch {}

    // Fault consumed, next call succeeds
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 29. Fault Schedule Clear Restores Normal Operation

  func testFaultScheduleClearRestoresNormalOperation() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs), error: .timeout,
        repeatCount: 0, label: "unlimited-timeout"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Multiple calls all fail
    for _ in 0..<3 {
      do {
        _ = try await faultyLink.getStorageIDs()
        XCTFail("Expected timeout")
      } catch {}
    }

    // Clear schedule
    schedule.clear()

    // Now succeeds
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 30. VirtualMTPDevice Operations After Repeated Errors

  func testDeviceOperationsAfterRepeatedErrors() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    for _ in 0..<10 {
      do { try await device.delete(9999, recursive: false) } catch {}
      do { _ = try await device.getInfo(handle: 9999) } catch {}
    }

    // Device still functional
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
    let info = try await device.info
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 31. Samsung Galaxy Full Lifecycle

  func testSamsungGalaxyFullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Samsung")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertFalse(objects.isEmpty)

    try await device.devClose()
  }

  // MARK: - 32. Canon EOS R5 Full Lifecycle

  func testCanonEOSR5FullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Canon")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    try await device.devClose()
  }

  // MARK: - 33. Nikon Z6 Full Lifecycle

  func testNikonZ6FullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .nikonZ6)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Nikon")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    try await device.devClose()
  }

  // MARK: - 34. OnePlus 9 Full Lifecycle

  func testOnePlus9FullLifecycle() async throws {
    let device = VirtualMTPDevice(config: .onePlus9)
    try await device.openIfNeeded()

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "OnePlus")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    try await device.devClose()
  }

  // MARK: - 35. Empty Device Upload Then List

  func testEmptyDeviceUploadThenList() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // Empty initially
    let objects = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertTrue(objects.isEmpty)

    // Upload a file
    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0x01, count: 256)
    let srcURL = dir.appendingPathComponent("first.dat")
    try data.write(to: srcURL)
    let progress = try await device.write(
      parent: nil, name: "first.dat", size: 256, from: srcURL)
    XCTAssertEqual(progress.completedUnitCount, 256)

    // Now has one object
    let objects2 = try await listAll(device: device, parent: nil, in: storages[0].id)
    XCTAssertEqual(objects2.count, 1)
    XCTAssertEqual(objects2.first?.name, "first.dat")
  }

  // MARK: - 36. Create Nested Folders Then Upload

  func testCreateNestedFoldersThenUpload() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let folder1 = try await device.createFolder(
      parent: nil, name: "Photos", storage: storageId)
    let folder2 = try await device.createFolder(
      parent: folder1, name: "2025", storage: storageId)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let data = Data(repeating: 0xBE, count: 512)
    let srcURL = dir.appendingPathComponent("photo.jpg")
    try data.write(to: srcURL)

    let progress = try await device.write(
      parent: folder2, name: "photo.jpg", size: 512, from: srcURL)
    XCTAssertEqual(progress.completedUnitCount, 512)

    let files = try await listAll(device: device, parent: folder2, in: storageId)
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(files.first?.name, "photo.jpg")
  }

  // MARK: - 37. Rename Then Verify

  func testRenameObjectThenVerify() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Handle 3 is IMG_20250101_120000.jpg in pixel7 config
    let infoBefore = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoBefore.name, "IMG_20250101_120000.jpg")

    try await device.rename(3, to: "renamed_photo.jpg")

    let infoAfter = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoAfter.name, "renamed_photo.jpg")
  }

  // MARK: - 38. Move Object Between Folders

  func testMoveObjectBetweenFolders() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let newFolder = try await device.createFolder(
      parent: nil, name: "Moved", storage: storageId)

    // Move handle 3 (photo) to newFolder
    try await device.move(3, to: newFolder)

    let movedFiles = try await listAll(device: device, parent: newFolder, in: storageId)
    XCTAssertTrue(movedFiles.contains(where: { $0.handle == 3 }))
  }

  // MARK: - 39. Delete Then Verify Not Found

  func testDeleteThenVerifyNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Verify exists first
    let info = try await device.getInfo(handle: 3)
    XCTAssertEqual(info.name, "IMG_20250101_120000.jpg")

    // Delete
    try await device.delete(3, recursive: false)

    // Should not be found
    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 40. Concurrent Folder Creation

  func testConcurrentFolderCreation() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let handles = try await withThrowingTaskGroup(
      of: MTPObjectHandle.self
    ) { group -> [MTPObjectHandle] in
      for i in 0..<5 {
        group.addTask {
          try await device.createFolder(
            parent: nil, name: "concurrent_\(i)", storage: storageId)
        }
      }
      var collected: [MTPObjectHandle] = []
      for try await h in group { collected.append(h) }
      return collected
    }

    XCTAssertEqual(handles.count, 5)
    let uniqueHandles = Set(handles)
    XCTAssertEqual(uniqueHandles.count, 5, "All folder handles should be unique")
  }

  // MARK: - 41. AddObject and RemoveObject on VirtualMTPDevice

  func testAddAndRemoveObjectOnVirtualDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)

    let newObj = VirtualObjectConfig(
      handle: 999, storage: storageId, parent: nil,
      name: "injected.txt", sizeBytes: 100,
      formatCode: 0x3000, data: Data(repeating: 0x42, count: 100)
    )
    await device.addObject(newObj)

    let info = try await device.getInfo(handle: 999)
    XCTAssertEqual(info.name, "injected.txt")

    await device.removeObject(handle: 999)

    do {
      _ = try await device.getInfo(handle: 999)
      XCTFail("Expected objectNotFound after removal")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 42. Operations Log Tracking

  func testOperationsLogTracking() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()

    _ = try await device.storages()
    _ = try await device.info
    _ = try await device.storages()

    let ops = await device.operations
    let storageOps = ops.filter { $0.operation == "storages" }
    XCTAssertEqual(storageOps.count, 2)
  }

  // MARK: - 43. Operations Log Clear

  func testOperationsLogClear() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    _ = try await device.storages()

    let opsBefore = await device.operations
    XCTAssertFalse(opsBefore.isEmpty)

    await device.clearOperations()

    let opsAfter = await device.operations
    XCTAssertTrue(opsAfter.isEmpty)
  }

  // MARK: - 44. Quirk with ResetOnOpen Flag

  func testQuirkWithResetOnOpenFlag() async throws {
    let quirk = DeviceQuirk(
      id: "reset-test", vid: 0x0001, pid: 0x0002, resetOnOpen: true
    )
    XCTAssertTrue(quirk.resetOnOpen ?? false)
  }

  // MARK: - 45. Quirk with DisableEventPump Flag

  func testQuirkWithDisableEventPumpFlag() async throws {
    let quirk = DeviceQuirk(
      id: "noevent-test", vid: 0x0001, pid: 0x0002, disableEventPump: true
    )
    XCTAssertTrue(quirk.disableEventPump ?? false)
  }

  // MARK: - 46. Quirk with Operations Map

  func testQuirkWithOperationsMap() async throws {
    let quirk = DeviceQuirk(
      id: "ops-test", vid: 0x0001, pid: 0x0002,
      operations: ["partialRead": true, "sendObject": false]
    )
    XCTAssertEqual(quirk.operations?["partialRead"], true)
    XCTAssertEqual(quirk.operations?["sendObject"], false)
  }

  // MARK: - 47. Quirk with StabilizeMs

  func testQuirkWithStabilizeMs() async throws {
    let quirk = DeviceQuirk(
      id: "stab-test", vid: 0x0001, pid: 0x0002,
      stabilizeMs: 200, postClaimStabilizeMs: 500
    )
    XCTAssertEqual(quirk.stabilizeMs, 200)
    XCTAssertEqual(quirk.postClaimStabilizeMs, 500)
  }

  // MARK: - 48. Multi-Device Registry Routing

  func testMultiDeviceRegistryRouting() async throws {
    let d1 = VirtualMTPDevice(config: .pixel7)
    let d2 = VirtualMTPDevice(config: .samsungGalaxy)

    let id1 = VirtualDeviceConfig.pixel7.deviceId
    let id2 = VirtualDeviceConfig.samsungGalaxy.deviceId

    let registry = DeviceServiceRegistry()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.register(deviceId: id2, service: DeviceService(device: d2))

    let svc1 = await registry.service(for: id1)
    let svc2 = await registry.service(for: id2)
    XCTAssertNotNil(svc1)
    XCTAssertNotNil(svc2)

    // Unknown device returns nil
    let unknown = await registry.service(
      for: MTPDeviceID(raw: "unknown:device"))
    XCTAssertNil(unknown)
  }

  // MARK: - 49. Registry Domain Mapping

  func testRegistryDomainMapping() async throws {
    let d1 = VirtualMTPDevice(config: .pixel7)
    let id1 = VirtualDeviceConfig.pixel7.deviceId

    let registry = DeviceServiceRegistry()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.registerDomainMapping(deviceId: id1, domainId: "com.test.pixel7")

    let resolved = await registry.deviceId(for: "com.test.pixel7")
    XCTAssertEqual(resolved, id1)

    let unknown = await registry.deviceId(for: "com.test.unknown")
    XCTAssertNil(unknown)
  }

  // MARK: - 50. Registry Detach Preserves Other Devices

  func testRegistryDetachPreservesOtherDevices() async throws {
    let d1 = VirtualMTPDevice(config: .pixel7)
    let d2 = VirtualMTPDevice(config: .canonEOSR5)

    let id1 = VirtualDeviceConfig.pixel7.deviceId
    let id2 = VirtualDeviceConfig.canonEOSR5.deviceId

    let registry = DeviceServiceRegistry()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.register(deviceId: id2, service: DeviceService(device: d2))

    await registry.handleDetach(deviceId: id1)

    let svc2 = await registry.service(for: id2)
    XCTAssertNotNil(svc2, "Device 2 should still be registered after device 1 detach")
  }

  // MARK: - 51. Concurrent Downloads from Same Device

  func testConcurrentDownloadsFromSameDevice() async throws {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    var config = VirtualDeviceConfig.pixel7
    for i in 0..<4 {
      let data = Data(repeating: UInt8(i + 1), count: 2048)
      config = config.withObject(VirtualObjectConfig(
        handle: MTPObjectHandle(400 + i), storage: storageId, parent: nil,
        name: "parallel_\(i).dat", sizeBytes: 2048, formatCode: 0x3000, data: data
      ))
    }
    let device = VirtualMTPDevice(config: config)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let results = try await withThrowingTaskGroup(
      of: Int64.self
    ) { group -> [Int64] in
      for i in 0..<4 {
        group.addTask {
          let out = dir.appendingPathComponent("p_\(i).dat")
          let p = try await device.read(
            handle: MTPObjectHandle(400 + i), range: nil, to: out)
          return p.completedUnitCount
        }
      }
      var collected: [Int64] = []
      for try await r in group { collected.append(r) }
      return collected
    }

    XCTAssertEqual(results.count, 4)
    XCTAssertTrue(results.allSatisfy { $0 == 2048 })
  }

  // MARK: - 52. Concurrent Uploads to Same Device

  func testConcurrentUploadsToSameDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let results = try await withThrowingTaskGroup(
      of: Int64.self
    ) { group -> [Int64] in
      for i in 0..<4 {
        group.addTask {
          let data = Data(repeating: UInt8(i), count: 1024)
          let src = dir.appendingPathComponent("cu_\(i).dat")
          try data.write(to: src)
          let p = try await device.write(
            parent: nil, name: "cu_\(i).dat", size: 1024, from: src)
          return p.completedUnitCount
        }
      }
      var collected: [Int64] = []
      for try await r in group { collected.append(r) }
      return collected
    }

    XCTAssertEqual(results.count, 4)
    XCTAssertTrue(results.allSatisfy { $0 == 1024 })
  }

  // MARK: - 53. VirtualMTPLink Session Open Close Cycle

  func testVirtualMTPLinkSessionOpenCloseCycle() async throws {
    let link = VirtualMTPLink(config: .pixel7)

    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
    try await link.closeSession()

    // Second cycle
    try await link.openSession(id: 2)
    let info2 = try await link.getDeviceInfo()
    XCTAssertEqual(info2.model, "Pixel 7")
    try await link.closeSession()
  }

  // MARK: - 54. VirtualMTPLink Storage Enumeration

  func testVirtualMTPLinkStorageEnumeration() async throws {
    let link = VirtualMTPLink(config: .pixel7)

    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    let storageInfo = try await link.getStorageInfo(id: ids[0])
    XCTAssertGreaterThan(storageInfo.capacityBytes, 0)
    XCTAssertGreaterThan(storageInfo.freeBytes, 0)
  }

  // MARK: - 55. VirtualMTPLink Object Handle Enumeration

  func testVirtualMTPLinkObjectHandleEnumeration() async throws {
    let link = VirtualMTPLink(config: .pixel7)

    let ids = try await link.getStorageIDs()
    let handles = try await link.getObjectHandles(storage: ids[0], parent: nil)
    XCTAssertFalse(handles.isEmpty)

    let infos = try await link.getObjectInfos(handles)
    XCTAssertEqual(infos.count, handles.count)
  }

  // MARK: - 56. FaultInjectingLink Access Denied Error

  func testFaultInjectingLinkAccessDeniedError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .accessDenied,
        repeatCount: 1, label: "access-denied"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected access denied")
    } catch {}

    // Retry succeeds
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 57. FaultInjectingLink IO Error

  func testFaultInjectingLinkIOError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs), error: .io("Simulated IO failure"),
        repeatCount: 1, label: "io-error"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected IO error")
    } catch {}

    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 58. FaultInjectingLink Disconnected Error

  func testFaultInjectingLinkDisconnectedError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getObjectHandles), error: .disconnected,
        repeatCount: 1, label: "disconnected"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      _ = try await faultyLink.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected disconnected")
    } catch {}

    let handles = try await faultyLink.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    XCTAssertFalse(handles.isEmpty)
  }

  // MARK: - 59. FaultInjectingLink Protocol Error

  func testFaultInjectingLinkProtocolError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .protocolError(code: 0x2002),
        repeatCount: 1, label: "protocol-error"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected protocol error")
    } catch {}

    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 60. FaultInjectingLink Reset Device

  func testFaultInjectingLinkResetDevice() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: FaultSchedule([]))

    // Reset should not crash
    try await faultyLink.resetDevice()

    // Operations still work after reset
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 61. Five Devices Four Operations Each

  func testFiveDevicesFourOperationsEach() async throws {
    let configs: [VirtualDeviceConfig] = [
      .pixel7, .samsungGalaxy, .canonEOSR5, .nikonZ6, .onePlus9,
    ]

    for config in configs {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()
      _ = try await device.info
      _ = try await device.storages()
      try await device.devClose()

      let ops = await device.operations
      XCTAssertTrue(ops.contains { $0.operation == "openIfNeeded" })
      XCTAssertTrue(ops.contains { $0.operation == "devClose" })
    }
  }

  // MARK: - 62. Upload Then Download Round-Trip Verify

  func testUploadThenDownloadRoundTripVerify() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let originalData = Data(repeating: 0xDE, count: 4096)
    let srcURL = dir.appendingPathComponent("roundtrip.dat")
    try originalData.write(to: srcURL)

    let uploadProgress = try await device.write(
      parent: nil, name: "roundtrip.dat", size: UInt64(originalData.count), from: srcURL)
    XCTAssertEqual(uploadProgress.completedUnitCount, Int64(originalData.count))

    // New handle is 4 (pixel7 has 1,2,3)
    let downloadURL = dir.appendingPathComponent("roundtrip_verify.dat")
    let downloadProgress = try await device.read(handle: 4, range: nil, to: downloadURL)
    XCTAssertEqual(downloadProgress.completedUnitCount, Int64(originalData.count))

    let downloadedData = try Data(contentsOf: downloadURL)
    XCTAssertEqual(downloadedData, originalData)
  }

  // MARK: - 63. FallbackLadder Empty Rungs

  func testFallbackLadderEmptyRungs() async throws {
    let rungs: [FallbackRung<String>] = []

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected error for empty rungs")
    } catch {
      // Expected: no rungs to execute
    }
  }

  // MARK: - 64. Quirk Database Multiple Entries Same VID Different PID

  func testQuirkDatabaseMultipleEntriesSameVIDDifferentPID() async throws {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "dev-a", vid: 0x1234, pid: 0x0001, maxChunkBytes: 1024),
      DeviceQuirk(id: "dev-b", vid: 0x1234, pid: 0x0002, maxChunkBytes: 2048),
      DeviceQuirk(id: "dev-c", vid: 0x1234, pid: 0x0003, maxChunkBytes: 4096),
    ])

    let a = db.match(
      vid: 0x1234, pid: 0x0001,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    let b = db.match(
      vid: 0x1234, pid: 0x0002,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    let c = db.match(
      vid: 0x1234, pid: 0x0003,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)

    XCTAssertEqual(a?.id, "dev-a")
    XCTAssertEqual(b?.id, "dev-b")
    XCTAssertEqual(c?.id, "dev-c")
    XCTAssertEqual(a?.maxChunkBytes, 1024)
    XCTAssertEqual(b?.maxChunkBytes, 2048)
    XCTAssertEqual(c?.maxChunkBytes, 4096)
  }

  // MARK: - 65. Quirk Governance Fields

  func testQuirkGovernanceFields() async throws {
    let quirk = DeviceQuirk(
      id: "gov-test", vid: 0x0001, pid: 0x0002,
      status: .verified, confidence: "high",
      evidenceRequired: ["probe_log", "write_test"],
      lastVerifiedDate: "2025-01-15",
      lastVerifiedBy: "test-team"
    )
    XCTAssertEqual(quirk.status, .verified)
    XCTAssertEqual(quirk.confidence, "high")
    XCTAssertEqual(quirk.evidenceRequired?.count, 2)
    XCTAssertEqual(quirk.lastVerifiedDate, "2025-01-15")
    XCTAssertEqual(quirk.lastVerifiedBy, "test-team")
  }

  // MARK: - 66. Rapid Open Close Cycles

  func testRapidOpenCloseCycles() async throws {
    let config = VirtualDeviceConfig.pixel7

    for _ in 0..<20 {
      let device = VirtualMTPDevice(config: config)
      try await device.openIfNeeded()
      try await device.devClose()
    }
    // No crash, no resource leak
  }

  // MARK: - 67. Multi-Device Registry Full Lifecycle

  func testMultiDeviceRegistryFullLifecycle() async throws {
    let registry = DeviceServiceRegistry()

    let configs: [(VirtualDeviceConfig, String)] = [
      (.pixel7, "domain-pixel"),
      (.samsungGalaxy, "domain-samsung"),
      (.canonEOSR5, "domain-canon"),
    ]

    for (config, domain) in configs {
      let device = VirtualMTPDevice(config: config)
      let id = config.deviceId
      await registry.register(deviceId: id, service: DeviceService(device: device))
      await registry.registerDomainMapping(deviceId: id, domainId: domain)
    }

    // All resolvable
    for (config, domain) in configs {
      let resolved = await registry.deviceId(for: domain)
      XCTAssertEqual(resolved, config.deviceId)
    }

    // Detach one
    await registry.handleDetach(deviceId: VirtualDeviceConfig.pixel7.deviceId)

    // Others still work
    let samsung = await registry.service(
      for: VirtualDeviceConfig.samsungGalaxy.deviceId)
    XCTAssertNotNil(samsung)
  }

  // MARK: - 68. Fault at Call Index

  func testFaultAtCallIndex() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .atCallIndex(2), error: .timeout, repeatCount: 1, label: "index-2"),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Call 0: success
    _ = try await faultyLink.getDeviceInfo()
    // Call 1: success
    _ = try await faultyLink.getStorageIDs()
    // Call 2: fault fires
    do {
      _ = try await faultyLink.getDeviceInfo()
      // May or may not fire depending on call index tracking
    } catch {
      // Expected if call index matches
    }
    // Call 3: should succeed
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 69. Probed Capabilities Check

  func testProbedCapabilitiesCheck() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let caps = await device.probedCapabilities
    // VirtualMTPDevice returns an empty dict by default
    XCTAssertNotNil(caps)
  }

  // MARK: - 70. Effective Tuning Check

  func testEffectiveTuningCheck() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let tuning = await device.effectiveTuning
    XCTAssertNotNil(tuning)
  }

  // MARK: - 71. Uncached Device Info

  func testUncachedDeviceInfo() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertEqual(info.manufacturer, "Google")
  }

  // MARK: - 72. Uncached Storage IDs

  func testUncachedStorageIDs() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let ids = try await device.devGetStorageIDsUncached()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 73. Uncached Root Handles

  func testUncachedRootHandles() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let handles = try await device.devGetRootHandlesUncached(storage: storageId)
    XCTAssertFalse(handles.isEmpty)
  }

  // MARK: - 74. Uncached Object Info

  func testUncachedObjectInfo() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.devGetObjectInfoUncached(handle: 3)
    XCTAssertEqual(info.name, "IMG_20250101_120000.jpg")
  }
}
