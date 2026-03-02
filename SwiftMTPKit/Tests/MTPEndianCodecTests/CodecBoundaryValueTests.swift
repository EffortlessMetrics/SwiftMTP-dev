// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import MTPEndianCodec
@testable import SwiftMTPCore

// MARK: - Integer Boundary Value Tests

@Suite("Codec Integer Boundary Values")
struct CodecIntegerBoundaryTests {

  @Test("UInt8 boundary values via MTPDataDecoder")
  func testUInt8Boundaries() {
    let values: [UInt8] = [0, 1, 0x7F, 0x80, 0xFE, 0xFF]
    for v in values {
      var decoder = MTPDataDecoder(data: Data([v]))
      #expect(decoder.readUInt8() == v, "Failed for \(v)")
    }
  }

  @Test("UInt16 boundary values via collection API")
  func testUInt16BoundariesCollection() {
    let values: [UInt16] = [0, 1, 0x00FF, 0x0100, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF]
    for v in values {
      let bytes = MTPEndianCodec.encodeToBytes(v)
      let decoded = MTPEndianCodec.decodeUInt16(from: bytes, at: 0)
      #expect(decoded == v, "Collection round-trip failed for \(v)")
    }
  }

  @Test("UInt32 boundary values via collection API")
  func testUInt32BoundariesCollection() {
    let values: [UInt32] = [
      0, 1, 0xFF, 0x100, 0xFFFF, 0x10000,
      0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF,
    ]
    for v in values {
      let bytes = MTPEndianCodec.encodeToBytes(v)
      let decoded = MTPEndianCodec.decodeUInt32(from: bytes, at: 0)
      #expect(decoded == v, "Collection round-trip failed for \(v)")
    }
  }

  @Test("UInt64 boundary values via collection API")
  func testUInt64BoundariesCollection() {
    let values: [UInt64] = [
      0, 1, 0xFF, 0xFFFF, 0xFFFFFFFF,
      0x100000000, 0x7FFFFFFFFFFFFFFF,
      0x8000000000000000, 0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF,
    ]
    for v in values {
      let bytes = MTPEndianCodec.encodeToBytes(v)
      let decoded = MTPEndianCodec.decodeUInt64(from: bytes, at: 0)
      #expect(decoded == v, "Collection round-trip failed for \(v)")
    }
  }

  @Test("Generic decoder with Int8 boundary values")
  func testGenericDecoderInt8() {
    let values: [Int8] = [Int8.min, -1, 0, 1, Int8.max]
    for v in values {
      let data = Data([UInt8(bitPattern: v)])
      let decoded: Int8? = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: Int8.self)
      #expect(decoded == v, "Generic Int8 failed for \(v)")
    }
  }

  @Test("Generic decoder with Int16 boundary values")
  func testGenericDecoderInt16() {
    let values: [Int16] = [Int16.min, -1, 0, 1, Int16.max]
    for v in values {
      let le = v.littleEndian
      let data = withUnsafeBytes(of: le) { Data($0) }
      let decoded: Int16? = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: Int16.self)
      #expect(decoded == v, "Generic Int16 failed for \(v)")
    }
  }

  @Test("Generic decoder with Int32 boundary values")
  func testGenericDecoderInt32() {
    let values: [Int32] = [Int32.min, -1, 0, 1, Int32.max]
    for v in values {
      let le = v.littleEndian
      let data = withUnsafeBytes(of: le) { Data($0) }
      let decoded: Int32? = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: Int32.self)
      #expect(decoded == v, "Generic Int32 failed for \(v)")
    }
  }

  @Test("Generic decoder with Int64 boundary values")
  func testGenericDecoderInt64() {
    let values: [Int64] = [Int64.min, -1, 0, 1, Int64.max]
    for v in values {
      let le = v.littleEndian
      let data = withUnsafeBytes(of: le) { Data($0) }
      let decoded: Int64? = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: Int64.self)
      #expect(decoded == v, "Generic Int64 failed for \(v)")
    }
  }
}

// MARK: - Endian Correctness Tests

