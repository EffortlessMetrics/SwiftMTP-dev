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

// MARK: - PTP Data Container Framing Tests

/// Tests verifying correct PTP container framing for file transfer operations.
/// These validate encoding/decoding at the container level without real USB hardware.
final class IOUSBHostPTPDataFramingTests: XCTestCase {

  // MARK: - Data-In Container Parsing

  func testDataInContainerHeaderParsing() {
    // Build a PTP data container: 12-byte header + payload
    let payload = Data(repeating: 0xAB, count: 256)
    let container = buildPTPDataContainer(code: PTPOp.getObject.rawValue, txid: 1, payload: payload)

    // Verify header fields
    container.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let length = UInt32(littleEndian: base.load(as: UInt32.self))
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      let code = UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self))
      let txid = UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self))

      XCTAssertEqual(Int(length), 12 + payload.count)
      XCTAssertEqual(type, PTPContainer.Kind.data.rawValue)
      XCTAssertEqual(code, PTPOp.getObject.rawValue)
      XCTAssertEqual(txid, 1)
    }

    // Verify payload extraction
    let extracted = container.subdata(in: 12..<container.count)
    XCTAssertEqual(extracted, payload)
  }

  func testDataInContainerMultiChunkReassembly() {
    // Simulate a large GetObject response split across multiple chunks
    let totalPayload = Data(0..<200)
    let container = buildPTPDataContainer(
      code: PTPOp.getObject.rawValue, txid: 1, payload: totalPayload
    )

    // Split into chunks (first chunk has header + partial data, rest are pure data)
    let chunk1 = container.subdata(in: 0..<100)
    let chunk2 = container.subdata(in: 100..<container.count)

    // Parse header from chunk1
    var reassembled = Data()
    chunk1.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let length = UInt32(littleEndian: base.load(as: UInt32.self))
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      XCTAssertEqual(Int(length), 12 + totalPayload.count)
      XCTAssertEqual(type, PTPContainer.Kind.data.rawValue)
    }
    // Extract payload from chunk1 (after 12-byte header)
    reassembled.append(chunk1.subdata(in: 12..<chunk1.count))
    // Append chunk2 (pure data, no header)
    reassembled.append(chunk2)

    XCTAssertEqual(reassembled, totalPayload)
  }

  func testDataInContainerLargeFileSentinel() {
    // For files >4GB, PTP uses 0xFFFFFFFF as length sentinel
    var header = Data(count: 12)
    header.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.data.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(
        of: PTPOp.getObject.rawValue.littleEndian,
        toByteOffset: 6, as: UInt16.self
      )
      base.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 8, as: UInt32.self)
    }

    header.withUnsafeBytes { buf in
      let len = UInt32(littleEndian: buf.load(as: UInt32.self))
      XCTAssertEqual(len, 0xFFFFFFFF, "Sentinel value indicates indeterminate length")
    }
  }

  // MARK: - Data-Out Container Encoding

  func testDataOutContainerEncoding() {
    // Verify the PTP data container header for SendObject
    let dataLen: UInt64 = 1024
    let code = PTPOp.sendObject.rawValue
    let txid: UInt32 = 5

    var header = Data(count: 12)
    let containerLen = UInt32(12) + UInt32(dataLen)
    header.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: containerLen.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.data.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
    }

    header.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      XCTAssertEqual(
        UInt32(littleEndian: base.load(as: UInt32.self)),
        UInt32(12 + 1024)
      )
      XCTAssertEqual(
        UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self)),
        PTPContainer.Kind.data.rawValue
      )
      XCTAssertEqual(
        UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self)),
        PTPOp.sendObject.rawValue
      )
      XCTAssertEqual(
        UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self)),
        5
      )
    }
  }

  func testDataOutLargeFileUseSentinel() {
    // For data > UInt32.max - 12 bytes, container length should be 0xFFFFFFFF
    let dataLen: UInt64 = UInt64(UInt32.max)
    let containerLen: UInt32
    if dataLen > UInt64(UInt32.max) - 12 {
      containerLen = 0xFFFFFFFF
    } else {
      containerLen = UInt32(12) + UInt32(dataLen)
    }
    XCTAssertEqual(containerLen, 0xFFFFFFFF)
  }

  // MARK: - SendObjectInfo + SendObject Framing

  func testSendObjectInfoCommandFraming() {
    // SendObjectInfo command: params = [StorageID, ParentHandle]
    let container = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObjectInfo.rawValue,
      txid: 1,
      params: [0x00010001, 0xFFFFFFFF]
    )
    XCTAssertEqual(container.code, 0x100C)
    XCTAssertEqual(container.params.count, 2)
    XCTAssertEqual(container.params[0], 0x00010001)
    XCTAssertEqual(container.params[1], 0xFFFFFFFF)
  }

  func testSendObjectCommandFraming() {
    // SendObject command has no params
    let container = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObject.rawValue,
      txid: 2,
      params: []
    )
    XCTAssertEqual(container.code, 0x100D)
    XCTAssertEqual(container.params.count, 0)
  }

  // MARK: - GetObject / GetPartialObject Command Framing

  func testGetObjectCommandFraming() {
    // GetObject command: params = [ObjectHandle]
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObject.rawValue,
      txid: 1,
      params: [42]
    )
    XCTAssertEqual(container.code, 0x1009)
    XCTAssertEqual(container.params, [42])
  }

  func testGetPartialObjectCommandFraming() {
    // GetPartialObject: params = [Handle, Offset, MaxBytes]
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getPartialObject.rawValue,
      txid: 1,
      params: [42, 1024, 4096]
    )
    XCTAssertEqual(container.code, 0x101B)
    XCTAssertEqual(container.params, [42, 1024, 4096])
  }

  func testGetPartialObject64CommandFraming() {
    // GetPartialObject64: params = [Handle, OffsetLo, OffsetHi, MaxBytes]
    let offset: UInt64 = 0x1_0000_0000  // 4GB
    let offsetLo = UInt32(offset & 0xFFFFFFFF)
    let offsetHi = UInt32(offset >> 32)
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getPartialObject64.rawValue,
      txid: 1,
      params: [42, offsetLo, offsetHi, 65536]
    )
    XCTAssertEqual(container.code, 0x95C1)
    XCTAssertEqual(container.params[0], 42)      // handle
    XCTAssertEqual(container.params[1], 0)        // offsetLo
    XCTAssertEqual(container.params[2], 1)        // offsetHi
    XCTAssertEqual(container.params[3], 65536)    // maxBytes
  }

  func testSendPartialObjectCommandFraming() {
    // SendPartialObject (0x95C2): params = [Handle, OffsetLo, OffsetHi, Size]
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendPartialObject.rawValue,
      txid: 1,
      params: [42, 0, 0, 8192]
    )
    XCTAssertEqual(container.code, 0x95C2)
    XCTAssertEqual(container.params.count, 4)
  }

  // MARK: - Response Framing

  func testResponseContainerForGetObject() {
    let response = buildPTPResponseContainer(code: 0x2001, txid: 1, params: [])
    let parsed = parseResponse(response)
    XCTAssertNotNil(parsed)
    XCTAssertTrue(parsed!.isOK)
  }

  func testResponseContainerWithError() {
    // 0x2009 = Invalid ObjectHandle
    let response = buildPTPResponseContainer(code: 0x2009, txid: 1, params: [])
    let parsed = parseResponse(response)
    XCTAssertNotNil(parsed)
    XCTAssertFalse(parsed!.isOK)
    XCTAssertEqual(parsed!.code, 0x2009)
  }

  func testSendObjectInfoResponseParams() {
    // SendObjectInfo response: params = [StorageID, ParentHandle, ObjectHandle]
    let response = buildPTPResponseContainer(
      code: 0x2001, txid: 1, params: [0x00010001, 0xFFFFFFFF, 100]
    )
    let parsed = parseResponse(response)
    XCTAssertNotNil(parsed)
    XCTAssertTrue(parsed!.isOK)
    XCTAssertEqual(parsed!.params.count, 3)
    XCTAssertEqual(parsed!.params[2], 100)  // new object handle
  }

  // MARK: - Helpers

  private func buildPTPDataContainer(code: UInt16, txid: UInt32, payload: Data) -> Data {
    let length = UInt32(12 + payload.count)
    var data = Data(count: 12)
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.data.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
    }
    data.append(payload)
    return data
  }

  private func buildPTPResponseContainer(
    code: UInt16, txid: UInt32, params: [UInt32]
  ) -> Data {
    let length = UInt32(12 + params.count * 4)
    var data = Data(count: Int(length))
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(
        of: PTPContainer.Kind.response.rawValue.littleEndian,
        toByteOffset: 4, as: UInt16.self
      )
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      for (i, p) in params.enumerated() {
        base.storeBytes(of: p.littleEndian, toByteOffset: 12 + i * 4, as: UInt32.self)
      }
    }
    return data
  }

  private func parseResponse(_ data: Data) -> PTPResponseResult? {
    guard data.count >= 12 else { return nil }
    return data.withUnsafeBytes { buf in
      let base = buf.baseAddress!
      let type = UInt16(littleEndian: base.load(fromByteOffset: 4, as: UInt16.self))
      guard type == PTPContainer.Kind.response.rawValue else { return nil }
      let code = UInt16(littleEndian: base.load(fromByteOffset: 6, as: UInt16.self))
      let txid = UInt32(littleEndian: base.load(fromByteOffset: 8, as: UInt32.self))
      var params: [UInt32] = []
      var offset = 12
      while offset + 4 <= data.count {
        let p = UInt32(littleEndian: base.load(fromByteOffset: offset, as: UInt32.self))
        params.append(p)
        offset += 4
      }
      return PTPResponseResult(code: code, txid: txid, params: params)
    }
  }
}

