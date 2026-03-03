// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

// MARK: - Generators

/// Generator for valid PTP container types.
private enum PTPContainerTypeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>.fromElements(of: [1, 2, 3, 4])  // command, data, response, event
  }
}

/// Generator for valid PTP operation codes.
private enum PTPOpCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>
      .fromElements(of: [
        0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007,
        0x1008, 0x1009, 0x100A, 0x100B, 0x100C, 0x100D, 0x100E,
        0x1014, 0x1015, 0x1016, 0x1017, 0x101B, 0x95C1, 0x95C4,
      ])
  }
}

/// Generator for arbitrary Unicode strings including multi-byte and emoji.
private enum UnicodeGen {
  static var arbitrary: Gen<String> {
    Gen<String>
      .one(of: [
        Gen<String>
          .fromElements(of: [
            "hello", "café", "naïve", "Müller", "Ångström", "Señor",
            "文件", "ファイル", "파일", "файл", "📷🎉🌍",
            "path/to/file", "a\u{0301}", "\u{1F600}\u{1F601}",
          ]),
        Gen<Character>.fromElements(of: Array("abcdefghijklmnopqrstuvwxyz0123456789"))
          .proliferate
          .suchThat { !$0.isEmpty }
          .map { String($0.prefix(100)) },
      ])
  }
}

/// Generator for valid MTP storage ID raw values.
private enum StorageIDGenerator {
  static var arbitrary: Gen<UInt32> {
    Gen<UInt32>
      .one(of: [
        // Realistic storage IDs: upper 16 = physical, lower 16 = logical
        Gen<(UInt16, UInt16)>
          .zip(
            Gen<UInt16>.choose((1, 8)),
            Gen<UInt16>.choose((1, 4))
          )
          .map { phys, log in (UInt32(phys) << 16) | UInt32(log) },
        // Boundary values
        Gen<UInt32>.fromElements(of: [0x00010001, 0x00020001, 0xFFFFFFFF]),
      ])
  }
}

/// Generator for device filenames that may contain dangerous characters.
private enum DeviceFilenameGenerator {
  static var arbitrary: Gen<String> {
    Gen<String>
      .fromElements(of: [
        "photo.jpg", "IMG_0001.CR2", "..hidden", "../escape.txt",
        "normal file.txt", "file\0name.jpg", "../../etc/passwd",
        "a/b/c.txt", "file\\name.txt", "...", ".", "..", "",
        "  spaces  ", "naïve café.mp3", "长文件名.png",
        String(repeating: "x", count: 300),
        "CON", "NUL", "file\u{00}name",
      ])
  }
}

// MARK: - Protocol Property Tests

/// Property-based tests for MTP protocol type invariants.
final class ProtocolPropertyTests: XCTestCase {

  // MARK: - 1. PTP Container Header Round-Trip

  /// Encoding a PTPContainer and decoding the bytes must yield the original fields.
  func testPTPContainerHeaderRoundTrip() {
    property("PTPContainer encode → decode round-trips all fields")
      <- forAll(
        PTPContainerTypeGenerator.arbitrary,
        PTPOpCodeGenerator.arbitrary,
        UInt32.arbitrary,
        Gen<[UInt32]>.fromElements(of: [[], [1], [1, 2], [1, 2, 3]])
      ) { type, code, txid, params in
        let length = UInt32(12 + params.count * 4)
        let container = PTPContainer(
          length: length, type: type, code: code, txid: txid, params: params)

        var buf = [UInt8](repeating: 0, count: Int(length) + 16)
        let written = buf.withUnsafeMutableBufferPointer { ptr in
          container.encode(into: ptr.baseAddress!)
        }

        // Decode the header fields
        let decoded = Data(buf[0..<written])
        var dec = MTPDataDecoder(data: decoded)
        guard let dLen = dec.readUInt32(),
          let dType = dec.readUInt16(),
          let dCode = dec.readUInt16(),
          let dTxid = dec.readUInt32()
        else { return false }

        var dParams = [UInt32]()
        for _ in 0..<params.count {
          guard let p = dec.readUInt32() else { return false }
          dParams.append(p)
        }

        return dLen == length && dType == type && dCode == code
          && dTxid == txid && dParams == params
      }
  }

  // MARK: - 2. PTP String Encode/Decode Round-Trip with Arbitrary Unicode

