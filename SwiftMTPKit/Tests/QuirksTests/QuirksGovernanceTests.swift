// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

// MARK: - Status Transition Validation

final class StatusTransitionTests: XCTestCase {

  func testProposedIsLowestStatus() {
    let quirk = DeviceQuirk(id: "t1", vid: 1, pid: 1, status: .proposed)
    XCTAssertEqual(quirk.status, .proposed)
  }

  func testVerifiedIsIntermediateStatus() {
    let quirk = DeviceQuirk(id: "t2", vid: 1, pid: 1, status: .verified)
    XCTAssertEqual(quirk.status, .verified)
  }

  func testPromotedIsHighestStatus() {
    let quirk = DeviceQuirk(id: "t3", vid: 1, pid: 1, status: .promoted)
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testStatusTransitionProposedToVerified() {
    var quirk = DeviceQuirk(id: "t4", vid: 1, pid: 1, status: .proposed)
    quirk.status = .verified
    XCTAssertEqual(quirk.status, .verified)
  }

  func testStatusTransitionVerifiedToPromoted() {
    var quirk = DeviceQuirk(id: "t5", vid: 1, pid: 1, status: .verified)
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testStatusTransitionFullLifecycle() {
    var quirk = DeviceQuirk(id: "t6", vid: 1, pid: 1, status: .proposed)
    XCTAssertEqual(quirk.status, .proposed)
    quirk.status = .verified
    XCTAssertEqual(quirk.status, .verified)
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testLegacyStatusesFallBackToProposed() throws {
    for legacy in ["stable", "experimental", "blocked", "community", "legacy", "unknown", ""] {
      let json = Data("\"\(legacy)\"".utf8)
      let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
      XCTAssertEqual(decoded, .proposed, "Legacy status '\(legacy)' should decode as .proposed")
    }
  }

  func testNilStatusIsAllowed() {
    let quirk = DeviceQuirk(id: "t7", vid: 1, pid: 1)
    XCTAssertNil(quirk.status)
  }
}

// MARK: - Evidence Requirements

final class EvidenceRequirementTests: XCTestCase {

  func testPromotedEntriesHaveEvidence() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    XCTAssertFalse(promoted.isEmpty, "Database should contain promoted entries")
    for entry in promoted {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Promoted entry '\(entry.id)' must declare evidenceRequired")
      if let evidence = entry.evidenceRequired {
        XCTAssertFalse(
          evidence.isEmpty,
          "Promoted entry '\(entry.id)' must have at least one evidence item")
        XCTAssertTrue(
          evidence.contains("probe_log"),
          "Promoted entry '\(entry.id)' must require probe_log evidence")
      }
    }
  }

  func testVerifiedEntriesHaveEvidence() throws {
    let db = try QuirkDatabase.load()
    let verified = db.entries.filter { $0.status == .verified }
    for entry in verified {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Verified entry '\(entry.id)' should declare evidenceRequired")
    }
  }

  func testEvidenceFieldsRoundTrip() throws {
    let json = """
      {
        "id": "evidence-test",
        "match": { "vid": "0xAAAA", "pid": "0xBBBB" },
        "status": "promoted",
        "confidence": "high",
        "evidenceRequired": ["probe_log", "write_test", "bench_100m"],
        "lastVerifiedDate": "2025-01-15",
        "lastVerifiedBy": "device-lab-ci"
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.evidenceRequired, ["probe_log", "write_test", "bench_100m"])
    XCTAssertEqual(quirk.lastVerifiedDate, "2025-01-15")
    XCTAssertEqual(quirk.lastVerifiedBy, "device-lab-ci")
  }

  func testConfidenceLevelsDeserialize() throws {
    for level in ["low", "medium", "high"] {
      let json = """
        {
          "id": "conf-\(level)",
          "match": { "vid": "0x0001", "pid": "0x0002" },
          "confidence": "\(level)"
        }
        """
      let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
      XCTAssertEqual(quirk.confidence, level)
    }
  }
}

// MARK: - Matching Priority

final class MatchingPriorityTests: XCTestCase {

  func testSpecificVIDPIDBeatsCategoryWildcard() {
    let specific = DeviceQuirk(id: "specific", vid: 0x1234, pid: 0x5678, ifaceClass: 0x06)
    let generic = DeviceQuirk(id: "generic", vid: 0x1234, pid: 0x5678)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [generic, specific])

    let result = db.match(
      vid: 0x1234, pid: 0x5678,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "specific", "Specific interface class match should win")
  }

  func testBCDDeviceAddsSpecificity() {
    let withBCD = DeviceQuirk(id: "bcd", vid: 0x10, pid: 0x20, bcdDevice: 0x0200)
    let noBCD = DeviceQuirk(id: "no-bcd", vid: 0x10, pid: 0x20)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [noBCD, withBCD])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: 0x0200, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "bcd", "BCD match should be more specific")
  }

  func testFullInterfaceMatchBeatsPartial() {
    let full = DeviceQuirk(
      id: "full", vid: 0x10, pid: 0x20,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let classOnly = DeviceQuirk(id: "class", vid: 0x10, pid: 0x20, ifaceClass: 0x06)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [classOnly, full])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertEqual(result?.id, "full")
  }

  func testFirstEntryWinsOnTiedScore() {
    let a = DeviceQuirk(id: "first", vid: 0x10, pid: 0x20)
    let b = DeviceQuirk(id: "second", vid: 0x10, pid: 0x20)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [a, b])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(result, "Should match one of the tied entries")
  }
}

// MARK: - Default Profile Fallback

final class DefaultProfileFallbackTests: XCTestCase {

  func testNoQuirkNoLearnedReturnsDefaults() {
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil)
    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(result.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(result.ioTimeoutMs, defaults.ioTimeoutMs)
    XCTAssertEqual(result.handshakeTimeoutMs, defaults.handshakeTimeoutMs)
    XCTAssertFalse(result.resetOnOpen)
    XCTAssertFalse(result.disableEventPump)
  }

  func testPTPCameraClassFallback() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.prefersPropListEnumeration)
    XCTAssertTrue(policy.flags.supportsPartialRead32)
  }

  func testNonCameraClassUsesDefaultFlags() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0xFF)
    let defaultFlags = QuirkFlags()
    XCTAssertEqual(policy.flags, defaultFlags)
  }

  func testPolicySourcesReflectDefaults() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .defaults)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .defaults)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
  }
}

// MARK: - Learned Profile Merge

final class LearnedProfileMergeTests: XCTestCase {

  func testLearnedValuesAppliedWithoutQuirk() {
    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 2 * 1024 * 1024
    learned.ioTimeoutMs = 12000
    learned.stabilizeMs = 300

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: nil, overrides: nil)
    XCTAssertEqual(result.maxChunkBytes, 2 * 1024 * 1024)
    XCTAssertEqual(result.ioTimeoutMs, 12000)
    XCTAssertEqual(result.stabilizeMs, 300)
  }

  func testStaticQuirkOverridesLearned() {
    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 4 * 1024 * 1024

    let quirk = DeviceQuirk(id: "q", vid: 1, pid: 1, maxChunkBytes: 512 * 1024)
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
    XCTAssertEqual(result.maxChunkBytes, 512 * 1024)
  }

  func testUserOverridesOverrideQuirkAndLearned() {
    var learned = EffectiveTuning.defaults()
    learned.ioTimeoutMs = 5000
    let quirk = DeviceQuirk(id: "q", vid: 1, pid: 1, ioTimeoutMs: 3000)
    let overrides = ["ioTimeoutMs": "20000"]

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: quirk, overrides: overrides)
    XCTAssertEqual(result.ioTimeoutMs, 20000)
  }

  func testPolicySourcesReflectLearned() {
    let learned = EffectiveTuning.defaults()
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: learned, quirk: nil, overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .learned)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .learned)
  }
}

// MARK: - Serialization Round-Trip

final class GovernanceSerializationTests: XCTestCase {

  func testDeviceQuirkWithGovernanceFieldsRoundTrip() throws {
    let json = """
      {
        "id": "gov-rt",
        "match": { "vid": "0xDEAD", "pid": "0xBEEF" },
        "status": "verified",
        "confidence": "medium",
        "evidenceRequired": ["probe_log", "write_test"],
        "lastVerifiedDate": "2025-06-01",
        "lastVerifiedBy": "test-lab"
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.status, .verified)
    XCTAssertEqual(quirk.confidence, "medium")
    XCTAssertEqual(quirk.evidenceRequired, ["probe_log", "write_test"])
    XCTAssertEqual(quirk.lastVerifiedDate, "2025-06-01")
    XCTAssertEqual(quirk.lastVerifiedBy, "test-lab")
  }

  func testQuirkDatabaseWithMixedStatusesDecodes() throws {
    let json = """
      {
        "schemaVersion": "1.0",
        "entries": [
          { "id": "e1", "match": { "vid": "0x0001", "pid": "0x0001" }, "status": "proposed" },
          { "id": "e2", "match": { "vid": "0x0002", "pid": "0x0002" }, "status": "verified" },
          { "id": "e3", "match": { "vid": "0x0003", "pid": "0x0003" }, "status": "promoted" },
          { "id": "e4", "match": { "vid": "0x0004", "pid": "0x0004" }, "status": "experimental" }
        ]
      }
      """
    let db = try JSONDecoder().decode(QuirkDatabase.self, from: Data(json.utf8))
    XCTAssertEqual(db.entries.count, 4)
    XCTAssertEqual(db.entries[0].status, .proposed)
    XCTAssertEqual(db.entries[1].status, .verified)
    XCTAssertEqual(db.entries[2].status, .promoted)
    XCTAssertEqual(db.entries[3].status, .proposed, "Legacy 'experimental' decodes as .proposed")
  }

  func testQuirkStatusEncodesCanonicalRawValues() throws {
    let encoder = JSONEncoder()
    for (status, expected) in [
      (QuirkStatus.proposed, "\"proposed\""),
      (QuirkStatus.verified, "\"verified\""),
      (QuirkStatus.promoted, "\"promoted\""),
    ] {
      let data = try encoder.encode(status)
      XCTAssertEqual(String(data: data, encoding: .utf8), expected)
    }
  }
}

// MARK: - Category Validation

final class GovernanceCategoryValidationTests: XCTestCase {

  func testAllBundledEntriesHaveValidCategories() throws {
    let db = try QuirkDatabase.load()
    let validCategories: Set<String> = [
      "phone", "camera", "tablet", "media-player", "drone",
      "action-camera", "gps-navigator", "e-reader", "audio-player",
      "scanner", "gaming-handheld", "wearable", "storage", "dashcam",
      "audio-recorder", "printer", "vr-headset", "dev-board",
      "thermal-camera", "automotive", "streaming-device", "embedded",
      "audio-interface", "lab-instrument", "3d-printer", "medical",
      "cnc", "smart-home", "fitness", "microscope", "telescope",
      "body-camera", "industrial-camera", "point-of-sale", "synthesizer",
      "projector", "security-camera", "access-control",
    ]
    for entry in db.entries {
      if let cat = entry.category {
        XCTAssertFalse(cat.isEmpty, "Entry '\(entry.id)' has empty category")
        XCTAssertTrue(
          validCategories.contains(cat),
          "Entry '\(entry.id)' has unknown category '\(cat)'")
      }
    }
  }

  func testCategoriesAreKebabCase() throws {
    let db = try QuirkDatabase.load()
    let categories = Set(db.entries.compactMap(\.category))
    let kebabCasePattern = try NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
    for cat in categories {
      let range = NSRange(cat.startIndex..., in: cat)
      XCTAssertTrue(
        kebabCasePattern.firstMatch(in: cat, range: range) != nil,
        "Category '\(cat)' is not valid kebab-case")
    }
  }
}

// MARK: - VID:PID Uniqueness

final class VIDPIDUniquenessTests: XCTestCase {

  func testBundledDatabaseHasUniqueVIDPIDPairs() throws {
    let db = try QuirkDatabase.load()
    var seen = Set<String>()
    for entry in db.entries {
      let key = String(format: "%04x:%04x", entry.vid, entry.pid)
      XCTAssertFalse(
        seen.contains(key),
        "Duplicate VID:PID \(key) found for entry '\(entry.id)'")
      seen.insert(key)
    }
  }

  func testBundledDatabaseHasUniqueIDs() throws {
    let db = try QuirkDatabase.load()
    var seen = Set<String>()
    for entry in db.entries {
      XCTAssertFalse(
        seen.contains(entry.id),
        "Duplicate quirk ID '\(entry.id)'")
      seen.insert(entry.id)
    }
  }
}

// MARK: - Transport Configuration Validation

final class TransportConfigValidationTests: XCTestCase {

  func testTuningClampingLowerBounds() {
    let quirk = DeviceQuirk(
      id: "low", vid: 1, pid: 1,
      maxChunkBytes: 1, ioTimeoutMs: 1, handshakeTimeoutMs: 1,
      inactivityTimeoutMs: 1, overallDeadlineMs: 1)
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertGreaterThanOrEqual(result.maxChunkBytes, 128 * 1024)
    XCTAssertGreaterThanOrEqual(result.ioTimeoutMs, 1000)
    XCTAssertGreaterThanOrEqual(result.handshakeTimeoutMs, 1000)
    XCTAssertGreaterThanOrEqual(result.inactivityTimeoutMs, 1000)
    XCTAssertGreaterThanOrEqual(result.overallDeadlineMs, 5000)
  }

  func testTuningClampingUpperBounds() {
    let quirk = DeviceQuirk(
      id: "high", vid: 1, pid: 1,
      maxChunkBytes: 100_000_000, ioTimeoutMs: 999_999,
      handshakeTimeoutMs: 999_999, inactivityTimeoutMs: 999_999,
      overallDeadlineMs: 999_999_999)
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertLessThanOrEqual(result.maxChunkBytes, 16 * 1024 * 1024)
    XCTAssertLessThanOrEqual(result.ioTimeoutMs, 60000)
    XCTAssertLessThanOrEqual(result.handshakeTimeoutMs, 60000)
    XCTAssertLessThanOrEqual(result.inactivityTimeoutMs, 60000)
    XCTAssertLessThanOrEqual(result.overallDeadlineMs, 300000)
  }

  func testStabilizeMsClampedToRange() {
    let low = DeviceQuirk(id: "stab-low", vid: 1, pid: 1, stabilizeMs: -100)
    let high = DeviceQuirk(id: "stab-high", vid: 1, pid: 1, stabilizeMs: 99999)
    let resultLow = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: low, overrides: nil)
    let resultHigh = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: high, overrides: nil)
    XCTAssertGreaterThanOrEqual(resultLow.stabilizeMs, 0)
    XCTAssertLessThanOrEqual(resultHigh.stabilizeMs, 5000)
  }

