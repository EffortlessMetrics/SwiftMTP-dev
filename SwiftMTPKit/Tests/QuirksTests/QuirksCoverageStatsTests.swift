// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

final class QuirksCoverageStatsTests: XCTestCase {

  // MARK: - Helpers

  private func makeEntry(
    id: String,
    vid: UInt16 = 0x1234,
    pid: UInt16 = 0x5678,
    category: String? = nil,
    flags: QuirkFlags? = nil,
    status: QuirkStatus? = nil,
    confidence: String? = nil,
    evidenceRequired: [String]? = nil
  ) -> DeviceQuirk {
    DeviceQuirk(
      id: id, category: category, vid: vid, pid: pid,
      flags: flags, status: status, confidence: confidence,
      evidenceRequired: evidenceRequired
    )
  }

  // MARK: - Empty database

  func testEmptyDatabaseStats() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let stats = db.coverageStats()

    XCTAssertEqual(stats.totalEntries, 0)
    XCTAssertEqual(stats.uniqueVIDs, 0)
    XCTAssertTrue(stats.categoryCounts.isEmpty)
    XCTAssertTrue(stats.flagUsage.isEmpty)
    XCTAssertEqual(stats.testedCount, 0)
    XCTAssertEqual(stats.untestedCount, 0)
    XCTAssertEqual(stats.withEvidence, 0)
    XCTAssertEqual(stats.withoutEvidence, 0)
  }

  // MARK: - Category counts

  func testCategoryCountsGroupCorrectly() {
    let entries = [
      makeEntry(id: "a", category: "phone"),
      makeEntry(id: "b", category: "phone"),
      makeEntry(id: "c", category: "camera"),
      makeEntry(id: "d", category: nil),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.categoryCounts["phone"], 2)
    XCTAssertEqual(stats.categoryCounts["camera"], 1)
    XCTAssertEqual(stats.categoryCounts["uncategorized"], 1)
  }

  func testTopCategoriesLimitsCount() {
    var entries: [DeviceQuirk] = []
    for i in 0..<15 {
      entries.append(makeEntry(id: "e\(i)", pid: UInt16(i), category: "cat\(i)"))
    }
    // Add extra entries to cat0 so it sorts first
    entries.append(makeEntry(id: "extra1", pid: 100, category: "cat0"))
    entries.append(makeEntry(id: "extra2", pid: 101, category: "cat0"))

    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    let top5 = stats.topCategories(5)
    XCTAssertEqual(top5.count, 5)
    XCTAssertEqual(top5.first?.category, "cat0")
    XCTAssertEqual(top5.first?.count, 3)
  }

  // MARK: - Flag usage

  func testFlagUsageCountsNonDefaultFlags() {
    var flagsA = QuirkFlags()
    flagsA.resetOnOpen = true
    flagsA.skipAltSetting = true

    var flagsB = QuirkFlags()
    flagsB.resetOnOpen = true
    flagsB.noZeroReads = true

    let entries = [
      makeEntry(id: "a", pid: 1, flags: flagsA),
      makeEntry(id: "b", pid: 2, flags: flagsB),
      makeEntry(id: "c", pid: 3),  // all defaults
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.flagUsage["resetOnOpen"], 2)
    XCTAssertEqual(stats.flagUsage["skipAltSetting"], 1)
    XCTAssertEqual(stats.flagUsage["noZeroReads"], 1)
    XCTAssertNil(stats.flagUsage["ignoreHeaderErrors"])
  }

  func testUnusedFlagsReturnsCorrectList() {
    var flagsA = QuirkFlags()
    flagsA.resetOnOpen = true

    let entries = [makeEntry(id: "a", flags: flagsA)]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    // resetOnOpen is used, so it shouldn't be in unused
    XCTAssertFalse(stats.unusedFlags.contains("resetOnOpen"))
    // Most flags should be unused since only one is set
    XCTAssertTrue(stats.unusedFlags.count > 30)
    XCTAssertTrue(stats.unusedFlags.contains("ignoreHeaderErrors"))
  }

  // MARK: - Status breakdown

  func testStatusBreakdown() {
    let entries = [
      makeEntry(id: "a", pid: 1, status: .promoted),
      makeEntry(id: "b", pid: 2, status: .verified),
      makeEntry(id: "c", pid: 3, status: .proposed),
      makeEntry(id: "d", pid: 4, status: nil),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.statusCounts["promoted"], 1)
    XCTAssertEqual(stats.statusCounts["verified"], 1)
    XCTAssertEqual(stats.statusCounts["proposed"], 2)  // nil defaults to "proposed"
  }

  // MARK: - Validation (evidence)

  func testEvidenceCountsAreCorrect() {
    let entries = [
      makeEntry(id: "a", pid: 1, evidenceRequired: ["probe_log"]),
      makeEntry(id: "b", pid: 2, evidenceRequired: []),
      makeEntry(id: "c", pid: 3, evidenceRequired: nil),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.withEvidence, 1)
    XCTAssertEqual(stats.withoutEvidence, 2)
  }

  // MARK: - Testing status

  func testTestedVsUntested() {
    let entries = [
      makeEntry(id: "tested", pid: 1, status: .promoted),
      makeEntry(id: "research1", pid: 2, status: .proposed),
      makeEntry(id: "research2", pid: 3, status: nil),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.testedCount, 1)
    XCTAssertEqual(stats.untestedCount, 2)
  }

  // MARK: - VID analysis

  func testUniqueVIDsAndTopVIDs() {
    let entries = [
      makeEntry(id: "a", vid: 0x18d1, pid: 1),
      makeEntry(id: "b", vid: 0x18d1, pid: 2),
      makeEntry(id: "c", vid: 0x18d1, pid: 3),
      makeEntry(id: "d", vid: 0x04e8, pid: 4),
      makeEntry(id: "e", vid: 0x04e8, pid: 5),
      makeEntry(id: "f", vid: 0x2717, pid: 6),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.uniqueVIDs, 3)
    XCTAssertEqual(stats.topVIDs.count, 3)
    XCTAssertEqual(stats.topVIDs.first?.vid, 0x18d1)
    XCTAssertEqual(stats.topVIDs.first?.count, 3)
    XCTAssertEqual(stats.topVIDs.first?.formatted, "0x18d1")
  }

  // MARK: - Confidence breakdown

  func testConfidenceBreakdown() {
    let entries = [
      makeEntry(id: "a", pid: 1, confidence: "high"),
      makeEntry(id: "b", pid: 2, confidence: "low"),
      makeEntry(id: "c", pid: 3, confidence: nil),
    ]
    let db = QuirkDatabase(schemaVersion: "1.0", entries: entries)
    let stats = db.coverageStats()

    XCTAssertEqual(stats.confidenceCounts["high"], 1)
    XCTAssertEqual(stats.confidenceCounts["low"], 1)
    XCTAssertEqual(stats.confidenceCounts["unspecified"], 1)
  }

  // MARK: - boolFlagMap

  func testBoolFlagMapReturnsAllFlags() {
    let flags = QuirkFlags()
    let map = flags.boolFlagMap
    // Should have all boolean flags
    XCTAssertTrue(map.count >= 40, "Expected at least 40 boolean flags, got \(map.count)")
    // Check a few known names
    let names = Set(map.map(\.name))
    XCTAssertTrue(names.contains("resetOnOpen"))
    XCTAssertTrue(names.contains("requiresKernelDetach"))
    XCTAssertTrue(names.contains("cameraClass"))
    XCTAssertTrue(names.contains("supportsGetObjectPropList"))
  }

  func testBoolFlagMapReflectsValues() {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.cameraClass = true

    let map = Dictionary(uniqueKeysWithValues: flags.boolFlagMap)
    XCTAssertEqual(map["resetOnOpen"], true)
    XCTAssertEqual(map["cameraClass"], true)
    XCTAssertEqual(map["ignoreHeaderErrors"], false)
  }
}
