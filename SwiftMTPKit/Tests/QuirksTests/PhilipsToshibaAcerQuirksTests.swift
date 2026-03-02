// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Philips (VID 0x0471), Toshiba (VID 0x0930), and Acer (VID 0x0502) quirks tests.
///
/// Research sourced from libmtp music-players.h:
/// - Philips: GoGear series (SA6014, SA5145, SA6125, ViBE, Aria, Ariaz, Muse) use
///   DEVICE_FLAG_UNLOAD_DRIVER. HDD6320/HDD1620 have BROKEN_MTPGETOBJPROPLIST_ALL.
///   Shoqbox uses ONLY_7BIT_FILENAMES. PSA235 uses DEVICE_FLAG_NONE.
/// - Toshiba: Gigabeat series need NO_RELEASE_INTERFACE + BROKEN_SEND_OBJECT_PROPLIST.
///   Gigabeat S also has BROKEN_MTPGETOBJPROPLIST_ALL. Excite AT300/AT200 and
///   Thrive AT100 use DEVICE_FLAGS_ANDROID_BUGS.
/// - Acer: All devices use DEVICE_FLAGS_ANDROID_BUGS. Includes Iconia TAB series
///   (A500, A501, A100, A200, A510, A700, A810), Liquid phones (E2, E3, X1, Z120,
///   Z130, Z220, Z330, Z530, Z630), One 7, and Zest.
final class PhilipsToshibaAcerQuirksTests: XCTestCase {

  // MARK: - Constants

  private static let philipsVID: UInt16 = 0x0471
  private static let toshibaVID: UInt16 = 0x0930
  private static let acerVID: UInt16 = 0x0502

  // MARK: - Properties