  func testBundledEntriesHaveNonZeroVIDPID() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries {
      XCTAssertNotEqual(entry.vid, 0, "Entry '\(entry.id)' has zero VID")
      XCTAssertNotEqual(entry.pid, 0, "Entry '\(entry.id)' has zero PID")
    }
  }

  func testBundledEntriesHaveNonEmptyIDs() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries {
      XCTAssertFalse(entry.id.isEmpty, "Quirk ID must not be empty")
      XCTAssertFalse(
        entry.id.contains(" "),
        "Quirk ID '\(entry.id)' should not contain spaces")
    }
  }
}

// MARK: - Governance Level Classification

final class GovernanceLevelTests: XCTestCase {

  func testPromotedEntryClassifiesAsPromoted() {
    let q = DeviceQuirk(id: "p1", vid: 1, pid: 1, status: .promoted)
    XCTAssertEqual(QuirkGovernanceLevel.classify(q), .promoted)
  }

  func testVerifiedEntryClassifiesAsResearch() {
    let q = DeviceQuirk(id: "v1", vid: 1, pid: 1, status: .verified)
    XCTAssertEqual(QuirkGovernanceLevel.classify(q), .research)
  }

  func testProposedEntryClassifiesAsResearch() {
    let q = DeviceQuirk(id: "r1", vid: 1, pid: 1, status: .proposed)
    XCTAssertEqual(QuirkGovernanceLevel.classify(q), .research)
  }