@Suite("Codec Endian Correctness")
struct CodecEndianCorrectnessTests {

  @Test("UInt16 each byte position verified")
  func testUInt16BytePositions() {
    let value: UInt16 = 0xABCD
    let data = MTPEndianCodec.encode(value)
    #expect(data[0] == 0xCD)  // byte 0 = bits 0-7
    #expect(data[1] == 0xAB)  // byte 1 = bits 8-15
  }

  @Test("UInt32 each byte position verified")
  func testUInt32BytePositions() {
    let value: UInt32 = 0xAABBCCDD
    let data = MTPEndianCodec.encode(value)
    #expect(data[0] == 0xDD)  // bits 0-7
    #expect(data[1] == 0xCC)  // bits 8-15
    #expect(data[2] == 0xBB)  // bits 16-23
    #expect(data[3] == 0xAA)  // bits 24-31
  }

  @Test("UInt64 each byte position verified")
  func testUInt64BytePositions() {
    let value: UInt64 = 0x1122334455667788
    let data = MTPEndianCodec.encode(value)
    #expect(data[0] == 0x88)
    #expect(data[1] == 0x77)
    #expect(data[2] == 0x66)
    #expect(data[3] == 0x55)
    #expect(data[4] == 0x44)
    #expect(data[5] == 0x33)
    #expect(data[6] == 0x22)
    #expect(data[7] == 0x11)
  }

  @Test("Endian known test vectors from MTP spec")
  func testEndianKnownVectors() {
    // MTP session open command: length=12, type=1 (command), code=0x1002 (OpenSession), txid=1
    let length = MTPEndianCodec.encode(UInt32(16))
    #expect(Array(length) == [0x10, 0x00, 0x00, 0x00])

    let typeCmd = MTPEndianCodec.encode(UInt16(1))
    #expect(Array(typeCmd) == [0x01, 0x00])

    let codeOpenSession = MTPEndianCodec.encode(UInt16(0x1002))
    #expect(Array(codeOpenSession) == [0x02, 0x10])

    let txid = MTPEndianCodec.encode(UInt32(1))
    #expect(Array(txid) == [0x01, 0x00, 0x00, 0x00])
  }

  @Test("Power-of-two values encode single-bit correctly")
  func testPowerOfTwoEncoding() {
    // Each power of two should set exactly one bit in the encoded bytes
    for bit in 0..<16 {
      let value = UInt16(1) << bit
      let data = MTPEndianCodec.encode(value)
      let byteIndex = bit / 8
      let bitInByte = bit % 8
      #expect(data[byteIndex] == UInt8(1 << bitInByte), "Bit \(bit) failed")
      #expect(data[1 - byteIndex] == 0, "Other byte should be 0 for bit \(bit)")
    }
  }
}

// MARK: - Mixed-Endian and Mixed-Type Tests

@Suite("Codec Mixed Type Handling")
struct CodecMixedTypeTests {

  @Test("Sequential decode of mixed types")
  func testMixedTypeSequentialDecode() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt8(0xAA))
    encoder.append(UInt16(0xBBCC))
    encoder.append(UInt32(0xDDEEFF00))
    encoder.append(UInt64(0x1122334455667788))

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    #expect(decoder.readUInt8() == 0xAA)
    #expect(decoder.readUInt16() == 0xBBCC)
    #expect(decoder.readUInt32() == 0xDDEEFF00)
    #expect(decoder.readUInt64() == 0x1122334455667788)
    #expect(!decoder.hasRemaining)
  }

  @Test("Interleaved widths encode/decode")
  func testInterleavedWidths() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(100))
    encoder.append(UInt16(200))
    encoder.append(UInt32(300))
    encoder.append(UInt16(400))

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    #expect(decoder.readUInt32() == 100)
    #expect(decoder.readUInt16() == 200)
    #expect(decoder.readUInt32() == 300)
    #expect(decoder.readUInt16() == 400)
    #expect(decoder.remainingBytes == 0)
  }

  @Test("Reinterpret bytes as different width")
  func testReinterpretWidth() {
    // Encode a UInt32 and read as two UInt16s
    let data = MTPEndianCodec.encode(UInt32(0xAABBCCDD))
    let low = MTPEndianCodec.decodeUInt16(from: data, at: 0)
    let high = MTPEndianCodec.decodeUInt16(from: data, at: 2)
    #expect(low == 0xCCDD)
    #expect(high == 0xAABB)
  }

  @Test("Reinterpret two UInt32 as UInt64")
  func testReinterpretTwoU32AsU64() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(0x11223344))
    encoder.append(UInt32(0x55667788))

    let u64 = MTPEndianCodec.decodeUInt64(from: encoder.encodedData, at: 0)
    #expect(u64 == 0x5566778811223344)
  }
}

