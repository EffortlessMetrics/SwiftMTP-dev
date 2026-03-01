// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

// MARK: - QuirkDatabase Matching

final class QuirkDatabaseMatchingTests: XCTestCase {

  func testVIDAndPIDMatch() {
    let entry = DeviceQuirk(id: "match-both", vid: 0x1234, pid: 0x5678)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [entry])

    let result = db.match(
      vid: 0x1234, pid: 0x5678,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "match-both")
  }

  func testVIDOnlyDoesNotMatch() {
    let entry = DeviceQuirk(id: "vid-only", vid: 0x1234, pid: 0x5678)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [entry])

    let result = db.match(
      vid: 0x1234, pid: 0xAAAA,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result, "PID mismatch must return nil even when VID matches")
  }

  func testNoMatchReturnsNil() {
    let entry = DeviceQuirk(id: "no-match", vid: 0x1111, pid: 0x2222)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [entry])

    let result = db.match(
      vid: 0xFFFF, pid: 0xFFFF,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result)
  }

  func testEmptyDatabaseReturnsNil() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let result = db.match(
      vid: 0x1234, pid: 0x5678,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result)
  }

  func testMultipleMatchesSelectsHighestScore() {
    let generic = DeviceQuirk(id: "generic", vid: 0x1234, pid: 0x5678)
    let withBCD = DeviceQuirk(id: "with-bcd", vid: 0x1234, pid: 0x5678, bcdDevice: 0x0100)
    let full = DeviceQuirk(
      id: "full", vid: 0x1234, pid: 0x5678, bcdDevice: 0x0100,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [generic, withBCD, full])

    let result = db.match(
      vid: 0x1234, pid: 0x5678,
      bcdDevice: 0x0100, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertEqual(result?.id, "full", "Most specific entry should win")
  }

  func testBCDMismatchFallsBackToGeneric() {
    let specific = DeviceQuirk(id: "bcd-specific", vid: 0xAA, pid: 0xBB, bcdDevice: 0x0300)
    let generic = DeviceQuirk(id: "bcd-generic", vid: 0xAA, pid: 0xBB)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [specific, generic])

    let result = db.match(
      vid: 0xAA, pid: 0xBB,
      bcdDevice: 0x0100, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "bcd-generic")
  }
}

// MARK: - DeviceQuirk Flag Resolution

final class DeviceQuirkResolutionTests: XCTestCase {

  func testResolvedFlagsReturnsTypedFlags() {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.disableEventPump = true
    let quirk = DeviceQuirk(id: "typed", vid: 1, pid: 1, flags: flags)

    let resolved = quirk.resolvedFlags()
    XCTAssertTrue(resolved.resetOnOpen)
    XCTAssertTrue(resolved.disableEventPump)
  }

  func testResolvedFlagsSynthesizesFromLegacyOps() {
    let quirk = DeviceQuirk(
      id: "legacy", vid: 1, pid: 1,
      operations: [
        "supportsGetPartialObject64": true,
        "supportsSendPartialObject": false,
        "preferGetObjectPropList": true,
        "supportsGetPartialObject": true,
      ])

    let resolved = quirk.resolvedFlags()
    XCTAssertTrue(resolved.supportsPartialRead64)
    XCTAssertFalse(resolved.supportsPartialWrite)
    XCTAssertTrue(resolved.prefersPropListEnumeration)
    XCTAssertTrue(resolved.supportsGetObjectPropList)
    XCTAssertTrue(resolved.supportsGetPartialObject)
  }

  func testResolvedFlagsSynthesizesResetOnOpen() {
    let quirk = DeviceQuirk(id: "reset", vid: 1, pid: 1, resetOnOpen: true)
    let resolved = quirk.resolvedFlags()
    XCTAssertTrue(resolved.resetOnOpen)
  }

  func testResolvedFlagsSynthesizesStabilization() {
    let quirk = DeviceQuirk(id: "stab", vid: 1, pid: 1, stabilizeMs: 500)
    let resolved = quirk.resolvedFlags()
    XCTAssertTrue(resolved.requireStabilization)
  }

  func testResolvedFlagsDefaultsWhenNoFlagsOrOps() {
    let quirk = DeviceQuirk(id: "bare", vid: 1, pid: 1)
    let resolved = quirk.resolvedFlags()
    let defaultFlags = QuirkFlags()
    XCTAssertEqual(resolved, defaultFlags)
  }