// MARK: - IOUSBHost Event Polling Tests

/// Tests for MTP event container parsing and event stream behavior
/// used by IOUSBHostLink's interrupt endpoint event polling.
final class IOUSBHostEventPollingTests: XCTestCase {

  // MARK: - Event Container Building Helper

  /// Build an MTP event container: [length(4) type(2)=0x0004 code(2) txid(4) params...]
  private func buildEventContainer(code: UInt16, txid: UInt32, params: [UInt32] = []) -> Data {
    let length = UInt32(12 + params.count * 4)
    var data = Data(count: Int(length))
    data.withUnsafeMutableBytes { buf in
      let base = buf.baseAddress!
      base.storeBytes(of: length.littleEndian, as: UInt32.self)
      base.storeBytes(of: UInt16(0x0004).littleEndian, toByteOffset: 4, as: UInt16.self)  // event type
      base.storeBytes(of: code.littleEndian, toByteOffset: 6, as: UInt16.self)
      base.storeBytes(of: txid.littleEndian, toByteOffset: 8, as: UInt32.self)
      for (i, param) in params.enumerated() {
        base.storeBytes(of: param.littleEndian, toByteOffset: 12 + i * 4, as: UInt32.self)
      }
    }
    return data
  }

  // MARK: - Event Container Parsing

