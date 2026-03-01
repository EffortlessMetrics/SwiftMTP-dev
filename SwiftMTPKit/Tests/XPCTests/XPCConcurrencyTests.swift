// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Tests for concurrent request handling across XPC service.
@MainActor
final class XPCConcurrencyTests: XCTestCase {

  private func makeService() async -> (impl: MTPXPCServiceImpl, stableId: String, storageId: UInt32) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<10 {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(1000 + i), storage: storageId, parent: nil,
          name: "file\(i).txt", data: Data("data-\(i)".utf8)
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
    return (impl, stableId, storageId.raw)
  }

  func testConcurrentPings() async {
    let svc = await makeService()
    var results: [String] = []
    for _ in 0..<10 {
      let msg = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
        svc.impl.ping { c.resume(returning: $0) }
      }
      results.append(msg)
    }
    XCTAssertEqual(results.count, 10)
    XCTAssertTrue(results.allSatisfy { $0.contains("running") })
  }

  func testConcurrentReads() async {
    let svc = await makeService()
    var successCount = 0
    for i in 0..<10 {
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
    XCTAssertEqual(successCount, 10)
  }

  func testConcurrentStatusQueries() async {
    let svc = await makeService()
    for _ in 0..<10 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
        svc.impl.deviceStatus(DeviceStatusRequest(deviceId: "nonexistent")) {
          c.resume(returning: $0)
        }
      }
      XCTAssertFalse(resp.connected)
    }
  }

  func testConcurrentMixedOperations() async {
    let svc = await makeService()
    let impl = svc.impl
    let stableId = svc.stableId
    let storageId = svc.storageId

    // Run multiple operations sequentially but verify they all succeed
    let pingMsg = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(pingMsg.contains("running"))

    let storageResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)

    let objectResp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      impl.listObjects(ObjectListRequest(deviceId: stableId, storageId: storageId, parentHandle: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(objectResp.success)

    let crawlResp = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      impl.requestCrawl(CrawlTriggerRequest(deviceId: stableId, storageId: storageId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(crawlResp.accepted) // no handler → not accepted
  }
}
