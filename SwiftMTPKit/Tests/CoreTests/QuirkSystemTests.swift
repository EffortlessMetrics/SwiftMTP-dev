// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SwiftMTPCore

final class QuirkSystemTests: XCTestCase {

    func testMergeOrder() throws {
        // Test that layers are applied in the correct order:
        // defaults → capabilityProbe → learnedProfile → staticQuirk → userOverride

        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let capabilities = ProbedCapabilities(
            supportsLargeTransfers: true,
            supportsGetPartialObject64: true,
            supportsSendPartialObject: true,
            isSlowDevice: false,
            needsStabilization: false
        )

        // Create mock learned profile
        let learnedProfile = LearnedProfile(
            fingerprint: fingerprint,
            optimalChunkSize: 4_194_304, // 4MB
            successRate: 0.95
        )

        // Create mock quirk
        let quirk = QuirkRule(
            id: "test-device",
            match: DeviceMatch(vid: "2717", pid: "ff10"),
            tuning: TuningConfig(maxChunkBytes: 8_388_608), // 8MB
            ops: OperationConfig(),
            confidence: "high",
            status: "stable"
        )

        // Create user override
        let userOverride = UserOverride(maxChunkBytes: 2_097_152) // 2MB

        // Build effective tuning
        let builder = EffectiveTuningBuilder()
        var tuning = EffectiveTuning.defaults

        // Apply layers in order
        tuning.apply(capabilities)         // Layer 1: capabilities
        tuning.apply(learnedProfile)       // Layer 2: learned profile
        tuning.apply(quirk)               // Layer 3: static quirk
        tuning.apply(userOverride)        // Layer 4: user override

        // User override should win (2MB)
        XCTAssertEqual(tuning.maxChunkBytes, 2_097_152, "User override should take precedence")
    }

    func testStrictMode() throws {
        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let capabilities = ProbedCapabilities(supportsLargeTransfers: true)
        let learnedProfile = LearnedProfile(fingerprint: fingerprint, optimalChunkSize: 8_388_608)

        let builder = EffectiveTuningBuilder()

        // Strict mode should skip learned profile
        let strictTuning = builder.buildEffectiveTuning(
            fingerprint: fingerprint,
            capabilities: capabilities,
            strict: true,
            safe: false
        )

        // Non-strict mode should include learned profile
        let normalTuning = builder.buildEffectiveTuning(
            fingerprint: fingerprint,
            capabilities: capabilities,
            strict: false,
            safe: false
        )

        // In strict mode, learned profile should not affect chunk size
        XCTAssertNotEqual(strictTuning.maxChunkBytes, 8_388_608, "Strict mode should not apply learned profile")
        XCTAssertGreaterThan(normalTuning.maxChunkBytes, strictTuning.maxChunkBytes, "Normal mode should apply learned profile")
    }

    func testSafeMode() throws {
        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let capabilities = ProbedCapabilities(supportsLargeTransfers: true)

        let builder = EffectiveTuningBuilder()

        let safeTuning = builder.buildEffectiveTuning(
            fingerprint: fingerprint,
            capabilities: capabilities,
            strict: false,
            safe: true
        )

        // Safe mode should use very conservative settings
        XCTAssertEqual(safeTuning.maxChunkBytes, 131_072, "Safe mode should use 128KB chunks")
        XCTAssertEqual(safeTuning.ioTimeoutMs, 30_000, "Safe mode should use 30s I/O timeout")
        XCTAssertEqual(safeTuning.handshakeTimeoutMs, 15_000, "Safe mode should use 15s handshake timeout")
        XCTAssertEqual(safeTuning.overallDeadlineMs, 300_000, "Safe mode should use 5min deadline")
        XCTAssertFalse(safeTuning.supportsGetPartialObject64, "Safe mode should disable partial read")
        XCTAssertFalse(safeTuning.supportsSendPartialObject, "Safe mode should disable partial write")
    }

