// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

// MARK: - Large Payload & Encoding Edge Cases

/// Tests for XPC message encoding/decoding edge cases: large payloads,
/// malformed data, type mismatches, Unicode, and concurrent round-trips.
final class XPCLargePayloadBoundaryTests: XCTestCase {

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  // MARK: - Large payload encoding/decoding

  func testBookmarkPayload1MBRoundTrip() throws {
    let oneMB = Data(repeating: 0xBE, count: 1_024 * 1_024)
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: oneMB)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 1_024 * 1_024)
    XCTAssertEqual(decoded?.bookmark, oneMB)
  }

  func testBookmarkPayload16MBRoundTrip() throws {
    let sixteenMB = Data(repeating: 0xAF, count: 16 * 1_024 * 1_024)
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil,
      name: "large.bin", size: UInt64(sixteenMB.count), bookmark: sixteenMB)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 16 * 1_024 * 1_024)
    XCTAssertEqual(decoded?.bookmark, sixteenMB)
  }

  func testBookmarkPayloadJustUnder64MBLimit() throws {
    // 60MB — just under the 64MB XPC message size limit
    let nearLimit = Data(repeating: 0xEE, count: 60 * 1_024 * 1_024)
    let req = ReadRequest(deviceId: "limit-test", objectHandle: 99, bookmark: nearLimit)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 60 * 1_024 * 1_024)
  }

  // MARK: - Empty payload handling

  func testEmptyDataBookmarkRoundTrip() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: Data())
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertNotNil(decoded?.bookmark)
    XCTAssertEqual(decoded?.bookmark?.count, 0)
  }

  func testWriteRequestEmptyBookmark() throws {
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil,
      name: "e.bin", size: 0, bookmark: Data())
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertNotNil(decoded?.bookmark)
    XCTAssertEqual(decoded?.bookmark?.count, 0)
  }

  // MARK: - Unicode strings in XPC messages

  func testMultiCodepointEmojiInDeviceId() throws {
    let emoji = "👨‍👩‍👧‍👦🏳️‍🌈🇯🇵"
    let req = ReadRequest(deviceId: emoji, objectHandle: 1)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, emoji)
  }

  func testRTLTextInObjectName() throws {
    let rtl = "مجلد الصور - תמונות"
    let info = ObjectInfo(
      handle: 1, name: rtl, sizeBytes: 100,
      isDirectory: true, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, rtl)
  }

  func testCombiningDiacriticsInFolderName() throws {
    // é composed via combining acute accent (U+0301)
    let combining = "re\u{0301}sume\u{0308}_folder"
    let req = CreateFolderRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil, name: combining)
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.name, combining)
  }

  func testNullCharacterEmbeddedInDeviceId() throws {
    let withNull = "device\0id\0test"
    let req = StorageListRequest(deviceId: withNull)
    let decoded = try roundTrip(req, as: StorageListRequest.self)
    XCTAssertEqual(decoded?.deviceId, withNull)
  }

  func testSurrogatePairsAndMixedScriptsInRename() throws {
    let mixed = "𝕳𝖊𝖑𝖑𝖔-世界-Привет-🎵"
    let req = RenameRequest(deviceId: "dev", objectHandle: 1, newName: mixed)
    let decoded = try roundTrip(req, as: RenameRequest.self)
    XCTAssertEqual(decoded?.newName, mixed)
  }
}

// MARK: - Malformed Data & Type Mismatch Tests

final class XPCMessageValidationTests: XCTestCase {

  // MARK: - Invalid message handling (malformed protocol messages)

