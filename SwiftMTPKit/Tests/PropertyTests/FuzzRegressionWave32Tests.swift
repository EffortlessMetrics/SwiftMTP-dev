// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import MTPEndianCodec
@testable import SwiftMTPCore

/// Wave 32 fuzz regression tests — discovered edge cases that must never crash.
///
/// Each test replays a minimised input that triggered (or could trigger) a crash,
/// hang, or unexpected behaviour in parsing, sanitisation, or dataset handling.
final class FuzzRegressionWave32Tests: XCTestCase {

  // MARK: - Helpers

  /// Build a minimal MTP container header (little-endian).
  private static func mtpHeader(
    length: UInt32, type: UInt16, code: UInt16, txid: UInt32
  ) -> Data {
    var e = MTPDataEncoder()
    e.append(length)
    e.append(type)
    e.append(code)
    e.append(txid)
    return e.encodedData
  }

  // MARK: - PTP String sentinel 0xFF

  func testStringLengthByte0xFF_SentinelDoesNotCrash() {
    // 0xFF is reserved as a sentinel — parser must return nil, never crash.
    var offset = 0
    let result = PTPString.parse(from: Data([0xFF]), at: &offset)
    XCTAssertNil(result, "0xFF sentinel length byte should return nil")
  }

  func testStringLengthByte0xFF_WithTrailingPayload() {
    // Sentinel followed by plausible UTF-16 data — must still reject.
    var payload = Data([0xFF])
    payload.append(contentsOf: Array(repeating: UInt8(0x41), count: 64))
    var offset = 0
    let result = PTPString.parse(from: payload, at: &offset)
    XCTAssertNil(result)
  }

  // MARK: - PTP container with exactly 12 bytes (minimum header, no payload)

  func testContainerExactly12Bytes_MinimumValidHeader() {
    let data = Self.mtpHeader(length: 12, type: 1, code: 0x1001, txid: 1)
    XCTAssertEqual(data.count, 12)

    var r = PTPReader(data: data)
    XCTAssertEqual(r.u32(), 12)
    XCTAssertEqual(r.u16(), 1)
    XCTAssertEqual(r.u16(), 0x1001)
    XCTAssertEqual(r.u32(), 1)
    // No further data available
    XCTAssertNil(r.u32())
  }

  func testContainerExactly12Bytes_AllContainerTypes() {
    for typeVal: UInt16 in [1, 2, 3, 4] {
      let data = Self.mtpHeader(length: 12, type: typeVal, code: 0x2001, txid: 0)
      var r = PTPReader(data: data)
      XCTAssertEqual(r.u32(), 12)
      XCTAssertEqual(r.u16(), typeVal)
      XCTAssertEqual(r.u16(), 0x2001)
      XCTAssertEqual(r.u32(), 0)
    }
  }

  // MARK: - PTP container with type field = 0 (invalid type)

  func testContainerTypeZero_InvalidTypeField() {
    let data = Self.mtpHeader(length: 12, type: 0, code: 0x1001, txid: 1)
    var r = PTPReader(data: data)
    XCTAssertEqual(r.u32(), 12)
    XCTAssertEqual(r.u16(), 0)  // Invalid type, but parsing must not crash
    XCTAssertEqual(r.u16(), 0x1001)
    XCTAssertEqual(r.u32(), 1)
  }

  func testContainerKind_TypeZeroNotRecognised() {
    // PTPContainer.Kind has no case for 0.
    XCTAssertNil(PTPContainer.Kind(rawValue: 0))
  }

  // MARK: - MTP ObjectInfo with zero-length filename

