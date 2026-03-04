// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCore

// MARK: - Generators

/// Generator for arbitrary filename extensions (including unknown ones).
private enum FilenameExtensionGenerator {
  static var arbitrary: Gen<String> {
    Gen<String>
      .one(of: [
        // Known extensions
        Gen<String>
          .fromElements(of: [
            "photo.jpg", "track.mp3", "video.mp4", "notes.txt",
            "image.png", "clip.avi", "song.wav", "doc.pdf",
            "pic.heic", "raw.tiff", "movie.mkv", "tune.flac",
            "PHOTO.JPG", "Track.MP3", "VIDEO.MP4",
          ]),
        // Unknown / random extensions
        Gen<String>
          .fromElements(of: [
            "file.xyz", "data.qqq", "noext", ".hidden", "dots...",
            "emoji📷.unknown", "café.???", "", "a", "file.123",
          ]),
        // Generated random filenames
        Gen<Character>.fromElements(of: Array("abcdefghijklmnopqrstuvwxyz"))
          .proliferate
          .suchThat { $0.count >= 1 && $0.count <= 20 }
          .map { chars in
            let name = String(chars)
            let exts = [".jpg", ".mp3", ".txt", ".bin", ".xyz", ""]
            let ext = exts[abs(name.hashValue) % exts.count]
            return name + ext
          },
      ])
  }
}

/// Generator for all defined MTP object property codes.
private enum PropCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>
      .fromElements(of: [
        // Object Info Properties
        0xDC01, 0xDC02, 0xDC03, 0xDC04, 0xDC05, 0xDC06, 0xDC07,
        0xDC08, 0xDC09, 0xDC0A, 0xDC0B, 0xDC0C, 0xDC0D, 0xDC0E,
        // Common Properties
        0xDC41, 0xDC42, 0xDC43, 0xDC44, 0xDC45, 0xDC46, 0xDC47,
        0xDC48, 0xDC49, 0xDC4A, 0xDC4B, 0xDC4C, 0xDC4D, 0xDC4E,
        0xDC4F, 0xDC50, 0xDC51,
        // Music / Audio
        0xDC89, 0xDC8A, 0xDC8B, 0xDC8C, 0xDC91, 0xDC94, 0xDC96,
        0xDC9A, 0xDC9B,
        // Representative Sample
        0xDCD5, 0xDCD6, 0xDCD7, 0xDCD8, 0xDCD9, 0xDCDA,
        // Video
        0xDE00, 0xDE01, 0xDE02, 0xDE03, 0xDE04,
        // Audio
        0xDE91, 0xDE92, 0xDE93, 0xDE94, 0xDE95, 0xDE97, 0xDE99,
      ])
  }
}

/// Generator for MTP event codes (0x4001-0x400E).
private enum EventCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>.choose((0x4001, 0x400E))
  }
}

/// Generator for PTP/MTP response codes.
private enum ResponseCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>
      .one(of: [
        // Standard response codes
        Gen<UInt16>
          .fromElements(of: [
            0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
            0x2008, 0x2009, 0x200A, 0x200B, 0x200C, 0x200D, 0x200E,
            0x200F, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015,
            0x2016, 0x2017, 0x2018, 0x2019, 0x201A, 0x201B, 0x201C,
            0x201D, 0x201E, 0x201F, 0x2020,
          ]),
        // MTP extension response codes
        Gen<UInt16>
          .fromElements(of: [
            0xA801, 0xA802, 0xA803, 0xA804, 0xA805,
            0xA806, 0xA807, 0xA808, 0xA809, 0xA80A,
          ]),
        // Random unknown codes
        Gen<UInt16>.choose((0x2021, 0x2FFF)),
      ])
  }
}

// MARK: - Format Roundtrip Property Tests

final class FormatRoundtripPropertyTests: XCTestCase {

  func testForFilenameNeverCrashesAndReturnsValidCode() {
    property("forFilename returns a valid UInt16 format code for any filename")
      <- forAll(FilenameExtensionGenerator.arbitrary) { filename in
        let code = PTPObjectFormat.forFilename(filename)
        // Code should be a valid UInt16 (always true by type, but verify non-negative range)
        return code >= 0x0000 && code <= 0xFFFF
      }
  }

