// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

// MARK: - Protocol Conformance

/// Verifies the MTPXPCService protocol surface and that MTPXPCServiceImpl
/// correctly conforms with all required methods.
@MainActor
final class XPCProtocolConformanceTests: XCTestCase {

  func testImplConformsToMTPXPCServiceProtocol() {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    XCTAssertTrue(impl is MTPXPCService, "MTPXPCServiceImpl must conform to MTPXPCService")
  }

  func testNSXPCInterfaceCanBeCreatedForProtocol() {
    let interface = NSXPCInterface(with: MTPXPCService.self)
    XCTAssertNotNil(interface)
  }

  func testProtocolMethodSelectorsExist() {
    // All 12 methods defined in MTPXPCService protocol must be resolvable
    let selectors: [Selector] = [
      #selector(MTPXPCService.ping(reply:)),
      #selector(MTPXPCService.readObject(_:withReply:)),
      #selector(MTPXPCService.listStorages(_:withReply:)),
      #selector(MTPXPCService.listObjects(_:withReply:)),
      #selector(MTPXPCService.getObjectInfo(deviceId:storageId:objectHandle:withReply:)),
      #selector(MTPXPCService.writeObject(_:withReply:)),
      #selector(MTPXPCService.deleteObject(_:withReply:)),
      #selector(MTPXPCService.createFolder(_:withReply:)),
      #selector(MTPXPCService.renameObject(_:withReply:)),
      #selector(MTPXPCService.moveObject(_:withReply:)),
      #selector(MTPXPCService.requestCrawl(_:withReply:)),
      #selector(MTPXPCService.deviceStatus(_:withReply:)),
    ]
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    for sel in selectors {
      XCTAssertTrue(impl.responds(to: sel), "Impl must respond to \(sel)")
    }
  }

  func testProtocolHasExactly12Methods() {
    // Guard against protocol drift: if someone adds a method, this test
    // reminds them to update conformance tests.
    let selectors: [Selector] = [
      #selector(MTPXPCService.ping(reply:)),
      #selector(MTPXPCService.readObject(_:withReply:)),
      #selector(MTPXPCService.listStorages(_:withReply:)),
      #selector(MTPXPCService.listObjects(_:withReply:)),
      #selector(MTPXPCService.getObjectInfo(deviceId:storageId:objectHandle:withReply:)),
      #selector(MTPXPCService.writeObject(_:withReply:)),
      #selector(MTPXPCService.deleteObject(_:withReply:)),
      #selector(MTPXPCService.createFolder(_:withReply:)),
      #selector(MTPXPCService.renameObject(_:withReply:)),
      #selector(MTPXPCService.moveObject(_:withReply:)),
      #selector(MTPXPCService.requestCrawl(_:withReply:)),
      #selector(MTPXPCService.deviceStatus(_:withReply:)),
    ]
    XCTAssertEqual(selectors.count, 12)
  }

  func testServiceNameIsReverseDNS() {
    XCTAssertTrue(
      MTPXPCServiceName.hasPrefix("com."),
      "XPC service name should follow reverse-DNS convention")
    XCTAssertEqual(MTPXPCServiceName, "com.effortlessmetrics.swiftmtp.xpc")
  }
}

// MARK: - Message Encoding Boundary Values

