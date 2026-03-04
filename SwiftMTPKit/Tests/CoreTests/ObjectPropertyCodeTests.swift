// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests for MTPObjectPropCode raw values, data types, display names, and property groups.
final class ObjectPropertyCodeTests: XCTestCase {

  // MARK: - Raw Value Verification

  func testObjectInfoPropertyCodes() {
    XCTAssertEqual(MTPObjectPropCode.storageID, 0xDC01)
    XCTAssertEqual(MTPObjectPropCode.objectFormat, 0xDC02)
    XCTAssertEqual(MTPObjectPropCode.protectionStatus, 0xDC03)
    XCTAssertEqual(MTPObjectPropCode.objectSize, 0xDC04)
    XCTAssertEqual(MTPObjectPropCode.associationType, 0xDC05)
    XCTAssertEqual(MTPObjectPropCode.associationDesc, 0xDC06)
    XCTAssertEqual(MTPObjectPropCode.objectFileName, 0xDC07)
    XCTAssertEqual(MTPObjectPropCode.dateCreated, 0xDC08)
    XCTAssertEqual(MTPObjectPropCode.dateModified, 0xDC09)
    XCTAssertEqual(MTPObjectPropCode.keywords, 0xDC0A)
    XCTAssertEqual(MTPObjectPropCode.parentObject, 0xDC0B)
    XCTAssertEqual(MTPObjectPropCode.allowedFolderContents, 0xDC0C)
    XCTAssertEqual(MTPObjectPropCode.hidden, 0xDC0D)
    XCTAssertEqual(MTPObjectPropCode.systemObject, 0xDC0E)
  }

  func testCommonPropertyCodes() {
    XCTAssertEqual(MTPObjectPropCode.persistentUniqueObjectIdentifier, 0xDC41)
    XCTAssertEqual(MTPObjectPropCode.syncID, 0xDC42)
    XCTAssertEqual(MTPObjectPropCode.propertyBag, 0xDC43)
    XCTAssertEqual(MTPObjectPropCode.name, 0xDC44)
    XCTAssertEqual(MTPObjectPropCode.createdBy, 0xDC45)
    XCTAssertEqual(MTPObjectPropCode.artist, 0xDC46)
    XCTAssertEqual(MTPObjectPropCode.dateAuthored, 0xDC47)
    XCTAssertEqual(MTPObjectPropCode.objectDescription, 0xDC48)
    XCTAssertEqual(MTPObjectPropCode.copyrightInformation, 0xDC4B)
    XCTAssertEqual(MTPObjectPropCode.nonConsumable, 0xDC4F)
    XCTAssertEqual(MTPObjectPropCode.producerSerialNumber, 0xDC51)
  }

  func testAudioPropertyCodes() {
    XCTAssertEqual(MTPObjectPropCode.duration, 0xDC89)
    XCTAssertEqual(MTPObjectPropCode.rating, 0xDC8A)
    XCTAssertEqual(MTPObjectPropCode.track, 0xDC8B)
    XCTAssertEqual(MTPObjectPropCode.genre, 0xDC8C)
    XCTAssertEqual(MTPObjectPropCode.albumName, 0xDC9A)
    XCTAssertEqual(MTPObjectPropCode.albumArtist, 0xDC9B)
    XCTAssertEqual(MTPObjectPropCode.sampleRate, 0xDE91)
    XCTAssertEqual(MTPObjectPropCode.numberOfChannels, 0xDE92)
    XCTAssertEqual(MTPObjectPropCode.audioBitRate, 0xDE94)
  }

  func testImageVideoPropertyCodes() {
    XCTAssertEqual(MTPObjectPropCode.width, 0xDE00)
    XCTAssertEqual(MTPObjectPropCode.height, 0xDE01)
    XCTAssertEqual(MTPObjectPropCode.dpi, 0xDE02)
    XCTAssertEqual(MTPObjectPropCode.fourCCCodec, 0xDE03)
    XCTAssertEqual(MTPObjectPropCode.videoBitRate, 0xDE04)
  }

