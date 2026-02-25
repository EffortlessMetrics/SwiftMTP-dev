// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

final class QuirkSystemTests: XCTestCase {

  func testMergeOrder() throws {
    // Test that layers are applied in the correct order:
    // defaults → capabilities → learned → quirk → overrides

    let capabilities: [String: Bool] = ["supportsLargeTransfers": true]

    // Create mock learned profile (as EffectiveTuning)
    var learned = EffectiveTuning.defaults()
    learned.maxChunkBytes = 4_194_304  // 4MB

    // Create mock quirk
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x2717,
      pid: 0xff10,
      maxChunkBytes: 8_388_608  // 8MB
    )

    // Create user override
    let overrides = ["maxChunkBytes": "2097152"]  // 2MB

    // Build effective tuning
    let tuning = EffectiveTuningBuilder.build(
      capabilities: capabilities,
      learned: learned,
      quirk: quirk,
      overrides: overrides
    )

    // User override should win (2MB)
    XCTAssertEqual(tuning.maxChunkBytes, 2_097_152, "User override should take precedence")
    XCTAssertEqual(tuning.operations["supportsLargeTransfers"], true)
  }

  func testSchemaBoundsClamping() throws {
    // Test chunk size clamping via builder
    let lowChunk = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: ["maxChunkBytes": "1000"]  // Too small
    )
    XCTAssertGreaterThanOrEqual(
      lowChunk.maxChunkBytes, 131_072, "Chunk size should be clamped to minimum")

    let highChunk = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: ["maxChunkBytes": "100000000"]  // Too large
    )
    XCTAssertLessThanOrEqual(
      highChunk.maxChunkBytes, 16_777_216, "Chunk size should be clamped to maximum")

    // Test timeout clamping
    let lowTimeout = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: ["ioTimeoutMs": "500"]  // Too small
    )
    XCTAssertGreaterThanOrEqual(
      lowTimeout.ioTimeoutMs, 1_000, "I/O timeout should be clamped to minimum")
  }

  // MARK: - Device-Specific Quirk Match Tests

  func testOnePlus3TQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x2a70, pid: 0xf003,
      bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(quirk, "OnePlus 3T should match a quirk entry")
    XCTAssertEqual(quirk?.id, "oneplus-3t-f003")
  }

  func testPixel7QuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x18d1, pid: 0x4ee1,
      bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(quirk, "Pixel 7 should match a quirk entry")
    XCTAssertEqual(quirk?.id, "google-pixel-7-4ee1")
  }

  func testOnePlus3TEffectiveTuning() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x2a70, pid: 0xf003,
      bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: ["partialRead": true, "partialWrite": true],
      learned: nil,
      quirk: quirk,
      overrides: nil
    )
    XCTAssertEqual(tuning.resetOnOpen, false, "OnePlus 3T should not need resetOnOpen")
    XCTAssertEqual(tuning.maxChunkBytes, 1_048_576, "OnePlus 3T chunk size should be 1MB")
    XCTAssertEqual(tuning.handshakeTimeoutMs, 6_000)
    XCTAssertEqual(tuning.ioTimeoutMs, 8_000)
    XCTAssertEqual(tuning.stabilizeMs, 200)
  }

  func testPixel7EffectiveTuning() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x18d1, pid: 0x4ee1,
      bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: nil
    )
    XCTAssertEqual(tuning.resetOnOpen, false, "Pixel 7 quirk has resetOnOpen=false")
    XCTAssertEqual(tuning.maxChunkBytes, 2_097_152, "Pixel 7 chunk size should be 2MB")
    XCTAssertEqual(tuning.handshakeTimeoutMs, 20_000)
    XCTAssertEqual(tuning.stabilizeMs, 3_000)
  }

  func testLearnedProfileFingerprintEvolution() throws {
    let fingerprint1 = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: "0318",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )

    let fingerprint2 = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: "0319",  // Different bcdDevice
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
    )

    let profile = LearnedProfile(fingerprint: fingerprint1, successRate: 0.95)

    let manager = LearnedProfileManager(storageURL: URL(fileURLWithPath: "/tmp/test-profiles.json"))

    // Profile should expire when bcdDevice changes
    XCTAssertTrue(
      manager.shouldExpireProfile(profile, newFingerprint: fingerprint2),
      "Profile should expire when bcdDevice changes")
  }
}