// MARK: - Buffer Underflow Tests

@Suite("Codec Buffer Underflow")
struct CodecBufferUnderflowTests {

  @Test("Decoder underflow returns nil for UInt8")
  func testDecoderUnderflowUInt8() {
    var decoder = MTPDataDecoder(data: Data())
    #expect(decoder.readUInt8() == nil)
  }

  @Test("Decoder underflow returns nil for UInt16 with 1 byte")
  func testDecoderUnderflowUInt16() {
    var decoder = MTPDataDecoder(data: Data([0xFF]))
    #expect(decoder.readUInt16() == nil)
  }

  @Test("Decoder underflow returns nil for UInt32 with 3 bytes")
  func testDecoderUnderflowUInt32() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02, 0x03]))
    #expect(decoder.readUInt32() == nil)
  }

  @Test("Decoder underflow returns nil for UInt64 with 7 bytes")
  func testDecoderUnderflowUInt64() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]))
    #expect(decoder.readUInt64() == nil)
  }

  @Test("Sequential reads until underflow")
  func testSequentialUnderflow() {
    // 5 bytes: can read one UInt32 then fails on next
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02, 0x03, 0x04, 0x05]))
    #expect(decoder.readUInt32() != nil)
    #expect(decoder.readUInt16() == nil)  // only 1 byte left
    #expect(decoder.readUInt8() == 0x05)  // 1 byte still works
    #expect(decoder.readUInt8() == nil)
  }

  @Test("readBytes underflow")
  func testReadBytesUnderflow() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02, 0x03]))
    #expect(decoder.readBytes(4) == nil)
    #expect(decoder.currentOffset == 0)  // offset unchanged on failure
  }

  @Test(
    "Decode from collection with exact boundary sizes",
    arguments: [0, 1, 2, 3, 4, 5, 6, 7, 8])
  func testCollectionBoundarySizes(size: Int) {
    let bytes = [UInt8](repeating: 0xAA, count: size)
    let u16 = MTPEndianCodec.decodeUInt16(from: bytes, at: 0)
    let u32 = MTPEndianCodec.decodeUInt32(from: bytes, at: 0)
    let u64 = MTPEndianCodec.decodeUInt64(from: bytes, at: 0)

    #expect((u16 != nil) == (size >= 2))
    #expect((u32 != nil) == (size >= 4))
    #expect((u64 != nil) == (size >= 8))
  }
}

// MARK: - Alignment-Sensitive Read Tests

@Suite("Codec Alignment-Sensitive Reads")
struct CodecAlignmentTests {

