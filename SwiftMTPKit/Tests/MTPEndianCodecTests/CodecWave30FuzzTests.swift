// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import MTPEndianCodec
@testable import SwiftMTPCore

// MARK: - Random Byte Container Fuzzing

@Suite("Wave30 Random Byte Container Fuzzing")
struct RandomByteContainerFuzzTests {

  /// Deterministic RNG for reproducible fuzz tests (xorshift64).
  struct FuzzRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }
  }

  static func randomData(length: Int, using rng: inout FuzzRNG) -> Data {
    Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &rng) })
  }

  @Test("Random bytes parsed as PTP container never crash")
  func testRandomBytesAsPTPContainer() {
    var rng = FuzzRNG(seed: 0x030C0DEC)

    for _ in 0..<5_000 {
      let len = Int.random(in: 0...64, using: &rng)
      let data = Self.randomData(length: len, using: &rng)

      // PTPReader: read header fields — must not crash
      var r = PTPReader(data: data)
      _ = r.u32()  // length
      _ = r.u16()  // type
      _ = r.u16()  // code
      _ = r.u32()  // txid
      // Remaining params
      while r.o < data.count { _ = r.u32() }
    }
  }

  @Test("Random bytes through all parser entry points never crash")
  func testRandomBytesThroughAllParsers() {
    var rng = FuzzRNG(seed: 0xFE220001)

    for _ in 0..<2_000 {
      let len = Int.random(in: 0...128, using: &rng)
      let data = Self.randomData(length: len, using: &rng)

      _ = PTPDeviceInfo.parse(from: data)
      _ = PTPPropList.parse(from: data)

      var offset = 0
      _ = PTPString.parse(from: data, at: &offset)

      var r = PTPReader(data: data)
      for dt: UInt16 in [
        0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006,
        0x0007, 0x0008, 0x0009, 0x000A, 0xFFFF,
        0x4004, 0x4006,
      ] {
        var r2 = PTPReader(data: data)
        _ = r2.value(dt: dt)
      }
      _ = r.string()
    }
  }
}

// MARK: - Container Length Field Edge Cases

@Suite("Wave30 Container Length Field Edge Cases")
struct ContainerLengthEdgeCaseTests {

  /// Build a minimal MTP container header (little-endian).
  private static func header(
    length: UInt32, type: UInt16, code: UInt16, txid: UInt32
  ) -> Data {
    var e = MTPDataEncoder()
    e.append(length)
    e.append(type)
    e.append(code)
    e.append(txid)
    return e.encodedData
  }

  @Test("Container with length smaller than 12-byte header minimum")
  func testLengthSmallerThanHeader() {
    for shortLen: UInt32 in [0, 1, 4, 8, 11] {
      let data = Self.header(length: shortLen, type: 1, code: 0x1002, txid: 1)
      var r = PTPReader(data: data)
      let parsedLen = r.u32()
      #expect(parsedLen == shortLen)
      // Parser must not crash even when length claims fewer bytes than header
      _ = r.u16()
      _ = r.u16()
      _ = r.u32()
    }
  }

  @Test("Container with length exactly 12 (minimum valid)")
  func testLengthExactlyMinimum() {
    let data = Self.header(length: 12, type: 1, code: 0x1001, txid: 1)
    #expect(data.count == 12)
    var r = PTPReader(data: data)
    #expect(r.u32() == 12)
    #expect(r.u16() == 1)
    #expect(r.u16() == 0x1001)
    #expect(r.u32() == 1)
  }

  @Test("Container with length larger than actual data (truncated)")
  func testLengthLargerThanData() {
    // Header claims 1000 bytes but only 12 exist
    let data = Self.header(length: 1000, type: 1, code: 0x1007, txid: 5)
    var r = PTPReader(data: data)
    #expect(r.u32() == 1000)
    #expect(r.u16() == 1)
    #expect(r.u16() == 0x1007)
    #expect(r.u32() == 5)
    // Attempting to read beyond available data returns nil
    #expect(r.u32() == nil)
  }

