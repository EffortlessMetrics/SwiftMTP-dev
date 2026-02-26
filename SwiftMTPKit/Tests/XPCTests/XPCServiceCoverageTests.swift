// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

@MainActor
final class XPCServiceCoverageTests: XCTestCase {
  private func configuredService() async -> (
    impl: MTPXPCServiceImpl, stableId: String, ephemeralId: MTPDeviceID, storageId: UInt32,
    objectHandle: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    let objectHandle: UInt32 = 4242
    config = config.withObject(
      VirtualObjectConfig(
        handle: objectHandle,
        storage: storageId,
        parent: nil,
        name: "xpc-test.txt",
        data: Data("xpc payload".utf8)
      )
    )

    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "domain-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, stableId, config.deviceId, storageId.raw, objectHandle)
  }

  private func ping(_ impl: MTPXPCServiceImpl) async -> String {
    await withCheckedContinuation { continuation in
      impl.ping { message in
        continuation.resume(returning: message)
      }
    }
  }

  private func read(_ impl: MTPXPCServiceImpl, request: ReadRequest) async -> ReadResponse {
    await withCheckedContinuation { continuation in
      impl.readObject(request) { response in
        continuation.resume(returning: response)
      }
    }
  }

  private func storages(_ impl: MTPXPCServiceImpl, request: StorageListRequest) async
    -> StorageListResponse
  {
    await withCheckedContinuation { continuation in
      impl.listStorages(request) { response in
        continuation.resume(returning: response)
      }
    }
  }

  private func objects(_ impl: MTPXPCServiceImpl, request: ObjectListRequest) async
    -> ObjectListResponse
  {
    await withCheckedContinuation { continuation in
      impl.listObjects(request) { response in
        continuation.resume(returning: response)
      }
    }
  }

  private func objectInfo(
    _ impl: MTPXPCServiceImpl, deviceId: String, storageId: UInt32, objectHandle: UInt32
  ) async -> ReadResponse {
    await withCheckedContinuation { continuation in
      impl.getObjectInfo(deviceId: deviceId, storageId: storageId, objectHandle: objectHandle) {
        response in
        continuation.resume(returning: response)
      }
    }
  }

  private func crawl(_ impl: MTPXPCServiceImpl, request: CrawlTriggerRequest) async
    -> CrawlTriggerResponse
  {
    await withCheckedContinuation { continuation in
      impl.requestCrawl(request) { response in
        continuation.resume(returning: response)
      }
    }
  }

  private func status(_ impl: MTPXPCServiceImpl, request: DeviceStatusRequest) async
    -> DeviceStatusResponse
  {
    await withCheckedContinuation { continuation in
      impl.deviceStatus(request) { response in
        continuation.resume(returning: response)
      }
    }
  }

  func testServiceImplSuccessAndErrorPaths() async throws {
    let config = await configuredService()
    let impl = config.impl

    let pingMessage = await ping(impl)
    XCTAssertTrue(pingMessage.contains("running"))

    let missingRead = await read(
      impl, request: ReadRequest(deviceId: "missing-device", objectHandle: config.objectHandle))
    XCTAssertFalse(missingRead.success)
    XCTAssertNotNil(missingRead.errorMessage)

    let successfulRead = await read(
      impl, request: ReadRequest(deviceId: config.stableId, objectHandle: config.objectHandle))
    XCTAssertTrue(successfulRead.success)
    XCTAssertNotNil(successfulRead.tempFileURL)
    XCTAssertEqual(successfulRead.fileSize, UInt64(Data("xpc payload".utf8).count))
    if let fileURL = successfulRead.tempFileURL {
      defer { try? FileManager.default.removeItem(at: fileURL) }
      let bytes = try Data(contentsOf: fileURL)
      XCTAssertEqual(bytes, Data("xpc payload".utf8))
    }

    let missingStorages = await storages(
      impl, request: StorageListRequest(deviceId: "missing-device"))
    XCTAssertFalse(missingStorages.success)
    XCTAssertNotNil(missingStorages.errorMessage)

    let storageResponse = await storages(
      impl, request: StorageListRequest(deviceId: config.stableId))
    XCTAssertTrue(storageResponse.success)
    XCTAssertTrue(
      (storageResponse.storages ?? []).contains(where: { $0.storageId == config.storageId }))

    let objectResponse = await objects(
      impl,
      request: ObjectListRequest(
        deviceId: config.stableId, storageId: config.storageId, parentHandle: nil)
    )
    XCTAssertTrue(objectResponse.success)
    XCTAssertTrue(
      (objectResponse.objects ?? []).contains(where: { $0.handle == config.objectHandle }))

    let objectInfoResponse = await objectInfo(
      impl,
      deviceId: config.stableId,
      storageId: config.storageId,
      objectHandle: config.objectHandle
    )
    XCTAssertTrue(objectInfoResponse.success)
    XCTAssertEqual(objectInfoResponse.fileSize, UInt64(Data("xpc payload".utf8).count))
  }

