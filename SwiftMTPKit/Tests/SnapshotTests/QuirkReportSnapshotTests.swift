// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Inline snapshot tests for quirk report formatting: database loading,
/// device matching, policy resolution, tuning output, and governance
/// classification display. Verifies that quirk lookup output is stable
/// for known devices.
final class QuirkReportSnapshotTests: XCTestCase {

  // MARK: - 1. QuirkDatabase Loading and Schema

  func testQuirkDatabaseLoadsSuccessfully() throws {
    let db = try QuirkDatabase.load()
    XCTAssertFalse(db.entries.isEmpty)
    XCTAssertFalse(db.schemaVersion.isEmpty)
  }

  func testQuirkDatabaseSchemaVersionFormat() throws {
    let db = try QuirkDatabase.load()
    // Schema version should be a semver-like string
    let parts = db.schemaVersion.split(separator: ".")
    XCTAssertGreaterThanOrEqual(parts.count, 2, "Schema version should have at least major.minor")
  }

  func testQuirkDatabaseHasSubstantialEntries() throws {
    let db = try QuirkDatabase.load()
    XCTAssertGreaterThan(db.entries.count, 1000, "Database should have >1000 quirk entries")
  }

  // MARK: - 2. Known Device Quirk Matching

  func testXiaomiMiNote2QuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff10")
    XCTAssertEqual(match?.vid, 0x2717)
    XCTAssertEqual(match?.pid, 0xFF10)
  }

  func testGooglePixel7QuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x18D1, pid: 0x4EE1,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.vid, 0x18D1)
    XCTAssertEqual(match?.pid, 0x4EE1)
  }

  func testSamsungGalaxyQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x04E8, pid: 0x6860,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    // Samsung 6860 may match depending on interface params; verify VID if matched
    if let match = match {
      XCTAssertEqual(match.vid, 0x04E8)
    }
  }

  func testUnknownDeviceReturnsNil() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0xFFFF, pid: 0xFFFF,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNil(match)
  }

  // MARK: - 3. Policy Resolution Output Format

  func testXiaomiPolicyTuningFields() throws {
    let db = try QuirkDatabase.load()
    let fp = makeFingerprint(vid: "2717", pid: "ff10")
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    XCTAssertGreaterThan(policy.tuning.maxChunkBytes, 0)
    XCTAssertGreaterThan(policy.tuning.ioTimeoutMs, 0)
    XCTAssertGreaterThan(policy.tuning.handshakeTimeoutMs, 0)
  }

  func testPixel7PolicyFlagsResolved() throws {
    let db = try QuirkDatabase.load()
    let fp = makeFingerprint(vid: "18d1", pid: "4ee1")
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    // Pixel 7 is a known Android device — flags should be resolved from quirk
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  func testUnknownDeviceGetsDefaultPolicy() throws {
    let db = try QuirkDatabase.load()
    let fp = makeFingerprint(vid: "ffff", pid: "0001")
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
  }

  func testPolicySummaryJSONFieldsPresent() throws {
    let db = try QuirkDatabase.load()
    let fp = makeFingerprint(vid: "2717", pid: "ff10")
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    let summary = PolicySummary(from: policy)
    let data = try sortedJSON(summary)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNotNil(dict["maxChunkBytes"])
    XCTAssertNotNil(dict["ioTimeoutMs"])
    XCTAssertNotNil(dict["handshakeTimeoutMs"])
    XCTAssertNotNil(dict["resetOnOpen"])
    XCTAssertNotNil(dict["disableEventPump"])
    XCTAssertNotNil(dict["enumerationStrategy"])
    XCTAssertNotNil(dict["readStrategy"])
    XCTAssertNotNil(dict["writeStrategy"])
  }

  // MARK: - 4. DeviceQuirk Field Stability

  func testDeviceQuirkRequiredFields() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries.prefix(50) {
      XCTAssertFalse(entry.id.isEmpty, "Quirk ID must not be empty")
      XCTAssertGreaterThan(entry.vid, 0, "VID must be set for: \(entry.id)")
      XCTAssertGreaterThan(entry.pid, 0, "PID must be set for: \(entry.id)")
    }
  }

  func testDeviceQuirkCategoryIsPopulated() throws {
    let db = try QuirkDatabase.load()
    let categorized = db.entries.filter { $0.category != nil }
    XCTAssertGreaterThan(categorized.count, 0, "At least some entries should have categories")
  }

  // MARK: - 5. Governance Classification Display

  func testGovernanceClassificationPromoted() {
    var quirk = makeTestQuirk()
    quirk.status = .promoted
    XCTAssertEqual(QuirkGovernanceLevel.classify(quirk), .promoted)
  }

  func testGovernanceClassificationVerified() {
    var quirk = makeTestQuirk()
    quirk.status = .verified
    XCTAssertEqual(QuirkGovernanceLevel.classify(quirk), .research)
  }

  func testGovernanceClassificationProposed() {
    var quirk = makeTestQuirk()
    quirk.status = .proposed
    XCTAssertEqual(QuirkGovernanceLevel.classify(quirk), .research)
  }

  func testGovernanceLevelAllCases() {
    let allCases = QuirkGovernanceLevel.allCases
    XCTAssertTrue(allCases.contains(.promoted))
    XCTAssertTrue(allCases.contains(.research))
    XCTAssertTrue(allCases.contains(.community))
    XCTAssertTrue(allCases.contains(.deprecated))
    XCTAssertEqual(allCases.count, 4)
  }

  // MARK: - 6. QuirkFlags Default Report

  func testDefaultFlagsReportStructure() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.requiresKernelDetach, true)
    XCTAssertEqual(flags.resetOnOpen, false)
    XCTAssertEqual(flags.supportsPartialRead64, true)
    XCTAssertEqual(flags.supportsPartialRead32, true)
    XCTAssertEqual(flags.supportsPartialWrite, true)
    XCTAssertEqual(flags.prefersPropListEnumeration, true)
    XCTAssertEqual(flags.disableEventPump, false)
  }

  func testResolvedFlagsForKnownQuirk() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    let flags = match!.resolvedFlags()
    // Should be a valid QuirkFlags — all fields should be accessible
    _ = flags.requiresKernelDetach
    _ = flags.resetOnOpen
    _ = flags.supportsPartialRead64
  }

  // MARK: - Helpers

  private func makeFingerprint(vid: String, pid: String) -> MTPDeviceFingerprint {
    MTPDeviceFingerprint(
      vid: vid, pid: pid, bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
  }

  private func makeTestQuirk() -> DeviceQuirk {
    DeviceQuirk(
      id: "test-device-0001",
      deviceName: "Test Device",
      category: "phone",
      vid: 0xAAAA,
      pid: 0xBBBB
    )
  }

  private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(value)
  }
}
