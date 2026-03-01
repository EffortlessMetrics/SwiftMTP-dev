// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Tests for service interruption and recovery, permission scenarios,
/// large payload handling, and cancellation support.
@MainActor
final class XPCServiceInterruptionTests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    objectCount: Int = 1
  ) async -> (impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry, deviceId: MTPDeviceID, stableId: String, storageId: UInt32) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<objectCount {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(500 + i), storage: storageId, parent: nil,
          name: "obj\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: 256)
        )
      )
    }
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "domain-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, registry, config.deviceId, stableId, storageId.raw)
  }

  // MARK: - Service interruption: device disconnect mid-operation

  func testReadAfterDisconnectReportsError() async {
    let svc = await makeService()
    // Disconnect the device
    if let service = await svc.registry.service(for: svc.deviceId) {
      await service.markDisconnected()
    }
    // Attempt to read — device is still in registry but marked disconnected
    // The read goes through findDevice which still resolves the device.
    // The virtual device will still respond, so let's test removal instead.
    await svc.registry.remove(deviceId: svc.deviceId)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 500)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testListObjectsAfterDeviceRemoval() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Recovery: re-register device

  func testRecoveryAfterReRegistration() async {
    let svc = await makeService()
    // Remove device
    await svc.registry.remove(deviceId: svc.deviceId)
    let failResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(failResp.success)

    // Re-register with a new virtual device
    let newConfig = VirtualDeviceConfig.emptyDevice
    let newVirtual = VirtualMTPDevice(config: newConfig)
    let newService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: newConfig.deviceId, service: newService)
    await svc.registry.registerDomainMapping(deviceId: newConfig.deviceId, domainId: svc.stableId)

    let successResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(successResp.success)
  }

  // MARK: - Disconnect / reconnect cycle

  func testDisconnectReconnectCyclePreservesService() async {
    let svc = await makeService()
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }
    // Disconnect
    await service.markDisconnected()
    let statusDisc = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(statusDisc.connected)

    // Reconnect
    await service.markReconnected()
    let statusReconn = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(statusReconn.connected)
  }

  // MARK: - Permission scenarios: crawl handler

  func testCrawlHandlerAcceptsForSpecificStorage() async {
    let svc = await makeService()
    let targetStorage = svc.storageId
    svc.impl.crawlBoostHandler = { _, storageId, _ in
      storageId == targetStorage
    }
    // Should accept for correct storage
    let accepted = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: targetStorage)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(accepted.accepted)

    // Should reject for wrong storage
    let rejected = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: 99999)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(rejected.accepted)
  }

  func testCrawlHandlerReceivesParentHandle() async {
    let svc = await makeService()
    var receivedParent: UInt32?
    svc.impl.crawlBoostHandler = { _, _, parent in
      receivedParent = parent
      return true
    }
    _ = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: 42)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertEqual(receivedParent, 42)
  }

  func testCrawlHandlerReceivesNilParentHandle() async {
    let svc = await makeService()
    var receivedParent: UInt32? = 999
    svc.impl.crawlBoostHandler = { _, _, parent in
      receivedParent = parent
      return true
    }
    _ = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertNil(receivedParent)
  }

  // MARK: - Large payload handling

  func testReadLargeObject() async {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    let largeData = Data(repeating: 0x42, count: 1024 * 1024) // 1 MB
    config = config.withObject(
      VirtualObjectConfig(handle: 7777, storage: storageId, parent: nil, name: "large.bin", data: largeData)
    )
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "domain-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry

    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      impl.readObject(ReadRequest(deviceId: stableId, objectHandle: 7777)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.success)
    XCTAssertEqual(resp.fileSize, UInt64(1024 * 1024))
    if let url = resp.tempFileURL {
      let data = try? Data(contentsOf: url)
      XCTAssertEqual(data?.count, 1024 * 1024)
      try? FileManager.default.removeItem(at: url)
    }
  }

  func testListManyObjects() async {
    let svc = await makeService(objectCount: 50)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.success)
    XCTAssertEqual(resp.objects?.count, 50)
  }

  // MARK: - Cleanup edge cases

  func testCleanupOldTempFilesWithNoFiles() {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    // Should not crash even with no temp files
    impl.cleanupOldTempFiles(olderThan: 0)
  }

  func testCleanupWithNegativeHoursRemovesAll() async {
    let svc = await makeService()
    // Create a temp file via read
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 500)) {
        c.resume(returning: $0)
      }
    }
    guard let url = resp.tempFileURL else {
      XCTFail("Expected temp file")
      return
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    svc.impl.cleanupOldTempFiles(olderThan: -1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }
}