  func testServiceImplCrawlStatusAndCleanupBranches() async throws {
    let config = await configuredService()
    let impl = config.impl

    let defaultCrawl = await crawl(
      impl,
      request: CrawlTriggerRequest(
        deviceId: config.stableId, storageId: config.storageId, parentHandle: nil)
    )
    XCTAssertFalse(defaultCrawl.accepted)
    XCTAssertNotNil(defaultCrawl.errorMessage)

    impl.crawlBoostHandler = { _, storageId, _ in
      storageId == config.storageId
    }

    let accepted = await crawl(
      impl,
      request: CrawlTriggerRequest(
        deviceId: config.stableId, storageId: config.storageId, parentHandle: config.objectHandle)
    )
    XCTAssertTrue(accepted.accepted)
    XCTAssertNil(accepted.errorMessage)

    let missingStatus = await status(impl, request: DeviceStatusRequest(deviceId: "missing-device"))
    XCTAssertFalse(missingStatus.connected)
    XCTAssertFalse(missingStatus.sessionOpen)

    let connectedStatus = await status(
      impl, request: DeviceStatusRequest(deviceId: config.ephemeralId.raw))
    XCTAssertTrue(connectedStatus.connected)
    XCTAssertTrue(connectedStatus.sessionOpen)

    let response = await read(
      impl, request: ReadRequest(deviceId: config.stableId, objectHandle: config.objectHandle))
    guard let tempFile = response.tempFileURL else {
      XCTFail("Expected temp file URL")
      return
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
    impl.cleanupOldTempFiles(olderThan: -1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
  }

  func testDeviceStatusReportsFalseAfterDisconnect() async throws {
    let config = await configuredService()
    let impl = config.impl

    // Before disconnect: service should be connected
    let before = await status(impl, request: DeviceStatusRequest(deviceId: config.ephemeralId.raw))
    XCTAssertTrue(before.connected)

    // Mark service disconnected
    if let svc = await config.impl.registry?.service(for: config.ephemeralId) {
      await svc.markDisconnected()
    }

    // After disconnect: deviceStatus must report connected=false
    let after = await status(impl, request: DeviceStatusRequest(deviceId: config.ephemeralId.raw))
    XCTAssertFalse(after.connected)
    XCTAssertFalse(after.sessionOpen)
  }

  func testRenameAndMoveObject() async throws {
    let config = await configuredService()
    let impl = config.impl

    // Rename: missing device
    let missingRename = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      impl.renameObject(RenameRequest(deviceId: "bad", objectHandle: 1, newName: "new.txt")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(missingRename.success)

    // Rename: success
    let renameResp = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      impl.renameObject(
        RenameRequest(
          deviceId: config.stableId, objectHandle: config.objectHandle, newName: "renamed.txt")
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(renameResp.success)

    // Move: missing device
    let missingMove = await withCheckedContinuation {
      (c: CheckedContinuation<WriteResponse, Never>) in
      impl.moveObject(
        MoveObjectRequest(deviceId: "bad", objectHandle: 1, newParentHandle: nil, newStorageId: 0)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(missingMove.success)

    // Move: success (move to root)
    let moveResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      impl.moveObject(
        MoveObjectRequest(
          deviceId: config.stableId, objectHandle: config.objectHandle,
          newParentHandle: nil, newStorageId: config.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(moveResp.success)
  }

  func testListenerLifecycleAndConnectionAcceptance() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)

    listener.start()
    listener.startTempFileCleanupTimer(interval: 0.01)
    try? await Task.sleep(for: .milliseconds(30))

    let connection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
    let accepted = listener.listener(
      NSXPCListener.anonymous(), shouldAcceptNewConnection: connection)
    XCTAssertTrue(accepted)

    listener.stop()
    MTPDeviceManager.shared.startXPCService()
    MTPDeviceManager.shared.stopXPCService()
  }
}
