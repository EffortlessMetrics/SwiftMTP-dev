// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import MTPEndianCodec
@testable import SwiftMTPCore

// MARK: - Codec Performance Tests

/// Performance-oriented tests that verify the codec handles large workloads correctly.
/// These are not benchmark measurements but correctness tests under load.
@Suite("Codec Performance Correctness")
struct CodecPerformanceCorrectnessTests {

  @Test("Large sequential UInt32 encode produces correct byte count")
  func testLargeSequentialEncode() {
    let count = 10_000
    var encoder = MTPDataEncoder(capacity: count * 4)
    for i in 0..<UInt32(count) {
      encoder.append(i)
    }
    #expect(encoder.count == count * 4)

    // Spot-check first and last values
    var decoder = MTPDataDecoder(data: encoder.encodedData)
    #expect(decoder.readUInt32() == 0)
    decoder.seek(to: (count - 1) * 4)
    #expect(decoder.readUInt32() == UInt32(count - 1))
  }

  @Test("Large sequential UInt16 encode/decode round-trip")
  func testLargeSequentialUInt16RoundTrip() {
    let count = 10_000
    var encoder = MTPDataEncoder(capacity: count * 2)
    for i in 0..<UInt16(min(count, Int(UInt16.max))) {
      encoder.append(i)
    }

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    for i in 0..<UInt16(min(count, Int(UInt16.max))) {
      let value = decoder.readUInt16()
      #expect(value == i, "Mismatch at index \(i)")
    }
  }

  @Test("Large sequential UInt64 encode/decode round-trip")
  func testLargeSequentialUInt64RoundTrip() {
    let count = 5_000
    var encoder = MTPDataEncoder(capacity: count * 8)
    for i in 0..<UInt64(count) {
      encoder.append(i &* 0x0123456789ABCDEF)
    }

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    for i in 0..<UInt64(count) {
      let value = decoder.readUInt64()
      #expect(value == i &* 0x0123456789ABCDEF, "Mismatch at index \(i)")
    }
  }

  @Test("Bulk raw buffer encode/decode round-trip")
  func testBulkRawBufferRoundTrip() {
    let count = 10_000
    var buffer = [UInt8](repeating: 0, count: count * 4)
    buffer.withUnsafeMutableBufferPointer { ptr in
      let base = UnsafeMutableRawPointer(ptr.baseAddress!)
      for i in 0..<count {
        MTPEndianCodec.encode(UInt32(i), into: base, at: i * 4)
      }
    }

    let data = Data(buffer)
    data.withUnsafeBytes { ptr in
      guard let base = ptr.baseAddress else { return }
      for i in 0..<count {
        let value = MTPEndianCodec.decodeUInt32(from: base, at: i * 4)
        #expect(value == UInt32(i), "Raw buffer mismatch at index \(i)")
      }
    }
  }

  @Test("Multiple PTPString encodes produce valid data")
  func testBulkStringEncode() {
    let strings = (0..<100).map { "file_\($0).jpg" }
    for s in strings {
      let encoded = PTPString.encode(s)
      var offset = 0
      let decoded = PTPString.parse(from: encoded, at: &offset)
      #expect(decoded == s)
    }
  }

  @Test("Bulk ObjectInfoDataset encoding")
  func testBulkObjectInfoEncoding() {
    for i in 0..<100 {
      let data = PTPObjectInfoDataset.encode(
        storageID: 0x00010001,
        parentHandle: UInt32(i),
        format: 0x3000,
        size: UInt64(i * 1024),
        name: "file_\(i).bin")
      #expect(data.count > 0)

      var decoder = MTPDataDecoder(data: data)
      #expect(decoder.readUInt32() == 0x00010001)  // storageID
    }
  }

  @Test("Mixed-width sequential reads at scale")
  func testMixedWidthAtScale() {
    var encoder = MTPDataEncoder(capacity: 15 * 1000)
    for i in 0..<1000 {
      encoder.append(UInt8(UInt8(truncatingIfNeeded: i)))
      encoder.append(UInt16(UInt16(truncatingIfNeeded: i)))
      encoder.append(UInt32(UInt32(i)))
      encoder.append(UInt64(UInt64(i)))
    }
    #expect(encoder.count == 15 * 1000)

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    for i in 0..<1000 {
      let u8 = decoder.readUInt8()
      let u16 = decoder.readUInt16()
      let u32 = decoder.readUInt32()
      let u64 = decoder.readUInt64()
      #expect(u8 == UInt8(truncatingIfNeeded: i))
      #expect(u16 == UInt16(truncatingIfNeeded: i))
      #expect(u32 == UInt32(i))
      #expect(u64 == UInt64(i))
    }
    #expect(!decoder.hasRemaining)
  }
}
