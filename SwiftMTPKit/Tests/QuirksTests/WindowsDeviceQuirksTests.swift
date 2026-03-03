// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

// MARK: - Microsoft Device Quirks Tests

/// Microsoft MTP device quirks tests validating libmtp-researched flags
/// for Zune media players, Windows Phone, Kin, and Lumia devices (VID 0x045e).
///
/// Microsoft pioneered the MTP protocol as part of Windows Media DRM.
/// The Zune was one of the first dedicated MTP devices.
/// All Microsoft devices use DEVICE_FLAG_NONE in libmtp.
///
/// Source: libmtp music-players.h
final class MicrosoftDeviceQuirksTests: XCTestCase {

  private static let microsoftVID: UInt16 = 0x045e
  private var db: QuirkDatabase!
  private var microsoftEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    microsoftEntries = db.entries.filter { $0.vid == Self.microsoftVID }
  }

  // MARK: - Vendor Presence

  func testMicrosoftEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      microsoftEntries.count, 20,
      "Expected at least 20 Microsoft device entries, found \(microsoftEntries.count)")
  }

  func testAllMicrosoftEntriesHaveCorrectVID() {
    for entry in microsoftEntries {
      XCTAssertEqual(
        entry.vid, Self.microsoftVID,
        "Microsoft entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateMicrosoftProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in microsoftEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Microsoft PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Zune Media Players

  func testZuneOriginalExists() {
    let zune = microsoftEntries.first { $0.pid == 0x0710 }
    XCTAssertNotNil(zune, "Missing Microsoft Zune (PID 0x0710)")
    XCTAssertEqual(zune?.category, "media-player")
  }

  func testZuneHDExists() {
    let zuneHD = microsoftEntries.first { $0.pid == 0x063e }
    XCTAssertNotNil(zuneHD, "Missing Microsoft Zune HD (PID 0x063e)")
    XCTAssertEqual(zuneHD?.category, "media-player")
  }

  func testZune8GBExists() {
    let zune = microsoftEntries.first { $0.pid == 0x0711 }
    XCTAssertNotNil(zune, "Missing Microsoft Zune 8GB (PID 0x0711)")
  }

  func testZune80GBExists() {
    let zune = microsoftEntries.first { $0.pid == 0x0712 }
    XCTAssertNotNil(zune, "Missing Microsoft Zune 80GB (PID 0x0712)")
  }

  func testZuneDevicesAreCategorizedAsMediaPlayer() {
    let zunePIDs: Set<UInt16> = [0x0710, 0x0711, 0x0712, 0x0713, 0x0714, 0x063e]
    for entry in microsoftEntries where zunePIDs.contains(entry.pid) {
      XCTAssertEqual(
        entry.category, "media-player",
        "Zune entry '\(entry.id)' should be categorized as media-player, got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - DEVICE_FLAG_NONE → No kernel detach needed

  func testMicrosoftDevicesDoNotRequireKernelDetach() {
    for entry in microsoftEntries {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.requiresKernelDetach,
        "Microsoft '\(entry.id)' should not require kernel detach (DEVICE_FLAG_NONE)")
    }
  }

  // MARK: - Windows Phone

  func testWindowsPhoneEntryExists() {
    let wp = microsoftEntries.first { $0.pid == 0x04ec }
    XCTAssertNotNil(wp, "Missing Windows Phone entry (PID 0x04ec)")
  }

  func testWindowsPhone8Exists() {
    let wp8 = microsoftEntries.first { $0.pid == 0x04ef }
    XCTAssertNotNil(wp8, "Missing Windows Phone 8 entry (PID 0x04ef)")
  }

  // MARK: - Microsoft Kin

  func testKinOneExists() {
    let kin = microsoftEntries.first { $0.pid == 0x04c1 }
    XCTAssertNotNil(kin, "Missing Microsoft Kin ONE (PID 0x04c1)")
    XCTAssertEqual(kin?.category, "phone")
  }

  func testKinTwoMExists() {
    let kin = microsoftEntries.first { $0.pid == 0x04c2 }
    XCTAssertNotNil(kin, "Missing Microsoft Kin TwoM (PID 0x04c2)")
    XCTAssertEqual(kin?.category, "phone")
  }

  func testKinOriginalPIDExists() {
    let kin = microsoftEntries.first { $0.pid == 0x0640 }
    XCTAssertNotNil(kin, "Missing Microsoft Kin (PID 0x0640)")
  }

  // MARK: - Lumia 950 XL

  func testLumia950XLExists() {
    let lumia = microsoftEntries.first { $0.pid == 0x0a00 }
    XCTAssertNotNil(lumia, "Missing Microsoft Lumia 950 XL (PID 0x0a00)")
  }

  // MARK: - Surface Duo

  func testSurfaceDuoExists() {
    let duo = microsoftEntries.first { $0.pid == 0x091e }
    XCTAssertNotNil(duo, "Missing Microsoft Surface Duo (PID 0x091e)")
  }

  func testSurfaceDuo2Exists() {
    let duo2 = microsoftEntries.first { $0.pid == 0x091f }
    XCTAssertNotNil(duo2, "Missing Microsoft Surface Duo 2 (PID 0x091f)")
  }

  // MARK: - ID Naming Convention

  func testMicrosoftIDsStartWithMicrosoft() {
    let prefixed = microsoftEntries.filter { $0.id.hasPrefix("microsoft-") }
    let ratio = Double(prefixed.count) / Double(microsoftEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.50,
      "At least 50% of VID 0x045e entries should start with 'microsoft-' (\(prefixed.count)/\(microsoftEntries.count))"
    )
  }
}

// MARK: - Dell Device Quirks Tests

/// Dell MTP device quirks tests validating libmtp-researched flags
/// for Dell DJ media players and Dell Android tablets (VID 0x413c).
///
/// Dell DJ Itty: DEVICE_FLAG_NONE
/// Dell Streak 7, Venue 7: DEVICE_FLAGS_ANDROID_BUGS
///
/// Source: libmtp music-players.h
final class DellDeviceQuirksTests: XCTestCase {

  private static let dellVID: UInt16 = 0x413c
  private var db: QuirkDatabase!
  private var dellEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    dellEntries = db.entries.filter { $0.vid == Self.dellVID }
  }

  // MARK: - Vendor Presence

  func testDellEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      dellEntries.count, 3,
      "Expected at least 3 Dell device entries, found \(dellEntries.count)")
  }

  func testAllDellEntriesHaveCorrectVID() {
    for entry in dellEntries {
      XCTAssertEqual(
        entry.vid, Self.dellVID,
        "Dell entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - Dell DJ Itty: DEVICE_FLAG_NONE

  func testDellDJIttyExists() {
    let dj = dellEntries.first { $0.pid == 0x4500 }
    XCTAssertNotNil(dj, "Missing Dell DJ Itty (PID 0x4500)")
    XCTAssertEqual(dj?.category, "media-player")
  }

  func testDellDJIttyDoesNotRequireKernelDetach() {
    let dj = dellEntries.first { $0.pid == 0x4500 }
    if let entry = dj {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.requiresKernelDetach,
        "Dell DJ Itty should not require kernel detach (DEVICE_FLAG_NONE)")
    }
  }

  // MARK: - Dell Streak 7: ANDROID_BUGS

  func testDellStreak7Exists() {
    let streak = dellEntries.first { $0.pid == 0xb10b }
    XCTAssertNotNil(streak, "Missing Dell Streak 7 (PID 0xb10b)")
  }

  func testDellStreak7RequiresKernelDetach() {
    let streak = dellEntries.first { $0.pid == 0xb10b }
    if let entry = streak {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Dell Streak 7 should require kernel detach (ANDROID_BUGS)")
    }
  }

  func testDellStreak7HasBrokenGetObjPropList() {
    let streak = dellEntries.first { $0.pid == 0xb10b }
    if let entry = streak {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Dell Streak 7 should have supportsGetObjectPropList=false (ANDROID_BUGS)")
    }
  }

  // MARK: - Dell Venue 7: ANDROID_BUGS

  func testDellVenue7Exists() {
    let venue = dellEntries.first { $0.pid == 0xb11a }
    XCTAssertNotNil(venue, "Missing Dell Venue 7 (PID 0xb11a)")
  }

  func testDellVenue7RequiresKernelDetach() {
    let venue = dellEntries.first { $0.pid == 0xb11a }
    if let entry = venue {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Dell Venue 7 should require kernel detach (ANDROID_BUGS)")
    }
  }

  func testDellVenue7HasBrokenGetObjPropList() {
    let venue = dellEntries.first { $0.pid == 0xb11a }
    if let entry = venue {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Dell Venue 7 should have supportsGetObjectPropList=false (ANDROID_BUGS)")
    }
  }

  // MARK: - Dell Axim PDA Devices

  func testDellAximDevicesExist() {
    let aximPIDs: Set<UInt16> = [0x4103, 0x4104, 0x4105, 0x4107, 0x4108]
    for pid in aximPIDs {
      let entry = dellEntries.first { $0.pid == pid }
      XCTAssertNotNil(entry, "Missing Dell Axim entry for PID 0x\(String(pid, radix: 16))")
    }
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateDellProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in dellEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Dell PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }
}

// MARK: - Fujitsu Device Quirks Tests

/// Fujitsu MTP device quirks tests validating libmtp-researched flags
/// for Fujitsu Android phones/tablets, feature phones, and scanners (VID 0x04c5).
///
/// Android devices (STYLISTIC, F-02E, ARROWS, TONE): DEVICE_FLAGS_ANDROID_BUGS
/// Feature phone (F903iX): DEVICE_FLAG_NONE
///
/// Source: libmtp music-players.h
final class FujitsuDeviceQuirksTests: XCTestCase {

  private static let fujitsuVID: UInt16 = 0x04c5
  private var db: QuirkDatabase!
  private var fujitsuEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    fujitsuEntries = db.entries.filter { $0.vid == Self.fujitsuVID }
  }

  // MARK: - Vendor Presence

  func testFujitsuEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      fujitsuEntries.count, 10,
      "Expected at least 10 Fujitsu device entries, found \(fujitsuEntries.count)")
  }

  func testAllFujitsuEntriesHaveCorrectVID() {
    for entry in fujitsuEntries {
      XCTAssertEqual(
        entry.vid, Self.fujitsuVID,
        "Fujitsu entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  // MARK: - STYLISTIC M532: ANDROID_BUGS

  func testStylisticM532Exists() {
    let stylistic = fujitsuEntries.first { $0.pid == 0x133b }
    XCTAssertNotNil(stylistic, "Missing Fujitsu STYLISTIC M532 (PID 0x133b)")
    XCTAssertEqual(stylistic?.category, "phone")
  }

  func testStylisticM532RequiresKernelDetach() {
    let stylistic = fujitsuEntries.first { $0.pid == 0x133b }
    if let entry = stylistic {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Fujitsu STYLISTIC M532 should require kernel detach (ANDROID_BUGS)")
    }
  }

  func testStylisticM532HasBrokenGetObjPropList() {
    let stylistic = fujitsuEntries.first { $0.pid == 0x133b }
    if let entry = stylistic {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Fujitsu STYLISTIC M532 should have supportsGetObjectPropList=false (ANDROID_BUGS)")
    }
  }

  // MARK: - Fujitsu Android Phones: ANDROID_BUGS

  func testFujitsuF02EExists() {
    let f02e = fujitsuEntries.first { $0.pid == 0x13f5 }
    XCTAssertNotNil(f02e, "Missing Fujitsu F-02E (PID 0x13f5)")
    XCTAssertEqual(f02e?.category, "phone")
  }

  func testFujitsuArrows202FExists() {
    let arrows = fujitsuEntries.first { $0.pid == 0x1409 }
    XCTAssertNotNil(arrows, "Missing Fujitsu ARROWS 202F (PID 0x1409)")
    XCTAssertEqual(arrows?.category, "phone")
  }

  func testFujitsuToneM17Exists() {
    let tone = fujitsuEntries.first { $0.pid == 0x145c }
    XCTAssertNotNil(tone, "Missing Fujitsu TONE m17 (PID 0x145c)")
    XCTAssertEqual(tone?.category, "phone")
  }

  func testFujitsuAndroidPhonesRequireKernelDetach() {
    let androidPIDs: Set<UInt16> = [0x1378, 0x13f5, 0x1409, 0x145c]
    for entry in fujitsuEntries where androidPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Fujitsu Android '\(entry.id)' should require kernel detach (ANDROID_BUGS)")
    }
  }

  func testFujitsuAndroidPhonesHaveBrokenGetObjPropList() {
    let androidPIDs: Set<UInt16> = [0x1378, 0x13f5, 0x1409, 0x145c]
    for entry in fujitsuEntries where androidPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Fujitsu Android '\(entry.id)' should have supportsGetObjectPropList=false (ANDROID_BUGS)")
    }
  }

  // MARK: - F903iX Feature Phone: DEVICE_FLAG_NONE

  func testF903iXExists() {
    let f903 = fujitsuEntries.first { $0.pid == 0x1140 }
    XCTAssertNotNil(f903, "Missing Fujitsu F903iX (PID 0x1140)")
    XCTAssertEqual(f903?.category, "phone")
  }

  func testF903iXDoesNotRequireKernelDetach() {
    let f903 = fujitsuEntries.first { $0.pid == 0x1140 }
    if let entry = f903 {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.requiresKernelDetach,
        "Fujitsu F903iX should not require kernel detach (DEVICE_FLAG_NONE)")
    }
  }

  func testF903iXSupportsGetObjectPropList() {
    let f903 = fujitsuEntries.first { $0.pid == 0x1140 }
    if let entry = f903 {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Fujitsu F903iX should support GetObjectPropList (DEVICE_FLAG_NONE)")
    }
  }

  // MARK: - Fujitsu Scanners

  func testFujitsuScanSnapsExist() {
    let scanners = fujitsuEntries.filter { $0.category == "scanner" }
    XCTAssertGreaterThanOrEqual(
      scanners.count, 5,
      "Expected at least 5 Fujitsu ScanSnap entries, found \(scanners.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateFujitsuProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in fujitsuEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Fujitsu PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }
}

// MARK: - Niche Device Quirks Tests

/// Niche MTP device quirks tests for Insignia, JVC, and Sirius devices.
///
/// Insignia (0x19ff): DEVICE_FLAG_UNLOAD_DRIVER → requiresKernelDetach
/// JVC (0x04f1): Mixed - Alneo player is NONE, automotive head units vary
/// Sirius (0x18f6): Satellite radio devices
///
/// Source: libmtp music-players.h
final class NicheDeviceQuirksTests: XCTestCase {

  private static let insigniaVID: UInt16 = 0x19ff
  private static let jvcVID: UInt16 = 0x04f1
  private static let siriusVID: UInt16 = 0x18f6

  private var db: QuirkDatabase!
  private var insigniaEntries: [DeviceQuirk]!
  private var jvcEntries: [DeviceQuirk]!
  private var siriusEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    insigniaEntries = db.entries.filter { $0.vid == Self.insigniaVID }
    jvcEntries = db.entries.filter { $0.vid == Self.jvcVID }
    siriusEntries = db.entries.filter { $0.vid == Self.siriusVID }
  }

  // MARK: - Insignia: UNLOAD_DRIVER

  func testInsigniaEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      insigniaEntries.count, 5,
      "Expected at least 5 Insignia entries, found \(insigniaEntries.count)")
  }

  func testInsigniaSportPlayerExists() {
    let sport = insigniaEntries.first { $0.pid == 0x0307 }
    XCTAssertNotNil(sport, "Missing Insignia Sport Player (PID 0x0307)")
    XCTAssertEqual(sport?.category, "media-player")
  }

  func testInsigniaPilot4002Exists() {
    let pilot = insigniaEntries.first { $0.pid == 0x0304 }
    XCTAssertNotNil(pilot, "Missing Insignia Pilot 4002 (PID 0x0304)")
    XCTAssertEqual(pilot?.category, "media-player")
  }

  func testInsigniaMediaPlayersRequireKernelDetach() {
    let mediaPlayers = insigniaEntries.filter { $0.category == "media-player" }
    for entry in mediaPlayers {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Insignia media player '\(entry.id)' should require kernel detach (UNLOAD_DRIVER)")
    }
  }

  // MARK: - JVC: Mixed device types

  func testJVCEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      jvcEntries.count, 5,
      "Expected at least 5 JVC entries, found \(jvcEntries.count)")
  }

  func testJVCAlneoExists() {
    let alneo = jvcEntries.first { $0.pid == 0x6105 }
    XCTAssertNotNil(alneo, "Missing JVC Alneo XA-HD500 (PID 0x6105)")
  }

  func testJVCAlneoDoesNotRequireKernelDetach() {
    let alneo = jvcEntries.first { $0.pid == 0x6105 }
    if let entry = alneo {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.requiresKernelDetach,
        "JVC Alneo should not require kernel detach (DEVICE_FLAG_NONE in libmtp)")
    }
  }

  func testJVCHasAutomotiveAndCameraCategories() {
    let categories = Set(jvcEntries.compactMap { $0.category })
    XCTAssertTrue(
      categories.contains("automotive") || categories.contains("camera"),
      "JVC entries should include automotive or camera categories, found \(categories)")
  }

  // MARK: - Sirius: Satellite Radio

  func testSiriusEntriesExist() {
    XCTAssertGreaterThanOrEqual(
      siriusEntries.count, 2,
      "Expected at least 2 Sirius entries, found \(siriusEntries.count)")
  }

  func testSiriusStilettoExists() {
    let stiletto = siriusEntries.first { $0.pid == 0x0102 }
    XCTAssertNotNil(stiletto, "Missing Sirius Stiletto (PID 0x0102)")
    XCTAssertEqual(stiletto?.category, "media-player")
  }

  func testSiriusStilettoDevicesSupportGetObjectPropList() {
    for entry in siriusEntries {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Sirius '\(entry.id)' should support GetObjectPropList")
    }
  }

  func testSiriusDevicesAreCategorizedAsMediaPlayer() {
    for entry in siriusEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "Sirius '\(entry.id)' should be categorized as media-player, got '\(entry.category ?? "nil")'"
      )
    }
  }
}