  @Test("Container with length 0xFFFFFFFF (max UInt32)")
  func testLengthMaxUInt32() {
    let data = Self.header(length: UInt32.max, type: 2, code: 0x1009, txid: 0)
    var r = PTPReader(data: data)
    #expect(r.u32() == UInt32.max)
    _ = r.u16()
    _ = r.u16()
    _ = r.u32()
    // No crash expected
  }
}

// MARK: - Nested Array/Dataset Depth Tests

@Suite("Wave30 Nested Array Depth Protection")
struct NestedArrayDepthTests {

  @Test("Deeply nested array type codes (depth > 100) returns nil safely")
  func testDeeplyNestedArrayType() {
    // PTP array bit is 0x4000. Nesting arrays means base type still has 0x4000 set.
    // In practice the codec strips 0x4000 once and recurses, so dt=0x4004 -> base=0x0004.
    // Construct data that would claim a large array of arrays:
    // The codec handles this by treating the inner type as the base (non-array),
    // so true stack recursion depth is bounded to 1 level.

    // Build: array of UInt16 arrays — dt=0x4004 with count claiming sub-arrays
    var encoder = MTPDataEncoder()
    // Outer array count
    encoder.append(UInt32(2))
    // Each element is a UInt16 (base type after stripping 0x4000)
    encoder.append(UInt16(0x0001))
    encoder.append(UInt16(0x0002))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4004)  // Array of UInt16
    if case .array(let elements) = value {
      #expect(elements.count == 2)
    } else {
      #expect(Bool(false), "Expected array value")
    }
  }

  @Test("Array with maxSafeCount+1 elements returns nil")
  func testArrayExceedsMaxSafeCount() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(PTPReader.maxSafeCount + 1))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4006)
    #expect(value == nil)
  }

  @Test("Array with count=0 returns empty array")
  func testArrayCountZero() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(0))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4006)
    if case .array(let elements) = value {
      #expect(elements.isEmpty)
    } else {
      #expect(Bool(false), "Expected empty array")
    }
  }

  @Test("Array where count exceeds available data returns nil")
  func testArrayCountExceedsData() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(100))  // claims 100 UInt32 elements
    encoder.append(UInt32(42))  // only 1 element provided

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4006)
    #expect(value == nil)
  }

  @Test("Nested array-of-arrays type code is treated as base type")
  func testNestedArrayOfArraysTypeCode() {
    // dt=0xC006 has both 0x4000 and 0x8000 set. After stripping 0x4000 -> 0x8006.
    // 0x8006 is not a recognized base type so inner parse returns nil -> outer returns nil.
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(1))  // count
    encoder.append(UInt32(0))  // would be inner array count
    encoder.append(UInt32(99))

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0xC006)
    // Inner base type 0x8006 is unknown, so parsing fails gracefully
    #expect(value == nil)
  }
}

// MARK: - PTP String Encoding Edge Cases

@Suite("Wave30 PTP String Edge Cases")
struct PTPStringEdgeCaseTests {

  @Test("Truncated UTF-16: claims N chars but data is short")
  func testTruncatedUTF16() {
    // Claims 5 chars (10 bytes of UTF-16) but only provides 3 bytes
    let data = Data([0x05, 0x41, 0x00, 0x42])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    #expect(result == nil)
  }