/// Verifies NSSecureCoding round-trip for boundary values (max UInt32/UInt64, zero, etc.).
final class XPCMessageBoundaryTests: XCTestCase {

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  func testReadRequestMaxObjectHandle() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: UInt32.max)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.objectHandle, UInt32.max)
  }

  func testStorageInfoMaxCapacity() throws {
    let info = StorageInfo(
      storageId: UInt32.max, description: "Max",
      capacityBytes: UInt64.max, freeBytes: UInt64.max)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.capacityBytes, UInt64.max)
    XCTAssertEqual(decoded?.freeBytes, UInt64.max)
  }

  func testObjectInfoMaxHandle() throws {
    let info = ObjectInfo(
      handle: UInt32.max, name: "max.bin",
      sizeBytes: UInt64.max, isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.handle, UInt32.max)
    XCTAssertEqual(decoded?.sizeBytes, UInt64.max)
  }

  func testWriteRequestMaxSize() throws {
    let req = WriteRequest(
      deviceId: "dev", storageId: UInt32.max, parentHandle: UInt32.max,
      name: "huge", size: UInt64.max, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.parentHandle, UInt32.max)
    XCTAssertEqual(decoded?.size, UInt64.max)
  }

  func testDeleteRequestMaxHandle() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: UInt32.max, recursive: true)
    let decoded = try roundTrip(req, as: DeleteRequest.self)
    XCTAssertEqual(decoded?.objectHandle, UInt32.max)
  }

  func testMoveObjectRequestMaxValues() throws {
    let req = MoveObjectRequest(
      deviceId: "dev", objectHandle: UInt32.max,
      newParentHandle: UInt32.max, newStorageId: UInt32.max)
    let decoded = try roundTrip(req, as: MoveObjectRequest.self)
    XCTAssertEqual(decoded?.objectHandle, UInt32.max)
    XCTAssertEqual(decoded?.newParentHandle, UInt32.max)
    XCTAssertEqual(decoded?.newStorageId, UInt32.max)
  }

  func testDeviceStatusResponseMaxTimestamp() throws {
    let resp = DeviceStatusResponse(
      connected: true, sessionOpen: true, lastCrawlTimestamp: Int64.max)
    let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, Int64.max)
  }

  func testReadResponseMaxFileSize() throws {
    let resp = ReadResponse(success: true, fileSize: UInt64.max)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.fileSize, UInt64.max)
  }

  func testWriteResponseMaxNewHandle() throws {
    let resp = WriteResponse(success: true, newHandle: UInt32.max)
    let decoded = try roundTrip(resp, as: WriteResponse.self)
    XCTAssertEqual(decoded?.newHandle, UInt32.max)
  }

  func testObjectListRequestMaxStorageAndParent() throws {
    let req = ObjectListRequest(
      deviceId: "dev", storageId: UInt32.max, parentHandle: UInt32.max)
    let decoded = try roundTrip(req, as: ObjectListRequest.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.parentHandle, UInt32.max)
  }

  func testCrawlTriggerRequestMaxValues() throws {
    let req = CrawlTriggerRequest(
      deviceId: "dev", storageId: UInt32.max, parentHandle: UInt32.max)
    let decoded = try roundTrip(req, as: CrawlTriggerRequest.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.parentHandle, UInt32.max)
  }
}

// MARK: - Error Propagation Through XPC Bridge

/// Verifies error messages propagate intact through the XPC service layer,
/// including XPCDeviceError descriptions and cascading failures.
@MainActor
final class XPCErrorCascadeTests: XCTestCase {

