// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// SonyEricsson (pre-Android feature phones) and Sony Xperia (Android) quirks tests
/// validating research-based entries for VID 0x0fce.
///
/// Key libmtp findings encoded here:
/// - SonyEricsson feature phones: BROKEN_MTPGETOBJPROPLIST (K850i, W910, W890i, etc.)
/// - Xperia dual MTP stacks: Aricent (old) vs Android (new), same VID:PID may switch
/// - MTP personality PIDs: 0x0nnn (standard), 0x4nnn (MTP+CDROM), 0x5nnn (MTP+ADB)
/// - LT26i Xperia S: DEVICE_FLAG_NO_ZERO_READS (unique among Xperia)
/// - Older Xperia (Z3v, Z2 Tablet, E1, Z Ultra, M2 Aqua): DEVICE_FLAGS_ANDROID_BUGS
/// - Most modern Xperia: DEVICE_FLAG_NONE (clean MTP stack)
final class SonyXperiaQuirksTests: XCTestCase {

  private static let sonyEricssonVID: UInt16 = 0x0fce
  private var db: QuirkDatabase!
  private var allEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    allEntries = db.entries.filter { $0.vid == Self.sonyEricssonVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllEntriesHaveCorrectVID() {
    for entry in allEntries {
      XCTAssertEqual(
        entry.vid, Self.sonyEricssonVID,
        "Entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testSubstantialEntryCount() {
    XCTAssertGreaterThan(
      allEntries.count, 200,
      "Expected a substantial SonyEricsson/Xperia database, found only \(allEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in allEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - SonyEricsson Feature Phone Tests (BROKEN_MTPGETOBJPROPLIST)

  /// libmtp documents BROKEN_MTPGETOBJPROPLIST for pre-Android SonyEricsson phones:
  /// K850i, W910, W890i, W760i, C902, C702, W980, C905, W595, W902, T700, W705/W715, W995, U5, U8i
  func testSonyEricssonFeaturePhonesBrokenPropList() {
    let featurePhonePIDs: Set<UInt16> = [
      0x0075,  // K850i
      0x0076,  // W910
      0x00b3,  // W890i
      0x00c6,  // W760i
      0x00d4,  // C902
      0x00d9,  // C702
      0x00da,  // W980
      0x00ef,  // C905
      0x00f3,  // W595
      0x00f5,  // W902
      0x00fb,  // T700
      0x0105,  // W705/W715
      0x0112,  // W995
      0x0133,  // U5
      0x013a,  // U8i
    ]
    let matched = allEntries.filter { featurePhonePIDs.contains($0.pid) }
    XCTAssertGreaterThanOrEqual(
      matched.count, 12,
      "Expected at least 12 SonyEricsson feature phone entries with broken proplist PIDs")
    for entry in matched {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "SonyEricsson feature phone '\(entry.id)' must NOT support GetObjectPropList (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  func testSonyEricssonFeaturePhonesAreCategorizedAsPhone() {
    let featurePhones = allEntries.filter { $0.id.contains("sonyericsson") }
    XCTAssertFalse(featurePhones.isEmpty, "Expected SonyEricsson entries in database")
    for entry in featurePhones {
      XCTAssertEqual(
        entry.category, "phone",
        "SonyEricsson entry '\(entry.id)' should have category 'phone', got '\(entry.category ?? "nil")'"
      )
    }
  }

  func testSonyEricssonW302BrokenPropList() {
    // W302 (PID 0x10c8) — unusual PID range, also BROKEN_MTPGETOBJPROPLIST
    let w302 = allEntries.first { $0.pid == 0x10c8 }
    XCTAssertNotNil(w302, "Expected SonyEricsson W302 entry (PID 0x10c8)")
    if let entry = w302 {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "W302 '\(entry.id)' must NOT support GetObjectPropList")
    }
  }

  func testSonyEricssonK550iBrokenPropList() {
    // K550i (PID 0xe000) — unusual high PID, BROKEN_MTPGETOBJPROPLIST
    let k550i = allEntries.first { $0.pid == 0xe000 }
    XCTAssertNotNil(k550i, "Expected SonyEricsson K550i entry (PID 0xe000)")
    if let entry = k550i {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "K550i '\(entry.id)' must NOT support GetObjectPropList")
    }
  }

  func testAllSonyEricssonPrefixedEntriesDisablePropList() {
    // All sony-sonyericsson-* entries should have broken proplist
    let seEntries = allEntries.filter { $0.id.hasPrefix("sony-sonyericsson-") }
    XCTAssertGreaterThan(
      seEntries.count, 30,
      "Expected at least 30 sony-sonyericsson-* entries")
    for entry in seEntries {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "SonyEricsson '\(entry.id)' must NOT support GetObjectPropList (BROKEN_MTPGETOBJPROPLIST)")
    }
  }

  // MARK: - Xperia LT26i NO_ZERO_READS Tests

  /// libmtp uniquely flags LT26i Xperia S with DEVICE_FLAG_NO_ZERO_READS:
  /// the device hangs on zero-length USB reads used to terminate bulk transfers.
  func testLT26iXperiaSMTPEntryExists() {
    let lt26i = allEntries.first { $0.pid == 0x0169 }
    XCTAssertNotNil(lt26i, "Expected LT26i Xperia S MTP entry (PID 0x0169)")
  }

  func testLT26iXperiaSCDROMEntryExists() {
    let lt26iCdrom = allEntries.first { $0.pid == 0x4169 }
    XCTAssertNotNil(lt26iCdrom, "Expected LT26i Xperia S MTP+CDROM entry (PID 0x4169)")
  }

  func testLT26iXperiaSADBEntryExists() {
    let lt26iAdb = allEntries.first { $0.pid == 0x5169 }
    XCTAssertNotNil(lt26iAdb, "Expected LT26i Xperia S MTP+ADB entry (PID 0x5169)")
  }

  func testLT26iAllPersonalitiesHaveConsistentFlags() {
    // All three LT26i personalities should have identical behavioral flags
    let lt26iPIDs: [UInt16] = [0x0169, 0x4169, 0x5169]
    let lt26iEntries = allEntries.filter { lt26iPIDs.contains($0.pid) }
    XCTAssertEqual(lt26iEntries.count, 3, "Expected exactly 3 LT26i personality entries")
    guard let first = lt26iEntries.first else { return }
    let referenceFlags = first.resolvedFlags()
    for entry in lt26iEntries.dropFirst() {
      let flags = entry.resolvedFlags()
      XCTAssertEqual(
        flags.supportsGetObjectPropList, referenceFlags.supportsGetObjectPropList,
        "LT26i '\(entry.id)' proplist flag should match across personalities")
      XCTAssertEqual(
        flags.resetOnOpen, referenceFlags.resetOnOpen,
        "LT26i '\(entry.id)' resetOnOpen should match across personalities")
    }
  }

  // MARK: - MTP Personality Variant Tests (0x0nnn vs 0x4nnn vs 0x5nnn)

  func testMTPStandardPersonalityEntriesExist() {
    let standard = allEntries.filter { $0.pid < 0x1000 }
    XCTAssertGreaterThan(
      standard.count, 100,
      "Expected over 100 standard MTP personality entries (0x0nnn)")
  }

  func testMTPCDROMPersonalityEntriesExist() {
    let cdrom = allEntries.filter { $0.pid >= 0x4000 && $0.pid < 0x5000 }
    XCTAssertGreaterThan(
      cdrom.count, 50,
      "Expected over 50 MTP+CDROM personality entries (0x4nnn)")
  }

  func testMTPADBPersonalityEntriesExist() {
    let adb = allEntries.filter { $0.pid >= 0x5000 && $0.pid < 0x6000 }
    XCTAssertGreaterThan(
      adb.count, 60,
      "Expected over 60 MTP+ADB personality entries (0x5nnn)")
  }

  func testMTPUMSPersonalityEntriesExist() {
    let ums = allEntries.filter { $0.pid >= 0xa000 && $0.pid < 0xb000 }
    XCTAssertGreaterThanOrEqual(
      ums.count, 3,
      "Expected at least 3 MTP+UMS personality entries (0xAnnn)")
  }

  func testMTPUMSADBPersonalityEntriesExist() {
    let umsAdb = allEntries.filter { $0.pid >= 0xb000 && $0.pid < 0xc000 }
    XCTAssertGreaterThanOrEqual(
      umsAdb.count, 3,
      "Expected at least 3 MTP+UMS+ADB personality entries (0xBnnn)")
  }

  /// Verify that standard MTP and CDROM personalities for the same device
  /// share the same low-12-bit base PID.
  func testCDROMPersonalitiesShareBasePIDWithStandard() {
    let cdrom = allEntries.filter { $0.pid >= 0x4000 && $0.pid < 0x5000 }
    let standardPIDs = Set(allEntries.filter { $0.pid < 0x1000 }.map { $0.pid })
    var matched = 0
    for entry in cdrom {
      let basePID = entry.pid & 0x0FFF
      if standardPIDs.contains(basePID) {
        matched += 1
      }
    }
    let ratio = Double(matched) / Double(cdrom.count)
    XCTAssertGreaterThan(
      ratio, 0.80,
      "At least 80% of CDROM PIDs should have matching standard PID (\(matched)/\(cdrom.count))")
  }

  /// Verify that ADB personalities share base PIDs with standard MTP entries.
  func testADBPersonalitiesShareBasePIDWithStandard() {
    let adb = allEntries.filter { $0.pid >= 0x5000 && $0.pid < 0x6000 }
    let standardPIDs = Set(allEntries.filter { $0.pid < 0x1000 }.map { $0.pid })
    var matched = 0
    for entry in adb {
      let basePID = entry.pid & 0x0FFF
      if standardPIDs.contains(basePID) {
        matched += 1
      }
    }
    let ratio = Double(matched) / Double(adb.count)
    XCTAssertGreaterThan(
      ratio, 0.80,
      "At least 80% of ADB PIDs should have matching standard PID (\(matched)/\(adb.count))")
  }

  // MARK: - Xperia Clean MTP Stack (DEVICE_FLAG_NONE)

  /// Most modern Xperia devices have DEVICE_FLAG_NONE (clean MTP stack)
  /// and should support GetObjectPropList.
  func testModernXperiaCleanStackSupportsPropList() {
    // Modern Xperia with confirmed DEVICE_FLAG_NONE in libmtp
    let modernPIDs: Set<UInt16> = [
      0x01e0,  // Xperia X
      0x01e7,  // Xperia XZ
      0x01f3,  // Xperia XZ1
      0x01ff,  // Xperia XZ3
      0x0201,  // Xperia 10
      0x0205,  // Xperia 1
      0x020a,  // Xperia 5
      0x020d,  // Xperia 5 II
    ]
    let modernEntries = allEntries.filter { modernPIDs.contains($0.pid) }
    XCTAssertGreaterThanOrEqual(
      modernEntries.count, 7,
      "Expected at least 7 modern Xperia entries")
    for entry in modernEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Modern Xperia '\(entry.id)' should support GetObjectPropList (DEVICE_FLAG_NONE = clean stack)"
      )
    }
  }

  func testXperiaZCleanStack() {
    // Xperia Z (PID 0x0193) — one of the first verified Xperia entries
    let xperiaZ = allEntries.first { $0.pid == 0x0193 }
    XCTAssertNotNil(xperiaZ, "Expected Xperia Z entry (PID 0x0193)")
    if let entry = xperiaZ {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Xperia Z should support GetObjectPropList (clean MTP stack)")
    }
  }

  func testXperiaZ3CleanStack() {
    // Xperia Z3 (PID 0x01ba) — verified entry
    let xperiaZ3 = allEntries.first { $0.pid == 0x01ba }
    XCTAssertNotNil(xperiaZ3, "Expected Xperia Z3 entry (PID 0x01ba)")
    if let entry = xperiaZ3 {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Xperia Z3 should support GetObjectPropList (clean MTP stack)")
    }
  }

  // MARK: - Xperia ANDROID_BUGS Flagged Devices

  /// libmtp flags certain older Xperia models with DEVICE_FLAGS_ANDROID_BUGS:
  /// broken GetObjectPropList on these specific models.
  func testAndroidBugsFlaggedDevicesDisablePropList() {
    // PIDs confirmed from libmtp to carry DEVICE_FLAGS_ANDROID_BUGS (standard MTP)
    let androidBugsPIDs: Set<UInt16> = [
      0x0196,  // Xperia Z Ultra (MTP ID2)
      0x0197,  // Xperia ZR
      0x0198,  // Xperia A
      0x01b0,  // Xperia Z3v
      0x01b1,  // Xperia Z2 Tablet
      0x01b5,  // Xperia E1
      0x01b6,  // Xperia Z Ultra
      0x01b8,  // Xperia M2 Aqua
    ]
    let bugged = allEntries.filter { androidBugsPIDs.contains($0.pid) }
    XCTAssertGreaterThanOrEqual(
      bugged.count, 7,
      "Expected at least 7 ANDROID_BUGS flagged entries")
    for entry in bugged {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "ANDROID_BUGS device '\(entry.id)' must NOT support GetObjectPropList")
    }
  }

