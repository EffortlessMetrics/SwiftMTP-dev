// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

// MARK: - Status Transition Workflow

final class GovernanceStatusTransitionWave32Tests: XCTestCase {

  // Valid forward transitions: proposed → verified → promoted
  func testTransitionProposedToVerified() {
    var quirk = DeviceQuirk(id: "tr-1", vid: 0x0001, pid: 0x0001, status: .proposed)
    XCTAssertEqual(quirk.status, .proposed)
    quirk.status = .verified
    XCTAssertEqual(quirk.status, .verified)
  }

  func testTransitionVerifiedToPromoted() {
    var quirk = DeviceQuirk(id: "tr-2", vid: 0x0001, pid: 0x0002, status: .verified)
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testTransitionProposedToPromotedDirectly() {
    var quirk = DeviceQuirk(id: "tr-3", vid: 0x0001, pid: 0x0003, status: .proposed)
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testFullForwardLifecycle() {
    var quirk = DeviceQuirk(id: "lifecycle", vid: 0x0001, pid: 0x0004, status: .proposed)
    XCTAssertEqual(quirk.status, .proposed)
    quirk.status = .verified
    XCTAssertEqual(quirk.status, .verified)
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
  }

  // Downgrade: promoted → proposed (the enum allows mutation, but governance
  // rules forbid it; validate that the raw value reflects the downgrade so
  // external tooling can reject it).
  func testDowngradePromotedToProposedIsDetectable() {
    var quirk = DeviceQuirk(id: "down-1", vid: 0x0001, pid: 0x0005, status: .promoted)
    quirk.status = .proposed
    // The struct allows the mutation — governance enforcement is policy-level.
    // Tests confirm the value is detectable by tooling that checks transitions.
    XCTAssertEqual(
      quirk.status, .proposed,
      "Struct allows downgrade; external validation must reject promoted→proposed")
  }

  func testDowngradePromotedToVerifiedIsDetectable() {
    var quirk = DeviceQuirk(id: "down-2", vid: 0x0001, pid: 0x0006, status: .promoted)
    quirk.status = .verified
    XCTAssertEqual(
      quirk.status, .verified,
      "Struct allows downgrade; external validation must reject promoted→verified")
  }

  /// Helper: returns true if `from → to` is a valid forward transition.
  private func isValidForwardTransition(from: QuirkStatus, to: QuirkStatus) -> Bool {
    let order: [QuirkStatus: Int] = [.proposed: 0, .verified: 1, .promoted: 2]
    guard let f = order[from], let t = order[to] else { return false }
    return t > f
  }

  func testValidForwardTransitions() {
    XCTAssertTrue(isValidForwardTransition(from: .proposed, to: .verified))
    XCTAssertTrue(isValidForwardTransition(from: .proposed, to: .promoted))
    XCTAssertTrue(isValidForwardTransition(from: .verified, to: .promoted))
  }

  func testInvalidDowngradeTransitions() {
    XCTAssertFalse(isValidForwardTransition(from: .promoted, to: .proposed))
    XCTAssertFalse(isValidForwardTransition(from: .promoted, to: .verified))
    XCTAssertFalse(isValidForwardTransition(from: .verified, to: .proposed))
  }

  func testSameStatusTransitionIsNotForward() {
    XCTAssertFalse(isValidForwardTransition(from: .proposed, to: .proposed))
    XCTAssertFalse(isValidForwardTransition(from: .promoted, to: .promoted))
  }

  // Legacy status strings (scaffolded, community, deprecated) all decode as .proposed
  func testLegacyScaffoldedDecodesAsProposed() throws {
    let json = Data("\"scaffolded\"".utf8)
    let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
    XCTAssertEqual(decoded, .proposed)
  }

  func testLegacyCommunityDecodesAsProposed() throws {
    let json = Data("\"community\"".utf8)
    let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
    XCTAssertEqual(decoded, .proposed)
  }

  func testLegacyDeprecatedDecodesAsProposed() throws {
    let json = Data("\"deprecated\"".utf8)
    let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
    XCTAssertEqual(decoded, .proposed)
  }
}

// MARK: - Evidence Validation

final class GovernanceEvidenceValidationWave32Tests: XCTestCase {

  func testPromotedEntryRequiresProbeLog() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    XCTAssertFalse(promoted.isEmpty, "Database must contain promoted entries")
    for entry in promoted {
      XCTAssertTrue(
        entry.evidenceRequired?.contains("probe_log") == true,
        "Promoted entry '\(entry.id)' must require probe_log evidence")
    }
  }

  func testPromotedEntryRequiresAtLeastTwoEvidenceItems() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      let evidence = entry.evidenceRequired ?? []
      XCTAssertGreaterThanOrEqual(
        evidence.count, 2,
        "Promoted entry '\(entry.id)' must require at least probe_log + one test evidence item")
    }
  }

  func testPromotedEntryHasNonEmptyEvidence() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Promoted entry '\(entry.id)' must have evidenceRequired")
      XCTAssertFalse(
        entry.evidenceRequired?.isEmpty ?? true,
        "Promoted entry '\(entry.id)' must have non-empty evidenceRequired")
    }
  }

  func testEvidenceFieldDeserialization() throws {
    let json = """
      {
        "id": "ev-test",
        "match": { "vid": "0xAAAA", "pid": "0xBBBB" },
        "status": "promoted",
        "evidenceRequired": ["probe_log", "transfer_test", "quirk_test"],
        "lastVerifiedDate": "2025-07-01",
        "lastVerifiedBy": "wave32-lab"
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.evidenceRequired?.count, 3)
    XCTAssertTrue(quirk.evidenceRequired?.contains("probe_log") == true)
    XCTAssertTrue(quirk.evidenceRequired?.contains("transfer_test") == true)
    XCTAssertTrue(quirk.evidenceRequired?.contains("quirk_test") == true)
  }

  func testEvidenceRequiredIsNilForProposedEntry() {
    let quirk = DeviceQuirk(id: "no-ev", vid: 0x0001, pid: 0x0001, status: .proposed)
    XCTAssertNil(quirk.evidenceRequired)
  }

  func testProbeLogPathEvidence() throws {
    let json = """
      {
        "id": "probe-path",
        "match": { "vid": "0x1111", "pid": "0x2222" },
        "evidenceRequired": ["probe_log"]
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertTrue(quirk.evidenceRequired?.contains("probe_log") == true)
  }

  func testTransferTestPathEvidence() throws {
    let json = """
      {
        "id": "transfer-path",
        "match": { "vid": "0x3333", "pid": "0x4444" },
        "evidenceRequired": ["transfer_test"]
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertTrue(quirk.evidenceRequired?.contains("transfer_test") == true)
  }
}

// MARK: - Governance Metadata

final class GovernanceMetadataWave32Tests: XCTestCase {

  func testDatePromotedFieldPreservation() throws {
    let json = """
      {
        "id": "meta-date",
        "match": { "vid": "0xDEAD", "pid": "0xBEEF" },
        "status": "promoted",
        "lastVerifiedDate": "2025-06-15",
        "lastVerifiedBy": "device-lab-ci",
        "evidenceRequired": ["probe_log", "write_test"]
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.lastVerifiedDate, "2025-06-15")
    XCTAssertEqual(quirk.lastVerifiedBy, "device-lab-ci")
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testVerifiedByFieldIsOptional() {
    let quirk = DeviceQuirk(id: "no-by", vid: 1, pid: 1, status: .verified)
    XCTAssertNil(quirk.lastVerifiedBy)
    XCTAssertNil(quirk.lastVerifiedDate)
  }

  func testConfidenceHighForPromoted() throws {
    let json = """
      {
        "id": "conf-promoted",
        "match": { "vid": "0x0010", "pid": "0x0020" },
        "status": "promoted",
        "confidence": "high",
        "evidenceRequired": ["probe_log", "write_test"]
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.confidence, "high")
    XCTAssertEqual(quirk.status, .promoted)
  }

  func testGovernanceMetadataRoundTrip() throws {
    let json = """
      {
        "id": "meta-rt",
        "match": { "vid": "0xCAFE", "pid": "0xBABE" },
        "status": "verified",
        "confidence": "medium",
        "evidenceRequired": ["probe_log"],
        "lastVerifiedDate": "2025-07-01",
        "lastVerifiedBy": "manual-test"
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    let encoded = try JSONEncoder().encode(quirk)
    let obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    XCTAssertEqual(obj?["status"] as? String, "verified")
    XCTAssertEqual(obj?["confidence"] as? String, "medium")
    XCTAssertEqual(obj?["lastVerifiedDate"] as? String, "2025-07-01")
    XCTAssertEqual(obj?["lastVerifiedBy"] as? String, "manual-test")
    XCTAssertEqual(obj?["evidenceRequired"] as? [String], ["probe_log"])
  }
}

// MARK: - QuirkEntry Merge (governance preservation)

final class GovernanceMergeWave32Tests: XCTestCase {

  func testGovernanceStatusPreservedDuringTuningMerge() {
    let quirk = DeviceQuirk(
      id: "merge-gov", vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 2_097_152, ioTimeoutMs: 15000,
      status: .promoted,
      evidenceRequired: ["probe_log", "write_test"])

    // Build effective tuning from the quirk
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)

    // Tuning values come from the quirk
    XCTAssertEqual(result.maxChunkBytes, 2_097_152)
    XCTAssertEqual(result.ioTimeoutMs, 15000)

    // The original quirk's governance status is untouched by tuning merge
    XCTAssertEqual(quirk.status, .promoted)
    XCTAssertEqual(quirk.evidenceRequired, ["probe_log", "write_test"])
  }

  func testPolicyBuildPreservesQuirkGovernance() {
    let quirk = DeviceQuirk(
      id: "policy-gov", vid: 0x1234, pid: 0x5678,
      status: .verified, confidence: "medium",
      evidenceRequired: ["probe_log"])

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)

    // Policy should reflect quirk source
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
    // Original quirk unchanged
    XCTAssertEqual(quirk.status, .verified)
    XCTAssertEqual(quirk.confidence, "medium")
  }

  func testLearnedProfileDoesNotOverrideGovernanceStatus() {
    let quirk = DeviceQuirk(
      id: "learned-gov", vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 512_000, status: .promoted,
      evidenceRequired: ["probe_log", "write_test"])

    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 4_194_304  // learned suggests bigger chunks

    // Static quirk overrides learned tuning
    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
    XCTAssertEqual(result.maxChunkBytes, 512_000)

    // Governance fields remain on the quirk
    XCTAssertEqual(quirk.status, .promoted)
  }
}