  @Test("UInt16 reads at odd offsets")
  func testUnalignedUInt16() {
    let data = Data([0x00, 0x34, 0x12, 0x78, 0x56])
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 1) == 0x1234)
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 3) == 0x5678)
  }

  @Test("UInt32 reads at odd offsets")
  func testUnalignedUInt32() {
    let data = Data([0x00, 0x78, 0x56, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE])
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 1) == 0x12345678)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 5) == 0xDEADBEEF)
  }

  @Test("UInt64 reads at odd offsets")
  func testUnalignedUInt64() {
    var data = Data([0xFF])  // 1-byte prefix for misalignment
    data.append(MTPEndianCodec.encode(UInt64(0x0123456789ABCDEF)))
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: 1) == 0x0123456789ABCDEF)
  }

  @Test("Unaligned collection reads match Data reads")
  func testUnalignedCollectionConsistency() {
    let data = Data([0xAA, 0x78, 0x56, 0x34, 0x12, 0xBB, 0xCC, 0xDD, 0xEE])
    let bytes = Array(data)

    #expect(
      MTPEndianCodec.decodeUInt32(from: data, at: 1)
        == MTPEndianCodec.decodeUInt32(from: bytes, at: 1))
    #expect(
      MTPEndianCodec.decodeUInt16(from: data, at: 3)
        == MTPEndianCodec.decodeUInt16(from: bytes, at: 3))
  }

  @Test("Raw buffer reads at odd offsets")
  func testUnalignedRawBuffer() {
    var data = Data([0xFF])
    data.append(MTPEndianCodec.encode(UInt32(0xDEADBEEF)))
    data.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      let value = MTPEndianCodec.decodeUInt32(from: base, at: 1)
      #expect(value == 0xDEADBEEF)
    }
  }
}

// MARK: - PTPString Encoding Tests

@Suite("PTPString Encoding")
struct PTPStringEncodingTests {

  @Test("Empty string encoding")
  func testEmptyString() {
    let data = PTPString.encode("")
    #expect(data.count == 1)
    #expect(data[0] == 0)  // char count = 0
  }

  @Test("Single character string")
  func testSingleChar() {
    let data = PTPString.encode("A")
    // count=2 (1 char + null), then "A" as UTF-16LE + null terminator
    #expect(data[0] == 2)
    #expect(data[1] == 0x41)  // 'A' low byte
    #expect(data[2] == 0x00)  // 'A' high byte
    #expect(data[3] == 0x00)  // null low
    #expect(data[4] == 0x00)  // null high
  }

  @Test("ASCII string round-trip")
  func testASCIIRoundTrip() {
    let original = "Hello"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == original)
  }

  @Test("Unicode string round-trip")
  func testUnicodeRoundTrip() {
    let original = "日本語テスト"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == original)
  }

  @Test("String parse from empty data returns nil")
  func testParseEmptyData() {
    var offset = 0
    let result = PTPString.parse(from: Data(), at: &offset)
    #expect(result == nil)
  }

  @Test("String parse with zero char count returns empty")
  func testParseZeroCount() {
    var offset = 0
    let result = PTPString.parse(from: Data([0x00]), at: &offset)
    #expect(result == "")
  }

  @Test("String with 0xFF char count returns nil")
  func testParse0xFFCount() {
    var offset = 0
    let result = PTPString.parse(from: Data([0xFF]), at: &offset)
    #expect(result == nil)
  }

  @Test("String parse with truncated UTF-16 data returns nil")
  func testParseTruncated() {
    // Claims 2 chars but only has bytes for 1
    var offset = 0
    let result = PTPString.parse(from: Data([0x02, 0x41, 0x00]), at: &offset)
    #expect(result == nil)
  }

  @Test("Long string up to 254 characters")
  func testLongString() {
    let original = String(repeating: "X", count: 253)
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == original)
  }
}

// MARK: - PTPReader Array Encoding Tests

@Suite("PTPReader Array Encoding")
struct PTPReaderArrayEncodingTests {

  @Test("Empty UInt16 array (count=0)")
  func testEmptyArray() {
    let data = MTPEndianCodec.encode(UInt32(0))  // count = 0
    var reader = PTPReader(data: data)
    let count = reader.u32()
    #expect(count == 0)
  }