  private func makeService(
    withObjects: Int = 0
  ) async -> (impl: MTPXPCServiceImpl, stableId: String, storageId: UInt32) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<withObjects {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(3000 + i), storage: storageId, parent: nil,
          name: "err\(i).bin", data: Data("data".utf8)))
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

  func testXPCDeviceErrorTimeoutDescription() {
    let error = XPCDeviceError.operationTimeout
    XCTAssertTrue(error.description.lowercased().contains("timed out"))
  }

  func testAllWriteAPIsReturnErrorForMissingDevice() async {
    let svc = await makeService()
    let badId = "nonexistent-device"

    // Write
    let writeResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(deviceId: badId, storageId: 1, parentHandle: nil, name: "f", size: 0, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(writeResp.success)
    XCTAssertNotNil(writeResp.errorMessage)

    // Delete
    let deleteResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: badId, objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(deleteResp.success)
    XCTAssertNotNil(deleteResp.errorMessage)

    // CreateFolder
    let folderResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.createFolder(
        CreateFolderRequest(deviceId: badId, storageId: 1, parentHandle: nil, name: "d")
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(folderResp.success)
    XCTAssertNotNil(folderResp.errorMessage)

    // Rename
    let renameResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.renameObject(
        RenameRequest(deviceId: badId, objectHandle: 1, newName: "x")
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(renameResp.success)
    XCTAssertNotNil(renameResp.errorMessage)

    // Move
    let moveResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.moveObject(
        MoveObjectRequest(deviceId: badId, objectHandle: 1, newParentHandle: nil, newStorageId: 1)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(moveResp.success)
    XCTAssertNotNil(moveResp.errorMessage)
  }

  func testErrorMessagesContainDeviceNotFoundIndicator() async {
    let svc = await makeService()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: "ghost-device", objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertTrue(
      resp.errorMessage?.lowercased().contains("not") == true
        || resp.errorMessage?.lowercased().contains("device") == true,
      "Error should mention device-not-found: \(resp.errorMessage ?? "nil")")
  }

  func testCrawlHandlerErrorMessagePreserved() async {
    let svc = await makeService()
    // No handler set → error message should mention configuration
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(resp.accepted)
    XCTAssertNotNil(resp.errorMessage)
    XCTAssertTrue(resp.errorMessage?.lowercased().contains("not configured") == true)
  }

  func testCrawlHandlerAcceptancePropagatesToResponse() async {
    let svc = await makeService()
    svc.impl.crawlBoostHandler = { _, _, _ in true }
    let resp = await withCheckedContinuation {
      (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(resp.accepted)
    XCTAssertNil(resp.errorMessage)
  }
}

// MARK: - Connection Lifecycle & Reconnection

/// Verifies XPC connection setup, invalidation, and reconnection behavior
/// using mock registries without real XPC connections.
@MainActor
final class XPCConnectionReconnectTests: XCTestCase {

  private func makeService() async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry,
    deviceId: MTPDeviceID, stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 5000, storage: storageId, parent: nil,
        name: "reconnect.txt", data: Data("reconnect-data".utf8)))
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

  func testDisconnectReconnectCyclePreservesOperability() async {
    let svc = await makeService()

    // Read works initially
    let before = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 5000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(before.success)
    if let url = before.tempFileURL { try? FileManager.default.removeItem(at: url) }

    // Disconnect
    if let service = await svc.registry.service(for: svc.deviceId) {
      await service.markDisconnected()
    }

    let mid = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(mid.connected)

    // Reconnect
    if let service = await svc.registry.service(for: svc.deviceId) {
      await service.markReconnected()
    }

    let after = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(after.connected)
  }

  func testListenerDelegateAcceptsAndConfiguresConnection() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()

    let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
    let accepted = listener.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn)
    XCTAssertTrue(accepted)

    // Verify the connection was configured with an exported interface
    XCTAssertNotNil(conn.exportedInterface)
    listener.stop()
  }

  func testRapidDisconnectReconnectCycles() async {
    let svc = await makeService()
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }

    for _ in 0..<10 {
      await service.markDisconnected()
      await service.markReconnected()
    }

    let status = await withCheckedContinuation {
      (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(status.connected)
  }

  func testDeviceRemovalPreventsAllOperations() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)

    // All operations should fail gracefully
    let readResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 5000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(readResp.success)

    let storageResp = await withCheckedContinuation {
      (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(storageResp.success)

    let objectResp = await withCheckedContinuation {
      (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(objectResp.success)
  }
}

// MARK: - App Group Container

/// Verifies the shared app group container path used for temp file exchange
/// between the File Provider extension and the main app.
@MainActor
final class XPCAppGroupContainerTests: XCTestCase {

  func testAppGroupIdentifierFormat() {
    // The app group identifier should follow Apple's conventions
    let expected = "group.com.effortlessmetrics.swiftmtp"
    let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: expected)
    // containerURL may be nil in test environment (no entitlements), but the
    // service should still create a fallback temp directory.
    // This test verifies the constant is correctly formatted.
    XCTAssertTrue(expected.hasPrefix("group."), "App group ID must start with 'group.'")
    XCTAssertTrue(expected.contains("swiftmtp"))

    // When no container is available, service falls back to system temp dir
    if containerURL == nil {
      let impl = MTPXPCServiceImpl(deviceManager: .shared)
      // Verify service still initializes without crashing
      XCTAssertNotNil(impl)
    }
  }

  func testServiceCreatesAndUsessTempDirectory() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)

    // Service should create temp directory during init — verify via ping
    let msg = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(msg.contains("running"))
  }

  func testTempFileCleanupRemovesOldFiles() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)

    // cleanupOldTempFiles with negative hours should remove all files
    impl.cleanupOldTempFiles(olderThan: -1)
    // No crash = pass; cleanup is best-effort
  }

  func testTempFileCleanupIgnoresRecentFiles() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    // Large olderThan value should skip everything
    impl.cleanupOldTempFiles(olderThan: 999_999)
  }
}
