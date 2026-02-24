// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import MTPEndianCodec

// MARK: - Fuzz Tests

/// Bounded fuzz tests for MTPEndianCodec.
///
/// These tests generate random byte sequences and verify that the decoder handles
/// all inputs gracefully without crashing. The tests use a fixed seed for
/// reproducibility in CI environments.
///
/// ## Test Strategy
///
/// 1. Generate random byte sequences of various lengths
/// 2. Test all decoder methods with these sequences
/// 3. Verify no crashes occur (memory safety)
/// 4. Test boundary conditions (offset at end, past end, negative)
///
/// ## Running Tests
///
/// These tests are designed to run in CI with a bounded number of iterations.
/// For more extensive fuzzing, use the `MTPEndianCodecFuzz` executable target.
@Suite("MTPEndianCodec Fuzz Tests")
struct MTPEndianCodecFuzzTests {

  // MARK: - Test Configuration

  /// Number of fuzz iterations to run. Kept low for CI performance.
  static let fuzzIterations = 10_000

  /// Fixed seed for reproducible fuzz tests.
  static let fuzzSeed: UInt64 = 42

  // MARK: - Random Data Generator

  /// A simple deterministic random number generator for fuzzing.
  /// Uses xorshift64 for reproducibility.
  struct FuzzRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
      self.state = seed
    }

    mutating func next() -> UInt64 {
      // xorshift64
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }
  }

  /// Generates random data of the specified length.
  static func generateRandomData(length: Int, using rng: inout FuzzRNG) -> Data {
    var data = Data(capacity: length)
    for _ in 0..<length {
      data.append(UInt8.random(in: 0...255, using: &rng))
    }
    return data
  }

  /// Generates random byte array of the specified length.
  static func generateRandomBytes(length: Int, using rng: inout FuzzRNG) -> [UInt8] {
    (0..<length).map { _ in UInt8.random(in: 0...255, using: &rng) }
  }

  // MARK: - UInt16 Decoder Fuzz Tests

  /// Fuzz test for UInt16 decoding from Data.
  @Test("UInt16 decode from Data - fuzz test with random bytes")
  func testFuzzDecodeUInt16FromData() async throws {
    var rng = FuzzRNG(seed: fuzzSeed)

    for iteration in 0..<fuzzIterations {
      // Generate random data of various lengths
      let dataLength = Int.random(in: 0...32, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)

      // Test at random offset
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash - only return nil or a valid value
      let result = MTPEndianCodec.decodeUInt16(from: data, at: offset)

      // Verify the result is valid if not nil
      if let value = result {
        // If we got a value, verify it can be re-encoded
        let reencoded = MTPEndianCodec.encode(value)
        #expect(reencoded.count == 2)

        // Verify the bytes match what was in the data
        if offset >= 0 && offset + 2 <= data.count {
          #expect(data[offset] == reencoded[0])
          #expect(data[offset + 1] == reencoded[1])
        }
      } else {
        // nil is expected for invalid offsets or insufficient data
        let isValidOffset = offset >= 0 && offset + 2 <= data.count
        #expect(!isValidOffset, "Should have decoded successfully at iteration \(iteration)")
      }
    }
  }

  /// Fuzz test for UInt16 decoding from byte array.
  @Test("UInt16 decode from byte array - fuzz test with random bytes")
  func testFuzzDecodeUInt16FromBytes() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 1)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let bytes = generateRandomBytes(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash
      let result = MTPEndianCodec.decodeUInt16(from: bytes, at: offset)

      // Verify result consistency
      if result != nil {
        let isValidOffset = offset >= 0 && offset + 2 <= bytes.count
        #expect(isValidOffset)
      }
    }
  }

  // MARK: - UInt32 Decoder Fuzz Tests

  /// Fuzz test for UInt32 decoding from Data.
  @Test("UInt32 decode from Data - fuzz test with random bytes")
  func testFuzzDecodeUInt32FromData() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 2)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash
      let result = MTPEndianCodec.decodeUInt32(from: data, at: offset)

      if result != nil {
        let isValidOffset = offset >= 0 && offset + 4 <= data.count
        #expect(isValidOffset)
      }
    }
  }

  /// Fuzz test for UInt32 decoding from byte array.
  @Test("UInt32 decode from byte array - fuzz test with random bytes")
  func testFuzzDecodeUInt32FromBytes() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 3)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let bytes = generateRandomBytes(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash
      let result = MTPEndianCodec.decodeUInt32(from: bytes, at: offset)

      if result != nil {
        let isValidOffset = offset >= 0 && offset + 4 <= bytes.count
        #expect(isValidOffset)
      }
    }
  }

  // MARK: - UInt64 Decoder Fuzz Tests

  /// Fuzz test for UInt64 decoding from Data.
  @Test("UInt64 decode from Data - fuzz test with random bytes")
  func testFuzzDecodeUInt64FromData() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 4)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash
      let result = MTPEndianCodec.decodeUInt64(from: data, at: offset)

      if result != nil {
        let isValidOffset = offset >= 0 && offset + 8 <= data.count
        #expect(isValidOffset)
      }
    }
  }

  /// Fuzz test for UInt64 decoding from byte array.
  @Test("UInt64 decode from byte array - fuzz test with random bytes")
  func testFuzzDecodeUInt64FromBytes() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 5)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let bytes = generateRandomBytes(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // This should never crash
      let result = MTPEndianCodec.decodeUInt64(from: bytes, at: offset)

      if result != nil {
        let isValidOffset = offset >= 0 && offset + 8 <= bytes.count
        #expect(isValidOffset)
      }
    }
  }

  // MARK: - Generic Decoder Fuzz Tests

  /// Fuzz test for generic decodeLittleEndian method.
  @Test("Generic decodeLittleEndian - fuzz test with random bytes")
  func testFuzzGenericDecode() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 6)

    for _ in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...32, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)
      let offset = Int.random(in: -8...32, using: &rng)

      // Test UInt16
      let u16 = MTPEndianCodec.decodeLittleEndian(data, at: offset, as: UInt16.self)
      if u16 != nil {
        let isValidOffset = offset >= 0 && offset + 2 <= data.count
        #expect(isValidOffset)
      }

      // Test UInt32
      let u32 = MTPEndianCodec.decodeLittleEndian(data, at: offset, as: UInt32.self)
      if u32 != nil {
        let isValidOffset = offset >= 0 && offset + 4 <= data.count
        #expect(isValidOffset)
      }

      // Test UInt64
      let u64 = MTPEndianCodec.decodeLittleEndian(data, at: offset, as: UInt64.self)
      if u64 != nil {
        let isValidOffset = offset >= 0 && offset + 8 <= data.count
        #expect(isValidOffset)
      }
    }
  }

  // MARK: - Raw Buffer Decoder Fuzz Tests

  /// Fuzz test for raw buffer decoding.
  /// Note: Raw buffer methods don't do bounds checking - they assume valid input.
  /// We test with valid buffers only to ensure no crashes with correct usage.
  @Test("Raw buffer decode - fuzz test with valid buffers")
  func testFuzzRawBufferDecode() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 7)

    for _ in 0..<fuzzIterations {
      // Generate enough data for all types
      let data = generateRandomData(length: 16, using: &rng)

      data.withUnsafeBytes { ptr in
        guard let baseAddress = ptr.baseAddress else { return }

        // These should never crash with valid buffer
        let u16 = MTPEndianCodec.decodeUInt16(from: baseAddress, at: 0)
        let u32 = MTPEndianCodec.decodeUInt32(from: baseAddress, at: 0)
        let u64 = MTPEndianCodec.decodeUInt64(from: baseAddress, at: 0)

        // Verify round-trip
        let encoded16 = MTPEndianCodec.encode(u16)
        let encoded32 = MTPEndianCodec.encode(u32)
        let encoded64 = MTPEndianCodec.encode(u64)

        #expect(encoded16.count == 2)
        #expect(encoded32.count == 4)
        #expect(encoded64.count == 8)
      }
    }
  }

  // MARK: - MTPDataDecoder Fuzz Tests

  /// Fuzz test for MTPDataDecoder with random data.
  @Test("MTPDataDecoder - fuzz test with random data")
  func testFuzzMTPDataDecoder() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 8)

    for iteration in 0..<fuzzIterations {
      let dataLength = Int.random(in: 0...64, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)

      var decoder = MTPDataDecoder(data: data)

      // Try to read various types - should never crash
      var totalRead = 0

      // Read UInt8s
      while totalRead < dataLength {
        guard let _ = decoder.readUInt8() else {
          break
        }
        totalRead += 1
      }

      // Reset and try UInt16
      decoder.reset()
      totalRead = 0
      while totalRead + 2 <= dataLength {
        guard let _ = decoder.readUInt16() else {
          break
        }
        totalRead += 2
      }

      // Reset and try UInt32
      decoder.reset()
      totalRead = 0
      while totalRead + 4 <= dataLength {
        guard let _ = decoder.readUInt32() else {
          break
        }
        totalRead += 4
      }

      // Reset and try UInt64
      decoder.reset()
      totalRead = 0
      while totalRead + 8 <= dataLength {
        guard let _ = decoder.readUInt64() else {
          break
        }
        totalRead += 8
      }

      // Test seek to random position
      let seekPos = Int.random(in: 0...max(0, dataLength), using: &rng)
      decoder.seek(to: seekPos)
      #expect(decoder.currentOffset == seekPos)

      // Test skip
      let skipAmount = Int.random(in: 0...16, using: &rng)
      let offsetBeforeSkip = decoder.currentOffset
      decoder.skip(skipAmount)
      #expect(decoder.currentOffset == min(offsetBeforeSkip + skipAmount, dataLength))

      // Test peek
      if decoder.remainingBytes >= 4 {
        let peekValue = decoder.peekUInt32()
        #expect(peekValue != nil)
        // Peek shouldn't advance offset
        let peekOffset = decoder.currentOffset
        _ = decoder.peekUInt32()
        #expect(decoder.currentOffset == peekOffset)
      }
    }
  }

  // MARK: - Boundary Condition Tests

  /// Test decoder behavior at exact boundaries.
  @Test("Boundary conditions - exact buffer boundaries")
  func testBoundaryConditions() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 9)

    for _ in 0..<1000 {
      // Test with exactly 2 bytes
      let data2 = generateRandomData(length: 2, using: &rng)
      #expect(MTPEndianCodec.decodeUInt16(from: data2, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data2, at: 0) == nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data2, at: 0) == nil)

      // Test with exactly 4 bytes
      let data4 = generateRandomData(length: 4, using: &rng)
      #expect(MTPEndianCodec.decodeUInt16(from: data4, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt16(from: data4, at: 2) != nil)
      #expect(MTPEndianCodec.decodeUInt16(from: data4, at: 3) == nil)  // Only 1 byte left
      #expect(MTPEndianCodec.decodeUInt32(from: data4, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data4, at: 0) == nil)

      // Test with exactly 8 bytes
      let data8 = generateRandomData(length: 8, using: &rng)
      #expect(MTPEndianCodec.decodeUInt16(from: data8, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt16(from: data8, at: 6) != nil)
      #expect(MTPEndianCodec.decodeUInt16(from: data8, at: 7) == nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data8, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data8, at: 4) != nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data8, at: 5) == nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data8, at: 0) != nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data8, at: 1) == nil)
    }
  }

  /// Test decoder behavior with empty data.
  @Test("Empty data handling")
  func testEmptyData() async throws {
    let emptyData = Data()
    let emptyBytes: [UInt8] = []

    // All decodes should return nil for empty data
    #expect(MTPEndianCodec.decodeUInt16(from: emptyData, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: emptyData, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: emptyData, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt16(from: emptyBytes, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: emptyBytes, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: emptyBytes, at: 0) == nil)

    // MTPDataDecoder with empty data
    var decoder = MTPDataDecoder(data: emptyData)
    #expect(decoder.remainingBytes == 0)
    #expect(!decoder.hasRemaining)
    #expect(decoder.readUInt8() == nil)
    #expect(decoder.readUInt16() == nil)
    #expect(decoder.readUInt32() == nil)
    #expect(decoder.readUInt64() == nil)
  }

  /// Test decoder behavior with negative offsets.
  @Test("Negative offset handling")
  func testNegativeOffsets() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 10)

    for _ in 0..<1000 {
      let data = generateRandomData(length: 16, using: &rng)
      let negativeOffset = -Int.random(in: 1...100, using: &rng)

      // All decodes should return nil for negative offsets
      #expect(MTPEndianCodec.decodeUInt16(from: data, at: negativeOffset) == nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data, at: negativeOffset) == nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data, at: negativeOffset) == nil)
    }
  }

  /// Test decoder behavior with offsets past the end.
  @Test("Offset past end handling")
  func testOffsetPastEnd() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 11)

    for _ in 0..<1000 {
      let dataLength = Int.random(in: 1...16, using: &rng)
      let data = generateRandomData(length: dataLength, using: &rng)
      let pastEndOffset = dataLength + Int.random(in: 0...100, using: &rng)

      // All decodes should return nil for offsets past end
      #expect(MTPEndianCodec.decodeUInt16(from: data, at: pastEndOffset) == nil)
      #expect(MTPEndianCodec.decodeUInt32(from: data, at: pastEndOffset) == nil)
      #expect(MTPEndianCodec.decodeUInt64(from: data, at: pastEndOffset) == nil)
    }
  }

  // MARK: - MTPDataEncoder Fuzz Tests

  /// Fuzz test for MTPDataEncoder with random values.
  @Test("MTPDataEncoder - fuzz test with random values")
  func testFuzzMTPDataEncoder() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 12)

    for _ in 0..<fuzzIterations {
      var encoder = MTPDataEncoder()
      var expectedData = Data()

      // Append random values of various types
      let operationCount = Int.random(in: 0...20, using: &rng)

      for _ in 0..<operationCount {
        let operationType = Int.random(in: 0...5, using: &rng)

        switch operationType {
        case 0:
          // Append UInt16
          let value = UInt16.random(in: .min ... .max, using: &rng)
          encoder.append(value)
          expectedData.append(MTPEndianCodec.encode(value))

        case 1:
          // Append UInt32
          let value = UInt32.random(in: .min ... .max, using: &rng)
          encoder.append(value)
          expectedData.append(MTPEndianCodec.encode(value))

        case 2:
          // Append UInt64
          let value = UInt64.random(in: .min ... .max, using: &rng)
          encoder.append(value)
          expectedData.append(MTPEndianCodec.encode(value))

        case 3:
          // Append UInt8
          let value = UInt8.random(in: .min ... .max, using: &rng)
          encoder.append(value)
          expectedData.append(value)

        case 4:
          // Append bytes
          let byteCount = Int.random(in: 0...8, using: &rng)
          let bytes = generateRandomBytes(length: byteCount, using: &rng)
          encoder.append(contentsOf: bytes)
          expectedData.append(contentsOf: bytes)

        case 5:
          // Append Data
          let dataLength = Int.random(in: 0...8, using: &rng)
          let data = generateRandomData(length: dataLength, using: &rng)
          encoder.append(data)
          expectedData.append(data)

        default:
          break
        }
      }

      // Verify the encoded data matches expected
      #expect(encoder.encodedData == expectedData)
      #expect(encoder.count == expectedData.count)
    }
  }

  // MARK: - Round-Trip Fuzz Tests

  /// Fuzz test for round-trip encoding/decoding.
  @Test("Round-trip fuzz test - encode then decode")
  func testFuzzRoundTrip() async throws {
    var rng = FuzzRNG(seed: fuzzSeed &+ 13)

    for _ in 0..<fuzzIterations {
      // UInt16 round-trip
      let u16 = UInt16.random(in: .min ... .max, using: &rng)
      let encoded16 = MTPEndianCodec.encode(u16)
      let decoded16 = MTPEndianCodec.decodeUInt16(from: encoded16, at: 0)
      #expect(decoded16 == u16)

      // UInt32 round-trip
      let u32 = UInt32.random(in: .min ... .max, using: &rng)
      let encoded32 = MTPEndianCodec.encode(u32)
      let decoded32 = MTPEndianCodec.decodeUInt32(from: encoded32, at: 0)
      #expect(decoded32 == u32)

      // UInt64 round-trip
      let u64 = UInt64.random(in: .min ... .max, using: &rng)
      let encoded64 = MTPEndianCodec.encode(u64)
      let decoded64 = MTPEndianCodec.decodeUInt64(from: encoded64, at: 0)
      #expect(decoded64 == u64)
    }
  }
}

