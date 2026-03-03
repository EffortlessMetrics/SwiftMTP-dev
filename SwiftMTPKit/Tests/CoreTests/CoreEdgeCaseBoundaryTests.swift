// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import XCTest

@testable import SwiftMTPCore

/// Edge-case and boundary-condition tests for PTPCodec, MTPEvent parsing,
/// transaction ID overflow, and DeviceState transitions.
final class CoreEdgeCaseBoundaryTests: XCTestCase {

  // MARK: - PTPCodec Boundary Conditions

  func testEncodeContainerToExactlySizedBuffer() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 1
    )
    var buffer = [UInt8](repeating: 0xAA, count: 12)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)
    XCTAssertFalse(buffer.contains(0xAA))
  }

  func testDecodeEmptyDataReturnsNilForAllReaderMethods() {
    var reader = PTPReader(data: Data())
    XCTAssertNil(reader.u8())
    XCTAssertNil(reader.u16())
    XCTAssertNil(reader.u32())
    XCTAssertNil(reader.u64())
    XCTAssertNil(reader.bytes(1))
    XCTAssertNil(reader.string())
    XCTAssertEqual(reader.o, 0, "Offset must not advance on failed reads")
  }

  func testReaderOffsetDoesNotAdvancePastEndOfData() {
    var reader = PTPReader(data: Data([0x01, 0x02, 0x03]))
    XCTAssertNil(reader.u32())
    XCTAssertEqual(reader.o, 0, "Offset must not advance on incomplete read")
    XCTAssertEqual(reader.u16(), 0x0201)
    XCTAssertEqual(reader.o, 2)
  }

  func testMaxLengthPTPStringEncode() {
    let longStr = String(repeating: "A", count: 300)
    let encoded = PTPString.encode(longStr)
    // Encode truncates to 255 (254 chars + null). But charCount 0xFF is
    // the parser's sentinel for "invalid", so round-trip returns nil.
    XCTAssertEqual(encoded[0], 255)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNil(decoded, "charCount=0xFF is the invalid sentinel; parse must return nil")
  }

  func testPTPStringEncodeNearMaxRoundTrips() {
    // 253 chars → charCount = 254 (fits under 0xFF sentinel)
    let nearMax = String(repeating: "B", count: 253)
    let encoded = PTPString.encode(nearMax)
    XCTAssertEqual(encoded[0], 254)  // 253 + null
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded, nearMax)
  }

  func testPTPStringParseWithCharCountFF() {
    let data = Data([0xFF, 0x41, 0x00, 0x00, 0x00])
    var offset = 0
    XCTAssertNil(PTPString.parse(from: data, at: &offset))
  }

  func testPTPStringParseTruncatedPayload() {
    let data = Data([0x05, 0x41, 0x00])
    var offset = 0
    XCTAssertNil(PTPString.parse(from: data, at: &offset))
  }

  func testContainerWithSixParamsEncodesExtraParam() {
    let container = PTPContainer(
      length: 36,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 1,
      params: [1, 2, 3, 4, 5, 6]
    )
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 36)
  }

  func testContainerKindEventRawValue() {
    XCTAssertEqual(PTPContainer.Kind.event.rawValue, 4)
  }

  // MARK: - MTPEvent Parsing Edge Cases

  func testEventFromRawTooShortReturnsNil() {
    let short = Data([0x0C, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x40])
    XCTAssertNil(MTPEvent.fromRaw(short))
  }

  func testEventFromRawExactMinimumLength() {
    var data = Data(repeating: 0, count: 12)
    data[0] = 0x0C; data[4] = 0x04; data[6] = 0x08; data[7] = 0x40; data[8] = 0x01
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .deviceInfoChanged = event {} else {
      XCTFail("Expected deviceInfoChanged, got \(String(describing: event))")
    }
  }

  func testEventFromRawUnknownCodeReturnsUnknown() {
    var data = Data(repeating: 0, count: 16)
    data[0] = 0x10; data[4] = 0x04; data[6] = 0xEF; data[7] = 0xBE; data[8] = 0x01
    data[12] = 0x42
    let event = MTPEvent.fromRaw(data)
    XCTAssertNotNil(event)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xBEEF)
      XCTAssertEqual(params.count, 1)
      XCTAssertEqual(params[0], 0x42)
    } else {
      XCTFail("Expected unknown event, got \(String(describing: event))")
    }
  }

  func testEventFromRawUnknownCodeWithNoParams() {
    var data = Data(repeating: 0, count: 12)
    data[0] = 0x0C; data[4] = 0x04; data[6] = 0xFF; data[7] = 0xFF; data[8] = 0x01
    let event = MTPEvent.fromRaw(data)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xFFFF)
      XCTAssertTrue(params.isEmpty)
    } else {
      XCTFail("Expected unknown event, got \(String(describing: event))")
    }
  }

  func testEventObjectAddedMissingParamReturnsNil() {
    var data = Data(repeating: 0, count: 12)
    data[0] = 0x0C; data[4] = 0x04; data[6] = 0x02; data[7] = 0x40; data[8] = 0x01
    XCTAssertNil(MTPEvent.fromRaw(data))
  }

  func testEventObjectAddedWithParam() {
    var data = Data(repeating: 0, count: 16)
    data[0] = 0x10; data[4] = 0x04; data[6] = 0x02; data[7] = 0x40; data[8] = 0x01
    data[12] = 0x07
    let event = MTPEvent.fromRaw(data)
    if case .objectAdded(let handle) = event {
      XCTAssertEqual(handle, 7)
    } else {
      XCTFail("Expected objectAdded, got \(String(describing: event))")
    }
  }

  func testEventObjectRemovedWithParam() {
    var data = Data(repeating: 0, count: 16)
    data[0] = 0x10; data[4] = 0x04; data[6] = 0x03; data[7] = 0x40; data[8] = 0x01
    data[12] = 0x0A
    let event = MTPEvent.fromRaw(data)
    if case .objectRemoved(let handle) = event {
      XCTAssertEqual(handle, 0x0A)
    } else {
      XCTFail("Expected objectRemoved, got \(String(describing: event))")
    }
  }

  func testEventStorageAddedWithParam() {
    var data = Data(repeating: 0, count: 16)
    data[0] = 0x10; data[4] = 0x04; data[6] = 0x04; data[7] = 0x40; data[8] = 0x01
    data[12] = 0x01; data[13] = 0x00; data[14] = 0x01; data[15] = 0x00
    let event = MTPEvent.fromRaw(data)
    if case .storageAdded(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storageAdded, got \(String(describing: event))")
    }
  }

  func testEventWithMultipleParams() {
    var data = Data(repeating: 0, count: 24)
    data[0] = 0x18; data[4] = 0x04; data[6] = 0x01; data[7] = 0xFF; data[8] = 0x01
    data[12] = 0x0A; data[16] = 0x0B; data[20] = 0x0C
    let event = MTPEvent.fromRaw(data)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xFF01)
      XCTAssertEqual(params, [0x0A, 0x0B, 0x0C])
    } else {
      XCTFail("Expected unknown event with 3 params")
    }
  }

  // MARK: - Transaction ID Overflow / Wraparound

  func testTransactionIDMaxValueContainer() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: 0xFFFFFFFF
    )
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)
    XCTAssertEqual(buffer[8], 0xFF)
    XCTAssertEqual(buffer[9], 0xFF)
    XCTAssertEqual(buffer[10], 0xFF)
    XCTAssertEqual(buffer[11], 0xFF)
  }

  func testTransactionIDWraparoundArithmetic() {
    let maxTxID: UInt32 = 0xFFFFFFFF
    let wrapped = maxTxID &+ 1
    XCTAssertEqual(wrapped, 0)
    let nextUsable: UInt32 = wrapped == 0 ? 1 : wrapped
    XCTAssertEqual(nextUsable, 1)
  }

  func testTransactionIDZeroEncodesCorrectly() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 0
    )
    var buffer = [UInt8](repeating: 0xFF, count: 64)
    _ = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(buffer[8], 0x00)
    XCTAssertEqual(buffer[9], 0x00)
    XCTAssertEqual(buffer[10], 0x00)
    XCTAssertEqual(buffer[11], 0x00)
  }

  func testSequentialTransactionIDsEncodeDistinctly() {
    var buffers: [[UInt8]] = []
    for txid: UInt32 in [1, 2, 0xFFFFFFFE, 0xFFFFFFFF] {
      let c = PTPContainer(
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.openSession.rawValue,
        txid: txid
      )
      var buf = [UInt8](repeating: 0, count: 16)
      _ = buf.withUnsafeMutableBufferPointer { ptr in
        c.encode(into: ptr.baseAddress!)
      }
      buffers.append(Array(buf[8...11]))
    }
    let unique = Set(buffers.map { $0.description })
    XCTAssertEqual(unique.count, 4)
  }

  // MARK: - Session State Transitions (DeviceState)

  func testDoubleConnectTransition() {
    var state: DeviceState = .connected
    state = .connected
    XCTAssertEqual(state, .connected)
    XCTAssertFalse(state.isDisconnected)
  }

  func testDisconnectWithoutConnecting() {
    var state: DeviceState = .disconnected
    state = .disconnecting
    XCTAssertFalse(state.isDisconnected)
    state = .disconnected
    XCTAssertTrue(state.isDisconnected)
  }

  func testErrorToErrorTransition() {
    var state: DeviceState = .error(.timeout)
    state = .error(.busy)
    if case .error(let err) = state {
      XCTAssertEqual(err, .busy)
    } else {
      XCTFail("Expected error state")
    }
  }

  func testTransferringToDisconnectedSkippingConnected() {
    var state: DeviceState = .transferring
    XCTAssertTrue(state.isTransferring)
    state = .disconnected
    XCTAssertTrue(state.isDisconnected)
    XCTAssertFalse(state.isTransferring)
  }

  func testRapidStateChurnDoesNotCorruptState() {
    var state: DeviceState = .disconnected
    for _ in 0..<100 {
      state = .connecting
      state = .connected
      state = .transferring
      state = .error(.timeout)
      state = .connecting
      state = .connected
      state = .disconnecting
      state = .disconnected
    }
    XCTAssertTrue(state.isDisconnected)
  }

  // MARK: - PTPDeviceInfo Parsing Edge Cases

  func testDeviceInfoParseFromEmptyDataReturnsNil() {
    XCTAssertNil(PTPDeviceInfo.parse(from: Data()))
  }

  func testDeviceInfoParseFromTruncatedDataReturnsNil() {
    let data = Data([0x00, 0x01])
    XCTAssertNil(PTPDeviceInfo.parse(from: data))
  }

  // MARK: - PTPPropList Parse Edge Cases

  func testPropListParseFromEmptyDataReturnsNil() {
    XCTAssertNil(PTPPropList.parse(from: Data()))
  }

  func testPropListParseZeroEntries() {
    let data = Data([0x00, 0x00, 0x00, 0x00])
    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result!.entries.count, 0)
  }

  func testPropListParseTruncatedEntry() {
    let data = Data([0x01, 0x00, 0x00, 0x00, 0xFF])
    XCTAssertNil(PTPPropList.parse(from: data))
  }

  // MARK: - PTPResponseCode Edge Cases

  func testResponseCodeDescribeForAllKnownCodes() {
    let knownCodes: [UInt16] = [
      0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
      0x2009, 0x200A, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2010,
      0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2016, 0x2017, 0x2018,
      0x2019, 0x201A, 0x201B, 0x201C, 0x201D, 0x201E, 0x201F, 0x2020,
    ]
    for code in knownCodes {
      let name = PTPResponseCode.name(for: code)
      XCTAssertNotNil(name, "Code 0x\(String(format: "%04X", code)) should have a known name")
      let desc = PTPResponseCode.describe(code)
      XCTAssertTrue(desc.contains("0x"), "Description should contain hex prefix")
    }
  }

  func testResponseCodeDescribeForVendorCode() {
    let desc = PTPResponseCode.describe(0xA001)
    XCTAssertTrue(desc.contains("Unknown"))
  }

  // MARK: - MTPError Edge Cases

  func testMTPErrorSessionAlreadyOpenDetection() {
    let err = MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
    XCTAssertTrue(err.isSessionAlreadyOpen)
  }

  func testMTPErrorNonSessionAlreadyOpenCode() {
    let err = MTPError.protocolError(code: 0x2019, message: "DeviceBusy")
    XCTAssertFalse(err.isSessionAlreadyOpen)
  }

  func testMTPErrorNonProtocolErrorIsNotSessionAlreadyOpen() {
    XCTAssertFalse(MTPError.timeout.isSessionAlreadyOpen)
    XCTAssertFalse(MTPError.busy.isSessionAlreadyOpen)
    XCTAssertFalse(MTPError.sessionBusy.isSessionAlreadyOpen)
  }

  // MARK: - PTPReader.validateCount

  func testValidateCountAtBoundary() {
    XCTAssertNoThrow(try PTPReader.validateCount(PTPReader.maxSafeCount))
    XCTAssertThrowsError(try PTPReader.validateCount(PTPReader.maxSafeCount + 1))
  }

  func testValidateCountZero() {
    XCTAssertNoThrow(try PTPReader.validateCount(0))
  }

  // MARK: - PTPValue via PTPReader for Array Types

  func testReaderValueArrayWithZeroCount() {
    let data = Data([0x00, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    let val = reader.value(dt: 0x4006)
    if case .array(let elements) = val {
      XCTAssertTrue(elements.isEmpty)
    } else {
      XCTFail("Expected empty array, got \(String(describing: val))")
    }
  }

  func testReaderValueStringType() {
    let encoded = PTPString.encode("test")
    var reader = PTPReader(data: encoded)
    let val = reader.value(dt: 0xFFFF)
    if case .string(let s) = val {
      XCTAssertEqual(s, "test")
    } else {
      XCTFail("Expected string value")
    }
  }

  func testReaderValueUnknownDataTypeReturnsNil() {
    let data = Data([0x42])
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.value(dt: 0x00FF))
  }
}