  @Test("Single-element UInt16 array")
  func testSingleElementArray() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(1))  // count
    encoder.append(UInt16(0x1234))
    var reader = PTPReader(data: encoder.encodedData)
    let count = reader.u32()
    #expect(count == 1)
    #expect(reader.u16() == 0x1234)
  }

  @Test("Multi-element UInt32 array")
  func testMultiElementArray() {
    var encoder = MTPDataEncoder()
    let values: [UInt32] = [100, 200, 300, 400, 500]
    encoder.append(UInt32(UInt32(values.count)))
    for v in values { encoder.append(v) }

    var reader = PTPReader(data: encoder.encodedData)
    let count = reader.u32()
    #expect(count == UInt32(values.count))
    for expected in values {
      #expect(reader.u32() == expected)
    }
  }

  @Test("PTPValue array type decoding")
  func testPTPValueArrayDecode() {
    var encoder = MTPDataEncoder()
    // Array of UInt16 (datatype 0x4004)
    encoder.append(UInt32(3))  // count
    encoder.append(UInt16(10))
    encoder.append(UInt16(20))
    encoder.append(UInt16(30))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4004)
    if case .array(let elements) = value {
      #expect(elements.count == 3)
      if case .uint16(let v) = elements[0] { #expect(v == 10) }
      if case .uint16(let v) = elements[1] { #expect(v == 20) }
      if case .uint16(let v) = elements[2] { #expect(v == 30) }
    } else {
      #expect(Bool(false), "Expected array value")
    }
  }

  @Test("Array with count exceeding maxSafeCount returns nil")
  func testArrayCountExceedsMax() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(PTPReader.maxSafeCount + 1))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4006)  // Array of UInt32
    #expect(value == nil)
  }
}

// MARK: - DateTime Encoding Tests

@Suite("Codec DateTime Encoding")
struct CodecDateTimeEncodingTests {

  @Test("Standard date string encoding")
  func testStandardDate() {
    let dateStr = "20250101T000000"
    let encoded = PTPString.encode(dateStr)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == dateStr)
  }

  @Test("Empty date string encoding")
  func testEmptyDate() {
    let encoded = PTPString.encode("")
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == "")
  }

  @Test("Year 9999 date string")
  func testYear9999Date() {
    let dateStr = "99991231T235959"
    let encoded = PTPString.encode(dateStr)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == dateStr)
  }
}

// MARK: - Nested Structure Encoding Tests

@Suite("Codec Nested Structure Encoding")
struct CodecNestedStructureTests {

