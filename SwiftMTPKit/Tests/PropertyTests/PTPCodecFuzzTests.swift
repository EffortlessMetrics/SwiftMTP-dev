// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
import MTPEndianCodec

/// Fuzz tests for PTPCodec - tests that the parser handles malformed input gracefully
final class PTPCodecFuzzTests: XCTestCase {

  // MARK: - PTPReader Fuzz Tests

  func testPTPReaderU8Fuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...20)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      let _ = reader.u8()
      // Should not crash
    }
  }

  func testPTPReaderU16Fuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...50)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      let _ = reader.u16()
      // Should not crash
    }
  }

  func testPTPReaderU32Fuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...100)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      let _ = reader.u32()
      // Should not crash
    }
  }

  func testPTPReaderU64Fuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...200)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      let _ = reader.u64()
      // Should not crash
    }
  }

  func testPTPReaderBytesFuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...300)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      let bytesToRead = Int.random(in: 0...100)
      let _ = reader.bytes(bytesToRead)
      // Should not crash
    }
  }

  func testPTPReaderValueFuzz() {
    for _ in 0..<1000 {
      let randomLength = Int.random(in: 0...500)
      var data = Data(count: randomLength)
      for i in 0..<randomLength {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var reader = PTPReader(data: data)
      // Test various data types
      let dataTypes: [UInt16] = [
        0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0xFFFF,
      ]
      for dt in dataTypes {
        let _ = reader.value(dt: dt)
      }
      // Should not crash
    }
  }

  // MARK: - PTPString Fuzz Tests

  func testPTPStringParseFuzz() {
    for _ in 0..<1000 {
      // Generate random byte sequences
      let length = Int.random(in: 0...100)
      var data = Data(count: length)
      for i in 0..<length {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      var offset = 0
      let _ = PTPString.parse(from: data, at: &offset)
      // Should not crash
    }
  }

  func testPTPStringParseBoundaryConditions() {
    // Test edge cases
    var data: Data

    // Empty data
    data = Data()
    var offset = 0
    XCTAssertNil(PTPString.parse(from: data, at: &offset))

    // Single byte (0xFF = invalid length)
    data = Data([0xFF])
    offset = 0
    XCTAssertNil(PTPString.parse(from: data, at: &offset))

    // Single byte (0x00 = empty string)
    data = Data([0x00])
    offset = 0
    XCTAssertEqual(PTPString.parse(from: data, at: &offset), "")

    // Valid string: "A" in UTF-16LE
    var validData = Data()
    validData.append(0x02)  // length (1 char + null)
    validData.append(contentsOf: [0x41, 0x00])  // 'A' in UTF-16LE
    validData.append(contentsOf: [0x00, 0x00])  // null terminator
    offset = 0
    XCTAssertEqual(PTPString.parse(from: validData, at: &offset), "A")

    // Truncated data
    data = Data([0x04])  // claims 3 chars + null
    offset = 0
    XCTAssertNil(PTPString.parse(from: data, at: &offset))
  }

  func testPTPStringEncodeFuzz() {
    for _ in 0..<500 {
      // Generate random string
      let length = Int.random(in: 0...50)
      let randomString = generateRandomString(length: length)

      let encoded = PTPString.encode(randomString)

      // Verify we can decode it back
      var offset = 0
      let decoded = PTPString.parse(from: encoded, at: &offset)

      // Note: encoding truncates to 255 chars, so check accordingly
      let expected = String(randomString.prefix(254))
      XCTAssertEqual(decoded, expected)
    }
  }

  // MARK: - PTPDeviceInfo Parse Fuzz Tests

  func testPTPDeviceInfoParseFuzz() {
    for _ in 0..<500 {
      // Generate random data
      let length = Int.random(in: 0...1000)
      var data = Data(count: length)
      for i in 0..<length {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      // Try to parse - should not crash
      let _ = PTPDeviceInfo.parse(from: data)
    }
  }

  // MARK: - PTPPropList Parse Fuzz Tests

  func testPTPPropListParseFuzz() {
    for _ in 0..<500 {
      // Generate random data
      let length = Int.random(in: 0...1000)
      var data = Data(count: length)
      for i in 0..<length {
        data[i] = UInt8.random(in: 0...UInt8.max)
      }

      // Try to parse - should not crash
      let _ = PTPPropList.parse(from: data)
    }
  }

  // MARK: - PTPContainer Fuzz Tests

  func testPTPContainerEncodeDecodeFuzz() {
    for _ in 0..<500 {
      // Generate random container
      let type = UInt16.random(in: 1...4)
      let code = UInt16.random(in: 0x1001...0x101B)
      let txid = UInt32.random(in: 0...UInt32.max)
      let paramCount = Int.random(in: 0...5)
      let params = (0..<paramCount).map { _ in UInt32.random(in: 0...UInt32.max) }

      let container = PTPContainer(
        length: 12 + UInt32(paramCount * 4),
        type: type,
        code: code,
        txid: txid,
        params: params
      )

      // Encode
      let requiredSize = 12 + paramCount * 4
      var buffer = [UInt8](repeating: 0, count: requiredSize)
      let bytesWritten = buffer.withUnsafeMutableBufferPointer { ptr in
        guard let base = ptr.baseAddress else { return 0 }
        return container.encode(into: base)
      }

      XCTAssertEqual(bytesWritten, requiredSize)
    }
  }

  // MARK: - PTPObjectFormat Tests

  func testPTPObjectFormatDetection() {
    // Test various file extensions
    XCTAssertEqual(PTPObjectFormat.forFilename("test.txt"), 0x3004)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.JPG"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.jpeg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("icon.png"), 0x380b)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300b)
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.aac"), 0xb903)
    XCTAssertEqual(PTPObjectFormat.forFilename("unknown.xyz"), 0x3000)
  }

  // MARK: - Helper

  private func generateRandomString(length: Int) -> String {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789áéíóú"
    return String((0..<length).map { _ in characters.randomElement()! })
  }
}

// MARK: - GetObjectPropValue Fuzz Tests

/// Fuzz tests for GetObjectPropValue (0x9803) response parsing.
///
/// These tests verify that `PTPLayer.getObjectSizeU64`, `MTPDateString.decode`,
/// and `PTPString.parse` handle arbitrary byte payloads without crashing.
final class GetObjectPropValueFuzzTests: XCTestCase {

  private static let iterations = 1_000

  /// Fuzz MTPDateString.decode with random strings — must not crash.
  func testMTPDateStringDecodeRandomStrings() {
    let chars = "0123456789T+-Z:."
    for _ in 0..<Self.iterations {
      let len = Int.random(in: 0...25)
      let s = String((0..<len).map { _ in chars.randomElement()! })
      _ = MTPDateString.decode(s)  // must not crash or throw
    }
  }

  /// Fuzz MTPDateString.decode with valid-looking but corrupt byte patterns.
  func testMTPDateStringDecodeCorruptPayloads() {
    let candidates = [
      "",
      "T",
      "20250101",
      "20250101T",
      "20250101T120000",
      "20250101T120000.0Z",
      "20250101T120000+0000",
      "99999999T999999",
      "00000000T000000",
      "2025-01-01T12:00:00Z",  // ISO 8601 variant — not MTP format
      "XXXXXXXXTXXXXXX",
    ]
    for s in candidates {
      _ = MTPDateString.decode(s)  // must not crash
    }
  }

  /// Fuzz getObjectSizeU64 via PTPLayer with random data payloads.
  ///
  /// The decoder reads a UInt64 from the start of the payload — any 8-byte
  /// or shorter input must be handled gracefully.
  func testGetObjectSizeU64WithRandomPayloads() {
    for len in [0, 1, 4, 7, 8, 9, 16, 64, 256] {
      var data = Data(count: len)
      // Fill with pseudo-random bytes
      for i in 0..<len { data[i] = UInt8((i &* 0x6B + 0x2D) & 0xFF) }
      var dec = MTPDataDecoder(data: data)
      let result = dec.readUInt64()
      if len >= 8 {
        XCTAssertNotNil(result, "readUInt64 should succeed for \(len)-byte payload")
      } else {
        XCTAssertNil(result, "readUInt64 should fail for \(len)-byte payload (too short)")
      }
    }
  }

  /// Fuzz PTPString.parse with random binary data — must not crash.
  func testPTPStringParseWithRandomBinaryPayloads() {
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<Self.iterations {
      let len = Int.random(in: 0...64, using: &rng)
      var data = Data(count: len)
      for i in 0..<len { data[i] = UInt8.random(in: 0...255, using: &rng) }
      var offset = 0
      _ = PTPString.parse(from: data, at: &offset)  // must not crash
    }
  }

  /// GetObjectPropsSupported response with random valid array payloads decodes correctly.
  func testGetObjectPropsSupportedDecodeRandomPropLists() {
    for count in [0, 1, 5, 20, 100] {
      var enc = MTPDataEncoder()
      enc.append(UInt32(count))
      for i in 0..<count { enc.append(UInt16(0xDC00 + i)) }
      let data = enc.encodedData
      var dec = MTPDataDecoder(data: data)
      guard let decoded = dec.readUInt32() else {
        XCTFail("readUInt32 should succeed")
        continue
      }
      XCTAssertEqual(decoded, UInt32(count))
      for _ in 0..<count {
        XCTAssertNotNil(dec.readUInt16())
      }
    }
  }

  /// GetObjectPropsSupported truncated response is handled gracefully.
  func testGetObjectPropsSupportedTruncatedResponse() {
    // Header says 10 props but only 3 bytes of data follows
    var enc = MTPDataEncoder()
    enc.append(UInt32(10))
    enc.append(UInt16(0xDC01))
    // Deliberately truncated: missing 9 more UInt16s
    let data = enc.encodedData
    var dec = MTPDataDecoder(data: data)
    guard let count = dec.readUInt32() else { return XCTFail("count parse failed") }
    XCTAssertEqual(count, 10)
    var props: [UInt16] = []
    for _ in 0..<count {
      guard let code = dec.readUInt16() else { break }
      props.append(code)
    }
    XCTAssertEqual(props.count, 1, "Only 1 prop should decode from truncated response")
  }
}
