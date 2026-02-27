// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

/// Property-based tests for PTPReader.value(dt:) dispatch correctness.
final class PTPReaderValuePropertyTests: XCTestCase {

  // MARK: - Scalar round-trips

  func testUInt8RoundTrip() {
    property("PTPReader.value(dt:0x0002) round-trips any UInt8")
      <- forAll { (v: UInt8) in
        var enc = MTPDataEncoder()
        enc.append(v)
        var reader = PTPReader(data: enc.encodedData)
        guard case .uint8(let decoded) = reader.value(dt: 0x0002) else { return false }
        return decoded == v
      }
  }

  func testUInt16RoundTrip() {
    property("PTPReader.value(dt:0x0004) round-trips any UInt16")
      <- forAll { (v: UInt16) in
        var enc = MTPDataEncoder()
        enc.append(v)
        var reader = PTPReader(data: enc.encodedData)
        guard case .uint16(let decoded) = reader.value(dt: 0x0004) else { return false }
        return decoded == v
      }
  }

  func testUInt32RoundTrip() {
    property("PTPReader.value(dt:0x0006) round-trips any UInt32")
      <- forAll { (v: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(v)
        var reader = PTPReader(data: enc.encodedData)
        guard case .uint32(let decoded) = reader.value(dt: 0x0006) else { return false }
        return decoded == v
      }
  }

  func testUInt64RoundTrip() {
    property("PTPReader.value(dt:0x0008) round-trips any UInt64")
      <- forAll { (v: UInt64) in
        var enc = MTPDataEncoder()
        enc.append(v)
        var reader = PTPReader(data: enc.encodedData)
        guard case .uint64(let decoded) = reader.value(dt: 0x0008) else { return false }
        return decoded == v
      }
  }

  // MARK: - String round-trip (0xFFFF regression)

  /// Regression test: 0xFFFF & 0x4000 != 0, so without the special-case guard it would
  /// fall into the array branch and silently mis-parse strings.
  func testStringRoundTripViaValueDt() {
    property("PTPReader.value(dt:0xFFFF) decodes PTPString-encoded strings correctly")
      <- forAll(String.arbitrary.suchThat { $0.utf16.count < 254 }) { str in
        let encoded = PTPString.encode(str)
        var reader = PTPReader(data: encoded)
        guard case .string(let decoded) = reader.value(dt: 0xFFFF) else {
          // empty string encodes as a single 0x00 length byte; parse returns ""
          return str.isEmpty
        }
        return decoded == str
      }
  }

  // MARK: - Array round-trip

  func testArrayOfUInt32RoundTrip() {
    property("PTPReader.value(dt:0x4006) round-trips arrays of UInt32")
      <- forAll { (arr: [UInt32]) in
        let limited = Array(arr.prefix(50))
        var enc = MTPDataEncoder()
        enc.append(UInt32(limited.count))
        for v in limited { enc.append(v) }
        var reader = PTPReader(data: enc.encodedData)
        guard case .array(let decoded) = reader.value(dt: 0x4006) else { return false }
        guard decoded.count == limited.count else { return false }
        return zip(decoded, limited).allSatisfy { elem, expected in
          guard case .uint32(let v) = elem else { return false }
          return v == expected
        }
      }
  }

  // MARK: - Truncated data safety

  /// Truncated data must return nil for every scalar type — never crash or return garbage.
  func testTruncatedDataReturnsNil() {
    let types: [(UInt16, Int)] = [
      (0x0001, 1), (0x0002, 1), (0x0003, 2), (0x0004, 2),
      (0x0005, 4), (0x0006, 4), (0x0007, 8), (0x0008, 8),
    ]
    for (dt, requiredBytes) in types where requiredBytes > 1 {
      let truncated = Data(repeating: 0, count: requiredBytes - 1)
      var reader = PTPReader(data: truncated)
      XCTAssertNil(
        reader.value(dt: dt),
        "dt=0x\(String(dt, radix: 16)) should return nil for truncated data")
    }
  }
}