  func testNilStatusClassifiesAsResearch() {
    let q = DeviceQuirk(id: "n1", vid: 1, pid: 1)
    XCTAssertEqual(QuirkGovernanceLevel.classify(q), .research)
  }
}

// MARK: - Database Governance Queries

final class DatabaseGovernanceQueryTests: XCTestCase {

  func testTestedDevicesReturnsOnlyPromoted() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "a", vid: 1, pid: 1, status: .promoted),
      DeviceQuirk(id: "b", vid: 2, pid: 2, status: .verified),
      DeviceQuirk(id: "c", vid: 3, pid: 3, status: .proposed),
      DeviceQuirk(id: "d", vid: 4, pid: 4),
    ])
    let tested = db.testedDevices()
    XCTAssertEqual(tested.count, 1)
    XCTAssertEqual(tested.first?.id, "a")
  }

  func testResearchEntriesExcludesPromoted() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "a", vid: 1, pid: 1, status: .promoted),
      DeviceQuirk(id: "b", vid: 2, pid: 2, status: .verified),
      DeviceQuirk(id: "c", vid: 3, pid: 3, status: .proposed),
    ])
    let research = db.researchEntries()
    XCTAssertEqual(research.count, 2)
    XCTAssertTrue(research.contains(where: { $0.id == "b" }))
    XCTAssertTrue(research.contains(where: { $0.id == "c" }))
  }

  func testGovernanceSummaryCountsLevels() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "a", vid: 1, pid: 1, status: .promoted),
      DeviceQuirk(id: "b", vid: 2, pid: 2, status: .promoted),
      DeviceQuirk(id: "c", vid: 3, pid: 3, status: .proposed),
    ])
    let summary = db.governanceSummary()
    XCTAssertEqual(summary[.promoted], 2)
    XCTAssertEqual(summary[.research], 1)
  }

  func testValidateGovernancePassesForValidDatabase() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "a", vid: 1, pid: 1, status: .promoted, evidenceRequired: ["probe_log"]),
      DeviceQuirk(id: "b", vid: 2, pid: 2, status: .proposed),
    ])
    let result = db.validateGovernance()
    XCTAssertTrue(result.isValid)
    XCTAssertTrue(result.violations.isEmpty)
  }

  func testValidateGovernanceFailsWhenPromotedMissingEvidence() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "bad", vid: 1, pid: 1, status: .promoted),
    ])
    let result = db.validateGovernance()
    XCTAssertFalse(result.isValid)
    XCTAssertEqual(result.violations.count, 1)
    XCTAssertTrue(result.violations[0].contains("bad"))
  }

  func testValidateGovernanceFailsWhenPromotedHasEmptyEvidence() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [
      DeviceQuirk(id: "empty-ev", vid: 1, pid: 1, status: .promoted, evidenceRequired: []),
    ])
    let result = db.validateGovernance()
    XCTAssertFalse(result.isValid)
  }

  func testBundledDatabasePassesGovernanceValidation() throws {
    let db = try QuirkDatabase.load()
    let result = db.validateGovernance()
    XCTAssertTrue(result.isValid, "Bundled database governance violations: \(result.violations)")
  }

  func testBundledTestedDevicesMatchPromotedCount() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    XCTAssertEqual(db.testedDevices().count, promoted.count)
  }
}
