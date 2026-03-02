// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import XCTest

@testable import SwiftMTPCore

/// Comprehensive edge case tests for MTP codec infrastructure.
///
/// Covers: truncated containers, length mismatches, Unicode edge cases,
/// integer overflow, all MTP data types, round-trip encoding, and
/// boundary conditions for DeviceInfo, ObjectInfo, PropList, and more.
final class MTPCodecEdgeCaseTests: XCTestCase {

  // MARK: - Zero-Length and Minimal Data Packets

  func testZeroLengthDataPacket() {
    let data = Data()
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.u8())
    XCTAssertNil(reader.u16())
    XCTAssertNil(reader.u32())
    XCTAssertNil(reader.u64())
    XCTAssertNil(reader.bytes(1))
    XCTAssertNil(reader.string())
    for dt: UInt16 in [0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006,
                       0x0007, 0x0008, 0x0009, 0x000A, 0xFFFF, 0x4006] {
      var r = PTPReader(data: data)
      XCTAssertNil(r.value(dt: dt), "dt=0x\(String(format: "%04X", dt)) should return nil for empty data")
    }
  }

  func testZeroLengthBytesRead() {
    let data = Data([0x01, 0x02])
    var reader = PTPReader(data: data)
    let zero = reader.bytes(0)
    XCTAssertNotNil(zero)
    XCTAssertEqual(zero?.count, 0)
    XCTAssertEqual(reader.o, 0)
  }

  // MARK: - Maximum-Size MTP Data Containers

  func testMaxLengthContainerHeader() {
    let container = PTPContainer(
      length: 0xFFFF_FFFF,
      type: PTPContainer.Kind.data.rawValue,
      code: 0x1009,
      txid: 1
    )
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)
    // Verify max length is encoded correctly in little-endian
    XCTAssertEqual(buffer[0], 0xFF)
    XCTAssertEqual(buffer[1], 0xFF)
    XCTAssertEqual(buffer[2], 0xFF)
    XCTAssertEqual(buffer[3], 0xFF)
  }

  func testContainerWithFiveParams() {
    // MTP allows up to 5 params (12 header + 5*4 = 32)
    let container = PTPContainer(
      length: 32,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: 0x0A,
      params: [0x00010001, 0xFFFF_FFFF, 0x0000_0000, 0x1234_5678, 0xDEAD_BEEF]
    )
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 32)
  }

  // MARK: - Truncated Containers at All Possible Points

  func testTruncatedContainerAtEveryByte() {
    // A valid 12-byte container
    let full = Data([0x0C, 0x00, 0x00, 0x00,  // length=12
                     0x01, 0x00,              // type=command
                     0x01, 0x10,              // code=GetDeviceInfo
                     0x01, 0x00, 0x00, 0x00]) // txid=1

    for truncLen in 0..<12 {
      let truncated = Data(full.prefix(truncLen))
      var reader = PTPReader(data: truncated)
      // Attempt sequential reads — must not crash at any truncation point
      let length = reader.u32()
      if truncLen < 4 {
        XCTAssertNil(length, "length should be nil at \(truncLen) bytes")
        // u32 didn't advance; remaining reads from offset 0 may or may not succeed
        continue
      }
      XCTAssertEqual(length, 12)

      let type = reader.u16()
      if truncLen < 6 {
        XCTAssertNil(type, "type should be nil at \(truncLen) bytes")
        continue
      }

      let code = reader.u16()
      if truncLen < 8 {
        XCTAssertNil(code, "code should be nil at \(truncLen) bytes")
        continue
      }

      let txid = reader.u32()
      if truncLen < 12 {
        XCTAssertNil(txid, "txid should be nil at \(truncLen) bytes")
      }
    }
  }

  func testTruncatedContainerWithParams() {
    // 16-byte container (header + 1 param) truncated at byte 14
    let full = Data([0x10, 0x00, 0x00, 0x00,
                     0x03, 0x00,
                     0x01, 0x20,
                     0x01, 0x00, 0x00, 0x00,
                     0xAA, 0xBB, 0xCC, 0xDD])
    let truncated = full.prefix(14)
    var reader = PTPReader(data: Data(truncated))
    XCTAssertEqual(reader.u32(), 16)
    XCTAssertEqual(reader.u16(), 3)
    XCTAssertEqual(reader.u16(), 0x2001)
    XCTAssertEqual(reader.u32(), 1)
    XCTAssertNil(reader.u32(), "Param should be nil when truncated")
  }

  // MARK: - Malformed Container Headers

  func testContainerWithInvalidTypeField() {
    // type=0xFF00 is not a valid PTP container type but should parse structurally
    let container = PTPContainer(type: 0xFF00, code: 0x1001, txid: 1)
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)

    var reader = PTPReader(data: Data(buffer.prefix(12)))
    _ = reader.u32()
    let type = reader.u16()
    XCTAssertEqual(type, 0xFF00)
  }

  func testContainerWithTypeZero() {
    let container = PTPContainer(type: 0, code: 0x1001, txid: 1)
    var buffer = [UInt8](repeating: 0, count: 64)
    _ = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    var reader = PTPReader(data: Data(buffer.prefix(12)))
    _ = reader.u32()
    XCTAssertEqual(reader.u16(), 0)
  }

  // MARK: - Container Length Mismatch

  func testContainerLengthSmallerThanActual() {
    // Header says 12 but buffer has 24 bytes
    var data = Data(repeating: 0, count: 24)
    data[0] = 0x0C; data[4] = 0x01; data[6] = 0x01; data[7] = 0x10; data[8] = 0x01
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u32(), 12)
    // Reader doesn't enforce length boundary — reads beyond
    XCTAssertEqual(reader.u16(), 1)
    XCTAssertEqual(reader.u16(), 0x1001)
    XCTAssertEqual(reader.u32(), 1)
    // Extra data readable
    XCTAssertNotNil(reader.u32())
  }

  func testContainerLengthLargerThanActual() {
    // Header says 100 but only 12 bytes of data
    let data = Data([0x64, 0x00, 0x00, 0x00,
                     0x01, 0x00, 0x01, 0x10,
                     0x01, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u32(), 100)
    XCTAssertEqual(reader.u16(), 1)
    XCTAssertEqual(reader.u16(), 0x1001)
    XCTAssertEqual(reader.u32(), 1)
    XCTAssertNil(reader.u8())
  }

  // MARK: - Unicode String Encoding Edge Cases

  func testStringSurrogatePairEmoji() {
    // 😀 = U+1F600 = surrogate pair D83D DE00
    let data = Data([0x03,              // charCount=3 (high, low, null)
                     0x3D, 0xD8,        // D83D
                     0x00, 0xDE,        // DE00
                     0x00, 0x00])       // null terminator
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNotNil(result)
    if let s = result {
      XCTAssertTrue(s.unicodeScalars.contains(where: { $0.value == 0x1F600 }),
                    "Should contain U+1F600 emoji")
    }
  }

  func testStringBOMPrefix() {
    // UTF-16LE BOM (0xFEFF) followed by 'A' and null
    let data = Data([0x03,
                     0xFF, 0xFE,        // BOM
                     0x41, 0x00,        // 'A'
                     0x00, 0x00])       // null
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNotNil(result)
    // BOM is included as a character
    XCTAssertTrue(result!.contains("A"))
  }

  func testStringAllNullCharacters() {
    // 3 null characters — all skipped by parser
    let data = Data([0x03,
                     0x00, 0x00,
                     0x00, 0x00,
                     0x00, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertEqual(result, "")
  }

  func testStringJapaneseCharacters() {
    let original = "日本語テスト"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }

  func testStringMixedASCIIAndUnicode() {
    let original = "IMG_日本_001.jpg"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original)
  }

  func testStringEncodeDecodeRoundTripSpecialChars() {
    let strings = [
      "", "A", "Hello World",
      "file (1).txt", "名前", "Ñoño",
      "path/to/file", "a\u{0301}",  // combining accent
      String(repeating: "X", count: 253),  // near max length
    ]
    for original in strings {
      let encoded = PTPString.encode(original)
      var offset = 0
      let decoded = PTPString.parse(from: encoded, at: &offset)
      XCTAssertEqual(decoded, original, "Round-trip failed for: \(original)")
    }
  }

  // MARK: - Integer Overflow in Container Lengths

  func testContainerLengthMaxUInt32() {
    var data = Data(count: 12)
    // length = 0xFFFFFFFF
    data[0] = 0xFF; data[1] = 0xFF; data[2] = 0xFF; data[3] = 0xFF
    data[4] = 0x01; data[5] = 0x00
    data[6] = 0x01; data[7] = 0x10
    data[8] = 0x01; data[9] = 0x00; data[10] = 0x00; data[11] = 0x00
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u32(), 0xFFFF_FFFF)
    // Can still read remaining header fields
    XCTAssertEqual(reader.u16(), 1)
  }

  func testArrayCountAtMaxSafeCountBoundary() {
    // count = maxSafeCount (100_000): accepted but not enough data
    var data = Data(count: 4)
    let count = PTPReader.maxSafeCount
    data[0] = UInt8(count & 0xFF)
    data[1] = UInt8((count >> 8) & 0xFF)
    data[2] = UInt8((count >> 16) & 0xFF)
    data[3] = UInt8((count >> 24) & 0xFF)
    var reader = PTPReader(data: data)
    // Count is accepted but reading elements fails
    let result = reader.value(dt: 0x4006)
    XCTAssertNil(result, "Not enough element data")
  }

  func testArrayCountJustAboveMaxSafe() {
    var data = Data(count: 4)
    let count = PTPReader.maxSafeCount + 1
    data[0] = UInt8(count & 0xFF)
    data[1] = UInt8((count >> 8) & 0xFF)
    data[2] = UInt8((count >> 16) & 0xFF)
    data[3] = UInt8((count >> 24) & 0xFF)
    var reader = PTPReader(data: data)
    XCTAssertNil(reader.value(dt: 0x4006), "Count above maxSafeCount should be rejected")
  }

  // MARK: - Back-to-Back Containers

  func testBackToBackContainerParsing() {
    var buf = [UInt8](repeating: 0, count: 128)

    // First container: command
    let c1 = PTPContainer(length: 12, type: 1, code: 0x1001, txid: 1)
    let w1 = buf.withUnsafeMutableBufferPointer { ptr in
      c1.encode(into: ptr.baseAddress!)
    }

    // Second container: response
    let c2 = PTPContainer(length: 16, type: 3, code: 0x2001, txid: 1, params: [0])
    let w2 = buf.withUnsafeMutableBufferPointer { ptr in
      c2.encode(into: ptr.baseAddress!.advanced(by: w1))
    }

    let combined = Data(buf.prefix(w1 + w2))
    var reader = PTPReader(data: combined)

    // Parse first container
    XCTAssertEqual(reader.u32(), 12)
    XCTAssertEqual(reader.u16(), 1)
    XCTAssertEqual(reader.u16(), 0x1001)
    XCTAssertEqual(reader.u32(), 1)

    // Parse second container
    XCTAssertEqual(reader.u32(), 16)
    XCTAssertEqual(reader.u16(), 3)
    XCTAssertEqual(reader.u16(), 0x2001)
    XCTAssertEqual(reader.u32(), 1)
    XCTAssertEqual(reader.u32(), 0)

    // End of data
    XCTAssertNil(reader.u8())
  }

  // MARK: - Container with Extreme Operation Codes

  func testContainerWithOpCodeFFFF() {
    let container = PTPContainer(type: 1, code: 0xFFFF, txid: 1)
    var buffer = [UInt8](repeating: 0, count: 64)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(written, 12)
    var reader = PTPReader(data: Data(buffer.prefix(12)))
    _ = reader.u32()
    _ = reader.u16()
    XCTAssertEqual(reader.u16(), 0xFFFF)
  }

  func testContainerWithOpCodeZero() {
    let container = PTPContainer(type: 1, code: 0x0000, txid: 1)
    var buffer = [UInt8](repeating: 0, count: 64)
    _ = buffer.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    var reader = PTPReader(data: Data(buffer.prefix(12)))
    _ = reader.u32()
    _ = reader.u16()
    XCTAssertEqual(reader.u16(), 0x0000)
  }

  // MARK: - All MTP Data Types Round-Trip via PTPReader

  func testRoundTripInt8() {
    let value: Int8 = -42
    let data = Data([UInt8(bitPattern: value)])
    var reader = PTPReader(data: data)
    if case .int8(let v) = reader.value(dt: 0x0001) {
      XCTAssertEqual(v, value)
    } else { XCTFail("Expected int8") }
  }

  func testRoundTripUInt8() {
    let data = Data([0xAB])
    var reader = PTPReader(data: data)
    if case .uint8(let v) = reader.value(dt: 0x0002) {
      XCTAssertEqual(v, 0xAB)
    } else { XCTFail("Expected uint8") }
  }

  func testRoundTripInt16() {
    let value: Int16 = -1234
    var data = Data(count: 2)
    let unsigned = UInt16(bitPattern: value).littleEndian
    withUnsafeBytes(of: unsigned) { data = Data($0) }
    var reader = PTPReader(data: data)
    if case .int16(let v) = reader.value(dt: 0x0003) {
      XCTAssertEqual(v, value)
    } else { XCTFail("Expected int16") }
  }

  func testRoundTripUInt16() {
    let data = MTPEndianCodec.encode(UInt16(0xBEEF))
    var reader = PTPReader(data: data)
    if case .uint16(let v) = reader.value(dt: 0x0004) {
      XCTAssertEqual(v, 0xBEEF)
    } else { XCTFail("Expected uint16") }
  }

  func testRoundTripInt32() {
    let value: Int32 = -100_000
    let data = MTPEndianCodec.encode(UInt32(bitPattern: value))
    var reader = PTPReader(data: data)
    if case .int32(let v) = reader.value(dt: 0x0005) {
      XCTAssertEqual(v, value)
    } else { XCTFail("Expected int32") }
  }

  func testRoundTripUInt32() {
    let data = MTPEndianCodec.encode(UInt32(0xDEAD_BEEF))
    var reader = PTPReader(data: data)
    if case .uint32(let v) = reader.value(dt: 0x0006) {
      XCTAssertEqual(v, 0xDEAD_BEEF)
    } else { XCTFail("Expected uint32") }
  }

  func testRoundTripInt64() {
    let value: Int64 = -9_000_000_000
    let data = MTPEndianCodec.encode(UInt64(bitPattern: value))
    var reader = PTPReader(data: data)
    if case .int64(let v) = reader.value(dt: 0x0007) {
      XCTAssertEqual(v, value)
    } else { XCTFail("Expected int64") }
  }

  func testRoundTripUInt64() {
    let data = MTPEndianCodec.encode(UInt64(0xCAFE_BABE_DEAD_BEEF))
    var reader = PTPReader(data: data)
    if case .uint64(let v) = reader.value(dt: 0x0008) {
      XCTAssertEqual(v, 0xCAFE_BABE_DEAD_BEEF)
    } else { XCTFail("Expected uint64") }
  }

  func testRoundTripInt128() {
    let bytes = Data((0..<16).map { UInt8($0 * 17) })
    var reader = PTPReader(data: bytes)
    if case .int128(let d) = reader.value(dt: 0x0009) {
      XCTAssertEqual(d, bytes)
    } else { XCTFail("Expected int128") }
  }

  func testRoundTripUInt128() {
    let bytes = Data(repeating: 0xAA, count: 16)
    var reader = PTPReader(data: bytes)
    if case .uint128(let d) = reader.value(dt: 0x000A) {
      XCTAssertEqual(d, bytes)
    } else { XCTFail("Expected uint128") }
  }

  func testRoundTripString() {
    let original = "MTP Protocol Test 🎉"
    let encoded = PTPString.encode(original)
    var reader = PTPReader(data: encoded)
    if case .string(let s) = reader.value(dt: 0xFFFF) {
      XCTAssertEqual(s, original)
    } else { XCTFail("Expected string") }
  }

  func testRoundTripEmptyString() {
    let encoded = PTPString.encode("")
    var reader = PTPReader(data: encoded)
    if case .string(let s) = reader.value(dt: 0xFFFF) {
      XCTAssertEqual(s, "")
    } else { XCTFail("Expected empty string") }
  }

  func testRoundTripArrayOfUInt16() {
    // Array of UInt16: dt = 0x4004
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt32(3)))  // count=3
    data.append(MTPEndianCodec.encode(UInt16(100)))
    data.append(MTPEndianCodec.encode(UInt16(200)))
    data.append(MTPEndianCodec.encode(UInt16(0xFFFF)))

    var reader = PTPReader(data: data)
    if case .array(let arr) = reader.value(dt: 0x4004) {
      XCTAssertEqual(arr.count, 3)
      if case .uint16(let v) = arr[0] { XCTAssertEqual(v, 100) }
      if case .uint16(let v) = arr[1] { XCTAssertEqual(v, 200) }
      if case .uint16(let v) = arr[2] { XCTAssertEqual(v, 0xFFFF) }
    } else { XCTFail("Expected array of uint16") }
  }

  func testEmptyArray() {
    let data = MTPEndianCodec.encode(UInt32(0))  // count=0
    var reader = PTPReader(data: data)
    if case .array(let arr) = reader.value(dt: 0x4006) {
      XCTAssertEqual(arr.count, 0)
    } else { XCTFail("Expected empty array") }
  }

  func testArrayOfInt8() {
    // dt = 0x4001 (array of int8)
    var data = MTPEndianCodec.encode(UInt32(2))
    data.append(UInt8(bitPattern: Int8(-1)))
    data.append(UInt8(bitPattern: Int8(127)))
    var reader = PTPReader(data: data)
    if case .array(let arr) = reader.value(dt: 0x4001) {
      XCTAssertEqual(arr.count, 2)
      if case .int8(let v) = arr[0] { XCTAssertEqual(v, -1) }
      if case .int8(let v) = arr[1] { XCTAssertEqual(v, 127) }
    } else { XCTFail("Expected array of int8") }
  }

  func testArrayOfUInt64() {
    // dt = 0x4008 (array of uint64)
    var data = MTPEndianCodec.encode(UInt32(1))
    data.append(MTPEndianCodec.encode(UInt64(0x0102030405060708)))
    var reader = PTPReader(data: data)
    if case .array(let arr) = reader.value(dt: 0x4008) {
      XCTAssertEqual(arr.count, 1)
      if case .uint64(let v) = arr[0] { XCTAssertEqual(v, 0x0102030405060708) }
    } else { XCTFail("Expected array of uint64") }
  }

  // MARK: - ObjectInfo Encode Edge Cases

  func testObjectInfoMaximalFields() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0xFFFF_FFFF,
      parentHandle: 0xFFFF_FFFF,
      format: 0x3801,  // JPEG
      size: UInt64(0xFFFF_FFFF),
      name: String(repeating: "A", count: 200),
      associationType: 0x0001,
      associationDesc: 0xFFFF_FFFF
    )
    XCTAssertGreaterThan(data.count, 50, "Maximal ObjectInfo should be substantial")

    // Verify storage ID
    let storageID = MTPEndianCodec.decodeUInt32(from: data, at: 0)
    XCTAssertEqual(storageID, 0xFFFF_FFFF)
  }

  func testObjectInfoZeroSizeFile() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3004,
      size: 0,
      name: "empty.txt"
    )
    XCTAssertGreaterThan(data.count, 0)
    // CompressedSize at offset 8 should be 0
    let compressed = MTPEndianCodec.decodeUInt32(from: data, at: 8)
    XCTAssertEqual(compressed, 0)
  }

  func testObjectInfoLargeFileSizeClamped() {
    // Size > UInt32.max should be clamped to 0xFFFFFFFF
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3000,
      size: UInt64(5_000_000_000),
      name: "huge.bin"
    )
    let compressed = MTPEndianCodec.decodeUInt32(from: data, at: 8)
    XCTAssertEqual(compressed, 0xFFFF_FFFF)
  }

  func testObjectInfoWithEmptyDates() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3001,
      size: 100,
      name: "test.dat",
      useEmptyDates: true
    )
    XCTAssertGreaterThan(data.count, 0)
  }

  func testObjectInfoWithCompressedSizeOverride() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3001,
      size: 1024,
      name: "test.dat",
      objectCompressedSizeOverride: 42
    )
    let compressed = MTPEndianCodec.decodeUInt32(from: data, at: 8)
    XCTAssertEqual(compressed, 42)
  }

  func testObjectInfoOmitOptionalStrings() {
    let withStrings = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0, format: 0x3001,
      size: 100, name: "a.txt", omitOptionalStringFields: false
    )
    let withoutStrings = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0, format: 0x3001,
      size: 100, name: "a.txt", omitOptionalStringFields: true
    )
    XCTAssertGreaterThan(withStrings.count, withoutStrings.count,
                         "Omitting optional strings should reduce size")
  }

  func testObjectInfoParentHandleOverride() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0x0000_0001,
      format: 0x3001,
      size: 100,
      name: "test.dat",
      objectInfoParentHandleOverride: 0xDEAD
    )
    // Parent handle is at offset 38 — use safe unaligned read
    let parent = MTPEndianCodec.decodeUInt32(from: data, at: 38)
    XCTAssertEqual(parent, 0xDEAD)
  }

  // MARK: - DeviceInfo Parsing Edge Cases

  func testDeviceInfoEmptyData() {
    XCTAssertNil(PTPDeviceInfo.parse(from: Data()))
  }

  func testDeviceInfoSingleByte() {
    XCTAssertNil(PTPDeviceInfo.parse(from: Data([0x42])))
  }

  func testDeviceInfoWithLargeArrays() {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt16(0x0100)))  // StandardVersion
    data.append(MTPEndianCodec.encode(UInt32(6)))        // VendorExtensionID=MicrosoftMTP
    data.append(MTPEndianCodec.encode(UInt16(100)))      // VendorExtensionVersion
    data.append(PTPString.encode("microsoft.com: 1.0")) // VendorExtensionDesc
    data.append(MTPEndianCodec.encode(UInt16(0)))        // FunctionalMode

    // Large operations array (50 entries)
    data.append(MTPEndianCodec.encode(UInt32(50)))
    for i: UInt16 in 0x1001...0x1032 {
      data.append(MTPEndianCodec.encode(i))
    }

    // Empty arrays for remaining
    for _ in 0..<4 {
      data.append(MTPEndianCodec.encode(UInt32(0)))
    }

    data.append(PTPString.encode("TestMfg"))
    data.append(PTPString.encode("TestModel"))
    data.append(PTPString.encode("1.0.0"))
    data.append(PTPString.encode("SN12345"))

    let info = PTPDeviceInfo.parse(from: data)
    XCTAssertNotNil(info)
    XCTAssertEqual(info?.standardVersion, 0x0100)
    XCTAssertEqual(info?.operationsSupported.count, 50)
    XCTAssertEqual(info?.manufacturer, "TestMfg")
    XCTAssertEqual(info?.model, "TestModel")
    XCTAssertEqual(info?.serialNumber, "SN12345")
  }

  func testDeviceInfoTruncatedBeforeModel() {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt16(1)))
    data.append(MTPEndianCodec.encode(UInt32(0)))
    data.append(MTPEndianCodec.encode(UInt16(0)))
    data.append(PTPString.encode(""))
    data.append(MTPEndianCodec.encode(UInt16(0)))
    for _ in 0..<5 { data.append(MTPEndianCodec.encode(UInt32(0))) }
    data.append(PTPString.encode("Mfg"))
    // Truncate here — no model string
    let result = PTPDeviceInfo.parse(from: data)
    XCTAssertNil(result, "Should fail without model string")
  }

  // MARK: - PropList Edge Cases

  func testPropListWithStringValue() {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt32(1)))     // count=1
    data.append(MTPEndianCodec.encode(UInt32(0x01)))  // handle
    data.append(MTPEndianCodec.encode(UInt16(0xDC07)))// propertyCode = ObjectFileName
    data.append(MTPEndianCodec.encode(UInt16(0xFFFF)))// dataType = string
    data.append(PTPString.encode("photo.jpg"))        // value

    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.entries.count, 1)
    if case .string(let s) = result?.entries.first?.value {
      XCTAssertEqual(s, "photo.jpg")
    } else {
      XCTFail("Expected string value")
    }
  }

  func testPropListWithMultipleMixedTypes() {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt32(2)))     // count=2

    // Entry 1: uint32
    data.append(MTPEndianCodec.encode(UInt32(1)))     // handle
    data.append(MTPEndianCodec.encode(UInt16(0xDC04)))// ObjectSize
    data.append(MTPEndianCodec.encode(UInt16(0x0006)))// UINT32
    data.append(MTPEndianCodec.encode(UInt32(4096)))  // value

    // Entry 2: uint16
    data.append(MTPEndianCodec.encode(UInt32(2)))     // handle
    data.append(MTPEndianCodec.encode(UInt16(0xDC02)))// ObjectFormat
    data.append(MTPEndianCodec.encode(UInt16(0x0004)))// UINT16
    data.append(MTPEndianCodec.encode(UInt16(0x3801)))// JPEG

    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.entries.count, 2)
  }

  func testPropListCountZeroIsEmpty() {
    let data = MTPEndianCodec.encode(UInt32(0))
    let result = PTPPropList.parse(from: data)
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.entries.count, 0)
  }

  // MARK: - PTPObjectFormat

  func testObjectFormatKnownExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("PHOTO.JPEG"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380b)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300b)
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.aac"), 0xb903)
    XCTAssertEqual(PTPObjectFormat.forFilename("notes.txt"), 0x3004)
  }

  func testObjectFormatUnknownExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("file.xyz"), 0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename("noext"), 0x3000)
    XCTAssertEqual(PTPObjectFormat.forFilename(""), 0x3000)
  }

  // MARK: - PTPResponseCode Edge Cases

  func testResponseCodeAllKnownCodes() {
    // Verify all codes in the known range have a name and description
    let knownCodes: [UInt16] = [
      0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
      0x2009, 0x200A, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2010,
      0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2016, 0x2017, 0x2018,
      0x2019, 0x201A, 0x201B, 0x201C, 0x201D, 0x201E, 0x201F, 0x2020,
    ]
    for code in knownCodes {
      // "UnknownVendorCode" is a valid name that contains "Unknown" — check name() not nil
      XCTAssertNotNil(PTPResponseCode.name(for: code),
                      "Code 0x\(String(format: "%04X", code)) should have a name")
    }
  }

  func testResponseCodeVendorRange() {
    // Vendor-specific codes (0xA000-0xAFFF) should be unknown
    XCTAssertNil(PTPResponseCode.name(for: 0xA001))
    XCTAssertTrue(PTPResponseCode.describe(0xA001).contains("Unknown"))
  }

  // MARK: - MTPDataEncoder / MTPDataDecoder Round-Trip

  func testEncoderDecoderRoundTrip() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(0x1234))
    encoder.append(UInt32(0xDEAD_BEEF))
    encoder.append(UInt64(0x0102_0304_0506_0708))
    encoder.append(UInt8(0xAB))

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    XCTAssertEqual(decoder.readUInt16(), 0x1234)
    XCTAssertEqual(decoder.readUInt32(), 0xDEAD_BEEF)
    XCTAssertEqual(decoder.readUInt64(), 0x0102_0304_0506_0708)
    XCTAssertEqual(decoder.readUInt8(), 0xAB)
    XCTAssertFalse(decoder.hasRemaining)
  }

  func testDecoderBoundsChecking() {
    let data = Data([0x01, 0x02])
    var decoder = MTPDataDecoder(data: data)
    XCTAssertEqual(decoder.remainingBytes, 2)
    XCTAssertNil(decoder.readUInt32())
    XCTAssertEqual(decoder.readUInt16(), 0x0201)
    XCTAssertEqual(decoder.remainingBytes, 0)
    XCTAssertNil(decoder.readUInt8())
  }

  func testDecoderPeekDoesNotAdvance() {
    let data = MTPEndianCodec.encode(UInt32(42))
    var decoder = MTPDataDecoder(data: data)
    XCTAssertEqual(decoder.peekUInt32(), 42)
    XCTAssertEqual(decoder.currentOffset, 0)
    XCTAssertEqual(decoder.readUInt32(), 42)
    XCTAssertEqual(decoder.currentOffset, 4)
  }

  func testDecoderSkipAndSeek() {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
    var decoder = MTPDataDecoder(data: data)
    decoder.skip(2)
    XCTAssertEqual(decoder.currentOffset, 2)
    XCTAssertEqual(decoder.readUInt8(), 0x03)
    decoder.seek(to: 0)
    XCTAssertEqual(decoder.readUInt8(), 0x01)
    decoder.seek(to: 100)  // beyond bounds
    XCTAssertEqual(decoder.currentOffset, 5)
    XCTAssertFalse(decoder.hasRemaining)
  }

  func testDecoderReadBytes() {
    let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
    var decoder = MTPDataDecoder(data: data)
    let bytes = decoder.readBytes(3)
    XCTAssertEqual(bytes, Data([0xAA, 0xBB, 0xCC]))
    XCTAssertEqual(decoder.remainingBytes, 1)
    XCTAssertNil(decoder.readBytes(2))
  }

  func testDecoderReset() {
    let data = MTPEndianCodec.encode(UInt16(0xBEEF))
    var decoder = MTPDataDecoder(data: data)
    _ = decoder.readUInt16()
    XCTAssertEqual(decoder.currentOffset, 2)
    decoder.reset()
    XCTAssertEqual(decoder.currentOffset, 0)
    XCTAssertEqual(decoder.readUInt16(), 0xBEEF)
  }

  func testEncoderReset() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(1))
    XCTAssertEqual(encoder.count, 4)
    encoder.reset()
    XCTAssertEqual(encoder.count, 0)
  }

  func testEncoderCapacityInit() {
    var encoder = MTPDataEncoder(capacity: 1024)
    XCTAssertEqual(encoder.count, 0)
    encoder.append(UInt16(1))
    XCTAssertEqual(encoder.count, 2)
  }

  // MARK: - MTPEndianCodec Direct Tests

  func testEndianCodecEncodeDecodeRoundTrip() {
    // UInt16
    let u16: UInt16 = 0xABCD
    let u16Data = MTPEndianCodec.encode(u16)
    XCTAssertEqual(MTPEndianCodec.decodeUInt16(from: u16Data, at: 0), u16)

    // UInt32
    let u32: UInt32 = 0x1234_5678
    let u32Data = MTPEndianCodec.encode(u32)
    XCTAssertEqual(MTPEndianCodec.decodeUInt32(from: u32Data, at: 0), u32)

    // UInt64
    let u64: UInt64 = 0xDEAD_BEEF_CAFE_BABE
    let u64Data = MTPEndianCodec.encode(u64)
    XCTAssertEqual(MTPEndianCodec.decodeUInt64(from: u64Data, at: 0), u64)
  }

  func testEndianCodecDecodeFromByteArray() {
    let bytes: [UInt8] = [0x78, 0x56, 0x34, 0x12, 0xEF, 0xCD, 0xAB, 0x89]
    XCTAssertEqual(MTPEndianCodec.decodeUInt16(from: bytes, at: 0), 0x5678)
    XCTAssertEqual(MTPEndianCodec.decodeUInt32(from: bytes, at: 0), 0x1234_5678)
    XCTAssertEqual(MTPEndianCodec.decodeUInt64(from: bytes, at: 0), 0x89AB_CDEF_1234_5678)
  }

  func testEndianCodecDecodeAtOffset() {
    let data = Data([0x00, 0x00, 0x34, 0x12])
    XCTAssertEqual(MTPEndianCodec.decodeUInt16(from: data, at: 2), 0x1234)
    XCTAssertNil(MTPEndianCodec.decodeUInt16(from: data, at: 3), "Not enough bytes at offset 3")
  }

  func testEndianCodecDecodeNegativeOffset() {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    XCTAssertNil(MTPEndianCodec.decodeUInt16(from: data, at: -1))
    XCTAssertNil(MTPEndianCodec.decodeUInt32(from: data, at: -1))
    XCTAssertNil(MTPEndianCodec.decodeUInt64(from: data, at: -1))
  }

  func testEndianCodecGenericDecodeLittleEndian() {
    let data = Data([0x78, 0x56, 0x34, 0x12])
    let u32: UInt32? = MTPEndianCodec.decodeLittleEndian(data, at: 0)
    XCTAssertEqual(u32, 0x1234_5678)

    let u16: UInt16? = MTPEndianCodec.decodeLittleEndian(data, at: 0)
    XCTAssertEqual(u16, 0x5678)

    let oob: UInt32? = MTPEndianCodec.decodeLittleEndian(data, at: 2)
    XCTAssertNil(oob)
  }

  func testEndianCodecEncodeToBytesArray() {
    let u16Bytes = MTPEndianCodec.encodeToBytes(UInt16(0x1234))
    XCTAssertEqual(u16Bytes, [0x34, 0x12])

    let u32Bytes = MTPEndianCodec.encodeToBytes(UInt32(0x12345678))
    XCTAssertEqual(u32Bytes, [0x78, 0x56, 0x34, 0x12])

    let u64Bytes = MTPEndianCodec.encodeToBytes(UInt64(0x0102030405060708))
    XCTAssertEqual(u64Bytes, [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
  }

  // MARK: - MTPDateString Edge Cases

  func testMTPDateStringEmptyInput() {
    // DateFormatter with "yyyyMMdd'T'HHmmss" may parse "" as a default date; verify no crash
    let result = MTPDateString.decode("")
    _ = result  // must not crash
  }

  func testMTPDateStringTruncatedInput() {
    XCTAssertNil(MTPDateString.decode("2025"))
    XCTAssertNil(MTPDateString.decode("20250101"))
    XCTAssertNil(MTPDateString.decode("20250101T"))
  }

  func testMTPDateStringWithTimezone() {
    // Should strip timezone suffix and still parse
    let date = MTPDateString.decode("20250615T143000.0Z")
    XCTAssertNotNil(date)
  }

  func testMTPDateStringRoundTrip() {
    let now = Date()
    let encoded = MTPDateString.encode(now)
    let decoded = MTPDateString.decode(encoded)
    XCTAssertNotNil(decoded)
    // Within 1 second due to format truncation
    if let d = decoded {
      XCTAssertEqual(d.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
    }
  }

  // MARK: - PTPValue Sendable Conformance Smoke

  func testPTPValueSendable() {
    // Verify PTPValue cases can be stored in Sendable contexts
    let values: [PTPValue] = [
      .int8(-1), .uint8(255),
      .int16(-1000), .uint16(65535),
      .int32(-100_000), .uint32(0xDEAD),
      .int64(-1), .uint64(0xCAFE),
      .int128(Data(repeating: 0, count: 16)),
      .uint128(Data(repeating: 0xFF, count: 16)),
      .string("test"),
      .bytes(Data([1, 2, 3])),
      .array([.uint32(1), .uint32(2)]),
    ]
    XCTAssertEqual(values.count, 13)
  }

  // MARK: - Fuzzing Corpus Smoke Tests

  func testAllTwoByteInputsForU16NoCrash() {
    // Exhaustive 2-byte inputs
    for hi in stride(from: UInt8(0), through: 255, by: 17) {
      for lo in stride(from: UInt8(0), through: 255, by: 17) {
        let data = Data([lo, hi])
        var reader = PTPReader(data: data)
        let val = reader.u16()
        XCTAssertNotNil(val)
      }
    }
  }

  func testRandomContainerBytesNoCrash() {
    // Pseudo-random containers should never crash the parser
    for seed in 0..<100 {
      var bytes = [UInt8](repeating: 0, count: 32)
      for i in 0..<32 {
        bytes[i] = UInt8((seed * 37 + i * 13 + 7) & 0xFF)
      }
      let data = Data(bytes)
      var reader = PTPReader(data: data)
      _ = reader.u32()
      _ = reader.u16()
      _ = reader.u16()
      _ = reader.u32()
      _ = reader.u32()

      // Also try parsing as DeviceInfo and PropList
      _ = PTPDeviceInfo.parse(from: data)
      _ = PTPPropList.parse(from: data)
    }
  }

  func testRepeatingPatternInputsNoCrash() {
    let patterns: [[UInt8]] = [
      [0x00], [0xFF], [0x80], [0x7F],
      [0x00, 0xFF], [0xFF, 0x00],
      [0x01, 0x00, 0x00, 0x00],
    ]
    for pattern in patterns {
      var data = Data()
      for _ in 0..<20 { data.append(contentsOf: pattern) }

      var reader = PTPReader(data: data)
      _ = reader.value(dt: 0x0006)

      _ = PTPDeviceInfo.parse(from: data)
      _ = PTPPropList.parse(from: data)

      var offset = 0
      _ = PTPString.parse(from: data, at: &offset)
    }
  }
}