  @Test("PTPContainer command encoding")
  func testPTPContainerEncoding() {
    let container = PTPContainer(
      length: 12, type: 1, code: 0x1002, txid: 1)
    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 12)
    let data = Data(buf[0..<written])
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 0) == 12)
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 4) == 1)
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 6) == 0x1002)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 8) == 1)
  }

  @Test("PTPContainer with parameters")
  func testPTPContainerWithParams() {
    let container = PTPContainer(
      length: 20, type: 1, code: 0x1007, txid: 2,
      params: [0x00010001, 0xFFFFFFFF])
    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 20)
    let data = Data(buf[0..<written])
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 12) == 0x00010001)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 16) == 0xFFFFFFFF)
  }

  @Test("ObjectInfoDataset encoding basic")
  func testObjectInfoDatasetEncoding() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0xFFFFFFFF,
      format: 0x3000,
      size: 1024,
      name: "test.txt")

    var decoder = MTPDataDecoder(data: data)
    #expect(decoder.readUInt32() == 0x00010001)  // storageID
    #expect(decoder.readUInt16() == 0x3000)  // format
    #expect(decoder.readUInt16() == 0)  // ProtectionStatus
    #expect(decoder.readUInt32() == 1024)  // CompressedSize
  }

  @Test("ObjectInfoDataset with empty dates")
  func testObjectInfoDatasetEmptyDates() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0x00000000,
      format: 0x3801,
      size: 0,
      name: "photo.jpg",
      useEmptyDates: true)
    #expect(data.count > 0)
  }

  @Test("ObjectInfoDataset omit optional string fields")
  func testObjectInfoDatasetOmitOptional() {
    let withOptional = PTPObjectInfoDataset.encode(
      storageID: 1, parentHandle: 0, format: 0x3000, size: 0, name: "a")
    let withoutOptional = PTPObjectInfoDataset.encode(
      storageID: 1, parentHandle: 0, format: 0x3000, size: 0, name: "a",
      omitOptionalStringFields: true)
    #expect(withoutOptional.count < withOptional.count)
  }

  @Test("ObjectInfoDataset large file size clamped to UInt32.max")
  func testObjectInfoDatasetLargeSize() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 1, parentHandle: 0, format: 0x3000,
      size: UInt64(UInt32.max) + 1, name: "big.bin")

    var decoder = MTPDataDecoder(data: data)
    _ = decoder.readUInt32()  // storageID
    _ = decoder.readUInt16()  // format
    _ = decoder.readUInt16()  // ProtectionStatus
    let compressedSize = decoder.readUInt32()
    #expect(compressedSize == UInt32.max)
  }

  @Test("DeviceInfo parsing from encoded data")
  func testDeviceInfoParsing() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(100))  // standardVersion
    encoder.append(UInt32(6))  // vendorExtensionID (MTP)
    encoder.append(UInt16(100))  // vendorExtensionVersion
    encoder.append(PTPString.encode("microsoft.com: 1.0"))  // vendorExtensionDesc
    encoder.append(UInt16(0))  // functionalMode

    // operationsSupported (2 ops)
    encoder.append(UInt32(2))
    encoder.append(UInt16(0x1001))
    encoder.append(UInt16(0x1002))

    // eventsSupported (0)
    encoder.append(UInt32(0))
    // devicePropertiesSupported (0)
    encoder.append(UInt32(0))
    // captureFormats (0)
    encoder.append(UInt32(0))
    // playbackFormats (0)
    encoder.append(UInt32(0))

    encoder.append(PTPString.encode("TestMfg"))
    encoder.append(PTPString.encode("TestModel"))
    encoder.append(PTPString.encode("1.0.0"))
    encoder.append(PTPString.encode("SN12345"))

    let info = PTPDeviceInfo.parse(from: encoder.encodedData)
    #expect(info != nil)
    #expect(info?.standardVersion == 100)
    #expect(info?.vendorExtensionID == 6)
    #expect(info?.operationsSupported.count == 2)
    #expect(info?.operationsSupported.first == 0x1001)
    #expect(info?.manufacturer == "TestMfg")
    #expect(info?.model == "TestModel")
    #expect(info?.serialNumber == "SN12345")
  }
}

// MARK: - PTPValue Type Encoding Tests

@Suite("PTPValue Type Encoding")
struct PTPValueTypeTests {

  @Test("PTPReader decodes UInt8 value")
  func testPTPReaderUInt8() {
    var reader = PTPReader(data: Data([0x42]))
    let value = reader.value(dt: 0x0002)  // UINT8
    if case .uint8(let v) = value {
      #expect(v == 0x42)
    } else {
      #expect(Bool(false), "Expected uint8 value")
    }
  }

  @Test("PTPReader decodes Int8 value")
  func testPTPReaderInt8() {
    var reader = PTPReader(data: Data([0x80]))  // -128
    let value = reader.value(dt: 0x0001)  // INT8
    if case .int8(let v) = value {
      #expect(v == -128)
    } else {
      #expect(Bool(false), "Expected int8 value")
    }
  }

  @Test("PTPReader decodes UInt16 value")
  func testPTPReaderUInt16() {
    let data = MTPEndianCodec.encode(UInt16(0xBEEF))
    var reader = PTPReader(data: data)
    let value = reader.value(dt: 0x0004)  // UINT16
    if case .uint16(let v) = value {
      #expect(v == 0xBEEF)
    } else {
      #expect(Bool(false), "Expected uint16 value")
    }
  }

  @Test("PTPReader decodes UInt32 value")
  func testPTPReaderUInt32() {
    let data = MTPEndianCodec.encode(UInt32(0xDEADBEEF))
    var reader = PTPReader(data: data)
    let value = reader.value(dt: 0x0006)  // UINT32
    if case .uint32(let v) = value {
      #expect(v == 0xDEADBEEF)
    } else {
      #expect(Bool(false), "Expected uint32 value")
    }
  }

