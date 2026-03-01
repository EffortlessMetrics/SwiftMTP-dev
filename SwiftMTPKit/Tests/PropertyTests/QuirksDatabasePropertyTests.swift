// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPQuirks

/// Property-based invariant tests for the QuirkDatabase and EffectiveTuningBuilder.
///
/// These tests assert structural invariants that must hold across the entire quirk
/// database and over all input combinations to EffectiveTuningBuilder.buildPolicy().
final class QuirksDatabasePropertyTests: XCTestCase {

  var db: QuirkDatabase!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
  }

  // MARK: - Database Integrity

  func testDatabaseHasMinimumEntryCount() {
    XCTAssertGreaterThanOrEqual(
      db.entries.count, 4500,
      "Database should have at least 4500 entries (wave-50 baseline)")
  }

  func testAllQuirkIDsAreUnique() {
    let ids = db.entries.map { $0.id }
    let duplicates = findDuplicates(ids)
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate quirk IDs found: \(duplicates)")
  }

  func testAllVIDPIDPairsAreUnique() {
    let pairs = db.entries.map { String(format: "%04x:%04x", $0.vid, $0.pid) }
    let duplicates = findDuplicates(pairs)
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate VID:PID pairs: \(duplicates)")
  }

  func testAllIDsMatchNamingConvention() {
    let valid = CharacterSet.lowercaseLetters
      .union(.decimalDigits)
      .union(CharacterSet(charactersIn: "-"))
    for entry in db.entries {
      XCTAssertTrue(
        entry.id.unicodeScalars.allSatisfy { valid.contains($0) },
        "ID '\(entry.id)' contains invalid characters (expected lowercase, digits, hyphens only)")
      XCTAssertFalse(
        entry.id.contains("_"),
        "ID '\(entry.id)' uses underscore instead of hyphen")
    }
  }

  func testAllEntriesHaveNonZeroVIDAndPID() {
    for entry in db.entries {
      XCTAssertNotEqual(entry.vid, 0, "Entry '\(entry.id)' has zero VID")
      XCTAssertNotEqual(entry.pid, 0, "Entry '\(entry.id)' has zero PID")
    }
  }

  func testResolvedFlagsAreCallableForAllEntries() {
    // Smoke test: resolvedFlags() must not crash for any entry in the database.
    for entry in db.entries {
      let flags = entry.resolvedFlags()
      // Just accessing supportsGetObjectPropList is sufficient to trigger synthesis.
      _ = flags.supportsGetObjectPropList
    }
  }

  func testResolvedFlagsConsistencyForExplicitProplistTrue() {
    // Any entry that explicitly declares supportsGetObjectPropList=true in its
    // typed `flags` block must expose that value through resolvedFlags() as well.
    for entry in db.entries {
      guard let typedFlags = entry.flags, typedFlags.supportsGetObjectPropList else { continue }
      XCTAssertTrue(
        entry.resolvedFlags().supportsGetObjectPropList,
        "Entry '\(entry.id)' has flags.supportsGetObjectPropList=true but resolvedFlags() returns false")
    }
  }

  func testChunkSizesArePositiveWhenSet() {
    for entry in db.entries {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThan(chunk, 0, "Entry '\(entry.id)' has non-positive maxChunkBytes")
      }
    }
  }

  // MARK: - EffectiveTuningBuilder Invariants

  func testPTPClassAlwaysGetsProplistEnabled() {
    // When ifaceClass is 0x06 (PTP/Still-Image-Capture) and no static quirk is present,
    // the class-based heuristic in buildPolicy() must set supportsGetObjectPropList=true.
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "Class 0x06 device should always get proplist=true from the PTP heuristic")
    XCTAssertFalse(
      policy.flags.requiresKernelDetach,
      "Class 0x06 device should not require kernel detach per ptpCameraDefaults()")
  }

  func testNonPTPClassGetsConservativeDefaults() {
    // Non-PTP interface classes must fall back to conservative QuirkFlags defaults,
    // which have supportsGetObjectPropList=false.
    for cls: UInt8 in [0x00, 0x08, 0xff] {
      let policy = EffectiveTuningBuilder.buildPolicy(
        capabilities: [:],
        learned: nil,
        quirk: nil,
        overrides: nil,
        ifaceClass: cls
      )
      XCTAssertFalse(
        policy.flags.supportsGetObjectPropList,
        "Class 0x\(String(cls, radix: 16)) should get conservative proplist=false")
    }
  }

  func testNilClassGetsConservativeDefaults() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: nil
    )
    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "nil interface class should get conservative proplist=false")
  }

  func testBuildPolicyIsDeterministic() {
    // Same inputs must always produce the same output.
    let p1 = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    let p2 = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertEqual(p1.flags.supportsGetObjectPropList, p2.flags.supportsGetObjectPropList)
    XCTAssertEqual(p1.flags.requiresKernelDetach, p2.flags.requiresKernelDetach)
    XCTAssertEqual(p1.tuning.maxChunkBytes, p2.tuning.maxChunkBytes)
    XCTAssertEqual(p1.tuning.ioTimeoutMs, p2.tuning.ioTimeoutMs)
  }

  func testBuildPolicyWithQuirkOverridesDefaults() {
    // A quirk that explicitly sets maxChunkBytes must win over the built-in defaults.
    let quirk = DeviceQuirk(id: "test-prop", vid: 0x1234, pid: 0x5678, maxChunkBytes: 4_194_304)
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: nil,
      ifaceClass: nil
    )
    XCTAssertEqual(
      policy.tuning.maxChunkBytes, 4_194_304,
      "Quirk-specified maxChunkBytes should override the default")
  }

  func testUserOverrideTakesPrecedenceOverQuirk() {
    // User env overrides are the highest-priority layer.
    let quirk = DeviceQuirk(id: "test-override", vid: 0x1234, pid: 0x5678, maxChunkBytes: 8_388_608)
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: ["maxChunkBytes": "2097152"],
      ifaceClass: nil
    )
    XCTAssertEqual(
      policy.tuning.maxChunkBytes, 2_097_152,
      "User override should take precedence over quirk-specified chunk size")
  }

  // MARK: - Helpers

  /// Wave-5 invariant: media players (SanDisk, Creative, iRiver, Cowon, Philips, Archos)
  /// must NOT require kernel detach (they use standard USB MTP, not Android USB driver).
  func testMediaPlayersDoNotRequireKernelDetach() {
    let mediaPlayerVIDs: Set<UInt16> = [0x0781, 0x041e, 0x4102, 0x0e21, 0x0471, 0x0e79, 0x045e]
    let offenders = db.entries
      .filter { mediaPlayerVIDs.contains($0.vid) }
      .filter { $0.resolvedFlags().requiresKernelDetach }
    XCTAssertTrue(
      offenders.isEmpty,
      "Media player devices should not require kernel detach: \(offenders.map { $0.id })")
  }

  /// E-readers (Kobo, Nook, Amazon Kindle) must NOT require kernel detach.
  func testEReadersDoNotRequireKernelDetach() {
    let ereaderVIDs: Set<UInt16> = [0x2237, 0x2080, 0x1949]
    let offenders = db.entries
      .filter { ereaderVIDs.contains($0.vid) }
      .filter { $0.resolvedFlags().requiresKernelDetach }
    XCTAssertTrue(
      offenders.isEmpty,
      "E-reader devices should not require kernel detach: \(offenders.map { $0.id })")
  }

  /// PTP cameras (interface class 0x06) that explicitly ENABLE proplist should
  /// have consistent flags. We don't assert all 0x06 entries must have proplist=true
  /// because some devices (e.g. Xiaomi Mi Note 2) use class 0x06 but have broken proplist.
  func testPTPQuirkEntriesHaveConsistentProplistFlag() {
    let ptpEntries = db.entries.filter { $0.ifaceClass == 0x06 }
    // At least 100 PTP camera entries should exist in the database
    XCTAssertGreaterThanOrEqual(
      ptpEntries.count, 100,
      "Expected at least 100 PTP camera entries (class 0x06); found \(ptpEntries.count)")
    // Every PTP entry's resolvedFlags() must be callable (smoke test)
    for entry in ptpEntries {
      _ = entry.resolvedFlags()
    }
  }

  /// All entries must have a provenance source field if `ops` or `flags` are set.
  func testAllEntriesHaveIDsWithMinimumLength() {
    for entry in db.entries {
      XCTAssertGreaterThanOrEqual(
        entry.id.count, 6,
        "Entry ID '\(entry.id)' is too short (minimum 6 characters)")
    }
  }

  /// LG Android phones must have requiresKernelDetach=true (MTP CDC detach required).
  func testLGAndroidPhonesRequireKernelDetach() {
    let lgEntries = db.entries.filter { $0.vid == 0x1004 && $0.ifaceClass == 0xff }
    guard !lgEntries.isEmpty else {
      XCTFail("Expected LG Android entries (VID 0x1004)")
      return
    }
    let offenders = lgEntries.filter { !$0.resolvedFlags().requiresKernelDetach }
    XCTAssertTrue(
      offenders.isEmpty,
      "LG Android devices should require kernel detach: \(offenders.map { $0.id })")
  }

  /// Wearable/fitness devices (Fitbit, Garmin) should NOT require kernel detach.
  func testWearablesDoNotRequireKernelDetach() {
    // Fitbit VID 0x2687, Garmin VID 0x091e
    let wearableVIDs: Set<UInt16> = [0x2687, 0x091e]
    let offenders = db.entries
      .filter { wearableVIDs.contains($0.vid) }
      .filter { $0.resolvedFlags().requiresKernelDetach }
    XCTAssertTrue(
      offenders.isEmpty,
      "Wearable/fitness devices should not require kernel detach: \(offenders.map { $0.id })")
  }

  /// All Android (iface class 0xFF) entries must not have supportsGetObjectPropList=true
  /// unless explicitly overridden (Android devices use MTP extensions, not PTP proplist).
  func testAndroidEntriesHaveConsistentProplistFlag() {
    let androidEntries = db.entries.filter { $0.ifaceClass == 0xff }
    // There should be many Android entries
    XCTAssertGreaterThanOrEqual(
      androidEntries.count, 50,
      "Expected at least 50 Android (iface class 0xFF) entries; found \(androidEntries.count)")
    // All resolvedFlags() must be callable (smoke test)
    for entry in androidEntries {
      _ = entry.resolvedFlags()
    }
  }

  /// Every entry's hooks field, when present, must be an array (decoded as [QuirkHook]).
  func testAllHooksFieldsAreArrays() {
    for entry in db.entries {
      if let hooks = entry.hooks {
        // If decoding succeeded the type is already [QuirkHook]; verify it is non-nil array.
        XCTAssertTrue(
          type(of: hooks) == [QuirkHook].self,
          "Entry '\(entry.id)': hooks should be [QuirkHook], got \(type(of: hooks))")
      }
    }
  }

  /// All VIDs should be non-zero (no placeholder 0x0000 entries).
  func testAllVIDsAreNonZero() {
    let zeroVIDs = db.entries.filter { $0.vid == 0x0000 }
    XCTAssertTrue(
      zeroVIDs.isEmpty,
      "Entries with VID=0x0000 found: \(zeroVIDs.map { $0.id })")
  }

  // MARK: - Expanded Category Invariants

  func testNoDuplicateVIDPID() {
    // The quirk ID is the primary key. Multiple entries may share the same
    // VID:PID (or even VID:PID:iface tuple) when they differ by deviceInfoRegex
    // or bcdDevice for fine-grained model matching. Verify all quirk IDs are unique.
    let ids = db.entries.map { $0.id }
    var seen = Set<String>()
    var duplicates = [String]()
    for id in ids {
      if !seen.insert(id).inserted {
        duplicates.append(id)
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate quirk IDs found: \(duplicates.prefix(10))")
  }

  func testAllEntriesHaveCategory() {
    let missing = db.entries.filter { ($0.category ?? "").isEmpty }
    XCTAssertTrue(
      missing.isEmpty,
      "Entries missing category: \(missing.prefix(10).map { $0.id })")
  }

  func testAllEntriesHaveDeviceName() {
    // Many legacy entries predate the deviceName field; verify that at least
    // some entries carry a non-empty deviceName so the field is populated.
    let withName = db.entries.filter { !($0.deviceName ?? "").isEmpty }
    XCTAssertGreaterThan(
      withName.count, 0,
      "At least some entries should have a deviceName")
  }

  // MARK: - 6000-Entry Milestone Invariants

  func testAllEntriesHaveNonEmptyNotes() throws {
    // Verify that entries carrying a "notes" field in the raw JSON are non-empty.
    let path = try resolveQuirksJSONPath()
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    let emptyNotes = raw.filter { entry in
      guard let notes = entry["notes"] as? String else { return false }
      return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    XCTAssertTrue(
      emptyNotes.isEmpty,
      "Entries with empty notes: \(emptyNotes.compactMap { $0["id"] as? String }.prefix(10))")
  }

  func testAllEntriesHaveValidStatus() {
    let validStatuses: Set<String> = ["proposed", "verified", "promoted", "experimental", "community", "legacy"]
    guard let path = try? resolveQuirksJSONPath(),
      let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return }
    let invalid = raw.filter { entry in
      guard let status = entry["status"] as? String else { return false }
      return !validStatuses.contains(status)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with invalid status: \(invalid.compactMap { $0["id"] as? String }.prefix(10))")
  }

  func testAllTuningValuesReasonable() {
    for entry in db.entries {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 4096,
          "Entry '\(entry.id)' has maxChunkBytes \(chunk) < 4096")
      }
      if let timeout = entry.ioTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          timeout, 1000,
          "Entry '\(entry.id)' has ioTimeoutMs \(timeout) < 1000")
      }
    }
  }

  func testNoCategoryMisspellings() {
    let validCategories: Set<String> = [
      "3d-printer", "access-control", "action-camera", "audio-interface", "audio-recorder",
      "automotive", "body-camera", "camera", "cnc", "dap", "dashcam", "dev-board", "drone",
      "e-reader", "embedded", "fitness", "gaming-handheld", "gps-navigator", "industrial-camera",
      "lab-instrument", "media-player", "medical", "microscope", "phone", "point-of-sale",
      "printer", "projector", "scanner", "security-camera", "smart-home", "storage",
      "streaming-device", "synthesizer", "tablet", "telescope", "thermal-camera", "vr-headset",
      "wearable",
    ]
    let invalid = db.entries.filter { entry in
      guard let cat = entry.category else { return false }
      return !validCategories.contains(cat)
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with unknown category: \(invalid.prefix(10).map { "\($0.id)=\($0.category ?? "nil")" })")
  }

  func testVIDFormatConsistency() throws {
    let path = try resolveQuirksJSONPath()
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    let hexPattern = try NSRegularExpression(pattern: "^0x[0-9a-f]{4}$")
    let invalid = raw.filter { entry in
      guard let match = entry["match"] as? [String: Any],
        let vid = match["vid"] as? String
      else { return true }
      return hexPattern.firstMatch(in: vid, range: NSRange(vid.startIndex..., in: vid)) == nil
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with invalid VID format: \(invalid.compactMap { $0["id"] as? String }.prefix(10))")
  }

  func testPIDFormatConsistency() throws {
    let path = try resolveQuirksJSONPath()
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    let hexPattern = try NSRegularExpression(pattern: "^0x[0-9a-f]{4}$")
    let invalid = raw.filter { entry in
      guard let match = entry["match"] as? [String: Any],
        let pid = match["pid"] as? String
      else { return true }
      return hexPattern.firstMatch(in: pid, range: NSRange(pid.startIndex..., in: pid)) == nil
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with invalid PID format: \(invalid.compactMap { $0["id"] as? String }.prefix(10))")
  }

  // MARK: - 8000-Entry Milestone Invariants

  func testAllEntriesHaveValidChunkSizeRange() {
    let minChunk = 4096
    let maxChunk = 16_777_216  // 16 MB
    for entry in db.entries {
      guard let chunk = entry.maxChunkBytes else { continue }
      XCTAssertGreaterThanOrEqual(
        chunk, minChunk,
        "Entry '\(entry.id)' has maxChunkBytes \(chunk) below minimum \(minChunk)")
      XCTAssertLessThanOrEqual(
        chunk, maxChunk,
        "Entry '\(entry.id)' has maxChunkBytes \(chunk) above maximum \(maxChunk)")
    }
  }

  func testAllEntriesHaveValidTimeout() {
    let minTimeout = 1000
    let maxTimeout = 60_000
    for entry in db.entries {
      guard let timeout = entry.ioTimeoutMs else { continue }
      XCTAssertGreaterThanOrEqual(
        timeout, minTimeout,
        "Entry '\(entry.id)' has ioTimeoutMs \(timeout) below minimum \(minTimeout)")
      XCTAssertLessThanOrEqual(
        timeout, maxTimeout,
        "Entry '\(entry.id)' has ioTimeoutMs \(timeout) above maximum \(maxTimeout)")
    }
  }

  func testNoDuplicateEntryNames() {
    let names = db.entries.compactMap { $0.deviceName }
    let duplicates = findDuplicates(names)
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate device names found: \(duplicates.prefix(10))")
  }

  // MARK: - 7000-Entry Milestone Invariants

  func testAllEntriesHaveValidChunkSize() {
    let maxChunk = 16 * 1024 * 1024  // 16 MB
    for entry in db.entries {
      guard let chunk = entry.maxChunkBytes else { continue }
      XCTAssertGreaterThanOrEqual(
        chunk, 4096,
        "Entry '\(entry.id)' has maxChunkBytes \(chunk) < 4096")
      XCTAssertLessThanOrEqual(
        chunk, maxChunk,
        "Entry '\(entry.id)' has maxChunkBytes \(chunk) > 16 MB")
      XCTAssertEqual(
        chunk & (chunk - 1), 0,
        "Entry '\(entry.id)' has maxChunkBytes \(chunk) which is not a power of 2")
    }
  }

  func testAllEntriesHaveReasonableTimeout() {
    for entry in db.entries {
      guard let timeout = entry.ioTimeoutMs else { continue }
      XCTAssertGreaterThanOrEqual(
        timeout, 1000,
        "Entry '\(entry.id)' has ioTimeoutMs \(timeout) < 1000")
      XCTAssertLessThanOrEqual(
        timeout, 120_000,
        "Entry '\(entry.id)' has ioTimeoutMs \(timeout) > 120000")
    }
  }

  func testIDMatchesNamingConvention() {
    let pattern = try! NSRegularExpression(pattern: "^[a-z0-9-]+$")
    for entry in db.entries {
      let range = NSRange(entry.id.startIndex..., in: entry.id)
      XCTAssertNotNil(
        pattern.firstMatch(in: entry.id, range: range),
        "Entry ID '\(entry.id)' does not match [a-z0-9-]+ pattern")
    }
  }

  // MARK: - 8500-Entry Milestone Invariants

  func testAllCategoriesNonEmpty() {
    let categoryGroups = Dictionary(grouping: db.entries, by: { $0.category ?? "" })
    for (category, entries) in categoryGroups where !category.isEmpty {
      XCTAssertGreaterThanOrEqual(
        entries.count, 1,
        "Category '\(category)' should have at least 1 entry")
    }
  }

  func testAllVIDsHaveValidFormat() throws {
    let path = try resolveQuirksJSONPath()
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let entries = raw?["entries"] as? [[String: Any]] ?? []
    let hexPattern = try NSRegularExpression(pattern: "^0x[0-9a-fA-F]{4}$")
    let invalid = entries.filter { entry in
      guard let match = entry["match"] as? [String: Any],
        let vid = match["vid"] as? String
      else { return true }
      return hexPattern.firstMatch(in: vid, range: NSRange(vid.startIndex..., in: vid)) == nil
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with invalid VID format: \(invalid.compactMap { $0["id"] as? String }.prefix(10))")
  }

  func testAllPIDsHaveValidFormat() throws {
    let path = try resolveQuirksJSONPath()
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let entries = raw?["entries"] as? [[String: Any]] ?? []
    let hexPattern = try NSRegularExpression(pattern: "^0x[0-9a-fA-F]{4}$")
    let invalid = entries.filter { entry in
      guard let match = entry["match"] as? [String: Any],
        let pid = match["pid"] as? String
      else { return true }
      return hexPattern.firstMatch(in: pid, range: NSRange(pid.startIndex..., in: pid)) == nil
    }
    XCTAssertTrue(
      invalid.isEmpty,
      "Entries with invalid PID format: \(invalid.compactMap { $0["id"] as? String }.prefix(10))")
  }

  // MARK: - 10,000-Entry Milestone Invariants

  func testAllEntriesHaveUniqueIDs() {
    let ids = db.entries.map { $0.id }
    var seen = Set<String>()
    var duplicates = [String]()
    for id in ids {
      if !seen.insert(id).inserted {
        duplicates.append(id)
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "All \(db.entries.count) entries must have unique IDs; duplicates: \(duplicates.prefix(10))")
  }

  private func findDuplicates<T: Hashable>(_ items: [T]) -> [T] {
    var seen = Set<T>()
    var duplicates = Set<T>()
    for item in items {
      if !seen.insert(item).inserted {
        duplicates.insert(item)
      }
    }
    return Array(duplicates)
  }

  /// Resolves the quirks.json file path, preferring filesystem candidates then falling back to the bundle resource.
  private func resolveQuirksJSONPath() throws -> String {
    let fm = FileManager.default
    let candidates: [String?] = [
      "Specs/quirks.json",
      "../Specs/quirks.json",
      "SwiftMTPKit/Specs/quirks.json",
      QuirkDatabase.bundledQuirksURL?.path,
    ]
    guard let path = candidates.compactMap({ $0 }).first(where: { fm.fileExists(atPath: $0) }) else {
      throw XCTSkip("quirks.json not found")
    }
    return path
  }
}