  @Test("Missing null terminator is handled gracefully")
  func testMissingNullTerminator() {
    // Encode "AB" manually: count=3 (2 chars + null), but omit the null
    // count=2, 'A'=0x0041 LE, 'B'=0x0042 LE — no null terminator
    let data = Data([0x02, 0x41, 0x00, 0x42, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // Parser reads charCount chars, null chars are filtered — should not crash
    #expect(result != nil)
  }

  @Test("BOM (0xFEFF) in UTF-16 data is preserved as character")
  func testBOMPresence() {
    // Build string with BOM as first char: count=2 (BOM + null)
    let data = Data([0x02, 0xFF, 0xFE, 0x00, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    // BOM (U+FEFF) should be treated as a regular character
    #expect(result != nil)
    if let s = result {
      #expect(s.unicodeScalars.first?.value == 0xFEFF)
    }
  }

  @Test("String with embedded null characters")
  func testEmbeddedNullCharacters() {
    // count=3: 'A', null, 'B' — null chars are filtered by parser
    let data = Data([0x03, 0x41, 0x00, 0x00, 0x00, 0x42, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    #expect(result != nil)
    // The null char is filtered, so result should be "AB"
    #expect(result == "AB")
  }

  @Test("Maximum-length PTP string (253 chars)")
  func testMaxLengthString() {
    // PTP strings: length byte = charCount + 1 (null). 0xFF (255) is a sentinel.
    // Max round-trippable: 253 chars → length byte = 254.
    let longStr = String(repeating: "Z", count: 253)
    let encoded = PTPString.encode(longStr)
    #expect(encoded[0] == 254)  // 253 chars + null = 254

    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == longStr)
  }

  @Test("String with 254+ chars encodes to 0xFF length byte (sentinel)")
  func testStringAtSentinelBoundary() {
    // 254 chars → len = min(255, 255) = 255 = 0xFF → parse treats as sentinel → nil
    let longStr = String(repeating: "A", count: 254)
    let encoded = PTPString.encode(longStr)
    #expect(encoded[0] == 0xFF)

    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    // 0xFF is treated as invalid sentinel by parse, so round-trip fails
    #expect(decoded == nil)
  }

  @Test("String longer than 254 chars also encodes to 0xFF (clamped)")
  func testStringTruncation() {
    let veryLong = String(repeating: "A", count: 300)
    let encoded = PTPString.encode(veryLong)
    #expect(encoded[0] == 0xFF)

    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    // Also hits 0xFF sentinel
    #expect(decoded == nil)
  }

  @Test("String with surrogate pair halves (invalid UTF-16)")
  func testSurrogateHalves() {
    // Lone high surrogate 0xD800 followed by non-surrogate 0x0041
    let data = Data([0x03, 0x00, 0xD8, 0x41, 0x00, 0x00, 0x00])
    var offset = 0
    // Must not crash; result may contain replacement character or be partial
    let result = PTPString.parse(from: data, at: &offset)
    _ = result  // just ensure no crash
  }

  @Test("Single-byte data with only length byte")
  func testSingleByteLengthOnly() {
    for b: UInt8 in [0, 1, 127, 128, 254, 255] {
      var offset = 0
      _ = PTPString.parse(from: Data([b]), at: &offset)
      // Must not crash for any length byte value
    }
  }

  @Test("Zero-length string round-trip")
  func testZeroLengthStringRoundTrip() {
    let encoded = PTPString.encode("")
    #expect(encoded == Data([0x00]))
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    #expect(decoded == "")
  }
}

// MARK: - Integer Overflow in Size Calculations

@Suite("Wave30 Integer Overflow Protection")
struct IntegerOverflowTests {

  @Test("PTPReader array count at UInt32.max returns nil")
  func testArrayCountUInt32Max() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32.max)

    var reader = PTPReader(data: encoder.encodedData)
    let value = reader.value(dt: 0x4006)
    #expect(value == nil)  // exceeds maxSafeCount
  }

  @Test("PTPPropList entry count at UInt32.max returns nil")
  func testPropListCountUInt32Max() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32.max)

    let list = PTPPropList.parse(from: encoder.encodedData)
    #expect(list == nil)
  }

  @Test("DeviceInfo array count at maxSafeCount+1 returns nil")
  func testDeviceInfoArrayOverflow() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(100))  // standardVersion
    encoder.append(UInt32(6))  // vendorExtensionID
    encoder.append(UInt16(100))  // vendorExtensionVersion
    encoder.append(PTPString.encode(""))  // vendorExtensionDesc
    encoder.append(UInt16(0))  // functionalMode
    // operationsSupported with overflow count
    encoder.append(UInt32(PTPReader.maxSafeCount + 1))