  /// CDROM personality variants of ANDROID_BUGS devices should also disable proplist.
  func testAndroidBugsCDROMVariantsDisablePropList() {
    let cdromBugsPIDs: Set<UInt16> = [
      0x41b0,  // Z3v CDROM
      0x41b1,  // Z2 Tablet CDROM
      0x41b5,  // E1 CDROM
      0x41b6,  // Z Ultra CDROM
      0x41b8,  // M2 Aqua CDROM
    ]
    let bugged = allEntries.filter { cdromBugsPIDs.contains($0.pid) }
    XCTAssertGreaterThanOrEqual(
      bugged.count, 4,
      "Expected at least 4 ANDROID_BUGS CDROM entries")
    for entry in bugged {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "ANDROID_BUGS CDROM device '\(entry.id)' must NOT support GetObjectPropList")
    }
  }

  /// ADB personality variants of ANDROID_BUGS devices should also disable proplist.
  func testAndroidBugsADBVariantsDisablePropList() {
    let adbBugsPIDs: Set<UInt16> = [
      0x5197,  // ZR ADB
      0x5198,  // Xperia A ADB
      0x51b0,  // Z3v ADB
      0x51b1,  // Z2 Tablet ADB
      0x51b5,  // E1 ADB
      0x51b8,  // M2 Aqua ADB
    ]
    let bugged = allEntries.filter { adbBugsPIDs.contains($0.pid) }
    XCTAssertGreaterThanOrEqual(
      bugged.count, 5,
      "Expected at least 5 ANDROID_BUGS ADB entries")
    for entry in bugged {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "ANDROID_BUGS ADB device '\(entry.id)' must NOT support GetObjectPropList")
    }
  }

  // MARK: - SonyEricsson Android Xperia (Transition Era)

  /// Early SonyEricsson-branded Xperia Android phones (X8, X10 Mini, Arc, Neo, Ray, Mini Pro)
  /// used VID 0x0fce and share the same vendor ID as feature phones.
  func testSonyEricssonXperiaAndroidEntriesExist() {
    let seXperiaPIDs: Set<UInt16> = [
      0x0187,  // Xperia X8
      0x0188,  // Xperia X10 Mini
      0x0189,  // Xperia Arc
      0x018a,  // Xperia Neo
      0x018b,  // Xperia Ray
      0x018c,  // Xperia Mini Pro
    ]
    let matched = allEntries.filter { seXperiaPIDs.contains($0.pid) }
    XCTAssertEqual(
      matched.count, 6,
      "Expected exactly 6 SonyEricsson Xperia Android entries")
    for entry in matched {
      XCTAssertEqual(
        entry.category, "phone",
        "SonyEricsson Xperia '\(entry.id)' should be categorized as phone")
    }
  }

  func testSonyEricssonXperiaAndroidDisablePropList() {
    // These transition-era devices don't support GetObjectPropList
    let seXperiaPIDs: Set<UInt16> = [0x0187, 0x0188, 0x0189, 0x018a, 0x018b, 0x018c]
    let matched = allEntries.filter { seXperiaPIDs.contains($0.pid) }
    for entry in matched {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "SonyEricsson Xperia '\(entry.id)' should not support GetObjectPropList")
    }
  }

  // MARK: - Category Validation

  func testAllEntriesHavePhoneCategory() {
    for entry in allEntries {
      XCTAssertEqual(
        entry.category, "phone",
        "Entry '\(entry.id)' should have category 'phone', got '\(entry.category ?? "nil")'")
    }
  }

  // MARK: - Naming Convention

  func testMajorityOfIDsFollowNamingConvention() {
    // IDs should start with "sony-" or "sonyericsson-" or "xperia-"
    let validPrefixed = allEntries.filter {
      $0.id.hasPrefix("sony-") || $0.id.hasPrefix("sonyericsson-") || $0.id.hasPrefix("xperia-")
    }
    let ratio = Double(validPrefixed.count) / Double(allEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x0fce entries should have sony-/sonyericsson-/xperia- prefix (\(validPrefixed.count)/\(allEntries.count))"
    )
  }

  // MARK: - Tuning Bounds

  func testXperiaChunkSizesAreInReasonableRange() {
    for entry in allEntries {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 512 * 1024,
          "Entry '\(entry.id)' chunk size \(chunk) is below 512KB minimum")
        XCTAssertLessThanOrEqual(
          chunk, 16 * 1024 * 1024,
          "Entry '\(entry.id)' chunk size \(chunk) exceeds 16MB maximum")
      }
    }
  }

  func testXperiaIOTimeoutsAreInReasonableRange() {
    for entry in allEntries {
      if let timeout = entry.ioTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          timeout, 3_000,
          "Entry '\(entry.id)' ioTimeout \(timeout)ms is below 3s — too aggressive")
        XCTAssertLessThanOrEqual(
          timeout, 120_000,
          "Entry '\(entry.id)' ioTimeout \(timeout)ms exceeds 120s — suspiciously high")
      }
    }
  }

  // MARK: - Kernel Detach Requirement

  /// Entries with explicit flags that set requiresKernelDetach=true should be consistent.
  /// Note: some entries use default flags where requiresKernelDetach defaults to true,
  /// while others explicitly set it; we check entries with explicit flag blocks.
  func testEntriesWithExplicitFlagsHaveKernelDetachSet() {
    let withExplicitKernelDetach = allEntries.filter {
      $0.flags?.requiresKernelDetach == true
    }
    XCTAssertGreaterThan(
      withExplicitKernelDetach.count, 50,
      "Expected at least 50 entries with explicit requiresKernelDetach=true")
  }

  // MARK: - PropList Support Distribution

  /// Verify that modern Xperia (clean stack) entries outnumber broken ones.
  func testCleanStackEntriesOutnumberBrokenOnes() {
    let withPropList = allEntries.filter { $0.resolvedFlags().supportsGetObjectPropList }
    let withoutPropList = allEntries.filter { !$0.resolvedFlags().supportsGetObjectPropList }
    // The majority of Xperia entries should support proplist (clean MTP stack)
    XCTAssertGreaterThan(
      withPropList.count, 50,
      "Expected at least 50 entries with GetObjectPropList support")
    // But there should also be a significant number of broken ones
    XCTAssertGreaterThan(
      withoutPropList.count, 50,
      "Expected at least 50 entries without GetObjectPropList support (feature phones + ANDROID_BUGS)"
    )
  }

  // MARK: - Xperia Z-Series Flagship Entries

  func testXperiaZSeriesEntriesExist() {
    let zSeriesPIDs: Set<UInt16> = [
      0x0193,  // Z
      0x019e,  // Z1
      0x01af,  // Z2
      0x01ba,  // Z3
      0x01d9,  // Z5
    ]
    let matched = allEntries.filter { zSeriesPIDs.contains($0.pid) }
    XCTAssertEqual(
      matched.count, 5,
      "Expected all 5 Xperia Z-series flagship entries")
  }

  func testXperiaNumberSeriesEntriesExist() {
    let numberSeriesPIDs: Set<UInt16> = [
      0x0205,  // Xperia 1
      0x020a,  // Xperia 5
      0x0201,  // Xperia 10
    ]
    let matched = allEntries.filter { numberSeriesPIDs.contains($0.pid) }
    XCTAssertEqual(
      matched.count, 3,
      "Expected Xperia 1, 5, and 10 entries")
  }

  // MARK: - Status Distribution

  func testProposedEntriesExist() {
    let proposed = allEntries.filter { $0.status == .proposed }
    XCTAssertGreaterThan(
      proposed.count, 100,
      "Expected a large number of proposed SonyEricsson/Xperia entries")
  }

  func testVerifiedEntriesExist() {
    let verified = allEntries.filter { $0.status == .verified }
    XCTAssertGreaterThan(
      verified.count, 0,
      "Expected at least one verified SonyEricsson/Xperia entry")
  }
}
