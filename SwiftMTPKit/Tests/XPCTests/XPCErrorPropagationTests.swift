// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Tests that errors propagate correctly across the XPC service boundary.
@MainActor
final class XPCErrorPropagationTests: XCTestCase {

  // MARK: - Helpers

  private func makeService(withObject: Bool = false) async -> (impl: MTPXPCServiceImpl, stableId: String, storageId: UInt32) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    if withObject {
      config = config.withObject(
        VirtualObjectConfig(handle: 100, storage: storageId, parent: nil, name: "test.bin", data: Data("hello".utf8))
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

  // MARK: - Read errors

  func testReadMissingDeviceReturnsError() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "nonexistent", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
    XCTAssertNil(resp.tempFileURL)
  }

  func testReadInvalidHandleReturnsError() async {
    let svc = await makeService(withObject: true)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 99999)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
  }

  // MARK: - Storage errors

  func testListStoragesMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: "no-such-device")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
  }

  // MARK: - Object list errors

  func testListObjectsMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(ObjectListRequest(deviceId: "no-such-device", storageId: 1, parentHandle: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
  }

  // MARK: - GetObjectInfo errors

  func testGetObjectInfoMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.getObjectInfo(deviceId: "no-device", storageId: 1, objectHandle: 1) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testGetObjectInfoInvalidHandle() async {
    let svc = await makeService(withObject: true)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.getObjectInfo(deviceId: svc.stableId, storageId: svc.storageId, objectHandle: 77777) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Write API errors

  func testWriteObjectMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(WriteRequest(deviceId: "missing", storageId: 1, parentHandle: nil, name: "f.txt", size: 0, bookmark: nil)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testDeleteObjectMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: "missing", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testCreateFolderMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.createFolder(CreateFolderRequest(deviceId: "missing", storageId: 1, parentHandle: nil, name: "dir")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testRenameObjectMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.renameObject(RenameRequest(deviceId: "missing", objectHandle: 1, newName: "x")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testMoveObjectMissingDevice() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.moveObject(MoveObjectRequest(deviceId: "missing", objectHandle: 1, newParentHandle: nil, newStorageId: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Crawl errors

  func testCrawlWithoutHandlerReturnsError() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.accepted)
    XCTAssertNotNil(resp.errorMessage)
  }

  func testCrawlWithRejectingHandler() async {
    let svc = await makeService()
    svc.impl.crawlBoostHandler = { _, _, _ in false }
    let resp = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.accepted)
  }

  // MARK: - Write with invalid bookmark

  func testWriteObjectWithNilBookmarkReturnsError() async {
    let svc = await makeService(withObject: true)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil, name: "f.txt", size: 10, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    // Nil bookmark → cannot resolve source URL → error
    XCTAssertFalse(resp.success)
  }

  func testWriteObjectWithInvalidBookmarkReturnsError() async {
    let svc = await makeService(withObject: true)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil, name: "f.txt", size: 10, bookmark: Data([0xFF, 0xFE]))
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.success)
  }
}
