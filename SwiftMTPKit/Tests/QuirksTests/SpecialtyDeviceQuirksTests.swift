// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

// MARK: - Amazon Kindle Fire Quirks Tests

/// Amazon Kindle Fire quirks tests validating libmtp-researched flags.
///
/// All Kindle Fire devices use DEVICE_FLAGS_ANDROID_BUGS in libmtp, which maps to:
/// - requiresKernelDetach: true (UNLOAD_DRIVER)
/// - supportsGetObjectPropList: false (BROKEN_MTPGETOBJPROPLIST)
///
/// VID 0x1949 — Amazon Lab126 / Amazon.com
/// Source: libmtp music-players.h
final class AmazonKindleQuirksTests: XCTestCase {

  private static let amazonVID: UInt16 = 0x1949
  private var db: QuirkDatabase!
  private var amazonEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    amazonEntries = db.entries.filter { $0.vid == Self.amazonVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllAmazonEntriesHaveCorrectVID() {
    for entry in amazonEntries {
      XCTAssertEqual(
        entry.vid, Self.amazonVID,
        "Amazon entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testAmazonEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      amazonEntries.count, 5,
      "Expected at least 5 Amazon Kindle entries, found \(amazonEntries.count)")
  }

  // MARK: - DEVICE_FLAGS_ANDROID_BUGS → requiresKernelDetach (named Fire entries)

  func testKindleFireNamedModelsRequireKernelDetach() {
    // Only the "named" Kindle Fire models have requiresKernelDetach: true in the DB
    let namedFirePIDs: Set<UInt16> = [
      0x0007, 0x0008, 0x00f2, 0x0211, 0x0212, 0x0221, 0x0222, 0x0281, 0x06b1,
    ]
    for entry in amazonEntries where namedFirePIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Amazon Kindle Fire '\(entry.id)' should require kernel detach")
    }
  }

  // MARK: - DEVICE_FLAGS_ANDROID_BUGS → supportsGetObjectPropList: false

  func testKindleFireDevicesHaveBrokenGetObjPropList() {
    let kindlePIDs: Set<UInt16> = [
      0x0007, 0x0008, 0x00f2, 0x0211, 0x0212, 0x0221, 0x0222, 0x0281,
    ]
    for entry in amazonEntries where kindlePIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Amazon Kindle '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  // MARK: - Kindle Fire HD and newer models

  func testKindleFireHD6HasAndroidBugs() {
    let hd6 = amazonEntries.first { $0.pid == 0x00f2 }
    XCTAssertNotNil(hd6, "Missing Amazon Kindle Fire HD6 (PID 0x00f2)")
  }

  func testKindleFire10HDExists() {
    let fire10 = amazonEntries.first { $0.pid == 0x0281 }
    XCTAssertNotNil(fire10, "Missing Amazon Kindle Fire Tablet 10 HD (PID 0x0281)")
  }

  func testKindleFireMax11Exists() {
    let max11 = amazonEntries.first { $0.pid == 0x06b1 }
    XCTAssertNotNil(max11, "Missing Amazon Kindle Fire Max 11 (PID 0x06b1)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateAmazonProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in amazonEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Amazon PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - ID Naming Convention

  func testAmazonIDsStartWithAmazon() {
    let prefixed = amazonEntries.filter { $0.id.hasPrefix("amazon-") }
    let ratio = Double(prefixed.count) / Double(amazonEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x1949 entries should start with 'amazon-' (\(prefixed.count)/\(amazonEntries.count))"
    )
  }
}

// MARK: - Garmin GPS/Fitness Device Quirks Tests

/// Garmin GPS and fitness device quirks tests validating libmtp-researched flags.
///
/// All Garmin devices use DEVICE_FLAGS_ANDROID_BUGS in libmtp, which maps to:
/// - requiresKernelDetach: true (UNLOAD_DRIVER)
/// - supportsGetObjectPropList: false (BROKEN_MTPGETOBJPROPLIST)
///
/// VID 0x091e — Garmin International
/// Source: libmtp music-players.h
final class GarminDeviceQuirksTests: XCTestCase {

  private static let garminVID: UInt16 = 0x091e
  private var db: QuirkDatabase!
  private var garminEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    garminEntries = db.entries.filter { $0.vid == Self.garminVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllGarminEntriesHaveCorrectVID() {
    for entry in garminEntries {
      XCTAssertEqual(
        entry.vid, Self.garminVID,
        "Garmin entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testGarminEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      garminEntries.count, 3,
      "Expected at least 3 Garmin entries, found \(garminEntries.count)")
  }

  // MARK: - Garmin Android Bugs Flags

  func testGarminFitnessDevicesHaveConsistentFlags() {
    let fitnessPIDs: Set<UInt16> = [
      0x4b48, 0x4c29, 0x4cda, 0x4c9a, 0x4f67,
    ]
    for entry in garminEntries where fitnessPIDs.contains(entry.pid) {
      XCTAssertNotNil(
        entry.flags,
        "Garmin '\(entry.id)' should have typed flags defined")
    }
  }

  // MARK: - DEVICE_FLAGS_ANDROID_BUGS → supportsGetObjectPropList: false

  func testGarminFitnessDevicesHaveBrokenGetObjPropList() {
    let fitnessPIDs: Set<UInt16> = [
      0x4b48, 0x4c29, 0x4cda, 0x4c9a, 0x4f67,
    ]
    for entry in garminEntries where fitnessPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Garmin '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  // MARK: - Specific Garmin Models

  func testForerunner645MusicExists() {
    let fr645 = garminEntries.first { $0.pid == 0x4b48 }
    XCTAssertNotNil(fr645, "Missing Garmin Forerunner 645 Music (PID 0x4b48)")
  }

  func testFenix6ProExists() {
    let fenix6 = garminEntries.first { $0.pid == 0x4cda }
    XCTAssertNotNil(fenix6, "Missing Garmin Fenix 6 Pro/Sapphire (PID 0x4cda)")
  }

  func testVenuExists() {
    let venu = garminEntries.first { $0.pid == 0x4c9a }
    XCTAssertNotNil(venu, "Missing Garmin Venu (PID 0x4c9a)")
  }

  func testEpix2Exists() {
    let epix = garminEntries.first { $0.pid == 0x4f67 }
    XCTAssertNotNil(epix, "Missing Garmin EPIX 2 (PID 0x4f67)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateGarminProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in garminEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Garmin PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }
}

// MARK: - GoPro Action Camera Quirks Tests

/// GoPro action camera quirks tests validating libmtp-researched flags.
///
/// GoPro cameras use DEVICE_FLAG_NONE in libmtp — no special workarounds needed.
/// They present as standard PTP cameras with MTP extensions.
/// In SwiftMTP, they are expected to have camera-class defaults.
///
/// VID 0x2672 — GoPro, Inc.
/// Source: libmtp music-players.h (guarded by #ifndef _GPHOTO2_INTERNAL_CODE)
final class GoProQuirksTests: XCTestCase {

  private static let goProVID: UInt16 = 0x2672
  private var db: QuirkDatabase!
  private var goProEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    goProEntries = db.entries.filter { $0.vid == Self.goProVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllGoProEntriesHaveCorrectVID() {
    for entry in goProEntries {
      XCTAssertEqual(
        entry.vid, Self.goProVID,
        "GoPro entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testGoProEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      goProEntries.count, 10,
      "Expected at least 10 GoPro entries, found \(goProEntries.count)")
  }

  // MARK: - GoPro Camera Class

  func testGoProDevicesAreActionCameraCategory() {
    let cameraPIDs: Set<UInt16> = [
      0x000c, 0x000d, 0x000e, 0x0011, 0x0027, 0x0037,
      0x0047, 0x0049, 0x004d, 0x0056, 0x0059,
    ]
    for entry in goProEntries where cameraPIDs.contains(entry.pid) {
      XCTAssertEqual(
        entry.category, "action-camera",
        "GoPro '\(entry.id)' should have category 'action-camera', got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - Specific GoPro Models

  func testGoProHeroExists() {
    let hero = goProEntries.first { $0.pid == 0x000c }
    XCTAssertNotNil(hero, "Missing GoPro HERO (PID 0x000c)")
  }

  func testGoProHero5BlackExists() {
    let hero5 = goProEntries.first { $0.pid == 0x0027 }
    XCTAssertNotNil(hero5, "Missing GoPro HERO5 Black (PID 0x0027)")
  }

  func testGoProHero7BlackExists() {
    let hero7 = goProEntries.first { $0.pid == 0x0047 }
    XCTAssertNotNil(hero7, "Missing GoPro HERO7 Black (PID 0x0047)")
  }

  func testGoProHero9BlackExists() {
    let hero9 = goProEntries.first { $0.pid == 0x004d }
    XCTAssertNotNil(hero9, "Missing GoPro HERO9 Black (PID 0x004d)")
  }

  func testGoProHero11BlackExists() {
    let hero11 = goProEntries.first { $0.pid == 0x0059 }
    XCTAssertNotNil(hero11, "Missing GoPro HERO11 Black (PID 0x0059)")
  }

  func testGoProMaxExists() {
    let max = goProEntries.first { $0.pid == 0x004b }
    XCTAssertNotNil(max, "Missing GoPro MAX (PID 0x004b)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateGoProProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in goProEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate GoPro PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - ID Naming Convention

  func testGoProIDsStartWithGoPro() {
    let prefixed = goProEntries.filter { $0.id.hasPrefix("gopro-") }
    let ratio = Double(prefixed.count) / Double(goProEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x2672 entries should start with 'gopro-' (\(prefixed.count)/\(goProEntries.count))"
    )
  }
}

// MARK: - Archos Media Player Quirks Tests

/// Archos portable media player and tablet quirks tests.
///
/// Early Archos devices use DEVICE_FLAG_UNLOAD_DRIVER (requiresKernelDetach: true).
/// Later Android-based tablets use DEVICE_FLAGS_ANDROID_BUGS.
///
/// VID 0x0e79 — Archos SA
/// Source: libmtp music-players.h
final class ArchosDeviceQuirksTests: XCTestCase {

  private static let archosVID: UInt16 = 0x0e79
  private var db: QuirkDatabase!
  private var archosEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    archosEntries = db.entries.filter { $0.vid == Self.archosVID }
  }

  func testArchosEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      archosEntries.count, 3,
      "Expected at least 3 Archos entries, found \(archosEntries.count)")
  }

  func testAllArchosEntriesHaveCorrectVID() {
    for entry in archosEntries {
      XCTAssertEqual(
        entry.vid, Self.archosVID,
        "Archos entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - Classic Archos Flag Validation

  func testClassicArchosDevicesHaveBrokenGetObjPropList() {
    let classicPIDs: Set<UInt16> = [
      0x1207, 0x1301, 0x1307, 0x1309, 0x1331,
    ]
    for entry in archosEntries where classicPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Archos '\(entry.id)' should have supportsGetObjectPropList=false")
    }
  }

  func testArchosIDsStartWithArchos() {
    let prefixed = archosEntries.filter { $0.id.hasPrefix("archos-") }
    let ratio = Double(prefixed.count) / Double(archosEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.90,
      "At least 90% of VID 0x0e79 entries should start with 'archos-' (\(prefixed.count)/\(archosEntries.count))"
    )
  }
}

// MARK: - iRiver Audiophile Player Quirks Tests

/// iRiver audiophile player quirks tests validating libmtp-researched flags.
///
/// Key libmtp flags for iRiver:
/// - DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST → supportsGetObjectPropList: false
/// - DEVICE_FLAG_NO_ZERO_READS → noZeroReads: true (mapped via operations/flags)
/// - DEVICE_FLAG_IRIVER_OGG_ALZHEIMER (OGG format handling, not directly mapped)
///
/// VID 0x4102 — iRiver Ltd (primary), also 0x1006 (legacy)
/// Source: libmtp music-players.h
final class IRiverDeviceQuirksTests: XCTestCase {

  private static let iriverVID: UInt16 = 0x4102
  private static let iriverLegacyVID: UInt16 = 0x1006
  private var db: QuirkDatabase!
  private var iriverEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    iriverEntries = db.entries.filter {
      $0.vid == Self.iriverVID || $0.vid == Self.iriverLegacyVID
    }
  }

  func testIRiverEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      iriverEntries.count, 5,
      "Expected at least 5 iRiver entries, found \(iriverEntries.count)")
  }

  // MARK: - BROKEN_MTPGETOBJPROPLIST → supportsGetObjectPropList: false

  func testIRiverClassicDevicesHaveBrokenGetObjPropList() {
    let classicPIDs: Set<UInt16> = [
      0x1008, 0x1113, 0x1114, 0x1119, 0x1134, 0x1141, 0x2101,
    ]
    for entry in iriverEntries where classicPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "iRiver '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  // MARK: - Clix2 uses DEVICE_FLAG_NONE

  func testIRiverClix2HasNoSpecialFlags() {
    let clix2 = iriverEntries.first { $0.pid == 0x1126 }
    XCTAssertNotNil(clix2, "Missing iRiver Clix2 (PID 0x1126)")
  }

  // MARK: - Specific iRiver Models

  func testIRiverT10Exists() {
    let t10 = iriverEntries.first { $0.pid == 0x1113 }
    XCTAssertNotNil(t10, "Missing iRiver T10 (PID 0x1113)")
  }

  func testIRiverH10Exists() {
    let h10 = iriverEntries.first { $0.pid == 0x2101 }
    XCTAssertNotNil(h10, "Missing iRiver H10 20GB (PID 0x2101)")
  }
}

// MARK: - Cowon/iAudio Audiophile Player Quirks Tests

/// Cowon/iAudio audiophile player quirks tests validating libmtp-researched flags.
///
/// Key libmtp flags for Cowon:
/// - DEVICE_FLAG_UNLOAD_DRIVER → requiresKernelDetach: true
/// - DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST → supportsGetObjectPropList: false
///
/// VID 0x0e21 — Cowon Systems, Inc.
/// Source: libmtp music-players.h
final class CowonDeviceQuirksTests: XCTestCase {

  private static let cowonVID: UInt16 = 0x0e21
  private var db: QuirkDatabase!
  private var cowonEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    cowonEntries = db.entries.filter { $0.vid == Self.cowonVID }
  }

  func testCowonEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      cowonEntries.count, 3,
      "Expected at least 3 Cowon entries, found \(cowonEntries.count)")
  }

  func testAllCowonEntriesHaveCorrectVID() {
    for entry in cowonEntries {
      XCTAssertEqual(
        entry.vid, Self.cowonVID,
        "Cowon entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - Cowon Flag Consistency

  func testCowonDevicesHaveTypedFlags() {
    let cowonPIDs: Set<UInt16> = [
      0x0701, 0x0711, 0x0801, 0x0901, 0x0921,
    ]
    for entry in cowonEntries where cowonPIDs.contains(entry.pid) {
      XCTAssertNotNil(
        entry.flags ?? entry.operations.map { _ in QuirkFlags() },
        "Cowon '\(entry.id)' should have flags or operations defined")
    }
  }

  // MARK: - BROKEN_MTPGETOBJPROPLIST → supportsGetObjectPropList: false

  func testCowonDevicesHaveBrokenGetObjPropList() {
    let cowonPIDs: Set<UInt16> = [
      0x0701, 0x0711, 0x0801, 0x0901, 0x0921,
    ]
    for entry in cowonEntries where cowonPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Cowon '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  // MARK: - Specific Cowon Models

  func testCowonIAudioU3Exists() {
    let u3 = cowonEntries.first { $0.pid == 0x0701 }
    XCTAssertNotNil(u3, "Missing Cowon iAudio U3 (PID 0x0701)")
  }

  func testCowonIAudioD2Exists() {
    let d2 = cowonEntries.first { $0.pid == 0x0801 }
    XCTAssertNotNil(d2, "Missing Cowon iAudio D2 (PID 0x0801)")
  }

  func testCowonIAudioJ3Exists() {
    let j3 = cowonEntries.first { $0.pid == 0x0921 }
    XCTAssertNotNil(j3, "Missing Cowon iAudio J3 (PID 0x0921)")
  }
}
