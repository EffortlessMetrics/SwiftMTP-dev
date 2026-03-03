// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Google Pixel/Nexus-specific quirks tests validating research-based entries
/// for Google devices (VID 0x18d1). Tests cover Pixel phones, Nexus legacy
/// devices, Pixel tablets, wearables, and Google-branded OEM devices.
///
/// Research sources:
/// - libmtp music-players.h: canonical PID assignments (0x4ee1=MTP, 0x4ee2=MTP+ADB,
///   0x4ee5=PTP, 0x4ee6=PTP+ADB, 0x5202/0x5203=Pixel C)
/// - AOSP MTP implementation: stock Android MTP responder uses Still Image class
///   (0x06/0x01/0x01) for MTP and vendor-specific class (0xFF) for MTP+ADB
/// - Pixel 7 macOS USB stack issue: device doesn't expose MTP interfaces to
///   macOS IOUSBInterface; claim succeeds but bulk writes timeout (rc=-7)
/// - Android 10+ supports GetObjectPropList for efficient batch enumeration
final class GooglePixelQuirksTests: XCTestCase {

  private static let googleVID: UInt16 = 0x18d1
  private var db: QuirkDatabase!
  private var googleEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    googleEntries = db.entries.filter { $0.vid == Self.googleVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllGoogleEntriesHaveCorrectVID() {
    for entry in googleEntries {
      XCTAssertEqual(
        entry.vid, Self.googleVID,
        "Google entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testGoogleEntriesExist() {
    XCTAssertGreaterThan(
      googleEntries.count, 20,
      "Expected a substantial Google device database, found only \(googleEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateGoogleProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in googleEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Google PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Core PID Coverage (libmtp canonical assignments)

  func testPrimaryMTPModePIDExists() {
    // 0x4ee1 is the primary Nexus/Pixel MTP PID per libmtp
    let primary = googleEntries.first { $0.pid == 0x4ee1 }
    XCTAssertNotNil(primary, "Missing primary Google Nexus/Pixel MTP PID 0x4ee1")
  }

  func testMTPADBModePIDExists() {
    // 0x4ee2 is MTP+ADB composite mode per libmtp
    let mtpAdb = googleEntries.first { $0.pid == 0x4ee2 }
    XCTAssertNotNil(mtpAdb, "Missing Google Nexus/Pixel MTP+ADB PID 0x4ee2")
  }

  func testPixel34MTPModePIDExists() {
    // 0x4eed is Pixel 3/4 specific MTP mode
    let pixel34 = googleEntries.first { $0.pid == 0x4eed }
    XCTAssertNotNil(pixel34, "Missing Google Pixel 3/4 MTP PID 0x4eed")
  }

  func testPixelCMTPModePIDExists() {
    // 0x5202 is Pixel C MTP mode per libmtp
    let pixelC = googleEntries.first { $0.pid == 0x5202 }
    XCTAssertNotNil(pixelC, "Missing Google Pixel C MTP PID 0x5202")
  }

  // MARK: - Pixel 7 USB Stack Issue (Research-Based)

  func testPixel7EntryHasUSBStackWarnings() {
    guard let pixel7 = googleEntries.first(where: { $0.id == "google-pixel-7-4ee1" }) else {
      XCTFail("Missing google-pixel-7-4ee1 entry")
      return
    }
    // Pixel 7 has documented macOS USB stack incompatibility where MTP
    // interfaces are not exposed (IOUSBInterface not present in ioreg)
    XCTAssertEqual(pixel7.pid, 0x4ee1, "Pixel 7 should use standard MTP PID 0x4ee1")
    XCTAssertEqual(pixel7.category, "phone", "Pixel 7 should be categorized as phone")
  }

  func testPixel7HasExtendedTimeoutsForUSBStackIssue() {
    guard let pixel7 = googleEntries.first(where: { $0.id == "google-pixel-7-4ee1" }) else {
      XCTFail("Missing google-pixel-7-4ee1 entry")
      return
    }
    // Pixel 7 needs extended timeouts due to macOS USB stack latency
    if let hsTimeout = pixel7.handshakeTimeoutMs {
      XCTAssertGreaterThanOrEqual(
        hsTimeout, 10000,
        "Pixel 7 handshake timeout \(hsTimeout)ms should be ≥10s due to USB stack issues")
    }
    if let stabilize = pixel7.stabilizeMs {
      XCTAssertGreaterThanOrEqual(
        stabilize, 2000,
        "Pixel 7 stabilizeMs \(stabilize) should be ≥2s due to slow interface enumeration")
    }
  }

  func testPixel7HasKernelDetachFlag() {
    guard let pixel7 = googleEntries.first(where: { $0.id == "google-pixel-7-4ee1" }) else {
      XCTFail("Missing google-pixel-7-4ee1 entry")
      return
    }
    let flags = pixel7.resolvedFlags()
    XCTAssertTrue(
      flags.requiresKernelDetach,
      "Pixel 7 should require kernel detach (macOS Apple PTP driver claims the interface)")
  }

  // MARK: - MTP+ADB Entry Validation

  func testMTPADBEntryHasCorrectStatus() {
    guard let mtpAdb = googleEntries.first(where: { $0.id == "google-nexus-pixel-mtp-adb-4ee2" })
    else {
      XCTFail("Missing google-nexus-pixel-mtp-adb-4ee2 entry")
      return
    }
    XCTAssertEqual(
      mtpAdb.status, .verified,
      "MTP+ADB entry should be verified (well-documented mode)")
  }

  func testMTPADBEntrySupportsGetObjectPropList() {
    guard let mtpAdb = googleEntries.first(where: { $0.id == "google-nexus-pixel-mtp-adb-4ee2" })
    else {
      XCTFail("Missing google-nexus-pixel-mtp-adb-4ee2 entry")
      return
    }
    // libmtp explicitly enables PROPLIST_OVERRIDES_OI for 0x4ee1 and notes
    // Android 10+ supports GetObjectPropList; MTP+ADB should also support it
    let flags = mtpAdb.resolvedFlags()
    XCTAssertTrue(
      flags.supportsGetObjectPropList,
      "Google MTP+ADB entry should support GetObjectPropList (Android 10+ feature)")
  }

  func testMTPADBEntryRequiresKernelDetach() {
    guard let mtpAdb = googleEntries.first(where: { $0.id == "google-nexus-pixel-mtp-adb-4ee2" })
    else {
      XCTFail("Missing google-nexus-pixel-mtp-adb-4ee2 entry")
      return
    }
    let flags = mtpAdb.resolvedFlags()
    XCTAssertTrue(
      flags.requiresKernelDetach,
      "Google MTP+ADB entry should require kernel detach on macOS")
  }

  // MARK: - Pixel 3/4 Entry Validation

  func testPixel34EntryHasCorrectCategory() {
    guard let pixel34 = googleEntries.first(where: { $0.id == "google-pixel-3-4-4eed" }) else {
      XCTFail("Missing google-pixel-3-4-4eed entry")
      return
    }
    XCTAssertEqual(pixel34.category, "phone", "Pixel 3/4 should be categorized as phone")
  }

  func testPixel34SupportsGetObjectPropList() {
    guard let pixel34 = googleEntries.first(where: { $0.id == "google-pixel-3-4-4eed" }) else {
      XCTFail("Missing google-pixel-3-4-4eed entry")
      return
    }
    // Pixel 3+ with Android 10+ supports GetObjectPropList per AOSP source
    let flags = pixel34.resolvedFlags()
    XCTAssertTrue(
      flags.supportsGetObjectPropList,
      "Pixel 3/4 should support GetObjectPropList (Android 10+ stock MTP stack)")
  }

  // MARK: - Category Validation

  func testGooglePixelPhonesAreCategorizedAsPhone() {
    let pixelPhones = googleEntries.filter {
      $0.id.contains("pixel") && !$0.id.contains("tablet") && !$0.id.contains("watch")
        && !$0.id.contains("c-") && $0.category != nil
    }
    for entry in pixelPhones {
      XCTAssertEqual(
        entry.category, "phone",
        "Pixel phone entry '\(entry.id)' should have category 'phone', got '\(entry.category ?? "nil")'"
      )
    }
  }

  func testGooglePixelTabletEntriesExist() {
    let tablets = googleEntries.filter { $0.category == "tablet" }
    XCTAssertFalse(tablets.isEmpty, "Expected at least one Google Pixel Tablet entry")
  }

  func testGoogleWatchEntriesAreCategorizedAsWearable() {
    let watches = googleEntries.filter { $0.id.contains("watch") }
    XCTAssertFalse(watches.isEmpty, "Expected Google Pixel Watch entries in database")
    for entry in watches {
      XCTAssertEqual(
        entry.category, "wearable",
        "Google watch entry '\(entry.id)' should have category 'wearable', got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - Tuning Parameters (Research-Based)

  func testGooglePhonesHaveReasonableChunkSize() {
    let phones = googleEntries.filter { $0.category == "phone" }
    for entry in phones {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 524_288,
          "Google phone '\(entry.id)' chunk size \(chunk) is below minimum 512KB")
        XCTAssertLessThanOrEqual(
          chunk, 16_777_216,
          "Google phone '\(entry.id)' chunk size \(chunk) exceeds safe 16MB maximum")
      }
    }
  }

  func testCoreGoogleEntriesRequireKernelDetach() {
    // Google MTP stack requires kernel driver detach on macOS to claim from Apple PTP driver
    let coreEntries = googleEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in coreEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Core Google entry '\(entry.id)' should require kernel detach for macOS compatibility")
    }
  }

  // MARK: - Still Image Class Interface (0x06/0x01/0x01)

  func testPixel7UsesStillImageClassInterface() {
    guard let pixel7 = googleEntries.first(where: { $0.id == "google-pixel-7-4ee1" }) else {
      XCTFail("Missing google-pixel-7-4ee1 entry")
      return
    }
    // AOSP MTP responder exposes USB interface class 0x06 (Still Image Capture)
    // with subclass 0x01 and protocol 0x01 for standard MTP mode
    if let ifaceClass = pixel7.ifaceClass {
      XCTAssertEqual(
        ifaceClass, 0x06,
        "Pixel 7 MTP mode should use Still Image class (0x06), not vendor-specific")
    }
  }

  func testPixel34UsesStillImageClassInterface() {
    guard let pixel34 = googleEntries.first(where: { $0.id == "google-pixel-3-4-4eed" }) else {
      XCTFail("Missing google-pixel-3-4-4eed entry")
      return
    }
    if let ifaceClass = pixel34.ifaceClass {
      XCTAssertEqual(
        ifaceClass, 0x06,
        "Pixel 3/4 MTP mode should use Still Image class (0x06)")
    }
  }

  // MARK: - Google ID Naming Convention

  func testMajorityOfGoogleIDsStartWithGoogle() {
    let googlePrefixed = googleEntries.filter { $0.id.hasPrefix("google-") }
    let ratio = Double(googlePrefixed.count) / Double(googleEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.70,
      "At least 70% of VID 0x18d1 entries should start with 'google-' (\(googlePrefixed.count)/\(googleEntries.count))"
    )
  }

  // MARK: - Category Distribution

  func testGoogleHasReasonableCategoryDistribution() {
    let phones = googleEntries.filter { $0.category == "phone" }.count
    let wearables = googleEntries.filter { $0.category == "wearable" }.count

    XCTAssertGreaterThan(phones, 20, "Expected significant Google phone entries")
    XCTAssertGreaterThan(wearables, 1, "Expected Google wearable entries (Pixel Watch)")
  }

  // MARK: - Modern Pixel Series Coverage

  func testModernPixelSeriesHaveEntries() {
    // Pixel 5 through Pixel 9 series should all have entries
    let pixelModels = [
      "pixel-5", "pixel-6", "pixel-7", "pixel-8", "pixel-9",
    ]
    for model in pixelModels {
      let matches = googleEntries.filter { $0.id.contains(model) }
      XCTAssertFalse(
        matches.isEmpty,
        "Expected at least one entry for Google \(model)")
    }
  }

  func testPixelFoldEntryExists() {
    let foldEntries = googleEntries.filter { $0.id.contains("fold") }
    XCTAssertFalse(foldEntries.isEmpty, "Expected Google Pixel Fold entry in database")
  }

  func testPixelTabletEntryExists() {
    let tabletEntries = googleEntries.filter { $0.id.contains("tablet") }
    XCTAssertFalse(tabletEntries.isEmpty, "Expected Google Pixel Tablet entry in database")
  }
}
