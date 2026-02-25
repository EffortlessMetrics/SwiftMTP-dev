// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftCheck
@testable import MTPEndianCodec

// MARK: - Property-Based Tests

/// Property-based tests for MTPEndianCodec using SwiftCheck.
///
/// These tests verify mathematical invariants that should hold for all possible input values.
/// Each property is tested with a large number of randomly generated inputs to ensure
/// correctness across the entire input space.
@Suite("MTPEndianCodec Property-Based Tests")
struct MTPEndianCodecPropertyTests {

  // MARK: - Round-Trip Invariants

  /// Verifies that encoding and then decoding any UInt16 value produces the original value.
  /// This is the fundamental round-trip invariant.
  @Test("UInt16 round-trip invariant: decode(encode(x)) == x for all x")
  func testUInt16RoundTripInvariant() async throws {
    property("UInt16 round-trip")
      <- forAll { (value: UInt16) in
        let encoded = MTPEndianCodec.encode(value)
        let decoded = MTPEndianCodec.decodeUInt16(from: encoded, at: 0)
        return decoded == value
      }
  }

  /// Verifies that encoding and then decoding any UInt32 value produces the original value.
  @Test("UInt32 round-trip invariant: decode(encode(x)) == x for all x")
  func testUInt32RoundTripInvariant() async throws {
    property("UInt32 round-trip")
      <- forAll { (value: UInt32) in
        let encoded = MTPEndianCodec.encode(value)
        let decoded = MTPEndianCodec.decodeUInt32(from: encoded, at: 0)
        return decoded == value
      }
  }

  /// Verifies that encoding and then decoding any UInt64 value produces the original value.
  @Test("UInt64 round-trip invariant: decode(encode(x)) == x for all x")
  func testUInt64RoundTripInvariant() async throws {
    property("UInt64 round-trip")
      <- forAll { (value: UInt64) in
        let encoded = MTPEndianCodec.encode(value)
        let decoded = MTPEndianCodec.decodeUInt64(from: encoded, at: 0)
        return decoded == value
      }
  }

  // MARK: - Idempotence Invariants

  /// Verifies that encoding the same UInt16 value twice produces identical byte sequences.
  @Test("UInt16 idempotence: encoding twice produces identical bytes")
  func testUInt16Idempotence() async throws {
    property("UInt16 idempotence")
      <- forAll { (value: UInt16) in
        let encoded1 = MTPEndianCodec.encode(value)
        let encoded2 = MTPEndianCodec.encode(value)
        return encoded1 == encoded2
      }
  }

  /// Verifies that encoding the same UInt32 value twice produces identical byte sequences.
  @Test("UInt32 idempotence: encoding twice produces identical bytes")
  func testUInt32Idempotence() async throws {
    property("UInt32 idempotence")
      <- forAll { (value: UInt32) in
        let encoded1 = MTPEndianCodec.encode(value)
        let encoded2 = MTPEndianCodec.encode(value)
        return encoded1 == encoded2
      }
  }

  /// Verifies that encoding the same UInt64 value twice produces identical byte sequences.
  @Test("UInt64 idempotence: encoding twice produces identical bytes")
  func testUInt64Idempotence() async throws {
    property("UInt64 idempotence")
      <- forAll { (value: UInt64) in
        let encoded1 = MTPEndianCodec.encode(value)
        let encoded2 = MTPEndianCodec.encode(value)
        return encoded1 == encoded2
      }
  }

  // MARK: - Byte Order Invariants

  /// Verifies that the first byte of encoded UInt16 is the least significant byte (little-endian).
  @Test("UInt16 byte order: first byte is LSB (little-endian)")
  func testUInt16ByteOrder() async throws {
    property("UInt16 byte order")
      <- forAll { (value: UInt16) in
        let encoded = MTPEndianCodec.encode(value)
        // First byte should be the least significant byte
        let expectedLSB = UInt8(value & 0xFF)
        return encoded[0] == expectedLSB
      }
  }