  func testRepresentativeSamplePropertyCodes() {
    XCTAssertEqual(MTPObjectPropCode.representativeSampleFormat, 0xDCD5)
    XCTAssertEqual(MTPObjectPropCode.representativeSampleSize, 0xDCD6)
    XCTAssertEqual(MTPObjectPropCode.representativeSampleHeight, 0xDCD7)
    XCTAssertEqual(MTPObjectPropCode.representativeSampleWidth, 0xDCD8)
    XCTAssertEqual(MTPObjectPropCode.representativeSampleDuration, 0xDCD9)
    XCTAssertEqual(MTPObjectPropCode.representativeSampleData, 0xDCDA)
  }

  // MARK: - Data Type Lookup

  func testStorageIDIsUInt32() {
    // 0x0006 = UInt32
    XCTAssertEqual(MTPObjectPropCode.dataType(for: MTPObjectPropCode.storageID), 0x0006)
  }

  func testObjectFileNameIsString() {
    // 0xFFFF = String
    XCTAssertEqual(MTPObjectPropCode.dataType(for: MTPObjectPropCode.objectFileName), 0xFFFF)
  }

  func testObjectSizeIsUInt64() {
    // 0x0008 = UInt64
    XCTAssertEqual(MTPObjectPropCode.dataType(for: MTPObjectPropCode.objectSize), 0x0008)
  }

  func testObjectFormatIsUInt16() {
    // 0x0004 = UInt16
    XCTAssertEqual(MTPObjectPropCode.dataType(for: MTPObjectPropCode.objectFormat), 0x0004)
  }

  func testPersistentUniqueIDIsUInt128() {
    // 0x000A = UInt128
    XCTAssertEqual(
      MTPObjectPropCode.dataType(for: MTPObjectPropCode.persistentUniqueObjectIdentifier), 0x000A)
  }

  func testNonConsumableIsUInt8() {
    // 0x0002 = UInt8
    XCTAssertEqual(MTPObjectPropCode.dataType(for: MTPObjectPropCode.nonConsumable), 0x0002)
  }

  func testAllowedFolderContentsIsArray() {
    // 0x4004 = UInt16 array
    XCTAssertEqual(
      MTPObjectPropCode.dataType(for: MTPObjectPropCode.allowedFolderContents), 0x4004)
  }

  func testRepresentativeSampleDataIsByteArray() {
    // 0x4002 = byte array
    XCTAssertEqual(
      MTPObjectPropCode.dataType(for: MTPObjectPropCode.representativeSampleData), 0x4002)
  }

  func testUnknownCodeDefaultsToString() {
    XCTAssertEqual(MTPObjectPropCode.dataType(for: 0xFFEE), 0xFFFF)
  }

  func testAudioPropertiesAreUInt32() {
    let uint32AudioProps: [UInt16] = [
      MTPObjectPropCode.duration,
      MTPObjectPropCode.sampleRate,
      MTPObjectPropCode.audioBitRate,
      MTPObjectPropCode.audioBitDepth,
    ]
    for prop in uint32AudioProps {
      XCTAssertEqual(
        MTPObjectPropCode.dataType(for: prop), 0x0006,
        "Property 0x\(String(prop, radix: 16)) should be UInt32")
    }
  }

  func testStringProperties() {
    let stringProps: [UInt16] = [
      MTPObjectPropCode.dateCreated,
      MTPObjectPropCode.dateModified,
      MTPObjectPropCode.artist,
      MTPObjectPropCode.genre,
      MTPObjectPropCode.albumName,
    ]
    for prop in stringProps {
      XCTAssertEqual(
        MTPObjectPropCode.dataType(for: prop), 0xFFFF,
        "Property 0x\(String(prop, radix: 16)) should be String")
    }
  }

  // MARK: - Display Names

  func testDisplayNameReturnsReadableNames() {
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.storageID), "Storage ID")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.objectFileName), "File Name")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.objectSize), "Object Size")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.dateCreated), "Date Created")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.parentObject), "Parent Object")
  }

  func testDisplayNameAudioProperties() {
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.duration), "Duration")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.albumName), "Album Name")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.artist), "Artist")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.sampleRate), "Sample Rate")
  }

  func testDisplayNameVideoProperties() {
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.width), "Width")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.height), "Height")
    XCTAssertEqual(MTPObjectPropCode.displayName(for: MTPObjectPropCode.videoBitRate), "Video Bit Rate")
  }

  func testDisplayNameUnknownCode() {
    let name = MTPObjectPropCode.displayName(for: 0xFFEE)
    XCTAssertTrue(name.contains("Unknown"))
    XCTAssertTrue(name.contains("FFEE"))
  }
}