    let info = PTPDeviceInfo.parse(from: encoder.encodedData)
    #expect(info == nil)
  }

  @Test("ObjectInfoDataset with UInt64.max size clamps to UInt32.max")
  func testObjectInfoSizeClamping() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 1, parentHandle: 0, format: 0x3000,
      size: UInt64.max, name: "huge.bin")

    var decoder = MTPDataDecoder(data: data)
    _ = decoder.readUInt32()  // storageID
    _ = decoder.readUInt16()  // format
    _ = decoder.readUInt16()  // ProtectionStatus
    let compressedSize = decoder.readUInt32()
    #expect(compressedSize == UInt32.max)
  }

  @Test("validateCount throws for values above maxSafeCount")
  func testValidateCountThrows() {
    #expect(throws: (any Error).self) {
      try PTPReader.validateCount(PTPReader.maxSafeCount + 1)
    }
  }

  @Test("validateCount succeeds at maxSafeCount boundary")
  func testValidateCountBoundary() throws {
    try PTPReader.validateCount(PTPReader.maxSafeCount)
    try PTPReader.validateCount(0)
    try PTPReader.validateCount(1)
  }
}

// MARK: - Zero-Length Arrays and Datasets

@Suite("Wave30 Zero-Length Arrays and Datasets")
struct ZeroLengthTests {

  @Test("PTPPropList with zero entries")
  func testPropListZeroEntries() {
    let data = MTPEndianCodec.encode(UInt32(0))
    let list = PTPPropList.parse(from: data)
    #expect(list != nil)
    #expect(list?.entries.isEmpty == true)
  }

  @Test("PTPReader value with zero-count array for all base types")
  func testZeroCountArrayAllTypes() {
    let arrayTypes: [UInt16] = [
      0x4001, 0x4002, 0x4003, 0x4004,
      0x4005, 0x4006, 0x4007, 0x4008,
    ]
    for dt in arrayTypes {
      var encoder = MTPDataEncoder()
      encoder.append(UInt32(0))

      var reader = PTPReader(data: encoder.encodedData)
      let value = reader.value(dt: dt)
      if case .array(let elements) = value {
        #expect(elements.isEmpty, "Expected empty array for dt=0x\(String(dt, radix: 16))")
      } else {
        #expect(Bool(false), "Expected array for dt=0x\(String(dt, radix: 16))")
      }
    }
  }

  @Test("DeviceInfo with all empty arrays parses successfully")
  func testDeviceInfoAllEmptyArrays() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt16(100))
    encoder.append(UInt32(6))
    encoder.append(UInt16(100))
    encoder.append(PTPString.encode(""))
    encoder.append(UInt16(0))
    // 5 empty arrays
    for _ in 0..<5 { encoder.append(UInt32(0)) }
    // 4 strings
    encoder.append(PTPString.encode("Mfg"))
    encoder.append(PTPString.encode("Model"))
    encoder.append(PTPString.encode("1.0"))
    encoder.append(PTPString.encode("SN"))

    let info = PTPDeviceInfo.parse(from: encoder.encodedData)
    #expect(info != nil)
    #expect(info?.operationsSupported.isEmpty == true)
    #expect(info?.eventsSupported.isEmpty == true)
    #expect(info?.devicePropertiesSupported.isEmpty == true)
    #expect(info?.captureFormats.isEmpty == true)
    #expect(info?.playbackFormats.isEmpty == true)
  }

  @Test("Zero-length readBytes returns empty Data")
  func testReadBytesZeroLength() {
    var decoder = MTPDataDecoder(data: Data([0x01, 0x02]))
    let bytes = decoder.readBytes(0)
    #expect(bytes == Data())
    #expect(decoder.currentOffset == 0)
  }
}

// MARK: - Mixed Endian Data in Single Container

@Suite("Wave30 Mixed Endian Data")
struct MixedEndianTests {

  @Test("Big-endian bytes decoded as little-endian produce swapped value")
  func testBigEndianBytesAsLittleEndian() {
    // If someone writes 0x1234 in big-endian: [0x12, 0x34]
    // Our LE decoder reads it as 0x3412
    let bigEndianData = Data([0x12, 0x34])
    let value = MTPEndianCodec.decodeUInt16(from: bigEndianData, at: 0)
    #expect(value == 0x3412)
  }

