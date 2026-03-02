// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

/// Extended property tests covering codec roundtrips, quirks matching,
/// progress reporting, and transfer journal invariants.
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
              let dc = dec.readUInt32() else { return false }
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

  // MARK: - PTP Container Length Invariant

  func testPTPContainerLengthIncludesHeader() {
    property("PTP container length is always >= 12")
      <- forAll(Gen<UInt16>.choose((0x1001, 0x101B))) { (code: UInt16) in
        let container = PTPContainer(
          type: .command,
          code: code,
          transactionId: 1,
          payload: Data()
        )
        return container.encoded().count >= 12
      }
  }

  func testPTPContainerPayloadAddedToLength() {
    property("PTP container payload increases length by payload size")
      <- forAll(Gen<Int>.choose((0, 100))) { (payloadSize: Int) in
        let payload = Data(repeating: 0xAB, count: payloadSize)
        let container = PTPContainer(
          type: .data,
          code: 0x1009,
          transactionId: 1,
          payload: payload
        )
        return container.encoded().count == 12 + payloadSize
      }
  }

  // MARK: - Response Code Classification

  func testSuccessCodesAreSuccess() {
    let resp = MTPResponseCode.ok
    XCTAssertTrue(resp.isSuccess)
  }

  func testErrorCodesAreNotSuccess() {
    let errorCodes: [MTPResponseCode] = [
      .generalError, .sessionNotOpen, .invalidTransactionID,
      .operationNotSupported, .storeFull, .accessDenied,
    ]
    for code in errorCodes {
      XCTAssertFalse(code.isSuccess, "\(code) should not be success")
    }
  }

  // MARK: - Operation Code Range Properties

  func testStandardOpsInRange() {
    let standardOps: [MTPOperationCode] = [
      .getDeviceInfo, .openSession, .closeSession,
      .getStorageIDs, .getStorageInfo, .getNumObjects,
      .getObjectHandles, .getObjectInfo, .getObject,
      .deleteObject, .sendObjectInfo, .sendObject,
    ]
    for op in standardOps {
      XCTAssertTrue(op.rawValue >= 0x1001 && op.rawValue <= 0x101B,
                    "\(op) should be in standard range 0x1001-0x101B")
    }
  }

  // MARK: - MTP String Encoding Properties

  func testMTPStringLengthIncludesNull() {
    property("MTP encoded string length byte counts null terminator")
      <- forAll(Gen<String>.fromElements(of: ["a", "ab", "abc", "test", "hello"])) { (str: String) in
        var enc = MTPDataEncoder()
        enc.appendMTPString(str)
        let data = enc.encodedData
        guard let lenByte = data.first else { return false }
        // Length byte = character count + 1 (null terminator)
        return Int(lenByte) == str.utf16.count + 1
      }
  }

  func testEmptyMTPStringEncoding() {
    var enc = MTPDataEncoder()
    enc.appendMTPString("")
    let data = enc.encodedData
    // Empty string → length byte 0
    XCTAssertEqual(data.first, 0)
  }

  // MARK: - Transaction ID Generator Properties

  func testTransactionIdNeverZero() {
    property("Transaction IDs are never zero")
      <- forAll(Gen<UInt32>.choose((0, 10000))) { (start: UInt32) in
        var gen = TransactionIDGenerator(current: start)
        for _ in 0..<100 {
          if gen.next() == 0 { return false }
        }
        return true
      }
  }

  func testTransactionIdAlwaysIncreasing() {
    var gen = TransactionIDGenerator()
    var prev = gen.next()
    for _ in 0..<1000 {
      let curr = gen.next()
      // Either strictly increasing or wrapped from max to 1
      if curr != prev + 1 && !(prev == UInt32.max && curr == 1) {
        XCTFail("ID \(curr) should follow \(prev)")
        return
      }
      prev = curr
    }
  }

  // MARK: - Storage Type Properties

  func testStorageTypesNonOverlapping() {
    let types: [MTPStorageType] = [.undefined, .fixedROM, .removableROM, .fixedRAM, .removableRAM]
    let rawValues = types.map(\.rawValue)
    XCTAssertEqual(Set(rawValues).count, rawValues.count, "Storage types should have unique raw values")
  }

  // MARK: - Event Code Properties

  func testEventCodesInRange() {
    let events: [MTPEventCode] = [
      .objectAdded, .objectRemoved, .storeAdded, .storeRemoved,
      .devicePropChanged, .objectInfoChanged, .storeFull,
    ]
    for event in events {
      XCTAssertTrue(event.rawValue >= 0x4000, "Event codes should be >= 0x4000")
      XCTAssertTrue(event.rawValue < 0x5000, "Standard event codes should be < 0x5000")
    }
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

  // MARK: - Object Format Properties

  func testAssociationFormatIsFolder() {
    XCTAssertEqual(MTPObjectFormat.association.rawValue, 0x3001)
  }

  func testImageFormatsInRange() {
    let imageFormats: [MTPObjectFormat] = [.exifJPEG, .tiffEP, .bmp, .gif, .png, .tiff]
    for fmt in imageFormats {
      XCTAssertTrue(fmt.rawValue >= 0x3800 && fmt.rawValue <= 0x3FFF,
                    "\(fmt) should be in image format range")
    }
  }

  func testAudioFormatsInRange() {
    let audioFormats: [MTPObjectFormat] = [.mp3, .wav, .aiff]
    for fmt in audioFormats {
      XCTAssertTrue(fmt.rawValue >= 0x3007 && fmt.rawValue <= 0x300C,
                    "\(fmt) should be in standard format range")
    }
  }
}