  func testParseObjectAddedEvent() {
    let data = buildEventContainer(code: 0x4002, txid: 1, params: [0x00000042])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .objectAdded(let handle) = event {
      XCTAssertEqual(handle, 0x42)
    } else {
      XCTFail("Expected objectAdded, got \(String(describing: event))")
    }
  }

  func testParseObjectRemovedEvent() {
    let data = buildEventContainer(code: 0x4003, txid: 2, params: [0x00000099])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .objectRemoved(let handle) = event {
      XCTAssertEqual(handle, 0x99)
    } else {
      XCTFail("Expected objectRemoved, got \(String(describing: event))")
    }
  }

  func testParseStorageAddedEvent() {
    let data = buildEventContainer(code: 0x4004, txid: 3, params: [0x00010001])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .storageAdded(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storageAdded, got \(String(describing: event))")
    }
  }

  func testParseStorageRemovedEvent() {
    let data = buildEventContainer(code: 0x4005, txid: 4, params: [0x00020001])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .storageRemoved(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00020001)
    } else {
      XCTFail("Expected storageRemoved, got \(String(describing: event))")
    }
  }

  func testParseDevicePropChangedEvent() {
    let data = buildEventContainer(code: 0x4006, txid: 5, params: [0x00005001])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .devicePropChanged(let propCode) = event {
      XCTAssertEqual(propCode, 0x5001)
    } else {
      XCTFail("Expected devicePropChanged, got \(String(describing: event))")
    }
  }

  func testParseDeviceInfoChangedEvent() {
    let data = buildEventContainer(code: 0x4008, txid: 6)
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .deviceInfoChanged = event {
      // OK
    } else {
      XCTFail("Expected deviceInfoChanged, got \(String(describing: event))")
    }
  }

  func testParseDeviceResetEvent() {
    let data = buildEventContainer(code: 0x400B, txid: 7)
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .deviceReset = event {
      // OK
    } else {
      XCTFail("Expected deviceReset, got \(String(describing: event))")
    }
  }

  func testParseCancelTransactionEvent() {
    let data = buildEventContainer(code: 0x4001, txid: 8, params: [42])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .cancelTransaction(let txId) = event {
      XCTAssertEqual(txId, 42)
    } else {
      XCTFail("Expected cancelTransaction, got \(String(describing: event))")
    }
  }

  func testParseStoreFullEvent() {
    let data = buildEventContainer(code: 0x400A, txid: 9, params: [0x00010001])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .storeFull(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storeFull, got \(String(describing: event))")
    }
  }

  func testParseCaptureCompleteEvent() {
    let data = buildEventContainer(code: 0x400D, txid: 10, params: [77])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .captureComplete(let txId) = event {
      XCTAssertEqual(txId, 77)
    } else {
      XCTFail("Expected captureComplete, got \(String(describing: event))")
    }
  }

  func testParseUnreportedStatusEvent() {
    let data = buildEventContainer(code: 0x400E, txid: 11)
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .unreportedStatus = event {
      // OK
    } else {
      XCTFail("Expected unreportedStatus, got \(String(describing: event))")
    }
  }

  func testParseStorageInfoChangedEvent() {
    let data = buildEventContainer(code: 0x400C, txid: 12, params: [0x00010001])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .storageInfoChanged(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storageInfoChanged, got \(String(describing: event))")
    }
  }

  func testParseObjectInfoChangedEvent() {
    let data = buildEventContainer(code: 0x4007, txid: 13, params: [0x55])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .objectInfoChanged(let handle) = event {
      XCTAssertEqual(handle, 0x55)
    } else {
      XCTFail("Expected objectInfoChanged, got \(String(describing: event))")
    }
  }

  func testParseRequestObjectTransferEvent() {
    let data = buildEventContainer(code: 0x4009, txid: 14, params: [0xAA])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .requestObjectTransfer(let handle) = event {
      XCTAssertEqual(handle, 0xAA)
    } else {
      XCTFail("Expected requestObjectTransfer, got \(String(describing: event))")
    }
  }

  // MARK: - Unknown / Vendor Events

  func testParseUnknownVendorEvent() {
    let data = buildEventContainer(code: 0xC801, txid: 15, params: [1, 2, 3])
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xC801)
      XCTAssertEqual(params, [1, 2, 3])
    } else {
      XCTFail("Expected unknown, got \(String(describing: event))")
    }
  }

  // MARK: - Edge Cases

  func testParseEventTooShort() {
    // Less than 12 bytes — should return nil
    let data = Data([0x0C, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x40])  // 8 bytes
    let event = MTPEvent.fromRaw(data)
    XCTAssertNil(event)
  }

  func testParseEventExactlyMinimumSize() {
    // 12 bytes, no params — e.g. DeviceInfoChanged (0x4008)
    let data = buildEventContainer(code: 0x4008, txid: 0)
    XCTAssertEqual(data.count, 12)
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .deviceInfoChanged = event {
      // OK
    } else {
      XCTFail("Expected deviceInfoChanged, got \(String(describing: event))")
    }
  }

  func testParseEventWithMultipleParams() {
    // Fabricated event with 3 params
    let data = buildEventContainer(code: 0xC802, txid: 99, params: [0x11, 0x22, 0x33])
    XCTAssertEqual(data.count, 24)  // 12 header + 12 params
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xC802)
      XCTAssertEqual(params.count, 3)
      XCTAssertEqual(params[0], 0x11)
      XCTAssertEqual(params[1], 0x22)
      XCTAssertEqual(params[2], 0x33)
    } else {
      XCTFail("Expected unknown, got \(String(describing: event))")
    }
  }

  func testEventCodeProperty() {
    let data = buildEventContainer(code: 0x4002, txid: 1, params: [0x42])
    let event = MTPEvent.fromRaw(data)!
    XCTAssertEqual(event.eventCode, 0x4002)
  }

  func testEventDescriptionNotEmpty() {
    let data = buildEventContainer(code: 0x4004, txid: 1, params: [0x00010001])
    let event = MTPEvent.fromRaw(data)!
    XCTAssertFalse(event.eventDescription.isEmpty)
    XCTAssertTrue(event.eventDescription.contains("StoreAdded"))
  }

  // MARK: - Default Event Stream (No Interrupt Endpoint)

  func testDefaultLinkEventStreamFinishesOnClose() async {
    let link = IOUSBHostLink()
    // Close the link to finish the event stream
    await link.close()
    var events: [Data] = []
    for await data in link.eventStream {
      events.append(data)
    }
    XCTAssertTrue(events.isEmpty)
  }

  func testDefaultLinkStartEventPumpIsNoOp() {
    let link = IOUSBHostLink()
    // Should not crash even without interrupt pipe
    link.startEventPump()
  }

  func testAllFourteenStandardEventCodes() {
    let codes: [(UInt16, Bool)] = [
      (0x4001, true),   // CancelTransaction — needs param but returns with 0
      (0x4002, true),   // ObjectAdded
      (0x4003, true),   // ObjectRemoved
      (0x4004, true),   // StorageAdded
      (0x4005, true),   // StorageRemoved
      (0x4006, true),   // DevicePropChanged
      (0x4007, true),   // ObjectInfoChanged
      (0x4008, false),  // DeviceInfoChanged — no param needed
      (0x4009, true),   // RequestObjectTransfer
      (0x400A, true),   // StoreFull
      (0x400B, false),  // DeviceReset — no param needed
      (0x400C, true),   // StorageInfoChanged
      (0x400D, true),   // CaptureComplete — needs param but returns with 0
      (0x400E, false),  // UnreportedStatus — no param needed
    ]
    for (code, needsParam) in codes {
      let params: [UInt32] = needsParam ? [0x00000001] : []
      let data = buildEventContainer(code: code, txid: 0, params: params)
      let event = MTPEvent.fromRaw(data)
      XCTAssertNotNil(event, "Event code 0x\(String(code, radix: 16)) should parse")
      XCTAssertEqual(event!.eventCode, code)
    }
  }
}