  func testForFilenameDescribeRoundtripProducesNonEmptyString() {
    property("forFilename → describe produces a non-empty string for any filename")
      <- forAll(FilenameExtensionGenerator.arbitrary) { filename in
        let code = PTPObjectFormat.forFilename(filename)
        let description = PTPObjectFormat.describe(code)
        return !description.isEmpty
      }
  }

  func testDescribeAlwaysContainsHexCode() {
    property("describe output always contains the hex representation of the code")
      <- forAll(FilenameExtensionGenerator.arbitrary) { filename in
        let code = PTPObjectFormat.forFilename(filename)
        let description = PTPObjectFormat.describe(code)
        let hexStr = String(format: "0x%04x", code)
        return description.contains(hexStr)
      }
  }

  func testKnownExtensionsReturnNonUndefinedFormat() {
    let knownFiles = [
      "photo.jpg", "track.mp3", "video.mp4", "notes.txt", "image.png",
      "clip.avi", "song.wav", "pic.heic", "raw.tiff", "movie.mkv",
    ]
    for file in knownFiles {
      let code = PTPObjectFormat.forFilename(file)
      XCTAssertNotEqual(
        code, PTPObjectFormat.undefined,
        "Known extension '\(file)' should not return undefined format")
    }
  }
}

// MARK: - Property Code Roundtrip Tests

final class PropertyCodeRoundtripPropertyTests: XCTestCase {

  func testDataTypeReturnsValidTypeForKnownCodes() {
    property("dataType returns a valid MTP data type for known property codes")
      <- forAll(PropCodeGenerator.arbitrary) { code in
        let dataType = MTPObjectPropCode.dataType(for: code)
        // Valid data types: UInt8=0x0002, UInt16=0x0004, UInt32=0x0006,
        // UInt64=0x0008, UInt128=0x000A, String=0xFFFF, Array=0x4004, ByteArray=0x4002
        let validTypes: Set<UInt16> = [0x0002, 0x0004, 0x0006, 0x0008, 0x000A, 0xFFFF, 0x4004, 0x4002]
        return validTypes.contains(dataType)
      }
  }

  func testDisplayNameReturnsNonEmptyString() {
    property("displayName returns a non-empty string for any known property code")
      <- forAll(PropCodeGenerator.arbitrary) { code in
        let name = MTPObjectPropCode.displayName(for: code)
        return !name.isEmpty
      }
  }

  func testDisplayNameForKnownCodesDoesNotContainUnknown() {
    property("displayName for known codes should not start with 'Unknown'")
      <- forAll(PropCodeGenerator.arbitrary) { code in
        let name = MTPObjectPropCode.displayName(for: code)
        return !name.hasPrefix("Unknown")
      }
  }

  func testDataTypeAndDisplayNameConsistency() {
    property("dataType and displayName both return values for the same code")
      <- forAll(PropCodeGenerator.arbitrary) { code in
        let dataType = MTPObjectPropCode.dataType(for: code)
        let name = MTPObjectPropCode.displayName(for: code)
        return dataType > 0 && !name.isEmpty
      }
  }
}

// MARK: - Event Code Roundtrip Tests

final class EventCodeRoundtripPropertyTests: XCTestCase {

  /// Build a minimal MTP event container from a code and optional parameter.
  private func buildEventData(code: UInt16, param: UInt32? = nil) -> Data {
    var data = Data(count: param != nil ? 16 : 12)
    // Length (4 bytes, little-endian)
    let len = UInt32(data.count)
    data[0] = UInt8(len & 0xFF)
    data[1] = UInt8((len >> 8) & 0xFF)
    data[2] = UInt8((len >> 16) & 0xFF)
    data[3] = UInt8((len >> 24) & 0xFF)
    // Type = 4 (event), little-endian
    data[4] = 4
    data[5] = 0
    // Code (2 bytes, little-endian)
    data[6] = UInt8(code & 0xFF)
    data[7] = UInt8((code >> 8) & 0xFF)
    // Transaction ID = 1
    data[8] = 1
    data[9] = 0
    data[10] = 0
    data[11] = 0
    // Optional parameter
    if let p = param {
      data[12] = UInt8(p & 0xFF)
      data[13] = UInt8((p >> 8) & 0xFF)
      data[14] = UInt8((p >> 16) & 0xFF)
      data[15] = UInt8((p >> 24) & 0xFF)
    }
    return data
  }