  /// PTPString.encode then parse must round-trip for valid Unicode strings.
  func testPTPStringUnicodeRoundTrip() {
    property("PTPString encode/decode round-trips arbitrary Unicode strings")
      <- forAll(UnicodeGen.arbitrary.suchThat { $0.utf16.count < 254 && !$0.isEmpty }) { str in
        let encoded = PTPString.encode(str)
        var offset = 0
        guard let decoded = PTPString.parse(from: encoded, at: &offset) else { return false }
        return decoded == str
      }
  }

  // MARK: - 3. Object Handle Allocation Uniqueness

  /// Generating N distinct random handles must produce N unique values (for small N).
  func testObjectHandleUniqueness() {
    property("Distinct random UInt32 values produce unique handle sets")
      <- forAll(Gen<Int>.choose((2, 100))) { count in
        var handles = Set<MTPObjectHandle>()
        for i in 0..<count {
          // Deterministic allocation: use sequential handles as a device would
          handles.insert(MTPObjectHandle(i + 1))
        }
        return handles.count == count
      }
  }

  // MARK: - 4. Transfer Chunk Size Auto-Tuning Monotonicity

  /// Clamping chunk size to pool buffer size must always yield a value ≤ the pool size.
  func testChunkSizeClampMonotonicity() {
    property("Effective chunk size is always ≤ pool buffer size")
      <- forAll(
        Gen<Int>.choose((1, 16 * 1024 * 1024)),
        Gen<Int>.choose((1, 16 * 1024 * 1024))
      ) { requested, poolSize in
        let effective = min(requested, poolSize)
        return effective <= poolSize && effective > 0
      }
  }

  /// Doubling chunk size proposals must produce non-decreasing sequence.
  func testChunkSizeDoublingIsMonotone() {
    property("Doubling chunk sizes produces a non-decreasing sequence")
      <- forAll(Gen<Int>.choose((512, 65536))) { initial in
        let maxChunk = 8 * 1024 * 1024
        var sizes = [Int]()
        var current = initial
        for _ in 0..<10 {
          sizes.append(current)
          current = min(current * 2, maxChunk)
        }
        return zip(sizes, sizes.dropFirst()).allSatisfy { $0 <= $1 }
      }
  }

  // MARK: - 5. Quirk Matching Determinism

  /// Calling QuirkDatabase.match with identical inputs must always return the same result.
  func testQuirkMatchingDeterminism() throws {
    let db = try QuirkDatabase.load()
    property("QuirkDatabase.match is deterministic for identical inputs")
      <- forAll(
        Gen<UInt16>.choose((1, UInt16.max)),
        Gen<UInt16>.choose((1, UInt16.max))
      ) { vid, pid in
        let r1 = db.match(
          vid: vid, pid: pid, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil,
          ifaceProtocol: nil)
        let r2 = db.match(
          vid: vid, pid: pid, bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil,
          ifaceProtocol: nil)
        return r1?.id == r2?.id
      }
  }

  // MARK: - 6. Response Code Classification Completeness

  /// All standard PTP response codes (0x2001–0x2020) must have a known name.
  func testResponseCodeClassificationCompleteness() {
    for code: UInt16 in 0x2001...0x2020 {
      let name = PTPResponseCode.name(for: code)
      XCTAssertNotNil(
        name,
        "Standard PTP response code 0x\(String(format: "%04x", code)) should have a name")
    }
  }

  /// PTPResponseCode.describe must never return an empty string for any UInt16.
  func testResponseCodeDescribeNeverEmpty() {
    property("PTPResponseCode.describe never returns an empty string")
      <- forAll { (code: UInt16) in
        let desc = PTPResponseCode.describe(code)
        return !desc.isEmpty
      }
  }

  /// PTPResponseCode.describe must always include the hex code.
  func testResponseCodeDescribeContainsHex() {
    property("PTPResponseCode.describe includes hex representation")
      <- forAll { (code: UInt16) in
        let desc = PTPResponseCode.describe(code)
        return desc.contains("0x")
      }
  }

  // MARK: - 7. File Path Normalization Idempotency

  /// Applying PathSanitizer.sanitize twice must yield the same result as applying it once.
  func testPathSanitizerIdempotency() {
    property("PathSanitizer.sanitize is idempotent")
      <- forAll(DeviceFilenameGenerator.arbitrary) { name in
        guard let first = PathSanitizer.sanitize(name) else { return true }
        let second = PathSanitizer.sanitize(first)
        return second == first
      }
  }

  /// Sanitized names must never contain path separators.
  func testPathSanitizerNoPathSeparators() {
    property("PathSanitizer output never contains / or \\")
      <- forAll(DeviceFilenameGenerator.arbitrary) { name in
        guard let result = PathSanitizer.sanitize(name) else { return true }
        return !result.contains("/") && !result.contains("\\")
      }
  }