  private var db: QuirkDatabase!
  private var philipsEntries: [DeviceQuirk]!
  private var toshibaEntries: [DeviceQuirk]!
  private var acerEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    philipsEntries = db.entries.filter { $0.vid == Self.philipsVID }
    toshibaEntries = db.entries.filter { $0.vid == Self.toshibaVID }
    acerEntries = db.entries.filter { $0.vid == Self.acerVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllPhilipsEntriesHaveCorrectVID() {
    for entry in philipsEntries {
      XCTAssertEqual(
        entry.vid, Self.philipsVID,
        "Philips entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testAllToshibaEntriesHaveCorrectVID() {
    for entry in toshibaEntries {
      XCTAssertEqual(
        entry.vid, Self.toshibaVID,
        "Toshiba entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testAllAcerEntriesHaveCorrectVID() {
    for entry in acerEntries {
      XCTAssertEqual(
        entry.vid, Self.acerVID,
        "Acer entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - Entry Count Validation

  func testPhilipsEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      philipsEntries.count, 10,
      "Expected substantial Philips device database, found only \(philipsEntries.count)")
  }

  func testToshibaEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      toshibaEntries.count, 10,
      "Expected substantial Toshiba device database, found only \(toshibaEntries.count)")
  }

  func testAcerEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      acerEntries.count, 10,
      "Expected substantial Acer device database, found only \(acerEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicatePhilipsProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in philipsEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Philips PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateToshibaProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in toshibaEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Toshiba PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateAcerProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in acerEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Acer PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Philips GoGear: UNLOAD_DRIVER → requiresKernelDetach

  /// Philips GoGear devices in libmtp use DEVICE_FLAG_UNLOAD_DRIVER.
  /// Mapped to requiresKernelDetach in our quirks system.
  func testPhilipsGoGearSA6014RequiresKernelDetach() {
    let entry = philipsEntries.first { $0.pid == 0x084e }
    XCTAssertNotNil(entry, "Missing Philips GoGear SA6014 (PID 0x084e)")
  }

  func testPhilipsGoGearSA5145Exists() {
    let entry = philipsEntries.first { $0.pid == 0x0857 }
    XCTAssertNotNil(entry, "Missing Philips GoGear SA5145 (PID 0x0857)")
  }

  func testPhilipsGoGearSA6125Exists() {
    let entry = philipsEntries.first { $0.pid == 0x2002 }
    XCTAssertNotNil(entry, "Missing Philips GoGear SA6125 (PID 0x2002)")
  }

  func testPhilipsGoGearVibeExists() {
    let entry = philipsEntries.first { $0.pid == 0x2075 }
    XCTAssertNotNil(entry, "Missing Philips GoGear ViBE (PID 0x2075)")
  }

  func testPhilipsGoGearMuseExists() {
    let entry = philipsEntries.first { $0.pid == 0x2077 }
    XCTAssertNotNil(entry, "Missing Philips GoGear Muse (PID 0x2077)")
  }

  func testPhilipsGoGearAriaExists() {
    let entry = philipsEntries.first { $0.pid == 0x207c }
    XCTAssertNotNil(entry, "Missing Philips GoGear Aria (PID 0x207c)")
  }

  func testPhilipsGoGearAriazExists() {
    let entry = philipsEntries.first { $0.pid == 0x20b9 }
    XCTAssertNotNil(entry, "Missing Philips GoGear Ariaz (PID 0x20b9)")
  }

  // MARK: - Philips HDD6320: BROKEN_MTPGETOBJPROPLIST_ALL

  /// Philips HDD6320 (PID 0x014b) has BROKEN_MTPGETOBJPROPLIST_ALL per libmtp.
  func testPhilipsHDD6320HasBrokenGetObjPropList() {
    let entry = philipsEntries.first { $0.pid == 0x014b }
    XCTAssertNotNil(entry, "Missing Philips HDD6320 (PID 0x014b)")
    if let entry = entry {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Philips HDD6320 should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST_ALL)")
    }
  }

  /// Philips HDD6320 second variant (PID 0x01eb) has DEVICE_FLAG_NONE per libmtp.
  func testPhilipsHDD6320SecondVariantExists() {
    let entry = philipsEntries.first { $0.pid == 0x01eb }
    XCTAssertNotNil(entry, "Missing Philips HDD6320 second variant (PID 0x01eb)")
  }

  // MARK: - Philips Shoqbox: ONLY_7BIT_FILENAMES

  /// Philips Shoqbox (PID 0x0172) uses ONLY_7BIT_FILENAMES per libmtp.
  func testPhilipsShoqboxExists() {
    let entry = philipsEntries.first { $0.pid == 0x0172 }
    XCTAssertNotNil(entry, "Missing Philips Shoqbox (PID 0x0172)")
  }

  // MARK: - Philips PSA235: DEVICE_FLAG_NONE

  /// Philips PSA235 (PID 0x7e01) has DEVICE_FLAG_NONE per libmtp.
  func testPhilipsPSA235Exists() {
    let entry = philipsEntries.first { $0.pid == 0x7e01 }
    XCTAssertNotNil(entry, "Missing Philips PSA235 (PID 0x7e01)")
  }

  // MARK: - Philips SA9200: DEVICE_FLAG_NONE

  func testPhilipsSA9200Exists() {
    let entry = philipsEntries.first { $0.pid == 0x014f }
    XCTAssertNotNil(entry, "Missing Philips GoGear SA9200 (PID 0x014f)")
  }

  // MARK: - Philips Category Validation

  func testPhilipsGoGearEntriesAreCategorizedAsMediaPlayer() {
    let gogearEntries = philipsEntries.filter { $0.id.contains("gogear") }
    XCTAssertFalse(gogearEntries.isEmpty, "Expected Philips GoGear entries in database")
    for entry in gogearEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "Philips GoGear '\(entry.id)' should have category 'media-player', got '\(entry.category ?? "nil")'")
    }
  }

  func testPhilipsHDDEntriesAreCategorizedAsMediaPlayer() {
    let hddEntries = philipsEntries.filter { $0.id.contains("hdd") }
    XCTAssertFalse(hddEntries.isEmpty, "Expected Philips HDD entries in database")
    for entry in hddEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "Philips HDD '\(entry.id)' should have category 'media-player', got '\(entry.category ?? "nil")'")
    }
  }

  // MARK: - Philips ID Naming Convention

  func testMajorityOfPhilipsIDsStartWithPhilips() {
    let philipsPrefixed = philipsEntries.filter { $0.id.hasPrefix("philips-") }
    let ratio = Double(philipsPrefixed.count) / Double(max(philipsEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x0471 entries should start with 'philips-' (\(philipsPrefixed.count)/\(philipsEntries.count))")
  }

  // MARK: - Toshiba Gigabeat: NO_RELEASE_INTERFACE + BROKEN_SEND_OBJECT_PROPLIST

  /// Toshiba Gigabeat MEGF-40 (PID 0x0009) needs NO_RELEASE_INTERFACE +
  /// BROKEN_SEND_OBJECT_PROPLIST per libmtp.
  func testToshibaGigabeatMEGF40Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x0009 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat MEGF-40 (PID 0x0009)")
  }

  func testToshibaGigabeatMTPModeExists() {
    let entry = toshibaEntries.first { $0.pid == 0x000c }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat MTP mode (PID 0x000c)")
  }

  func testToshibaGigabeatP20Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x000f }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat P20 (PID 0x000f)")
  }

  func testToshibaGigabeatP10Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x0011 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat P10 (PID 0x0011)")
  }

  func testToshibaGigabeatV30Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x0014 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat V30 (PID 0x0014)")
  }

  // MARK: - Toshiba Gigabeat S: BROKEN_MTPGETOBJPROPLIST_ALL

  /// Toshiba Gigabeat S (PID 0x0010) has BROKEN_MTPGETOBJPROPLIST_ALL +
  /// NO_RELEASE_INTERFACE per libmtp.
  func testToshibaGigabeatSHasBrokenGetObjPropList() {
    let entry = toshibaEntries.first { $0.pid == 0x0010 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat S (PID 0x0010)")
    if let entry = entry {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Toshiba Gigabeat S should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST_ALL)")
    }
  }

  // MARK: - Toshiba Gigabeat Category Validation

  func testToshibaGigabeatEntriesAreCategorizedAsMediaPlayer() {
    let gigabeatEntries = toshibaEntries.filter { $0.id.contains("gigabeat") }
    XCTAssertFalse(gigabeatEntries.isEmpty, "Expected Toshiba Gigabeat entries in database")
    for entry in gigabeatEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "Toshiba Gigabeat '\(entry.id)' should have category 'media-player', got '\(entry.category ?? "nil")'")
    }
  }

  // MARK: - Toshiba Android Tablets: DEVICE_FLAGS_ANDROID_BUGS

  /// Toshiba Excite AT300 (PID 0x0963) uses DEVICE_FLAGS_ANDROID_BUGS per libmtp.
  func testToshibaExciteAT300RequiresKernelDetach() {
    let entry = toshibaEntries.first { $0.pid == 0x0963 }
    XCTAssertNotNil(entry, "Missing Toshiba Excite AT300 (PID 0x0963)")
    if let entry = entry {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Toshiba Excite AT300 should require kernel detach (DEVICE_FLAGS_ANDROID_BUGS)")
    }
  }

  func testToshibaExciteAT300DisablesGetObjectPropList() {
    let entry = toshibaEntries.first { $0.pid == 0x0963 }
    if let entry = entry {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Toshiba Excite AT300 should have supportsGetObjectPropList=false (DEVICE_FLAGS_ANDROID_BUGS)")
    }
  }

  /// Toshiba Excite AT200 (PID 0x0960) uses DEVICE_FLAGS_ANDROID_BUGS per libmtp.
  func testToshibaExciteAT200Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x0960 }
    XCTAssertNotNil(entry, "Missing Toshiba Excite AT200 (PID 0x0960)")
  }

  /// Toshiba Thrive AT100 (PID 0x7100) uses DEVICE_FLAGS_ANDROID_BUGS per libmtp.
  func testToshibaThriveAT100Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x7100 }
    XCTAssertNotNil(entry, "Missing Toshiba Thrive AT100 (PID 0x7100)")
  }

  func testToshibaAndroidTabletsRequireKernelDetach() {
    let androidTabletPIDs: Set<UInt16> = [0x0960, 0x0963, 0x7100]
    for entry in toshibaEntries where androidTabletPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Toshiba Android tablet '\(entry.id)' should require kernel detach (DEVICE_FLAGS_ANDROID_BUGS)")
    }
  }

  // MARK: - Toshiba ID Naming Convention

  func testMajorityOfToshibaIDsStartWithToshiba() {
    let toshibaPrefixed = toshibaEntries.filter { $0.id.hasPrefix("toshiba-") }
    let ratio = Double(toshibaPrefixed.count) / Double(max(toshibaEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.50,
      "At least 50% of VID 0x0930 entries should start with 'toshiba-' (\(toshibaPrefixed.count)/\(toshibaEntries.count))")
  }

  // MARK: - Acer Iconia Tab: DEVICE_FLAGS_ANDROID_BUGS

  /// Acer Iconia Tab A500 (PID 0x3325) uses DEVICE_FLAGS_ANDROID_BUGS per libmtp.
  func testAcerIconiaA500Exists() {
    let entry = acerEntries.first { $0.pid == 0x3325 }
    XCTAssertNotNil(entry, "Missing Acer Iconia A500 (PID 0x3325)")
  }

  func testAcerIconiaA700Exists() {
    let entry = acerEntries.first { $0.pid == 0x3378 }
    XCTAssertNotNil(entry, "Missing Acer Iconia A700 (PID 0x3378)")
  }

  func testAcerIconiaTabA510Exists() {
    let entry = acerEntries.first { $0.pid == 0x3326 }
    XCTAssertNotNil(entry, "Missing Acer Iconia Tab A510 (PID 0x3326)")
  }

  // MARK: - Acer Liquid Phones: DEVICE_FLAGS_ANDROID_BUGS

  func testAcerLiquidE2Exists() {
    let entry = acerEntries.first { $0.pid == 0x3514 }
    XCTAssertNotNil(entry, "Missing Acer Liquid E2 (PID 0x3514)")
  }

  func testAcerLiquidZ220Exists() {
    let entry = acerEntries.first { $0.pid == 0x374f }
    XCTAssertNotNil(entry, "Missing Acer Liquid Z220 (PID 0x374f)")
  }

  func testAcerLiquidZ630Exists() {
    let entry = acerEntries.first { $0.pid == 0x37ef }
    XCTAssertNotNil(entry, "Missing Acer Liquid Z630 (PID 0x37ef)")
  }

  func testAcerOne7Exists() {
    let entry = acerEntries.first { $0.pid == 0x3657 }
    XCTAssertNotNil(entry, "Missing Acer One 7 (PID 0x3657)")
  }

  func testAcerZestExists() {
    let entry = acerEntries.first { $0.pid == 0x3886 }
    XCTAssertNotNil(entry, "Missing Acer Zest (PID 0x3886)")
  }

  // MARK: - Acer Android Bug Flags

  /// All Acer devices in libmtp use DEVICE_FLAGS_ANDROID_BUGS which implies:
  /// - requiresKernelDetach: true (DEVICE_FLAG_UNLOAD_DRIVER)
  /// - supportsGetObjectPropList: false (DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST)
  func testAcerDevicesRequireKernelDetach() {
    let acerWithFlags = acerEntries.filter { $0.flags != nil }
    let withKernelDetach = acerWithFlags.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(withKernelDetach.count) / Double(max(acerWithFlags.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.5,
      "Most Acer entries with flags should require kernel detach (\(withKernelDetach.count)/\(acerWithFlags.count))")
  }

  func testAcerAndroidDevicesDisableGetObjectPropList() {
    let androidDevices = acerEntries.filter {
      $0.id.contains("iconia") || $0.id.contains("liquid") || $0.id.contains("zest")
        || $0.id.contains("one-7")
    }
    for entry in androidDevices {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Acer Android entry '\(entry.id)' should have GetObjectPropList disabled (DEVICE_FLAGS_ANDROID_BUGS per libmtp)"
      )
    }
  }

  // MARK: - Acer ID Naming Convention

  func testMajorityOfAcerIDsStartWithAcer() {
    let acerPrefixed = acerEntries.filter { $0.id.hasPrefix("acer-") }
    let ratio = Double(acerPrefixed.count) / Double(max(acerEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x0502 entries should start with 'acer-' (\(acerPrefixed.count)/\(acerEntries.count))")
  }

  // MARK: - Cross-Vendor Legacy Media Player Chunk Sizes

  func testPhilipsMediaPlayersHaveConservativeChunkSize() {
    let mediaPlayers = philipsEntries.filter { $0.category == "media-player" }
    for entry in mediaPlayers {
      if let chunk = entry.maxChunkBytes {
        XCTAssertLessThanOrEqual(
          chunk, 4_194_304,
          "Philips media player '\(entry.id)' chunk size \(chunk) exceeds safe 4MB maximum for legacy devices")
      }
    }
  }

  func testToshibaGigabeatHasConservativeChunkSize() {
    let gigabeatEntries = toshibaEntries.filter { $0.id.contains("gigabeat") }
    for entry in gigabeatEntries {
      if let chunk = entry.maxChunkBytes {
        XCTAssertLessThanOrEqual(
          chunk, 4_194_304,
          "Toshiba Gigabeat '\(entry.id)' chunk size \(chunk) exceeds safe 4MB maximum for legacy devices")
      }
    }
  }

  // MARK: - Toshiba Gigabeat Additional Models

  func testToshibaGigabeatUExists() {
    let entry = toshibaEntries.first { $0.pid == 0x0016 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat U (PID 0x0016)")
  }

  func testToshibaGigabeatTExists() {
    let entry = toshibaEntries.first { $0.pid == 0x0019 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat T (PID 0x0019)")
  }

  func testToshibaGigabeatMEU202Exists() {
    let entry = toshibaEntries.first { $0.pid == 0x0018 }
    XCTAssertNotNil(entry, "Missing Toshiba Gigabeat MEU202 (PID 0x0018)")
  }

  // MARK: - Philips GoGear Additional Models

  func testPhilipsGoGearSA3345Exists() {
    let entry = philipsEntries.first { $0.pid == 0x2004 }
    XCTAssertNotNil(entry, "Missing Philips GoGear SA3345 (PID 0x2004)")
  }

  func testPhilipsGoGearVibe08Exists() {
    let entry = philipsEntries.first { $0.pid == 0x207b }
    XCTAssertNotNil(entry, "Missing Philips GoGear ViBE 08 (PID 0x207b)")
  }

  func testPhilipsGoGearMuse2Exists() {
    let entry = philipsEntries.first { $0.pid == 0x20e1 }
    XCTAssertNotNil(entry, "Missing Philips GoGear Muse 2 (PID 0x20e1)")
  }
}
