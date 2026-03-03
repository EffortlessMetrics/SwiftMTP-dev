// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

/// Extended property tests covering codec roundtrips, PTP container invariants,
/// PTPReader bounds, PTP string encoding, and operation code ranges.
final class ExtendedPropertyTests: XCTestCase {

  // MARK: - UInt8 Round-Trip

  func testUInt8RoundTrip() {
    property("UInt8 round-trips through encoder/decoder")
      <- forAll { (value: UInt8) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt8() else { return false }
        return decoded == value
      }
  }

  // MARK: - UInt32 Round-Trip

  func testUInt32RoundTrip() {
    property("UInt32 round-trips through encoder/decoder")
      <- forAll { (value: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt32() else { return false }
        return decoded == value
      }
  }

  // MARK: - UInt64 Round-Trip

  func testUInt64RoundTrip() {
    property("UInt64 round-trips through encoder/decoder")
      <- forAll { (value: UInt64) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt64() else { return false }
        return decoded == value
      }
  }

  // MARK: - Multi-Value Sequence Round-Trip

  func testMultiValueSequenceRoundTrip() {
    property("Multi-value sequences round-trip")
      <- forAll { (a: UInt8, b: UInt16, c: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(a)
        enc.append(b)
        enc.append(c)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let da = dec.readUInt8(),
          let db = dec.readUInt16(),
          let dc = dec.readUInt32()
        else { return false }
        return da == a && db == b && dc == c
      }
  }

  // MARK: - Encoder Length Property

  func testEncoderLengthMatchesTypeSize() {
    property("Encoder produces correct byte count for UInt32")
      <- forAll { (value: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(value)
        return enc.encodedData.count == 4
      }
  }

  func testEncoderLengthUInt16() {
    property("Encoder produces 2 bytes for UInt16")
      <- forAll { (value: UInt16) in
        var enc = MTPDataEncoder()
        enc.append(value)
        return enc.encodedData.count == 2
      }
  }

  // MARK: - PTP Container Encoding

  func testPTPContainerEncodesMinimum12Bytes() {
    // A PTP container with no params should encode to exactly 12 bytes (header only)
    let container = PTPContainer(
      type: PTPContainer.Kind.command.rawValue, code: 0x1001, txid: 1)
    var buf = [UInt8](repeating: 0, count: 64)
    let written = container.encode(into: &buf)
    XCTAssertEqual(written, 12, "Empty PTP container header should be 12 bytes")
  }

  func testPTPContainerParamsAddToLength() {
    property("Each PTP container param adds 4 bytes to encoded size")
      <- forAll(Gen<Int>.choose((0, 5))) { (paramCount: Int) in
        let params = (0..<paramCount).map { _ in UInt32.random(in: 0...UInt32.max) }
        let container = PTPContainer(
          type: PTPContainer.Kind.command.rawValue,
          code: 0x1001,
          txid: 1,
          params: params
        )
        var buf = [UInt8](repeating: 0, count: 64)
        let written = container.encode(into: &buf)
        return written == 12 + paramCount * 4
      }
  }

  // MARK: - PTP Response Code Classification

  func testOKResponseCodeIsStandard() {
    // 0x2001 is the standard OK code
    XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
  }

  func testErrorCodesHaveNames() {
    let errorCodes: [(UInt16, String)] = [
      (0x2002, "GeneralError"),
      (0x2003, "SessionNotOpen"),
      (0x2004, "InvalidTransactionID"),
      (0x2005, "OperationNotSupported"),
      (0x200C, "StoreFull"),
      (0x200F, "AccessDenied"),
    ]
    for (code, expectedName) in errorCodes {
      XCTAssertEqual(
        PTPResponseCode.name(for: code), expectedName,
        "Code 0x\(String(format: "%04x", code)) should be \(expectedName)"
      )
    }
  }

  func testUnknownResponseCodeReturnsNil() {
    XCTAssertNil(PTPResponseCode.name(for: 0x0000))
    XCTAssertNil(PTPResponseCode.name(for: 0xFFFF))
  }

  func testDescribeIncludesHexCode() {
    let desc = PTPResponseCode.describe(0x201D)
    XCTAssertTrue(desc.contains("201d"), "Describe should include hex code")
    XCTAssertTrue(desc.contains("InvalidParameter"), "Describe should include name")
  }

  // MARK: - Operation Code Range Properties

  func testStandardOpsInRange() {
    let standardOps: [PTPOp] = [
      .getDeviceInfo, .openSession, .closeSession,
      .getStorageIDs, .getStorageInfo, .getNumObjects,
      .getObjectHandles, .getObjectInfo, .getObject,
      .deleteObject, .sendObjectInfo, .sendObject,
    ]
    for op in standardOps {
      XCTAssertTrue(
        op.rawValue >= 0x1001 && op.rawValue <= 0x101B,
        "\(op) should be in standard range 0x1001-0x101B"
      )
    }
  }

  func testVendorOpsOutsideStandardRange() {
    let vendorOps: [PTPOp] = [.getPartialObject64, .sendPartialObject]
    for op in vendorOps {
      XCTAssertTrue(
        op.rawValue > 0x101B,
        "\(op) should be outside standard range"
      )
    }
  }

  // MARK: - PTP String Encoding Properties

  func testPTPStringRoundTrip() {
    property("PTPString encode/parse round-trips for short strings")
      <- forAll(
        Gen<String>.fromElements(of: ["a", "ab", "abc", "test", "hello"])
      ) { (str: String) in
        let encoded = PTPString.encode(str)
        var offset = 0
        guard let decoded = PTPString.parse(from: encoded, at: &offset) else { return false }
        return decoded == str
      }
  }

  func testPTPStringEncodedLengthIncludesNullTerminator() {
    // For a non-empty string, the length byte should be char count + 1 (null terminator)
    let str = "test"
    let encoded = PTPString.encode(str)
    let lenByte = Int(encoded[0])
    XCTAssertEqual(lenByte, str.utf16.count + 1, "Length byte should include null terminator")
  }

  func testEmptyPTPStringEncoding() {
    let encoded = PTPString.encode("")
    // Empty string -> length byte 0
    XCTAssertEqual(encoded.first, 0)
    XCTAssertEqual(encoded.count, 1, "Empty PTP string should be just the zero length byte")
  }

  // MARK: - Chunk Size Properties

  func testChunkSizeAlwaysPowerOf2Multiple() {
    let validChunks: [UInt32] = [
      512 * 1024, 1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024, 8 * 1024 * 1024,
    ]
    for chunk in validChunks {
      XCTAssertEqual(chunk & (chunk - 1), 0, "Chunk size \(chunk) should be power of 2")
    }
  }

  // MARK: - PTPReader Bounds

  func testPTPReaderNeverReadsPartialValue() {
    // If there's only 1 byte, u16 should return nil, not read partial
    var reader = PTPReader(data: Data([0xFF]))
    XCTAssertNil(reader.u16(), "Should not read partial UInt16")
  }

  func testPTPReaderNeverReadsPartialU32() {
    var reader = PTPReader(data: Data([0xFF, 0xFF, 0xFF]))
    XCTAssertNil(reader.u32(), "Should not read partial UInt32")
  }

  func testPTPReaderBytesExact() {
    var reader = PTPReader(data: Data([0x01, 0x02, 0x03]))
    let bytes = reader.bytes(3)
    XCTAssertEqual(bytes, Data([0x01, 0x02, 0x03]))
    XCTAssertNil(reader.bytes(1), "Should be exhausted")
  }

  func testPTPReaderBytesOverflow() {
    var reader = PTPReader(data: Data([0x01, 0x02]))
    XCTAssertNil(reader.bytes(3), "Should not read beyond buffer")
  }

  // MARK: - MTP Data Array Round-Trip

  func testUInt32ArrayRoundTrip() {
    property("UInt32 array round-trips")
      <- forAll(Gen<[UInt32]>.compose { c in
        let count = c.generate(using: Gen<Int>.choose((0, 10)))
        return (0..<count).map { _ in c.generate() }
      }) { (values: [UInt32]) in
        var enc = MTPDataEncoder()
        enc.append(UInt32(values.count))
        for v in values { enc.append(v) }
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let count = dec.readUInt32() else { return false }
        var decoded: [UInt32] = []
        for _ in 0..<count {
          guard let v = dec.readUInt32() else { return false }
          decoded.append(v)
        }
        return decoded == values
      }
  }

  // MARK: - PTP Object Format Helper

  func testObjectFormatForJPEG() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("PHOTO.JPEG"), 0x3801)
  }

  func testObjectFormatForPNG() {
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380b)
  }