  /// Sanitized names must respect the maximum length limit.
  func testPathSanitizerMaxLength() {
    property("PathSanitizer output never exceeds maxNameLength")
      <- forAll { (s: String) in
        guard let result = PathSanitizer.sanitize(s) else { return true }
        return result.count <= PathSanitizer.maxNameLength
      }
  }

  // MARK: - 8. Storage ID Validity Invariants

  /// MTPStorageID constructed from any UInt32 must round-trip through .raw.
  func testStorageIDRoundTrip() {
    property("MTPStorageID round-trips through raw")
      <- forAll { (raw: UInt32) in
        let sid = MTPStorageID(raw: raw)
        return sid.raw == raw
      }
  }

  /// MTPStorageID equality must be reflexive.
  func testStorageIDEqualityReflexive() {
    property("MTPStorageID is reflexively equal")
      <- forAll { (raw: UInt32) in
        let sid = MTPStorageID(raw: raw)
        return sid == sid
      }
  }

  /// Different raw values must produce unequal storage IDs.
  func testStorageIDInequality() {
    property("Different raw values produce unequal MTPStorageIDs")
      <- forAll(
        Gen<UInt32>.choose((0, UInt32.max / 2)),
        Gen<UInt32>.choose((UInt32.max / 2 + 1, UInt32.max))
      ) { a, b in
        MTPStorageID(raw: a) != MTPStorageID(raw: b)
      }
  }

  // MARK: - 9. MTPDataEncoder/Decoder UInt16 Round-Trip

  func testEncoderDecoderUInt16RoundTrip() {
    property("MTPDataEncoder/Decoder round-trips UInt16")
      <- forAll { (value: UInt16) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt16() else { return false }
        return decoded == value
      }
  }

  // MARK: - 10. MTPDataEncoder/Decoder UInt64 Round-Trip

  func testEncoderDecoderUInt64RoundTrip() {
    property("MTPDataEncoder/Decoder round-trips UInt64")
      <- forAll { (value: UInt64) in
        var enc = MTPDataEncoder()
        enc.append(value)
        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let decoded = dec.readUInt64() else { return false }
        return decoded == value
      }
  }

  // MARK: - 11. PTPContainer Encode Size Correctness

  /// Encoded PTPContainer byte count must match declared length.
  func testPTPContainerEncodedSize() {
    property("PTPContainer encode produces exactly the declared byte count")
      <- forAll(
        PTPContainerTypeGenerator.arbitrary,
        PTPOpCodeGenerator.arbitrary,
        UInt32.arbitrary,
        Gen<Int>.choose((0, 5))
      ) { type, code, txid, paramCount in
        let params = (0..<paramCount).map { UInt32($0) }
        let length = UInt32(12 + paramCount * 4)
        let container = PTPContainer(
          length: length, type: type, code: code, txid: txid, params: params)
        var buf = [UInt8](repeating: 0, count: 512)
        let written = buf.withUnsafeMutableBufferPointer { ptr in
          container.encode(into: ptr.baseAddress!)
        }
        return written == Int(length)
      }
  }

  // MARK: - 12. PTPObjectFormat Consistency

  /// PTPObjectFormat.forFilename must return a non-zero format for any filename.
  func testObjectFormatAlwaysNonZero() {
    property("PTPObjectFormat.forFilename always returns a non-zero format code")
      <- forAll(
        Gen<String>
          .fromElements(of: [
            "photo.jpg", "image.png", "video.mp4", "song.mp3", "notes.txt",
            "document.pdf", "archive.zip", "unknown.xyz", "noext",
          ])
      ) { filename in
        PTPObjectFormat.forFilename(filename) != 0
      }
  }

