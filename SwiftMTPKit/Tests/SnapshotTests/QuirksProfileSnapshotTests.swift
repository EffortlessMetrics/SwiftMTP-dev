// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Snapshot tests for quirks profile construction, flag resolution,
/// tuning parameter merging, and policy building across different
/// device categories.
final class QuirksProfileSnapshotTests: XCTestCase {

  // MARK: - 1. Default QuirkFlags Profile

  func testDefaultFlagsTransportLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.resetOnOpen, false)
    XCTAssertEqual(flags.requiresKernelDetach, true)
    XCTAssertEqual(flags.needsLongerOpenTimeout, false)
  }

  func testDefaultFlagsProtocolLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.requiresSessionBeforeDeviceInfo, false)
    XCTAssertEqual(flags.transactionIdResetsOnSession, false)
    XCTAssertEqual(flags.resetReopenOnOpenSessionIOError, false)
  }

  func testDefaultFlagsTransferLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.supportsPartialRead64, true)
    XCTAssertEqual(flags.supportsPartialRead32, true)
    XCTAssertEqual(flags.supportsPartialWrite, true)
    XCTAssertEqual(flags.prefersPropListEnumeration, true)
    XCTAssertEqual(flags.needsShortReads, false)
    XCTAssertEqual(flags.stallOnLargeReads, false)
  }

  func testDefaultFlagsSessionLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.disableEventPump, false)
    XCTAssertEqual(flags.requireStabilization, false)
    XCTAssertEqual(flags.skipPTPReset, false)
  }

  func testDefaultFlagsWriteLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.writeToSubfolderOnly, false)
    XCTAssertNil(flags.preferredWriteFolder)
    XCTAssertEqual(flags.forceFFFFFFFForSendObject, false)
    XCTAssertEqual(flags.emptyDatesInSendObject, false)
    XCTAssertEqual(flags.unknownSizeInSendObjectInfo, false)
  }

  func testDefaultFlagsPropertyLayer() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.skipGetObjectPropValue, false)
    XCTAssertEqual(flags.supportsGetObjectPropList, false)
    XCTAssertEqual(flags.supportsGetPartialObject, false)
  }

  func testDefaultFlagsDeviceClassHint() {
    let flags = QuirkFlags()
    XCTAssertEqual(flags.cameraClass, false)
  }

  // MARK: - 2. PTP Camera Defaults Profile

  func testPTPCameraDefaultsKernelDetach() {
    let flags = QuirkFlags.ptpCameraDefaults()
    XCTAssertEqual(flags.requiresKernelDetach, false)
  }

  func testPTPCameraDefaultsPropList() {
    let flags = QuirkFlags.ptpCameraDefaults()
    XCTAssertEqual(flags.supportsGetObjectPropList, true)
    XCTAssertEqual(flags.prefersPropListEnumeration, true)
  }

  func testPTPCameraDefaultsPartialRead() {
    let flags = QuirkFlags.ptpCameraDefaults()
    XCTAssertEqual(flags.supportsPartialRead32, true)
  }

  func testPTPCameraDefaultsRetainsOtherDefaults() {
    let flags = QuirkFlags.ptpCameraDefaults()
    XCTAssertEqual(flags.resetOnOpen, false)
    XCTAssertEqual(flags.disableEventPump, false)
    XCTAssertEqual(flags.writeToSubfolderOnly, false)
    XCTAssertEqual(flags.cameraClass, false)
  }

  // MARK: - 3. Samsung Profile (via QuirkDatabase)

  func testSamsungQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x04E8, pid: 0x6860,
      bcdDevice: nil, ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "samsung-android-6860")
  }

  func testSamsungPolicyResolution() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "04e8", pid: "6860", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "ff", subclass: "00", protocol: "00"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertGreaterThan(policy.tuning.ioTimeoutMs, 0)
    XCTAssertGreaterThan(policy.tuning.maxChunkBytes, 0)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  // MARK: - 4. Canon Profile

  func testCanonQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x04A9, pid: 0x3139,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "canon-eos-rebel-3139")
  }

  func testCanonPolicyResolution() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "04a9", pid: "3139", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertGreaterThan(policy.tuning.maxChunkBytes, 0)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  // MARK: - 5. Android Default Profile (Unknown Device)

  func testAndroidDefaultPolicyNoQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0xAAAA, pid: 0xBBBB,
      bcdDevice: nil, ifaceClass: 0xFF, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNil(match)
  }

  func testAndroidDefaultPolicyFlags() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "aaaa", pid: "bbbb", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "ff", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    // Vendor-specific class uses conservative defaults
    XCTAssertEqual(policy.flags.requiresKernelDetach, true)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, false)
  }

  func testPTPDefaultPolicyFlags() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "aaaa", pid: "bbbb", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    // PTP class uses camera defaults
    XCTAssertEqual(policy.flags.requiresKernelDetach, false)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, true)
  }

  // MARK: - 6. Merged Profile Output (EffectiveTuningBuilder)

  func testDefaultTuningValues() {
    let tuning = EffectiveTuning.defaults()
    XCTAssertEqual(tuning.maxChunkBytes, 1 << 20)  // 1 MiB
    XCTAssertEqual(tuning.ioTimeoutMs, 8000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 6000)
    XCTAssertEqual(tuning.inactivityTimeoutMs, 8000)
    XCTAssertEqual(tuning.overallDeadlineMs, 60000)
    XCTAssertEqual(tuning.stabilizeMs, 0)
    XCTAssertEqual(tuning.postClaimStabilizeMs, 250)
    XCTAssertEqual(tuning.postProbeStabilizeMs, 0)
    XCTAssertEqual(tuning.resetOnOpen, false)
    XCTAssertEqual(tuning.disableEventPump, false)
    XCTAssertTrue(tuning.operations.isEmpty)
    XCTAssertTrue(tuning.hooks.isEmpty)
  }

  func testBuildWithCapabilitiesOnly() {
    let capabilities: [String: Bool] = [
      "supportsGetPartialObject64": true,
      "supportsSendPartialObject": true,
    ]
    let tuning = EffectiveTuningBuilder.build(
      capabilities: capabilities,
      learned: nil,
      quirk: nil,
      overrides: nil
    )
    XCTAssertEqual(tuning.operations["supportsGetPartialObject64"], true)
    XCTAssertEqual(tuning.operations["supportsSendPartialObject"], true)
    // Defaults preserved
    XCTAssertEqual(tuning.maxChunkBytes, 1 << 20)
    XCTAssertEqual(tuning.ioTimeoutMs, 8000)
  }

  func testBuildWithQuirkOverrides() {
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 2_097_152,
      ioTimeoutMs: 15000,
      handshakeTimeoutMs: 10000,
      stabilizeMs: 400
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: nil
    )
    XCTAssertEqual(tuning.maxChunkBytes, 2_097_152)
    XCTAssertEqual(tuning.ioTimeoutMs, 15000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 10000)
    XCTAssertEqual(tuning.stabilizeMs, 400)
  }

  func testBuildWithUserOverrides() {
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: [
        "maxChunkBytes": "4194304",
        "ioTimeoutMs": "30000",
      ]
    )
    XCTAssertEqual(tuning.maxChunkBytes, 4_194_304)
    XCTAssertEqual(tuning.ioTimeoutMs, 30000)
  }

  func testBuildUserOverridesOverrideQuirk() {
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 1_048_576,
      ioTimeoutMs: 10000
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: ["maxChunkBytes": "4194304"]
    )
    // User override wins over quirk
    XCTAssertEqual(tuning.maxChunkBytes, 4_194_304)
    // Quirk value preserved where no override
    XCTAssertEqual(tuning.ioTimeoutMs, 10000)
  }

  func testBuildClampsMinimums() {
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: [
        "maxChunkBytes": "1",      // below minimum (128KB)
        "ioTimeoutMs": "1",         // below minimum (1000ms)
        "overallDeadlineMs": "1",   // below minimum (5000ms)
      ]
    )
    XCTAssertGreaterThanOrEqual(tuning.maxChunkBytes, 128 * 1024)
    XCTAssertGreaterThanOrEqual(tuning.ioTimeoutMs, 1000)
    XCTAssertGreaterThanOrEqual(tuning.overallDeadlineMs, 5000)
  }

  func testBuildClampsMaximums() {
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: [
        "maxChunkBytes": "999999999",    // above maximum (16MB)
        "ioTimeoutMs": "999999",          // above maximum (60000ms)
        "overallDeadlineMs": "999999999", // above maximum (300000ms)
      ]
    )
    XCTAssertLessThanOrEqual(tuning.maxChunkBytes, 16 * 1024 * 1024)
    XCTAssertLessThanOrEqual(tuning.ioTimeoutMs, 60000)
    XCTAssertLessThanOrEqual(tuning.overallDeadlineMs, 300000)
  }

  func testBuildWithLearnedProfile() {
    let learned = EffectiveTuning(
      maxChunkBytes: 2_097_152,
      ioTimeoutMs: 20000,
      handshakeTimeoutMs: 8000,
      inactivityTimeoutMs: 12000,
      overallDeadlineMs: 120000,
      stabilizeMs: 200,
      postClaimStabilizeMs: 300,
      postProbeStabilizeMs: 100,
      resetOnOpen: false,
      disableEventPump: false,
      operations: ["supportsGetPartialObject64": true],
      hooks: []
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: learned,
      quirk: nil,
      overrides: nil
    )
    XCTAssertEqual(tuning.maxChunkBytes, 2_097_152)
    XCTAssertEqual(tuning.ioTimeoutMs, 20000)
    XCTAssertEqual(tuning.operations["supportsGetPartialObject64"], true)
  }

  func testBuildQuirkOverridesLearned() {
    let learned = EffectiveTuning(
      maxChunkBytes: 2_097_152,
      ioTimeoutMs: 20000,
      handshakeTimeoutMs: 8000,
      inactivityTimeoutMs: 12000,
      overallDeadlineMs: 120000,
      stabilizeMs: 200,
      postClaimStabilizeMs: 300,
      postProbeStabilizeMs: 100,
      resetOnOpen: false,
      disableEventPump: false,
      operations: [:],
      hooks: []
    )
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 1_048_576  // smaller than learned
    )
    let tuning = EffectiveTuningBuilder.build(
      capabilities: [:],
      learned: learned,
      quirk: quirk,
      overrides: nil
    )
    // Quirk overrides learned
    XCTAssertEqual(tuning.maxChunkBytes, 1_048_576)
    // Learned value preserved where quirk doesn't specify
    XCTAssertEqual(tuning.ioTimeoutMs, 20000)
  }

  // MARK: - 7. DevicePolicy BuildPolicy Snapshots

  func testBuildPolicyWithQuirk() {
    var testFlags = QuirkFlags()
    testFlags.writeToSubfolderOnly = true
    testFlags.preferredWriteFolder = "Download"
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x1234, pid: 0x5678,
      flags: testFlags
    )
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: nil
    )
    XCTAssertEqual(policy.flags.writeToSubfolderOnly, true)
    XCTAssertEqual(policy.flags.preferredWriteFolder, "Download")
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  func testBuildPolicyPTPCameraHeuristic() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertEqual(policy.flags.requiresKernelDetach, false)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, true)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
  }

  func testBuildPolicyNoQuirkNoClass() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: nil
    )
    XCTAssertEqual(policy.flags.requiresKernelDetach, true)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, false)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
  }

  func testBuildPolicyUserOverrideSources() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: ["maxChunkBytes": "2097152"]
    )
    XCTAssertEqual(policy.sources.chunkSizeSource, .userOverride)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .userOverride)
  }

  func testBuildPolicyQuirkSources() {
    let quirk = DeviceQuirk(
      id: "test-device",
      vid: 0x1234, pid: 0x5678
    )
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: quirk,
      overrides: nil
    )
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
    XCTAssertEqual(policy.sources.ioTimeoutSource, .quirk)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  // MARK: - 8. QuirkFlags JSON Round-Trip Snapshots

  func testQuirkFlagsWriteLevelRoundTrip() throws {
    var flags = QuirkFlags()
    flags.writeToSubfolderOnly = true
    flags.preferredWriteFolder = "DCIM"
    flags.forceFFFFFFFForSendObject = true
    flags.emptyDatesInSendObject = true
    flags.unknownSizeInSendObjectInfo = true
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertEqual(decoded.writeToSubfolderOnly, true)
    XCTAssertEqual(decoded.preferredWriteFolder, "DCIM")
    XCTAssertEqual(decoded.forceFFFFFFFForSendObject, true)
    XCTAssertEqual(decoded.emptyDatesInSendObject, true)
    XCTAssertEqual(decoded.unknownSizeInSendObjectInfo, true)
  }

  func testQuirkFlagsProtocolLevelRoundTrip() throws {
    var flags = QuirkFlags()
    flags.requiresSessionBeforeDeviceInfo = true
    flags.transactionIdResetsOnSession = true
    flags.resetReopenOnOpenSessionIOError = true
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertEqual(decoded.requiresSessionBeforeDeviceInfo, true)
    XCTAssertEqual(decoded.transactionIdResetsOnSession, true)
    XCTAssertEqual(decoded.resetReopenOnOpenSessionIOError, true)
  }

  func testQuirkFlagsTransferLevelRoundTrip() throws {
    var flags = QuirkFlags()
    flags.supportsPartialRead64 = false
    flags.supportsPartialRead32 = false
    flags.supportsPartialWrite = false
    flags.needsShortReads = true
    flags.stallOnLargeReads = true
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertEqual(decoded.supportsPartialRead64, false)
    XCTAssertEqual(decoded.supportsPartialRead32, false)
    XCTAssertEqual(decoded.supportsPartialWrite, false)
    XCTAssertEqual(decoded.needsShortReads, true)
    XCTAssertEqual(decoded.stallOnLargeReads, true)
  }

  // MARK: - 9. DeviceQuirk Construction and ResolvedFlags

  func testDeviceQuirkResolvedFlagsFromTypedFlags() {
    var typedFlags = QuirkFlags()
    typedFlags.resetOnOpen = true
    typedFlags.requireStabilization = true
    let quirk = DeviceQuirk(
      id: "test-typed",
      vid: 0x1234, pid: 0x5678,
      flags: typedFlags
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.resetOnOpen, true)
    XCTAssertEqual(resolved.requireStabilization, true)
  }

  func testDeviceQuirkResolvedFlagsFromLegacyOps() {
    let quirk = DeviceQuirk(
      id: "test-legacy",
      vid: 0x1234, pid: 0x5678,
      operations: [
        "supportsGetPartialObject64": true,
        "supportsSendPartialObject": false,
        "preferGetObjectPropList": true,
      ]
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.supportsPartialRead64, true)
    XCTAssertEqual(resolved.supportsPartialWrite, false)
    XCTAssertEqual(resolved.prefersPropListEnumeration, true)
    XCTAssertEqual(resolved.supportsGetObjectPropList, true)
  }

  func testDeviceQuirkResolvedFlagsStabilization() {
    let quirk = DeviceQuirk(
      id: "test-stabilize",
      vid: 0x1234, pid: 0x5678,
      stabilizeMs: 500
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.requireStabilization, true)
  }

  func testDeviceQuirkResolvedFlagsNoStabilization() {
    let quirk = DeviceQuirk(
      id: "test-no-stabilize",
      vid: 0x1234, pid: 0x5678,
      stabilizeMs: 0
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.requireStabilization, false)
  }

  func testDeviceQuirkResolvedFlagsResetOnOpen() {
    let quirk = DeviceQuirk(
      id: "test-reset",
      vid: 0x1234, pid: 0x5678,
      resetOnOpen: true
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.resetOnOpen, true)
  }

  func testDeviceQuirkResolvedFlagsDisableEventPump() {
    let quirk = DeviceQuirk(
      id: "test-no-events",
      vid: 0x1234, pid: 0x5678,
      disableEventPump: true
    )
    let resolved = quirk.resolvedFlags()
    XCTAssertEqual(resolved.disableEventPump, true)
  }

  // MARK: - 10. FallbackSelections Snapshots

  func testFallbackSelectionsDefaults() {
    let fallbacks = FallbackSelections()
    XCTAssertEqual(fallbacks.enumeration, .unknown)
    XCTAssertEqual(fallbacks.read, .unknown)
    XCTAssertEqual(fallbacks.write, .unknown)
  }

  func testFallbackSelectionsEnumerationStrategies() {
    XCTAssertEqual(FallbackSelections.EnumerationStrategy.propList5.rawValue, "propList5")
    XCTAssertEqual(FallbackSelections.EnumerationStrategy.propList3.rawValue, "propList3")
    XCTAssertEqual(
      FallbackSelections.EnumerationStrategy.handlesThenInfo.rawValue, "handlesThenInfo")
    XCTAssertEqual(FallbackSelections.EnumerationStrategy.unknown.rawValue, "unknown")
  }

  func testFallbackSelectionsReadStrategies() {
    XCTAssertEqual(FallbackSelections.ReadStrategy.partial64.rawValue, "partial64")
    XCTAssertEqual(FallbackSelections.ReadStrategy.partial32.rawValue, "partial32")
    XCTAssertEqual(FallbackSelections.ReadStrategy.wholeObject.rawValue, "wholeObject")
    XCTAssertEqual(FallbackSelections.ReadStrategy.unknown.rawValue, "unknown")
  }

  func testFallbackSelectionsWriteStrategies() {
    XCTAssertEqual(FallbackSelections.WriteStrategy.partial.rawValue, "partial")
    XCTAssertEqual(FallbackSelections.WriteStrategy.wholeObject.rawValue, "wholeObject")
    XCTAssertEqual(FallbackSelections.WriteStrategy.unknown.rawValue, "unknown")
  }

  func testFallbackSelectionsEquality() {
    var a = FallbackSelections()
    a.enumeration = .propList5
    a.read = .partial64
    a.write = .partial
    var b = FallbackSelections()
    b.enumeration = .propList5
    b.read = .partial64
    b.write = .partial
    XCTAssertEqual(a, b)
  }

  func testFallbackSelectionsInequality() {
    var a = FallbackSelections()
    a.enumeration = .propList5
    var b = FallbackSelections()
    b.enumeration = .handlesThenInfo
    XCTAssertNotEqual(a, b)
  }

  func testFallbackSelectionsJSONRoundTrip() throws {
    var selections = FallbackSelections()
    selections.enumeration = .propList5
    selections.read = .partial64
    selections.write = .partial
    let data = try JSONEncoder().encode(selections)
    let decoded = try JSONDecoder().decode(FallbackSelections.self, from: data)
    XCTAssertEqual(decoded.enumeration, .propList5)
    XCTAssertEqual(decoded.read, .partial64)
    XCTAssertEqual(decoded.write, .partial)
  }

  // MARK: - 11. Nikon Profile

  func testNikonQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x04B0, pid: 0x0410,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "nikon-dslr-0410")
  }

  // MARK: - 12. OnePlus Profile

  func testOnePlusQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2A70, pid: 0xF003,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "oneplus-3t-f003")
  }

  // MARK: - 13. Xiaomi Profile (Both PIDs)

  func testXiaomiFF10QuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff10")
  }

  func testXiaomiFF40QuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF40,
      bcdDevice: nil, ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff40")
  }

  // MARK: - 14. PolicySources Snapshots

  func testPolicySourcesDefaultValues() {
    let sources = PolicySources()
    XCTAssertEqual(sources.chunkSizeSource, .defaults)
    XCTAssertEqual(sources.ioTimeoutSource, .defaults)
    XCTAssertEqual(sources.flagsSource, .defaults)
    XCTAssertEqual(sources.fallbackSource, .defaults)
  }

  func testPolicySourcesAllRawValues() {
    XCTAssertEqual(PolicySources.Source.defaults.rawValue, "defaults")
    XCTAssertEqual(PolicySources.Source.learned.rawValue, "learned")
    XCTAssertEqual(PolicySources.Source.quirk.rawValue, "quirk")
    XCTAssertEqual(PolicySources.Source.probe.rawValue, "probe")
    XCTAssertEqual(PolicySources.Source.userOverride.rawValue, "userOverride")
  }

  // MARK: - 15. QuirkFlags Equality

  func testQuirkFlagsDefaultEquality() {
    let a = QuirkFlags()
    let b = QuirkFlags()
    XCTAssertEqual(a, b)
  }

  func testQuirkFlagsModifiedInequality() {
    var a = QuirkFlags()
    a.resetOnOpen = true
    let b = QuirkFlags()
    XCTAssertNotEqual(a, b)
  }

  func testQuirkFlagsPTPCameraNotEqualToDefault() {
    let defaults = QuirkFlags()
    let camera = QuirkFlags.ptpCameraDefaults()
    XCTAssertNotEqual(defaults, camera)
  }
}