// MARK: - Database Load with Mixed Governance Statuses

final class GovernanceMixedStatusDatabaseWave32Tests: XCTestCase {

  func testDatabaseWithMixedStatusesDecodes() throws {
    let json = """
      {
        "schemaVersion": "1.0",
        "entries": [
          { "id": "e-proposed", "match": { "vid": "0x0001", "pid": "0x0001" }, "status": "proposed" },
          { "id": "e-verified", "match": { "vid": "0x0002", "pid": "0x0002" }, "status": "verified" },
          { "id": "e-promoted", "match": { "vid": "0x0003", "pid": "0x0003" }, "status": "promoted" },
          { "id": "e-legacy-stable", "match": { "vid": "0x0004", "pid": "0x0004" }, "status": "stable" },
          { "id": "e-legacy-experimental", "match": { "vid": "0x0005", "pid": "0x0005" }, "status": "experimental" },
          { "id": "e-legacy-community", "match": { "vid": "0x0006", "pid": "0x0006" }, "status": "community" },
          { "id": "e-no-status", "match": { "vid": "0x0007", "pid": "0x0007" } }
        ]
      }
      """
    let db = try JSONDecoder().decode(QuirkDatabase.self, from: Data(json.utf8))
    XCTAssertEqual(db.entries.count, 7)
    XCTAssertEqual(db.entries[0].status, .proposed)
    XCTAssertEqual(db.entries[1].status, .verified)
    XCTAssertEqual(db.entries[2].status, .promoted)
    XCTAssertEqual(db.entries[3].status, .proposed, "Legacy 'stable' decodes as .proposed")
    XCTAssertEqual(db.entries[4].status, .proposed, "Legacy 'experimental' decodes as .proposed")
    XCTAssertEqual(db.entries[5].status, .proposed, "Legacy 'community' decodes as .proposed")
    XCTAssertNil(db.entries[6].status, "Missing status should be nil")
  }

