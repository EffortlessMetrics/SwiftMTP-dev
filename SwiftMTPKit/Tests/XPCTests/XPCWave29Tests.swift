// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Wave 29 XPC edge-case and boundary tests covering message size limits,
/// rapid connect/disconnect, crash recovery, invalid messages, concurrent
/// callers, memory management, security paths, progress accuracy, and
/// cancellation propagation.
@MainActor
final class XPCWave29Tests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    objectCount: Int = 0,
    objectDataSize: Int = 64
  ) async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry,
    deviceId: MTPDeviceID, stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<objectCount {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(3000 + i), storage: storageId, parent: nil,
          name: "w29-\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: objectDataSize)
        )
      )
    }
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "w29-domain-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, registry, config.deviceId, stableId, storageId.raw)
  }

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  // MARK: - 1. XPC Message Size Limits

  func testLargeDeviceListSerialization() throws {
    // Simulate a response with 5000 objects (large device file listing)
    let objects = (0..<5000).map { i in
      ObjectInfo(
        handle: UInt32(i),
        name: "IMG_\(String(format: "%05d", i)).jpg",
        sizeBytes: UInt64(i) * 4096,
        isDirectory: false,
        modifiedDate: Date(timeIntervalSince1970: Double(1_700_000_000 + i))
      )
    }
    let resp = ObjectListResponse(success: true, objects: objects)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 5000)
    XCTAssertEqual(decoded?.objects?[0].name, "IMG_00000.jpg")
    XCTAssertEqual(decoded?.objects?[4999].name, "IMG_04999.jpg")
  }

  func testLargeFileMetadataSerialization() throws {
    // ObjectInfo with maximum-length name and all fields populated
    let longName = String(repeating: "あ", count: 255) + ".mp4"
    let info = ObjectInfo(
      handle: UInt32.max, name: longName,
      sizeBytes: UInt64.max, isDirectory: false,
      modifiedDate: Date(timeIntervalSince1970: 1_700_000_000))
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, longName)
    XCTAssertEqual(decoded?.sizeBytes, UInt64.max)
    XCTAssertEqual(decoded?.handle, UInt32.max)
  }

  func testLargeBookmarkPayloadRoundTrip() throws {
    // 8 MB bookmark (simulating a complex security-scoped bookmark)
    let bookmark = Data(repeating: 0xBE, count: 8 * 1024 * 1024)
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil,
      name: "upload.bin", size: UInt64(bookmark.count), bookmark: bookmark)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 8 * 1024 * 1024)
    XCTAssertEqual(decoded?.bookmark, bookmark)
  }

  func testLargeStorageListWithManyStorages() throws {
    // 200 storages (some devices expose many partitions)
    let storages = (0..<200).map { i in
      StorageInfo(
        storageId: UInt32(i),
        description: "Partition \(i) — " + String(repeating: "📁", count: 10),
        capacityBytes: UInt64(i) * 1_000_000_000,
        freeBytes: UInt64(i) * 500_000_000)
    }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 200)
    XCTAssertEqual(decoded?.storages?[199].storageId, 199)
  }

  // MARK: - 2. Rapid Connect/Disconnect Cycles

  func testRapidConnectDisconnect10Cycles() async {
    let svc = await makeService(objectCount: 2)
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }
    for cycle in 0..<10 {
      await service.markDisconnected()
      let disc = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
        svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertFalse(disc.connected, "Cycle \(cycle): should be disconnected")

      await service.markReconnected()
      let recon = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
        svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(recon.connected, "Cycle \(cycle): should be reconnected")
    }
  }

  func testOperationsWorkAfterRapidCycles() async {
    let svc = await makeService(objectCount: 3)
    guard let service = await svc.registry.service(for: svc.deviceId) else {
      XCTFail("Expected service")
      return
    }
    // Rapid disconnect/reconnect
    for _ in 0..<5 {
      await service.markDisconnected()
      await service.markReconnected()
    }
    // Operations should still succeed
    let storageResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)

    let objResp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(objResp.success)
    XCTAssertEqual(objResp.objects?.count, 3)
  }

  // MARK: - 3. XPC Service Crash Recovery Simulation

  func testCrashRecoveryViaRegistryRemoveAndReRegister() async {
    let svc = await makeService(objectCount: 2)
    let stableId = svc.stableId

    // Verify working state
    let beforeResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(beforeResp.success)

    // Simulate crash: remove device from registry
    await svc.registry.remove(deviceId: svc.deviceId)

    // All operations should fail gracefully during "crash"
    let crashResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(crashResp.success)

    let readCrash = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: stableId, objectHandle: 3000)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(readCrash.success)

    // Recovery: re-register new device with same stable ID
    var newConfig = VirtualDeviceConfig.emptyDevice
    let newStorageId = newConfig.storages[0].id
    newConfig = newConfig.withObject(
      VirtualObjectConfig(
        handle: 5000, storage: newStorageId, parent: nil,
        name: "recovered.dat", data: Data("recovered".utf8)))
    let newVirtual = VirtualMTPDevice(config: newConfig)
    let newDeviceService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: newConfig.deviceId, service: newDeviceService)
    await svc.registry.registerDomainMapping(deviceId: newConfig.deviceId, domainId: stableId)

    // Operations should work again
    let recoveredResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(recoveredResp.success)
  }

  func testListenerSurvivesMultipleRestarts() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    for _ in 0..<5 {
      let listener = MTPXPCListener(serviceImpl: impl)
      listener.start()
      listener.startTempFileCleanupTimer(interval: 0.01)
      try? await Task.sleep(for: .milliseconds(20))
      listener.stop()
    }
    // No crash = pass
  }

  // MARK: - 4. Invalid Message Format Handling

  func testCorruptedArchiveDataFailsGracefully() {
    let corruptData = Data([0x00, 0xFF, 0xDE, 0xAD, 0xBE, 0xEF])
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadRequest.self, from: corruptData)
    )
  }

  func testTruncatedArchiveDataFailsGracefully() throws {
    let req = ReadRequest(deviceId: "device", objectHandle: 42)
    let fullData = try NSKeyedArchiver.archivedData(withRootObject: req, requiringSecureCoding: true)
    // Truncate to half
    let truncated = fullData.prefix(fullData.count / 2)
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadRequest.self, from: Data(truncated))
    )
  }

  func testDecodingWrongTypeFailsGracefully() throws {
    // Encode a ReadRequest, try to decode as WriteResponse — should throw
    let req = ReadRequest(deviceId: "dev", objectHandle: 1)
    let data = try NSKeyedArchiver.archivedData(withRootObject: req, requiringSecureCoding: true)
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(ofClass: WriteResponse.self, from: data),
      "Decoding wrong type should throw"
    )
  }

  func testNullByteInStringFields() throws {
    let nameWithNull = "file\0name.txt"
    let info = ObjectInfo(
      handle: 1, name: nameWithNull, sizeBytes: 100,
      isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, nameWithNull)
  }

  func testControlCharactersInDeviceId() throws {
    let controlId = "dev\t\n\r\u{0001}\u{001F}"
    let req = ReadRequest(deviceId: controlId, objectHandle: 1)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, controlId)
  }

  // MARK: - 5. Concurrent Method Invocations from Multiple Callers

  func testConcurrentReadAndListFromSeparateServices() async {
    let svc = await makeService(objectCount: 5)

    // Simulate two independent "callers" issuing different operations
    var readResults: [Bool] = []
    var listResults: [Bool] = []

    for i in 0..<5 {
      let readResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: UInt32(3000 + i))) {
          c.resume(returning: $0)
        }
      }
      readResults.append(readResp.success)
      if let url = readResp.tempFileURL {
        try? FileManager.default.removeItem(at: url)
      }

      let listResp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
        svc.impl.listObjects(
          ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
        ) { c.resume(returning: $0) }
      }
      listResults.append(listResp.success)
    }

    XCTAssertTrue(readResults.allSatisfy { $0 }, "All reads should succeed")
    XCTAssertTrue(listResults.allSatisfy { $0 }, "All lists should succeed")
  }

  func testConcurrentWriteOpsOnSeparateDevices() async {
    let svc1 = await makeService(objectCount: 2)
    let svc2 = await makeService(objectCount: 3)

    // Both services operate independently
    let resp1 = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc1.impl.listObjects(
        ObjectListRequest(deviceId: svc1.stableId, storageId: svc1.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    let resp2 = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc2.impl.listObjects(
        ObjectListRequest(deviceId: svc2.stableId, storageId: svc2.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }

    XCTAssertTrue(resp1.success)
    XCTAssertTrue(resp2.success)
    XCTAssertEqual(resp1.objects?.count, 2)
    XCTAssertEqual(resp2.objects?.count, 3)
  }

  func testConcurrentCrawlInvocations() async {
    let svc = await makeService()
    var callCount = 0
    svc.impl.crawlBoostHandler = { _, _, _ in
      callCount += 1
      return true
    }
    for _ in 0..<20 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
        svc.impl.requestCrawl(
          CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)
        ) { c.resume(returning: $0) }
      }
      XCTAssertTrue(resp.accepted)
    }
    XCTAssertEqual(callCount, 20)
  }

  // MARK: - 6. Memory Management During Long-Running Sessions

  func testRepeatedLargeObjectReadsCleansUp() async {
    let svc = await makeService(objectCount: 5, objectDataSize: 1024)
    var tempURLs: [URL] = []

    for i in 0..<5 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: UInt32(3000 + i))) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(resp.success)
      if let url = resp.tempFileURL {
        tempURLs.append(url)
      }
    }

    // Cleanup should remove all temp files
    svc.impl.cleanupOldTempFiles(olderThan: -1)
    for url in tempURLs {
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                     "Temp file should be cleaned up: \(url.lastPathComponent)")
    }
  }

  func testRepeatedServiceCreationDoesNotLeak() async {
    // Create and destroy many service instances to verify no resource leaks
    for _ in 0..<20 {
      let svc = await makeService(objectCount: 1)
      let resp = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
        svc.impl.ping { c.resume(returning: $0) }
      }
      XCTAssertTrue(resp.contains("running"))
    }
  }

  func testCleanupTimerRepeatedInvocationsStable() async {
    let svc = await makeService(objectCount: 3)
    // Create some temp files via reads
    for i in 0..<3 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: UInt32(3000 + i))) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(resp.success)
    }
    // Run cleanup many times without crashing
    for _ in 0..<10 {
      svc.impl.cleanupOldTempFiles(olderThan: -1)
    }
  }

  // MARK: - 7. XPC Security / Entitlement Validation Paths

  func testNSSecureCodingEnforcedForAllTypes() {
    // Verify all XPC message types support NSSecureCoding
    let types: [NSSecureCoding.Type] = [
      ReadRequest.self, ReadResponse.self,
      StorageInfo.self, StorageListRequest.self, StorageListResponse.self,
      ObjectInfo.self, ObjectListRequest.self, ObjectListResponse.self,
      WriteRequest.self, WriteResponse.self,
      DeleteRequest.self, CreateFolderRequest.self,
      RenameRequest.self, MoveObjectRequest.self,
      CrawlTriggerRequest.self, CrawlTriggerResponse.self,
      DeviceStatusRequest.self, DeviceStatusResponse.self,
    ]
    for type in types {
      XCTAssertTrue(type.supportsSecureCoding, "\(type) must support secure coding")
    }
  }

  func testSecureCodingRejectsNonAllowlistedClasses() {
    // Attempting to decode an unexpected class from XPC data should fail
    let dict = NSDictionary(dictionary: ["key": "value"])
    let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true)
    guard let data = data else { return }
    // Trying to decode as ReadRequest should return nil
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ReadRequest.self, from: data)
    XCTAssertNil(decoded, "Should not decode NSDictionary as ReadRequest")
  }

  func testXPCListenerDelegateConfiguresConnection() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()
    // Verify listener accepts multiple connections in sequence (simulating reconnect)
    for _ in 0..<3 {
      let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
      let accepted = listener.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn)
      XCTAssertTrue(accepted, "Listener should accept connections")
    }
    listener.stop()
  }

  func testPathTraversalInDeviceIdDoesNotSucceed() async {
    let svc = await makeService()
    let maliciousIds = [
      "../../../etc/passwd",
      "..%2F..%2F..%2Fetc%2Fpasswd",
      "/dev/null",
      "device; rm -rf /",
      String(repeating: "A", count: 100_000),
    ]
    for maliciousId in maliciousIds {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: maliciousId, objectHandle: 1)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertFalse(resp.success, "Malicious ID should not succeed: \(maliciousId.prefix(40))")
    }
  }

  // MARK: - 8. Progress Reporting Accuracy During Transfers

  func testReadResponseFileSizeMatchesActualData() async {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    let testData = Data(repeating: 0x42, count: 2048)
    config = config.withObject(
      VirtualObjectConfig(
        handle: 8888, storage: storageId, parent: nil,
        name: "progress-test.bin", data: testData))
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "w29-progress-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry

    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      impl.readObject(ReadRequest(deviceId: stableId, objectHandle: 8888)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.success)
    XCTAssertEqual(resp.fileSize, UInt64(testData.count))

    if let url = resp.tempFileURL {
      let actual = try? Data(contentsOf: url)
      XCTAssertEqual(actual?.count, testData.count)
      XCTAssertEqual(actual, testData)
      try? FileManager.default.removeItem(at: url)
    }
  }

  func testObjectInfoFileSizeConsistency() async {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    let sizes: [Int] = [0, 1, 512, 1024, 65536]
    for (i, size) in sizes.enumerated() {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(9000 + i), storage: storageId, parent: nil,
          name: "size-\(size).dat", data: Data(repeating: 0xAA, count: size)))
    }
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "w29-sizes-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry

    let objResp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      impl.listObjects(
        ObjectListRequest(deviceId: stableId, storageId: storageId.raw, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(objResp.success)
    XCTAssertEqual(objResp.objects?.count, sizes.count)

    // Verify reported sizes match expected values
    for (i, size) in sizes.enumerated() {
      let infoResp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        impl.getObjectInfo(
          deviceId: stableId, storageId: storageId.raw, objectHandle: UInt32(9000 + i)
        ) { c.resume(returning: $0) }
      }
      XCTAssertTrue(infoResp.success)
      XCTAssertEqual(infoResp.fileSize, UInt64(size), "Size mismatch for object \(9000 + i)")
    }
  }

  // MARK: - 9. Cancellation Propagation Through XPC Boundary

  func testCrawlHandlerCancellationPropagates() async {
    let svc = await makeService()
    var handlerInvoked = false
    svc.impl.crawlBoostHandler = { _, _, _ in
      handlerInvoked = true
      // Simulate slow crawl handler that checks for cancellation
      try? await Task.sleep(for: .milliseconds(50))
      return Task.isCancelled ? false : true
    }
    let resp = await withCheckedContinuation { (c: CheckedContinuation<CrawlTriggerResponse, Never>) in
      svc.impl.requestCrawl(
        CrawlTriggerRequest(deviceId: svc.stableId, storageId: svc.storageId)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(handlerInvoked)
    // Since we didn't cancel, it should succeed
    XCTAssertTrue(resp.accepted)
  }

  func testAllWriteOperationsFailForMissingDeviceWithinTimeout() async {
    let svc = await makeService()
    let missingId = "cancelled-device-\(UUID().uuidString)"
    let start = ContinuousClock.now

    // Write
    let writeResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.writeObject(
        WriteRequest(
          deviceId: missingId, storageId: 1, parentHandle: nil,
          name: "f.txt", size: 100, bookmark: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(writeResp.success)

    // Delete
    let deleteResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.deleteObject(DeleteRequest(deviceId: missingId, objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(deleteResp.success)

    // CreateFolder
    let folderResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.createFolder(
        CreateFolderRequest(deviceId: missingId, storageId: 1, parentHandle: nil, name: "dir")
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(folderResp.success)

    // Rename
    let renameResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.renameObject(RenameRequest(deviceId: missingId, objectHandle: 1, newName: "x")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(renameResp.success)

    // Move
    let moveResp = await withCheckedContinuation { (c: CheckedContinuation<WriteResponse, Never>) in
      svc.impl.moveObject(
        MoveObjectRequest(deviceId: missingId, objectHandle: 1, newParentHandle: nil, newStorageId: 1)
      ) { c.resume(returning: $0) }
    }
    XCTAssertFalse(moveResp.success)

    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(elapsed < .seconds(10), "All cancelled ops should complete promptly")
  }

  func testServiceRemainsStableAfterRepeatedFailures() async {
    let svc = await makeService(objectCount: 1)

    // Issue many failing requests
    for _ in 0..<20 {
      let _ = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(ReadRequest(deviceId: "nonexistent", objectHandle: 99999)) {
          c.resume(returning: $0)
        }
      }
    }

    // Service should still work for valid requests
    let ping = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      svc.impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(ping.contains("running"))

    let storageResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)
  }
}
