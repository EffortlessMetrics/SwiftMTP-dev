// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import MTPEndianCodec

@Suite("MTPEndianCodec Tests")
struct MTPEndianCodecTests {

  // MARK: - UInt16 Encoding Tests

  @Test("UInt16 encoding produces correct byte order")
  func testUInt16EncodingByteOrder() async throws {
    let value: UInt16 = 0x1234
    let data = MTPEndianCodec.encode(value)

    // Little-endian: least significant byte first
    #expect(data.count == 2)
    #expect(data[0] == 0x34)  // LSB
    #expect(data[1] == 0x12)  // MSB
  }

  @Test("UInt16 encoding known values")
  func testUInt16EncodingKnownValues() async throws {
    let testCases: [(UInt16, [UInt8])] = [
      (0x0000, [0x00, 0x00]),
      (0x0001, [0x01, 0x00]),
      (0x00FF, [0xFF, 0x00]),
      (0x0100, [0x00, 0x01]),
      (0xFFFF, [0xFF, 0xFF]),
      (0x1234, [0x34, 0x12]),
      (0xABCD, [0xCD, 0xAB]),
    ]

    for (value, expected) in testCases {
      let data = MTPEndianCodec.encode(value)
      #expect(Array(data) == expected, "Failed for value 0x\(String(value, radix: 16))")
    }
  }

  // MARK: - UInt32 Encoding Tests

  @Test("UInt32 encoding produces correct byte order")
  func testUInt32EncodingByteOrder() async throws {
    let value: UInt32 = 0x12345678
    let data = MTPEndianCodec.encode(value)

    // Little-endian: least significant byte first
    #expect(data.count == 4)
    #expect(data[0] == 0x78)  // LSB
    #expect(data[1] == 0x56)
    #expect(data[2] == 0x34)
    #expect(data[3] == 0x12)  // MSB
  }

  @Test("UInt32 encoding known values")
  func testUInt32EncodingKnownValues() async throws {
    let testCases: [(UInt32, [UInt8])] = [
      (0x00000000, [0x00, 0x00, 0x00, 0x00]),
      (0x00000001, [0x01, 0x00, 0x00, 0x00]),
      (0x000000FF, [0xFF, 0x00, 0x00, 0x00]),
      (0x00000100, [0x00, 0x01, 0x00, 0x00]),
      (0xFFFFFFFF, [0xFF, 0xFF, 0xFF, 0xFF]),
      (0x12345678, [0x78, 0x56, 0x34, 0x12]),
      (0xDEADBEEF, [0xEF, 0xBE, 0xAD, 0xDE]),
    ]

    for (value, expected) in testCases {
      let data = MTPEndianCodec.encode(value)
      #expect(Array(data) == expected, "Failed for value 0x\(String(value, radix: 16))")
    }
  }

  // MARK: - UInt64 Encoding Tests

  @Test("UInt64 encoding produces correct byte order")
  func testUInt64EncodingByteOrder() async throws {
    let value: UInt64 = 0x0123456789ABCDEF
    let data = MTPEndianCodec.encode(value)

    // Little-endian: least significant byte first
    #expect(data.count == 8)
    #expect(data[0] == 0xEF)  // LSB
    #expect(data[1] == 0xCD)
    #expect(data[2] == 0xAB)
    #expect(data[3] == 0x89)
    #expect(data[4] == 0x67)
    #expect(data[5] == 0x45)
    #expect(data[6] == 0x23)
    #expect(data[7] == 0x01)  // MSB
  }

