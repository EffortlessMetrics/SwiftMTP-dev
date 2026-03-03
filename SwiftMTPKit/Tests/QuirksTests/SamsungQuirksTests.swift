// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Samsung-specific quirks tests validating research-based improvements
/// for Samsung Galaxy phones, tablets, and wearables (VID 0x04e8).
final class SamsungQuirksTests: XCTestCase {

  private static let samsungVID: UInt16 = 0x04e8
  private var db: QuirkDatabase!
  private var samsungEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    samsungEntries = db.entries.filter { $0.vid == Self.samsungVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllSamsungEntriesHaveCorrectVID() {
    for entry in samsungEntries {
      XCTAssertEqual(
        entry.vid, Self.samsungVID,
        "Samsung entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testSamsungEntriesExist() {
    XCTAssertGreaterThan(
      samsungEntries.count, 100,
      "Expected a substantial Samsung device database, found only \(samsungEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateSamsungProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in samsungEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Samsung PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Category Validation

  func testSamsungPhonesAreCategorizedAsPhone() {
    let galaxyPhones = samsungEntries.filter {
      $0.id.contains("galaxy") && !$0.id.contains("tab") && !$0.id.contains("watch")
        && !$0.id.contains("buds")
    }
    for entry in galaxyPhones {
      if let cat = entry.category {
        XCTAssertTrue(
          cat == "phone" || cat == "tablet" || cat == "wearable",
          "Galaxy entry '\(entry.id)' has unexpected category '\(cat)'")
      }
    }
  }

  func testSamsungTabletsAreCategorizedCorrectly() {
    // Match "galaxy-tab" to avoid false positives on SSDs ("t7", "t9") or other "tab" substrings
    let tablets = samsungEntries.filter { $0.id.contains("galaxy-tab") }
    XCTAssertFalse(tablets.isEmpty, "Expected Samsung Galaxy Tab entries in database")
    for entry in tablets {
      XCTAssertEqual(
        entry.category, "tablet",
        "Samsung tablet entry '\(entry.id)' should have category 'tablet', got '\(entry.category ?? "nil")'"
      )
    }
  }

  func testSamsungWatchEntriesAreCategorizedAsWearable() {
    let watches = samsungEntries.filter { $0.id.contains("watch") }
    XCTAssertFalse(watches.isEmpty, "Expected Samsung Galaxy Watch entries in database")
    for entry in watches {
      XCTAssertEqual(
        entry.category, "wearable",
        "Samsung watch entry '\(entry.id)' should have category 'wearable', got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - Tuning Parameters (Research-Based)

  func testSamsungPromotedEntryHasOptimalChunkSize() {
    let promoted = samsungEntries.filter { $0.status == .promoted }
    XCTAssertFalse(promoted.isEmpty, "Expected at least one promoted Samsung entry")
    for entry in promoted {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 2_097_152,
          "Promoted Samsung entry '\(entry.id)' should use at least 2MB chunks (modern devices support 4MB)"
        )
      }
    }
  }

  func testSamsungPhonesHaveReasonableChunkSize() {
    let phones = samsungEntries.filter { $0.category == "phone" }
    for entry in phones {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 524_288,
          "Samsung phone '\(entry.id)' chunk size \(chunk) is below minimum 512KB")
        XCTAssertLessThanOrEqual(
          chunk, 16_777_216,
          "Samsung phone '\(entry.id)' chunk size \(chunk) exceeds safe 16MB maximum")
      }
    }
  }

  func testSamsungWearablesHaveConservativeChunkSize() {
    let wearables = samsungEntries.filter { $0.category == "wearable" }
    for entry in wearables {
      if let chunk = entry.maxChunkBytes {
        XCTAssertLessThanOrEqual(
          chunk, 2_097_152,
          "Samsung wearable '\(entry.id)' chunk \(chunk) too large for constrained device")
      }
    }
  }

  // MARK: - Samsung MTP Stack Behavioral Flags

  func testCoreSamsungEntriesRequireKernelDetach() {
    // Samsung's MTP stack requires kernel driver detach on macOS
    let coreEntries = samsungEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in coreEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Core Samsung entry '\(entry.id)' should require kernel detach for macOS compatibility")
    }
  }

  func testSamsungMTPEntriesHaveStabilizationDelay() {
    // Samsung devices need stabilization after claim due to custom MTP stack
    let mtpEntries = samsungEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in mtpEntries {
      if let stabilize = entry.stabilizeMs {
        XCTAssertGreaterThanOrEqual(
          stabilize, 300,
          "Samsung entry '\(entry.id)' stabilizeMs \(stabilize) too low for Samsung MTP stack")
      }
    }
  }

  func testSamsungPhoneTimeoutsAreAdequate() {
    // Samsung has a ~3 second connection timeout per libmtp comments
    let promoted = samsungEntries.filter { $0.status == .promoted || $0.status == .verified }
    for entry in promoted {
      if let hsTimeout = entry.handshakeTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          hsTimeout, 5000,
          "Samsung entry '\(entry.id)' handshake timeout \(hsTimeout)ms too low; Samsung needs ≥5s")
      }
    }
  }

  // MARK: - Samsung Hooks Validation

  func testCoreSamsungEntriesHavePostOpenSessionHook() {
    let coreEntries = samsungEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in coreEntries {
      guard let hooks = entry.hooks else {
        XCTFail("Samsung entry '\(entry.id)' missing hooks array")
        continue
      }
      let hasPostOpen = hooks.contains { $0.phase == .postOpenSession }
      XCTAssertTrue(
        hasPostOpen,
        "Samsung entry '\(entry.id)' should have postOpenSession hook for Samsung MTP readiness")
    }
  }

  func testCoreSamsungEntriesHaveStorageBackoff() {
    let coreEntries = samsungEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in coreEntries {
      guard let hooks = entry.hooks else {
        XCTFail("Samsung entry '\(entry.id)' missing hooks")
        continue
      }
      let hasBackoff = hooks.contains {
        $0.phase == .beforeGetStorageIDs && $0.busyBackoff != nil
      }
      XCTAssertTrue(
        hasBackoff,
        "Samsung entry '\(entry.id)' should have beforeGetStorageIDs busy-backoff hook")
    }
  }

  // MARK: - Samsung ID Naming Convention

  func testMajorityOfSamsungIDsStartWithSamsung() {
    // Some entries sharing Samsung's VID (0x04e8) may be OEM/partner devices
    let samsungPrefixed = samsungEntries.filter { $0.id.hasPrefix("samsung-") }
    let ratio = Double(samsungPrefixed.count) / Double(samsungEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x04e8 entries should start with 'samsung-' (\(samsungPrefixed.count)/\(samsungEntries.count))"
    )
  }

  // MARK: - Samsung PID Mode Coverage

  func testPrimaryMTPModePIDExists() {
    // 0x6860 is the primary MTP PID used by most Samsung Galaxy devices
    let primary = samsungEntries.first { $0.pid == 0x6860 }
    XCTAssertNotNil(primary, "Missing primary Samsung MTP PID 0x6860")
    XCTAssertEqual(primary?.status, .promoted, "Primary Samsung MTP entry should be promoted")
  }

  func testMTPADBModePIDExists() {
    // 0x685c is MTP+ADB mode
    let mtpAdb = samsungEntries.first { $0.pid == 0x685c }
    XCTAssertNotNil(mtpAdb, "Missing Samsung MTP+ADB PID 0x685c")
  }

  func testKiesModePIDExists() {
    // 0x6877 is Samsung Kies mode
    let kies = samsungEntries.first { $0.pid == 0x6877 }
    XCTAssertNotNil(kies, "Missing Samsung Kies mode PID 0x6877")
  }

  // MARK: - Samsung Category Distribution

  func testSamsungHasReasonableCategoryDistribution() {
    let phones = samsungEntries.filter { $0.category == "phone" }.count
    let tablets = samsungEntries.filter { $0.category == "tablet" }.count
    let wearables = samsungEntries.filter { $0.category == "wearable" }.count

    XCTAssertGreaterThan(phones, 50, "Expected significant Samsung phone entries")
    XCTAssertGreaterThan(tablets, 10, "Expected Samsung tablet entries")
    XCTAssertGreaterThan(wearables, 5, "Expected Samsung wearable entries")
  }

  // MARK: - Samsung Vendor-Specific Interface Class

  func testCoreSamsungEntriesUseVendorSpecificIfaceClass() {
    // Samsung Galaxy phones use vendor-specific class 0xff, not standard MTP 0x06
    let coreEntries = samsungEntries.filter {
      $0.status == .promoted || $0.status == .verified
    }
    for entry in coreEntries {
      if let ifaceClass = entry.ifaceClass {
        XCTAssertEqual(
          ifaceClass, 0xFF,
          "Core Samsung entry '\(entry.id)' should use vendor-specific interface class 0xFF")
      }
    }
  }
}