  func testMalformedArchiveDataReturnsNilOrThrows() {
    let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(
        ofClass: ReadRequest.self, from: garbage))
  }

  func testTruncatedArchiveDataReturnsNilOrThrows() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: 42)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: req, requiringSecureCoding: true)
    // Truncate to half
    let truncated = data.prefix(data.count / 2)
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(
        ofClass: ReadRequest.self, from: Data(truncated)))
  }

  func testEmptyArchiveDataReturnsNilOrThrows() {
    XCTAssertThrowsError(
      try NSKeyedUnarchiver.unarchivedObject(
        ofClass: ReadRequest.self, from: Data()))
  }

  // MARK: - Type mismatch resilience

  func testDecodingReadRequestAsWriteRequestFails() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: 1)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: req, requiringSecureCoding: true)
    // Attempting to decode as a different XPC type should fail
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: WriteRequest.self, from: data)
    XCTAssertNil(decoded)
  }

  func testDecodingStorageInfoAsObjectInfoFails() throws {
    let info = StorageInfo(
      storageId: 1, description: "SD", capacityBytes: 1000, freeBytes: 500)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: info, requiringSecureCoding: true)
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: ObjectInfo.self, from: data)
    XCTAssertNil(decoded)
  }

  func testDecodingWriteResponseAsReadResponseFails() throws {
    let resp = WriteResponse(success: true, newHandle: 42)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: resp, requiringSecureCoding: true)
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: ReadResponse.self, from: data)
    XCTAssertNil(decoded)
  }

  // MARK: - Version mismatch handling (missing/extra keys)

  func testDecodingWithMissingRequiredKeyReturnsNil() throws {
    // Manually build an archive without the required "deviceId" key
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    archiver.encode(Int64(42), forKey: "objectHandle")
    // Intentionally omit "deviceId"
    archiver.finishEncoding()
    let data = archiver.encodedData

    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
    unarchiver.requiresSecureCoding = true
    let decoded = ReadRequest(coder: unarchiver)
    XCTAssertNil(decoded, "Missing required key should cause init?(coder:) to return nil")
  }

  func testDecodingWithExtraKeysSucceeds() throws {
    // Encode a ReadRequest, then add an extra key — decoding should still work
    let req = ReadRequest(deviceId: "dev", objectHandle: 7)
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    req.encode(with: archiver)
    archiver.encode("extraValue", forKey: "futureField")
    archiver.finishEncoding()

    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    unarchiver.requiresSecureCoding = true
    let decoded = ReadRequest(coder: unarchiver)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "dev")
    XCTAssertEqual(decoded?.objectHandle, 7)
  }

  func testMissingOptionalFieldsDecodeAsNil() throws {
    // Encode only the required fields of ReadResponse (success)
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    archiver.encode(true, forKey: "success")
    // Intentionally omit errorMessage, tempFileURL, fileSize
    archiver.finishEncoding()

    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    unarchiver.requiresSecureCoding = true
    let decoded = ReadResponse(coder: unarchiver)
    XCTAssertNotNil(decoded)
    XCTAssertTrue(decoded!.success)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertNil(decoded?.tempFileURL)
    XCTAssertNil(decoded?.fileSize)
  }
}

// MARK: - Concurrent Encoding & Service-Level Boundary Tests

@MainActor
final class XPCConcurrentBoundaryTests: XCTestCase {

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
          handle: UInt32(2000 + i), storage: storageId, parent: nil,
          name: "boundary\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: 32)))
    }
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "boundary-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, registry, config.deviceId, stableId, storageId.raw)
  }

  // MARK: - Concurrent XPC calls

  func testConcurrentRoundTripEncodingDecoding() async throws {
    // Verify thread safety of NSKeyedArchiver/Unarchiver across many concurrent tasks
    try await withThrowingTaskGroup(of: Bool.self) { group in
      for i in 0..<50 {
        group.addTask {
          let req = ReadRequest(deviceId: "dev-\(i)", objectHandle: UInt32(i))
          let data = try NSKeyedArchiver.archivedData(
            withRootObject: req, requiringSecureCoding: true)
          let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ReadRequest.self, from: data)
          return decoded?.deviceId == "dev-\(i)" && decoded?.objectHandle == UInt32(i)
        }
      }
      for try await result in group {
        XCTAssertTrue(result)
      }
    }
  }

  func testConcurrentMixedTypeRoundTrips() async throws {
    try await withThrowingTaskGroup(of: Bool.self) { group in
      for i in 0..<20 {
        group.addTask {
          let info = StorageInfo(
            storageId: UInt32(i), description: "S\(i)",
            capacityBytes: UInt64(i) * 1000, freeBytes: UInt64(i) * 500)
          let data = try NSKeyedArchiver.archivedData(
            withRootObject: info, requiringSecureCoding: true)
          let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: StorageInfo.self, from: data)
          return decoded?.storageId == UInt32(i)
        }
        group.addTask {
          let obj = ObjectInfo(
            handle: UInt32(i), name: "f\(i).txt",
            sizeBytes: UInt64(i * 100), isDirectory: false, modifiedDate: nil)
          let data = try NSKeyedArchiver.archivedData(
            withRootObject: obj, requiringSecureCoding: true)
          let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ObjectInfo.self, from: data)
          return decoded?.handle == UInt32(i)
        }
      }
      for try await result in group {
        XCTAssertTrue(result)
      }
    }
  }

  // MARK: - Connection interruption recovery

  func testInterruptionRecoveryWithRepeatedCycles() async {
    let svc = await makeService(objectCount: 3)

    for cycle in 0..<3 {
      // Verify working
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
        svc.impl.listObjects(
          ObjectListRequest(
            deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
        ) { c.resume(returning: $0) }
      }
      XCTAssertTrue(resp.success, "Cycle \(cycle): expected success before disconnect")

      // Simulate interruption
      if let service = await svc.registry.service(for: svc.deviceId) {
        await service.markDisconnected()
      }

      let discStatus = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
        svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertFalse(discStatus.connected, "Cycle \(cycle): expected disconnected")

      // Recover
      if let service = await svc.registry.service(for: svc.deviceId) {
        await service.markReconnected()
      }

      let reconnStatus = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
        svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
          c.resume(returning: $0)
        }
      }
      XCTAssertTrue(reconnStatus.connected, "Cycle \(cycle): expected reconnected")
    }
  }

  // MARK: - Stress: large object list round-trip via service

  func testLargeObjectListViaService() async {
    let count = 500
    let svc = await makeService(objectCount: count)

    let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(
          deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(resp.success)
    XCTAssertEqual(resp.objects?.count, count)
  }
}