  @Test("UInt64 encoding known values")
  func testUInt64EncodingKnownValues() async throws {
    let testCases: [(UInt64, [UInt8])] = [
      (0x0000000000000000, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      (0x0000000000000001, [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      (0xFFFFFFFFFFFFFFFF, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
      (0x0123456789ABCDEF, [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]),
    ]

    for (value, expected) in testCases {
      let data = MTPEndianCodec.encode(value)
      #expect(Array(data) == expected, "Failed for value 0x\(String(value, radix: 16))")
    }
  }

  // MARK: - Round-Trip Tests

  @Test("UInt16 round-trip encoding and decoding")
  func testUInt16RoundTrip() async throws {
    let testValues: [UInt16] = [0, 1, 127, 128, 255, 256, 32767, 32768, 65534, 65535]

    for original in testValues {
      let encoded = MTPEndianCodec.encode(original)
      let decoded = MTPEndianCodec.decodeUInt16(from: encoded, at: 0)
      #expect(decoded == original, "Round-trip failed for \(original)")
    }
  }

  @Test("UInt32 round-trip encoding and decoding")
  func testUInt32RoundTrip() async throws {
    let testValues: [UInt32] = [
      0, 1, 127, 128, 255, 256,
      65535, 65536,
      0x7FFFFFFF, 0x80000000,
      0xFFFFFFFF,
    ]

    for original in testValues {
      let encoded = MTPEndianCodec.encode(original)
      let decoded = MTPEndianCodec.decodeUInt32(from: encoded, at: 0)
      #expect(decoded == original, "Round-trip failed for \(original)")
    }
  }

  @Test("UInt64 round-trip encoding and decoding")
  func testUInt64RoundTrip() async throws {
    let testValues: [UInt64] = [
      0, 1, 127, 128, 255, 256,
      65535, 65536,
      0xFFFFFFFF,
      0x100000000,
      0x7FFFFFFFFFFFFFFF,
      0xFFFFFFFFFFFFFFFF,
    ]

    for original in testValues {
      let encoded = MTPEndianCodec.encode(original)
      let decoded = MTPEndianCodec.decodeUInt64(from: encoded, at: 0)
      #expect(decoded == original, "Round-trip failed for \(original)")
    }
  }

  // MARK: - Boundary Value Tests

  @Test("Decoding returns nil for insufficient bytes")
  func testDecodingInsufficientBytes() async throws {
    let shortData = Data([0x01, 0x02])  // Only 2 bytes

    // UInt16 should succeed
    #expect(MTPEndianCodec.decodeUInt16(from: shortData, at: 0) != nil)

    // UInt32 should fail
    #expect(MTPEndianCodec.decodeUInt32(from: shortData, at: 0) == nil)

    // UInt64 should fail
    #expect(MTPEndianCodec.decodeUInt64(from: shortData, at: 0) == nil)
  }

  @Test("Decoding returns nil for invalid offset")
  func testDecodingInvalidOffset() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

    // Negative offset
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: -1) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: -1) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: -1) == nil)

    // Offset at boundary
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 7) == nil)  // Only 1 byte available
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 5) == nil)  // Only 3 bytes available
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: 1) == nil)  // Only 7 bytes available

    // Offset beyond data
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 10) == nil)
  }

  @Test("Decoding at various offsets")
  func testDecodingAtOffsets() async throws {
    // Create data with known pattern
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt16(0x1122)))
    data.append(MTPEndianCodec.encode(UInt32(0x33445566)))
    data.append(MTPEndianCodec.encode(UInt64(0x778899AABBCCDDEE)))

    // Decode at specific offsets
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 0) == 0x1122)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: 2) == 0x33445566)
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: 6) == 0x778899AABBCCDDEE)
  }

  // MARK: - Encode to Bytes Tests

  @Test("encodeToBytes produces correct arrays")
  func testEncodeToBytes() async throws {
    #expect(MTPEndianCodec.encodeToBytes(UInt16(0x1234)) == [0x34, 0x12])
    #expect(MTPEndianCodec.encodeToBytes(UInt32(0x12345678)) == [0x78, 0x56, 0x34, 0x12])
    #expect(
      MTPEndianCodec.encodeToBytes(UInt64(0x0123456789ABCDEF)) == [
        0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01,
      ])
  }

  // MARK: - Raw Buffer Encoding Tests

  @Test("Encoding into raw buffer")
  func testEncodeIntoRawBuffer() async throws {
    var buffer = [UInt8](repeating: 0, count: 20)

    let written16 = buffer.withUnsafeMutableBufferPointer { ptr in
      MTPEndianCodec.encode(UInt16(0x1122), into: ptr.baseAddress!, at: 0)
    }
    #expect(written16 == 2)

    let written32 = buffer.withUnsafeMutableBufferPointer { ptr in
      MTPEndianCodec.encode(UInt32(0x33445566), into: ptr.baseAddress!, at: 2)
    }
    #expect(written32 == 4)

    let written64 = buffer.withUnsafeMutableBufferPointer { ptr in
      MTPEndianCodec.encode(UInt64(0x778899AABBCCDDEE), into: ptr.baseAddress!, at: 6)
    }
    #expect(written64 == 8)

    // Verify bytes
    #expect(buffer[0] == 0x22)
    #expect(buffer[1] == 0x11)
    #expect(buffer[2] == 0x66)
    #expect(buffer[3] == 0x55)
    #expect(buffer[4] == 0x44)
    #expect(buffer[5] == 0x33)
  }

  // MARK: - Raw Buffer Decoding Tests

  @Test("Decoding from raw buffer")
  func testDecodeFromRawBuffer() async throws {
    let data =
      MTPEndianCodec.encode(UInt32(0x12345678)) + MTPEndianCodec.encode(UInt64(0x0123456789ABCDEF))

    let value32 = data.withUnsafeBytes { ptr in
      MTPEndianCodec.decodeUInt32(from: ptr.baseAddress!, at: 0)
    }
    #expect(value32 == 0x12345678)

    let value64 = data.withUnsafeBytes { ptr in
      MTPEndianCodec.decodeUInt64(from: ptr.baseAddress!, at: 4)
    }
    #expect(value64 == 0x0123456789ABCDEF)
  }

  // MARK: - Generic Decoding Tests

  @Test("Generic decodeLittleEndian works for all types")
  func testGenericDecode() async throws {
    let data = Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00])

    let u16 = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: UInt16.self)
    #expect(u16 == 0x0001)

    let u32 = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: UInt32.self)
    #expect(u32 == 0x00020001)

    let u64 = MTPEndianCodec.decodeLittleEndian(data, at: 0, as: UInt64.self)
    #expect(u64 == 0x0004000300020001)
  }

  // MARK: - Collection Decoding Tests

  @Test("Decoding from byte array collection")
  func testDecodeFromCollection() async throws {
    let bytes: [UInt8] = [0x78, 0x56, 0x34, 0x12, 0xEF, 0xCD, 0xAB, 0x89]

    let value32 = MTPEndianCodec.decodeUInt32(from: bytes, at: 0)
    #expect(value32 == 0x12345678)

    let value32AtOffset = MTPEndianCodec.decodeUInt32(from: bytes, at: 4)
    #expect(value32AtOffset == 0x89ABCDEF)
  }
}