  /// Verifies that the first byte of encoded UInt32 is the least significant byte (little-endian).
  @Test("UInt32 byte order: first byte is LSB (little-endian)")
  func testUInt32ByteOrder() async throws {
    property("UInt32 byte order")
      <- forAll { (value: UInt32) in
        let encoded = MTPEndianCodec.encode(value)
        // First byte should be the least significant byte
        let expectedLSB = UInt8(value & 0xFF)
        return encoded[0] == expectedLSB
      }
  }

  /// Verifies that the first byte of encoded UInt64 is the least significant byte (little-endian).
  @Test("UInt64 byte order: first byte is LSB (little-endian)")
  func testUInt64ByteOrder() async throws {
    property("UInt64 byte order")
      <- forAll { (value: UInt64) in
        let encoded = MTPEndianCodec.encode(value)
        // First byte should be the least significant byte
        let expectedLSB = UInt8(value & 0xFF)
        return encoded[0] == expectedLSB
      }
  }

  // MARK: - Output Size Invariants

  /// Verifies that encoding UInt16 always produces exactly 2 bytes.
  @Test("UInt16 encoding size: always produces 2 bytes")
  func testUInt16EncodingSize() async throws {
    property("UInt16 encoding size")
      <- forAll { (value: UInt16) in
        let encoded = MTPEndianCodec.encode(value)
        return encoded.count == 2
      }
  }

  /// Verifies that encoding UInt32 always produces exactly 4 bytes.
  @Test("UInt32 encoding size: always produces 4 bytes")
  func testUInt32EncodingSize() async throws {
    property("UInt32 encoding size")
      <- forAll { (value: UInt32) in
        let encoded = MTPEndianCodec.encode(value)
        return encoded.count == 4
      }
  }

  /// Verifies that encoding UInt64 always produces exactly 8 bytes.
  @Test("UInt64 encoding size: always produces 8 bytes")
  func testUInt64EncodingSize() async throws {
    property("UInt64 encoding size")
      <- forAll { (value: UInt64) in
        let encoded = MTPEndianCodec.encode(value)
        return encoded.count == 8
      }
  }

  // MARK: - Monotonicity Invariants

  /// Verifies that for UInt16, if a < b, then encode(a) != encode(b).
  /// Note: Little-endian encoding is NOT lexicographically ordered, but different values
  /// must produce different encodings.
  @Test("UInt16 distinctness: different values produce different encodings")
  func testUInt16Distinctness() async throws {
    property("UInt16 distinctness")
      <- forAll { (a: UInt16, b: UInt16) in
        guard a != b else { return true }  // Skip equal values
        let encodedA = MTPEndianCodec.encode(a)
        let encodedB = MTPEndianCodec.encode(b)
        return encodedA != encodedB
      }
  }

  /// Verifies that for UInt32, different values produce different encodings.
  @Test("UInt32 distinctness: different values produce different encodings")
  func testUInt32Distinctness() async throws {
    property("UInt32 distinctness")
      <- forAll { (a: UInt32, b: UInt32) in
        guard a != b else { return true }  // Skip equal values
        let encodedA = MTPEndianCodec.encode(a)
        let encodedB = MTPEndianCodec.encode(b)
        return encodedA != encodedB
      }
  }

  /// Verifies that for UInt64, different values produce different encodings.
  @Test("UInt64 distinctness: different values produce different encodings")
  func testUInt64Distinctness() async throws {
    property("UInt64 distinctness")
      <- forAll { (a: UInt64, b: UInt64) in
        guard a != b else { return true }  // Skip equal values
        let encodedA = MTPEndianCodec.encode(a)
        let encodedB = MTPEndianCodec.encode(b)
        return encodedA != encodedB
      }
  }

  // MARK: - Decode at Offset Invariants

