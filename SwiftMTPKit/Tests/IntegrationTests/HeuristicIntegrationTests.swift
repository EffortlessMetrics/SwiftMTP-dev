// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
import XCTest

/// Integration tests that exercise the PTP-class heuristic and the
/// auto-disable mechanism for `GetObjectPropList` (0x9805).
///
/// Tests operate at two levels:
/// - **Unit-style**: call `EffectiveTuningBuilder.buildPolicy` and
///   `QuirkResolver.resolve` directly to verify flag values.
/// - **Simulation-style**: mutate `DevicePolicy.flags` to confirm the
///   auto-disable path described in `DeviceActor+PropList.swift` is
///   structurally sound (flags are mutable and a fresh policy resets them).
final class HeuristicIntegrationTests: XCTestCase {

  // MARK: - Test 1: PTP class heuristic applies correct flags

  func testPTPClassHeuristicBuildsCorrectPolicy() {
    // Interface class 0x06 = USB Still Image Capture (PTP/MTP cameras).
    // When no quirk entry is present, buildPolicy should apply ptpCameraDefaults().
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )

    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "PTP class 0x06 with no quirk should enable GetObjectPropList via heuristic")
    XCTAssertFalse(
      policy.flags.requiresKernelDetach,
      "PTP class 0x06 should not require kernel detach (cameras don't run a kernel driver)")
    XCTAssertTrue(
      policy.flags.prefersPropListEnumeration,
      "PTP class 0x06 should prefer batch proplist enumeration")
  }

  // MARK: - Test 2: Non-PTP class gets conservative defaults

  func testNonPTPClassGetsConservativeDefaults() {
    // Android MTP devices use vendor-specific class 0xFF — no proplist heuristic.
    let androidPolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0xFF
    )
    XCTAssertFalse(
      androidPolicy.flags.supportsGetObjectPropList,
      "Vendor-class 0xFF should not enable GetObjectPropList")

    // nil ifaceClass: conservative defaults apply.
    let nilPolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: nil
    )
    XCTAssertFalse(
      nilPolicy.flags.supportsGetObjectPropList,
      "nil ifaceClass should not enable GetObjectPropList")
    XCTAssertTrue(
      nilPolicy.flags.requiresKernelDetach,
      "Default QuirkFlags should require kernel detach")
  }

  // MARK: - Test 3: QuirkResolver propagates ifaceClass to buildPolicy

  func testQuirkResolverPropagatesIfaceClassHeuristic() {
    // Use a VID/PID that is definitely not in any real quirks database.
    // With an empty database, the resolver must fall through to the class heuristic.
    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0xBEEF,
      pid: 0xCAFE,
      interfaceClass: 0x06,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      epIn: 0x81,
      epOut: 0x02
    )

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: emptyDB)

    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "QuirkResolver should apply PTP heuristic when ifaceClass==0x06 and no quirk matches")
    XCTAssertFalse(
      policy.flags.requiresKernelDetach,
      "QuirkResolver should apply ptpCameraDefaults() via buildPolicy for class 0x06")
  }

  // MARK: - Test 4: Auto-disable mechanism — flags are mutable

  func testAutoDisableQuirkFlagMechanism() {
    // DeviceActor+PropList.swift performs:
    //   currentPolicy!.flags.supportsGetObjectPropList = false
    // This test verifies that DevicePolicy.flags is mutable (var) so the
    // auto-disable can actually take effect at runtime.
    var policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )

    XCTAssertTrue(policy.flags.supportsGetObjectPropList, "Should start enabled via heuristic")

    // Simulate what DeviceActor+PropList does on OperationNotSupported:
    policy.flags.supportsGetObjectPropList = false

    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "Flag should be false after simulated auto-disable")
  }

  // MARK: - Test 5: Fresh policy after auto-disable restores heuristic defaults

  func testFreshPolicyRestoresHeuristicAfterAutoDisable() {
    // The auto-disable only affects the in-memory DevicePolicy for the current
    // session.  A new buildPolicy call (next session / reconnect) must restore
    // the heuristic default so the device gets a fair chance on every connect.
    var policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    policy.flags.supportsGetObjectPropList = false
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)

    let freshPolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertTrue(
      freshPolicy.flags.supportsGetObjectPropList,
      "A fresh policy for a PTP class device must re-enable GetObjectPropList")
  }

  // MARK: - Test 6: PolicySources reflects class-heuristic provenance

  func testPolicySourcesReflectClassHeuristic() {
    // When the flags come from the class heuristic (not a quirk, not learned),
    // PolicySources.flagsSource should be .defaults.
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertEqual(
      policy.sources.flagsSource, .defaults,
      "Class heuristic flags must record .defaults as their source")
  }

  // MARK: - Test 7: VirtualMTPDevice — camera preset exposes proplist in device info

  func testCameraPresetDeviceInfoIncludesNoPropListOpcode() async throws {
    // Camera presets deliberately omit 0x9805 (GetObjectPropList) from their
    // operationsSupported set, mirroring real-world PTP cameras that gain
    // proplist support via the class heuristic rather than advertising it.
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let info = try await device.info

    // Confirm the camera preset does NOT advertise 0x9805:
    XCTAssertFalse(
      info.operationsSupported.contains(0x9805),
      "Camera preset should not advertise GetObjectPropList in operationsSupported")

    // But the PTP-class heuristic should still enable it at the policy layer:
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "Heuristic must enable proplist even when device doesn't advertise 0x9805")
  }

  // MARK: - Test 8: Android preset that includes proplist opcode

  func testAndroidPresetWithPropListHasOpcodeAdvertised() async throws {
    // samsungGalaxy is built with includePropList: true, so 0x9805 appears in
    // operationsSupported.  The policy layer for a non-PTP class device should
    // NOT enable the flag by default (it relies on the quirk DB instead).
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let info = try await device.info

    XCTAssertTrue(
      info.operationsSupported.contains(0x9805),
      "Samsung Galaxy preset should advertise GetObjectPropList in operationsSupported")

    // Without a quirk or PTP class, the default policy disables the flag.
    let conservativePolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0xFF  // Android vendor class
    )
    XCTAssertFalse(
      conservativePolicy.flags.supportsGetObjectPropList,
      "Android vendor-class device should not get proplist flag without an explicit quirk")
  }
}
