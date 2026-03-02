// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Sony-specific quirks tests validating Walkman (NWZ/NW) media player bugs
/// and Alpha camera PTP entries in the quirks database (VID 0x054c).
///
/// Key libmtp findings encoded here:
/// - DEVICE_FLAGS_SONY_NWZ_BUGS = BROKEN_MTPGETOBJPROPLIST | UNIQUE_FILENAMES
///   | FORCE_RESET_ON_CLOSE | UNLOAD_DRIVER
/// - NWZ devices auto-detected via "sony.net" vendor extension string
final class SonyDeviceQuirksTests: XCTestCase {

  private static let sonyVID: UInt16 = 0x054c
  private var db: QuirkDatabase!
  private var sonyEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    sonyEntries = db.entries.filter { $0.vid == Self.sonyVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllSonyEntriesHaveCorrectVID() {
    for entry in sonyEntries {
      XCTAssertEqual(
        entry.vid, Self.sonyVID,
        "Sony entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testSonyEntriesExist() {
    XCTAssertGreaterThan(
      sonyEntries.count, 100,
      "Expected a substantial Sony device database, found only \(sonyEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateSonyProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in sonyEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Sony PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Walkman NWZ Entries: BROKEN_MTPGETOBJPROPLIST

  /// libmtp DEVICE_FLAGS_SONY_NWZ_BUGS includes BROKEN_MTPGETOBJPROPLIST:
  /// GetObjectPropList returns incomplete/corrupt data on these devices.
  func testNWZWalkmanEntriesDoNotSupportGetObjectPropList() {
    // PIDs confirmed from libmtp to carry DEVICE_FLAGS_SONY_NWZ_BUGS
    let nwzPIDs: Set<UInt16> = [
      0x0325, 0x0326, 0x0327, 0x035a, 0x035b, 0x035c,
      0x036e, 0x0385, 0x0388, 0x038c, 0x038e, 0x0397,
      0x0398, 0x03d8, 0x03fc, 0x03fd, 0x03fe, 0x0404,
      0x04bb, 0x04be, 0x04cb, 0x04cc, 0x059a, 0x05a6,
      0x05a8, 0x0689, 0x06a9, 0x0882, 0x0c71, 0x0d00,
      0x0d01, 0x0e6e, 0x0e6f,
    ]
    let nwzEntries = sonyEntries.filter { nwzPIDs.contains($0.pid) }
    XCTAssertGreaterThan(
      nwzEntries.count, 20,
      "Expected at least 20 NWZ Walkman entries matching libmtp PIDs")
    for entry in nwzEntries {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "NWZ Walkman '\(entry.id)' must NOT support GetObjectPropList (BROKEN_MTPGETOBJPROPLIST)")
    }
  }

  // MARK: - Walkman NWZ Entries: FORCE_RESET_ON_CLOSE

  func testNWZWalkmanEntriesRequireResetOnOpen() {
    let nwzEntries = sonyEntries.filter {
      ($0.id.contains("nwz") || $0.id.hasPrefix("sony-nw-"))
        && !$0.id.contains("alpha")
    }
    let withResetFlag = nwzEntries.filter { $0.resolvedFlags().resetOnOpen }
    // At minimum, the core libmtp-sourced NWZ entries should have this
    XCTAssertGreaterThan(
      withResetFlag.count, 20,
      "Expected at least 20 NWZ entries with resetOnOpen=true (FORCE_RESET_ON_CLOSE)")
  }

  // MARK: - Walkman NWZ Entries: UNIQUE_FILENAMES

  /// UNIQUE_FILENAMES bug: device requires globally unique filenames.
  /// Mapped to writeToSubfolderOnly flag as the closest behavioral analog.
  func testNWZWalkmanEntriesHaveUniqueFilenameRequirement() {
    let nwzPIDs: Set<UInt16> = [
      0x0325, 0x0326, 0x0327, 0x035a, 0x035b, 0x035c,
      0x036e, 0x0385, 0x0388, 0x038c, 0x038e, 0x0397,
      0x0398, 0x03d8, 0x03fc, 0x03fd, 0x03fe, 0x0404,
      0x04bb, 0x04be, 0x04cb, 0x04cc, 0x059a, 0x05a6,
      0x05a8, 0x0689, 0x06a9, 0x0882, 0x0c71, 0x0d00,
      0x0d01, 0x0e6e, 0x0e6f,
    ]
    let nwzEntries = sonyEntries.filter { nwzPIDs.contains($0.pid) }
    for entry in nwzEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.writeToSubfolderOnly,
        "NWZ Walkman '\(entry.id)' should have writeToSubfolderOnly=true (UNIQUE_FILENAMES)")
    }
  }

  // MARK: - Sony Camera Entries: PTP Support

  func testSonyCameraEntriesExist() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    XCTAssertGreaterThan(
      cameras.count, 100,
      "Expected a substantial Sony camera database, found only \(cameras.count)")
  }

  func testSonyCameraEntriesHaveCameraClass() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    let withCameraClass = cameras.filter { $0.resolvedFlags().cameraClass }
    let ratio = Double(withCameraClass.count) / Double(cameras.count)
    XCTAssertGreaterThan(
      ratio, 0.80,
      "At least 80% of Sony cameras should have cameraClass=true (\(withCameraClass.count)/\(cameras.count))"
    )
  }

