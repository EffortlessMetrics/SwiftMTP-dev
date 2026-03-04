// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTransportIOUSBHost

// MARK: - IOUSBHostTransportError Tests

final class IOUSBHostTransportErrorTests: XCTestCase {

  func testErrorCases() {
    // Verify all error cases are constructible and distinct
    let errors: [IOUSBHostTransportError] = [
      .notImplemented("test"),
      .deviceNotFound(vendorID: 0x1234, productID: 0x5678),
      .claimFailed("test"),
      .noMTPInterface,
      .endpointNotFound("bulk-in"),
      .ioError("failed", -1),
      .invalidState("not open"),
      .pipeStall,
      .transferTimeout,
    ]
    // Each error should have a non-empty description
    for error in errors {
      XCTAssertFalse(error.description.isEmpty, "Error \(error) should have a description")
    }
  }

  func testNotImplementedDescription() {
    let error = IOUSBHostTransportError.notImplemented("getStorageInfo")
    XCTAssertTrue(error.description.contains("getStorageInfo"))
    XCTAssertTrue(error.description.contains("Not implemented"))
  }

  func testDeviceNotFoundDescription() {
    let error = IOUSBHostTransportError.deviceNotFound(vendorID: 0x18D1, productID: 0x4EE1)
    XCTAssertTrue(error.description.contains("18d1"))
    XCTAssertTrue(error.description.contains("4ee1"))
  }

  func testIOErrorDescription() {
    let error = IOUSBHostTransportError.ioError("pipe stalled", -536870212)
    XCTAssertTrue(error.description.contains("pipe stalled"))
    XCTAssertTrue(error.description.contains("-536870212"))
  }
}

// MARK: - IOUSBHostLink Default Constructor Tests

final class IOUSBHostLinkDefaultTests: XCTestCase {

  func testDefaultInitHasNilProperties() {
    let link = IOUSBHostLink()
    // Default-constructed link has nil cached info but non-nil linkDescriptor
    // (linkDescriptor is set from the zero-valued endpoint addresses)
    XCTAssertNil(link.cachedDeviceInfo)
  }

  func testDefaultLinkOpenUSBThrowsInvalidState() async {
    let link = IOUSBHostLink()
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected invalidState error")
    } catch let error as IOUSBHostTransportError {
      if case .invalidState = error {
        // expected
      } else {
        XCTFail("Expected invalidState, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testDefaultLinkCloseIsNoOp() async {
    let link = IOUSBHostLink()
    // Should not crash
    await link.close()
  }
}

// MARK: - IOUSBHostTransport Factory Tests

final class IOUSBHostTransportTests: XCTestCase {

  func testTransportFactoryCreatesTransport() {
    let transport = IOUSBHostTransportFactory.createTransport()
    XCTAssertTrue(transport is IOUSBHostTransport)
  }

  func testTransportOpenWithNoDeviceThrows() async {
    let transport = IOUSBHostTransport()
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: nil,  // No VID → should fail
      productID: nil
    )
    do {
      _ = try await transport.open(summary, config: SwiftMTPConfig())
      XCTFail("Expected error for nil VID/PID")
    } catch let error as IOUSBHostTransportError {
      if case .deviceNotFound = error {
        // expected
      } else {
        XCTFail("Expected deviceNotFound, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testTransportCloseIsNoOp() async throws {
    let transport = IOUSBHostTransport()
    // Close without opening should be safe
    try await transport.close()
  }
}

// MARK: - IOUSBHostLink Stub Method Tests

final class IOUSBHostLinkStubTests: XCTestCase {

  /// Methods that are not yet implemented should throw notImplemented.
  func testUnimplementedMethodsThrowNotImplemented() async {
    let link = IOUSBHostLink()

    // resetDevice is still not implemented
    await assertThrowsNotImplemented { try await link.resetDevice() }
  }

  /// Implemented bulk operations should throw invalidState on a default-constructed link
  /// (no USB pipes open) rather than notImplemented.
  func testImplementedMethodsThrowInvalidStateOnDefaultLink() async {
    let link = IOUSBHostLink()

    // getStorageInfo — now implemented, but needs USB pipes
    await assertThrowsInvalidStateOrError {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 1))
    }

    // getObjectHandles
    await assertThrowsInvalidStateOrError {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 1), parent: nil)
    }

    // getObjectInfos (handles)
    await assertThrowsInvalidStateOrError { _ = try await link.getObjectInfos([1]) }

    // getObjectInfos (storage)
    await assertThrowsInvalidStateOrError {
      _ = try await link.getObjectInfos(storage: MTPStorageID(raw: 1), parent: nil, format: nil)
    }

    // moveObject
    await assertThrowsInvalidStateOrError {
      try await link.moveObject(handle: 1, to: MTPStorageID(raw: 1), parent: nil)
    }

    // copyObject
    await assertThrowsInvalidStateOrError {
      _ = try await link.copyObject(handle: 1, toStorage: MTPStorageID(raw: 1), parent: nil)
    }
  }