  func testPTPCameraDefaultFlags() {
    let cam = QuirkFlags.ptpCameraDefaults()
    XCTAssertFalse(cam.requiresKernelDetach)
    XCTAssertTrue(cam.supportsGetObjectPropList)
    XCTAssertTrue(cam.prefersPropListEnumeration)
    XCTAssertTrue(cam.supportsPartialRead32)
  }
}

// MARK: - Category Validation

final class CategoryValidationTests: XCTestCase {

  func testAllCategoriesAreNonEmpty() throws {
    let db = try QuirkDatabase.load()
    let categories = Set(db.entries.compactMap(\.category))
    XCTAssertFalse(categories.isEmpty)
    for cat in categories {
      XCTAssertFalse(cat.isEmpty, "Category string must not be empty")
      XCTAssertFalse(cat.contains(" "), "Category '\(cat)' should be kebab-case")
    }
  }

  func testKnownCategoriesPresent() throws {
    let db = try QuirkDatabase.load()
    let categories = Set(db.entries.compactMap(\.category))
    let expected: Set<String> = ["phone", "camera", "tablet", "media-player", "drone"]
    for cat in expected {
      XCTAssertTrue(categories.contains(cat), "Expected category '\(cat)' missing")
    }
  }
}

// MARK: - QuirkHook Handling

final class QuirkHookTests: XCTestCase {

  func testEmptyHooksArray() {
    let quirk = DeviceQuirk(id: "no-hooks", vid: 1, pid: 1, hooks: [])
    XCTAssertEqual(quirk.hooks?.count, 0)
  }

  func testSingleHook() {
    let hook = QuirkHook(phase: .postOpenUSB, delayMs: 100)
    let quirk = DeviceQuirk(id: "one-hook", vid: 1, pid: 1, hooks: [hook])
    XCTAssertEqual(quirk.hooks?.count, 1)
    XCTAssertEqual(quirk.hooks?.first?.phase, .postOpenUSB)
    XCTAssertEqual(quirk.hooks?.first?.delayMs, 100)
  }

  func testMultipleHooks() {
    let hooks: [QuirkHook] = [
      QuirkHook(phase: .postOpenSession, delayMs: 50),
      QuirkHook(phase: .beforeTransfer),
      QuirkHook(
        phase: .onDeviceBusy,
        busyBackoff: QuirkHook.BusyBackoff(retries: 5, baseMs: 200, jitterPct: 0.1)),
    ]
    let quirk = DeviceQuirk(id: "multi-hook", vid: 1, pid: 1, hooks: hooks)
    XCTAssertEqual(quirk.hooks?.count, 3)
    XCTAssertNil(quirk.hooks?[1].delayMs)
    XCTAssertEqual(quirk.hooks?[2].busyBackoff?.retries, 5)
  }

  func testAllHookPhasesExist() {
    let allPhases: [QuirkHook.Phase] = [
      .postOpenUSB, .postClaimInterface, .postOpenSession,
      .beforeGetDeviceInfo, .beforeGetStorageIDs, .beforeGetObjectHandles,
      .beforeTransfer, .afterTransfer, .onDeviceBusy, .onDetach,
    ]
    XCTAssertEqual(allPhases.count, 10)
    for phase in allPhases {
      let hook = QuirkHook(phase: phase)
      XCTAssertEqual(hook.phase, phase)
    }
  }
}

// MARK: - Interface Matching Scores

final class InterfaceMatchingTests: XCTestCase {