// MARK: - Crash Test Fixtures

/// Test fixtures for known crash-inducing inputs.
/// These are inputs that have been found to cause issues in other implementations
/// and should be tested to ensure our implementation handles them correctly.
@Suite("MTPEndianCodec Crash Fixture Tests")
struct MTPEndianCodecCrashFixtureTests {

  /// Test with all-zero bytes.
  @Test("All-zero bytes")
  func testAllZeroBytes() async throws {
    let zeros = Data(repeating: 0, count: 16)

    #expect(MTPEndianCodec.decodeUInt16(from: zeros, at: 0) == 0)
    #expect(MTPEndianCodec.decodeUInt32(from: zeros, at: 0) == 0)
    #expect(MTPEndianCodec.decodeUInt64(from: zeros, at: 0) == 0)
  }

  /// Test with all-FF bytes.
  @Test("All-FF bytes")
  func testAllFFBytes() async throws {
    let allFF = Data(repeating: 0xFF, count: 16)

    #expect(MTPEndianCodec.decodeUInt16(from: allFF, at: 0) == UInt16.max)
    #expect(MTPEndianCodec.decodeUInt32(from: allFF, at: 0) == UInt32.max)
    #expect(MTPEndianCodec.decodeUInt64(from: allFF, at: 0) == UInt64.max)
  }

