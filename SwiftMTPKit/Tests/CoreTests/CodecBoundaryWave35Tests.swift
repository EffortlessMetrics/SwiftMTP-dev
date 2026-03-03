// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

// MARK: - Codec Boundary Wave 35 Tests

final class CodecBoundaryWave35Tests: XCTestCase {

  // MARK: - Zero-length PTP String

  func testZeroLengthPTPStringDecodesAsEmpty() {
    // charCount byte = 0 means empty string
    let data = Data([0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Zero-length string should return empty or nil; either is acceptable
    if let result = result {
      XCTAssertTrue(result.isEmpty, "Zero-length PTP string should be empty")
    }
  }

  func testSingleNullCharPTPStringDecode() {
    // charCount = 1, single null terminator (U+0000 in UTF-16LE)
    let data = Data([0x01, 0x00, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    if let result = result {
      XCTAssertTrue(result.isEmpty || result == "\0",
        "Single null-char PTP string should be empty or contain null")
    }
  }

  // MARK: - Max-length PTP Container (4GB boundary)

  func testMaxLengthContainerField() {
    // Container with length = UInt32.max (0xFFFFFFFF)
    let container = PTPContainer(
      length: UInt32.max,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 1
    )
    XCTAssertEqual(container.length, UInt32.max)

    // Encode and verify the length field round-trips
    var buf = [UInt8](repeating: 0, count: 12)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)

    // Verify little-endian length bytes
    XCTAssertEqual(buf[0], 0xFF)
    XCTAssertEqual(buf[1], 0xFF)
    XCTAssertEqual(buf[2], 0xFF)
    XCTAssertEqual(buf[3], 0xFF)
  }

  func testContainerWithFiveMaxParams() {
    let params: [UInt32] = Array(repeating: UInt32.max, count: 5)
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: UInt32.max,
      params: params
    )
    // 12 header + 5*4 params = 32 bytes
    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 32)
  }

  // MARK: - Invalid UTF-16 Surrogate Pairs

  func testUnpairedHighSurrogateInPTPString() {
    // charCount=2, high surrogate 0xD800 followed by non-surrogate 0x0041 ('A')
    let data = Data([0x02, 0x00, 0xD8, 0x41, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Should either return nil or a replacement character string; must not crash
    _ = result  // No crash = pass
  }

  func testUnpairedLowSurrogateInPTPString() {
    // charCount=1, lone low surrogate 0xDC00
    let data = Data([0x01, 0x00, 0xDC])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Should handle gracefully (nil or replacement)
    _ = result
  }

  func testSentinelCharCountReturnsNil() {
    // charCount = 0xFF is the invalid sentinel
    let data = Data([0xFF, 0x41, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNil(result, "0xFF sentinel charCount should return nil")
  }

  // MARK: - Truncated Container Headers

  func testTruncatedContainerUnder12Bytes() {
    // Only 8 bytes — less than the 12-byte minimum header
    let data = Data([0x0C, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10])
    var reader = PTPReader(data: data)

    // Reading a full header's worth of fields: length + type + code + txid
    let length = reader.u32()
    let type = reader.u16()
    // Should fail to read remaining fields since only 8 bytes available
    let code = reader.u16()
    let txid = reader.u32()

    XCTAssertNotNil(length)
    XCTAssertNotNil(type)
    XCTAssertNil(txid, "Truncated header should fail to read txid")
    // code may or may not be readable depending on exact byte boundary
    _ = code
  }

  func testEmptyDataReaderReturnsNil() {
    let data = Data()
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.u8())
    XCTAssertNil(reader.u16())
    XCTAssertNil(reader.u32())
    XCTAssertNil(reader.u64())
    XCTAssertNil(reader.string())
    XCTAssertEqual(reader.o, 0, "Offset should not advance on failed reads")
  }

  // MARK: - Container Length Field Mismatch

  func testContainerLengthMismatchWithPayload() {
    // Container claims length=100 but only 12 bytes encoded
    let container = PTPContainer(
      length: 100,
      type: PTPContainer.Kind.response.rawValue,
      code: 0x2001,
      txid: 42
    )
    var buf = [UInt8](repeating: 0, count: 12)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12, "Encode always writes actual header regardless of length field")

    // The length field in the buffer should be 100 (as specified), not 12
    let encodedLength = UInt32(buf[0]) | (UInt32(buf[1]) << 8)
      | (UInt32(buf[2]) << 16) | (UInt32(buf[3]) << 24)
    XCTAssertEqual(encodedLength, 100)
  }

  func testContainerLengthZero() {
    let container = PTPContainer(
      length: 0,
      type: PTPContainer.Kind.data.rawValue,
      code: 0x1001,
      txid: 1
    )
    var buf = [UInt8](repeating: 0, count: 12)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)

    let encodedLength = UInt32(buf[0]) | (UInt32(buf[1]) << 8)
      | (UInt32(buf[2]) << 16) | (UInt32(buf[3]) << 24)
    XCTAssertEqual(encodedLength, 0, "Zero length should round-trip")
  }

  // MARK: - Operation Code Boundary

  func testOperationCodeAtUInt16Max() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: UInt16.max,
      txid: 1
    )
    var buf = [UInt8](repeating: 0, count: 12)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)

    // Verify code field (bytes 6-7) is 0xFFFF little-endian
    XCTAssertEqual(buf[6], 0xFF)
    XCTAssertEqual(buf[7], 0xFF)
  }

  func testOperationCodeZero() {
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: 0x0000,
      txid: 0
    )
    var buf = [UInt8](repeating: 0, count: 12)
    _ = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(buf[6], 0x00)
    XCTAssertEqual(buf[7], 0x00)
  }

  // MARK: - PTPReader Edge Cases

  func testReaderValueWithUnknownDataType() {
    // Data type 0x0000 is not a recognized PTP data type
    let data = Data([0x42])
    var reader = PTPReader(data: data)
    let value = reader.value(dt: 0x0000)
    // Unknown type should return nil or a fallback; must not crash
    _ = value
  }

  func testReaderStringWithMaxCharCount() {
    // charCount = 254 (max valid, since 0xFF is sentinel)
    var payload = Data([0xFE])  // 254 chars
    // Append 254 UTF-16LE code units (508 bytes) of 'A'
    for _ in 0..<254 {
      payload.append(contentsOf: [0x41, 0x00])
    }
    var offset = 0
    let result = PTPString.parse(from: payload, at: &offset)
    XCTAssertNotNil(result, "Max-length PTP string (254 chars) should parse")
    if let result = result {
      // 254 chars includes null terminator, so actual string length is 253
      XCTAssertTrue(result.count >= 253, "Should have at least 253 characters")
    }
  }

  func testReaderBytesExactBoundary() {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    var reader = PTPReader(data: data)
    let exact = reader.bytes(4)
    XCTAssertNotNil(exact, "Should read exactly available bytes")
    XCTAssertEqual(exact?.count, 4)

    // Now there's nothing left
    let over = reader.bytes(1)
    XCTAssertNil(over, "Should return nil when no bytes remain")
  }
}