  func testObjectFormatForMP3() {
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
  }

  func testObjectFormatForMP4() {
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300b)
  }

  func testObjectFormatForUnknownExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("data.xyz"), 0x3000, "Unknown should be Undefined")
  }

  // MARK: - MTPDataDecoder Remaining Bytes

  func testDecoderRemainingBytesProperty() {
    property("Decoder remaining bytes decreases correctly after reads")
      <- forAll { (value: UInt32) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        let before = dec.remainingBytes
        _ = dec.readUInt32()
        let after = dec.remainingBytes
        return before == 4 && after == 0
      }
  }

  func testDecoderHasRemainingAfterPartialRead() {
    var enc = MTPDataEncoder()
    enc.append(UInt32(42))
    enc.append(UInt16(7))
    var dec = MTPDataDecoder(data: enc.encodedData)
    XCTAssertTrue(dec.hasRemaining)
    _ = dec.readUInt32()
    XCTAssertTrue(dec.hasRemaining)
    _ = dec.readUInt16()
    XCTAssertFalse(dec.hasRemaining)
  }

  // MARK: - MTPDataEncoder Reset

  func testEncoderReset() {
    var enc = MTPDataEncoder()
    enc.append(UInt32(0xDEAD_BEEF))
    XCTAssertEqual(enc.count, 4)
    enc.reset()
    XCTAssertEqual(enc.count, 0)
    XCTAssertTrue(enc.encodedData.isEmpty)
  }
}
