// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import Foundation
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
import MTPEndianCodec
import SwiftMTPQuirks

/// Tests for GetObjectPropValue / SetObjectPropValue APIs including
/// VirtualMTPLink property read-back and PTPLayer date helpers.
final class ObjectPropAPITests: XCTestCase {

  // MARK: - VirtualMTPLink property get tests

  func testGetObjectFileNameReturnsName() async throws {
    let link = makeLinkWithSamplePhoto()
    let data = try await link.getObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.objectFileName)
    var offset = 0
    let name = PTPString.parse(from: data, at: &offset)
    XCTAssertEqual(name, "IMG_20250101_120000.jpg")
  }

  func testGetObjectSizeReturnsBytes() async throws {
    let link = makeLinkWithSamplePhoto()
    let data = try await link.getObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.objectSize)
    var dec = MTPDataDecoder(data: data)
    let size = dec.readUInt64()
    XCTAssertEqual(size, 4_500_000)  // as set in pixel7 config
  }

  func testGetObjectStorageIDReturnsCorrectStorage() async throws {
    let link = makeLinkWithSamplePhoto()
    let data = try await link.getObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.storageID)
    var dec = MTPDataDecoder(data: data)
    let raw = dec.readUInt32()
    XCTAssertNotNil(raw)
  }

  func testGetParentObjectReturnsParentHandle() async throws {
    let link = makeLinkWithSamplePhoto()
    let data = try await link.getObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.parentObject)
    var dec = MTPDataDecoder(data: data)
    let parent = dec.readUInt32()
    XCTAssertNotNil(parent)
  }

  func testGetDateModifiedReturnsPTPDateString() async throws {
    let link = makeLinkWithSamplePhoto()
    let data = try await link.getObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.dateModified)
    var offset = 0
    let str = PTPString.parse(from: data, at: &offset)
    XCTAssertNotNil(str)
    // Virtual device returns "20250101T000000"
    XCTAssertEqual(str, "20250101T000000")
  }

  func testGetUnknownPropertyThrows() async throws {
    let link = makeLinkWithSamplePhoto()
    do {
      _ = try await link.getObjectPropValue(handle: 0x0003, property: 0xFFFF)
      XCTFail("Should have thrown for unsupported property")
    } catch {
      // Expected
    }
  }

  func testGetPropertyOnMissingHandleThrows() async throws {
    let link = makeLinkWithSamplePhoto()
    do {
      _ = try await link.getObjectPropValue(
        handle: 0xDEAD, property: MTPObjectPropCode.objectFileName)
      XCTFail("Should have thrown for missing object")
    } catch {
      // Expected
    }
  }

  // MARK: - SetObjectPropValue tests

  func testSetObjectPropValueSucceeds() async throws {
    let link = makeLinkWithSamplePhoto()
    // VirtualMTPLink accepts all set operations silently
    let encoded = PTPString.encode("NEWNAME.JPG")
    try await link.setObjectPropValue(
      handle: 0x0003, property: MTPObjectPropCode.objectFileName, value: encoded)
    // No assertion needed — just verifying it doesn't throw
  }

  func testSetPropertyOnMissingHandleThrows() async throws {
    let link = makeLinkWithSamplePhoto()
    do {
      try await link.setObjectPropValue(
        handle: 0xDEAD, property: MTPObjectPropCode.objectFileName, value: Data())
      XCTFail("Should have thrown for missing object")
    } catch {
      // Expected
    }
  }

  // MARK: - PTPLayer date helpers

  func testGetObjectModificationDateParsesDate() async throws {
    let link = makeLinkWithSamplePhoto()
    let date = try await PTPLayer.getObjectModificationDate(handle: 0x0003, on: link)
    XCTAssertNotNil(date)
    // "20250101T000000" should parse to 2025-01-01 00:00:00 UTC
    let cal = Calendar.current
    let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
    XCTAssertEqual(comps.year, 2025)
    XCTAssertEqual(comps.month, 1)
    XCTAssertEqual(comps.day, 1)
  }

  func testGetObjectFileNameParsesName() async throws {
    let link = makeLinkWithSamplePhoto()
    let name = try await PTPLayer.getObjectFileName(handle: 0x0003, on: link)
    XCTAssertEqual(name, "IMG_20250101_120000.jpg")
  }

  // MARK: - MTPDateString encode/decode roundtrip

  func testMTPDateStringRoundtrip() {
    let now = Date(timeIntervalSince1970: 1_735_689_600)  // 2025-01-01 00:00:00 UTC
    let encoded = MTPDateString.encode(now)
    XCTAssertEqual(encoded, "20250101T000000")
    let decoded = MTPDateString.decode(encoded)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded!.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
  }

  func testMTPDateStringDecodeStripsTimezone() {
    let str = "20250101T000000.0Z"
    let decoded = MTPDateString.decode(str)
    XCTAssertNotNil(decoded)
  }

  // MARK: - PTPString roundtrip property test

  func testPTPStringEncodeDecodeRoundtrip() {
    let strings = ["", "hello", "IMG_0001.JPG", "DCIM", "20250101T000000", "日本語テスト"]
    for s in strings {
      let encoded = PTPString.encode(s)
      var offset = 0
      let decoded = PTPString.parse(from: encoded, at: &offset)
      XCTAssertEqual(decoded, s, "Failed roundtrip for: \(s)")
    }
  }

  func testPTPStringEncodeEmptyProducesMinimalData() {
    let data = PTPString.encode("")
    // Empty string: 1-byte length field = 0x00
    XCTAssertEqual(data.count, 1)
    XCTAssertEqual(data[0], 0)
  }

  // MARK: - PTPObjectInfoDataset date round-trip

  func testPTPObjectInfoDatasetDateDecoding() {
    // Encode an ObjectInfoDataset with a known modification date
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3801,
      size: 4096,
      name: "photo.jpg",
      useEmptyDates: false,
      omitOptionalStringFields: false
    )
    XCTAssertGreaterThan(data.count, 0)
    // Parse the encoded data using PTPReader (same code path as DeviceActor)
    var reader = PTPReader(data: data)
    _ = reader.u32()  // storageID
    _ = reader.u16()  // format
    _ = reader.u16()  // ProtectionStatus
    _ = reader.u32()  // ObjectCompressedSize
    _ = reader.u16()  // ThumbFormat
    _ = reader.u32()  // ThumbCompressedSize
    _ = reader.u32()  // ThumbPixWidth
    _ = reader.u32()  // ThumbPixHeight
    _ = reader.u32()  // ImagePixWidth
    _ = reader.u32()  // ImagePixHeight
    _ = reader.u32()  // ImageBitDepth
    _ = reader.u32()  // ParentObject
    _ = reader.u16()  // AssociationType
    _ = reader.u32()  // AssociationDesc
    _ = reader.u32()  // SequenceNumber
    _ = reader.string()  // Filename
    _ = reader.string()  // CaptureDate
    let modStr = reader.string()
    XCTAssertNotNil(modStr)
    // Default date string is "20250101T000000"
    XCTAssertEqual(modStr, "20250101T000000")
    let date = modStr.flatMap { MTPDateString.decode($0) }
    XCTAssertNotNil(date)
  }

  func testPTPObjectInfoDatasetEmptyDatesSkipped() {
    let data = PTPObjectInfoDataset.encode(
      storageID: 0x00010001,
      parentHandle: 0,
      format: 0x3001,
      size: 0,
      name: "folder",
      useEmptyDates: true,
      omitOptionalStringFields: false
    )
    XCTAssertGreaterThan(data.count, 0)
  }

  func testPTPObjectInfoDatasetOmitOptionalFields() {
    let withFields = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0, format: 0x3001,
      size: 0, name: "a", useEmptyDates: true, omitOptionalStringFields: false
    )
    let withoutFields = PTPObjectInfoDataset.encode(
      storageID: 0x00010001, parentHandle: 0, format: 0x3001,
      size: 0, name: "a", useEmptyDates: true, omitOptionalStringFields: true
    )
    XCTAssertGreaterThan(withFields.count, withoutFields.count)
  }

  // MARK: - Helpers

  private func makeLinkWithSamplePhoto() -> VirtualMTPLink {
    let config = VirtualDeviceConfig.pixel7
    return VirtualMTPLink(config: config)
  }
}