  @Test("PTPReader decodes UInt64 value")
  func testPTPReaderUInt64() {
    let data = MTPEndianCodec.encode(UInt64(0x0123456789ABCDEF))
    var reader = PTPReader(data: data)
    let value = reader.value(dt: 0x0008)  // UINT64
    if case .uint64(let v) = value {
      #expect(v == 0x0123456789ABCDEF)
    } else {
      #expect(Bool(false), "Expected uint64 value")
    }
  }

  @Test("PTPReader decodes Int128 (16 bytes)")
  func testPTPReaderInt128() {
    let bytes = Data(repeating: 0xAB, count: 16)
    var reader = PTPReader(data: bytes)
    let value = reader.value(dt: 0x0009)  // INT128
    if case .int128(let d) = value {
      #expect(d.count == 16)
    } else {
      #expect(Bool(false), "Expected int128 value")
    }
  }

  @Test("PTPReader decodes string value (dt=0xFFFF)")
  func testPTPReaderString() {
    let encoded = PTPString.encode("Hello MTP")
    var reader = PTPReader(data: encoded)
    let value = reader.value(dt: 0xFFFF)
    if case .string(let s) = value {
      #expect(s == "Hello MTP")
    } else {
      #expect(Bool(false), "Expected string value")
    }
  }

  @Test("PTPReader returns nil for unknown datatype")
  func testPTPReaderUnknownType() {
    var reader = PTPReader(data: Data([0x00, 0x00, 0x00, 0x00]))
    let value = reader.value(dt: 0x00FF)  // Unknown type
    #expect(value == nil)
  }

  @Test("PTPReader returns nil for insufficient data")
  func testPTPReaderInsufficientData() {
    var reader = PTPReader(data: Data([0x01]))  // Only 1 byte
    let value = reader.value(dt: 0x0006)  // UINT32 needs 4 bytes
    #expect(value == nil)
  }
}

// MARK: - PTPPropList Parsing Tests

@Suite("PTPPropList Parsing")
struct PTPPropListTests {

  @Test("Empty prop list")
  func testEmptyPropList() {
    let data = MTPEndianCodec.encode(UInt32(0))
    let list = PTPPropList.parse(from: data)
    #expect(list != nil)
    #expect(list?.entries.count == 0)
  }

  @Test("Single entry prop list with UInt32 value")
  func testSingleEntryPropList() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(1))  // entry count
    encoder.append(UInt32(0x00000001))  // handle
    encoder.append(UInt16(0xDC01))  // propertyCode (StorageID)
    encoder.append(UInt16(0x0006))  // dataType (UINT32)
    encoder.append(UInt32(0x00010001))  // value

    let list = PTPPropList.parse(from: encoder.encodedData)
    #expect(list != nil)
    #expect(list?.entries.count == 1)
    #expect(list?.entries.first?.handle == 1)
    #expect(list?.entries.first?.propertyCode == 0xDC01)
    if case .uint32(let v) = list?.entries.first?.value {
      #expect(v == 0x00010001)
    }
  }

  @Test("Prop list with count exceeding maxSafeCount returns nil")
  func testPropListExceedsMax() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(PTPReader.maxSafeCount + 1))
    let list = PTPPropList.parse(from: encoder.encodedData)
    #expect(list == nil)
  }
}

// MARK: - Cross-API Consistency Tests

@Suite("Codec Cross-API Consistency")
struct CodecCrossAPIConsistencyTests {

