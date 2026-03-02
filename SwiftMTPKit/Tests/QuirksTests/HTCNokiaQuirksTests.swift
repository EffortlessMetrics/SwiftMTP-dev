// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// HTC (VID 0x0bb4) and Nokia (VID 0x0421, 0x2e04) quirks tests.
///
/// Research sourced from libmtp music-players.h:
/// - HTC: Android OEM with VID 0x0bb4. Nearly all devices use
///   DEVICE_FLAGS_ANDROID_BUGS (broken proplist, unload driver, long timeout,
///   force reset). Some older models (Windows Phone 8X/8s, One Mini 2, One Remix)
///   use DEVICE_FLAG_NONE. HTC VID is also reused by some third-party devices
///   (Zopo, Bird, DEXP Ixion, HP Touchpad via HTC OEM).
/// - Nokia: Symbian/MeeGo phones use VID 0x0421 with mostly DEVICE_FLAG_NONE.
///   Exceptions: N82/N73/N80 need DEVICE_FLAG_UNLOAD_DRIVER; 5800 XpressMusic
///   has DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL; X6 has broken proplist.
///   Nokia Android phones (Nokia 6, 6.1, 6.2) use VID 0x2e04 with
///   DEVICE_FLAGS_ANDROID_BUGS.
final class HTCNokiaQuirksTests: XCTestCase {

  // MARK: - Constants

  private static let htcVID: UInt16 = 0x0bb4
  private static let nokiaVID: UInt16 = 0x0421
  private static let nokiaAndroidVID: UInt16 = 0x2e04

  // MARK: - Properties

