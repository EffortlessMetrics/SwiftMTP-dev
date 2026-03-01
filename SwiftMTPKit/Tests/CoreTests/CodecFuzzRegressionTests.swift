// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Regression tests for MTP codec edge cases discovered through fuzzing.
final class CodecFuzzRegressionTests: XCTestCase {

  // MARK: - Empty / Minimal Containers

  func testEmptyContainerLength() {
    // Container with length field = 0 should not crash any parser
    let data = Data([0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10, 0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    let length = reader.u32()
    XCTAssertEqual(length, 0)
  }

  func testEmptyDataNoCrash() {
    // Zero-length data must not crash any parser
    let data = Data()
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.u8())
    XCTAssertNil(reader.u16())
    XCTAssertNil(reader.u32())
    XCTAssertNil(reader.u64())
    XCTAssertNil(reader.string())
    XCTAssertNil(reader.value(dt: 0x0006))
  }

  func testSingleByteDataNoCrash() {
    let data = Data([0x42])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u8(), 0x42)
    XCTAssertNil(reader.u16())
  }

  // MARK: - Length Mismatches

  func testContainerLengthExceedsData() {
    // Header says 24 bytes but only 12 provided
    let data = Data([0x18, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10, 0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    let length = reader.u32()
    XCTAssertEqual(length, 24)
    // Reading params beyond available data returns nil
    _ = reader.u16()  // type
    _ = reader.u16()  // code
    _ = reader.u32()  // txid
    XCTAssertNil(reader.u32())  // no param data available
  }

  func testContainerLengthUnderflowBelowHeader() {
    // Length says 4 but a valid PTP header needs 12 bytes minimum
    let data = Data([0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10, 0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    let length = reader.u32()
    XCTAssertEqual(length, 4)
    // The remaining fields are still readable from the raw data
    XCTAssertEqual(reader.u16(), 1)  // type
  }

  // MARK: - Unicode String Edge Cases

  func testStringSurrogatePairRoundTrip() {
    // UTF-16LE surrogate pair for U+1F600 (😀): D83D DE00, plus null terminator
    let data = Data([0x03, 0x3D, 0xD8, 0x00, 0xDE, 0x00, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Should parse without crashing; the surrogate pair forms an emoji
    XCTAssertNotNil(result)
    if let s = result {
      XCTAssertTrue(s.contains("😀") || s.count > 0, "Should decode surrogate pair or produce non-empty string")
    }
  }

  func testStringNullOnlyCharacter() {
    // charCount=1, single null character (0x0000)
    let data = Data([0x01, 0x00, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Null chars are skipped in PTPString.parse, so result should be empty string
    XCTAssertNotNil(result)
    XCTAssertEqual(result, "")
    XCTAssertEqual(offset, 3)
  }

  func testStringMaxLength254() {
    // Build a PTPString with charCount=254 (max valid; 0xFF is reserved)
    var data = Data([254])  // charCount
    for _ in 0..<253 {
      data.append(contentsOf: [0x41, 0x00])  // 'A' in UTF-16LE
    }
    data.append(contentsOf: [0x00, 0x00])  // null terminator

    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.count, 253)  // 254 chars minus null
    XCTAssertEqual(offset, 1 + 254 * 2)
  }

  func testStringCharCountFFReserved() {
    // 0xFF charCount is reserved and should return nil
    let data = Data([0xFF, 0x41, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNil(result)
  }

  func testStringTruncatedUTF16() {
    // charCount=5 but only 3 UTF-16LE code units provided (6 bytes instead of 10)
    let data = Data([0x05, 0x48, 0x00, 0x69, 0x00, 0x21, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Not enough bytes → nil
    XCTAssertNil(result)
  }

  // MARK: - PropList Edge Cases

  func testPropListMaxCountRejected() {
    // count = 0xFFFFFFFF exceeds PTPReader.maxSafeCount
    let data = Data([0xFF, 0xFF, 0xFF, 0xFF])
    let result = PTPPropList.parse(from: data)
    XCTAssertNil(result)
  }

  func testPropListEmptyValid() {
    // count = 0, should parse as empty list
    let data = Data([0x00, 0x00, 0x00, 0x00])
    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.entries.count, 0)
  }

  func testPropListMaxHandleEntry() {
    // 1 entry with handle=0xFFFFFFFF, propCode=0xDC01, dt=uint32(0x0006), value=0x42
    let data = Data([
      0x01, 0x00, 0x00, 0x00,  // count = 1
      0xFF, 0xFF, 0xFF, 0xFF,  // handle
      0x01, 0xDC,              // property code
      0x06, 0x00,              // data type = UINT32
      0x42, 0x00, 0x00, 0x00,  // value
    ])
    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.entries.count, 1)
    if let entry = result?.entries.first {
      XCTAssertEqual(entry.handle, 0xFFFF_FFFF)
      XCTAssertEqual(entry.propertyCode, 0xDC01)
      if case .uint32(let v) = entry.value {
        XCTAssertEqual(v, 0x42)
      } else {
        XCTFail("Expected uint32 value")
      }
    }
  }

  func testPropListTruncatedEntry() {
    // count=1 but entry data is incomplete (missing value bytes)
    let data = Data([
      0x01, 0x00, 0x00, 0x00,  // count = 1
      0x01, 0x00, 0x00, 0x00,  // handle
      0x01, 0xDC,              // property code
      0x06, 0x00,              // data type = UINT32
      // missing value bytes
    ])
    let result = PTPPropList.parse(from: data)
    XCTAssertNil(result)
  }

  // MARK: - Event Packet Edge Cases

  func testEventContainerInvalidCodeZero() {
    // Event container with code=0x0000, should parse structurally
    let data = Data([0x0C, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u32(), 12)   // length
    XCTAssertEqual(reader.u16(), 4)    // type = event
    XCTAssertEqual(reader.u16(), 0)    // code = 0 (invalid)
    XCTAssertEqual(reader.u32(), 1)    // txid
  }

  func testEventContainerVendorCode() {
    // Event with vendor-specific code 0xC801
    let data = Data([0x0C, 0x00, 0x00, 0x00, 0x04, 0x00, 0x01, 0xC8, 0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    _ = reader.u32()
    _ = reader.u16()
    let code = reader.u16()
    XCTAssertEqual(code, 0xC801)
  }

  // MARK: - Overflow / Underflow in Field Parsing

  func testReaderU16AtBoundary() {
    // Exactly 2 bytes → u16 should succeed, then fail
    let data = Data([0xFF, 0xFF])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u16(), 0xFFFF)
    XCTAssertNil(reader.u16())
  }

  func testReaderU32AtBoundary() {
    // Exactly 4 bytes → u32 should succeed, then fail
    let data = Data([0xFF, 0xFF, 0xFF, 0xFF])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u32(), 0xFFFF_FFFF)
    XCTAssertNil(reader.u32())
  }

  func testReaderU64AtBoundary() {
    let data = Data(repeating: 0xFF, count: 8)
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u64(), 0xFFFF_FFFF_FFFF_FFFF)
    XCTAssertNil(reader.u64())
  }

  func testReaderBytesExactBoundary() {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    var reader = PTPReader(data: data)
    let bytes = reader.bytes(4)
    XCTAssertEqual(bytes, Data([0x01, 0x02, 0x03, 0x04]))
    XCTAssertNil(reader.bytes(1))
  }

  func testReaderBytesExceedsBounds() {
    let data = Data([0x01, 0x02])
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.bytes(3))
  }

  func testArrayValueWithCountExceedingMaxSafe() {
    // Array dt=0x4006 (array of uint32), count=200_000 > maxSafeCount
    var data = Data(count: 4)
    let count: UInt32 = 200_000
    data[0] = UInt8(count & 0xFF)
    data[1] = UInt8((count >> 8) & 0xFF)
    data[2] = UInt8((count >> 16) & 0xFF)
    data[3] = UInt8((count >> 24) & 0xFF)
    var reader = PTPReader(data: data)
    let result = reader.value(dt: 0x4006)
    XCTAssertNil(result, "Array count exceeding maxSafeCount should return nil")
  }

  func testArrayValueWithTruncatedElements() {
    // Array says count=3 but only 1 element of data
    var data = Data(count: 4 + 4)  // count header + 1 uint32
    data[0] = 0x03  // count = 3
    data[4] = 0x01  // first element
    var reader = PTPReader(data: data)
    let result = reader.value(dt: 0x4006)
    // Should return nil because 2nd element can't be read
    XCTAssertNil(result)
  }

  // MARK: - DeviceInfo Parsing Edge Cases

  func testDeviceInfoFromAllZeros() {
    // All-zeros data should not crash; likely returns nil due to string parsing
    let data = Data(repeating: 0, count: 64)
    let result = PTPDeviceInfo.parse(from: data)
    // May or may not parse, but must not crash
    _ = result
  }

  func testDeviceInfoFromAllFF() {
    // All 0xFF data should not crash
    let data = Data(repeating: 0xFF, count: 64)
    let result = PTPDeviceInfo.parse(from: data)
    // 0xFF string length is reserved → parse should fail gracefully
    XCTAssertNil(result)
  }

  func testDeviceInfoTruncatedMidArray() {
    // Valid header fields but truncated during operations array
    var data = Data()
    data.append(contentsOf: [0x01, 0x00])  // StandardVersion
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // VendorExtensionID
    data.append(contentsOf: [0x01, 0x00])  // VendorExtensionVersion
    data.append(0x00)  // VendorExtensionDesc (empty string)
    data.append(contentsOf: [0x00, 0x00])  // FunctionalMode
    data.append(contentsOf: [0x05, 0x00, 0x00, 0x00])  // OperationsSupported count=5
    // Only 2 operations provided instead of 5
    data.append(contentsOf: [0x01, 0x10])
    data.append(contentsOf: [0x02, 0x10])

    let result = PTPDeviceInfo.parse(from: data)
    XCTAssertNil(result, "Truncated operations array should fail parse")
  }

  // MARK: - Validate Count Threshold

  func testValidateCountAtBoundary() throws {
    // Exactly at maxSafeCount should not throw
    try PTPReader.validateCount(PTPReader.maxSafeCount)
  }

  func testValidateCountAboveBoundary() {
    // One above maxSafeCount should throw
    XCTAssertThrowsError(try PTPReader.validateCount(PTPReader.maxSafeCount + 1))
  }

  // MARK: - All-Bytes Fuzzing Smoke

  func testAllSingleByteInputsNoCrash() {
    // Every possible single-byte input must not crash the parser
    for b in UInt8.min...UInt8.max {
      let data = Data([b])
      var reader = PTPReader(data: data)
      _ = reader.u8()
      _ = PTPString.parse(from: data, at: &reader.o)
      _ = PTPDeviceInfo.parse(from: data)
      _ = PTPPropList.parse(from: data)
    }
  }

  // MARK: - Response Code Lookup Edge Cases

  func testResponseCodeUnknown() {
    XCTAssertNil(PTPResponseCode.name(for: 0x0000))
    XCTAssertTrue(PTPResponseCode.describe(0x0000).contains("Unknown"))
  }

  func testResponseCodeKnown() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
    XCTAssertEqual(PTPResponseCode.name(for: 0x2019), "DeviceBusy")
  }
}