  /// Verifies that decoding at an offset correctly reads from that position.
  @Test("UInt16 decode at offset: correct value at any offset")
  func testUInt16DecodeAtOffset() async throws {
    property("UInt16 decode at offset")
      <- forAll { (value: UInt16, prefixLength: UInt8) in
        let prefix = Data(repeating: 0xAA, count: Int(prefixLength % 100))
        let suffix = Data(repeating: 0xBB, count: 10)
        var data = prefix
        data.append(MTPEndianCodec.encode(value))
        data.append(suffix)

        let decoded = MTPEndianCodec.decodeUInt16(from: data, at: Int(prefixLength % 100))
        return decoded == value
      }
  }

  /// Verifies that decoding at an offset correctly reads from that position.
  @Test("UInt32 decode at offset: correct value at any offset")
  func testUInt32DecodeAtOffset() async throws {
    property("UInt32 decode at offset")
      <- forAll { (value: UInt32, prefixLength: UInt8) in
        let prefix = Data(repeating: 0xAA, count: Int(prefixLength % 100))
        let suffix = Data(repeating: 0xBB, count: 10)
        var data = prefix
        data.append(MTPEndianCodec.encode(value))
        data.append(suffix)

        let decoded = MTPEndianCodec.decodeUInt32(from: data, at: Int(prefixLength % 100))
        return decoded == value
      }
  }

  /// Verifies that decoding at an offset correctly reads from that position.
  @Test("UInt64 decode at offset: correct value at any offset")
  func testUInt64DecodeAtOffset() async throws {
    property("UInt64 decode at offset")
      <- forAll { (value: UInt64, prefixLength: UInt8) in
        let prefix = Data(repeating: 0xAA, count: Int(prefixLength % 100))
        let suffix = Data(repeating: 0xBB, count: 10)
        var data = prefix
        data.append(MTPEndianCodec.encode(value))
        data.append(suffix)

        let decoded = MTPEndianCodec.decodeUInt64(from: data, at: Int(prefixLength % 100))
        return decoded == value
      }
  }

  // MARK: - Encode to Bytes Invariant

  /// Verifies that encodeToBytes produces the same bytes as encode.
  @Test("encodeToBytes matches encode for UInt16")
  func testEncodeToBytesMatchesEncodeUInt16() async throws {
    property("UInt16 encodeToBytes matches encode")
      <- forAll { (value: UInt16) in
        let data = MTPEndianCodec.encode(value)
        let bytes = MTPEndianCodec.encodeToBytes(value)
        return Array(data) == bytes
      }
  }

  /// Verifies that encodeToBytes produces the same bytes as encode.
  @Test("encodeToBytes matches encode for UInt32")
  func testEncodeToBytesMatchesEncodeUInt32() async throws {
    property("UInt32 encodeToBytes matches encode")
      <- forAll { (value: UInt32) in
        let data = MTPEndianCodec.encode(value)
        let bytes = MTPEndianCodec.encodeToBytes(value)
        return Array(data) == bytes
      }
  }

  /// Verifies that encodeToBytes produces the same bytes as encode.
  @Test("encodeToBytes matches encode for UInt64")
  func testEncodeToBytesMatchesEncodeUInt64() async throws {
    property("UInt64 encodeToBytes matches encode")
      <- forAll { (value: UInt64) in
        let data = MTPEndianCodec.encode(value)
        let bytes = MTPEndianCodec.encodeToBytes(value)
        return Array(data) == bytes
      }
  }

  // MARK: - Generic Decode Invariant