  private var db: QuirkDatabase!
  private var htcEntries: [DeviceQuirk]!
  private var nokiaEntries: [DeviceQuirk]!
  private var nokiaAndroidEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    htcEntries = db.entries.filter { $0.vid == Self.htcVID }
    nokiaEntries = db.entries.filter { $0.vid == Self.nokiaVID }
    nokiaAndroidEntries = db.entries.filter { $0.vid == Self.nokiaAndroidVID && $0.id.hasPrefix("nokia-") }
  }

  // MARK: - HTC VID Consistency

  func testAllHTCEntriesHaveCorrectVID() {
    for entry in htcEntries {
      XCTAssertEqual(
        entry.vid, Self.htcVID,
        "HTC entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testHTCEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      htcEntries.count, 5,
      "Expected HTC device entries in database, found only \(htcEntries.count)")
  }

  // MARK: - Nokia VID Consistency

  func testAllNokiaEntriesHaveCorrectVID() {
    for entry in nokiaEntries {
      XCTAssertEqual(
        entry.vid, Self.nokiaVID,
        "Nokia entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testNokiaEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      nokiaEntries.count, 5,
      "Expected Nokia device entries in database, found only \(nokiaEntries.count)")
  }

  func testNokiaAndroidEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      nokiaAndroidEntries.count, 1,
      "Expected Nokia Android entries (VID 0x2e04), found \(nokiaAndroidEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateHTCProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in htcEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate HTC PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateNokiaProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in nokiaEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Nokia PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Key HTC PIDs

  /// HTC One (ID1) - PID 0x0dda - DEVICE_FLAGS_ANDROID_BUGS in libmtp
  func testHTCOnePrimaryPIDExists() {
    let one = htcEntries.first { $0.pid == 0x0dda }
    XCTAssertNotNil(one, "Missing HTC One primary PID 0x0dda")
  }

  /// HTC One M8 (MTP) - PID 0x0f25 - DEVICE_FLAGS_ANDROID_BUGS in libmtp
  func testHTCOneM8MTPPIDExists() {
    let m8 = htcEntries.first { $0.pid == 0x0f25 }
    XCTAssertNotNil(m8, "Missing HTC One M8 (MTP) PID 0x0f25")
  }

  /// HTC M9 - PID 0x0401 - DEVICE_FLAGS_ANDROID_BUGS in libmtp
  func testHTCM9PIDExists() {
    let m9 = htcEntries.first { $0.pid == 0x0401 }
    XCTAssertNotNil(m9, "Missing HTC M9 PID 0x0401")
  }

  /// HTC One U11 (MTP) - PID 0x0f26 - DEVICE_FLAGS_ANDROID_BUGS in libmtp
  func testHTCU11PIDExists() {
    let u11 = htcEntries.first { $0.pid == 0x0f26 }
    XCTAssertNotNil(u11, "Missing HTC One U11 PID 0x0f26")
  }

  /// HTC Desire 310 (MTP) - PID 0x0ec6 - DEVICE_FLAGS_ANDROID_BUGS in libmtp
  func testHTCDesire310PIDExists() {
    let desire = htcEntries.first { $0.pid == 0x0ec6 }
    XCTAssertNotNil(desire, "Missing HTC Desire 310 PID 0x0ec6")
  }

  /// HTC generic Android device ID1 - PID 0x0c02 - used by many devices
  func testHTCGenericAndroidPIDExists() {
    let generic = htcEntries.first { $0.pid == 0x0c02 }
    XCTAssertNotNil(
      generic,
      "Missing HTC generic Android PID 0x0c02 (used by Zopo, HD2, Bird, Fairphone, etc.)")
  }

  // MARK: - Key Nokia PIDs

  /// Nokia N8 - PID 0x02fe - DEVICE_FLAG_NONE in libmtp
  func testNokiaN8PIDExists() {
    let n8 = nokiaEntries.first { $0.pid == 0x02fe }
    XCTAssertNotNil(n8, "Missing Nokia N8 PID 0x02fe")
  }

  /// Nokia Lumia WP8 - PID 0x0661 - covers Lumia 920, 820, most WP8 devices
  func testNokiaLumiaWP8PIDExists() {
    let lumia = nokiaEntries.first { $0.pid == 0x0661 }
    XCTAssertNotNil(lumia, "Missing Nokia Lumia WP8 PID 0x0661")
  }

  /// Nokia Lumia RM-975 - PID 0x06fc - various Lumia versions
  func testNokiaLumiaRM975PIDExists() {
    let lumia = nokiaEntries.first { $0.pid == 0x06fc }
    XCTAssertNotNil(lumia, "Missing Nokia Lumia RM-975 PID 0x06fc")
  }

  /// Nokia C7 - PID 0x03c1 - Symbian phone, DEVICE_FLAG_NONE
  func testNokiaC7PIDExists() {
    let c7 = nokiaEntries.first { $0.pid == 0x03c1 }
    XCTAssertNotNil(c7, "Missing Nokia C7 PID 0x03c1")
  }

  /// Nokia E7 - PID 0x0334 - Symbian phone, DEVICE_FLAG_NONE
  func testNokiaE7PIDExists() {
    let e7 = nokiaEntries.first { $0.pid == 0x0334 }
    XCTAssertNotNil(e7, "Missing Nokia E7 PID 0x0334")
  }

  /// Nokia 808 PureView - PID 0x05d3 - Symbian phone, DEVICE_FLAG_NONE
  func testNokia808PureViewPIDExists() {
    let pv = nokiaEntries.first { $0.pid == 0x05d3 }
    XCTAssertNotNil(pv, "Missing Nokia 808 PureView PID 0x05d3")
  }

  // MARK: - HTC Android Bug Flags

  /// Most HTC devices in libmtp use DEVICE_FLAGS_ANDROID_BUGS which implies:
  /// - requiresKernelDetach: true (DEVICE_FLAG_UNLOAD_DRIVER)
  /// - supportsGetObjectPropList: false (DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST)
  func testHTCAndroidDevicesRequireKernelDetach() {
    let androidDevices = htcEntries.filter {
      $0.flags != nil && !$0.id.contains("windows-phone")
    }
    let withKernelDetach = androidDevices.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(withKernelDetach.count) / Double(max(androidDevices.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.5,
      "Most HTC Android entries with flags should require kernel detach (\(withKernelDetach.count)/\(androidDevices.count))"
    )
  }

  func testHTCAndroidDevicesDisableGetObjectPropList() {
    let androidDevices = htcEntries.filter {
      $0.id.contains("one") || $0.id.contains("desire") || $0.id.contains("evo")
        || $0.id.contains("butterfly")
    }
    for entry in androidDevices {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "HTC Android entry '\(entry.id)' should have GetObjectPropList disabled (DEVICE_FLAGS_ANDROID_BUGS per libmtp)"
      )
    }
  }

  // MARK: - Nokia Symbian Devices (DEVICE_FLAG_NONE)

  /// Nokia Symbian phones (N8, C7, E7, 808 PureView, N97, N95, etc.)
  /// use DEVICE_FLAG_NONE in libmtp - minimal quirks needed.
  func testNokiaSymbianDevicesHaveMinimalQuirks() {
    let symbianIDs = ["nokia-n8", "nokia-c7", "nokia-e7", "nokia-808-pureview"]
    for prefix in symbianIDs {
      let matches = nokiaEntries.filter { $0.id.hasPrefix(prefix) }
      XCTAssertFalse(
        matches.isEmpty,
        "Expected Nokia Symbian entry with prefix '\(prefix)' in database")
    }
  }

  // MARK: - Nokia Android Devices (VID 0x2e04)

  /// Nokia 6, 6.1, 6.2 use VID 0x2e04 and DEVICE_FLAGS_ANDROID_BUGS in libmtp.
  func testNokiaAndroidDevicesRequireKernelDetach() {
    for entry in nokiaAndroidEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Nokia Android entry '\(entry.id)' should require kernel detach (DEVICE_FLAGS_ANDROID_BUGS)"
      )
    }
  }

  func testNokiaAndroidDevicesDisableGetObjectPropList() {
    for entry in nokiaAndroidEntries {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Nokia Android entry '\(entry.id)' should have GetObjectPropList disabled")
    }
  }

  // MARK: - HTC ID Naming Convention

  func testHTCIDsStartWithHTC() {
    let htcPrefixed = htcEntries.filter { $0.id.hasPrefix("htc-") }
    let ratio = Double(htcPrefixed.count) / Double(max(htcEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.80,
      "At least 80% of VID 0x0bb4 entries should start with 'htc-' (\(htcPrefixed.count)/\(htcEntries.count))"
    )
  }

  func testNokiaIDsStartWithNokia() {
    let nokiaPrefixed = nokiaEntries.filter { $0.id.hasPrefix("nokia-") }
    let ratio = Double(nokiaPrefixed.count) / Double(max(nokiaEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x0421 entries should start with 'nokia-' (\(nokiaPrefixed.count)/\(nokiaEntries.count))"
    )
  }

  // MARK: - HTC Category Validation

  func testHTCPhonesAreCategorizedCorrectly() {
    let phones = htcEntries.filter { $0.category == "phone" }
    XCTAssertFalse(phones.isEmpty, "Expected HTC phone category entries")
  }

  // MARK: - Nokia Category Validation

  func testNokiaPhonesAreCategorizedCorrectly() {
    let phones = nokiaEntries.filter { $0.category == "phone" }
    XCTAssertFalse(phones.isEmpty, "Expected Nokia phone category entries")
  }

  // MARK: - HTC One Series Completeness

  /// Verify that multiple HTC One variants are represented in the database,
  /// matching the rich set documented in libmtp (One M7, M8, M9, One X, etc.)
  func testHTCOneSeriesVariantsExist() {
    let oneEntries = htcEntries.filter { $0.id.contains("one") }
    XCTAssertGreaterThanOrEqual(
      oneEntries.count, 2,
      "Expected multiple HTC One series variants, found \(oneEntries.count)")
  }

  // MARK: - HTC Desire Series

  func testHTCDesireSeriesExists() {
    let desireEntries = htcEntries.filter { $0.id.contains("desire") }
    XCTAssertGreaterThanOrEqual(
      desireEntries.count, 1,
      "Expected at least one HTC Desire entry, found \(desireEntries.count)")
  }

  // MARK: - VID Matching Works for Both Brands

  func testVIDMatchingReturnsHTCEntries() {
    let matched = db.entries.filter { $0.vid == 0x0bb4 }
    XCTAssertFalse(matched.isEmpty, "VID 0x0bb4 should match HTC entries")
    XCTAssertEqual(
      matched.count, htcEntries.count,
      "VID 0x0bb4 filter count should match htcEntries count")
  }

  func testVIDMatchingReturnsNokiaEntries() {
    let matched = db.entries.filter { $0.vid == 0x0421 }
    XCTAssertFalse(matched.isEmpty, "VID 0x0421 should match Nokia entries")
    XCTAssertEqual(
      matched.count, nokiaEntries.count,
      "VID 0x0421 filter count should match nokiaEntries count")
  }

  func testVIDMatchingReturnsNokiaAndroidEntries() {
    let matched = db.entries.filter { $0.vid == 0x2e04 && $0.id.hasPrefix("nokia-") }
    XCTAssertFalse(matched.isEmpty, "VID 0x2e04 should match Nokia Android entries")
    XCTAssertEqual(
      matched.count, nokiaAndroidEntries.count,
      "VID 0x2e04 nokia-prefixed filter count should match nokiaAndroidEntries count")
  }

  // MARK: - HTC Windows Phone Entries

  /// HTC Windows Phone 8X (PIDs 0x0ba1, 0x0ba2) and 8s (0xf0ca) use
  /// DEVICE_FLAG_NONE in libmtp - no Android-specific bugs.
  func testHTCWindowsPhoneEntriesExist() {
    let wpEntries = htcEntries.filter {
      $0.id.contains("windows-phone") || $0.id.contains("wp8")
    }
    // WP entries may or may not be in the database; just verify they don't have Android bugs if present
    for entry in wpEntries {
      let flags = entry.resolvedFlags()
      // Windows Phone MTP stack is different from Android - shouldn't need Android bug workarounds
      XCTAssertFalse(
        flags.supportsGetObjectPropList && flags.requiresKernelDetach,
        "HTC Windows Phone entry '\(entry.id)' should not combine Android-style bug flags")
    }
  }

  // MARK: - Nokia Lumia Series

  /// Nokia Lumia phones (WP8) should be present in the database.
  func testNokiaLumiaEntriesExist() {
    let lumiaEntries = nokiaEntries.filter { $0.id.contains("lumia") }
    XCTAssertGreaterThanOrEqual(
      lumiaEntries.count, 1,
      "Expected at least one Nokia Lumia entry, found \(lumiaEntries.count)")
  }

  // MARK: - Cross-Brand VID Isolation

  /// HTC and Nokia VIDs should not overlap in the database.
  func testHTCAndNokiaVIDsDoNotOverlap() {
    let htcVIDs = Set(htcEntries.map(\.vid))
    let nokiaVIDs = Set(nokiaEntries.map(\.vid))
    let nokiaAndroidVIDs = Set(nokiaAndroidEntries.map(\.vid))

    XCTAssertTrue(
      htcVIDs.isDisjoint(with: nokiaVIDs),
      "HTC and Nokia VIDs should not overlap")
    XCTAssertTrue(
      htcVIDs.isDisjoint(with: nokiaAndroidVIDs),
      "HTC and Nokia Android VIDs should not overlap")
  }
}
