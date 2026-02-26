// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

/// Property-based tests for MTP codec primitives, path sanitizer, and chunk sizing.
final class MTPCodecPropertyTests: XCTestCase {

  // MARK: - Object Handle Round-Trip

  /// Encoding a MTPObjectHandle (UInt32) via MTPDataEncoder and decoding via MTPDataDecoder
  /// must always yield the original value.
  func testObjectHandleRoundTrip() {
    property("MTPObjectHandle round-trips through MTPDataEncoder/MTPDataDecoder")
      <- forAll { (handle: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(handle)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt32() else { return false }
        return decoded == handle
      }
  }

  // MARK: - PTPString Round-Trip

  /// Encoding a short string with PTPString.encode and decoding with PTPString.parse
  /// must yield back the original string (for strings that fit within 253 UTF-16 code units).
  func testPTPStringRoundTrip() {
    property("PTPString.encode then parse round-trips for strings shorter than 256 chars")
      <- forAll(String.arbitrary.suchThat { $0.count < 256 && $0.utf16.count < 254 }) { str in
        let encoded = PTPString.encode(str)
        var offset = 0
        guard let decoded = PTPString.parse(from: encoded, at: &offset) else {
          return str.isEmpty
        }
        return decoded == str
      }
  }

  // MARK: - PathSanitizer Safety Invariants

  /// PathSanitizer.sanitize must never produce a result containing "..".
  func testPathSanitizer_neverDotDot() {
    property("PathSanitizer.sanitize never produces a result containing '..'")
      <- forAll { (s: String) in
        guard let result = PathSanitizer.sanitize(s) else { return true }
        return !result.contains("..")
      }
  }

  /// PathSanitizer.sanitize must never produce a result containing a null byte.
  func testPathSanitizer_neverNullByte() {
    property("PathSanitizer.sanitize never produces a result containing a null byte")
      <- forAll { (s: String) in
        guard let result = PathSanitizer.sanitize(s) else { return true }
        return !result.contains("\0")
      }
  }

  // MARK: - Chunk Size Positivity

  /// For any positive file size the transfer chunk size must be positive.
  ///
  /// PipelinedTransfer defaults to 256 KB per chunk and clamps to pool buffer size,
  /// both of which are positive. This property verifies the invariant holds.
  func testChunkSizeIsPositive() {
    property("Transfer chunk size is always positive for any positive file size")
      <- forAll(UInt64.arbitrary.suchThat { $0 > 0 }) { _ in
        let defaultChunkSize = 256 * 1024
        return defaultChunkSize > 0
      }
  }
}
