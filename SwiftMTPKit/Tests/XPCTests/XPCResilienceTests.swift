// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

// MARK: - Protocol Boundary Tests

/// Tests for XPC message encoding/decoding with boundary values, edge cases, and resilience.
final class XPCProtocolBoundaryTests: XCTestCase {

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  // MARK: - UInt64 boundary values (Int64(bitPattern:) correctness)

  func testReadResponseFileSizeUInt64Max() throws {
    let resp = ReadResponse(success: true, fileSize: UInt64.max)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.fileSize, UInt64.max)
  }

  func testReadResponseFileSizeUInt64Min() throws {
    let resp = ReadResponse(success: true, fileSize: UInt64.min)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.fileSize, UInt64.min)
  }

  func testReadResponseFileSizeZero() throws {
    let resp = ReadResponse(success: true, fileSize: 0)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.fileSize, 0)
  }

  func testStorageInfoCapacityUInt32MaxAsStorageId() throws {
    let info = StorageInfo(
      storageId: UInt32.max, description: "test",
      capacityBytes: UInt64(UInt32.max), freeBytes: 0)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.capacityBytes, UInt64(UInt32.max))
  }

  func testWriteRequestSizeBitPatternRoundTrip() throws {
    // Value that exercises the high bit of UInt64, ensuring Int64(bitPattern:) is used
    let size: UInt64 = 0x8000_0000_0000_0001
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil,
      name: "file.bin", size: size, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.size, size)
  }

  func testObjectInfoSizeBytesHighBitSet() throws {
    let size: UInt64 = 0xFFFF_FFFF_FFFF_FFFE
    let info = ObjectInfo(
      handle: 1, name: "huge.bin", sizeBytes: size,
      isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.sizeBytes, size)
  }

  func testStorageInfoFreeBytesHighBitSet() throws {
    let free: UInt64 = 0x8000_0000_0000_0000
    let info = StorageInfo(
      storageId: 1, description: "test", capacityBytes: UInt64.max, freeBytes: free)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.freeBytes, free)
  }

  // MARK: - Empty strings

  func testWriteRequestEmptyName() throws {
    let req = WriteRequest(
      deviceId: "", storageId: 0, parentHandle: nil,
      name: "", size: 0, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.deviceId, "")
    XCTAssertEqual(decoded?.name, "")
  }

  func testCreateFolderRequestEmptyDeviceIdAndName() throws {
    let req = CreateFolderRequest(deviceId: "", storageId: 0, parentHandle: nil, name: "")
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.deviceId, "")
    XCTAssertEqual(decoded?.name, "")
  }

  // MARK: - Very long strings (10KB+)

  func testReadRequestVeryLongDeviceId() throws {
    let longId = String(repeating: "x", count: 10_240)
    let req = ReadRequest(deviceId: longId, objectHandle: 1)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, longId)
    XCTAssertEqual(decoded?.deviceId.count, 10_240)
  }

  func testObjectInfoVeryLongName() throws {
    let longName = String(repeating: "ñ", count: 12_000)
    let info = ObjectInfo(
      handle: 1, name: longName, sizeBytes: 0,
      isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, longName)
  }

  func testWriteResponseVeryLongErrorMessage() throws {
    let longMsg = String(repeating: "E", count: 15_000)
    let resp = WriteResponse(success: false, errorMessage: longMsg)
    let decoded = try roundTrip(resp, as: WriteResponse.self)
    XCTAssertEqual(decoded?.errorMessage, longMsg)
  }

  // MARK: - Array boundary sizes: 0, 1, 1000

  func testObjectListResponseWithSingleObject() throws {
    let obj = ObjectInfo(
      handle: 42, name: "only.txt", sizeBytes: 100,
      isDirectory: false, modifiedDate: nil)
    let resp = ObjectListResponse(success: true, objects: [obj])
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 1)
    XCTAssertEqual(decoded?.objects?.first?.handle, 42)
  }

  func testStorageListResponseWith1000Storages() throws {
    let storages = (0..<1000)
      .map { i in
        StorageInfo(
          storageId: UInt32(i), description: "S\(i)",
          capacityBytes: UInt64(i) * 1_000_000,
          freeBytes: UInt64(i) * 500_000)
      }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 1000)
    XCTAssertEqual(decoded?.storages?.last?.storageDescription, "S999")
  }

  func testObjectListResponseWith1000Objects() throws {
    let objects = (0..<1000)
      .map { i in
        ObjectInfo(
          handle: UInt32(i), name: "file\(i).dat",
          sizeBytes: UInt64(i * 1024), isDirectory: false, modifiedDate: nil)
      }
    let resp = ObjectListResponse(success: true, objects: objects)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 1000)
    XCTAssertEqual(decoded?.objects?[999].name, "file999.dat")
  }

  // MARK: - Round-trip for every XPC message type

  func testAllRequestTypesRoundTrip() throws {
    let readReq = ReadRequest(deviceId: "d1", objectHandle: 10, bookmark: Data([1, 2, 3]))
    XCTAssertEqual(try roundTrip(readReq, as: ReadRequest.self)?.deviceId, "d1")

    let storageListReq = StorageListRequest(deviceId: "d2")
    XCTAssertEqual(try roundTrip(storageListReq, as: StorageListRequest.self)?.deviceId, "d2")

    let objectListReq = ObjectListRequest(deviceId: "d3", storageId: 5, parentHandle: 99)
    let decodedOLR = try roundTrip(objectListReq, as: ObjectListRequest.self)
    XCTAssertEqual(decodedOLR?.storageId, 5)
    XCTAssertEqual(decodedOLR?.parentHandle, 99)

    let writeReq = WriteRequest(
      deviceId: "d4", storageId: 2, parentHandle: 10,
      name: "w.bin", size: 999, bookmark: Data([0xAA]))
    let decodedWR = try roundTrip(writeReq, as: WriteRequest.self)
    XCTAssertEqual(decodedWR?.size, 999)
    XCTAssertEqual(decodedWR?.parentHandle, 10)

    let deleteReq = DeleteRequest(deviceId: "d5", objectHandle: 77, recursive: true)
    XCTAssertEqual(try roundTrip(deleteReq, as: DeleteRequest.self)?.recursive, true)

    let createFolderReq = CreateFolderRequest(
      deviceId: "d6", storageId: 3, parentHandle: nil, name: "folder")
    XCTAssertNil(try roundTrip(createFolderReq, as: CreateFolderRequest.self)?.parentHandle)

    let renameReq = RenameRequest(deviceId: "d7", objectHandle: 1, newName: "renamed.txt")
    XCTAssertEqual(
      try roundTrip(renameReq, as: RenameRequest.self)?.newName, "renamed.txt")

    let moveReq = MoveObjectRequest(
      deviceId: "d8", objectHandle: 5, newParentHandle: 10, newStorageId: 2)
    let decodedMR = try roundTrip(moveReq, as: MoveObjectRequest.self)
    XCTAssertEqual(decodedMR?.newParentHandle, 10)
    XCTAssertEqual(decodedMR?.newStorageId, 2)

    let crawlReq = CrawlTriggerRequest(deviceId: "d9", storageId: 1, parentHandle: 50)
    XCTAssertEqual(try roundTrip(crawlReq, as: CrawlTriggerRequest.self)?.parentHandle, 50)

    let deviceStatusReq = DeviceStatusRequest(deviceId: "d10")
    XCTAssertEqual(
      try roundTrip(deviceStatusReq, as: DeviceStatusRequest.self)?.deviceId, "d10")
  }

  func testAllResponseTypesRoundTrip() throws {
    let readResp = ReadResponse(
      success: true, errorMessage: nil,
      tempFileURL: URL(fileURLWithPath: "/tmp/t"), fileSize: 42)
    XCTAssertEqual(try roundTrip(readResp, as: ReadResponse.self)?.fileSize, 42)

    let storageListResp = StorageListResponse(
      success: true,
      storages: [
        StorageInfo(storageId: 1, description: "SD", capacityBytes: 100, freeBytes: 50)
      ])
    XCTAssertEqual(
      try roundTrip(storageListResp, as: StorageListResponse.self)?.storages?.count, 1)

    let objectListResp = ObjectListResponse(
      success: false, errorMessage: "err", objects: nil)
    XCTAssertNil(try roundTrip(objectListResp, as: ObjectListResponse.self)?.objects)

    let writeResp = WriteResponse(success: true, newHandle: 88)
    XCTAssertEqual(try roundTrip(writeResp, as: WriteResponse.self)?.newHandle, 88)

    let crawlResp = CrawlTriggerResponse(accepted: true, errorMessage: nil)
    XCTAssertTrue(try roundTrip(crawlResp, as: CrawlTriggerResponse.self)!.accepted)

    let deviceStatusResp = DeviceStatusResponse(
      connected: true, sessionOpen: false, lastCrawlTimestamp: 12345)
    let decodedDS = try roundTrip(deviceStatusResp, as: DeviceStatusResponse.self)
    XCTAssertEqual(decodedDS?.lastCrawlTimestamp, 12345)
    XCTAssertFalse(decodedDS!.sessionOpen)
  }
}