  func testClassMatchIncreasesScore() {
    let withClass = DeviceQuirk(id: "with-class", vid: 0x10, pid: 0x20, ifaceClass: 0x06)
    let plain = DeviceQuirk(id: "plain", vid: 0x10, pid: 0x20)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [withClass, plain])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "with-class", "Class match should score higher")
  }

  func testSubclassMatchIncreasesScore() {
    let withSub = DeviceQuirk(
      id: "with-sub", vid: 0x10, pid: 0x20, ifaceClass: 0x06, ifaceSubclass: 0x01)
    let classOnly = DeviceQuirk(id: "class-only", vid: 0x10, pid: 0x20, ifaceClass: 0x06)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [withSub, classOnly])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "with-sub")
  }

  func testProtocolMatchIncreasesScore() {
    let full = DeviceQuirk(
      id: "full-iface", vid: 0x10, pid: 0x20,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let partial = DeviceQuirk(
      id: "partial-iface", vid: 0x10, pid: 0x20,
      ifaceClass: 0x06, ifaceSubclass: 0x01)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [full, partial])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertEqual(result?.id, "full-iface")
  }

  func testClassMismatchExcludesEntry() {
    let strict = DeviceQuirk(id: "strict", vid: 0x10, pid: 0x20, ifaceClass: 0x06)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [strict])

    let result = db.match(
      vid: 0x10, pid: 0x20,
      bcdDevice: nil, ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNil(result, "Class mismatch should disqualify the entry")
  }
}

// MARK: - Learned Profile Integration

final class LearnedProfileTests: XCTestCase {

  func testLearnedProfileOverridesDefaults() {
    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 2 * 1024 * 1024
    learned.ioTimeoutMs = 12000

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: nil, overrides: nil)
    XCTAssertEqual(result.maxChunkBytes, 2 * 1024 * 1024)
    XCTAssertEqual(result.ioTimeoutMs, 12000)
  }

  func testStaticQuirkOverridesLearnedProfile() {
    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 4 * 1024 * 1024

    let quirk = DeviceQuirk(id: "static", vid: 1, pid: 1, maxChunkBytes: 512 * 1024)

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
    XCTAssertEqual(result.maxChunkBytes, 512 * 1024)
  }

  func testUserOverridesHaveHighestPrecedence() {
    let quirk = DeviceQuirk(id: "quirk", vid: 1, pid: 1, ioTimeoutMs: 3000)
    let overrides = ["ioTimeoutMs": "15000"]

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: overrides)
    XCTAssertEqual(result.ioTimeoutMs, 15000)
  }

  func testBuildPolicySourcesReflectQuirk() {
    let quirk = DeviceQuirk(id: "q", vid: 1, pid: 1)
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  func testBuildPolicyWithPTPCameraClassFallback() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
  }
}

// MARK: - Edge Cases

final class QuirkEdgeCaseTests: XCTestCase {

  func testZeroVIDAndPID() {
    let entry = DeviceQuirk(id: "zero", vid: 0x0000, pid: 0x0000)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [entry])

    let result = db.match(
      vid: 0x0000, pid: 0x0000,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "zero")
  }

  func testMaxVIDAndPID() {
    let entry = DeviceQuirk(id: "max", vid: 0xFFFF, pid: 0xFFFF)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [entry])

    let result = db.match(
      vid: 0xFFFF, pid: 0xFFFF,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertEqual(result?.id, "max")
  }

  func testNilOptionalFields() {
    let quirk = DeviceQuirk(id: "nil-fields", vid: 1, pid: 1)
    XCTAssertNil(quirk.deviceName)
    XCTAssertNil(quirk.category)
    XCTAssertNil(quirk.bcdDevice)
    XCTAssertNil(quirk.ifaceClass)
    XCTAssertNil(quirk.maxChunkBytes)
    XCTAssertNil(quirk.hooks)
    XCTAssertNil(quirk.flags)
    XCTAssertNil(quirk.status)
    XCTAssertNil(quirk.confidence)
  }

  func testEmptyDeviceName() {
    let quirk = DeviceQuirk(id: "empty-name", deviceName: "", vid: 1, pid: 1)
    XCTAssertEqual(quirk.deviceName, "")
  }

  func testTuningClampingEnforcesMinimums() {
    let quirk = DeviceQuirk(
      id: "tiny", vid: 1, pid: 1,
      maxChunkBytes: 1, ioTimeoutMs: 1, handshakeTimeoutMs: 1)

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertGreaterThanOrEqual(result.maxChunkBytes, 128 * 1024)
    XCTAssertGreaterThanOrEqual(result.ioTimeoutMs, 1000)
    XCTAssertGreaterThanOrEqual(result.handshakeTimeoutMs, 1000)
  }

  func testTuningClampingEnforcesMaximums() {
    let quirk = DeviceQuirk(
      id: "huge", vid: 1, pid: 1,
      maxChunkBytes: 100_000_000, ioTimeoutMs: 999_999)

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertLessThanOrEqual(result.maxChunkBytes, 16 * 1024 * 1024)
    XCTAssertLessThanOrEqual(result.ioTimeoutMs, 60000)
  }
}