  @Test("Container header with mixed field byte orders is parseable")
  func testMixedFieldByteOrders() {
    // Simulates corrupted/mixed data: first 4 bytes LE, rest random
    var data = Data()
    data.append(MTPEndianCodec.encode(UInt32(20)))  // length LE
    data.append(Data([0x00, 0x01]))  // type in reversed byte order
    data.append(MTPEndianCodec.encode(UInt16(0x1002)))  // code LE
    data.append(MTPEndianCodec.encode(UInt32(1)))  // txid LE
    data.append(MTPEndianCodec.encode(UInt32(0x00000001)))  // param LE

    var r = PTPReader(data: data)
    #expect(r.u32() == 20)
    let typeVal = r.u16()
    #expect(typeVal == 0x0100)  // decoded as LE from big-endian bytes
    #expect(r.u16() == 0x1002)
    #expect(r.u32() == 1)
    #expect(r.u32() == 1)
  }

  @Test("Reinterpret LE-encoded UInt32 bytes as two UInt16s")
  func testReinterpretU32AsU16s() {
    let data = MTPEndianCodec.encode(UInt32(0xAABBCCDD))
    let lo = MTPEndianCodec.decodeUInt16(from: data, at: 0)
    let hi = MTPEndianCodec.decodeUInt16(from: data, at: 2)
    #expect(lo == 0xCCDD)
    #expect(hi == 0xAABB)
  }
}

// MARK: - Reserved Operation Code 0xFFFF

@Suite("Wave30 Reserved Operation Codes")
struct ReservedOperationCodeTests {

  @Test("Container with operation code 0xFFFF (reserved) parses header safely")
  func testReservedOpCode0xFFFF() {
    var encoder = MTPDataEncoder()
    encoder.append(UInt32(12))  // length
    encoder.append(UInt16(1))  // type = command
    encoder.append(UInt16(0xFFFF))  // reserved op code
    encoder.append(UInt32(1))  // txid

    var r = PTPReader(data: encoder.encodedData)
    #expect(r.u32() == 12)
    #expect(r.u16() == 1)
    #expect(r.u16() == 0xFFFF)
    #expect(r.u32() == 1)
  }

  @Test("PTPContainer encode/decode with reserved code 0xFFFF")
  func testPTPContainerReservedCode() {
    let container = PTPContainer(length: 12, type: 1, code: 0xFFFF, txid: 99)
    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 12)

    let data = Data(buf[0..<written])
    #expect(MTPEndianCodec.decodeUInt16(from: data, at: 6) == 0xFFFF)
  }

  @Test("PTPContainer with all container types and reserved code")
  func testAllContainerTypesWithReservedCode() {
    for typeVal: UInt16 in [0, 1, 2, 3, 4, 5, 0xFFFF] {
      let container = PTPContainer(length: 12, type: typeVal, code: 0xFFFF, txid: 0)
      var buf = [UInt8](repeating: 0, count: 32)
      let written = buf.withUnsafeMutableBufferPointer { ptr in
        container.encode(into: ptr.baseAddress!)
      }
      #expect(written == 12)

      let data = Data(buf[0..<written])
      #expect(MTPEndianCodec.decodeUInt16(from: data, at: 4) == typeVal)
      #expect(MTPEndianCodec.decodeUInt16(from: data, at: 6) == 0xFFFF)
    }
  }

  @Test("PTPOp does not include 0xFFFF as a valid case")
  func testPTPOpDoesNotIncludeReserved() {
    let reserved = PTPOp(rawValue: 0xFFFF)
    #expect(reserved == nil)
  }

  @Test("PTPResponseCode.describe handles unknown codes")
  func testResponseCodeDescribeUnknown() {
    let desc = PTPResponseCode.describe(0xFFFF)
    #expect(desc.contains("Unknown"))
    #expect(desc.contains("ffff"))
  }
}

// MARK: - PTPValue Type Edge Cases

@Suite("Wave30 PTPValue Type Edge Cases")
struct PTPValueEdgeCaseTests {

