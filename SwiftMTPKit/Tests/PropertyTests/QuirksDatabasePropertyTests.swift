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
      db.entries.count, 222,
      "Database should have at least 222 entries")
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
}