// MARK: - Serialization Round-Trip

final class QuirkSerializationTests: XCTestCase {

  func testQuirkFlagsRoundTrip() throws {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.requiresKernelDetach = false
    flags.writeToSubfolderOnly = true
    flags.preferredWriteFolder = "Download"
    flags.cameraClass = true

    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertEqual(decoded, flags)
  }

  func testQuirkHookRoundTrip() throws {
    let backoff = QuirkHook.BusyBackoff(retries: 3, baseMs: 500, jitterPct: 0.15)
    let hook = QuirkHook(phase: .onDeviceBusy, delayMs: 100, busyBackoff: backoff)

    let data = try JSONEncoder().encode(hook)
    let decoded = try JSONDecoder().decode(QuirkHook.self, from: data)
    XCTAssertEqual(decoded.phase, hook.phase)
    XCTAssertEqual(decoded.delayMs, hook.delayMs)
    XCTAssertEqual(decoded.busyBackoff?.retries, 3)
    XCTAssertEqual(decoded.busyBackoff?.baseMs, 500)
    XCTAssertEqual(decoded.busyBackoff?.jitterPct ?? 0, 0.15, accuracy: 0.001)
  }

  func testQuirkStatusRoundTrip() throws {
    for status in [QuirkStatus.proposed, .verified, .promoted] {
      let data = try JSONEncoder().encode(status)
      let decoded = try JSONDecoder().decode(QuirkStatus.self, from: data)
      XCTAssertEqual(decoded, status)
    }
  }

  func testDeviceQuirkDecodeFromJSON() throws {
    let json = """
      {
        "id": "test-device",
        "deviceName": "Test Device",
        "category": "phone",
        "match": { "vid": "0x1234", "pid": "0x5678", "bcdDevice": "0x0100",
                   "iface": { "class": "0x06", "subclass": "0x01", "protocol": "0x01" } },
        "tuning": { "maxChunkBytes": 524288, "ioTimeoutMs": 5000, "stabilizeMs": 200,
                    "handshakeTimeoutMs": 3000, "inactivityTimeoutMs": 4000,
                    "overallDeadlineMs": 30000, "resetOnOpen": true },
        "hooks": [ { "phase": "postOpenUSB", "delayMs": 50 } ],
        "ops": { "supportsGetPartialObject64": true },
        "status": "verified",
        "confidence": "high"
      }
      """
    let quirk = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
    XCTAssertEqual(quirk.id, "test-device")
    XCTAssertEqual(quirk.deviceName, "Test Device")
    XCTAssertEqual(quirk.category, "phone")
    XCTAssertEqual(quirk.vid, 0x1234)
    XCTAssertEqual(quirk.pid, 0x5678)
    XCTAssertEqual(quirk.bcdDevice, 0x0100)
    XCTAssertEqual(quirk.ifaceClass, 0x06)
    XCTAssertEqual(quirk.ifaceSubclass, 0x01)
    XCTAssertEqual(quirk.ifaceProtocol, 0x01)
    XCTAssertEqual(quirk.maxChunkBytes, 524288)
    XCTAssertEqual(quirk.ioTimeoutMs, 5000)
    XCTAssertEqual(quirk.stabilizeMs, 200)
    XCTAssertTrue(quirk.resetOnOpen ?? false)
    XCTAssertEqual(quirk.hooks?.count, 1)
    XCTAssertEqual(quirk.operations?["supportsGetPartialObject64"], true)
    XCTAssertEqual(quirk.status, .verified)
    XCTAssertEqual(quirk.confidence, "high")
  }