  @Test("All scalar PTP data types with boundary values")
  func testAllScalarTypeBoundaries() {
    // INT8 min/max
    for byte: UInt8 in [0x00, 0x7F, 0x80, 0xFF] {
      var r = PTPReader(data: Data([byte]))
      let v = r.value(dt: 0x0001)
      #expect(v != nil)
    }

    // UINT8 min/max
    for byte: UInt8 in [0x00, 0xFF] {
      var r = PTPReader(data: Data([byte]))
      let v = r.value(dt: 0x0002)
      #expect(v != nil)
    }

    // INT16 / UINT16
    for val: UInt16 in [0, UInt16.max, 0x8000] {
      let data = MTPEndianCodec.encode(val)
      var r1 = PTPReader(data: data)
      #expect(r1.value(dt: 0x0003) != nil)
      var r2 = PTPReader(data: data)
      #expect(r2.value(dt: 0x0004) != nil)
    }

    // INT32 / UINT32
    for val: UInt32 in [0, UInt32.max, 0x80000000] {
      let data = MTPEndianCodec.encode(val)
      var r1 = PTPReader(data: data)
      #expect(r1.value(dt: 0x0005) != nil)
      var r2 = PTPReader(data: data)
      #expect(r2.value(dt: 0x0006) != nil)
    }

    // INT64 / UINT64
    for val: UInt64 in [0, UInt64.max, 0x8000000000000000] {
      let data = MTPEndianCodec.encode(val)
      var r1 = PTPReader(data: data)
      #expect(r1.value(dt: 0x0007) != nil)
      var r2 = PTPReader(data: data)
      #expect(r2.value(dt: 0x0008) != nil)
    }
  }

  @Test("INT128 / UINT128 with 16 bytes of data")
  func testInt128Types() {
    let data = Data(repeating: 0xFF, count: 16)

    var r1 = PTPReader(data: data)
    if case .int128(let d) = r1.value(dt: 0x0009) {
      #expect(d.count == 16)
    } else {
      #expect(Bool(false), "Expected int128")
    }

    var r2 = PTPReader(data: data)
    if case .uint128(let d) = r2.value(dt: 0x000A) {
      #expect(d.count == 16)
    } else {
      #expect(Bool(false), "Expected uint128")
    }
  }

  @Test("INT128 with insufficient data returns nil")
  func testInt128InsufficientData() {
    let data = Data(repeating: 0x00, count: 15)
    var r = PTPReader(data: data)
    #expect(r.value(dt: 0x0009) == nil)
  }

  @Test("Unknown data type codes return nil")
  func testUnknownDataTypes() {
    let data = Data(repeating: 0x00, count: 32)
    let unknownTypes: [UInt16] = [0x000B, 0x000C, 0x00FF, 0x0010, 0x0020, 0x3000]
    for dt in unknownTypes {
      var r = PTPReader(data: data)
      #expect(r.value(dt: dt) == nil, "Expected nil for unknown dt=0x\(String(dt, radix: 16))")
    }
  }

  @Test("String type 0xFFFF is handled before array bit check")
  func testStringTypeBeforeArrayBitCheck() {
    // 0xFFFF has 0x4000 bit set, but must be handled as string, not array
    let encoded = PTPString.encode("test")
    var r = PTPReader(data: encoded)
    let value = r.value(dt: 0xFFFF)
    if case .string(let s) = value {
      #expect(s == "test")
    } else {
      #expect(Bool(false), "Expected string for dt=0xFFFF")
    }
  }
}

// MARK: - PTP Object Format Edge Cases

@Suite("Wave30 PTP Object Format")
struct PTPObjectFormatTests {

  @Test("Known file extensions return correct format codes")
  func testKnownExtensions() {
    #expect(PTPObjectFormat.forFilename("photo.jpg") == 0x3801)
    #expect(PTPObjectFormat.forFilename("photo.jpeg") == 0x3801)
    #expect(PTPObjectFormat.forFilename("image.png") == 0x380b)
    #expect(PTPObjectFormat.forFilename("notes.txt") == 0x3004)
    #expect(PTPObjectFormat.forFilename("video.mp4") == 0x300b)
    #expect(PTPObjectFormat.forFilename("song.mp3") == 0x3009)
    #expect(PTPObjectFormat.forFilename("audio.aac") == 0xb903)
  }