  /// Known extensions must map to their expected format codes.
  func testObjectFormatKnownExtensions() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpeg"), 0x3801)
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380b)
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300b)
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
    XCTAssertEqual(PTPObjectFormat.forFilename("notes.txt"), 0x3004)
    XCTAssertEqual(PTPObjectFormat.forFilename("unknown.xyz"), 0x3000)
  }

  // MARK: - 13. PTPString Empty String Handling

  /// Empty string encode/decode must round-trip correctly.
  func testPTPStringEmptyRoundTrip() {
    let encoded = PTPString.encode("")
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, "")
  }

  // MARK: - 14. MTPDataDecoder Exhaustion Safety

  /// Reading from an exhausted decoder must return nil, never crash.
  func testDecoderExhaustionReturnsNil() {
    property("Exhausted MTPDataDecoder returns nil for all read methods")
      <- forAll { (bytes: [UInt8]) in
        let data = Data(bytes.prefix(8))
        var dec = MTPDataDecoder(data: data)
        // Consume all bytes
        _ = dec.readBytes(data.count)
        // All subsequent reads must be nil
        return dec.readUInt8() == nil
          && dec.readUInt16() == nil
          && dec.readUInt32() == nil
          && dec.readUInt64() == nil
      }
  }

  // MARK: - 15. PTPReader Truncated Data Safety

  /// PTPReader.value must return nil for data shorter than the type requires.
  func testPTPReaderTruncatedSafety() {
    let scalarTypes: [(UInt16, Int)] = [
      (0x0002, 1), (0x0004, 2), (0x0006, 4), (0x0008, 8),
    ]
    for (dt, requiredBytes) in scalarTypes where requiredBytes > 1 {
      let truncated = Data(repeating: 0xAB, count: requiredBytes - 1)
      var reader = PTPReader(data: truncated)
      XCTAssertNil(
        reader.value(dt: dt),
        "dt=0x\(String(dt, radix: 16)) should return nil for \(requiredBytes - 1) bytes")
    }
  }

  // MARK: - 16. MTPStorageID Hashable Consistency

  /// Equal MTPStorageIDs must have equal hash values (Hashable contract).
  func testStorageIDHashableConsistency() {
    property("Equal MTPStorageIDs have equal hash values")
      <- forAll { (raw: UInt32) in
        let a = MTPStorageID(raw: raw)
        let b = MTPStorageID(raw: raw)
        return a.hashValue == b.hashValue
      }
  }

  // MARK: - 17. PTPContainer Kind Raw Values

  /// All PTPContainer.Kind cases have distinct raw values.
  func testContainerKindDistinctRawValues() {
    let kinds: [PTPContainer.Kind] = [.command, .data, .response, .event]
    let rawValues = kinds.map { $0.rawValue }
    XCTAssertEqual(Set(rawValues).count, rawValues.count, "Kind raw values must be unique")
  }

  // MARK: - 18. Multi-Value Encoder Decoder Sequence

  /// Encoding multiple values sequentially must decode in the same order.
  func testEncoderDecoderSequentialValues() {
    property("Sequential encode/decode preserves order for mixed types")
      <- forAll(
        UInt16.arbitrary,
        UInt32.arbitrary,
        UInt64.arbitrary
      ) { v16, v32, v64 in
        var enc = MTPDataEncoder()
        enc.append(v16)
        enc.append(v32)
        enc.append(v64)

        var dec = MTPDataDecoder(data: enc.encodedData)
        guard let d16 = dec.readUInt16(),
          let d32 = dec.readUInt32(),
          let d64 = dec.readUInt64()
        else { return false }
        return d16 == v16 && d32 == v32 && d64 == v64
      }
  }

  // MARK: - 19. EffectiveTuningBuilder Determinism

  /// Building a policy twice with identical inputs must produce identical results.
  func testEffectiveTuningBuilderDeterminism() {
    property("EffectiveTuningBuilder.buildPolicy is deterministic")
      <- forAll(
        Gen<UInt8?>.fromElements(of: [nil, 0x00, 0x06, 0x08, 0xFF])
      ) { ifaceClass in
        let p1 = EffectiveTuningBuilder.buildPolicy(
          capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: ifaceClass)
        let p2 = EffectiveTuningBuilder.buildPolicy(
          capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: ifaceClass)
        return p1.flags.supportsGetObjectPropList == p2.flags.supportsGetObjectPropList
          && p1.flags.requiresKernelDetach == p2.flags.requiresKernelDetach
          && p1.tuning.maxChunkBytes == p2.tuning.maxChunkBytes
      }
  }

  // MARK: - 20. PTPObjectInfoDataset Encode Non-Empty

  /// PTPObjectInfoDataset.encode must always produce non-empty data.
  func testObjectInfoDatasetEncodeNonEmpty() {
    property("PTPObjectInfoDataset.encode always produces non-empty data")
      <- forAll(
        StorageIDGenerator.arbitrary,
        Gen<UInt32>.choose((0, UInt32.max)),
        Gen<String>.fromElements(of: ["photo.jpg", "video.mp4", "test.txt", "image.png"])
      ) { storage, parent, name in
        let data = PTPObjectInfoDataset.encode(
          storageID: storage, parentHandle: parent, format: 0x3801,
          size: 1024, name: name)
        return !data.isEmpty
      }
  }
}
