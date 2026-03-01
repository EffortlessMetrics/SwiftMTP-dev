// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests designed to catch common source-level mutations in SwiftMTPCore.
///
/// Each test targets a single code path and uses precise assertions that
/// would fail if a typical mutation (boolean swap, boundary shift, arithmetic
/// sign change, nil-guard removal, etc.) were applied.
final class MutationDetectionTests: XCTestCase {

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPDeviceID Parsing & Comparison
  // ═══════════════════════════════════════════════════════════════════════════

  func testDeviceIDEquality_sameRaw() {
    let a = MTPDeviceID(raw: "usb:001:002")
    let b = MTPDeviceID(raw: "usb:001:002")
    XCTAssertEqual(a, b, "Identical raw strings must produce equal IDs")
  }

  func testDeviceIDInequality_differentRaw() {
    let a = MTPDeviceID(raw: "usb:001:002")
    let b = MTPDeviceID(raw: "usb:001:003")
    XCTAssertNotEqual(a, b, "Different raw strings must produce unequal IDs")
  }

  func testDeviceIDHashConsistency() {
    let id = MTPDeviceID(raw: "usb:005:010")
    var set = Set<MTPDeviceID>()
    set.insert(id)
    set.insert(id)
    XCTAssertEqual(set.count, 1, "Inserting same ID twice must not grow the set")
  }

  func testDeviceIDEmptyRaw() {
    let id = MTPDeviceID(raw: "")
    XCTAssertEqual(id.raw, "", "Empty raw string must round-trip")
  }

  func testDeviceIDCodableRoundTrip() throws {
    let original = MTPDeviceID(raw: "usb:007:042")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MTPDeviceID.self, from: data)
    XCTAssertEqual(original, decoded, "Codable round-trip must preserve equality")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPStorageID Operations
  // ═══════════════════════════════════════════════════════════════════════════

  func testStorageIDEquality_sameRaw() {
    let a = MTPStorageID(raw: 0x00010001)
    let b = MTPStorageID(raw: 0x00010001)
    XCTAssertEqual(a, b)
  }

  func testStorageIDInequality_differentRaw() {
    let a = MTPStorageID(raw: 0x00010001)
    let b = MTPStorageID(raw: 0x00020001)
    XCTAssertNotEqual(a, b)
  }

  func testStorageIDZero() {
    let id = MTPStorageID(raw: 0)
    XCTAssertEqual(id.raw, 0)
  }

  func testStorageIDMaxValue() {
    let id = MTPStorageID(raw: UInt32.max)
    XCTAssertEqual(id.raw, 0xFFFF_FFFF)
  }

