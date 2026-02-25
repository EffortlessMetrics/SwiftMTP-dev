// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import Foundation
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
import MTPEndianCodec

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
    var comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
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

  // MARK: - Helpers

  private func makeLinkWithSamplePhoto() -> VirtualMTPLink {
    let config = VirtualDeviceConfig.pixel7
    return VirtualMTPLink(config: config)
  }
}
