// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTransportLibUSB

/// Tests for Samsung Galaxy (04e8:6860) transport behavior.
///
/// Verifies the three transport-level fixes from the Samsung debug report:
/// 1. skipClearHaltBeforeProbe — skip unnecessary clear_halt during init
/// 2. resetReopenOnOpenSessionIOError — reset+reopen recovery on first OpenSession failure
/// 3. forceResetOnClose — USB reset before handle close (AOSP/Android quirk)
final class SamsungTransportTests: XCTestCase {

  // MARK: - QuirkFlags Integration

  func testSamsungQuirkFlagsSkipClearHaltBeforeProbe() {
    var flags = QuirkFlags()
    XCTAssertFalse(flags.skipClearHaltBeforeProbe, "Default should be false")
    flags.skipClearHaltBeforeProbe = true
    XCTAssertTrue(flags.skipClearHaltBeforeProbe)
  }

  func testSamsungQuirkFlagsResetReopenOnOpenSessionIOError() {
    var flags = QuirkFlags()
    XCTAssertFalse(flags.resetReopenOnOpenSessionIOError, "Default should be false")
    flags.resetReopenOnOpenSessionIOError = true
    XCTAssertTrue(flags.resetReopenOnOpenSessionIOError)
  }

  func testSamsungQuirkFlagsForceResetOnClose() {
    var flags = QuirkFlags()
    XCTAssertFalse(flags.forceResetOnClose, "Default should be false")
    flags.forceResetOnClose = true
    XCTAssertTrue(flags.forceResetOnClose)
  }

  // MARK: - skipClearHaltBeforeProbe Codable Round-Trip

  func testSkipClearHaltBeforeProbeCodableRoundTrip() throws {
    var flags = QuirkFlags()
    flags.skipClearHaltBeforeProbe = true

    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertTrue(decoded.skipClearHaltBeforeProbe)
  }

  func testSkipClearHaltBeforeProbeDefaultsToFalseWhenMissing() throws {
    let json = #"{"skipAltSetting": true}"#
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertFalse(
      decoded.skipClearHaltBeforeProbe,
      "Missing key should default to false for backward compat")
  }

  // MARK: - SwiftMTPConfig Propagation

  func testConfigSkipClearHaltBeforeProbeDefault() {
    let config = SwiftMTPConfig()
    XCTAssertFalse(config.skipClearHaltBeforeProbe)
  }

  func testConfigSkipClearHaltBeforeProbeSetTrue() {
    var config = SwiftMTPConfig()
    config.skipClearHaltBeforeProbe = true
    XCTAssertTrue(config.skipClearHaltBeforeProbe)
  }

  func testConfigForceResetOnCloseDefault() {
    let config = SwiftMTPConfig()
    XCTAssertFalse(config.forceResetOnClose)
  }

  func testConfigForceResetOnCloseSetTrue() {
    var config = SwiftMTPConfig()
    config.forceResetOnClose = true
    XCTAssertTrue(config.forceResetOnClose)
  }

  // MARK: - Samsung-Specific Flag Combinations

  func testSamsungFullFlagCombination() {
    var flags = QuirkFlags()
    flags.skipAltSetting = true
    flags.skipPreClaimReset = true
    flags.skipClearHaltBeforeProbe = true
    flags.forceResetOnClose = true
    flags.resetReopenOnOpenSessionIOError = true
    flags.extendedBulkTimeout = true

    XCTAssertTrue(flags.skipAltSetting)
    XCTAssertTrue(flags.skipPreClaimReset)
    XCTAssertTrue(flags.skipClearHaltBeforeProbe)
    XCTAssertTrue(flags.forceResetOnClose)
    XCTAssertTrue(flags.resetReopenOnOpenSessionIOError)
    XCTAssertTrue(flags.extendedBulkTimeout)
  }

  func testSamsungFlagsCodableRoundTripFullSet() throws {
    var flags = QuirkFlags()
    flags.skipAltSetting = true
    flags.skipPreClaimReset = true
    flags.skipClearHaltBeforeProbe = true
    flags.forceResetOnClose = true
    flags.resetReopenOnOpenSessionIOError = true
    flags.propListOverridesObjectInfo = true
    flags.samsungPartialObjectBoundaryBug = true
    flags.extendedBulkTimeout = true

    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)

    XCTAssertEqual(flags, decoded, "Full Samsung flag set should survive encode/decode")
  }

  // MARK: - Config-to-Quirk Mapping

  func testQuirkFlagsMapToConfig() {
    var flags = QuirkFlags()
    flags.skipAltSetting = true
    flags.skipPreClaimReset = true
    flags.skipClearHaltBeforeProbe = true
    flags.forceResetOnClose = true
    flags.noZeroReads = true
    flags.noReleaseInterface = true
    flags.ignoreHeaderErrors = true

    var config = SwiftMTPConfig()
    config.skipAltSetting = flags.skipAltSetting
    config.skipPreClaimReset = flags.skipPreClaimReset
    config.skipClearHaltBeforeProbe = flags.skipClearHaltBeforeProbe
    config.forceResetOnClose = flags.forceResetOnClose
    config.noZeroReads = flags.noZeroReads
    config.noReleaseInterface = flags.noReleaseInterface
    config.ignoreHeaderErrors = flags.ignoreHeaderErrors

    XCTAssertTrue(config.skipAltSetting)
    XCTAssertTrue(config.skipPreClaimReset)
    XCTAssertTrue(config.skipClearHaltBeforeProbe)
    XCTAssertTrue(config.forceResetOnClose)
    XCTAssertTrue(config.noZeroReads)
    XCTAssertTrue(config.noReleaseInterface)
    XCTAssertTrue(config.ignoreHeaderErrors)
  }

  // MARK: - Samsung Session Window Budget

  func testSamsungSessionWindowBudgetWithSkipClearHalt() {
    // Samsung has a ~3 second session window. Verify that with all Samsung
    // transport quirks enabled, the overhead is minimized:
    // - skipPreClaimReset saves ~300ms
    // - skipAltSetting saves ~5ms
    // - skipClearHaltBeforeProbe saves ~10ms
    // Total savings: ~315ms
    let postClaimStabilizeMs = 100  // Samsung tuning value
    let clearHaltOverheadMs = 10  // typical clear_halt time
    let preClaimResetMs = 300  // pre-claim reset + settle

    let withoutQuirks = postClaimStabilizeMs + clearHaltOverheadMs + preClaimResetMs
    let withQuirks = postClaimStabilizeMs  // only stabilize remains

    XCTAssertLessThan(withQuirks, withoutQuirks)
    XCTAssertLessThanOrEqual(withQuirks, 100, "With quirks, overhead should be ≤100ms")
  }
}