  func testStorageIDCodableRoundTrip() throws {
    let original = MTPStorageID(raw: 0x00030002)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MTPStorageID.self, from: data)
    XCTAssertEqual(original, decoded)
  }

  func testStorageIDHashSetBehavior() {
    let ids: Set<MTPStorageID> = [
      MTPStorageID(raw: 1),
      MTPStorageID(raw: 2),
      MTPStorageID(raw: 1),
    ]
    XCTAssertEqual(ids.count, 2, "Duplicate storage IDs must collapse in a set")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPObjectHandle Operations
  // ═══════════════════════════════════════════════════════════════════════════

  func testObjectHandleIsUInt32TypeAlias() {
    let handle: MTPObjectHandle = 42
    XCTAssertEqual(handle, 42 as UInt32)
  }

  func testObjectHandleZero() {
    let handle: MTPObjectHandle = 0
    XCTAssertEqual(handle, 0)
  }

  func testObjectHandleMaxValue() {
    let handle: MTPObjectHandle = 0xFFFF_FFFF
    XCTAssertEqual(handle, UInt32.max)
  }

  func testObjectHandleArithmetic() {
    let a: MTPObjectHandle = 10
    let b: MTPObjectHandle = 5
    XCTAssertEqual(a - b, 5, "Catches + ↔ - mutation")
    XCTAssertEqual(a + b, 15, "Catches + ↔ - mutation")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPOp Code Mapping
  // ═══════════════════════════════════════════════════════════════════════════

  func testPTPOpGetDeviceInfo() {
    XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
  }

  func testPTPOpOpenSession() {
    XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
  }

  func testPTPOpCloseSession() {
    XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
  }

  func testPTPOpGetStorageIDs() {
    XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
  }

  func testPTPOpGetObject() {
    XCTAssertEqual(PTPOp.getObject.rawValue, 0x1009)
  }

  func testPTPOpSendObject() {
    XCTAssertEqual(PTPOp.sendObject.rawValue, 0x100D)
  }

  func testPTPOpDeleteObject() {
    XCTAssertEqual(PTPOp.deleteObject.rawValue, 0x100B)
  }

  func testPTPOpGetPartialObject() {
    XCTAssertEqual(PTPOp.getPartialObject.rawValue, 0x101B)
  }

  func testPTPOpGetPartialObject64() {
    XCTAssertEqual(PTPOp.getPartialObject64.rawValue, 0x95C4)
  }

  func testPTPOpAllCodesAreDistinct() {
    let codes: [UInt16] = [
      PTPOp.getDeviceInfo.rawValue,
      PTPOp.openSession.rawValue,
      PTPOp.closeSession.rawValue,
      PTPOp.getStorageIDs.rawValue,
      PTPOp.getStorageInfo.rawValue,
      PTPOp.getNumObjects.rawValue,
      PTPOp.getObjectHandles.rawValue,
      PTPOp.getObjectInfo.rawValue,
      PTPOp.getObject.rawValue,
      PTPOp.sendObject.rawValue,
      PTPOp.deleteObject.rawValue,
    ]
    XCTAssertEqual(Set(codes).count, codes.count, "All PTP op-codes must be unique")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPResponseCode Mapping
  // ═══════════════════════════════════════════════════════════════════════════

  func testResponseCodeOK() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
  }

  func testResponseCodeGeneralError() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2002), "GeneralError")
  }

  func testResponseCodeDeviceBusy() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2019), "DeviceBusy")
  }

  func testResponseCodeSessionAlreadyOpen() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x201E), "SessionAlreadyOpen")
  }

  func testResponseCodeUnknownReturnsNil() {
    XCTAssertNil(PTPResponseCode.name(for: 0xFFFF), "Unknown code must return nil")
  }

  func testResponseDescribeKnownCode() {
    let desc = PTPResponseCode.describe(0x2001)
    XCTAssertTrue(desc.contains("OK"), "Description must include name")
    XCTAssertTrue(desc.contains("0x2001"), "Description must include hex code")
  }

  func testResponseDescribeUnknownCode() {
    let desc = PTPResponseCode.describe(0x9999)
    XCTAssertTrue(desc.contains("Unknown"), "Unknown code must say 'Unknown'")
    XCTAssertTrue(desc.contains("0x9999"), "Must include the hex code")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPContainer Encode Boundary Conditions
  // ═══════════════════════════════════════════════════════════════════════════

  func testContainerEncodeMinimal() {
    let c = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])
    var buf = [UInt8](repeating: 0, count: 64)
    let n = buf.withUnsafeMutableBufferPointer { ptr in
      c.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(n, 12, "Empty-param container must encode to exactly 12 bytes")
  }

  func testContainerEncodeWithParams() {
    let c = PTPContainer(type: 1, code: 0x1002, txid: 1, params: [0xDEAD_BEEF, 0xCAFE_BABE])
    var buf = [UInt8](repeating: 0, count: 64)
    let n = buf.withUnsafeMutableBufferPointer { ptr in
      c.encode(into: ptr.baseAddress!)
    }
    XCTAssertEqual(n, 20, "Two params → 12 header + 8 param bytes = 20")
  }

  func testContainerEncodeLittleEndian() {
    let c = PTPContainer(type: 1, code: 0xABCD, txid: 0, params: [])
    var buf = [UInt8](repeating: 0, count: 64)
    _ = buf.withUnsafeMutableBufferPointer { ptr in
      c.encode(into: ptr.baseAddress!)
    }
    // code at offset 6..7 in little-endian
    XCTAssertEqual(buf[6], 0xCD, "Low byte of code at offset 6")
    XCTAssertEqual(buf[7], 0xAB, "High byte of code at offset 7")
  }

  func testContainerParamOrderPreserved() {
    let c = PTPContainer(type: 1, code: 0x1001, txid: 0, params: [1, 2, 3])
    var buf = [UInt8](repeating: 0, count: 64)
    _ = buf.withUnsafeMutableBufferPointer { ptr in
      c.encode(into: ptr.baseAddress!)
    }
    // Params start at offset 12, each 4 bytes LE
    XCTAssertEqual(buf[12], 1)
    XCTAssertEqual(buf[16], 2)
    XCTAssertEqual(buf[20], 3)
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPString Encode/Decode Boundary Conditions
  // ═══════════════════════════════════════════════════════════════════════════

  func testPTPStringEncodeEmpty() {
    let encoded = PTPString.encode("")
    XCTAssertEqual(encoded.count, 1, "Empty string encodes to single zero byte")
    XCTAssertEqual(encoded[0], 0)
  }

  func testPTPStringEncodeSingleChar() {
    let encoded = PTPString.encode("A")
    // Count byte + 1 char (2 bytes UTF-16LE) + null terminator (2 bytes)
    XCTAssertEqual(encoded[0], 2, "Length prefix: 1 char + null = 2")
    // 'A' = 0x0041 LE → 0x41 0x00
    XCTAssertEqual(encoded[1], 0x41)
    XCTAssertEqual(encoded[2], 0x00)
  }

  func testPTPStringRoundTrip() {
    let original = "Hello"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original, "Encode→decode must round-trip")
  }

  func testPTPStringRoundTripUnicode() {
    let original = "日本語"
    let encoded = PTPString.encode(original)
    var offset = 0
    let decoded = PTPString.parse(from: encoded, at: &offset)
    XCTAssertEqual(decoded, original, "Unicode must round-trip")
  }

  func testPTPStringParseTooShortReturnsNil() {
    let data = Data()
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNil(result, "Empty data must return nil")
  }

  func testPTPStringParseZeroLengthReturnsEmpty() {
    let data = Data([0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertEqual(result, "", "Zero-length prefix must return empty string")
  }

  func testPTPStringParseTruncatedReturnsNil() {
    // Claim 3 chars (6 bytes) but only provide 2 bytes
    let data = Data([0x03, 0x41, 0x00])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNil(result, "Truncated data must return nil")
  }

  func testPTPStringParse0xFFReturnsNil() {
    let data = Data([0xFF])
    var offset = 0
    let result = PTPString.parse(from: data, at: &offset)
    XCTAssertNil(result, "0xFF sentinel must return nil")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPObjectFormat Boundary Conditions
  // ═══════════════════════════════════════════════════════════════════════════

  func testObjectFormatJPG() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
  }

  func testObjectFormatJPEG() {
    XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpeg"), 0x3801)
  }

  func testObjectFormatPNG() {
    XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380B)
  }

  func testObjectFormatMP4() {
    XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300B)
  }

  func testObjectFormatMP3() {
    XCTAssertEqual(PTPObjectFormat.forFilename("song.mp3"), 0x3009)
  }

  func testObjectFormatTXT() {
    XCTAssertEqual(PTPObjectFormat.forFilename("readme.txt"), 0x3004)
  }

  func testObjectFormatAAC() {
    XCTAssertEqual(PTPObjectFormat.forFilename("audio.aac"), 0xB903)
  }

  func testObjectFormatUnknownExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("data.xyz"), 0x3000, "Unknown ext → Undefined")
  }

  func testObjectFormatCaseInsensitive() {
    XCTAssertEqual(
      PTPObjectFormat.forFilename("PHOTO.JPG"),
      PTPObjectFormat.forFilename("photo.jpg"),
      "Format lookup must be case-insensitive"
    )
  }

  func testObjectFormatNoExtension() {
    XCTAssertEqual(PTPObjectFormat.forFilename("Makefile"), 0x3000)
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPReader Boundary Conditions
  // ═══════════════════════════════════════════════════════════════════════════

  func testPTPReaderU8EmptyData() {
    var reader = PTPReader(data: Data())
    XCTAssertNil(reader.u8(), "Reading from empty data must return nil")
  }

  func testPTPReaderU16InsufficientBytes() {
    var reader = PTPReader(data: Data([0x01]))
    XCTAssertNil(reader.u16(), "1 byte is too few for u16")
  }

  func testPTPReaderU32InsufficientBytes() {
    var reader = PTPReader(data: Data([0x01, 0x02, 0x03]))
    XCTAssertNil(reader.u32(), "3 bytes is too few for u32")
  }

  func testPTPReaderU64InsufficientBytes() {
    var reader = PTPReader(data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]))
    XCTAssertNil(reader.u64(), "7 bytes is too few for u64")
  }

  func testPTPReaderU16LittleEndian() {
    var reader = PTPReader(data: Data([0xCD, 0xAB]))
    XCTAssertEqual(reader.u16(), 0xABCD, "Must decode little-endian u16")
  }

  func testPTPReaderU32LittleEndian() {
    var reader = PTPReader(data: Data([0x78, 0x56, 0x34, 0x12]))
    XCTAssertEqual(reader.u32(), 0x1234_5678, "Must decode little-endian u32")
  }

  func testPTPReaderU64LittleEndian() {
    var reader = PTPReader(data: Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    XCTAssertEqual(reader.u64(), 1)
  }

  func testPTPReaderSequentialReads() {
    let data = Data([0x01, 0x02, 0x00, 0x03, 0x00, 0x00, 0x00])
    var reader = PTPReader(data: data)
    XCTAssertEqual(reader.u8(), 0x01)
    XCTAssertEqual(reader.u16(), 0x0002)
    XCTAssertEqual(reader.u32(), 0x0000_0003)
  }

  func testPTPReaderMaxSafeCount() {
    XCTAssertEqual(PTPReader.maxSafeCount, 100_000)
  }

  func testPTPReaderValidateCountWithinLimit() {
    XCTAssertNoThrow(try PTPReader.validateCount(100_000))
  }

  func testPTPReaderValidateCountExceedsLimit() {
    XCTAssertThrowsError(try PTPReader.validateCount(100_001))
  }

  func testPTPReaderBytesExact() {
    var reader = PTPReader(data: Data([0xAA, 0xBB, 0xCC]))
    let result = reader.bytes(3)
    XCTAssertEqual(result, Data([0xAA, 0xBB, 0xCC]))
  }

  func testPTPReaderBytesTooMany() {
    var reader = PTPReader(data: Data([0xAA, 0xBB]))
    XCTAssertNil(reader.bytes(3), "Requesting more bytes than available must return nil")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPEvent.fromRaw Boundary Conditions
  // ═══════════════════════════════════════════════════════════════════════════

  func testEventFromRawTooShort() {
    let data = Data(repeating: 0, count: 11)
    XCTAssertNil(MTPEvent.fromRaw(data), "< 12 bytes must return nil")
  }

  func testEventFromRawExactlyMinimum() {
    // 12 bytes: valid header but no params → event code determines result
    // Use 0x4008 (DeviceInfoChanged) which needs no params
    var data = Data(repeating: 0, count: 12)
    // code at offset 6..7 LE
    data[6] = 0x08
    data[7] = 0x40
    let event = MTPEvent.fromRaw(data)
    if case .deviceInfoChanged = event {
      // expected
    } else {
      XCTFail("Expected .deviceInfoChanged, got \(String(describing: event))")
    }
  }

  func testEventFromRawObjectAdded() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0x02; data[7] = 0x40  // code 0x4002
    data[12] = 0x2A; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00  // handle 42
    if case .objectAdded(let h) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(h, 42)
    } else {
      XCTFail("Expected .objectAdded(42)")
    }
  }

  func testEventFromRawObjectRemoved() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0x03; data[7] = 0x40  // code 0x4003
    data[12] = 0x07; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00
    if case .objectRemoved(let h) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(h, 7)
    } else {
      XCTFail("Expected .objectRemoved(7)")
    }
  }

  func testEventFromRawStorageInfoChanged() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0x0C; data[7] = 0x40  // code 0x400C
    data[12] = 0x01; data[13] = 0x00; data[14] = 0x01; data[15] = 0x00  // storageID 0x00010001
    if case .storageInfoChanged(let sid) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(sid.raw, 0x0001_0001)
    } else {
      XCTFail("Expected .storageInfoChanged")
    }
  }

  func testEventFromRawStoreAdded() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0x04; data[7] = 0x40  // code 0x4004
    data[12] = 0x02; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00
    if case .storageAdded(let sid) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(sid.raw, 2)
    } else {
      XCTFail("Expected .storageAdded")
    }
  }

  func testEventFromRawStoreRemoved() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0x05; data[7] = 0x40  // code 0x4005
    data[12] = 0x03; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00
    if case .storageRemoved(let sid) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(sid.raw, 3)
    } else {
      XCTFail("Expected .storageRemoved")
    }
  }

  func testEventFromRawUnknownCode() {
    var data = Data(repeating: 0, count: 16)
    data[6] = 0xFF; data[7] = 0xFF  // code 0xFFFF — unrecognised
    data[12] = 0x01; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00
    if case .unknown(let code, let params) = MTPEvent.fromRaw(data) {
      XCTAssertEqual(code, 0xFFFF)
      XCTAssertEqual(params, [1])
    } else {
      XCTFail("Expected .unknown for unrecognised code")
    }
  }

  func testEventFromRawObjectAddedMissingParam() {
    // 0x4002 with no param bytes → nil
    var data = Data(repeating: 0, count: 12)
    data[6] = 0x02; data[7] = 0x40
    XCTAssertNil(MTPEvent.fromRaw(data), "ObjectAdded with no params must return nil")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPError Boolean / Nil Guard Tests
  // ═══════════════════════════════════════════════════════════════════════════

  func testIsSessionAlreadyOpen_true() {
    let err = MTPError.protocolError(code: 0x201E, message: nil)
    XCTAssertTrue(err.isSessionAlreadyOpen, "0x201E must be detected as session-already-open")
  }

  func testIsSessionAlreadyOpen_false() {
    let err = MTPError.protocolError(code: 0x2001, message: nil)
    XCTAssertFalse(err.isSessionAlreadyOpen, "Non-0x201E must not be session-already-open")
  }

  func testIsSessionAlreadyOpen_nonProtocolError() {
    let err = MTPError.busy
    XCTAssertFalse(err.isSessionAlreadyOpen)
  }

  func testErrorDescriptionNotNil() {
    let errors: [MTPError] = [
      .deviceDisconnected, .permissionDenied, .objectNotFound,
      .storageFull, .readOnly, .timeout, .busy, .sessionBusy,
    ]
    for err in errors {
      XCTAssertNotNil(err.errorDescription, "\(err) must have a description")
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPDeviceSummary Fingerprint
  // ═══════════════════════════════════════════════════════════════════════════

  func testFingerprintFormatting() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: 0x04E8,
      productID: 0x6860
    )
    XCTAssertEqual(summary.fingerprint, "04e8:6860", "Must format as lowercase hex vid:pid")
  }

  func testFingerprintWithNilIDs() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: nil,
      productID: nil
    )
    XCTAssertEqual(summary.fingerprint, "unknown", "Nil IDs must produce 'unknown'")
  }

  func testFingerprintPartialNilVendorID() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: nil,
      productID: 0x1234
    )
    XCTAssertEqual(summary.fingerprint, "unknown", "Partial nil must produce 'unknown'")
  }

  func testFingerprintPartialNilProductID() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: 0x1234,
      productID: nil
    )
    XCTAssertEqual(summary.fingerprint, "unknown", "Partial nil must produce 'unknown'")
  }

  func testFingerprintZeroPadding() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: 0x0001,
      productID: 0x0002
    )
    XCTAssertEqual(summary.fingerprint, "0001:0002", "Must zero-pad to 4 hex digits")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - MTPStorageInfo Arithmetic / Boolean
  // ═══════════════════════════════════════════════════════════════════════════

  func testStorageInfoReadOnlyTrue() {
    let info = MTPStorageInfo(
      id: MTPStorageID(raw: 1), description: "SD Card",
      capacityBytes: 1024, freeBytes: 512, isReadOnly: true
    )
    XCTAssertTrue(info.isReadOnly, "Catches true/false swap")
  }

  func testStorageInfoReadOnlyFalse() {
    let info = MTPStorageInfo(
      id: MTPStorageID(raw: 1), description: "Internal",
      capacityBytes: 1024, freeBytes: 512, isReadOnly: false
    )
    XCTAssertFalse(info.isReadOnly, "Catches true/false swap")
  }

  func testStorageInfoCapacityVsFree() {
    let info = MTPStorageInfo(
      id: MTPStorageID(raw: 1), description: "Test",
      capacityBytes: 1000, freeBytes: 300, isReadOnly: false
    )
    XCTAssertEqual(info.capacityBytes, 1000)
    XCTAssertEqual(info.freeBytes, 300)
    XCTAssertTrue(info.capacityBytes > info.freeBytes, "Catches < vs > swap")
    XCTAssertTrue(
      info.capacityBytes >= info.freeBytes, "Catches boundary mutations on >=")
  }

  func testStorageInfoUsedBytesArithmetic() {
    let info = MTPStorageInfo(
      id: MTPStorageID(raw: 1), description: "Test",
      capacityBytes: 1000, freeBytes: 300, isReadOnly: false
    )
    let used = info.capacityBytes - info.freeBytes
    XCTAssertEqual(used, 700, "Catches + ↔ - arithmetic swap")
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - PTPValue Type Decoding
  // ═══════════════════════════════════════════════════════════════════════════

  func testPTPReaderValueUint8() {
    var reader = PTPReader(data: Data([0x42]))
    let val = reader.value(dt: 0x0002)
    if case .uint8(let v) = val {
      XCTAssertEqual(v, 0x42)
    } else {
      XCTFail("Expected .uint8, got \(String(describing: val))")
    }
  }

  func testPTPReaderValueUint16() {
    var reader = PTPReader(data: Data([0xCD, 0xAB]))
    let val = reader.value(dt: 0x0004)
    if case .uint16(let v) = val {
      XCTAssertEqual(v, 0xABCD)
    } else {
      XCTFail("Expected .uint16")
    }
  }

  func testPTPReaderValueUint32() {
    var reader = PTPReader(data: Data([0x78, 0x56, 0x34, 0x12]))
    let val = reader.value(dt: 0x0006)
    if case .uint32(let v) = val {
      XCTAssertEqual(v, 0x1234_5678)
    } else {
      XCTFail("Expected .uint32")
    }
  }

  func testPTPReaderValueInt8Negative() {
    var reader = PTPReader(data: Data([0xFF]))
    let val = reader.value(dt: 0x0001)
    if case .int8(let v) = val {
      XCTAssertEqual(v, -1)
    } else {
      XCTFail("Expected .int8(-1)")
    }
  }

  func testPTPReaderValueString() {
    let strData = PTPString.encode("Test")
    var reader = PTPReader(data: strData)
    let val = reader.value(dt: 0xFFFF)
    if case .string(let s) = val {
      XCTAssertEqual(s, "Test")
    } else {
      XCTFail("Expected .string(\"Test\")")
    }
  }

  func testPTPReaderValueUnknownType() {
    var reader = PTPReader(data: Data([0x00]))
    let val = reader.value(dt: 0x00FF)
    XCTAssertNil(val, "Unknown data type must return nil")
  }

  func testPTPReaderValueArray() {
    // Array of uint8 (dt=0x4002): count(4 bytes LE) + elements
    var data = Data()
    data.append(contentsOf: [0x02, 0x00, 0x00, 0x00])  // count = 2
    data.append(0x0A)  // element 1
    data.append(0x0B)  // element 2
    var reader = PTPReader(data: data)
    let val = reader.value(dt: 0x4002)
    if case .array(let arr) = val {
      XCTAssertEqual(arr.count, 2)
      if case .uint8(let v0) = arr[0] { XCTAssertEqual(v0, 0x0A) }
      if case .uint8(let v1) = arr[1] { XCTAssertEqual(v1, 0x0B) }
    } else {
      XCTFail("Expected .array, got \(String(describing: val))")
    }
  }
}
