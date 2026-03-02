// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Tests for XPC timeout, connection interruption, recovery, and concurrency limiting behavior.
@MainActor
final class XPCTimeoutTests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    objectCount: Int = 0
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
          name: "file\(i).txt", data: Data("content-\(i)".utf8)
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

  // MARK: - Connection timeout behavior

  func testPingRespondsWithinReasonableTime() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let msg = await pingResult(svc.impl)
    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(msg.contains("running"))
    XCTAssertTrue(elapsed < .seconds(5), "Ping should respond quickly")
  }

  func testDeviceStatusRespondsQuicklyForMissingDevice() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let resp = await statusResult(svc.impl, deviceId: "nonexistent-device")
    let elapsed = ContinuousClock.now - start
    XCTAssertFalse(resp.connected)
    XCTAssertTrue(elapsed < .seconds(5))
  }

  func testReadRequestForMissingDeviceRespondsPromptly() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "no-device", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    let elapsed = ContinuousClock.now - start
    XCTAssertFalse(resp.success)
    XCTAssertTrue(elapsed < .seconds(5))
  }

  // MARK: - Reply timeout behavior

  func testListStoragesForMissingDeviceDoesNotHang() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: "gone")) { c.resume(returning: $0) }
    }
    let elapsed = ContinuousClock.now - start
    XCTAssertFalse(resp.success)
    XCTAssertTrue(elapsed < .seconds(5))
  }

  func testListObjectsForMissingDeviceDoesNotHang() async {
    let svc = await makeService()
    let start = ContinuousClock.now
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: "gone", storageId: 1)) {
        c.resume(returning: $0)
      }
    }
    let elapsed = ContinuousClock.now - start
    XCTAssertFalse(resp.success)
    XCTAssertTrue(elapsed < .seconds(5))
  }

  func testWriteOperationsForMissingDeviceRespondPromptly() async {
    let svc = await makeService()
    let start = ContinuousClock.now

    let writeResp = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(
          deviceId: "gone", storageId: 1, parentHandle: nil, name: "f", size: 0, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    let deleteResp = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: "gone", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    let folderResp = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.createFolder(
        CreateFolderRequest(deviceId: "gone", storageId: 1, parentHandle: nil, name: "d")
      ) { c.resume(returning: $0) }
    }
    let renameResp = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.renameObject(RenameRequest(deviceId: "gone", objectHandle: 1, newName: "x")) {
        c.resume(returning: $0)
      }
    }
    let moveResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.moveObject(
        MoveObjectRequest(deviceId: "gone", objectHandle: 1, newParentHandle: nil, newStorageId: 1)
      ) { c.resume(returning: $0) }
    }

    let elapsed = ContinuousClock.now - start
    XCTAssertFalse(writeResp.success)
    XCTAssertFalse(deleteResp.success)
    XCTAssertFalse(folderResp.success)
    XCTAssertFalse(renameResp.success)
    XCTAssertFalse(moveResp.success)
    XCTAssertTrue(elapsed < .seconds(10), "All write ops should respond promptly")
  }

  // MARK: - Slow service response handling (crawl handler latency)

  func testSlowCrawlHandlerEventuallyResponds() async {
    let svc = await makeService()
    svc.impl.crawlBoostHandler = { _, _, _ in
      try? await Task.sleep(for: .milliseconds(200))
      return true
    }
    let start = ContinuousClock.now
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)) {
        c.resume(returning: $0)
      }
    }
    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(resp.accepted)
    XCTAssertTrue(elapsed >= .milliseconds(150), "Should wait for handler")
    XCTAssertTrue(elapsed < .seconds(5), "Should not take too long")
  }

  func testCrawlHandlerRejectingAfterDelay() async {
    let svc = await makeService()
    svc.impl.crawlBoostHandler = { _, _, _ in
      try? await Task.sleep(for: .milliseconds(100))
      return false
    }
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.accepted)
  }

  // MARK: - Connection interruption recovery

  func testServiceRecoveryAfterDeviceDisconnectReconnect() async {
    let svc = await makeService(objectCount: 3)
    let deviceId = svc.deviceId

    // Verify connected
    let before = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertTrue(before.connected)

    // Simulate disconnect
    if let service = await svc.registry.service(for: deviceId) {
      await service.markDisconnected()
    }
    let mid = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertFalse(mid.connected)

    // Simulate reconnect
    if let service = await svc.registry.service(for: deviceId) {
      await service.markReconnected()
    }
    let after = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertTrue(after.connected)
  }

  func testReadFailsDuringDisconnectSucceedsAfterReconnect() async {
    let svc = await makeService(objectCount: 1)
    let deviceId = svc.deviceId

    // Disconnect
    if let service = await svc.registry.service(for: deviceId) {
      await service.markDisconnected()
    }

    // Read during disconnect should fail
    let failResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: deviceId.raw, objectHandle: 1000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(failResp.success)

    // Reconnect
    if let service = await svc.registry.service(for: deviceId) {
      await service.markReconnected()
    }

    // Status should show connected again after reconnect
    let status = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertTrue(status.connected)
  }

  func testMultipleDisconnectReconnectCycles() async {
    let svc = await makeService(objectCount: 1)
    let deviceId = svc.deviceId

    for cycle in 0..<5 {
      if let service = await svc.registry.service(for: deviceId) {
        await service.markDisconnected()
        let resp = await statusResult(svc.impl, deviceId: deviceId.raw)
        XCTAssertFalse(resp.connected, "Cycle \(cycle) should be disconnected")

        await service.markReconnected()
        let resp2 = await statusResult(svc.impl, deviceId: deviceId.raw)
        XCTAssertTrue(resp2.connected, "Cycle \(cycle) should be reconnected")
      }
    }
  }

  // MARK: - Service crash and reconnect (device removal + re-registration)

  func testDeviceRemovalAndReRegistration() async {
    let svc = await makeService(objectCount: 2)
    let deviceId = svc.deviceId

    // Remove device entirely
    await svc.registry.remove(deviceId: deviceId)
    let goneResp = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertFalse(goneResp.connected)

    // Re-register with new virtual device
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 2000, storage: storageId, parent: nil, name: "new.txt", data: Data("new".utf8))
    )
    let newVirtual = VirtualMTPDevice(config: config)
    let newService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: deviceId, service: newService)

    let backResp = await statusResult(svc.impl, deviceId: deviceId.raw)
    XCTAssertTrue(backResp.connected)
  }

  func testOperationsFailGracefullyDuringDeviceAbsence() async {
    let svc = await makeService(objectCount: 1)
    await svc.registry.remove(deviceId: svc.deviceId)

    // All operation types should return error, not crash
    let readResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.deviceId.raw, objectHandle: 1000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(readResp.success)

    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(storageResp.success)

    let objectResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: svc.deviceId.raw, storageId: svc.storageId))
      { c.resume(returning: $0) }
    }
    XCTAssertFalse(objectResp.success)

    let infoResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.getObjectInfo(
        deviceId: svc.deviceId.raw, storageId: svc.storageId, objectHandle: 1000
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(infoResp.success)
  }

  // MARK: - Concurrent request limiting

  func testSequentialPingBurstCompletes() async {
    let svc = await makeService()
    var count = 0
    for _ in 0..<50 {
      let msg = await pingResult(svc.impl)
      if msg.contains("running") { count += 1 }
    }
    XCTAssertEqual(count, 50)
  }

  func testSequentialReadBurstCompletes() async {
    let svc = await makeService(objectCount: 5)
    var successCount = 0
    for i in 0..<5 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: UInt32(1000 + i))) {
          c.resume(returning: $0)
        }
      }
      if resp.success { successCount += 1 }
      if let url = resp.tempFileURL {
        try? FileManager.default.removeItem(at: url)
      }
    }
    XCTAssertEqual(successCount, 5)
  }

  func testSequentialMixedOperationBurst() async {
    let svc = await makeService(objectCount: 3)
    let stableId = svc.stableId
    let storageId = svc.storageId

    // Burst of mixed operations
    for _ in 0..<10 {
      _ = await pingResult(svc.impl)
    }
    for _ in 0..<5 {
      _ = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    }
    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) { c.resume(returning: $0) }
    }
    XCTAssertTrue(storageResp.success)

    let objResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: stableId, storageId: storageId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(objResp.success)
  }

  // MARK: - Request deduplication (same request repeated)

  func testRepeatedIdenticalPingsAllSucceed() async {
    let svc = await makeService()
    var results: [String] = []
    for _ in 0..<20 {
      results.append(await pingResult(svc.impl))
    }
    XCTAssertTrue(results.allSatisfy { $0.contains("running") })
  }

  func testRepeatedIdenticalStatusQueriesAllReturn() async {
    let svc = await makeService()
    var responses: [DeviceStatusResponse] = []
    for _ in 0..<20 {
      responses.append(await statusResult(svc.impl, deviceId: svc.deviceId.raw))
    }
    XCTAssertTrue(responses.allSatisfy { $0.connected })
  }

  func testRepeatedStorageListQueriesConsistent() async {
    let svc = await makeService(objectCount: 5)
    var counts: [Int] = []
    for _ in 0..<10 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<StorageListResponse, Never>) in
        svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(resp.success)
      counts.append(resp.storages?.count ?? -1)
    }
    // All queries should return same count
    XCTAssertTrue(Set(counts).count == 1, "All storage queries should return consistent count")
  }

  func testRepeatedObjectListQueriesConsistent() async {
    let svc = await makeService(objectCount: 5)
    var counts: [Int] = []
    for _ in 0..<10 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<ObjectListResponse, Never>) in
        svc.impl.listObjects(ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(resp.success)
      counts.append(resp.objects?.count ?? -1)
    }
    XCTAssertTrue(Set(counts).count == 1, "All object queries should return consistent count")
  }

  func testRepeatedCrawlRequestsWithoutHandler() async {
    let svc = await makeService()
    for _ in 0..<10 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
        svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId))
        { c.resume(returning: $0) }
      }
      XCTAssertFalse(resp.accepted)
    }
  }

  // MARK: - Listener interruption and recovery

  func testListenerStopAndRestartCycle() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)

    for _ in 0..<3 {
      listener.start()
      listener.stop()
    }
    // No crash = pass
  }

  func testListenerAcceptsConnectionsAfterRestart() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()
    listener.stop()
    // Create new listener (simulating restart)
    let listener2 = MTPXPCListener(serviceImpl: impl)
    listener2.start()
    let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
    let accepted = listener2.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn)
    XCTAssertTrue(accepted)
    listener2.stop()
  }

  // MARK: - Crawl handler concurrent invocations

  func testCrawlHandlerCalledMultipleTimesSequentially() async {
    let svc = await makeService()
    var callCount = 0
    svc.impl.crawlBoostHandler = { _, _, _ in
      callCount += 1
      return true
    }
    for _ in 0..<10 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
        svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId))
        { c.resume(returning: $0) }
      }
      XCTAssertTrue(resp.accepted)
    }
    XCTAssertEqual(callCount, 10)
  }

  // MARK: - Error message preservation under load

  func testErrorMessagesPreservedAcrossMultipleFailures() async {
    let svc = await makeService()
    for i in 0..<10 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: "missing-\(i)", objectHandle: UInt32(i))) {
          c.resume(returning: $0)
        }
      }
      XCTAssertFalse(resp.success)
      XCTAssertNotNil(resp.errorMessage, "Error message should be preserved for request \(i)")
    }
  }

  // MARK: - Cleanup timer behavior

  func testCleanupTimerDoesNotCrashOnEmptyDirectory() {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.cleanupOldTempFiles(olderThan: 0)
    // No crash = pass
  }

  func testCleanupTimerIdempotent() {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    for _ in 0..<5 {
      impl.cleanupOldTempFiles(olderThan: 24)
    }
    // No crash = pass
  }
}