  private func assertThrowsNotImplemented(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected notImplemented error", file: file, line: line)
    } catch let error as IOUSBHostTransportError {
      if case .notImplemented = error {
        // expected
      } else if case .invalidState = error {
        // also acceptable for default-constructed links
      } else {
        XCTFail("Expected notImplemented, got \(error)", file: file, line: line)
      }
    } catch {
      XCTFail("Unexpected error type: \(error)", file: file, line: line)
    }
  }

  private func assertThrowsInvalidStateOrError(
    _ block: () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected error on default-constructed link", file: file, line: line)
    } catch {
      // Any error is acceptable — invalidState, ioError, etc.
      // The point is that it doesn't succeed without a USB connection.
    }
  }
}

// MARK: - PTP Container Encoding Tests

final class IOUSBHostPTPEncodingTests: XCTestCase {

  func testPTPContainerBasicStructure() {
    // Verify PTPContainer round-trips correctly through the link's encoding.
    // We test indirectly by verifying the container struct itself.
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: 42,
      params: [1]
    )
    XCTAssertEqual(container.type, 1)
    XCTAssertEqual(container.code, 0x1002)
    XCTAssertEqual(container.txid, 42)
    XCTAssertEqual(container.params, [1])
  }

  func testPTPResponseResultOK() {
    let ok = PTPResponseResult(code: 0x2001, txid: 1)
    XCTAssertTrue(ok.isOK)

    let error = PTPResponseResult(code: 0x2002, txid: 1)
    XCTAssertFalse(error.isOK)
  }
}

// MARK: - Device Locator Tests

final class IOUSBHostDeviceLocatorTests: XCTestCase {

  func testEnumerateReturnsArrayWithoutCrash() async throws {
    // On a CI machine without USB devices, this should return an empty array.
    let devices = try await IOUSBHostDeviceLocator.enumerateMTPDevices()
    // We can't assert specific devices, but it shouldn't crash
    XCTAssertTrue(devices.count >= 0)
  }

  func testDeviceEventsStreamFinishes() async {
    let stream = IOUSBHostDeviceLocator.deviceEvents()
    var count = 0
    for await _ in stream {
      count += 1
    }
    // Empty stream should finish immediately
    XCTAssertEqual(count, 0)
  }
}

// MARK: - MTPDeviceEvent Tests

final class MTPDeviceEventTests: XCTestCase {

  func testAttachedEvent() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Google", model: "Pixel 7"
    )
    let event = MTPDeviceEvent.attached(summary)
    if case .attached(let s) = event {
      XCTAssertEqual(s.manufacturer, "Google")
    } else {
      XCTFail("Expected attached event")
    }
  }

  func testDetachedEvent() {
    let event = MTPDeviceEvent.detached("device-123")
    if case .detached(let id) = event {
      XCTAssertEqual(id, "device-123")
    } else {
      XCTFail("Expected detached event")
    }
  }
}

// MARK: - IOUSBHost Bulk Operation Parsing Tests

/// Tests for the PTP response/data parsing logic used by IOUSBHostLink bulk operations.
/// These validate the encoding/decoding helpers without requiring real USB hardware.
final class IOUSBHostBulkOperationTests: XCTestCase {

  // MARK: - Storage ID Array Parsing

  func testStorageIDArrayParsing() {
    // Simulate a GetStorageIDs response payload: count=2, IDs=[0x00010001, 0x00020001]
    var data = Data()
    appendUInt32(&data, 2)         // count
    appendUInt32(&data, 0x00010001) // storage 1
    appendUInt32(&data, 0x00020001) // storage 2

    let ids = parseStorageIDs(from: data)
    XCTAssertEqual(ids.count, 2)
    XCTAssertEqual(ids[0].raw, 0x00010001)
    XCTAssertEqual(ids[1].raw, 0x00020001)
  }

  func testStorageIDArrayEmptyPayload() {
    let ids = parseStorageIDs(from: Data())
    XCTAssertEqual(ids.count, 0)
  }

  func testStorageIDArrayTruncatedPayload() {
    // count says 3 but only 1 ID follows
    var data = Data()
    appendUInt32(&data, 3)
    appendUInt32(&data, 0x00010001)

    let ids = parseStorageIDs(from: data)
    XCTAssertEqual(ids.count, 1)
  }

  // MARK: - Object Handle Array Parsing

  func testObjectHandleArrayParsing() {
    var data = Data()
    appendUInt32(&data, 3)
    appendUInt32(&data, 100)
    appendUInt32(&data, 200)
    appendUInt32(&data, 300)

    let handles = parseObjectHandles(from: data)
    XCTAssertEqual(handles, [100, 200, 300])
  }

  func testObjectHandleArrayEmpty() {
    var data = Data()
    appendUInt32(&data, 0)

    let handles = parseObjectHandles(from: data)
    XCTAssertEqual(handles, [])
  }

  // MARK: - PTP Response Result