  func testMatchingWorksRegardlessOfGovernanceStatus() throws {
    let json = """
      {
        "schemaVersion": "1.0",
        "entries": [
          { "id": "match-proposed", "match": { "vid": "0x1000", "pid": "0x2000" }, "status": "proposed" },
          { "id": "match-promoted", "match": { "vid": "0x3000", "pid": "0x4000" }, "status": "promoted" }
        ]
      }
      """
    let db = try JSONDecoder().decode(QuirkDatabase.self, from: Data(json.utf8))

    let proposed = db.match(
      vid: 0x1000, pid: 0x2000,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(proposed?.id, "match-proposed")

    let promoted = db.match(
      vid: 0x3000, pid: 0x4000,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(promoted?.id, "match-promoted")
  }
}

// MARK: - Learned Profile → Promoted Pathway

final class GovernancePromotionPathwayWave32Tests: XCTestCase {

  func testLearnedProfileAccumulatesEvidence() {
    // Simulate a device starting with proposed status and learned tuning,
    // then being promoted after evidence accumulation.
    var quirk = DeviceQuirk(
      id: "learn-promote", vid: 0xAAAA, pid: 0xBBBB,
      status: .proposed, confidence: "low")

    // Stage 1: device tested, evidence gathered
    quirk.evidenceRequired = ["probe_log"]
    quirk.confidence = "medium"
    quirk.status = .verified
    XCTAssertEqual(quirk.status, .verified)
    XCTAssertEqual(quirk.confidence, "medium")

    // Stage 2: more evidence → promotion
    quirk.evidenceRequired = ["probe_log", "write_test", "disconnect_recovery"]
    quirk.confidence = "high"
    quirk.lastVerifiedDate = "2025-07-01"
    quirk.lastVerifiedBy = "device-lab"
    quirk.status = .promoted
    XCTAssertEqual(quirk.status, .promoted)
    XCTAssertEqual(quirk.confidence, "high")
    XCTAssertEqual(quirk.evidenceRequired?.count, 3)
    XCTAssertEqual(quirk.lastVerifiedDate, "2025-07-01")
  }

  func testLearnedTuningFeedsPolicyBeforePromotion() {
    // A device with learned tuning but only proposed status
    let quirk = DeviceQuirk(
      id: "learn-policy", vid: 0xCCCC, pid: 0xDDDD,
      status: .proposed, confidence: "low")

    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 2_097_152
    learned.ioTimeoutMs = 10000

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: learned, quirk: quirk, overrides: nil)

    // Quirk overrides learned (quirk has no maxChunkBytes set, so learned applies
    // only where quirk doesn't specify)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
    // Governance status is still on the quirk
    XCTAssertEqual(quirk.status, .proposed)
  }
}

// MARK: - Status Filtering

final class GovernanceStatusFilteringWave32Tests: XCTestCase {