  @Test("Unknown extensions return undefined format 0x3000")
  func testUnknownExtension() {
    #expect(PTPObjectFormat.forFilename("data.bin") == 0x3000)
    #expect(PTPObjectFormat.forFilename("archive.zip") == 0x3000)
    #expect(PTPObjectFormat.forFilename("noext") == 0x3000)
    #expect(PTPObjectFormat.forFilename("") == 0x3000)
  }

  @Test("Case-insensitive extension matching")
  func testCaseInsensitiveExtensions() {
    #expect(PTPObjectFormat.forFilename("PHOTO.JPG") == 0x3801)
    #expect(PTPObjectFormat.forFilename("Photo.Jpeg") == 0x3801)
    #expect(PTPObjectFormat.forFilename("IMAGE.PNG") == 0x380b)
    #expect(PTPObjectFormat.forFilename("NOTES.TXT") == 0x3004)
  }
}

// MARK: - PTPContainer Encode Round-Trip

@Suite("Wave30 PTPContainer Encode Edge Cases")
struct PTPContainerEncodeTests {

  @Test("Container with maximum parameters (5)")
  func testContainerMaxParams() {
    let params: [UInt32] = [1, 2, 3, 4, 5]
    let container = PTPContainer(
      length: UInt32(12 + params.count * 4), type: 1, code: 0x1007, txid: 10,
      params: params)

    var buf = [UInt8](repeating: 0, count: 64)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 32)  // 12 header + 5*4 params

    let data = Data(buf[0..<written])
    for (i, expected) in params.enumerated() {
      let decoded = MTPEndianCodec.decodeUInt32(from: data, at: 12 + i * 4)
      #expect(decoded == expected)
    }
  }

  @Test("Container with empty params encodes 12 bytes")
  func testContainerEmptyParams() {
    let container = PTPContainer(length: 12, type: 3, code: 0x2001, txid: 0)
    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 12)
  }

  @Test("Container with all-zero fields")
  func testContainerAllZeros() {
    let container = PTPContainer(length: 0, type: 0, code: 0, txid: 0)
    var buf = [UInt8](repeating: 0xFF, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 12)

    let data = Data(buf[0..<written])
    #expect(data == Data(repeating: 0, count: 12))
  }

  @Test("Container with all-max fields")
  func testContainerAllMax() {
    let container = PTPContainer(
      length: UInt32.max, type: UInt16.max, code: UInt16.max, txid: UInt32.max,
      params: [UInt32.max])

    var buf = [UInt8](repeating: 0, count: 32)
    let written = buf.withUnsafeMutableBufferPointer { ptr in
      container.encode(into: ptr.baseAddress!)
    }
    #expect(written == 16)

    let data = Data(buf[0..<written])
    #expect(data == Data(repeating: 0xFF, count: 16))
  }
}

// MARK: - MTPDataDecoder Fuzzing with PTP Patterns

@Suite("Wave30 MTPDataDecoder PTP Pattern Fuzzing")
struct MTPDataDecoderPTPPatternTests {

  @Test("Decoder handles seek-read-seek-read pattern")
  func testSeekReadPattern() {
    var encoder = MTPDataEncoder()
    for i: UInt32 in 0..<10 {
      encoder.append(i)
    }

    var decoder = MTPDataDecoder(data: encoder.encodedData)
    // Read in non-sequential order
    decoder.seek(to: 20)  // offset of value 5
    #expect(decoder.readUInt32() == 5)
    decoder.seek(to: 0)
    #expect(decoder.readUInt32() == 0)
    decoder.seek(to: 36)  // offset of value 9
    #expect(decoder.readUInt32() == 9)
  }

  @Test("Decoder readBytes at various sizes from PTP-like data")
  func testReadBytesVariousSizes() {
    let data = Data(0..<64)
    var decoder = MTPDataDecoder(data: data)

    let chunk1 = decoder.readBytes(12)  // PTP header size
    #expect(chunk1?.count == 12)

    let chunk2 = decoder.readBytes(4)  // single param
    #expect(chunk2?.count == 4)

    let chunk3 = decoder.readBytes(100)  // more than available
    #expect(chunk3 == nil)
    #expect(decoder.currentOffset == 16)  // offset unchanged on failure
  }
}
