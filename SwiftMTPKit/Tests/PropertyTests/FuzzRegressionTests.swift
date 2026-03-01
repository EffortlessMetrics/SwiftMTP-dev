// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Regression tests that replay known-tricky inputs from fuzz corpus.
///
/// When a fuzzer finds a crash or unexpected behaviour, add the minimised
/// input here so it is exercised on every CI run. Each test feeds the raw
/// bytes through the same code paths exercised by the SwiftMTPFuzz harness.
final class FuzzRegressionTests: XCTestCase {

  // MARK: - Helpers

  /// Build a minimal MTP container header (little-endian).
  private static func mtpHeader(
    length: UInt32, type: UInt16, opcode: UInt16, txid: UInt32
  ) -> Data {
    var d = Data()
    d.append(contentsOf: withUnsafeBytes(of: length.littleEndian, Array.init))
    d.append(contentsOf: withUnsafeBytes(of: type.littleEndian, Array.init))
    d.append(contentsOf: withUnsafeBytes(of: opcode.littleEndian, Array.init))
    d.append(contentsOf: withUnsafeBytes(of: txid.littleEndian, Array.init))
    return d
  }

  // MARK: - PTPReader edge cases

  func testReaderEmptyData() {
    var r = PTPReader(data: Data())
    XCTAssertNil(r.u8())
    XCTAssertNil(r.u16())
    XCTAssertNil(r.u32())
    XCTAssertNil(r.u64())
    XCTAssertNil(r.string())
  }

  func testReaderAllFF() {
    let data = Data(repeating: 0xFF, count: 12)
    var r = PTPReader(data: data)
    XCTAssertEqual(r.u8(), 0xFF)
    XCTAssertNotNil(r.u16())
    XCTAssertNotNil(r.u32())
  }

  func testReaderAllZeros() {
    let data = Data(repeating: 0x00, count: 12)
    var r = PTPReader(data: data)
    XCTAssertEqual(r.u8(), 0)
    XCTAssertEqual(r.u16(), 0)
    XCTAssertEqual(r.u32(), 0)
  }

  // MARK: - PTPString edge cases

  func testStringMaxLenByte() {
    // Length byte 0xFF with no payload — must not crash.
    var offset = 0
    XCTAssertNil(PTPString.parse(from: Data([0xFF]), at: &offset))
  }

  func testStringTruncatedUTF16() {
    // Claims 2 chars but only has 1 byte of UTF-16 data.
    var offset = 0
    _ = PTPString.parse(from: Data([0x02, 0x41]), at: &offset)
    // Must not crash; result may be nil.
  }

  // MARK: - PTPDeviceInfo edge cases

  func testDeviceInfoEmptyData() {
    XCTAssertNil(PTPDeviceInfo.parse(from: Data()))
  }

  func testDeviceInfoAllFF() {
    _ = PTPDeviceInfo.parse(from: Data(repeating: 0xFF, count: 12))
    // Must not crash.
  }

  func testDeviceInfoHugeLengthField() {
    let data = Self.mtpHeader(length: 0x7FFF_FFFF, type: 2, opcode: 0x1001, txid: 1)
    _ = PTPDeviceInfo.parse(from: data)
  }

  // MARK: - PTPPropList edge cases

  func testPropListEmptyData() {
    let result = PTPPropList.parse(from: Data())
    // Should return nil or empty; must not crash.
    if let r = result { XCTAssertTrue(r.entries.isEmpty) }
  }

  func testPropListZeroEntries() {
    var d = Data()
    d.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian, Array.init))
    let result = PTPPropList.parse(from: d)
    if let r = result { XCTAssertTrue(r.entries.isEmpty) }
  }

  func testPropListTruncatedEntry() {
    // Claims 1 entry but payload is incomplete.
    var d = Data()
    d.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian, Array.init))
    d.append(contentsOf: [0x01, 0x00]) // partial objectHandle
    _ = PTPPropList.parse(from: d)
    // Must not crash.
  }

  // MARK: - PathSanitizer edge cases

  func testPathSanitizerTraversal() {
    // PathSanitizer strips path separators; pure ".." is rejected as nil.
    XCTAssertNil(PathSanitizer.sanitize(".."))
    // With path separators, they are stripped but the remaining chars are kept.
    let sanitized = PathSanitizer.sanitize("../../../etc/passwd")
    // Slashes must be removed so result cannot escape directory.
    XCTAssertFalse(sanitized?.contains("/") ?? false)
  }

  func testPathSanitizerEmbeddedNull() {
    _ = PathSanitizer.sanitize("/\0embedded/null")
    // Must not crash.
  }

  func testPathSanitizerEmpty() {
    _ = PathSanitizer.sanitize("")
  }

  func testPathSanitizerMultipleSlashes() {
    let sanitized = PathSanitizer.sanitize("////multiple////slashes////")
    XCTAssertFalse(sanitized?.contains("//") ?? false)
  }

  // MARK: - Container header edge cases

  func testContainerInvalidType() {
    let data = Self.mtpHeader(length: 12, type: 0, opcode: 0x1001, txid: 1)
    var r = PTPReader(data: data)
    _ = r.u32() // length
    _ = r.u16() // type
    _ = r.u16() // opcode
    _ = r.u32() // txid
    // Parsing must not crash even with invalid type.
  }

  func testContainerLengthZero() {
    let data = Self.mtpHeader(length: 0, type: 1, opcode: 0x1001, txid: 1)
    var r = PTPReader(data: data)
    _ = r.u32()
    _ = r.u16()
    // Must not crash.
  }

  // MARK: - Corpus replay

  /// Replays every file in the fuzz corpus through all harness code paths.
  func testReplayCorpus() throws {
    let corpusURL = self.corpusDirectoryURL()
    guard let corpusURL else {
      // Corpus not bundled in test target — skip gracefully.
      return
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: corpusURL, includingPropertiesForKeys: nil)

    for file in files where file.pathExtension == "bin" {
      let data = try Data(contentsOf: file)

      // PTPReader
      var r = PTPReader(data: data)
      _ = r.u8(); _ = r.u16(); _ = r.u32(); _ = r.u64(); _ = r.string()

      // PTPString
      var offset = 0
      _ = PTPString.parse(from: data, at: &offset)

      // PTPDeviceInfo
      _ = PTPDeviceInfo.parse(from: data)

      // PTPPropList
      _ = PTPPropList.parse(from: data)

      // PathSanitizer (treat bytes as UTF-8 string)
      if let str = String(data: data, encoding: .utf8) {
        _ = PathSanitizer.sanitize(str)
      }
    }
  }

  // MARK: - Private

  /// Locate the corpus directory relative to the source tree.
  private func corpusDirectoryURL() -> URL? {
    // Walk up from the test file location to find the corpus.
    var url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // PropertyTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // SwiftMTPKit/
    url.appendPathComponent("Sources/Tools/SwiftMTPFuzz/corpus")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url
  }
}