  func testFilterByPromotedStatus() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    XCTAssertFalse(promoted.isEmpty, "Should have promoted entries")
    for entry in promoted {
      XCTAssertEqual(entry.status, .promoted)
    }
  }

  func testFilterByVerifiedStatus() throws {
    let db = try QuirkDatabase.load()
    let verified = db.entries.filter { $0.status == .verified }
    // Verified entries may or may not exist; just confirm filter works
    for entry in verified {
      XCTAssertEqual(entry.status, .verified)
    }
  }

  func testFilterByProposedStatus() throws {
    let db = try QuirkDatabase.load()
    let proposed = db.entries.filter { $0.status == .proposed }
    // The vast majority should be proposed (including legacy fallback)
    XCTAssertFalse(proposed.isEmpty)
    for entry in proposed {
      XCTAssertEqual(entry.status, .proposed)
    }
  }

  func testStatusCountsAreReasonable() throws {
    let db = try QuirkDatabase.load()
    let proposed = db.entries.filter { $0.status == .proposed }.count
    let promoted = db.entries.filter { $0.status == .promoted }.count
    // Most entries are scaffolded (proposed); only a few are promoted
    XCTAssertGreaterThan(
      proposed, promoted,
      "Proposed entries should outnumber promoted entries")
    XCTAssertGreaterThanOrEqual(
      promoted, 1,
      "Database should contain at least one promoted entry")
  }

