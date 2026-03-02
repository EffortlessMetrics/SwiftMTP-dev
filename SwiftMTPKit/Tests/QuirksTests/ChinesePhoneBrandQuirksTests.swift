// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Quirks tests for Chinese phone brands: Xiaomi (incl. POCO/Redmi),
/// OnePlus, OPPO, and Realme.
///
/// These brands share Android-based MTP stacks (MIUI/HyperOS, OxygenOS,
/// ColorOS) that require macOS kernel driver detach, post-open stabilization,
/// and brand-specific workarounds (e.g. writeToSubfolderOnly on OnePlus).
final class ChinesePhoneBrandQuirksTests: XCTestCase {

  // MARK: - Vendor IDs

  /// Xiaomi primary VID; also used by POCO, Redmi sub-brands.
  private static let xiaomiVID: UInt16 = 0x2717
  /// OnePlus primary VID.
  private static let oneplusVID: UInt16 = 0x2A70
  /// OPPO/Realme shared VID (BBK Electronics subsidiary).
  private static let oppoRealmeVID: UInt16 = 0x22D9
  /// Qualcomm VID used by some early OnePlus devices (e.g. OnePlus One).
  private static let qualcommVID: UInt16 = 0x05C6

  private var db: QuirkDatabase!
  private var xiaomiEntries: [DeviceQuirk]!
  private var oneplusEntries: [DeviceQuirk]!
  private var oppoRealmeEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    xiaomiEntries = db.entries.filter { $0.vid == Self.xiaomiVID }
    oneplusEntries = db.entries.filter { $0.vid == Self.oneplusVID }
    oppoRealmeEntries = db.entries.filter { $0.vid == Self.oppoRealmeVID }
  }

  // MARK: - Entry Existence

  func testXiaomiEntriesExist() {
    XCTAssertGreaterThan(
      xiaomiEntries.count, 100,
      "Expected a substantial Xiaomi device database, found only \(xiaomiEntries.count)")
  }

  func testOnePlusEntriesExist() {
    XCTAssertGreaterThan(
      oneplusEntries.count, 10,
      "Expected OnePlus device entries, found only \(oneplusEntries.count)")
  }

  func testOPPORealmeEntriesExist() {
    XCTAssertGreaterThan(
      oppoRealmeEntries.count, 50,
      "Expected OPPO/Realme device entries, found only \(oppoRealmeEntries.count)")
  }

  // MARK: - Vendor ID Consistency

  func testAllXiaomiVIDEntriesHaveCorrectVID() {
    for entry in xiaomiEntries {
      XCTAssertEqual(
        entry.vid, Self.xiaomiVID,
        "Xiaomi entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testAllOnePlusVIDEntriesHaveCorrectVID() {
    for entry in oneplusEntries {
      XCTAssertEqual(
        entry.vid, Self.oneplusVID,
        "OnePlus entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testMajorityOfXiaomiIDsStartWithKnownBrands() {
    let branded = xiaomiEntries.filter {
      $0.id.hasPrefix("xiaomi-") || $0.id.hasPrefix("poco-")
        || $0.id.hasPrefix("redmi-")
    }
    let ratio = Double(branded.count) / Double(xiaomiEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.90,
      "≥90% of VID 0x2717 entries should start with 'xiaomi-', 'poco-', or 'redmi-' (\(branded.count)/\(xiaomiEntries.count))")
  }

  func testMajorityOfOnePlusIDsStartWithKnownBrands() {
    // OnePlus VID 0x2a70 is also used by Nothing Phone (both BBK subsidiaries)
    let branded = oneplusEntries.filter {
      $0.id.hasPrefix("oneplus-") || $0.id.hasPrefix("nothing-")
        || $0.id.hasPrefix("cmf-")
    }
    let ratio = Double(branded.count) / Double(oneplusEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "≥95% of VID 0x2a70 entries should start with 'oneplus-', 'nothing-', or 'cmf-' (\(branded.count)/\(oneplusEntries.count))")
  }

  // MARK: - POCO Uses Xiaomi VID

  func testPOCODevicesUseXiaomiVID() {
    let pocoEntries = xiaomiEntries.filter { $0.id.contains("poco") }
    XCTAssertGreaterThan(
      pocoEntries.count, 20,
      "Expected substantial POCO entries under Xiaomi VID 0x2717")
    for entry in pocoEntries {
      XCTAssertEqual(
        entry.vid, Self.xiaomiVID,
        "POCO entry '\(entry.id)' should use Xiaomi VID 0x2717")
    }
  }

  func testRedmiDevicesUseXiaomiVID() {
    let redmiEntries = xiaomiEntries.filter { $0.id.contains("redmi") }
    XCTAssertGreaterThan(
      redmiEntries.count, 5,
      "Expected Redmi entries under Xiaomi VID 0x2717")
  }

  // MARK: - OnePlus Cross-Brand VIDs

  func testOnePlusDevicesUnderQualcommVID() {
    // Early OnePlus One used Qualcomm VID 0x05c6
    let qualcommOnePlus = db.entries.filter {
      $0.vid == Self.qualcommVID && $0.id.contains("oneplus")
    }
    XCTAssertFalse(
      qualcommOnePlus.isEmpty,
      "Expected early OnePlus entries under Qualcomm VID 0x05c6 (e.g. OnePlus One)")
  }

  func testOnePlusDevicesUnderOPPOVID() {
    // Modern OnePlus models (post-merger) may use OPPO VID 0x22d9
    let oppoOnePlus = db.entries.filter {
      $0.vid == Self.oppoRealmeVID && $0.id.contains("oneplus")
    }
    XCTAssertFalse(
      oppoOnePlus.isEmpty,
      "Expected modern OnePlus entries under OPPO VID 0x22d9 (post-BBK consolidation)")
  }

  // MARK: - No Duplicate PIDs Within Vendor

  func testNoDuplicateXiaomiPIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in xiaomiEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Xiaomi PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateOnePlusPIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in oneplusEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate OnePlus PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Category Validation

  func testXiaomiPhonesAreCategorizedAsPhone() {
    let phones = xiaomiEntries.filter {
      ($0.id.contains("mi-note") || $0.id.contains("mi3") || $0.id.contains("mi2")
        || $0.id.contains("redmi") || $0.id.contains("xiaomi1"))
        && !$0.id.contains("pad") && !$0.id.contains("tab")
    }
    for entry in phones {
      if let cat = entry.category {
        XCTAssertEqual(
          cat, "phone",
          "Xiaomi phone entry '\(entry.id)' should have category 'phone', got '\(cat)'")
      }
    }
  }

  func testXiaomiTabletsAreCategorizedAsTablet() {
    let tablets = xiaomiEntries.filter {
      $0.id.contains("pad") || $0.id.contains("mipad")
    }
    XCTAssertFalse(tablets.isEmpty, "Expected Xiaomi tablet entries (Mi Pad)")
    for entry in tablets {
      if let cat = entry.category {
        XCTAssertEqual(
          cat, "tablet",
          "Xiaomi tablet entry '\(entry.id)' should have category 'tablet', got '\(cat)'")
      }
    }
  }

  func testAllOnePlusEntriesAreCategorizedAsPhone() {
    let phones = oneplusEntries.filter {
      !$0.id.contains("pad") && !$0.id.contains("watch") && !$0.id.contains("buds")
    }
    for entry in phones {
      if let cat = entry.category {
        XCTAssertEqual(
          cat, "phone",
          "OnePlus entry '\(entry.id)' should have category 'phone', got '\(cat)'")
      }
    }
  }

  // MARK: - Xiaomi Mi Note 2 Promoted Entries (Custom USB Modes)

  func testMiNote2FF10Exists() {
    let entry = xiaomiEntries.first { $0.id == "xiaomi-mi-note-2-ff10" }
    XCTAssertNotNil(entry, "Missing Xiaomi Mi Note 2 MTP mode PID 0xff10")
    XCTAssertEqual(entry?.pid, 0xFF10)
    XCTAssertEqual(entry?.status, .promoted, "Mi Note 2 ff10 should be promoted")
  }

  func testMiNote2FF40Exists() {
    let entry = xiaomiEntries.first { $0.id == "xiaomi-mi-note-2-ff40" }
    XCTAssertNotNil(entry, "Missing Xiaomi Mi Note 2 alternate PID 0xff40")
    XCTAssertEqual(entry?.pid, 0xFF40)
    XCTAssertEqual(entry?.status, .promoted, "Mi Note 2 ff40 should be promoted")
  }

  func testMiNote2UsesStandardMTPInterfaceClass() {
    // Mi Note 2 ff10 uses standard MTP interface class 0x06
    let entry = xiaomiEntries.first { $0.id == "xiaomi-mi-note-2-ff10" }
    XCTAssertNotNil(entry)
    if let ifaceClass = entry?.ifaceClass {
      XCTAssertEqual(
        ifaceClass, 0x06,
        "Mi Note 2 ff10 uses standard MTP interface class 0x06, not vendor-specific")
    }
  }

  // MARK: - OnePlus 3T Promoted Entry

  func testOnePlus3TExists() {
    let entry = oneplusEntries.first { $0.id == "oneplus-3t-f003" }
    XCTAssertNotNil(entry, "Missing OnePlus 3T entry PID 0xf003")
    XCTAssertEqual(entry?.pid, 0xF003)
    XCTAssertEqual(entry?.status, .promoted, "OnePlus 3T should be promoted")
  }

  func testOnePlus3TWriteToSubfolderOnly() {
    // OnePlus 3T returns InvalidParameter (0x201D) writing to storage root
    let entry = oneplusEntries.first { $0.id == "oneplus-3t-f003" }
    XCTAssertNotNil(entry)
    let flags = entry!.resolvedFlags()
    XCTAssertTrue(
      flags.writeToSubfolderOnly,
      "OnePlus 3T should have writeToSubfolderOnly due to InvalidParameter on root writes")
  }

  func testOnePlus3THasResetReopenRecovery() {
    // OnePlus 3T uses reset+reopen recovery on OpenSession I/O failures
    let entry = oneplusEntries.first { $0.id == "oneplus-3t-f003" }
    XCTAssertNotNil(entry)
    let flags = entry!.resolvedFlags()
    XCTAssertTrue(
      flags.resetReopenOnOpenSessionIOError,
      "OnePlus 3T should have resetReopenOnOpenSessionIOError for I/O recovery")
  }

  // MARK: - Kernel Detach Requirements

  func testPromotedXiaomiEntriesRequireKernelDetach() {
    let promoted = xiaomiEntries.filter { $0.status == .promoted }
    XCTAssertFalse(promoted.isEmpty, "Expected promoted Xiaomi entries")
    for entry in promoted {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Promoted Xiaomi entry '\(entry.id)' should require kernel detach on macOS")
    }
  }

  func testOnePlusEntriesWithFlagsRequireKernelDetach() {
    // OnePlus devices running OxygenOS/ColorOS need kernel detach on macOS
    let flagged = oneplusEntries.filter { $0.flags != nil }
    for entry in flagged {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "OnePlus entry '\(entry.id)' with explicit flags should require kernel detach")
    }
  }

  func testOPPORealmePhoneEntriesWithFlagsRequireKernelDetach() {
    // Non-phone categories (TV sticks, smart glasses) may not need kernel detach
    let flaggedPhones = oppoRealmeEntries.filter {
      $0.flags != nil && ($0.category == "phone" || $0.category == "tablet")
    }
    for entry in flaggedPhones {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "OPPO/Realme phone entry '\(entry.id)' with explicit flags should require kernel detach")
    }
  }

  // MARK: - Tuning Parameters

  func testXiaomiPromotedEntriesHaveOptimalChunkSize() {
    let promoted = xiaomiEntries.filter { $0.status == .promoted }
    for entry in promoted {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 2_097_152,
          "Promoted Xiaomi entry '\(entry.id)' should use at least 2MB chunks")
      }
    }
  }

  func testChinesePhoneBrandsHaveReasonableChunkSizes() {
    let allEntries = xiaomiEntries + oneplusEntries + oppoRealmeEntries
    for entry in allEntries {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 524_288,
          "Entry '\(entry.id)' chunk size \(chunk) below minimum 512KB")
        XCTAssertLessThanOrEqual(
          chunk, 16_777_216,
          "Entry '\(entry.id)' chunk size \(chunk) exceeds safe 16MB maximum")
      }
    }
  }

  func testPromotedEntriesHaveAdequateTimeouts() {
    let promoted = (xiaomiEntries + oneplusEntries).filter { $0.status == .promoted }
    for entry in promoted {
      if let hsTimeout = entry.handshakeTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          hsTimeout, 5000,
          "Promoted entry '\(entry.id)' handshake timeout \(hsTimeout)ms too low; needs ≥5s")
      }
    }
  }

  func testPromotedEntriesHaveStabilizationDelay() {
    let promoted = (xiaomiEntries + oneplusEntries).filter { $0.status == .promoted }
    for entry in promoted {
      if let stabilize = entry.stabilizeMs {
        XCTAssertGreaterThanOrEqual(
          stabilize, 200,
          "Promoted entry '\(entry.id)' stabilizeMs \(stabilize) too low for Android MTP stack")
      }
    }
  }

  // MARK: - Hooks Validation

  func testPromotedXiaomiEntriesWithHooksHavePostOpenSession() {
    // Not all promoted entries have hooks (e.g. ff40 variant inherits from ff10)
    let promotedWithHooks = xiaomiEntries.filter {
      $0.status == .promoted && $0.hooks != nil
    }
    XCTAssertFalse(promotedWithHooks.isEmpty, "Expected promoted Xiaomi entries with hooks")
    for entry in promotedWithHooks {
      let hasPostOpen = entry.hooks!.contains { $0.phase == .postOpenSession }
      XCTAssertTrue(
        hasPostOpen,
        "Promoted Xiaomi entry '\(entry.id)' should have postOpenSession hook for MIUI MTP readiness")
    }
  }

  func testMiNote2HasStorageBackoff() {
    let entry = xiaomiEntries.first { $0.id == "xiaomi-mi-note-2-ff10" }
    XCTAssertNotNil(entry)
    guard let hooks = entry?.hooks else {
      XCTFail("Mi Note 2 ff10 missing hooks")
      return
    }
    let hasBackoff = hooks.contains {
      $0.phase == .beforeGetStorageIDs && $0.busyBackoff != nil
    }
    XCTAssertTrue(
      hasBackoff,
      "Mi Note 2 ff10 should have beforeGetStorageIDs busy-backoff hook")
  }

  // MARK: - Brand-Specific Notes (JSON validation)

  func testXiaomiNotesReferenceMIUIOrHyperOS() throws {
    // Notes are stored in JSON but not decoded into the Swift model;
    // read JSON directly to validate brand-specific documentation.
    let (_, entries) = try Self.loadQuirksJSON()
    let xiaomiWithNotes = entries.filter { entry in
      let vid = (entry["match"] as? [String: Any])?["vid"] as? String
      let notes = entry["notes"] as? [String]
      return vid == "0x2717" && notes != nil && !notes!.isEmpty
    }
    XCTAssertFalse(
      xiaomiWithNotes.isEmpty, "Expected Xiaomi entries with notes in quirks.json")
    let mentionsMIUI = xiaomiWithNotes.contains { entry in
      let notes = (entry["notes"] as? [String]) ?? []
      return notes.contains { $0.contains("MIUI") || $0.contains("HyperOS") }
    }
    XCTAssertTrue(
      mentionsMIUI,
      "At least one Xiaomi entry's notes should mention MIUI or HyperOS MTP stack")
  }

  func testOnePlusNotesReferenceOxygenOSOrColorOS() throws {
    let (_, entries) = try Self.loadQuirksJSON()
    let oneplusWithNotes = entries.filter { entry in
      let vid = (entry["match"] as? [String: Any])?["vid"] as? String
      let notes = entry["notes"] as? [String]
      return vid == "0x2a70" && notes != nil && !notes!.isEmpty
    }
    XCTAssertFalse(
      oneplusWithNotes.isEmpty, "Expected OnePlus entries with notes in quirks.json")
    let mentionsOS = oneplusWithNotes.contains { entry in
      let notes = (entry["notes"] as? [String]) ?? []
      return notes.contains { $0.contains("OxygenOS") || $0.contains("ColorOS") }
    }
    XCTAssertTrue(
      mentionsOS,
      "At least one OnePlus entry's notes should mention OxygenOS or ColorOS MTP stack")
  }

  func testOPPORealmeNotesReferenceColorOS() throws {
    let (_, entries) = try Self.loadQuirksJSON()
    let oppoWithNotes = entries.filter { entry in
      let vid = (entry["match"] as? [String: Any])?["vid"] as? String
      let notes = entry["notes"] as? [String]
      return vid == "0x22d9" && notes != nil && !notes!.isEmpty
    }
    XCTAssertFalse(
      oppoWithNotes.isEmpty, "Expected OPPO/Realme entries with notes in quirks.json")
    let mentionsColorOS = oppoWithNotes.contains { entry in
      let notes = (entry["notes"] as? [String]) ?? []
      return notes.contains { $0.contains("ColorOS") || $0.contains("Realme UI") }
    }
    XCTAssertTrue(
      mentionsColorOS,
      "At least one OPPO/Realme entry's notes should mention ColorOS or Realme UI")
  }

  // MARK: - Category Distribution

  func testXiaomiHasReasonableCategoryDistribution() {
    let phones = xiaomiEntries.filter { $0.category == "phone" }.count
    let tablets = xiaomiEntries.filter { $0.category == "tablet" }.count

    XCTAssertGreaterThan(phones, 100, "Expected many Xiaomi phone entries")
    XCTAssertGreaterThan(tablets, 5, "Expected Xiaomi tablet entries (Mi Pad series)")
  }

  // MARK: - Helpers

  private static func loadQuirksJSON() throws -> ([String: Any], [[String: Any]]) {
    let candidates = [
      "Specs/quirks.json",
      "../Specs/quirks.json",
      "SwiftMTPKit/Specs/quirks.json",
    ]
    let fm = FileManager.default
    guard let path = candidates.first(where: { fm.fileExists(atPath: $0) }) else {
      throw NSError(
        domain: "Test", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "quirks.json not found"])
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let entries = json["entries"] as! [[String: Any]]
    return (json, entries)
  }
}