    func testMatchingPrecedence() throws {
        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        // Create quirks with different specificity levels
        let broadMatch = QuirkRule(
            id: "broad-vid-only",
            match: DeviceMatch(vid: "2717"),
            tuning: TuningConfig(maxChunkBytes: 1_048_576),
            ops: OperationConfig(),
            confidence: "medium",
            status: "stable"
        )

        let specificMatch = QuirkRule(
            id: "specific-vid-pid",
            match: DeviceMatch(vid: "2717", pid: "ff10"),
            tuning: TuningConfig(maxChunkBytes: 2_097_152),
            ops: OperationConfig(),
            confidence: "high",
            status: "stable"
        )

        let mostSpecificMatch = QuirkRule(
            id: "most-specific-vid-pid-iface",
            match: DeviceMatch(
                vid: "2717",
                pid: "ff10",
                iface: InterfaceMatch(class: "06", subclass: "01", protocol: "01")
            ),
            tuning: TuningConfig(maxChunkBytes: 4_194_304),
            ops: OperationConfig(),
            confidence: "high",
            status: "stable"
        )

        let quirkDB = QuirkDatabase(with: [broadMatch, specificMatch, mostSpecificMatch])

        // Most specific match should win
        let matchedQuirk = quirkDB.match(for: fingerprint)
        XCTAssertEqual(matchedQuirk?.id, "most-specific-vid-pid-iface", "Most specific match should win")
        XCTAssertEqual(matchedQuirk?.tuning.maxChunkBytes, 4_194_304, "Should use most specific quirk's chunk size")
    }

    func testUserOverrideParsing() throws {
        let override = UserOverride.fromEnvironment("maxChunkBytes=2097152,ioTimeoutMs=15000")
        XCTAssertNotNil(override)
        XCTAssertEqual(override?.maxChunkBytes, 2_097_152)
        XCTAssertEqual(override?.ioTimeoutMs, 15_000)
        XCTAssertNil(override?.handshakeTimeoutMs)
    }

    func testQuirkDenylist() throws {
        let deniedQuirks = EffectiveTuningBuilder.deniedQuirksFromEnvironment("xiaomi-mi-note-2,test-device")
        XCTAssertNotNil(deniedQuirks)
        XCTAssertTrue(deniedQuirks?.contains("xiaomi-mi-note-2") ?? false)
        XCTAssertTrue(deniedQuirks?.contains("test-device") ?? false)
        XCTAssertEqual(deniedQuirks?.count, 2)
    }

    func testSchemaBoundsClamping() throws {
        var tuning = EffectiveTuning.defaults

        // Test chunk size clamping
        tuning.maxChunkBytes = 100_000 // Too small
        XCTAssertGreaterThanOrEqual(tuning.maxChunkBytes, 131_072, "Chunk size should be clamped to minimum")

        tuning.maxChunkBytes = 100_000_000 // Too large
        XCTAssertLessThanOrEqual(tuning.maxChunkBytes, 16_777_216, "Chunk size should be clamped to maximum")

        // Test timeout clamping
        tuning.ioTimeoutMs = 500 // Too small
        XCTAssertGreaterThanOrEqual(tuning.ioTimeoutMs, 1_000, "I/O timeout should be clamped to minimum")

        tuning.ioTimeoutMs = 100_000 // Too large
        XCTAssertLessThanOrEqual(tuning.ioTimeoutMs, 60_000, "I/O timeout should be clamped to maximum")
    }

    func testLearnedProfileFingerprintEvolution() throws {
        let fingerprint1 = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10", bcdDevice: "0318",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let fingerprint2 = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10", bcdDevice: "0319", // Different bcdDevice
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let profile = LearnedProfile(fingerprint: fingerprint1, successRate: 0.95)

        let manager = LearnedProfileManager(storageURL: URL(fileURLWithPath: "/tmp/test-profiles.json"))

        // Profile should expire when bcdDevice changes
        XCTAssertTrue(manager.shouldExpireProfile(profile, newFingerprint: fingerprint2),
                     "Profile should expire when bcdDevice changes")
    }

    func testHookPhaseOrdering() throws {
        var tuning = EffectiveTuning.defaults

        // Add hooks in different phases
        tuning.hooks.append(Hook(phase: .postOpenSession, delayMs: 400))
        tuning.hooks.append(Hook(phase: .beforeGetStorageIDs, delayMs: 200))

        let postOpenHooks = tuning.hooksForPhase(.postOpenSession)
        let beforeStorageHooks = tuning.hooksForPhase(.beforeGetStorageIDs)

        XCTAssertEqual(postOpenHooks.count, 1)
        XCTAssertEqual(beforeStorageHooks.count, 1)
        XCTAssertEqual(postOpenHooks[0].delayMs, 400)
        XCTAssertEqual(beforeStorageHooks[0].delayMs, 200)
    }
}