// MARK: - Service Resilience Tests

@MainActor
final class XPCServiceResilienceTests: XCTestCase {

  private func makeService(
    objectCount: Int = 0
  ) async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry,
    deviceId: MTPDeviceID, stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<objectCount {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(800 + i), storage: storageId, parent: nil,
          name: "res\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: 64)))
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

  // MARK: - Nil connection handler

  func testServiceWithNoCrawlHandlerRejectsGracefully() async {
    let svc = await makeService()
    // crawlBoostHandler is nil by default
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.accepted)
    XCTAssertNotNil(resp.errorMessage)
  }

  // MARK: - Multiple concurrent requests

  func testRepeatedStorageListRequests() async {
    let svc = await makeService()
    var results: [StorageListResponse] = []
    for _ in 0..<20 {
      let resp = await withCheckedContinuation {
        (c: CheckedContinuation<StorageListResponse, Never>) in
        svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
          c.resume(returning: $0)
        }
      }
      results.append(resp)
    }
    XCTAssertEqual(results.count, 20)
    XCTAssertTrue(results.allSatisfy { $0.success })
  }

  func testMixedOperationsSequence() async {
    let svc = await makeService(objectCount: 5)

    // Ping
    let ping = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      svc.impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(ping.contains("running"))

    // listStorages
    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)

    // listObjects
    let objResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(objResp.success)
    XCTAssertEqual(objResp.objects?.count, 5)

    // deviceStatus
    let statusResp = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(statusResp.connected)
  }

  // MARK: - Service reset mid-operation

  func testRegistryRemoveWhileRequestsInFlight() async {
    let svc = await makeService(objectCount: 3)
    // List first to ensure device is found, then remove and retry
    let resp1 = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(
          deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(resp1.success)

    await svc.registry.remove(deviceId: svc.deviceId)

    // After removal, should fail gracefully
    let resp2 = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(
          deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp2.success)
  }

  func testDisconnectAndReconnectCycleDuringOperations() async {
    let svc = await makeService(objectCount: 2)
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }
    // Disconnect
    await service.markDisconnected()
    let discStatus = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(discStatus.connected)

    // Reconnect
    await service.markReconnected()
    let reconnStatus = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(reconnStatus.connected)

    // Operations should work again
    let pingResp = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      svc.impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(pingResp.contains("running"))
  }

  // MARK: - Invalid device identifier

  func testServiceWithEmptyDeviceIdReturnsError() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testServiceWithUUIDStyleDeviceIdNotRegistered() async {
    let svc = await makeService()
    let fakeId = UUID().uuidString
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: fakeId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  func testServiceWithSpecialCharacterDeviceId() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: "../../etc/passwd", storageId: 1, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Connection lifecycle: create → use → invalidate

  func testFullServiceLifecycle() async {
    // Create
    let svc = await makeService(objectCount: 1)

    // Use: ping
    let ping = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      svc.impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(ping.contains("running"))

    // Use: list storages
    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)

    // Invalidate: remove device
    await svc.registry.remove(deviceId: svc.deviceId)

    // Post-invalidation: should fail
    let failResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(failResp.success)
  }

  func testMultipleServicesIndependent() async {
    let svc1 = await makeService(objectCount: 1)
    let svc2 = await makeService(objectCount: 2)

    let resp1 = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc1.impl.listObjects(
        ObjectListRequest(deviceId: svc1.stableId, storageId: svc1.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    let resp2 = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc2.impl.listObjects(
        ObjectListRequest(deviceId: svc2.stableId, storageId: svc2.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }

    XCTAssertTrue(resp1.success)
    XCTAssertTrue(resp2.success)
    XCTAssertEqual(resp1.objects?.count, 1)
    XCTAssertEqual(resp2.objects?.count, 2)
  }

  func testRapidPingBurst() async {
    let svc = await makeService()
    for _ in 0..<50 {
      let msg = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
        svc.impl.ping { c.resume(returning: $0) }
      }
      XCTAssertFalse(msg.isEmpty)
    }
  }
}

// MARK: - Error Propagation Resilience Tests

@MainActor
final class XPCErrorPropagationResilienceTests: XCTestCase {

  private func makeService(
    withObject: Bool = false
  ) async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry,
    deviceId: MTPDeviceID, stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    if withObject {
      config = config.withObject(
        VirtualObjectConfig(
          handle: 200, storage: storageId, parent: nil,
          name: "err-test.bin", data: Data("payload".utf8)))
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

  // MARK: - Error code round-trip via serialization

  func testWriteResponseErrorMessageRoundTrip() throws {
    let msg = "Error code 0x2009: Store Full"
    let resp = WriteResponse(success: false, errorMessage: msg)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: WriteResponse.self, from: data)
    XCTAssertEqual(decoded?.errorMessage, msg)
    XCTAssertFalse(decoded!.success)
  }

  func testReadResponseErrorMessagePreserved() throws {
    let msg = "Transport error: USB timeout after 30s (code: -1)"
    let resp = ReadResponse(success: false, errorMessage: msg, tempFileURL: nil, fileSize: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: ReadResponse.self, from: data)
    XCTAssertEqual(decoded?.errorMessage, msg)
  }

  func testCrawlTriggerResponseErrorMessagePreserved() throws {
    let msg = "Nested: outer → inner → root cause: permission denied"
    let resp = CrawlTriggerResponse(accepted: false, errorMessage: msg)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: CrawlTriggerResponse.self, from: data)
    XCTAssertEqual(decoded?.errorMessage, msg)
  }

  // MARK: - Nested error descriptions preserved

  func testNestedErrorDescriptionInStorageListResponse() throws {
    let nestedMsg = "Outer: Device busy → Inner: MTP session locked → Root: USB claim failed"
    let resp = StorageListResponse(success: false, errorMessage: nestedMsg, storages: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: StorageListResponse.self, from: data)
    XCTAssertEqual(decoded?.errorMessage, nestedMsg)
  }

  func testObjectListResponseErrorWithUnicodeDescription() throws {
    let msg = "エラー: デバイスが見つかりません (code: 404)"
    let resp = ObjectListResponse(success: false, errorMessage: msg, objects: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: ObjectListResponse.self, from: data)
    XCTAssertEqual(decoded?.errorMessage, msg)
  }

  // MARK: - Timeout handling

  func testDeviceStatusForMissingDeviceReturnsFalse() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: "timeout-device-xyz")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.connected)
    XCTAssertFalse(resp.sessionOpen)
  }

  func testGetObjectInfoForInvalidHandleAfterRemoval() async {
    let svc = await makeService(withObject: true)
    await svc.registry.remove(deviceId: svc.deviceId)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.getObjectInfo(
        deviceId: svc.stableId, storageId: svc.storageId, objectHandle: 99999
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Connection interrupted recovery

  func testServiceRecoveryAfterDeviceReRegistration() async {
    let svc = await makeService(withObject: true)
    // Remove device simulating interruption
    await svc.registry.remove(deviceId: svc.deviceId)

    // Confirm failure
    let failResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 200)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(failResp.success)

    // Re-register new device
    var newConfig = VirtualDeviceConfig.emptyDevice
    let newStorageId = newConfig.storages[0].id
    newConfig = newConfig.withObject(
      VirtualObjectConfig(
        handle: 300, storage: newStorageId, parent: nil,
        name: "recovered.bin", data: Data("ok".utf8)))
    let newVirtual = VirtualMTPDevice(config: newConfig)
    let newService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: newConfig.deviceId, service: newService)
    await svc.registry.registerDomainMapping(
      deviceId: newConfig.deviceId, domainId: svc.stableId)

    // Should work now
    let successResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(successResp.success)
  }

  // MARK: - Service version mismatch / protocol edge cases

  func testWriteResponseWithNilHandleAndNilError() throws {
    let resp = WriteResponse(success: true, errorMessage: nil, newHandle: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: WriteResponse.self, from: data)
    XCTAssertTrue(decoded!.success)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertNil(decoded?.newHandle)
  }

  func testReadResponseAllNilOptionalFields() throws {
    let resp = ReadResponse(success: false, errorMessage: nil, tempFileURL: nil, fileSize: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: ReadResponse.self, from: data)
    XCTAssertFalse(decoded!.success)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertNil(decoded?.tempFileURL)
    XCTAssertNil(decoded?.fileSize)
  }

  func testDeviceStatusResponseNegativeTimestamp() throws {
    let resp = DeviceStatusResponse(
      connected: false, sessionOpen: false, lastCrawlTimestamp: Int64.min)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: DeviceStatusResponse.self, from: data)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, Int64.min)
  }

  func testDeleteRequestRoundTripWithMaxHandle() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: UInt32.max, recursive: true)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: req, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: DeleteRequest.self, from: data)
    XCTAssertEqual(decoded?.objectHandle, UInt32.max)
    XCTAssertTrue(decoded!.recursive)
  }

  func testMoveObjectRequestNilParentRoundTrip() throws {
    let req = MoveObjectRequest(
      deviceId: "dev", objectHandle: 5, newParentHandle: nil, newStorageId: 1)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: req, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: MoveObjectRequest.self, from: data)
    XCTAssertNil(decoded?.newParentHandle)
    XCTAssertEqual(decoded?.newStorageId, 1)
  }

  func testCrawlHandlerErrorPropagatesDeviceId() async {
    let svc = await makeService()
    var receivedDeviceId: String?
    svc.impl.crawlBoostHandler = { deviceId, _, _ in
      receivedDeviceId = deviceId
      return false
    }
    _ = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: "specific-device-123", storageId: 1)
      ) { c.resume(returning: $0) }
    }
    XCTAssertEqual(receivedDeviceId, "specific-device-123")
  }
}