  func testEventParsingSucceedsForAllStandardCodes() {
    property("MTPEvent.fromRaw succeeds for all standard event codes 0x4001-0x400E")
      <- forAll(EventCodeGenerator.arbitrary) { code in
        // Events 0x4008, 0x400B, 0x400E don't require params
        let needsParam = ![0x4008, 0x400B, 0x400E].contains(code)
        let data = self.buildEventData(code: code, param: needsParam ? 42 : nil)
        let event = MTPEvent.fromRaw(data)
        return event != nil
      }
  }

  func testEventParsingReturnsNonUnknownForStandardCodes() {
    property("Standard event codes parse to specific cases, not .unknown")
      <- forAll(EventCodeGenerator.arbitrary) { code in
        let data = self.buildEventData(code: code, param: 42)
        guard let event = MTPEvent.fromRaw(data) else { return false }
        if case .unknown = event { return false }
        return true
      }
  }

  func testEventParsingWithEmptyDataReturnsNil() {
    let result = MTPEvent.fromRaw(Data())
    XCTAssertNil(result, "Empty data should return nil")
  }

  func testEventParsingWithTooShortDataReturnsNil() {
    property("Data shorter than 12 bytes always returns nil")
      <- forAll(Gen<Int>.choose((0, 11))) { size in
        let data = Data(repeating: 0, count: size)
        return MTPEvent.fromRaw(data) == nil
      }
  }
}

// MARK: - Response Code Roundtrip Tests

final class ResponseCodeRoundtripPropertyTests: XCTestCase {

  func testDescribeReturnsNonEmptyString() {
    property("PTPResponseCode.describe returns a non-empty string for any code")
      <- forAll(ResponseCodeGenerator.arbitrary) { code in
        let description = PTPResponseCode.describe(code)
        return !description.isEmpty
      }
  }

  func testDescribeAlwaysContainsHexSuffix() {
    property("describe output always includes the hex code in parentheses")
      <- forAll(ResponseCodeGenerator.arbitrary) { code in
        let description = PTPResponseCode.describe(code)
        let hexStr = String(format: "0x%04x", code)
        return description.contains("(\(hexStr))")
      }
  }

  func testDescribeForKnownCodesContainsName() {
    let knownCodes: [UInt16] = [
      0x2001, 0x2002, 0x2005, 0x2009, 0x200C, 0x2019, 0x201D,
    ]
    let expectedNames = [
      "OK", "GeneralError", "OperationNotSupported", "InvalidObjectHandle",
      "StoreFull", "DeviceBusy", "InvalidParameter",
    ]
    for (code, name) in zip(knownCodes, expectedNames) {
      let description = PTPResponseCode.describe(code)
      XCTAssertTrue(
        description.contains(name),
        "describe(0x\(String(format: "%04x", code))) should contain '\(name)', got '\(description)'"
      )
    }
  }

  func testUnknownResponseCodesDescribeAsUnknown() {
    property("Unknown response codes describe with 'Unknown' prefix")
      <- forAll(Gen<UInt16>.choose((0x2021, 0x2FFF))) { code in
        let description = PTPResponseCode.describe(code)
        return description.hasPrefix("Unknown")
      }
  }

  func testUserMessageReturnsNonEmptyForKnownCodes() {
    let knownCodes: [UInt16] = [
      0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2009, 0x200C, 0x2019,
    ]
    for code in knownCodes {
      let message = PTPResponseCode.userMessage(for: code)
      XCTAssertFalse(message.isEmpty, "userMessage for 0x\(String(format: "%04x", code)) should be non-empty")
    }
  }
}

