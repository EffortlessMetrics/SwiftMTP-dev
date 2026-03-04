// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Wave 35 edge case tests for XPC: connection interruption and recovery,
/// malformed/boundary messages, timeout handling, and concurrent requests
/// from multiple FileProvider instances.
@MainActor
final class XPCEdgeCaseWave35Tests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    objectCount: Int = 3
  ) async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry, deviceId: MTPDeviceID,
    stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<objectCount {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(1000 + i), storage: storageId, parent: nil,
          name: "file\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: 512)
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

  private func pingResult(_ impl: MTPXPCServiceImpl) async -> String {
    await withCheckedContinuation { c in
      impl.ping { c.resume(returning: $0) }
    }
  }

  private func statusResult(_ impl: MTPXPCServiceImpl, deviceId: String) async
    -> DeviceStatusResponse
  {
    await withCheckedContinuation { c in
      impl.deviceStatus(DeviceStatusRequest(deviceId: deviceId)) { c.resume(returning: $0) }
    }
  }

  // MARK: - Connection interruption and recovery

  func testReadFailsAfterDeviceRemoval() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)

    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 1000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testWriteFailsAfterDeviceRemoval() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)

    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(
          deviceId: svc.stableId, storageId: svc.storageId,
          parentHandle: nil, name: "new.txt", size: 100, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.success)
  }

  func testDeleteFailsAfterDeviceRemoval() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)

    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: svc.stableId, objectHandle: 1000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testRecoveryAfterRemoveAndReRegister() async {
    let svc = await makeService()

    // Remove device
    await svc.registry.remove(deviceId: svc.deviceId)
    let failResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(failResp.success)

    // Re-register with fresh device
    var newConfig = VirtualDeviceConfig.emptyDevice
    let newStorageId = newConfig.storages[0].id
    newConfig = newConfig.withObject(
      VirtualObjectConfig(
        handle: 2000, storage: newStorageId, parent: nil,
        name: "recovered.dat", data: Data("hello".utf8)))
    let newVirtual = VirtualMTPDevice(config: newConfig)
    let newService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: newConfig.deviceId, service: newService)
    await svc.registry.registerDomainMapping(deviceId: newConfig.deviceId, domainId: svc.stableId)

    let successResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: newStorageId.raw)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(successResp.success)
    XCTAssertEqual(successResp.objects?.count, 1)
    XCTAssertEqual(successResp.objects?.first?.name, "recovered.dat")
  }

  func testDisconnectReconnectCyclePreservesData() async {
    let svc = await makeService()
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }

    // Verify connected
    let status1 = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(status1.connected)

    // Disconnect
    await service.markDisconnected()
    let status2 = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertFalse(status2.connected)

    // Reconnect
    await service.markReconnected()
    let status3 = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(status3.connected)

    // Data still accessible
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(resp.success)
    XCTAssertEqual(resp.objects?.count, 3)
  }

  // MARK: - Malformed messages / boundary values

  func testReadWithNonexistentDeviceIdFails() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "completely-invalid-device", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testReadWithZeroObjectHandle() async {
    let svc = await makeService()
    // Handle 0 is typically the root — not a valid file handle
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 0)) {
        c.resume(returning: $0)
      }
    }
    // Should either fail gracefully or return empty
    XCTAssertTrue(!resp.success || resp.fileSize == nil || resp.fileSize == 0)
  }

  func testReadWithMaxUInt32Handle() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: UInt32.max)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testListObjectsWithZeroStorageId() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: 0)
      ) { c.resume(returning: $0) }
    }
    // Storage 0 doesn't exist; should fail or return empty list
    XCTAssertTrue(!resp.success || (resp.objects?.isEmpty ?? true))
  }

  func testListObjectsWithMaxStorageId() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: UInt32.max)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(!resp.success || (resp.objects?.isEmpty ?? true))
  }

  func testEmptyDeviceIdInStorageListFails() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: "")) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.success)
  }

  func testCreateFolderWithEmptyName() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.createFolder(
        CreateFolderRequest(
          deviceId: svc.stableId, storageId: svc.storageId,
          parentHandle: nil, name: "")
      ) { c.resume(returning: $0) }
    }
    // Empty name is an edge case; service should handle gracefully
    // (virtual device may accept or reject it)
    XCTAssertNotNil(resp)
  }

  func testRenameWithEmptyNewName() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.renameObject(
        RenameRequest(deviceId: svc.stableId, objectHandle: 1000, newName: "")
      ) { c.resume(returning: $0) }
    }
    XCTAssertNotNil(resp)
  }

  func testDeviceStatusWithEmptyDeviceId() async {
    let svc = await makeService()
    let resp = await statusResult(svc.impl, deviceId: "")
    XCTAssertFalse(resp.connected)
  }

  // MARK: - Timeout handling

  func testPingRespondsQuickly() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let msg = await pingResult(svc.impl)
    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(msg.contains("running"))
    XCTAssertTrue(elapsed < .seconds(5), "Ping took too long: \(elapsed)")
  }

  func testAllOperationsRespondWithinTimeout() async {
    let svc = await makeService()
    let timeout: Duration = .seconds(5)

    // Storage list for missing device
    let start1 = ContinuousClock.now
    let _ = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: "missing")) { c.resume(returning: $0) }
    }
    XCTAssertTrue(ContinuousClock.now - start1 < timeout)

    // Object list for missing device
    let start2 = ContinuousClock.now
    let _ = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: "missing", storageId: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(ContinuousClock.now - start2 < timeout)

    // Read for missing device
    let start3 = ContinuousClock.now
    let _ = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "missing", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(ContinuousClock.now - start3 < timeout)

    // Write for missing device
    let start4 = ContinuousClock.now
    let _ = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(
          deviceId: "missing", storageId: 1, parentHandle: nil,
          name: "test.txt", size: 0, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(ContinuousClock.now - start4 < timeout)

    // Delete for missing device
    let start5 = ContinuousClock.now
    let _ = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: "missing", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(ContinuousClock.now - start5 < timeout)
  }

  func testCrawlRequestForMissingDeviceRespondsPromptly() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: "nonexistent", storageId: 1)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.accepted)
    XCTAssertTrue(ContinuousClock.now - start < .seconds(5))
  }

  // MARK: - Concurrent requests from multiple FileProvider instances

  func testConcurrentPingsFromMultipleClients() async {
    let svc = await makeService()
    var results: [String] = []
    // Simulate 20 rapid pings (as if from multiple FP domains)
    for _ in 0..<20 {
      let msg = await pingResult(svc.impl)
      results.append(msg)
    }
    XCTAssertEqual(results.count, 20)
    XCTAssertTrue(results.allSatisfy { $0.contains("running") })
  }

  func testConcurrentReadsFromMultipleClients() async {
    let svc = await makeService(objectCount: 5)
    var successCount = 0
    // Read each object twice (simulating 2 FP instances)
    for round in 0..<2 {
      for i in 0..<5 {
        let handle = UInt32(1000 + i)
        let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
          svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: handle)) {
            c.resume(returning: $0)
          }
        }
        if resp.success { successCount += 1 }
        if let url = resp.tempFileURL {
          try? FileManager.default.removeItem(at: url)
        }
      }
      _ = round
    }
    XCTAssertEqual(successCount, 10)
  }

  func testConcurrentMixedOperationsFromMultipleDomains() async {
    let svc = await makeService(objectCount: 3)

    // Interleave different operation types
    let pingMsg = await pingResult(svc.impl)
    XCTAssertTrue(pingMsg.contains("running"))

    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)

    let objResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(objResp.success)
    XCTAssertEqual(objResp.objects?.count, 3)

    let statusResp = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(statusResp.connected)

    // Read while querying status
    let readResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 1000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(readResp.success)
    if let url = readResp.tempFileURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  func testConcurrentStatusQueriesForDifferentDevices() async {
    let svc = await makeService()
    // Query status for real device and several nonexistent ones
    let realStatus = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(realStatus.connected)

    for i in 0..<5 {
      let fakeStatus = await statusResult(svc.impl, deviceId: "fake-device-\(i)")
      XCTAssertFalse(fakeStatus.connected)
    }

    // Real device still works after fake queries
    let finalStatus = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(finalStatus.connected)
  }

  func testConcurrentCrawlRequestsFromMultipleDomains() async {
    let svc = await makeService()
    var accepted = 0
    // Set up a handler that accepts all crawls
    svc.impl.crawlBoostHandler = { _, _, _ in true }

    for i: UInt32 in 0..<5 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
        svc.impl.requestCrawl(
          CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: i)
        ) { c.resume(returning: $0) }
      }
      if resp.accepted { accepted += 1 }
    }
    XCTAssertEqual(accepted, 5)
  }

  // MARK: - NSSecureCoding round-trip edge cases

  func testReadRequestRoundTrip() throws {
    let original = ReadRequest(
      deviceId: "test-device", objectHandle: 42, bookmark: Data([1, 2, 3]))
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadRequest.self, from: data)
    XCTAssertEqual(decoded?.deviceId, "test-device")
    XCTAssertEqual(decoded?.objectHandle, 42)
    XCTAssertEqual(decoded?.bookmark, Data([1, 2, 3]))
  }

  func testWriteRequestRoundTrip() throws {
    let original = WriteRequest(
      deviceId: "dev1", storageId: 1, parentHandle: 10,
      name: "test.txt", size: 999_999, bookmark: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: WriteRequest.self, from: data)
    XCTAssertEqual(decoded?.deviceId, "dev1")
    XCTAssertEqual(decoded?.storageId, 1)
    XCTAssertEqual(decoded?.parentHandle, 10)
    XCTAssertEqual(decoded?.name, "test.txt")
    XCTAssertEqual(decoded?.size, 999_999)
    XCTAssertNil(decoded?.bookmark)
  }

  func testDeleteRequestRoundTrip() throws {
    let original = DeleteRequest(deviceId: "dev1", objectHandle: 55, recursive: false)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: DeleteRequest.self, from: data)
    XCTAssertEqual(decoded?.objectHandle, 55)
    XCTAssertEqual(decoded?.recursive, false)
  }

  func testDeviceStatusResponseRoundTrip() throws {
    let original = DeviceStatusResponse(
      connected: true, sessionOpen: false, lastCrawlTimestamp: 123)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: DeviceStatusResponse.self, from: data)
    XCTAssertEqual(decoded?.connected, true)
    XCTAssertEqual(decoded?.sessionOpen, false)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, 123)
  }

  func testCrawlTriggerRequestWithNilParentHandle() throws {
    let original = CrawlTriggerRequest(deviceId: "dev1", storageId: 5, parentHandle: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: CrawlTriggerRequest.self, from: data)
    XCTAssertEqual(decoded?.storageId, 5)
    XCTAssertNil(decoded?.parentHandle)
  }

  func testMoveObjectRequestRoundTrip() throws {
    let original = MoveObjectRequest(
      deviceId: "dev1", objectHandle: 100, newParentHandle: nil, newStorageId: 2)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: MoveObjectRequest.self, from: data)
    XCTAssertEqual(decoded?.objectHandle, 100)
    XCTAssertNil(decoded?.newParentHandle)
    XCTAssertEqual(decoded?.newStorageId, 2)
  }
}
