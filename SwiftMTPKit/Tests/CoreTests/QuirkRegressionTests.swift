// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Regression tests proving each quirk flag actually gates its associated code path.
final class QuirkRegressionTests: XCTestCase {

  // MARK: - stabilizeMs

  /// A quirk with stabilizeMs > 0 sets requireStabilization in resolvedFlags() and
  /// propagates the delay through EffectiveTuningBuilder.  The DeviceActor checks
  /// `initialTuning.stabilizeMs > 0` (DeviceActor.swift:500) before sleeping, so
  /// both assertions are required for the regression to be meaningful.
  func testStabilizeMsQuirkGatesStabilizationCodePath() throws {
    let withStabilize = DeviceQuirk(
      id: "test-stabilize",
      vid: 0xAAAA,
      pid: 0x0001,
      stabilizeMs: 100
      // No typed `flags` — exercises the legacy-synthesis path in resolvedFlags()
    )

    let withoutStabilize = DeviceQuirk(
      id: "test-no-stabilize",
      vid: 0xAAAA,
      pid: 0x0002
    )

    // resolvedFlags() synthesises requireStabilization from stabilizeMs when flags == nil
    XCTAssertTrue(
      withStabilize.resolvedFlags().requireStabilization,
      "resolvedFlags() must set requireStabilization when stabilizeMs > 0"
    )
    XCTAssertFalse(
      withoutStabilize.resolvedFlags().requireStabilization,
      "resolvedFlags() must NOT set requireStabilization when stabilizeMs is absent"
    )

    // EffectiveTuningBuilder must carry the delay value through to EffectiveTuning.stabilizeMs
    let tuningWith = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: withStabilize,
      overrides: nil
    )
    XCTAssertEqual(tuningWith.stabilizeMs, 100, "EffectiveTuning.stabilizeMs should be 100ms")

    let tuningWithout = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: withoutStabilize,
      overrides: nil
    )
    XCTAssertEqual(
      tuningWithout.stabilizeMs, 0,
      "EffectiveTuning.stabilizeMs should be 0 (default) when quirk omits stabilizeMs"
    )
  }

  // MARK: - resetReopenOnOpenSessionIOError ("stall recovery")

  /// The reset+reopen recovery ladder in DeviceActor (line 427) is enabled only when
  /// initialPolicy.flags.resetReopenOnOpenSessionIOError is true.  This test verifies
  /// the flag is faithfully preserved from DeviceQuirk.flags through resolvedFlags().
  func testResetReopenFlagGatesRecoveryLadder() throws {
    var recoveryFlags = QuirkFlags()
    recoveryFlags.resetReopenOnOpenSessionIOError = true

    let withRecovery = DeviceQuirk(
      id: "test-recovery",
      vid: 0xBBBB,
      pid: 0x0001,
      flags: recoveryFlags
    )

    let withoutRecovery = DeviceQuirk(
      id: "test-no-recovery",
      vid: 0xBBBB,
      pid: 0x0002
      // flags defaults to nil → QuirkFlags() → resetReopenOnOpenSessionIOError = false
    )

    XCTAssertTrue(
      withRecovery.resolvedFlags().resetReopenOnOpenSessionIOError,
      "Recovery ladder flag must be true when quirk sets resetReopenOnOpenSessionIOError"
    )
    XCTAssertFalse(
      withoutRecovery.resolvedFlags().resetReopenOnOpenSessionIOError,
      "Recovery ladder flag must be false when quirk omits resetReopenOnOpenSessionIOError"
    )

    // DevicePolicy propagation: the actor builds DevicePolicy from the resolved flags.
    let tuning = EffectiveTuning.defaults()
    let policyWith = DevicePolicy(tuning: tuning, flags: withRecovery.resolvedFlags())
    let policyWithout = DevicePolicy(tuning: tuning, flags: withoutRecovery.resolvedFlags())

    XCTAssertTrue(policyWith.flags.resetReopenOnOpenSessionIOError)
    XCTAssertFalse(policyWithout.flags.resetReopenOnOpenSessionIOError)
  }

  // MARK: - writeToSubfolderOnly

  /// DeviceActor+Transfer (line 261) reads policy?.flags.writeToSubfolderOnly to decide
  /// whether to resolve a subfolder target before writing.  This test confirms the flag
  /// propagates from a DeviceQuirk through resolvedFlags() and DevicePolicy.
  func testWriteToSubfolderFlagGatesWritePath() throws {
    var subfolderFlags = QuirkFlags()
    subfolderFlags.writeToSubfolderOnly = true
    subfolderFlags.preferredWriteFolder = "Download"

    let withSubfolder = DeviceQuirk(
      id: "test-subfolder",
      vid: 0xCCCC,
      pid: 0x0001,
      flags: subfolderFlags
    )

    let withoutSubfolder = DeviceQuirk(
      id: "test-no-subfolder",
      vid: 0xCCCC,
      pid: 0x0002
    )

    XCTAssertTrue(
      withSubfolder.resolvedFlags().writeToSubfolderOnly,
      "writeToSubfolderOnly must be true when set in quirk flags"
    )
    XCTAssertEqual(withSubfolder.resolvedFlags().preferredWriteFolder, "Download")

    XCTAssertFalse(
      withoutSubfolder.resolvedFlags().writeToSubfolderOnly,
      "writeToSubfolderOnly must default to false when quirk omits it"
    )
    XCTAssertNil(withoutSubfolder.resolvedFlags().preferredWriteFolder)

    let tuning = EffectiveTuning.defaults()
    let policyWith = DevicePolicy(tuning: tuning, flags: withSubfolder.resolvedFlags())
    XCTAssertTrue(policyWith.flags.writeToSubfolderOnly)
    XCTAssertEqual(policyWith.flags.preferredWriteFolder, "Download")
  }

  // MARK: - Promoted quirk governance

  /// validate-quirks.sh requires promoted entries to carry provenance fields.
  /// This test loads the live quirk database and asserts every promoted entry
  /// has both lastVerifiedDate and lastVerifiedBy populated.
  func testPromotedQuirkEntriesHaveRequiredEvidence() throws {
    let db = try QuirkDatabase.load()
    let promoted = db.entries.filter { $0.status == .promoted }

    for entry in promoted {
      XCTAssertNotNil(
        entry.lastVerifiedDate,
        "Promoted quirk '\(entry.id)' must have lastVerifiedDate"
      )
      XCTAssertNotNil(
        entry.lastVerifiedBy,
        "Promoted quirk '\(entry.id)' must have lastVerifiedBy"
      )
    }
  }
}