  @Test("Data vs Collection decode consistency for UInt16")
  func testDataVsCollectionUInt16() {
    let data = Data([0x78, 0x56, 0x34, 0x12])
    let bytes: [UInt8] = [0x78, 0x56, 0x34, 0x12]
    for offset in 0...2 {
      #expect(
        MTPEndianCodec.decodeUInt16(from: data, at: offset)
          == MTPEndianCodec.decodeUInt16(from: bytes, at: offset))
    }
  }

  @Test("Data vs Collection decode consistency for UInt32")
  func testDataVsCollectionUInt32() {
    let data = Data([0x78, 0x56, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE])
    let bytes = Array(data)
    for offset in [0, 1, 4] {
      #expect(
        MTPEndianCodec.decodeUInt32(from: data, at: offset)
          == MTPEndianCodec.decodeUInt32(from: bytes, at: offset))
    }
  }

  @Test("Data vs Raw buffer decode consistency")
  func testDataVsRawBuffer() {
    let data = Data([0x78, 0x56, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE])
    let fromData16 = MTPEndianCodec.decodeUInt16(from: data, at: 0)
    let fromData32 = MTPEndianCodec.decodeUInt32(from: data, at: 0)
    let fromData64 = MTPEndianCodec.decodeUInt64(from: data, at: 0)

    data.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      #expect(MTPEndianCodec.decodeUInt16(from: base, at: 0) == fromData16)
      #expect(MTPEndianCodec.decodeUInt32(from: base, at: 0) == fromData32)
      #expect(MTPEndianCodec.decodeUInt64(from: base, at: 0) == fromData64)
    }
  }

  @Test("encodeToBytes vs encode Data consistency")
  func testEncodeToBytesVsEncodeData() {
    let values16: [UInt16] = [0, 1, 0x7FFF, 0xFFFF]
    for v in values16 {
      #expect(Array(MTPEndianCodec.encode(v)) == MTPEndianCodec.encodeToBytes(v))
    }
    let values32: [UInt32] = [0, 1, 0x7FFFFFFF, 0xFFFFFFFF]
    for v in values32 {
      #expect(Array(MTPEndianCodec.encode(v)) == MTPEndianCodec.encodeToBytes(v))
    }
    let values64: [UInt64] = [0, 1, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    for v in values64 {
      #expect(Array(MTPEndianCodec.encode(v)) == MTPEndianCodec.encodeToBytes(v))
    }
  }

  @Test("Raw buffer encode round-trip via Data decode")
  func testRawBufferEncodeDataDecode() {
    var buffer = [UInt8](repeating: 0, count: 14)
    buffer.withUnsafeMutableBufferPointer { ptr in
      let base = UnsafeMutableRawPointer(ptr.baseAddress!)
      MTPEndianCodec.encode(UInt16(0x1234), into: base, at: 0)
      MTPEndianCodec.encode(UInt32(0x56789ABC), into: base, at: 2)
      MTPEndianCodec.encode(UInt64(0xDEF0123456789ABC), into: base, at: 6)
    }
    let data = Data(buffer)
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 0) == 0x1234)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 2) == 0x56789ABC)
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: 6) == 0xDEF0123456789ABC)
  }
}

// MARK: - Decoder Navigation Edge Cases

@Suite("Decoder Navigation Edge Cases")
struct DecoderNavigationEdgeCaseTests {

  @Test("Seek beyond end clamps to data count")
  func testSeekBeyondEnd() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02]))
    decoder.seek(to: 100)
    #expect(decoder.currentOffset == 2)
    #expect(decoder.remainingBytes == 0)
  }

  @Test("Seek to negative clamps to zero")
  func testSeekNegative() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02]))
    decoder.seek(to: -5)
    #expect(decoder.currentOffset == 0)
  }

  @Test("Skip beyond end clamps to data count")
  func testSkipBeyondEnd() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02]))
    decoder.skip(100)
    #expect(decoder.currentOffset == 2)
    #expect(!decoder.hasRemaining)
  }

  @Test("Peek at relative offset beyond end returns nil")
  func testPeekBeyondEnd() {
    let decoder = MTPDataDecoder(data: Data([0x01, 0x02, 0x03, 0x04]))
    #expect(decoder.peekUInt32(at: 2) == nil)
    #expect(decoder.peekUInt16(at: 4) == nil)
  }

  @Test("Multiple resets preserve data")
  func testMultipleResets() {
    var decoder = MTPDataDecoder(data: MTPEndianCodec.encode(UInt32(42)))
    #expect(decoder.readUInt32() == 42)
    decoder.reset()
    #expect(decoder.readUInt32() == 42)
    decoder.reset()
    #expect(decoder.readUInt32() == 42)
  }
}
