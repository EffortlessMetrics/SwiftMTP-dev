// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Targeted tests for write-path error handling, retry classification,
/// VirtualMTPDevice edge cases, and protocol codec boundary conditions.
/// Wave 37 — tests/harness zone.
final class WritePathAndErrorEdgeCaseTests: XCTestCase {

  // MARK: - Helpers

  private func makeDevice(
    objects: [VirtualObjectConfig] = [],
    storages: [VirtualStorageConfig]? = nil
  ) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    if let storages {
      config = VirtualDeviceConfig(
        deviceId: config.deviceId,
        summary: config.summary,
        info: config.info,
        storages: storages,
        objects: objects
      )
    } else {
      for obj in objects {
        config = config.withObject(obj)
      }
    }
    return VirtualMTPDevice(config: config)
  }

  private var defaultStorage: MTPStorageID {
    MTPStorageID(raw: 0x0001_0001)
  }

  // MARK: - retryableSendObjectFailureReason edge cases

  func testRetryReasonForInvalidParameter0x201D() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.protocolError(code: 0x201D, message: "InvalidParameter")
    )
    XCTAssertEqual(reason, "invalid-parameter-0x201d")
  }

  func testRetryReasonForBusyError() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.busy
    )
    XCTAssertEqual(reason, "busy")
  }

  func testRetryReasonForTimeoutError() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.timeout
    )
    XCTAssertEqual(reason, "timeout")
  }

  func testRetryReasonForTransportTimeout() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.transport(.timeout)
    )
    XCTAssertEqual(reason, "transport-timeout")
  }

  func testRetryReasonForTransportStallIsNotRetryable() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.transport(.stall)
    )
    XCTAssertNil(reason, "Stall is a permanent failure and should not be retried")
  }

  func testRetryReasonReturnsNilForNonMTPErrors() {
    struct CustomError: Error {}
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: CustomError())
    XCTAssertNil(reason, "Non-MTP errors should not produce a retry reason")
  }

  func testRetryReasonReturnsNilForNonRetryableProtocolErrors() {
    // StoreFull (0x200C) is not a retryable write error
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.storageFull
    )
    XCTAssertNil(reason, "storageFull should not be retryable")
  }

  // MARK: - shouldAttemptTargetLadderFallback

  func testTargetLadderFallbackAlwaysTrueForInvalidParameter() {
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: nil, retryClass: .invalidParameter))
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 42, retryClass: .invalidParameter))
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 0xFFFFFFFF, retryClass: .invalidParameter))
  }

  func testTargetLadderFallbackForInvalidObjectHandleRequiresNonRootParent() {
    // With a concrete non-root parent → true
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 42, retryClass: .invalidObjectHandle))
    // nil parent → false (root write)
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: nil, retryClass: .invalidObjectHandle))
    // root sentinel → false
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 0xFFFFFFFF, retryClass: .invalidObjectHandle))
  }

  func testTargetLadderFallbackAlwaysFalseForTransientTransport() {
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: nil, retryClass: .transientTransport))
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 42, retryClass: .transientTransport))
  }

  // MARK: - MTPError property edge cases

  func testIsSessionAlreadyOpenTrue() {
    let error = MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
    XCTAssertTrue(error.isSessionAlreadyOpen)
  }

  func testIsSessionAlreadyOpenFalseForOtherCodes() {
    XCTAssertFalse(MTPError.protocolError(code: 0x2003, message: nil).isSessionAlreadyOpen)
    XCTAssertFalse(MTPError.busy.isSessionAlreadyOpen)
    XCTAssertFalse(MTPError.timeout.isSessionAlreadyOpen)
  }

  func testInternalErrorFactoryMapsToNotSupported() {
    let error = MTPError.internalError("something broke")
    if case .notSupported(let msg) = error {
      XCTAssertEqual(msg, "something broke")
    } else {
      XCTFail("internalError should map to .notSupported")
    }
  }

  // MARK: - MTPEvent.fromRaw boundary cases

  func testEventFromRawTooShortReturnsNil() {
    XCTAssertNil(MTPEvent.fromRaw(Data([0x00, 0x01, 0x02, 0x03, 0x04])))
    XCTAssertNil(MTPEvent.fromRaw(Data()))
    XCTAssertNil(MTPEvent.fromRaw(Data(count: 11)))
  }

  func testEventFromRawExactly12BytesNoParams() {
    // 12-byte container for DeviceInfoChanged (0x4008) — no params needed
    var data = Data(count: 12)
    // length (4 LE)
    data[0] = 12; data[1] = 0; data[2] = 0; data[3] = 0
    // type (2 LE) = 4 (event)
    data[4] = 4; data[5] = 0
    // code (2 LE) = 0x4008
    data[6] = 0x08; data[7] = 0x40
    // txid (4 LE)
    data[8] = 0; data[9] = 0; data[10] = 0; data[11] = 0

    if case .deviceInfoChanged = MTPEvent.fromRaw(data) {
      // expected
    } else {
      XCTFail("Should parse DeviceInfoChanged with no params")
    }
  }

  func testEventFromRawStorageAddedAndRemoved() {
    func makeEvent(code: UInt16, param: UInt32) -> Data {
      var data = Data(count: 16)
      data[0] = 16; data[1] = 0; data[2] = 0; data[3] = 0
      data[4] = 4; data[5] = 0
      data[6] = UInt8(code & 0xFF); data[7] = UInt8(code >> 8)
      data[8] = 0; data[9] = 0; data[10] = 0; data[11] = 0
      data[12] = UInt8(param & 0xFF); data[13] = UInt8((param >> 8) & 0xFF)
      data[14] = UInt8((param >> 16) & 0xFF); data[15] = UInt8((param >> 24) & 0xFF)
      return data
    }

    // StoreAdded (0x4004)
    if case .storageAdded(let sid) = MTPEvent.fromRaw(makeEvent(code: 0x4004, param: 0x0001_0001))
    {
      XCTAssertEqual(sid.raw, 0x0001_0001)
    } else {
      XCTFail("Should parse StoreAdded")
    }

    // StoreRemoved (0x4005)
    if case .storageRemoved(let sid) = MTPEvent.fromRaw(
      makeEvent(code: 0x4005, param: 0x0002_0001))
    {
      XCTAssertEqual(sid.raw, 0x0002_0001)
    } else {
      XCTFail("Should parse StoreRemoved")
    }

    // ObjectInfoChanged (0x4007)
    if case .objectInfoChanged(let handle) = MTPEvent.fromRaw(
      makeEvent(code: 0x4007, param: 99))
    {
      XCTAssertEqual(handle, 99)
    } else {
      XCTFail("Should parse ObjectInfoChanged")
    }
  }

  func testEventFromRawMissingRequiredParamReturnsNil() {
    // ObjectAdded (0x4002) requires a handle param — send no params (12 bytes only)
    var data = Data(count: 12)
    data[0] = 12; data[1] = 0; data[2] = 0; data[3] = 0
    data[4] = 4; data[5] = 0
    data[6] = 0x02; data[7] = 0x40
    data[8] = 0; data[9] = 0; data[10] = 0; data[11] = 0
    XCTAssertNil(MTPEvent.fromRaw(data), "ObjectAdded without param should return nil")
  }

  // MARK: - VirtualMTPDevice edge cases

  func testDeleteNonexistentObjectThrowsObjectNotFound() async throws {
    let device = makeDevice()
    do {
      try await device.delete(999, recursive: false)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testRenameNonexistentObjectThrowsObjectNotFound() async throws {
    let device = makeDevice()
    do {
      try await device.rename(999, to: "new.txt")
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testMoveNonexistentObjectThrowsObjectNotFound() async throws {
    let device = makeDevice()
    do {
      try await device.move(999, to: nil)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testRecursiveDeleteDeepTree() async throws {
    // Create a 3-level deep tree: root folder → child folder → grandchild file
    let rootFolder = VirtualObjectConfig(
      handle: 1, storage: defaultStorage, parent: nil,
      name: "Root", sizeBytes: 0, formatCode: 0x3001
    )
    let childFolder = VirtualObjectConfig(
      handle: 2, storage: defaultStorage, parent: 1,
      name: "Child", sizeBytes: 0, formatCode: 0x3001
    )
    let grandchild = VirtualObjectConfig(
      handle: 3, storage: defaultStorage, parent: 2,
      name: "deep.txt", sizeBytes: 10, formatCode: 0x3000,
      data: Data(repeating: 0xBB, count: 10)
    )

    let device = makeDevice(objects: [rootFolder, childFolder, grandchild])

    // Recursive delete from root should remove entire subtree
    try await device.delete(1, recursive: true)

    // All objects should be gone
    do {
      _ = try await device.getInfo(handle: 1)
      XCTFail("Root should be deleted")
    } catch {}

    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Grandchild should be deleted")
    } catch {}
  }

  func testWriteAndReadBackRoundTrip() async throws {
    let device = makeDevice()
    let tempDir = FileManager.default.temporaryDirectory
    let sourceURL = tempDir.appendingPathComponent("wave37-write-test.bin")
    let destURL = tempDir.appendingPathComponent("wave37-read-test.bin")
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: destURL)
    }

    let payload = Data(repeating: 0xCA, count: 4096)
    try payload.write(to: sourceURL)

    let writeProgress = try await device.write(
      parent: nil, name: "roundtrip.bin", size: UInt64(payload.count), from: sourceURL)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(payload.count))

    // Find the written object by listing
    let stream = device.list(parent: nil, in: defaultStorage)
    var foundHandle: MTPObjectHandle?
    for try await batch in stream {
      if let obj = batch.first(where: { $0.name == "roundtrip.bin" }) {
        foundHandle = obj.handle
      }
    }
    guard let handle = foundHandle else {
      XCTFail("Written object not found in listing")
      return
    }

    let readProgress = try await device.read(handle: handle, range: nil, to: destURL)
    XCTAssertEqual(readProgress.completedUnitCount, Int64(payload.count))

    let readBack = try Data(contentsOf: destURL)
    XCTAssertEqual(readBack, payload, "Round-trip data should match")
  }

  func testReadNonexistentHandleThrows() async throws {
    let device = makeDevice()
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "wave37-noexist.bin")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    do {
      _ = try await device.read(handle: 0xDEAD, range: nil, to: tempURL)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - postWriteVerify edge cases

  func testPostWriteVerifyWithZeroSizeFile() async throws {
    let device = makeDevice(objects: [
      VirtualObjectConfig(
        handle: 50, storage: defaultStorage, parent: nil,
        name: "empty.txt", sizeBytes: 0, formatCode: 0x3000, data: Data()
      )
    ])
    // Should succeed: expected=0, actual=0
    try await postWriteVerify(device: device, handle: 50, expectedSize: 0)
  }

  func testPostWriteVerifyMismatchIncludesExpectedAndActual() async throws {
    let device = makeDevice(objects: [
      VirtualObjectConfig(
        handle: 51, storage: defaultStorage, parent: nil,
        name: "short.bin", sizeBytes: 100, formatCode: 0x3000,
        data: Data(repeating: 0, count: 100)
      )
    ])
    do {
      try await postWriteVerify(device: device, handle: 51, expectedSize: 200)
      XCTFail("Expected verificationFailed")
    } catch let error as MTPError {
      if case .verificationFailed(let expected, let actual) = error {
        XCTAssertEqual(expected, 200)
        XCTAssertEqual(actual, 100)
      } else {
        XCTFail("Wrong error case: \(error)")
      }
    }
  }

  // MARK: - FallbackLadder edge cases

  func testFallbackLadderEmptyRungsThrows() async throws {
    do {
      _ = try await FallbackLadder.execute([FallbackRung<Int>]())
      XCTFail("Empty rungs should throw")
    } catch let error as FallbackAllFailedError {
      XCTAssertTrue(error.attempts.isEmpty)
      XCTAssertTrue(error.description.contains("All fallback rungs failed"))
    }
  }

  func testFallbackAllFailedErrorDescriptionContainsRungNames() async throws {
    let rungs = [
      FallbackRung<Int>(name: "Alpha") { throw MTPError.timeout },
      FallbackRung<Int>(name: "Beta") { throw MTPError.busy },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Should have thrown")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 2)
      XCTAssertTrue(error.description.contains("Alpha"), "Should mention rung name Alpha")
      XCTAssertTrue(error.description.contains("Beta"), "Should mention rung name Beta")
      XCTAssertEqual(error.localizedDescription, error.description)
    }
  }

  // MARK: - Concurrent VirtualMTPDevice operations

  func testConcurrentCreateFolderProducesUniqueHandles() async throws {
    let device = makeDevice()
    let handles = await withTaskGroup(of: MTPObjectHandle.self, returning: [MTPObjectHandle].self) {
      group in
      for i in 0..<10 {
        group.addTask {
          try! await device.createFolder(
            parent: nil, name: "folder-\(i)", storage: MTPStorageID(raw: 0x0001_0001))
        }
      }
      var result: [MTPObjectHandle] = []
      for await h in group { result.append(h) }
      return result
    }
    // All handles must be unique
    XCTAssertEqual(Set(handles).count, 10, "Concurrent createFolder should yield unique handles")
  }
}