  /// Verifies that the generic decodeLittleEndian works correctly for all types.
  @Test("Generic decodeLittleEndian matches specific decode methods")
  func testGenericDecodeMatchesSpecific() async throws {
    property("UInt16 generic decode")
      <- forAll { (value: UInt16) in
        let encoded = MTPEndianCodec.encode(value)
        let generic = MTPEndianCodec.decodeLittleEndian(encoded, at: 0, as: UInt16.self)
        let specific = MTPEndianCodec.decodeUInt16(from: encoded, at: 0)
        return generic == specific
      }

    property("UInt32 generic decode")
      <- forAll { (value: UInt32) in
        let encoded = MTPEndianCodec.encode(value)
        let generic = MTPEndianCodec.decodeLittleEndian(encoded, at: 0, as: UInt32.self)
        let specific = MTPEndianCodec.decodeUInt32(from: encoded, at: 0)
        return generic == specific
      }

    property("UInt64 generic decode")
      <- forAll { (value: UInt64) in
        let encoded = MTPEndianCodec.encode(value)
        let generic = MTPEndianCodec.decodeLittleEndian(encoded, at: 0, as: UInt64.self)
        let specific = MTPEndianCodec.decodeUInt64(from: encoded, at: 0)
        return generic == specific
      }
  }
}

// MARK: - MTPDataEncoder Property Tests

@Suite("MTPDataEncoder Property-Based Tests")
struct MTPDataEncoderPropertyTests {

  /// Verifies that appending values sequentially produces the same result as encoding them together.
  @Test("Append commutativity: sequential append matches combined encoding")
  func testAppendCommutativity() async throws {
    property("Append commutativity UInt16")
      <- forAll { (a: UInt16, b: UInt16) in
        // Sequential append
        var encoder = MTPDataEncoder()
        encoder.append(a)
        encoder.append(b)
        let sequential = encoder.encodedData

        // Combined encoding
        let combined = MTPEndianCodec.encode(a) + MTPEndianCodec.encode(b)

        return sequential == combined
      }

    property("Append commutativity UInt32")
      <- forAll { (a: UInt32, b: UInt32) in
        var encoder = MTPDataEncoder()
        encoder.append(a)
        encoder.append(b)
        let sequential = encoder.encodedData

        let combined = MTPEndianCodec.encode(a) + MTPEndianCodec.encode(b)

        return sequential == combined
      }

    property("Append commutativity UInt64")
      <- forAll { (a: UInt64, b: UInt64) in
        var encoder = MTPDataEncoder()
        encoder.append(a)
        encoder.append(b)
        let sequential = encoder.encodedData

        let combined = MTPEndianCodec.encode(a) + MTPEndianCodec.encode(b)

        return sequential == combined
      }
  }

  /// Verifies that the encoder's count property correctly tracks the number of bytes written.
  @Test("Encoder count tracks bytes correctly")
  func testEncoderCountTracking() async throws {
    property("Encoder count")
      <- forAll { (a: UInt16, b: UInt32, c: UInt64) in
        var encoder = MTPDataEncoder()
        #expect(encoder.count == 0)

        encoder.append(a)
        let countAfterA = encoder.count
        let expectedCountA = 2

        encoder.append(b)
        let countAfterB = encoder.count
        let expectedCountB = expectedCountA + 4

        encoder.append(c)
        let countAfterC = encoder.count
        let expectedCountC = expectedCountB + 8

        return countAfterA == expectedCountA
          && countAfterB == expectedCountB
          && countAfterC == expectedCountC
      }
  }

  /// Verifies that reset clears all data but maintains capacity.
  @Test("Reset clears data")
  func testResetClearsData() async throws {
    property("Reset clears data")
      <- forAll { (values: [UInt32]) in
        guard !values.isEmpty else { return true }

        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        // Verify data was added
        let countBeforeReset = encoder.count
        guard countBeforeReset > 0 else { return false }

        // Reset
        encoder.reset()

        // Verify data is cleared
        return encoder.count == 0 && encoder.encodedData.isEmpty
      }
  }
}

// MARK: - MTPDataDecoder Property Tests

@Suite("MTPDataDecoder Property-Based Tests")
struct MTPDataDecoderPropertyTests {