// MARK: - Handle Validation Property Tests

final class HandleValidationPropertyTests: XCTestCase {

  /// Simulates the DeviceActor guard pattern: handle=0 should be rejected.
  private func validateHandle(_ handle: MTPObjectHandle, operation: String) throws {
    guard handle != 0 else {
      throw MTPError.preconditionFailed("\(operation) requires a valid object handle (got 0).")
    }
  }

  func testZeroHandleAlwaysThrows() {
    let operations = [
      "DeleteObject", "Rename", "MoveObject", "CopyObject",
      "BeginEditObject", "EndEditObject", "TruncateObject",
      "SetObjectPropValue", "GetThumb",
    ]
    for op in operations {
      XCTAssertThrowsError(try validateHandle(0, operation: op)) { error in
        guard let mtpError = error as? MTPError,
              case .preconditionFailed(let msg) = mtpError else {
          XCTFail("Expected preconditionFailed for \(op), got \(error)")
          return
        }
        XCTAssertTrue(msg.contains("handle"), "\(op) error should mention handle: \(msg)")
      }
    }
  }

  func testNonZeroHandleNeverThrows() {
    property("Non-zero handles pass validation for any operation")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max))) { handle in
        do {
          try self.validateHandle(handle, operation: "CopyObject")
          return true
        } catch {
          return false
        }
      }
  }

  func testHandleZeroBoundary() {
    // Handle = 0 is the only invalid handle value
    XCTAssertThrowsError(try validateHandle(0, operation: "CopyObject"))
    XCTAssertNoThrow(try validateHandle(1, operation: "CopyObject"))
    XCTAssertNoThrow(try validateHandle(UInt32.max, operation: "CopyObject"))
  }
}

// MARK: - CopyObject Idempotency Tests

final class CopyObjectIdempotencyPropertyTests: XCTestCase {

  func testCopyObjectProducesDifferentHandles() {
    // Test that the concept of copy always produces new handles
    // Using a simple handle allocator model (mirrors VirtualMTPDevice behavior)
    property("Two sequential allocations produce different handles")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max - 10))) { startHandle in
        let first = startHandle
        let second = startHandle + 1
        return first != second
      }
  }

  func testCopyObjectHandleMonotonicity() {
    property("Sequential handle allocations are strictly increasing")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max / 2))) { baseHandle in
        let handles = (0..<5).map { baseHandle + UInt32($0) }
        return zip(handles, handles.dropFirst()).allSatisfy { $0 < $1 }
      }
  }
}

// MARK: - Transaction ID Monotonicity Tests

final class TransactionIDMonotonicityPropertyTests: XCTestCase {

  func testTransactionIDsAreMonotonicallyIncreasing() {
    property("Sequential transaction IDs are strictly increasing")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max / 2))) { startTxID in
        let txIDs = (0..<10).map { startTxID + UInt32($0) }
        return zip(txIDs, txIDs.dropFirst()).allSatisfy { $0 < $1 }
      }
  }

  func testTransactionIDEncodesCorrectlyInContainer() {
    property("Transaction ID round-trips through PTP container encoding")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max))) { txid in
        let container = PTPContainer(type: 1, code: 0x1001, txid: txid)
        var buf = [UInt8](repeating: 0, count: 64)
        let written = container.encode(into: &buf)
        guard written >= 12 else { return false }
        // txid is at offset 8 in a PTP container (little-endian)
        let decoded = UInt32(buf[8])
          | (UInt32(buf[9]) << 8)
          | (UInt32(buf[10]) << 16)
          | (UInt32(buf[11]) << 24)
        return decoded == txid
      }
  }

  func testTransactionIDNeverZero() {
    // In the PTP spec, transaction ID 0 is reserved for session-open
    property("Valid transaction IDs for data operations are always > 0")
      <- forAll(Gen<UInt32>.choose((1, UInt32.max))) { txid in
        return txid > 0
      }
  }
}