  func testSonyCameraSupportGetObjectPropList() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    let withPropList = cameras.filter { $0.resolvedFlags().supportsGetObjectPropList }
    let ratio = Double(withPropList.count) / Double(cameras.count)
    XCTAssertGreaterThan(
      ratio, 0.70,
      "At least 70% of Sony cameras should support GetObjectPropList (\(withPropList.count)/\(cameras.count))"
    )
  }

  func testSonyCamerasUseValidInterfaceClass() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    let withIface = cameras.filter { $0.ifaceClass != nil }
    for entry in withIface {
      let cls = entry.ifaceClass!
      // PTP Still Image class: 0x06, or vendor-specific 0xFF
      XCTAssertTrue(
        cls == 0x06 || cls == 0xFF,
        "Sony camera '\(entry.id)' should use USB class 0x06 (Still Image) or 0xFF (vendor), got 0x\(String(cls, radix: 16))"
      )
    }
  }

  // MARK: - Category Validation

  func testSonyWalkmanEntriesHaveAudioCategory() {
    let walkmanEntries = sonyEntries.filter {
      $0.id.contains("nwz") || $0.id.contains("walkman") || $0.id.hasPrefix("sony-nw-")
    }
    XCTAssertFalse(walkmanEntries.isEmpty, "Expected Sony Walkman entries in database")
    for entry in walkmanEntries {
      if let cat = entry.category {
        XCTAssertTrue(
          cat == "audio-player" || cat == "media-player",
          "Walkman entry '\(entry.id)' should have audio/media category, got '\(cat)'")
      }
    }
  }

  func testSonyHasReasonableCategoryDistribution() {
    let cameras = sonyEntries.filter { $0.category == "camera" }.count
    let audioPlayers =
      sonyEntries.filter {
        $0.category == "audio-player" || $0.category == "media-player"
      }
      .count

    XCTAssertGreaterThan(cameras, 100, "Expected significant Sony camera entries")
    XCTAssertGreaterThan(audioPlayers, 30, "Expected Sony Walkman/audio player entries")
  }

  // MARK: - Sony ID Naming Convention

  func testMajorityOfSonyIDsStartWithSony() {
    let sonyPrefixed = sonyEntries.filter { $0.id.hasPrefix("sony-") }
    let ratio = Double(sonyPrefixed.count) / Double(sonyEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x054c entries should start with 'sony-' (\(sonyPrefixed.count)/\(sonyEntries.count))"
    )
  }

  // MARK: - Camera Tuning Bounds

  func testSonyCameraChunkSizesAreInReasonableRange() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    for entry in cameras {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 512 * 1024,
          "Sony camera '\(entry.id)' chunk size \(chunk) is below 512KB minimum")
        XCTAssertLessThanOrEqual(
          chunk, 16 * 1024 * 1024,
          "Sony camera '\(entry.id)' chunk size \(chunk) exceeds 16MB — unusually large")
      }
    }
  }

  func testSonyCameraIOTimeoutsAreInReasonableRange() {
    let cameras = sonyEntries.filter { $0.category == "camera" }
    for entry in cameras {
      if let timeout = entry.ioTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          timeout, 5_000,
          "Sony camera '\(entry.id)' ioTimeout \(timeout)ms is below 5s — too aggressive")
        XCTAssertLessThanOrEqual(
          timeout, 120_000,
          "Sony camera '\(entry.id)' ioTimeout \(timeout)ms exceeds 120s — suspiciously high")
      }
    }
  }

  // MARK: - Walkman Tuning Bounds

  func testSonyWalkmanChunkSizesAreConservative() {
    let walkmans = sonyEntries.filter {
      $0.category == "audio-player" || $0.category == "media-player"
    }
    for entry in walkmans {
      if let chunk = entry.maxChunkBytes {
        XCTAssertLessThanOrEqual(
          chunk, 4 * 1024 * 1024,
          "Sony Walkman '\(entry.id)' chunk \(chunk) too large for portable media player")
      }
    }
  }
}