  /// Verifies that sequential reads produce the same values that were encoded.
  @Test("Sequential read matches sequential write")
  func testSequentialReadMatchesWrite() async throws {
    property("Sequential read/write UInt16")
      <- forAll { (values: [UInt16]) in
        guard values.count > 0 && values.count < 100 else { return true }

        // Encode all values
        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        // Decode sequentially
        var decoder = MTPDataDecoder(data: encoder.encodedData)
        for originalValue in values {
          guard let decoded = decoder.readUInt16() else { return false }
          guard decoded == originalValue else { return false }
        }

        return true
      }

    property("Sequential read/write UInt32")
      <- forAll { (values: [UInt32]) in
        guard values.count > 0 && values.count < 100 else { return true }

        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        var decoder = MTPDataDecoder(data: encoder.encodedData)
        for originalValue in values {
          guard let decoded = decoder.readUInt32() else { return false }
          guard decoded == originalValue else { return false }
        }

        return true
      }

    property("Sequential read/write UInt64")
      <- forAll { (values: [UInt64]) in
        guard values.count > 0 && values.count < 100 else { return true }

        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        var decoder = MTPDataDecoder(data: encoder.encodedData)
        for originalValue in values {
          guard let decoded = decoder.readUInt64() else { return false }
          guard decoded == originalValue else { return false }
        }

        return true
      }
  }

  /// Verifies that peek does not advance the offset.
  @Test("Peek does not advance offset")
  func testPeekDoesNotAdvanceOffset() async throws {
    property("Peek UInt16")
      <- forAll { (value: UInt16) in
        let data = MTPEndianCodec.encode(value)
        var decoder = MTPDataDecoder(data: data)

        // Peek multiple times
        let peek1 = decoder.peekUInt16()
        let peek2 = decoder.peekUInt16()
        let peek3 = decoder.peekUInt16()

        // Offset should still be 0
        return peek1 == value && peek2 == value && peek3 == value && decoder.currentOffset == 0
      }

    property("Peek UInt32")
      <- forAll { (value: UInt32) in
        let data = MTPEndianCodec.encode(value)
        var decoder = MTPDataDecoder(data: data)

        let peek1 = decoder.peekUInt32()
        let peek2 = decoder.peekUInt32()

        return peek1 == value && peek2 == value && decoder.currentOffset == 0
      }
  }

  /// Verifies that remainingBytes is correctly calculated.
  @Test("Remaining bytes calculation")
  func testRemainingBytesCalculation() async throws {
    property("Remaining bytes")
      <- forAll { (values: [UInt32]) in
        guard values.count > 0 && values.count < 50 else { return true }

        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        var decoder = MTPDataDecoder(data: encoder.encodedData)
        let totalBytes = values.count * 4

        for (index, _) in values.enumerated() {
          let expectedRemaining = totalBytes - (index * 4)
          if decoder.remainingBytes != expectedRemaining {
            return false
          }
          _ = decoder.readUInt32()
        }

        return decoder.remainingBytes == 0
      }
  }

  /// Verifies that seek correctly sets the offset.
  @Test("Seek sets offset correctly")
  func testSeekSetsOffset() async throws {
    property("Seek")
      <- forAll { (values: [UInt16], seekIndex: UInt8) in
        guard values.count > 1 else { return true }

        var encoder = MTPDataEncoder()
        for value in values {
          encoder.append(value)
        }

        var decoder = MTPDataDecoder(data: encoder.encodedData)
        let targetIndex = Int(seekIndex) % values.count
        let targetOffset = targetIndex * 2

        decoder.seek(to: targetOffset)

        if decoder.currentOffset != targetOffset {
          return false
        }

        // Read should return the value at that position
        guard let decoded = decoder.readUInt16() else {
          return false
        }

        return decoded == values[targetIndex]
      }
  }
}

// MARK: - Parameterized Tests with Swift Testing

@Suite("MTPEndianCodec Parameterized Tests")
struct MTPEndianCodecParameterizedTests {