  func testFilterEntriesWithEvidence() throws {
    let db = try QuirkDatabase.load()
    let withEvidence = db.entries.filter {
      ($0.evidenceRequired?.isEmpty == false)
    }
    XCTAssertFalse(withEvidence.isEmpty, "Some entries should have evidence")
    for entry in withEvidence {
      XCTAssertFalse(entry.evidenceRequired!.isEmpty)
    }
  }
}

// MARK: - Bulk Governance Validation

final class GovernanceBulkValidationWave32Tests: XCTestCase {

  func testAllEntriesHaveValidStatusField() throws {
    let db = try QuirkDatabase.load()
    XCTAssertGreaterThanOrEqual(
      db.entries.count, 20_000,
      "Database should contain ~20,026 entries")

    let validStatuses: Set<QuirkStatus> = [.proposed, .verified, .promoted]
    for entry in db.entries {
      if let status = entry.status {
        XCTAssertTrue(
          validStatuses.contains(status),
          "Entry '\(entry.id)' has invalid decoded status '\(status)'")
      }
      // status may be nil for legacy entries without the field
    }
  }

  func testAllPromotedEntriesHaveEvidenceRequired() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.evidenceRequired,
        "Promoted entry '\(entry.id)' must have evidenceRequired")
      XCTAssertTrue(
        (entry.evidenceRequired?.count ?? 0) > 0,
        "Promoted entry '\(entry.id)' must have at least one evidence item")
    }
  }

  func testAllEntriesHaveNonEmptyID() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries {
      XCTAssertFalse(entry.id.isEmpty, "Quirk entry ID must not be empty")
    }
  }

  func testAllEntriesHaveNonZeroVIDPID() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries {
      XCTAssertNotEqual(entry.vid, 0, "Entry '\(entry.id)' has zero VID")
      XCTAssertNotEqual(entry.pid, 0, "Entry '\(entry.id)' has zero PID")
    }
  }

  func testEntryIDsAreUnique() throws {
    let db = try QuirkDatabase.load()
    var seen = Set<String>()
    for entry in db.entries {
      XCTAssertFalse(
        seen.contains(entry.id),
        "Duplicate quirk ID: '\(entry.id)'")
      seen.insert(entry.id)
    }
  }

  func testPromotedEntriesHaveLastVerifiedDate() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }
    for entry in promoted {
      XCTAssertNotNil(
        entry.lastVerifiedDate,
        "Promoted entry '\(entry.id)' should have lastVerifiedDate")
      if let date = entry.lastVerifiedDate {
        XCTAssertFalse(
          date.isEmpty,
          "Promoted entry '\(entry.id)' has empty lastVerifiedDate")
      }
    }
  }
}
