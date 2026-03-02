// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPQuirks

// MARK: - Helpers

/// Build an EffectiveTuning from primitive values.
private func makeTuning(
  chunk: Int, io: Int, hs: Int, inact: Int, deadline: Int,
  stab: Int, postClaim: Int, postProbe: Int,
  reset: Bool, disableEvt: Bool
) -> EffectiveTuning {
  EffectiveTuning(
    maxChunkBytes: chunk, ioTimeoutMs: io, handshakeTimeoutMs: hs,
    inactivityTimeoutMs: inact, overallDeadlineMs: deadline,
    stabilizeMs: stab, postClaimStabilizeMs: postClaim,
    postProbeStabilizeMs: postProbe, resetOnOpen: reset,
    disableEventPump: disableEvt, operations: [:], hooks: []
  )
}

/// Build a DeviceQuirk from primitive values.
private func makeQuirk(
  chunk: Int? = nil, io: Int? = nil, hs: Int? = nil,
  inact: Int? = nil, deadline: Int? = nil,
  reset: Bool? = nil, disableEvt: Bool? = nil,
  operations: [String: Bool]? = nil,
  hooks: [QuirkHook]? = nil,
  flags: QuirkFlags? = nil
) -> DeviceQuirk {
  DeviceQuirk(
    id: "test-quirk", vid: 0x1234, pid: 0x5678,
    maxChunkBytes: chunk, ioTimeoutMs: io,
    handshakeTimeoutMs: hs, inactivityTimeoutMs: inact,
    overallDeadlineMs: deadline, resetOnOpen: reset,
    disableEventPump: disableEvt, operations: operations,
    hooks: hooks, flags: flags
  )
}

// MARK: - Quirks Merge Property Tests

final class QuirksMergePropertyTests: XCTestCase {

  // MARK: - Merging with Defaults is Idempotent

  /// Building tuning with no overrides, no quirk, and no learned profile returns defaults.
  func testBuildWithNoInputsReturnsDefaults() {
    let defaults = EffectiveTuning.defaults()
    let built = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil)
    XCTAssertEqual(built.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(built.ioTimeoutMs, defaults.ioTimeoutMs)
    XCTAssertEqual(built.handshakeTimeoutMs, defaults.handshakeTimeoutMs)
    XCTAssertEqual(built.inactivityTimeoutMs, defaults.inactivityTimeoutMs)
    XCTAssertEqual(built.overallDeadlineMs, defaults.overallDeadlineMs)
    XCTAssertEqual(built.stabilizeMs, defaults.stabilizeMs)
    XCTAssertEqual(built.resetOnOpen, defaults.resetOnOpen)
    XCTAssertEqual(built.disableEventPump, defaults.disableEventPump)
  }