  func testQuirkDatabaseEncodeDecodeSchemaLevel() throws {
    // DeviceQuirk.encode() omits the nested `match` object, so a full
    // encode→decode round-trip at the entry level isn't supported.
    // Verify schema-level encode/decode with a hand-crafted JSON payload.
    let json = """
      {
        "schemaVersion": "2.0",
        "entries": [
          { "id": "rt-entry", "match": { "vid": "0x1111", "pid": "0x2222" }, "status": "promoted", "confidence": "medium" }
        ]
      }
      """
    let decoded = try JSONDecoder().decode(QuirkDatabase.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.schemaVersion, "2.0")
    XCTAssertEqual(decoded.entries.count, 1)
    XCTAssertEqual(decoded.entries.first?.id, "rt-entry")
    XCTAssertEqual(decoded.entries.first?.vid, 0x1111)
    XCTAssertEqual(decoded.entries.first?.status, .promoted)

    // Re-encode preserves schema-level fields
    let reEncoded = try JSONEncoder().encode(decoded)
    let obj = try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any]
    XCTAssertEqual(obj?["schemaVersion"] as? String, "2.0")
  }

  func testFallbackSelectionsRoundTrip() throws {
    var sel = FallbackSelections()
    sel.enumeration = .propList5
    sel.read = .partial64
    sel.write = .partial

    let data = try JSONEncoder().encode(sel)
    let decoded = try JSONDecoder().decode(FallbackSelections.self, from: data)
    XCTAssertEqual(decoded, sel)
  }
}

// MARK: - Governance Status

final class GovernanceStatusTests: XCTestCase {

  func testAllStatusValuesDecodeCorrectly() throws {
    for (raw, expected) in [
      ("proposed", QuirkStatus.proposed),
      ("verified", QuirkStatus.verified),
      ("promoted", QuirkStatus.promoted),
    ] {
      let json = Data("\"\(raw)\"".utf8)
      let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
      XCTAssertEqual(decoded, expected)
    }
  }

  func testUnknownStatusDefaultsToProposed() throws {
    // Legacy values like "stable", "experimental", "blocked" should default to .proposed
    for legacy in ["stable", "experimental", "blocked", "unknown", ""] {
      let json = Data("\"\(legacy)\"".utf8)
      let decoded = try JSONDecoder().decode(QuirkStatus.self, from: json)
      XCTAssertEqual(decoded, .proposed, "'\(legacy)' should default to .proposed")
    }
  }

  func testBundledDatabaseStatusValues() throws {
    let db = try QuirkDatabase.load()
    let validStatuses: Set<QuirkStatus> = [.proposed, .verified, .promoted]
    for entry in db.entries {
      if let status = entry.status {
        XCTAssertTrue(
          validStatuses.contains(status),
          "Entry '\(entry.id)' has unexpected decoded status")
      }
    }
  }

  func testStatusRawValueRoundTrips() {
    XCTAssertEqual(QuirkStatus(rawValue: "proposed"), .proposed)
    XCTAssertEqual(QuirkStatus(rawValue: "verified"), .verified)
    XCTAssertEqual(QuirkStatus(rawValue: "promoted"), .promoted)
    XCTAssertNil(QuirkStatus(rawValue: "invalid"))
  }
}

// MARK: - EffectiveTuning Defaults

final class EffectiveTuningDefaultsTests: XCTestCase {

  func testDefaultValues() {
    let d = EffectiveTuning.defaults()
    XCTAssertEqual(d.maxChunkBytes, 1 << 20)
    XCTAssertEqual(d.ioTimeoutMs, 8000)
    XCTAssertEqual(d.handshakeTimeoutMs, 6000)
    XCTAssertEqual(d.stabilizeMs, 0)
    XCTAssertFalse(d.resetOnOpen)
    XCTAssertFalse(d.disableEventPump)
    XCTAssertTrue(d.operations.isEmpty)
    XCTAssertTrue(d.hooks.isEmpty)
  }

  func testCapabilitiesMergedIntoOperations() {
    let caps: [String: Bool] = ["partialRead": true, "partialWrite": false]
    let result = EffectiveTuningBuilder.build(
      capabilities: caps, learned: nil, quirk: nil, overrides: nil)
    XCTAssertEqual(result.operations["partialRead"], true)
    XCTAssertEqual(result.operations["partialWrite"], false)
  }

  func testQuirkHooksAppendedToEffectiveTuning() {
    let hooks = [QuirkHook(phase: .afterTransfer, delayMs: 10)]
    let quirk = DeviceQuirk(id: "hooks", vid: 1, pid: 1, hooks: hooks)

    let result = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
    XCTAssertEqual(result.hooks.count, 1)
    XCTAssertEqual(result.hooks.first?.phase, .afterTransfer)
  }
}
