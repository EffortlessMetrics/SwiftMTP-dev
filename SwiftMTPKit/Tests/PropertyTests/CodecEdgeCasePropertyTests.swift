// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

/// Property tests for codec edge cases: boundary values, multi-field sequences, and PTPString.
final class CodecEdgeCasePropertyTests: XCTestCase {

  // MARK: - UInt16 Round-Trip

  /// UInt16 encode/decode must round-trip for all values including 0 and UInt16.max.
  func testUInt16RoundTrip() {
    property("UInt16 round-trips through MTPDataEncoder/MTPDataDecoder")
      <- forAll { (value: UInt16) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt16() else { return false }
        return decoded == value
      }
  }

  /// UInt16 boundary values encode and decode correctly.
  func testUInt16BoundaryValues() {
    let boundaries: [UInt16] = [0, 1, UInt16.max - 1, UInt16.max, 0x00FF, 0xFF00]
    for value in boundaries {
      var enc = MTPDataEncoder()
      enc.append(value)
      var dec = MTPDataDecoder(data: enc.encodedData)
      XCTAssertEqual(dec.readUInt16(), value, "Failed for boundary value \(value)")
    }
  }

  // MARK: - UInt32 Boundary Values

  /// UInt32 encode/decode for edge-case values.
  func testUInt32BoundaryRoundTrip() {
    let boundaries: [UInt32] = [0, 1, UInt32.max - 1, UInt32.max, 0x0000FFFF, 0xFFFF0000]
    for value in boundaries {
      var enc = MTPDataEncoder()
      enc.append(value)
      var dec = MTPDataDecoder(data: enc.encodedData)
      XCTAssertEqual(dec.readUInt32(), value, "Failed for boundary value \(value)")
    }
  }

  // MARK: - UInt64 Round-Trip

  /// UInt64 encode/decode must round-trip for all values.
  func testUInt64RoundTrip() {
    property("UInt64 round-trips through MTPDataEncoder/MTPDataDecoder")
      <- forAll { (value: UInt64) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt64() else { return false }
        return decoded == value
      }
  }

  /// UInt64 boundary values.
  func testUInt64BoundaryRoundTrip() {
    let boundaries: [UInt64] = [
      0, 1, UInt64.max, UInt64.max - 1,
      UInt64(UInt32.max), UInt64(UInt32.max) + 1,
      0x0000_0000_FFFF_FFFF, 0xFFFF_FFFF_0000_0000,
    ]
    for value in boundaries {
      var enc = MTPDataEncoder()
      enc.append(value)
      var dec = MTPDataDecoder(data: enc.encodedData)
      XCTAssertEqual(dec.readUInt64(), value, "Failed for boundary value \(value)")
    }
  }

  // MARK: - Multi-Field Sequence

  /// Encoding multiple fields in sequence and decoding in the same order should round-trip.
  func testMultiFieldSequenceRoundTrip() {
    property("Multi-field encode/decode should preserve all values in order")
      <- forAll(
        Gen<UInt16>.choose((0, UInt16.max)),
        Gen<UInt32>.choose((0, UInt32.max)),
        Gen<UInt64>.choose((0, UInt64.max)),
        Gen<UInt8>.choose((0, UInt8.max))
      ) { u16, u32, u64, u8 in
        var enc = MTPDataEncoder()
        enc.append(u16)
        enc.append(u32)
        enc.append(u64)
        enc.append(u8)

        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let d16 = dec.readUInt16(),
          let d32 = dec.readUInt32(),
          let d64 = dec.readUInt64(),
          let d8 = dec.readUInt8()
        else { return false }

        return d16 == u16 && d32 == u32 && d64 == u64 && d8 == u8
      }
  }

  // MARK: - Encoder Byte Count

  /// Encoded data size should match the sum of appended type sizes.
  func testEncoderByteCount() {
    property("Encoder byte count should equal sum of appended type widths")
      <- forAll(
        Gen<UInt16>.choose((0, UInt16.max)),
        Gen<UInt32>.choose((0, UInt32.max)),
        Gen<UInt64>.choose((0, UInt64.max))
      ) { u16, u32, u64 in
        var enc = MTPDataEncoder()
        enc.append(u16)  // 2 bytes
        enc.append(u32)  // 4 bytes
        enc.append(u64)  // 8 bytes
        return enc.count == 2 + 4 + 8
      }
  }

  // MARK: - Decoder Exhaustion

  /// Reading past the end of data should return nil, not crash.
  func testDecoderExhaustion() {
    property("Reading past end of data should return nil")
      <- forAll { (value: UInt16) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        _ = dec.readUInt16()  // consume the data
        // Now try to read more — should return nil
        return dec.readUInt16() == nil && dec.readUInt32() == nil && dec.readUInt64() == nil
      }
  }

  // MARK: - Encoder Reset

  /// After reset, encoder should be empty.
  func testEncoderReset() {
    property("After reset, encoder count should be zero")
      <- forAll { (value: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(value)
        enc.reset()
        return enc.count == 0 && enc.encodedData.isEmpty
      }
  }

  // MARK: - PTPString Edge Cases

  /// Empty string should encode and decode correctly.
  func testPTPStringEmptyRoundTrip() {
    let encoded = PTPString.encode("")
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    // Empty string encodes to a single zero byte (length = 0)
    XCTAssertTrue(decoded == nil || decoded == "")
  }

  /// Single-character strings should round-trip.
  func testPTPStringSingleCharRoundTrip() {
    property("Single-character strings should round-trip through PTPString")
      <- forAll(
        Gen<String>.fromElements(of: ["a", "Z", "0", "!", "@", "€", "¥"])
      ) { ch in
        let encoded = PTPString.encode(ch)
        var offset = 0
        guard let decoded = PTPString.parse(from: encoded, at: &offset) else {
          return false
        }
        return decoded == ch
      }
  }
}