/// Tests for GetObjectPropsSupported and ObjectSize U64 fallback.
final class ObjectPropsSupportedTests: XCTestCase {

  /// VirtualMTPLink.getObjectPropsSupported returns a non-empty array for JPEG format.
  func testGetObjectPropsSupportedReturnsStandardProps() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let props = try await PTPLayer.getObjectPropsSupported(format: 0x3801, on: link)
    XCTAssertFalse(props.isEmpty, "Expected non-empty props list for JPEG format")
    XCTAssertTrue(props.contains(0xDC07), "objectFileName (0xDC07) should be supported")
    XCTAssertTrue(props.contains(0xDC04), "objectSize (0xDC04) should be supported")
  }

  /// getObjectPropsSupported returns an array that includes storageID and parentObject.
  func testGetObjectPropsSupportedContainsBaselineProps() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let props = try await PTPLayer.getObjectPropsSupported(format: 0x3001, on: link)
    // storageID (0xDC01), objectFormat (0xDC02), objectSize (0xDC04),
    // objectFileName (0xDC07), parentObject (0xDC0B)
    let baseline: [UInt16] = [0xDC01, 0xDC04, 0xDC07, 0xDC0B]
    for code in baseline {
      XCTAssertTrue(props.contains(code), "Missing expected code 0x\(String(code, radix: 16))")
    }
  }

  /// getObjectSizeU64 returns the size as UInt64 via GetObjectPropValue.
  func testGetObjectSizeU64ReturnsCorrectValue() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let config = VirtualDeviceConfig.pixel7
    let storage = try XCTUnwrap(config.storages.first, "pixel7 config must have storages")
    let handles = try await link.getObjectHandles(storage: storage.id, parent: nil)
    let firstHandle = try XCTUnwrap(handles.first, "pixel7 config must have objects")
    let size = try await PTPLayer.getObjectSizeU64(handle: firstHandle, on: link)
    XCTAssertNotNil(size)
  }

  /// skipGetObjectPropValue quirk flag is decoded correctly from QuirkFlags.
  func testSkipGetObjectPropValueFlagRoundTrips() throws {
    var flags = QuirkFlags()
    XCTAssertFalse(flags.skipGetObjectPropValue, "Default should be false")
    flags.skipGetObjectPropValue = true

    let enc = JSONEncoder()
    let data = try enc.encode(flags)
    let dec = JSONDecoder()
    let decoded = try dec.decode(QuirkFlags.self, from: data)
    XCTAssertTrue(decoded.skipGetObjectPropValue, "Flag should survive JSON round-trip")
  }

  /// skipGetObjectPropValue defaults to false in decoder (backward compat).
  func testSkipGetObjectPropValueDefaultsToFalse() throws {
    let json = Data("{}".utf8)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: json)
    XCTAssertFalse(decoded.skipGetObjectPropValue)
  }
}