  /// Test round-trip for edge cases using parameterized tests.
  @Test(
    "UInt16 edge cases round-trip",
    arguments: [
      UInt16.min,
      UInt16.max,
      0x0001,
      0x00FF,
      0x0100,
      0x7FFF,
      0x8000,
      0xFFFE,
      0xAAAA,
      0x5555,
    ])
  func testUInt16EdgeCases(value: UInt16) async throws {
    let encoded = MTPEndianCodec.encode(value)
    let decoded = MTPEndianCodec.decodeUInt16(from: encoded, at: 0)
    #expect(decoded == value)
  }

  /// Test round-trip for edge cases using parameterized tests.
  @Test(
    "UInt32 edge cases round-trip",
    arguments: [
      UInt32.min,
      UInt32.max,
      0x00000001,
      0x000000FF,
      0x00000100,
      0x0000FFFF,
      0x00010000,
      0x7FFFFFFF,
      0x80000000,
      0xFFFFFFFE,
      0xDEADBEEF,
      0xCAFEBABE,
    ])
  func testUInt32EdgeCases(value: UInt32) async throws {
    let encoded = MTPEndianCodec.encode(value)
    let decoded = MTPEndianCodec.decodeUInt32(from: encoded, at: 0)
    #expect(decoded == value)
  }

  /// Test round-trip for edge cases using parameterized tests.
  @Test(
    "UInt64 edge cases round-trip",
    arguments: [
      UInt64.min,
      UInt64.max,
      0x0000000000000001,
      0x00000000FFFFFFFF,
      0xFFFFFFFF00000000,
      0x7FFFFFFFFFFFFFFF,
      0x8000000000000000,
      0xFFFFFFFFFFFFFFFE,
      0x0123456789ABCDEF,
      0xFEDCBA9876543210,
    ])
  func testUInt64EdgeCases(value: UInt64) async throws {
    let encoded = MTPEndianCodec.encode(value)
    let decoded = MTPEndianCodec.decodeUInt64(from: encoded, at: 0)
    #expect(decoded == value)
  }

  /// Test byte order verification for known values.
  @Test(
    "UInt16 byte order verification",
    arguments: [
      (UInt16(0x0000), [0x00, 0x00]),
      (UInt16(0x0001), [0x01, 0x00]),
      (UInt16(0x0100), [0x00, 0x01]),
      (UInt16(0xFFFF), [0xFF, 0xFF]),
      (UInt16(0x1234), [0x34, 0x12]),
      (UInt16(0xABCD), [0xCD, 0xAB]),
    ])
  func testUInt16ByteOrderVerification(value: UInt16, expected: [UInt8]) async throws {
    let encoded = MTPEndianCodec.encode(value)
    #expect(Array(encoded) == expected)
  }

  /// Test byte order verification for known values.
  @Test(
    "UInt32 byte order verification",
    arguments: [
      (UInt32(0x00000000), [0x00, 0x00, 0x00, 0x00]),
      (UInt32(0x00000001), [0x01, 0x00, 0x00, 0x00]),
      (UInt32(0x00000100), [0x00, 0x01, 0x00, 0x00]),
      (UInt32(0x00010000), [0x00, 0x00, 0x01, 0x00]),
      (UInt32(0x01000000), [0x00, 0x00, 0x00, 0x01]),
      (UInt32(0x12345678), [0x78, 0x56, 0x34, 0x12]),
      (UInt32(0xDEADBEEF), [0xEF, 0xBE, 0xAD, 0xDE]),
    ])
  func testUInt32ByteOrderVerification(value: UInt32, expected: [UInt8]) async throws {
    let encoded = MTPEndianCodec.encode(value)
    #expect(Array(encoded) == expected)
  }

  /// Test byte order verification for known values.
  @Test(
    "UInt64 byte order verification",
    arguments: [
      (UInt64(0x0000000000000000), [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      (UInt64(0x0100000000000000), [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]),
      (UInt64(0x0000000000000001), [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      (UInt64(0x0123456789ABCDEF), [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]),
    ])
  func testUInt64ByteOrderVerification(value: UInt64, expected: [UInt8]) async throws {
    let encoded = MTPEndianCodec.encode(value)
    #expect(Array(encoded) == expected)
  }
}