// MARK: - MTPDataEncoder Tests

@Suite("MTPDataEncoder Tests")
struct MTPDataEncoderTests {

  @Test("Encoder appends values correctly")
  func testEncoderAppend() async throws {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(0x1122))
    encoder.append(UInt32(0x33445566))
    encoder.append(UInt64(0x778899AABBCCDDEE))

    let data = encoder.encodedData
    #expect(data.count == 14)  // 2 + 4 + 8

    // Verify the UInt16
    let u16 = MTPEndianCodec.decodeUInt16(from: data, at: 0)
    #expect(u16 == 0x1122)

    // Verify the UInt32
    let u32 = MTPEndianCodec.decodeUInt32(from: data, at: 2)
    #expect(u32 == 0x33445566)

    // Verify the UInt64
    let u64 = MTPEndianCodec.decodeUInt64(from: data, at: 6)
    #expect(u64 == 0x778899AABBCCDDEE)
  }

  @Test("Encoder append single byte")
  func testEncoderAppendByte() async throws {
    var encoder = MTPDataEncoder()
    encoder.append(UInt8(0xFF))
    encoder.append(UInt8(0x00))

    #expect(encoder.count == 2)
    #expect(encoder.encodedData[0] == 0xFF)
    #expect(encoder.encodedData[1] == 0x00)
  }

  @Test("Encoder append raw bytes")
  func testEncoderAppendRawBytes() async throws {
    var encoder = MTPDataEncoder()
    encoder.append(contentsOf: [0x01, 0x02, 0x03])

    #expect(encoder.count == 3)
    #expect(Array(encoder.encodedData) == [0x01, 0x02, 0x03])
  }

  @Test("Encoder reset clears data")
  func testEncoderReset() async throws {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(0x12345678))
    #expect(encoder.count == 4)

    encoder.reset()
    #expect(encoder.count == 0)
    #expect(encoder.encodedData.isEmpty)
  }

  @Test("Encoder with initial capacity")
  func testEncoderWithCapacity() async throws {
    var encoder = MTPDataEncoder(capacity: 100)
    encoder.append(UInt32(0x12345678))

    #expect(encoder.count == 4)
  }
}

// MARK: - MTPDataDecoder Tests

@Suite("MTPDataDecoder Tests")
struct MTPDataDecoderTests {

