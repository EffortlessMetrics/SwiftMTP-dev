// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Wave 30 research: deep validation of quirk entries for under-represented
/// brands (Oppo, Vivo, Realme, Xiaomi/Redmi, Nothing, DJI, Insta360, FiiO,
/// Astell&Kern). Tests validate transport configuration, interface settings,
/// category consistency, VID:PID uniqueness within each brand, and evidence
/// fields for promoted entries.
final class QuirksWave30ResearchTests: XCTestCase {

  // MARK: - Vendor IDs

  private static let oppoVID: UInt16 = 0x22D9
  private static let vivoVID: UInt16 = 0x2D95
  private static let xiaomiVID: UInt16 = 0x2717
  private static let nothingVID: UInt16 = 0x2B0E
  private static let djiVID: UInt16 = 0x2CA3
  private static let insta360VID: UInt16 = 0x2E1A
  private static let fiioVID: UInt16 = 0x2972
  private static let astellKernVID: UInt16 = 0x4102

  // PTP Still-Image-Capture interface class
  private static let ptpIfaceClass: UInt8 = 0x06
  private static let ptpIfaceSubclass: UInt8 = 0x01
  private static let ptpIfaceProtocol: UInt8 = 0x01
  private static let vendorIfaceClass: UInt8 = 0xFF