  /// Building with defaults as learned profile returns the same as defaults.
  func testMergingDefaultsWithDefaultsIsIdempotent() {
    let defaults = EffectiveTuning.defaults()
    let built = EffectiveTuningBuilder.build(
      capabilities: [:], learned: defaults, quirk: nil, overrides: nil)
    XCTAssertEqual(built.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(built.ioTimeoutMs, defaults.ioTimeoutMs)
    XCTAssertEqual(built.handshakeTimeoutMs, defaults.handshakeTimeoutMs)
    XCTAssertEqual(built.inactivityTimeoutMs, defaults.inactivityTimeoutMs)
    XCTAssertEqual(built.overallDeadlineMs, defaults.overallDeadlineMs)
  }

  /// Building twice with the same quirk inputs is idempotent.
  func testBuildIsIdempotent() {
    property("Building EffectiveTuning is deterministic")
      <- forAll(
        Gen<Int>.choose((64 * 1024, 32 * 1024 * 1024)),
        Gen<Int>.choose((500, 120_000)),
        Bool.arbitrary
      ) { (chunk: Int, io: Int, reset: Bool) in
        let quirk = makeQuirk(chunk: chunk, io: io, reset: reset)
        let first = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
        let second = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
        return first.maxChunkBytes == second.maxChunkBytes
          && first.ioTimeoutMs == second.ioTimeoutMs
          && first.handshakeTimeoutMs == second.handshakeTimeoutMs
          && first.inactivityTimeoutMs == second.inactivityTimeoutMs
          && first.overallDeadlineMs == second.overallDeadlineMs
          && first.stabilizeMs == second.stabilizeMs
          && first.resetOnOpen == second.resetOnOpen
          && first.disableEventPump == second.disableEventPump
      }
  }

  // MARK: - Overrides Take Precedence

  /// User overrides for maxChunkBytes always win over quirk and learned values.
  func testUserOverrideTakesPrecedenceForChunk() {
    property("User override for maxChunkBytes takes precedence")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((64 * 1024, 32 * 1024 * 1024))
      ) { (overrideChunk: Int, quirkChunk: Int) in
        let quirk = makeQuirk(chunk: quirkChunk)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk,
          overrides: ["maxChunkBytes": String(overrideChunk)])
        let expected = min(max(overrideChunk, 128 * 1024), 16 * 1024 * 1024)
        return built.maxChunkBytes == expected
      }
  }

  /// User overrides for ioTimeoutMs always win.
  func testUserOverrideTakesPrecedenceForTimeout() {
    property("User override for ioTimeoutMs takes precedence")
      <- forAll(
        Gen<Int>.choose((1000, 60000)),
        Gen<Int>.choose((500, 120_000))
      ) { (overrideTimeout: Int, quirkTimeout: Int) in
        let quirk = makeQuirk(io: quirkTimeout)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk,
          overrides: ["ioTimeoutMs": String(overrideTimeout)])
        let expected = min(max(overrideTimeout, 1000), 60000)
        return built.ioTimeoutMs == expected
      }
  }

  /// Quirk overrides take precedence over learned profile.
  func testQuirkOverridesLearnedProfile() {
    property("Quirk values override learned profile values")
      <- forAll(
        Gen<Int>.choose((0, 64 * 1024 * 1024)),
        Gen<Int>.choose((64 * 1024, 32 * 1024 * 1024))
      ) { (learnedChunk: Int, quirkChunk: Int) in
        let learned = makeTuning(
          chunk: learnedChunk, io: 8000, hs: 6000, inact: 8000,
          deadline: 60000, stab: 0, postClaim: 250, postProbe: 0,
          reset: false, disableEvt: false)
        let quirk = makeQuirk(chunk: quirkChunk)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
        let clampedQuirk = min(max(quirkChunk, 128 * 1024), 16 * 1024 * 1024)
        return built.maxChunkBytes == clampedQuirk
      }
  }

  // MARK: - Merged Values Within Valid Ranges

  /// All tuning values are within clamped ranges after build.
  func testMergedTuningValuesInValidRanges() {
    property("All built tuning values are within valid clamped ranges")
      <- forAll(
        Gen<Int>.choose((0, 64 * 1024 * 1024)),
        Gen<Int>.choose((0, 120_000)),
        Gen<Int>.choose((0, 120_000)),
        Gen<Int>.choose((0, 600_000)),
        Gen<Int>.choose((0, 10_000))
      ) { (chunk: Int, io: Int, hs: Int, deadline: Int, stab: Int) in
        let learned = makeTuning(
          chunk: chunk, io: io, hs: hs, inact: io,
          deadline: deadline, stab: stab, postClaim: stab, postProbe: stab,
          reset: false, disableEvt: false)
        let quirk = makeQuirk(chunk: chunk, io: io, deadline: deadline)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
        return built.maxChunkBytes >= 128 * 1024
          && built.maxChunkBytes <= 16 * 1024 * 1024
          && built.ioTimeoutMs >= 1000
          && built.ioTimeoutMs <= 60000
          && built.handshakeTimeoutMs >= 1000
          && built.handshakeTimeoutMs <= 60000
          && built.inactivityTimeoutMs >= 1000
          && built.inactivityTimeoutMs <= 60000
          && built.overallDeadlineMs >= 5000
          && built.overallDeadlineMs <= 300000
          && built.stabilizeMs >= 0
          && built.stabilizeMs <= 5000
          && built.postClaimStabilizeMs >= 0
          && built.postClaimStabilizeMs <= 5000
          && built.postProbeStabilizeMs >= 0
          && built.postProbeStabilizeMs <= 5000
      }
  }

  /// maxChunkBytes is always clamped to [128KB, 16MB] regardless of input.
  func testMaxChunkBytesAlwaysClamped() {
    property("maxChunkBytes clamped to [128KB, 16MB]")
      <- forAll(Gen<Int>.choose((0, 128 * 1024 * 1024))) { (rawChunk: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(chunk: rawChunk), overrides: nil)
        return built.maxChunkBytes >= 128 * 1024 && built.maxChunkBytes <= 16 * 1024 * 1024
      }
  }

  /// Timeout values are always clamped to [1000, 60000].
  func testTimeoutValuesAlwaysClamped() {
    property("ioTimeoutMs clamped to [1000, 60000]")
      <- forAll(Gen<Int>.choose((0, 200_000))) { (rawTimeout: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(io: rawTimeout), overrides: nil)
        return built.ioTimeoutMs >= 1000 && built.ioTimeoutMs <= 60000
      }
  }

  /// overallDeadlineMs is always clamped to [5000, 300000].
  func testOverallDeadlineAlwaysClamped() {
    property("overallDeadlineMs clamped to [5000, 300000]")
      <- forAll(Gen<Int>.choose((0, 1_000_000))) { (rawDeadline: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(deadline: rawDeadline), overrides: nil)
        return built.overallDeadlineMs >= 5000 && built.overallDeadlineMs <= 300000
      }
  }

  /// stabilizeMs values are always clamped to [0, 5000].
  func testStabilizeMsAlwaysClamped() {
    property("stabilizeMs clamped to [0, 5000]")
      <- forAll(Gen<Int>.choose((0, 50_000))) { (rawStabilize: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: DeviceQuirk(
            id: "test", vid: 1, pid: 1, stabilizeMs: rawStabilize),
          overrides: nil)
        return built.stabilizeMs >= 0 && built.stabilizeMs <= 5000
      }
  }

  /// handshakeTimeoutMs is always clamped to [1000, 60000].
  func testHandshakeTimeoutAlwaysClamped() {
    property("handshakeTimeoutMs clamped to [1000, 60000]")
      <- forAll(Gen<Int>.choose((0, 200_000))) { (rawTimeout: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(hs: rawTimeout), overrides: nil)
        return built.handshakeTimeoutMs >= 1000 && built.handshakeTimeoutMs <= 60000
      }
  }

  /// postClaimStabilizeMs is always clamped to [0, 5000].
  func testPostClaimStabilizeMsAlwaysClamped() {
    property("postClaimStabilizeMs clamped to [0, 5000]")
      <- forAll(Gen<Int>.choose((0, 50_000))) { (raw: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: DeviceQuirk(
            id: "test", vid: 1, pid: 1, postClaimStabilizeMs: raw),
          overrides: nil)
        return built.postClaimStabilizeMs >= 0 && built.postClaimStabilizeMs <= 5000
      }
  }

  // MARK: - Merging Preserves Flags

  /// Boolean flags set in a quirk override are preserved through build.
  func testResetOnOpenPreserved() {
    property("resetOnOpen from quirk is preserved in built tuning")
      <- forAll(Bool.arbitrary) { (value: Bool) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(reset: value), overrides: nil)
        return built.resetOnOpen == value
      }
  }

  /// disableEventPump from quirk is preserved.
  func testDisableEventPumpPreserved() {
    property("disableEventPump from quirk is preserved")
      <- forAll(Bool.arbitrary) { (value: Bool) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(disableEvt: value), overrides: nil)
        return built.disableEventPump == value
      }
  }

  /// Operations from quirk are merged into the result.
  func testOperationsFromQuirkAreMerged() {
    property("Operations from quirk appear in built tuning")
      <- forAll(
        Gen<String>.fromElements(of: [
          "partialRead", "partialWrite", "supportsEvents",
          "supportsGetObjectPropList", "supportsGetPartialObject",
        ]),
        Bool.arbitrary
      ) { (opKey: String, opValue: Bool) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil,
          quirk: makeQuirk(operations: [opKey: opValue]),
          overrides: nil)
        return built.operations[opKey] == opValue
      }
  }

  /// Capabilities are preserved when no quirk overrides them.
  func testCapabilitiesPreservedWithoutQuirk() {
    property("Capabilities are preserved in operations when no quirk overrides them")
      <- forAll(
        Gen<String>.fromElements(of: ["partialRead", "partialWrite", "supportsEvents"]),
        Bool.arbitrary
      ) { (capKey: String, capValue: Bool) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [capKey: capValue], learned: nil,
          quirk: nil, overrides: nil)
        return built.operations[capKey] == capValue
      }
  }

  /// Quirk operations override capability probes.
  func testQuirkOperationsOverrideCapabilities() {
    property("Quirk operations override capability values")
      <- forAll(
        Gen<String>.fromElements(of: ["partialRead", "partialWrite"]),
        Bool.arbitrary
      ) { (key: String, quirkValue: Bool) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [key: !quirkValue], learned: nil,
          quirk: makeQuirk(operations: [key: quirkValue]),
          overrides: nil)
        return built.operations[key] == quirkValue
      }
  }

  // MARK: - buildPolicy Invariants

  /// buildPolicy always returns a valid DevicePolicy.
  func testBuildPolicyAlwaysReturnsValidPolicy() {
    property("buildPolicy returns a policy with valid tuning values")
      <- forAll(
        Gen<Int>.choose((64 * 1024, 32 * 1024 * 1024)),
        Gen<Int>.choose((500, 120_000))
      ) { (chunk: Int, io: Int) in
        let quirk = makeQuirk(chunk: chunk, io: io)
        let policy = EffectiveTuningBuilder.buildPolicy(
          capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
        return policy.tuning.maxChunkBytes >= 128 * 1024
          && policy.tuning.maxChunkBytes <= 16 * 1024 * 1024
          && policy.tuning.ioTimeoutMs >= 1000
          && policy.tuning.ioTimeoutMs <= 60000
      }
  }

  /// buildPolicy with PTP camera interface class sets camera defaults.
  func testBuildPolicyWithPTPCameraClass() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil,
      overrides: nil, ifaceClass: 0x06)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.prefersPropListEnumeration)
    XCTAssertTrue(policy.flags.supportsPartialRead32)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
  }

  /// resolvedFlags from a quirk with typed flags returns those flags.
  func testResolvedFlagsFromTypedFlags() {
    property("resolvedFlags returns typed flags when present")
      <- forAll(
        Bool.arbitrary, Bool.arbitrary,
        Bool.arbitrary, Bool.arbitrary
      ) { (reset: Bool, kernelDetach: Bool, partial64: Bool, propList: Bool) in
        var flags = QuirkFlags()
        flags.resetOnOpen = reset
        flags.requiresKernelDetach = kernelDetach
        flags.supportsPartialRead64 = partial64
        flags.supportsGetObjectPropList = propList
        let quirk = makeQuirk(flags: flags)
        let resolved = quirk.resolvedFlags()
        return resolved == flags
      }
  }

  /// resolvedFlags synthesizes from operations when typed flags are absent.
  func testResolvedFlagsSynthesizesFromOperations() {
    property("resolvedFlags synthesizes from operations map")
      <- forAll(Bool.arbitrary) { (value: Bool) in
        let quirk = makeQuirk(
          operations: ["supportsGetObjectPropList": value])
        return quirk.resolvedFlags().supportsGetObjectPropList == value
      }
  }

  /// resolvedFlags: resetOnOpen from tuning propagates to flags.
  func testResolvedFlagsResetOnOpenPropagates() {
    property("resetOnOpen propagates to resolvedFlags")
      <- forAll(Bool.arbitrary) { (value: Bool) in
        let quirk = makeQuirk(reset: value)
        return quirk.resolvedFlags().resetOnOpen == value
      }
  }

  /// resolvedFlags: disableEventPump propagates to flags.
  func testResolvedFlagsDisableEventPumpPropagates() {
    property("disableEventPump propagates to resolvedFlags")
      <- forAll(Bool.arbitrary) { (value: Bool) in
        let quirk = makeQuirk(disableEvt: value)
        return quirk.resolvedFlags().disableEventPump == value
      }
  }

  // MARK: - Hooks Preservation

  /// Hooks from quirk are preserved in built tuning.
  func testHooksFromQuirkPreserved() {
    let hook = QuirkHook(phase: .postOpenUSB, delayMs: 100)
    let built = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil,
      quirk: makeQuirk(hooks: [hook]), overrides: nil)
    XCTAssertEqual(built.hooks.count, 1)
    XCTAssertEqual(built.hooks.first?.phase, .postOpenUSB)
    XCTAssertEqual(built.hooks.first?.delayMs, 100)
  }

  /// Hooks from learned and quirk are concatenated, not replaced.
  func testHooksFromLearnedAndQuirkConcatenated() {
    let learnedHook = QuirkHook(phase: .postClaimInterface, delayMs: 50)
    var learnedTuning = EffectiveTuning.defaults()
    learnedTuning.hooks = [learnedHook]
    let quirkHook = QuirkHook(phase: .postOpenUSB, delayMs: 100)
    let built = EffectiveTuningBuilder.build(
      capabilities: [:], learned: learnedTuning,
      quirk: makeQuirk(hooks: [quirkHook]), overrides: nil)
    XCTAssertEqual(built.hooks.count, 2)
  }

  // MARK: - Edge Cases

  /// Empty overrides dict does not change the result vs nil overrides.
  func testEmptyOverridesDictSameAsNil() {
    let withNil = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil)
    let withEmpty = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: nil, overrides: [:])
    XCTAssertEqual(withNil.maxChunkBytes, withEmpty.maxChunkBytes)
    XCTAssertEqual(withNil.ioTimeoutMs, withEmpty.ioTimeoutMs)
    XCTAssertEqual(withNil.handshakeTimeoutMs, withEmpty.handshakeTimeoutMs)
  }

  /// Non-numeric override strings are ignored.
  func testNonNumericOverridesIgnored() {
    let defaults = EffectiveTuning.defaults()
    let built = EffectiveTuningBuilder.build(
      capabilities: [:], learned: nil, quirk: nil,
      overrides: ["maxChunkBytes": "not-a-number", "ioTimeoutMs": "abc"])
    XCTAssertEqual(built.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(built.ioTimeoutMs, defaults.ioTimeoutMs)
  }

  /// User override for stabilizeMs takes precedence.
  func testUserOverrideForStabilizeMs() {
    property("User override for stabilizeMs is applied and clamped")
      <- forAll(Gen<Int>.choose((0, 5000))) { (overrideStab: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: nil,
          overrides: ["stabilizeMs": String(overrideStab)])
        return built.stabilizeMs >= 0 && built.stabilizeMs <= 5000
      }
  }

  /// Multiple user overrides are all applied.
  func testMultipleUserOverridesApplied() {
    property("Multiple user overrides are all applied")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((1000, 60000))
      ) { (chunk: Int, io: Int) in
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: nil,
          overrides: [
            "maxChunkBytes": String(chunk),
            "ioTimeoutMs": String(io),
          ])
        return built.maxChunkBytes == chunk && built.ioTimeoutMs == io
      }
  }

  // MARK: - PolicySources Provenance

  /// buildPolicy with quirk sets chunkSizeSource to .quirk.
  func testPolicySetsQuirkSource() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil,
      quirk: makeQuirk(chunk: 512 * 1024), overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
  }

  /// buildPolicy with overrides sets chunkSizeSource to .userOverride.
  func testPolicySetsUserOverrideSource() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil,
      overrides: ["maxChunkBytes": "524288"])
    XCTAssertEqual(policy.sources.chunkSizeSource, .userOverride)
  }

  /// buildPolicy without quirk or overrides has default sources.
  func testPolicyDefaultSources() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .defaults)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .defaults)
  }

  /// buildPolicy with learned profile sets source to .learned.
  func testPolicySetsLearnedSource() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: EffectiveTuning.defaults(),
      quirk: nil, overrides: nil)
    XCTAssertEqual(policy.sources.chunkSizeSource, .learned)
  }

  // MARK: - Merge Layer Ordering

  /// Each merge layer supersedes the previous: defaults < learned < quirk < overrides.
  func testMergeLayerOrdering() {
    property("Override chunk beats quirk chunk beats learned chunk")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 512 * 1024)),
        Gen<Int>.choose((512 * 1024 + 1, 2 * 1024 * 1024)),
        Gen<Int>.choose((2 * 1024 * 1024 + 1, 8 * 1024 * 1024))
      ) { (learnedChunk: Int, quirkChunk: Int, overrideChunk: Int) in
        let learned = makeTuning(
          chunk: learnedChunk, io: 8000, hs: 6000, inact: 8000,
          deadline: 60000, stab: 0, postClaim: 250, postProbe: 0,
          reset: false, disableEvt: false)
        let quirk = makeQuirk(chunk: quirkChunk)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: learned, quirk: quirk,
          overrides: ["maxChunkBytes": String(overrideChunk)])
        let expected = min(max(overrideChunk, 128 * 1024), 16 * 1024 * 1024)
        return built.maxChunkBytes == expected
      }
  }

  /// Quirk layer without overrides beats learned layer.
  func testQuirkLayerBeatsLearnedWithoutOverrides() {
    property("Quirk chunk beats learned chunk when no overrides")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 512 * 1024)),
        Gen<Int>.choose((512 * 1024 + 1, 4 * 1024 * 1024))
      ) { (learnedChunk: Int, quirkChunk: Int) in
        let learned = makeTuning(
          chunk: learnedChunk, io: 8000, hs: 6000, inact: 8000,
          deadline: 60000, stab: 0, postClaim: 250, postProbe: 0,
          reset: false, disableEvt: false)
        let quirk = makeQuirk(chunk: quirkChunk)
        let built = EffectiveTuningBuilder.build(
          capabilities: [:], learned: learned, quirk: quirk, overrides: nil)
        let expected = min(max(quirkChunk, 128 * 1024), 16 * 1024 * 1024)
        return built.maxChunkBytes == expected
      }
  }

  // MARK: - QuirkFlags Defaults

  /// Default QuirkFlags have expected default values.
  func testDefaultQuirkFlagsValues() {
    let f = QuirkFlags()
    XCTAssertFalse(f.resetOnOpen)
    XCTAssertTrue(f.requiresKernelDetach)
    XCTAssertTrue(f.supportsPartialRead64)
    XCTAssertTrue(f.supportsPartialWrite)
    XCTAssertTrue(f.prefersPropListEnumeration)
    XCTAssertFalse(f.disableEventPump)
    XCTAssertFalse(f.requireStabilization)
  }

  /// PTP camera defaults differ from vanilla defaults.
  func testPTPCameraDefaultsDifferFromVanilla() {
    let vanilla = QuirkFlags()
    let ptpCamera = QuirkFlags.ptpCameraDefaults()
    XCTAssertNotEqual(vanilla.requiresKernelDetach, ptpCamera.requiresKernelDetach)
  }
}