  func testObjectInfo_ZeroLengthFilename() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0xFFFFFFFF,
      format: 0x3000, size: 0, name: "")
    // Must encode without crash and produce valid data.
    XCTAssertFalse(data.isEmpty)

    // Verify the encoded filename is a zero-length PTP string (single 0x00 byte).
    var decoder = MTPDataDecoder(data: data)
    // Skip fixed fields: storageID(4) + format(2) + protection(2) + compressedSize(4)
    // + thumbFormat(2) + thumbSize(4) + thumbW(4) + thumbH(4) + imgW(4) + imgH(4)
    // + bitDepth(4) + parent(4) + assocType(2) + assocDesc(4) + seqNum(4) = 52 bytes
    decoder.seek(to: 52)
    let nameLenByte = decoder.readUInt8()
    XCTAssertEqual(nameLenByte, 0, "Empty name should encode as length byte 0")
  }

  // MARK: - MTP DeviceInfo with empty supported operations array

  func testDeviceInfo_EmptySupportedOperations() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(100))          // standardVersion
    encoder.append(UInt32(6))            // vendorExtensionID
    encoder.append(UInt16(100))          // vendorExtensionVersion
    encoder.append(PTPString.encode("")) // vendorExtensionDesc
    encoder.append(UInt16(0))            // functionalMode
    // All 5 arrays empty
    for _ in 0..<5 { encoder.append(UInt32(0)) }
    encoder.append(PTPString.encode("TestMfg"))
    encoder.append(PTPString.encode("TestModel"))
    encoder.append(PTPString.encode("1.0"))
    encoder.append(PTPString.encode("SN123"))

    let info = PTPDeviceInfo.parse(from: encoder.encodedData)
    XCTAssertNotNil(info)
    XCTAssertEqual(info?.operationsSupported.count, 0)
    XCTAssertEqual(info?.eventsSupported.count, 0)
    XCTAssertEqual(info?.manufacturer, "TestMfg")
  }

  // MARK: - PTP response with more than 5 parameters

  func testResponse_MoreThan5Parameters() {
    // A real PTP response has at most 5 params, but malformed data may carry more.
    let params: [UInt32] = [1, 2, 3, 4, 5, 6, 7, 8]
    let length = UInt32(12 + params.count * 4)
    var encoder = MTPDataEncoder()
    encoder.append(length)
    encoder.append(UInt16(3))       // type = response
    encoder.append(UInt16(0x2001))  // code = OK
    encoder.append(UInt32(1))       // txid
    for p in params { encoder.append(p) }

    // Reading all fields from the wire must not crash.
    var r = PTPReader(data: encoder.encodedData)
    XCTAssertEqual(r.u32(), length)
    XCTAssertEqual(r.u16(), 3)
    XCTAssertEqual(r.u16(), 0x2001)
    XCTAssertEqual(r.u32(), 1)
    // Read all 8 params — no crash expected
    for i in 0..<8 {
      XCTAssertEqual(r.u32(), UInt32(i + 1))
    }
    // Beyond the data
    XCTAssertNil(r.u32())
  }

  // MARK: - Dataset with self-referential handles (parent = self)

  func testObjectInfo_SelfReferentialHandle() {
    // Object with handle = parent handle (parent points to itself)
    let selfHandle: UInt32 = 0x00000042
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: selfHandle,
      format: 0x3001, size: 1024, name: "loop.txt")
    // Must encode without crash.
    XCTAssertFalse(data.isEmpty)

    // Verify parent handle is encoded at offset 38:
    // storageID(4)+format(2)+protection(2)+compSize(4)+thumbFmt(2)+thumbSize(4)
    // +thumbW(4)+thumbH(4)+imgW(4)+imgH(4)+bitDepth(4) = 38 bytes before parent
    let parentDecoded = MTPEndianCodec.decodeUInt32(from: data, at: 38)
    XCTAssertEqual(parentDecoded, selfHandle)
  }

  // MARK: - Unicode filenames: combining characters, ZWJ, RTL override

  func testUnicode_CombiningCharacters() {
    // "é" as e + combining acute accent (U+0065 U+0301)
    let name = "caf\u{0065}\u{0301}.txt"
    let encoded = PTPString.encode(name)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNotNil(decoded)
    // Sanitizer must handle it too
    XCTAssertNotNil(PathSanitizer.sanitize(name))
  }

  func testUnicode_ZeroWidthJoiner() {
    // Family emoji: 👨‍👩‍👧 uses ZWJ (U+200D)
    let name = "family\u{200D}photo.jpg"
    let encoded = PTPString.encode(name)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNotNil(decoded)
    XCTAssertNotNil(PathSanitizer.sanitize(name))
  }

  func testUnicode_RTLOverride() {
    // Right-to-left override U+202E can be used to spoof filenames.
    let name = "benign\u{202E}fdp.exe"
    let encoded = PTPString.encode(name)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNotNil(decoded)
    // PathSanitizer should still produce a non-nil result (stripping is optional).
    let sanitized = PathSanitizer.sanitize(name)
    XCTAssertNotNil(sanitized)
  }

  func testUnicode_SurrogatePairEmoji() {
    // Emoji outside BMP: 🎵 U+1F3B5 requires surrogate pair in UTF-16
    let name = "music\u{1F3B5}.mp3"
    let encoded = PTPString.encode(name)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertNotNil(decoded)
  }

  // MARK: - Extremely long paths (1000+ characters)

  func testPathSanitizer_ExtremelyLongPath() {
    let longName = String(repeating: "a", count: 1500)
    let sanitized = PathSanitizer.sanitize(longName)
    // Should truncate to maxNameLength, not crash.
    XCTAssertNotNil(sanitized)
    XCTAssertLessThanOrEqual(sanitized!.count, PathSanitizer.maxNameLength)
  }

  func testPTPString_LongFilenameEncoding() {
    // PTP strings clamp at 254 chars (len byte 0xFF is sentinel).
    let longName = String(repeating: "B", count: 1000)
    let encoded = PTPString.encode(longName)
    // Length byte should be 0xFF (clamped)
    XCTAssertEqual(encoded[0], 0xFF)
    // Parse should return nil for sentinel
    var offset = 0
    XCTAssertNil(PTPString.parse(from: encoded, at: &offset))
  }

  func testPathSanitizer_LongPathWithUnicode() {
    // 1000+ chars of multi-byte Unicode
    let longName = String(repeating: "日本語", count: 400)  // 1200 chars
    let sanitized = PathSanitizer.sanitize(longName)
    XCTAssertNotNil(sanitized)
    XCTAssertLessThanOrEqual(sanitized!.count, PathSanitizer.maxNameLength)
  }

  // MARK: - Object handle 0x00000000 and 0xFFFFFFFF (reserved values)

  func testObjectHandle_Zero_RootHandle() {
    // Handle 0x00000000 is "root" / undefined in MTP.
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0x00000000,
      format: 0x3001, size: 100, name: "root.txt")
    XCTAssertFalse(data.isEmpty)
    let parentDecoded = MTPEndianCodec.decodeUInt32(from: data, at: 38)
    XCTAssertEqual(parentDecoded, 0x00000000)
  }

  func testObjectHandle_AllOnes_ReservedSentinel() {
    // Handle 0xFFFFFFFF is used as "all objects" or "no parent" in MTP.
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0xFFFFFFFF,
      format: 0x3001, size: 100, name: "sentinel.txt")
    XCTAssertFalse(data.isEmpty)
    let parentDecoded = MTPEndianCodec.decodeUInt32(from: data, at: 38)
    XCTAssertEqual(parentDecoded, 0xFFFFFFFF)
  }

  func testReservedHandles_InPropList() {
    // PTPPropList entries with reserved handles should parse without crash.
    for handle: UInt32 in [0x00000000, 0xFFFFFFFF] {
      var encoder = MTPDataEncoder()
      encoder.append(UInt32(1))     // 1 entry
      encoder.append(handle)        // object handle
      encoder.append(UInt16(0xDC01)) // property code (StorageID)
      encoder.append(UInt16(0x0006)) // data type (UInt32)
      encoder.append(UInt32(0x00010001)) // value
      let list = PTPPropList.parse(from: encoder.encodedData)
      XCTAssertNotNil(list)
      XCTAssertEqual(list?.entries.first?.handle, handle)
    }
  }

  // MARK: - Combined edge cases

  func testContainerType0_WithReservedHandle() {
    // Invalid type + reserved handle in same container.
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(16))      // length (header + 1 param)
    encoder.append(UInt16(0))       // type = invalid
    encoder.append(UInt16(0xFFFF))  // code = reserved
    encoder.append(UInt32(0))       // txid
    encoder.append(UInt32(0xFFFFFFFF))  // param = reserved handle

    var r = PTPReader(data: encoder.encodedData)
    XCTAssertEqual(r.u32(), 16)
    XCTAssertEqual(r.u16(), 0)
    XCTAssertEqual(r.u16(), 0xFFFF)
    XCTAssertEqual(r.u32(), 0)
    XCTAssertEqual(r.u32(), 0xFFFFFFFF)
  }

  func testDeviceInfo_ParsedFromAllZeros() {
    // 128 zero bytes — all fields parse as 0 or empty.
    let data = Data(repeating: 0x00, count: 128)
    // Should return nil (zero-length strings parse as "" but arrays of 0 are valid;
    // eventually a string parse fails when data runs out).
    _ = PTPDeviceInfo.parse(from: data)
    // Must not crash — result may or may not be nil depending on string encoding.
  }

  func testObjectInfo_EmptyDates_ZeroFilename() {
    // Encode with empty dates and empty filename — boundary combination.
    let data = PTPObjectInfoDataset.encode(
      storageID: 1, parentHandle: 0, format: 0x3000, size: 0, name: "",
      useEmptyDates: true)
    XCTAssertFalse(data.isEmpty)
  }
}