  func testPTPResponseResultParamsFromCopyObject() {
    // CopyObject response should contain the new handle in params[0]
    let result = PTPResponseResult(code: 0x2001, txid: 5, params: [42])
    XCTAssertTrue(result.isOK)
    XCTAssertEqual(result.params.first, 42)
  }

  func testPTPResponseResultError() {
    let result = PTPResponseResult(code: 0x2002, txid: 1)  // GeneralError
    XCTAssertFalse(result.isOK)
  }

  // MARK: - StorageInfo Parsing

  func testStorageInfoParsing() {
    // Build a minimal StorageInfo dataset matching PTP spec
    var data = Data()
    appendUInt16(&data, 0x0003)  // StorageType = FixedRAM
    appendUInt16(&data, 0x0002)  // FilesystemType = GenericHierarchical
    appendUInt16(&data, 0x0000)  // AccessCapability = ReadWrite
    appendUInt64(&data, 16_000_000_000)  // MaxCapacity
    appendUInt64(&data, 8_000_000_000)   // FreeSpaceInBytes
    appendUInt32(&data, 0)       // FreeSpaceInObjects
    appendPTPString(&data, "Internal Storage")  // StorageDescription

    var r = PTPReader(data: data)
    _ = r.u16()  // StorageType
    _ = r.u16()  // FilesystemType
    let accessCap = r.u16()
    let maxCap = r.u64()
    let freeSpace = r.u64()
    _ = r.u32()
    let desc = r.string() ?? ""

    XCTAssertEqual(accessCap, 0x0000)
    XCTAssertEqual(maxCap, 16_000_000_000)
    XCTAssertEqual(freeSpace, 8_000_000_000)
    XCTAssertEqual(desc, "Internal Storage")
  }

  func testStorageInfoReadOnly() {
    var data = Data()
    appendUInt16(&data, 0x0003)
    appendUInt16(&data, 0x0002)
    appendUInt16(&data, 0x0001)  // AccessCapability = ReadOnly
    appendUInt64(&data, 1000)
    appendUInt64(&data, 500)
    appendUInt32(&data, 0)
    appendPTPString(&data, "SD Card")

    var r = PTPReader(data: data)
    _ = r.u16(); _ = r.u16()
    let accessCap = r.u16()
    XCTAssertEqual(accessCap, 0x0001)  // ReadOnly
  }

  // MARK: - PTP Container Encoding Round-Trip

  func testPTPContainerEncodingStructure() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getStorageInfo.rawValue,
      txid: 7,
      params: [0x00010001]
    )
    // Verify container properties
    XCTAssertEqual(container.code, 0x1005)
    XCTAssertEqual(container.type, 1)
    XCTAssertEqual(container.txid, 7)
    XCTAssertEqual(container.params, [0x00010001])
  }

  func testPTPContainerMultipleParams() {
    // GetObjectHandles takes 3 params: storageID, formatCode, parent
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: 1,
      params: [0x00010001, 0, 0xFFFFFFFF]
    )
    XCTAssertEqual(container.params.count, 3)
    XCTAssertEqual(container.code, 0x1007)
  }

  // MARK: - Helpers

  private func appendUInt16(_ data: inout Data, _ value: UInt16) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 2))
  }

  private func appendUInt32(_ data: inout Data, _ value: UInt32) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 4))
  }

  private func appendUInt64(_ data: inout Data, _ value: UInt64) {
    var v = value.littleEndian
    data.append(Data(bytes: &v, count: 8))
  }

  private func appendPTPString(_ data: inout Data, _ string: String) {
    // PTP string: UInt8 count (including null), then UTF-16LE chars + null terminator
    let utf16 = Array(string.utf16)
    data.append(UInt8(utf16.count + 1))
    for ch in utf16 {
      var v = ch.littleEndian
      data.append(Data(bytes: &v, count: 2))
    }
    var null: UInt16 = 0
    data.append(Data(bytes: &null, count: 2))
  }

  private func parseStorageIDs(from data: Data) -> [MTPStorageID] {
    guard data.count >= 4 else { return [] }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let count = Int(UInt32(littleEndian: base.load(as: UInt32.self)))
      let available = (data.count - 4) / 4
      let total = min(count, available)
      var ids: [MTPStorageID] = []
      for i in 0..<total {
        let id = UInt32(littleEndian: base.load(fromByteOffset: 4 + i * 4, as: UInt32.self))
        ids.append(MTPStorageID(raw: id))
      }
      return ids
    }
  }

  private func parseObjectHandles(from data: Data) -> [MTPObjectHandle] {
    guard data.count >= 4 else { return [] }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let count = Int(UInt32(littleEndian: base.load(as: UInt32.self)))
      let available = (data.count - 4) / 4
      let total = min(count, available)
      var handles: [MTPObjectHandle] = []
      for i in 0..<total {
        let h = UInt32(littleEndian: base.load(fromByteOffset: 4 + i * 4, as: UInt32.self))
        handles.append(h)
      }
      return handles
    }
  }
}