  private var db: QuirkDatabase!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
  }

  // MARK: - Helper: filter entries by brand ID prefix

  private func entries(matching prefix: String) -> [DeviceQuirk] {
    db.entries.filter { $0.id.hasPrefix(prefix) }
  }

  private func entries(withVID vid: UInt16) -> [DeviceQuirk] {
    db.entries.filter { $0.vid == vid }
  }

  private func entries(idContaining substring: String) -> [DeviceQuirk] {
    db.entries.filter { $0.id.contains(substring) }
  }

  // MARK: - Oppo Validation

  func testOppoEntriesExist() {
    let oppo = entries(matching: "oppo-")
    XCTAssertGreaterThan(
      oppo.count, 50,
      "Expected substantial Oppo device database, found only \(oppo.count)")
  }

  func testOppoMajorityHavePhoneCategory() {
    let oppo = entries(matching: "oppo-")
    let phones = oppo.filter { $0.category == "phone" }
    let ratio = Double(phones.count) / Double(max(oppo.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of Oppo entries to be phones, got \(Int(ratio * 100))%")
  }

  func testOppoMajorityRequireKernelDetach() {
    let oppo = entries(matching: "oppo-")
    let kdTrue = oppo.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(oppo.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of Oppo entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(oppo.count - kdTrue.count) entries have it disabled)")
  }

  func testOppoVIDConsistency() {
    let oppo = entries(matching: "oppo-").filter {
      !$0.id.contains("realme")
    }
    let primaryVID = oppo.filter { $0.vid == Self.oppoVID }
    let ratio = Double(primaryVID.count) / Double(max(oppo.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.85,
      "Expected >85% of Oppo entries to use VID 0x22D9, got \(Int(ratio * 100))%")
  }

  // MARK: - Vivo Validation

  func testVivoEntriesExist() {
    let vivo = entries(matching: "vivo-")
    XCTAssertGreaterThan(
      vivo.count, 50,
      "Expected substantial Vivo device database, found only \(vivo.count)")
  }

  func testVivoEntriesHavePhoneCategory() {
    let vivo = entries(matching: "vivo-")
    let nonPhone = vivo.filter { $0.category != "phone" }
    XCTAssertTrue(
      nonPhone.isEmpty,
      "Vivo entries should be phones, found: "
        + "\(nonPhone.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testVivoMajorityRequireKernelDetach() {
    let vivo = entries(matching: "vivo-")
    let kdTrue = vivo.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(vivo.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of Vivo entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(vivo.count - kdTrue.count) entries have it disabled)")
  }

  func testVivoVIDConsistency() {
    let vivo = entries(matching: "vivo-")
    let primaryVID = vivo.filter { $0.vid == Self.vivoVID }
    let ratio = Double(primaryVID.count) / Double(max(vivo.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.70,
      "Expected >70% of Vivo entries to use VID 0x2D95, got \(Int(ratio * 100))%")
  }

  // MARK: - Realme Validation

  func testRealmeEntriesExist() {
    let realme = entries(matching: "realme-")
    XCTAssertGreaterThan(
      realme.count, 50,
      "Expected substantial Realme device database, found only \(realme.count)")
  }

  func testRealmeMajorityHavePhoneCategory() {
    let realme = entries(matching: "realme-")
    let validCategories: Set<String> = ["phone", "tablet", "media-player"]
    let valid = realme.filter {
      guard let cat = $0.category else { return false }
      return validCategories.contains(cat)
    }
    XCTAssertEqual(
      valid.count, realme.count,
      "Realme entries should be phones, tablets, or media-players")
  }

  func testRealmeSharesOppoVID() {
    // Realme is a subsidiary of BBK/Oppo — most entries share the Oppo VID
    let realme = entries(matching: "realme-")
    let oppoVID = realme.filter { $0.vid == Self.oppoVID }
    XCTAssertGreaterThan(
      oppoVID.count, 0,
      "Expected some Realme entries to share Oppo VID 0x22D9")
  }

  func testRealmeMajorityRequireKernelDetach() {
    let realme = entries(matching: "realme-")
    let kdTrue = realme.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(realme.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of Realme entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(realme.count - kdTrue.count) entries have it disabled)")
  }

  // MARK: - Xiaomi/Redmi Validation

  func testRedmiEntriesExist() {
    let redmi = entries(idContaining: "redmi")
    XCTAssertGreaterThan(
      redmi.count, 50,
      "Expected substantial Redmi device database, found only \(redmi.count)")
  }

  func testRedmiEntriesArePhonesOrTablets() {
    let redmi = entries(idContaining: "redmi")
    let validCategories: Set<String> = ["phone", "tablet"]
    let invalid = redmi.filter {
      guard let cat = $0.category else { return true }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Redmi entries should be phones or tablets, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testRedmiMajorityRequireKernelDetach() {
    let redmi = entries(idContaining: "redmi")
    let kdTrue = redmi.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(redmi.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of Redmi entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(redmi.count - kdTrue.count) entries have it disabled)")
  }

  func testRedmiEntriesUseXiaomiVID() {
    let redmi = entries(idContaining: "redmi")
    let xiaomiVIDEntries = redmi.filter { $0.vid == Self.xiaomiVID }
    let ratio = Double(xiaomiVIDEntries.count) / Double(max(redmi.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.85,
      "Expected >85% of Redmi entries to use Xiaomi VID 0x2717, got \(Int(ratio * 100))%")
  }

  // MARK: - Nothing Phone Validation

  func testNothingEntriesExist() {
    let nothing = entries(matching: "nothing-")
    XCTAssertGreaterThan(
      nothing.count, 5,
      "Expected Nothing Phone entries, found only \(nothing.count)")
  }

  func testNothingEntriesArePhonesOrTablets() {
    let nothing = entries(matching: "nothing-")
    let validCategories: Set<String> = ["phone", "tablet"]
    let invalid = nothing.filter {
      guard let cat = $0.category else { return true }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Nothing entries should be phones or tablets, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testNothingMajorityRequireKernelDetach() {
    let nothing = entries(matching: "nothing-")
    let kdTrue = nothing.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(nothing.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.85,
      "Expected >85% of Nothing entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(nothing.count - kdTrue.count) entries have it disabled)")
  }

  // MARK: - DJI / Action Camera Validation

  func testDJIEntriesExist() {
    let dji = entries(matching: "dji-")
    XCTAssertGreaterThan(
      dji.count, 100,
      "Expected substantial DJI device database, found only \(dji.count)")
  }

  func testDJIEntriesHaveExpectedCategories() {
    let dji = entries(matching: "dji-")
    let validCategories: Set<String> = ["drone", "action-camera", "camera", "embedded"]
    let invalid = dji.filter {
      guard let cat = $0.category else { return true }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "DJI entries should be drone/camera/embedded, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testDJIPrimaryVIDConsistency() {
    let dji = entries(matching: "dji-")
    let primaryVID = dji.filter { $0.vid == Self.djiVID }
    let ratio = Double(primaryVID.count) / Double(max(dji.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.90,
      "Expected >90% of DJI entries to use VID 0x2CA3, got \(Int(ratio * 100))%")
  }

  func testDJICameraEntriesMajorityHaveCameraClassFlag() {
    let dji = entries(matching: "dji-")
    let cameraEntries = dji.filter {
      $0.category == "action-camera" || $0.category == "camera"
    }
    let withFlag = cameraEntries.filter { $0.resolvedFlags().cameraClass }
    let ratio = Double(withFlag.count) / Double(max(cameraEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.50,
      "Expected >50% of DJI camera entries to have cameraClass flag, got \(Int(ratio * 100))%")
  }

  // MARK: - Insta360 Validation

  func testInsta360EntriesExist() {
    let insta = entries(matching: "insta360-")
    XCTAssertGreaterThan(
      insta.count, 30,
      "Expected substantial Insta360 database, found only \(insta.count)")
  }

  func testInsta360EntriesHaveCameraCategory() {
    let insta = entries(matching: "insta360-")
    let validCategories: Set<String> = ["action-camera", "camera", "streaming-device"]
    let invalid = insta.filter {
      guard let cat = $0.category else { return true }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Insta360 entries should be action-camera, camera, or streaming-device, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testInsta360PrimaryVIDConsistency() {
    let insta = entries(matching: "insta360-")
    let primaryVID = insta.filter { $0.vid == Self.insta360VID }
    let ratio = Double(primaryVID.count) / Double(max(insta.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.85,
      "Expected >85% of Insta360 entries to use VID 0x2E1A, got \(Int(ratio * 100))%")
  }

  func testInsta360MajorityHaveCameraClassFlag() {
    let insta = entries(matching: "insta360-")
    let withFlag = insta.filter { $0.resolvedFlags().cameraClass }
    let ratio = Double(withFlag.count) / Double(max(insta.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.60,
      "Expected >60% of Insta360 entries to have cameraClass flag, got \(Int(ratio * 100))%")
  }

  func testInsta360PTPInterfaceEntriesHaveFullDescriptor() {
    // Insta360 cameras with full PTP descriptor (class + subclass + protocol)
    let insta = entries(matching: "insta360-").filter {
      $0.ifaceClass == Self.ptpIfaceClass && $0.ifaceSubclass != nil
    }
    for entry in insta {
      XCTAssertEqual(
        entry.ifaceSubclass, Self.ptpIfaceSubclass,
        "Insta360 PTP entry '\(entry.id)' should have subclass 0x01")
      XCTAssertEqual(
        entry.ifaceProtocol, Self.ptpIfaceProtocol,
        "Insta360 PTP entry '\(entry.id)' should have protocol 0x01")
    }
  }

  // MARK: - FiiO Audio Player Validation

  func testFiiOEntriesExist() {
    let fiio = entries(matching: "fiio-")
    XCTAssertGreaterThan(
      fiio.count, 20,
      "Expected substantial FiiO database, found only \(fiio.count)")
  }

  func testFiiOEntriesHaveAudioCategory() {
    let fiio = entries(matching: "fiio-")
    let validCategories: Set<String> = ["audio-player", "audio-interface"]
    let invalid = fiio.filter {
      guard let cat = $0.category else { return true }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "FiiO entries should be audio-player or audio-interface, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testFiiOPrimaryVIDConsistency() {
    let fiio = entries(matching: "fiio-")
    let primaryVID = fiio.filter { $0.vid == Self.fiioVID }
    let ratio = Double(primaryVID.count) / Double(max(fiio.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.60,
      "Expected >60% of FiiO entries to use VID 0x2972, got \(Int(ratio * 100))%")
  }

  func testFiiOMajorityRequireKernelDetach() {
    let fiio = entries(matching: "fiio-")
    let kdTrue = fiio.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(kdTrue.count) / Double(max(fiio.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.60,
      "Expected >60% of FiiO entries to require kernel detach, got \(Int(ratio * 100))%"
        + " (\(fiio.count - kdTrue.count) entries have it disabled)")
  }

  // MARK: - Astell&Kern Audio Player Validation

  func testAstellKernEntriesExist() {
    let ak = entries(matching: "astell-")
    XCTAssertGreaterThan(
      ak.count, 15,
      "Expected substantial Astell&Kern database, found only \(ak.count)")
  }

  func testAstellKernEntriesHaveAudioPlayerCategory() {
    let ak = entries(matching: "astell-")
    let invalid = ak.filter { $0.category != "audio-player" }
    XCTAssertTrue(
      invalid.isEmpty,
      "Astell&Kern entries should be audio-player, found: "
        + "\(invalid.prefix(5).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testAstellKernPTPInterfaceEntries() {
    // Astell&Kern DAPs with PTP interface should have proper class/subclass/protocol
    let ak = entries(matching: "astell-").filter {
      $0.ifaceClass == Self.ptpIfaceClass
    }
    for entry in ak {
      XCTAssertEqual(
        entry.ifaceSubclass, Self.ptpIfaceSubclass,
        "Astell&Kern PTP entry '\(entry.id)' should have subclass 0x01")
      XCTAssertEqual(
        entry.ifaceProtocol, Self.ptpIfaceProtocol,
        "Astell&Kern PTP entry '\(entry.id)' should have protocol 0x01")
    }
  }

  // MARK: - Cross-Brand: VID:PID Uniqueness Within Brand

  func testVIDPIDUniquenessWithinOppo() {
    assertNoDuplicateVIDPID(in: entries(matching: "oppo-"), brand: "Oppo")
  }

  func testVIDPIDUniquenessWithinVivo() {
    assertNoDuplicateVIDPID(in: entries(matching: "vivo-"), brand: "Vivo")
  }

  func testVIDPIDUniquenessWithinRealme() {
    assertNoDuplicateVIDPID(in: entries(matching: "realme-"), brand: "Realme")
  }

  func testVIDPIDUniquenessWithinDJI() {
    assertNoDuplicateVIDPID(in: entries(matching: "dji-"), brand: "DJI")
  }

  func testVIDPIDUniquenessWithinInsta360() {
    assertNoDuplicateVIDPID(in: entries(matching: "insta360-"), brand: "Insta360")
  }

  func testVIDPIDUniquenessWithinFiiO() {
    assertNoDuplicateVIDPID(in: entries(matching: "fiio-"), brand: "FiiO")
  }

  func testVIDPIDUniquenessWithinAstellKern() {
    assertNoDuplicateVIDPID(in: entries(matching: "astell-"), brand: "Astell&Kern")
  }

  func testVIDPIDUniquenessWithinNothing() {
    assertNoDuplicateVIDPID(in: entries(matching: "nothing-"), brand: "Nothing")
  }

  private func assertNoDuplicateVIDPID(
    in entries: [DeviceQuirk], brand: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    var seen = [String: String]()
    var duplicates = [(String, String, String)]()
    for entry in entries {
      let key = String(format: "%04x:%04x", entry.vid, entry.pid)
      if let first = seen[key] {
        duplicates.append((key, first, entry.id))
      } else {
        seen[key] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "\(brand) has duplicate VID:PID pairs: "
        + "\(duplicates.prefix(5).map { "\($0.0) [\($0.1), \($0.2)]" })",
      file: file, line: line)
  }

  // MARK: - Cross-Brand: Promoted Entry Evidence

  func testPromotedEntriesHaveEvidence() {
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Promoted entry '\(entry.id)' must declare evidenceRequired")
      if let evidence = entry.evidenceRequired {
        XCTAssertFalse(
          evidence.isEmpty,
          "Promoted entry '\(entry.id)' has empty evidenceRequired array")
      }
      XCTAssertNotNil(
        entry.lastVerifiedDate,
        "Promoted entry '\(entry.id)' must have lastVerifiedDate")
      XCTAssertNotNil(
        entry.lastVerifiedBy,
        "Promoted entry '\(entry.id)' must have lastVerifiedBy")
    }
  }

  // MARK: - Cross-Brand: Category Consistency

  func testPhoneBrandsMajorityHavePhoneCategory() {
    let phoneBrands = ["oppo-", "vivo-", "nothing-"]
    for prefix in phoneBrands {
      let brandEntries = entries(matching: prefix)
      let phones = brandEntries.filter { $0.category == "phone" }
      let ratio = Double(phones.count) / Double(max(brandEntries.count, 1))
      XCTAssertGreaterThan(
        ratio, 0.85,
        "Brand '\(prefix)' expected >85% phones, got \(Int(ratio * 100))%")
    }
  }

  func testAllAudioBrandsHaveAudioCategory() {
    let audioBrands = ["fiio-", "astell-"]
    let validCategories: Set<String> = ["audio-player", "audio-interface"]
    for prefix in audioBrands {
      let brandEntries = entries(matching: prefix)
      let wrongCat = brandEntries.filter {
        guard let cat = $0.category else { return true }
        return !validCategories.contains(cat)
      }
      XCTAssertTrue(
        wrongCat.isEmpty,
        "Brand '\(prefix)' has non-audio entries: "
          + "\(wrongCat.prefix(3).map { "\($0.id)=\($0.category ?? "nil")" })")
    }
  }

  // MARK: - Cross-Brand: Reasonable Timeout Bounds

  func testAllBrandEntriesHaveReasonableTimeouts() {
    let brandPrefixes = [
      "oppo-", "vivo-", "realme-", "nothing-", "dji-", "insta360-", "fiio-", "astell-",
    ]
    for prefix in brandPrefixes {
      for entry in entries(matching: prefix) {
        if let io = entry.ioTimeoutMs {
          XCTAssertGreaterThan(
            io, 0,
            "Entry '\(entry.id)' has non-positive ioTimeoutMs: \(io)")
          XCTAssertLessThanOrEqual(
            io, 120_000,
            "Entry '\(entry.id)' has excessive ioTimeoutMs: \(io)")
        }
        if let hs = entry.handshakeTimeoutMs {
          XCTAssertGreaterThan(
            hs, 0,
            "Entry '\(entry.id)' has non-positive handshakeTimeoutMs: \(hs)")
          XCTAssertLessThanOrEqual(
            hs, 60_000,
            "Entry '\(entry.id)' has excessive handshakeTimeoutMs: \(hs)")
        }
        if let chunk = entry.maxChunkBytes {
          XCTAssertGreaterThanOrEqual(
            chunk, 512,
            "Entry '\(entry.id)' has tiny maxChunkBytes: \(chunk)")
          XCTAssertLessThanOrEqual(
            chunk, 16_777_216,
            "Entry '\(entry.id)' has excessive maxChunkBytes (>16MB): \(chunk)")
        }
      }
    }
  }

  // MARK: - Cross-Brand: Android Phone Interface Class

  func testAndroidPhoneBrandsUseVendorOrMTPInterface() {
    let phonePrefixes = ["oppo-", "vivo-", "realme-", "nothing-"]
    let validClasses: Set<UInt8> = [Self.vendorIfaceClass, Self.ptpIfaceClass]
    for prefix in phonePrefixes {
      for entry in entries(matching: prefix) {
        if let ifClass = entry.ifaceClass {
          XCTAssertTrue(
            validClasses.contains(ifClass),
            "Phone entry '\(entry.id)' has unexpected iface class 0x\(String(ifClass, radix: 16))"
              + " — expected 0xFF (vendor) or 0x06 (PTP)")
        }
      }
    }
  }

  // MARK: - Device Family Grouping: Redmi Note Series

  func testRedmiNoteSeriesGrouping() {
    let redmiNote = entries(idContaining: "redmi").filter {
      $0.id.contains("note")
    }
    XCTAssertGreaterThan(
      redmiNote.count, 5,
      "Expected multiple Redmi Note entries, found only \(redmiNote.count)")
    // All should share Xiaomi VID
    for entry in redmiNote {
      XCTAssertEqual(
        entry.vid, Self.xiaomiVID,
        "Redmi Note entry '\(entry.id)' should use Xiaomi VID 0x2717")
    }
  }

  // MARK: - Device Family Grouping: DJI Drones vs Cameras

  func testDJIDroneVsCameraFamilies() {
    let dji = entries(matching: "dji-")
    let drones = dji.filter { $0.category == "drone" }
    let cameras = dji.filter {
      $0.category == "action-camera" || $0.category == "camera"
    }
    XCTAssertGreaterThan(drones.count, 0, "Expected DJI drone entries")
    XCTAssertGreaterThan(cameras.count, 0, "Expected DJI camera entries")
    // Camera entries (majority) should have cameraClass flag
    let camsWithFlag = cameras.filter { $0.resolvedFlags().cameraClass }
    let ratio = Double(camsWithFlag.count) / Double(max(cameras.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.50,
      "Expected >50% of DJI camera entries to have cameraClass flag, got \(Int(ratio * 100))%")
  }
}