  @Test("Decoder reads values sequentially")
  func testDecoderSequentialRead() async throws {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt16(0x1122)))
    data.append(MTPEndianCodec.encode(UInt32(0x33445566)))
    data.append(MTPEndianCodec.encode(UInt64(0x778899AABBCCDDEE)))

    var decoder = MTPDataDecoder(data: data)

    #expect(decoder.currentOffset == 0)
    #expect(decoder.remainingBytes == 14)
    #expect(decoder.hasRemaining)

    let u16 = decoder.readUInt16()
    #expect(u16 == 0x1122)
    #expect(decoder.currentOffset == 2)

    let u32 = decoder.readUInt32()
    #expect(u32 == 0x33445566)
    #expect(decoder.currentOffset == 6)

    let u64 = decoder.readUInt64()
    #expect(u64 == 0x778899AABBCCDDEE)
    #expect(decoder.currentOffset == 14)
    #expect(!decoder.hasRemaining)
  }

  @Test("Decoder returns nil when insufficient bytes")
  func testDecoderInsufficientBytes() async throws {
    let data = Data([0x01, 0x02])  // Only 2 bytes
    var decoder = MTPDataDecoder(data: data)

    #expect(decoder.readUInt16() != nil)
    #expect(decoder.readUInt32() == nil)  // Not enough bytes
  }

  @Test("Decoder peek does not advance offset")
  func testDecoderPeek() async throws {
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt32(0x12345678)))
    data.append(MTPEndianCodec.encode(UInt32(0x9ABCDEF0)))

    var decoder = MTPDataDecoder(data: data)

    // Peek at first value
    let peek1 = decoder.peekUInt32()
    #expect(peek1 == 0x12345678)
    #expect(decoder.currentOffset == 0)  // Offset unchanged

    // Peek at second value
    let peek2 = decoder.peekUInt32(at: 4)
    #expect(peek2 == 0x9ABCDEF0)
    #expect(decoder.currentOffset == 0)  // Offset unchanged

    // Read first value
    let read1 = decoder.readUInt32()
    #expect(read1 == 0x12345678)
    #expect(decoder.currentOffset == 4)  // Offset advanced
  }

  @Test("Decoder skip advances offset")
  func testDecoderSkip() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    var decoder = MTPDataDecoder(data: data)

    decoder.skip(3)
    #expect(decoder.currentOffset == 3)

    let value = decoder.readUInt32()
    #expect(value == 0x07060504)  // Bytes at offsets 3-6 in little-endian: [0x04, 0x05, 0x06, 0x07]
  }

  @Test("Decoder seek sets offset")
  func testDecoderSeek() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    var decoder = MTPDataDecoder(data: data)

    decoder.seek(to: 4)
    #expect(decoder.currentOffset == 4)

    let value = decoder.readUInt16()
    #expect(value == 0x0605)
  }

  @Test("Decoder reset returns to beginning")
  func testDecoderReset() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04])
    var decoder = MTPDataDecoder(data: data)

    _ = decoder.readUInt32()
    #expect(decoder.currentOffset == 4)

    decoder.reset()
    #expect(decoder.currentOffset == 0)
    #expect(decoder.remainingBytes == 4)
  }

  @Test("Decoder readBytes returns correct data")
  func testDecoderReadBytes() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
    var decoder = MTPDataDecoder(data: data)

    let bytes = decoder.readBytes(3)
    #expect(bytes == Data([0x01, 0x02, 0x03]))
    #expect(decoder.currentOffset == 3)
  }

  @Test("Decoder readUInt8")
  func testDecoderReadUInt8() async throws {
    let data = Data([0xFF, 0x00, 0x7F])
    var decoder = MTPDataDecoder(data: data)

    #expect(decoder.readUInt8() == 0xFF)
    #expect(decoder.readUInt8() == 0x00)
    #expect(decoder.readUInt8() == 0x7F)
    #expect(decoder.readUInt8() == nil)  // No more bytes
  }
}

// MARK: - Sendable Conformance Tests

@Suite("Sendable Conformance Tests")
struct SendableConformanceTests {

  @Test("MTPEndianCodec is Sendable")
  func testCodecIsSendable() async throws {
    // This test verifies at compile time that MTPEndianCodec conforms to Sendable
    let codec: any Sendable = MTPEndianCodec.self
    #expect(codec is MTPEndianCodec.Type)
  }

  @Test("MTPDataEncoder is Sendable")
  func testEncoderIsSendable() async throws {
    let encoder = MTPDataEncoder()
    let sendable: any Sendable = encoder
    #expect(sendable is MTPDataEncoder)
  }

  @Test("MTPDataDecoder is Sendable")
  func testDecoderIsSendable() async throws {
    let decoder = MTPDataDecoder(data: Data())
    let sendable: any Sendable = decoder
    #expect(sendable is MTPDataDecoder)
  }
}
