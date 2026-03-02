// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Huawei/Honor-specific quirks tests validating device entries for
/// EMUI and HarmonyOS phones, tablets, wearables, and IoT devices (VID 0x12d1).
///
/// Huawei's MTP stack (EMUI/HarmonyOS) has notable platform-specific behavior:
///   - Vendor-specific USB interface class 0xFF on most phones (not standard MTP 0x06)
///   - HiSuite companion software can claim the USB interface, blocking MTP access
///   - macOS kernel driver must be detached before claiming the device
///   - HarmonyOS devices share the same VID but may differ in capability negotiation
///   - Post-open stabilization needed due to EMUI's deferred MTP readiness
final class HuaweiQuirksTests: XCTestCase {

  // MARK: - Constants

  /// Huawei Technologies primary USB Vendor ID (assigned by USB-IF).
  private static let huaweiVID: UInt16 = 0x12d1

  /// Valid device categories for Huawei's broad product ecosystem.
  private static let validCategories: Set<String> = [
    "phone", "tablet", "wearable", "fitness", "smart-home",
    "vr-headset", "embedded",
  ]

  private var db: QuirkDatabase!
  private var huaweiEntries: [DeviceQuirk]!
  private var honorEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    huaweiEntries = db.entries.filter { $0.vid == Self.huaweiVID }
    honorEntries = huaweiEntries.filter { $0.id.hasPrefix("honor-") }
  }

  // MARK: - Entry Existence

  func testHuaweiEntriesExist() {
    XCTAssertGreaterThan(
      huaweiEntries.count, 100,
      "Expected a substantial Huawei device database, found only \(huaweiEntries.count)")
  }

  func testHonorEntriesExist() {
    XCTAssertGreaterThan(
      honorEntries.count, 10,
      "Expected Honor sub-brand entries, found only \(honorEntries.count)")
  }

  // MARK: - Vendor ID Consistency

  func testAllHuaweiEntriesHaveCorrectVID() {
    for entry in huaweiEntries {
      XCTAssertEqual(
        entry.vid, Self.huaweiVID,
        "Huawei entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateHuaweiProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in huaweiEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Huawei PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Category Validation

  func testAllCategoriesAreValid() {
    for entry in huaweiEntries {
      if let cat = entry.category {
        XCTAssertTrue(
          Self.validCategories.contains(cat),
          "Huawei entry '\(entry.id)' has invalid category '\(cat)'")
      }
    }
  }

  func testHuaweiPhonesAreCategorizedAsPhone() {
    let phones = huaweiEntries.filter {
      ($0.id.contains("p30") || $0.id.contains("p40") || $0.id.contains("p50")
        || $0.id.contains("mate") || $0.id.contains("nova"))
        && !$0.id.contains("pad") && !$0.id.contains("watch")
    }
    for entry in phones {
      XCTAssertEqual(
        entry.category, "phone",
        "Huawei phone entry '\(entry.id)' should have category 'phone', got '\(entry.category ?? "nil")'"
      )
    }
  }

  func testHuaweiTabletsAreCategorizedCorrectly() {
    // MediaPad entries and MatePad entries explicitly categorized as tablet
    let tablets = huaweiEntries.filter { $0.category == "tablet" }
    XCTAssertFalse(tablets.isEmpty, "Expected Huawei tablet entries in database")
    let tabletKeywords = tablets.filter {
      $0.id.contains("mediapad") || $0.id.contains("matepad")
    }
    XCTAssertEqual(
      tabletKeywords.count, tablets.count,
      "All Huawei tablet entries should contain 'mediapad' or 'matepad' in ID")
  }

  func testHuaweiWatchEntriesAreCategorizedAsWearable() {
    let watches = huaweiEntries.filter { $0.id.contains("watch") }
    XCTAssertFalse(watches.isEmpty, "Expected Huawei Watch entries in database")
    for entry in watches {
      // Watch GT series are wearables; Watch Fit series are fitness trackers
      let allowedCategories: Set<String> = ["wearable", "fitness"]
      if let cat = entry.category {
        XCTAssertTrue(
          allowedCategories.contains(cat),
          "Huawei watch entry '\(entry.id)' should be 'wearable' or 'fitness', got '\(cat)'")
      }
    }
  }

  // MARK: - Category Distribution

  func testHuaweiHasReasonableCategoryDistribution() {
    let phones = huaweiEntries.filter { $0.category == "phone" }.count
    let tablets = huaweiEntries.filter { $0.category == "tablet" }.count
    let wearables = huaweiEntries.filter { $0.category == "wearable" }.count

    XCTAssertGreaterThan(phones, 50, "Expected significant Huawei phone entries")
    XCTAssertGreaterThan(tablets, 5, "Expected Huawei tablet entries")
    XCTAssertGreaterThan(wearables, 3, "Expected Huawei wearable entries")
  }

  // MARK: - ID Naming Convention

  func testAllIDsStartWithHuaweiOrHonor() {
    let branded = huaweiEntries.filter {
      $0.id.hasPrefix("huawei-") || $0.id.hasPrefix("honor-")
    }
    XCTAssertEqual(
      branded.count, huaweiEntries.count,
      "All VID 0x12d1 entries should start with 'huawei-' or 'honor-' "
        + "(\(branded.count)/\(huaweiEntries.count))")
  }

  func testMajorityOfIDsStartWithHuawei() {
    let huaweiPrefixed = huaweiEntries.filter { $0.id.hasPrefix("huawei-") }
    let ratio = Double(huaweiPrefixed.count) / Double(huaweiEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.70,
      "At least 70% of VID 0x12d1 entries should start with 'huawei-' "
        + "(\(huaweiPrefixed.count)/\(huaweiEntries.count))")
  }

  // MARK: - Key PID Coverage

  func testGenericMTPPIDExists() {
    // 0x107e is Huawei's common generic MTP mode PID
    let generic = huaweiEntries.first { $0.pid == 0x107e }
    XCTAssertNotNil(generic, "Missing Huawei generic MTP PID 0x107e")
  }

  func testP9P10EraPIDExists() {
    // 0x1052 covers P9/P10 generation
    let p9p10 = huaweiEntries.first { $0.pid == 0x1052 }
    XCTAssertNotNil(p9p10, "Missing Huawei P9/P10 PID 0x1052")
  }

  func testP20MatePIDExists() {
    // 0x1054 covers P20 Pro and Mate 20 era
    let p20 = huaweiEntries.first { $0.pid == 0x1054 }
    XCTAssertNotNil(p20, "Missing Huawei P20 Pro/Mate 20 PID 0x1054")
  }

  func testP30Mate30PIDExists() {
    // 0x10c1 covers P30/Mate 30 era
    let p30 = huaweiEntries.first { $0.pid == 0x10c1 }
    XCTAssertNotNil(p30, "Missing Huawei P30/Mate 30 PID 0x10c1")
  }

  // MARK: - EMUI/HarmonyOS Behavioral Flags

  func testKernelDetachRequiredOnPhonesWithIfaceClass() {
    // EMUI phones exposing a USB interface class need macOS kernel driver detach
    let phonesWithIface = huaweiEntries.filter {
      $0.category == "phone" && $0.ifaceClass != nil
    }
    for entry in phonesWithIface {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Huawei phone '\(entry.id)' with iface class should require kernel detach for macOS")
    }
  }

  func testVendorSpecificInterfaceClassIsCommon() {
    // Most Huawei phones use vendor-specific class 0xFF rather than standard MTP 0x06
    let withIface = huaweiEntries.filter { $0.ifaceClass != nil }
    let vendorSpecific = withIface.filter { $0.ifaceClass == 0xFF }
    if !withIface.isEmpty {
      let ratio = Double(vendorSpecific.count) / Double(withIface.count)
      XCTAssertGreaterThan(
        ratio, 0.5,
        "Majority of Huawei entries with iface class should use vendor-specific 0xFF "
          + "(\(vendorSpecific.count)/\(withIface.count))")
    }
  }

  // MARK: - Tuning Parameters

  func testHuaweiPhonesHaveReasonableChunkSize() {
    let phones = huaweiEntries.filter { $0.category == "phone" }
    for entry in phones {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 524_288,
          "Huawei phone '\(entry.id)' chunk size \(chunk) is below minimum 512KB")
        XCTAssertLessThanOrEqual(
          chunk, 16_777_216,
          "Huawei phone '\(entry.id)' chunk size \(chunk) exceeds safe 16MB maximum")
      }
    }
  }

  func testHuaweiWearablesHaveConservativeChunkSize() {
    let wearables = huaweiEntries.filter { $0.category == "wearable" }
    for entry in wearables {
      if let chunk = entry.maxChunkBytes {
        XCTAssertLessThanOrEqual(
          chunk, 2_097_152,
          "Huawei wearable '\(entry.id)' chunk \(chunk) too large for constrained device")
      }
    }
  }

  func testHuaweiIOTimeoutsAreAdequate() {
    // EMUI can be slow to respond; ensure I/O timeouts are generous
    for entry in huaweiEntries {
      if let ioTimeout = entry.ioTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          ioTimeout, 5000,
          "Huawei entry '\(entry.id)' ioTimeoutMs \(ioTimeout)ms too low for EMUI MTP stack")
      }
    }
  }

  // MARK: - Honor Sub-Brand

  func testHonorEntriesAllHaveHuaweiVID() {
    // Honor split from Huawei but historic devices still share VID 0x12d1
    for entry in honorEntries {
      XCTAssertEqual(
        entry.vid, Self.huaweiVID,
        "Honor entry '\(entry.id)' should use Huawei VID 0x12d1")
    }
  }

  func testHonorPhoneEntriesHavePhoneCategory() {
    let honorPhones = honorEntries.filter {
      $0.id.contains("magic")
        || $0.id.contains("honor-") && !$0.id.contains("pad")
          && !$0.id.contains("watch") && !$0.id.contains("band")
    }
    for entry in honorPhones {
      if let cat = entry.category {
        XCTAssertTrue(
          cat == "phone" || cat == "tablet",
          "Honor entry '\(entry.id)' has unexpected category '\(cat)' for a phone/tablet model")
      }
    }
  }
}