  /// Test with alternating bytes.
  @Test("Alternating byte pattern")
  func testAlternatingBytes() async throws {
    let alternating = Data([0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55])

    let u16 = MTPEndianCodec.decodeUInt16(from: alternating, at: 0)
    #expect(u16 == 0x55AA)

    let u32 = MTPEndianCodec.decodeUInt32(from: alternating, at: 0)
    #expect(u32 == 0x55AA55AA)

    let u64 = MTPEndianCodec.decodeUInt64(from: alternating, at: 0)
    #expect(u64 == 0x55AA55AA55AA55AA)
  }

  /// Test with single byte.
  @Test("Single byte data")
  func testSingleByte() async throws {
    let singleByte = Data([0x42])

    #expect(MTPEndianCodec.decodeUInt16(from: singleByte, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: singleByte, at: 0) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: singleByte, at: 0) == nil)
  }

  /// Test with maximum valid offset.
  @Test("Maximum valid offset")
  func testMaximumValidOffset() async throws {
    // For UInt16, offset 6 is the last valid offset in 8 bytes
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

    let u16 = MTPEndianCodec.decodeUInt16(from: data, at: 6)
    #expect(u16 == 0x0807)

    // Offset 7 should fail (only 1 byte available)
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 7) == nil)
  }

  /// Test with Int.max offset (should not crash).
  @Test("Int.max offset")
  func testIntMaxOffset() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04])

    // Should return nil without crashing
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: Int.max) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: Int.max) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: Int.max) == nil)
  }

  /// Test with Int.min offset (should not crash).
  @Test("Int.min offset")
  func testIntMinOffset() async throws {
    let data = Data([0x01, 0x02, 0x03, 0x04])

    // Should return nil without crashing
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: Int.min) == nil)
    #expect(MTPEndianCodec.decodeUInt32(from: data, at: Int.min) == nil)
    #expect(MTPEndianCodec.decodeUInt64(from: data, at: Int.min) == nil)
  }
}
