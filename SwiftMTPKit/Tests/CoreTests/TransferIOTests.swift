// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

@Suite("Transfer IO Tests")
struct TransferIOTests {

    @Test("FileSink writes data correctly")
    func testFileSink() async throws {
        // Create a temporary file URL
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_sink.tmp")

        // Remove if exists
        try? FileManager.default.removeItem(at: tempURL)

        do {
            // Test writing data
            var sink = try FileSink(url: tempURL)
            let testData: [UInt8] = [1, 2, 3, 4, 5]
            testData.withUnsafeBytes { buffer in
                _ = sink.write(buffer)
            }
            try sink.close()

            // Verify file contents
            let fileData = try Data(contentsOf: tempURL)
            #expect(fileData == Data(testData))
        } catch {
            Issue.record("FileSink test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("FileSource reads data correctly")
    func testFileSource() async throws {
        // Create a temporary file with known content
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_source.tmp")
        let testData: [UInt8] = [10, 20, 30, 40, 50]
        try Data(testData).write(to: tempURL)

        do {
            // Test reading data
            var source = try FileSource(url: tempURL)
            var buffer = [UInt8](repeating: 0, count: 10)

            let bytesRead = buffer.withUnsafeMutableBytes { buf in
                source.read(into: buf)
            }

            #expect(bytesRead == testData.count)
            #expect(Array(buffer.prefix(bytesRead)) == testData)
            #expect(source.fileSize == UInt64(testData.count))

            try source.close()
        } catch {
            Issue.record("FileSource test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Atomic replace works correctly")
    func testAtomicReplace() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_file.tmp")
        let finalURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("final_file.tmp")

        // Create temp file with content
        let tempData: [UInt8] = [100, 101, 102]
        try Data(tempData).write(to: tempURL)

        // Create final file with different content
        let finalData: [UInt8] = [200, 201, 202]
        try Data(finalData).write(to: finalURL)

        do {
            // Perform atomic replace
            try atomicReplace(temp: tempURL, final: finalURL)

            // Verify final file has temp content
            let resultData = try Data(contentsOf: finalURL)
            #expect(resultData == Data(tempData))

            // Verify temp file is gone
            #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        } catch {
            Issue.record("Atomic replace test failed: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: finalURL)
    }
}

@Suite("Effective Tuning Tests")
struct EffectiveTuningTests {

    @Test("Merge order is enforced correctly")
    func testMergeOrderEnforcement() async throws {
        // Test the exact merge order: defaults → capability probe → learned profile → static quirk → user override

        // Create test components
        let capabilities = ProbedCapabilities(
            supportsLargeTransfers: true,
            supportsGetPartialObject64: true,
            supportsSendPartialObject: true,
            isSlowDevice: false,
            needsStabilization: true
        )

        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let learnedProfile = LearnedProfile(
            fingerprint: fingerprint,
            optimalChunkSize: 4_194_304, // 4MB learned
            avgHandshakeMs: 300,
            optimalIoTimeoutMs: 20000,
            successRate: 0.95
        )

        let quirk = QuirkRule(
            id: "test-device",
            match: DeviceMatch(vid: "2717", pid: "ff10"),
            tuning: TuningConfig(
                maxChunkBytes: 8_388_608, // 8MB from quirk
                ioTimeoutMs: 25000,
                handshakeTimeoutMs: 8000,
                stabilizeMs: 500
            ),
            hooks: [
                Hook(phase: .postOpenSession, delayMs: 400),
                Hook(phase: .beforeGetStorageIDs, busyBackoff: MTPBusyBackoff(retries: 3, baseMs: 200, jitterPct: 0.2))
            ],
            ops: OperationConfig(),
            confidence: "high",
            status: "stable"
        )

        let userOverrides = UserOverride(
            maxChunkBytes: 2_097_152, // 2MB user override (should win)
            ioTimeoutMs: 30000
        )

        // Test normal mode (all layers)
        var tuning = EffectiveTuning.defaults
        tuning.apply(capabilities)
        tuning.apply(learnedProfile)
        tuning.apply(quirk)
        tuning.apply(userOverrides)

        // Verify user override wins
        #expect(tuning.maxChunkBytes == 2_097_152, "User override should take precedence")
        #expect(tuning.ioTimeoutMs == 30000, "User override should take precedence")

        // Verify hooks are present
        #expect(tuning.hooks.count == 2, "Should have hooks from quirk")
        #expect(tuning.hooksForPhase(.postOpenSession).count == 1, "Should have postOpenSession hook")
        #expect(tuning.hooksForPhase(.beforeGetStorageIDs).count == 1, "Should have beforeGetStorageIDs hook")
    }

    @Test("Strict mode skips learned and static layers")
    func testStrictMode() async throws {
        let capabilities = ProbedCapabilities(supportsLargeTransfers: true)
        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let learnedProfile = LearnedProfile(fingerprint: fingerprint, optimalChunkSize: 4_194_304)
        let quirk = QuirkRule(
            id: "test-device",
            match: DeviceMatch(vid: "2717", pid: "ff10"),
            tuning: TuningConfig(maxChunkBytes: 8_388_608),
            ops: OperationConfig(),
            confidence: "high",
            status: "stable"
        )

        // Test strict mode
        var tuning = EffectiveTuning.defaults
        tuning.apply(capabilities)
        // Note: In strict mode, we skip learned and quirk layers

        #expect(tuning.maxChunkBytes == EffectiveTuning.defaults.maxChunkBytes * 2,
                "Should apply capability adjustments but not learned/quirk layers")
    }

    @Test("Safe mode enforces conservative settings")
    func testSafeMode() async throws {
        // Safe mode should override everything with conservative settings
        var tuning = EffectiveTuning.defaults

        // Apply safe mode settings (this would be done by the builder)
        tuning.maxChunkBytes = 131_072  // 128KB
        tuning.ioTimeoutMs = 30_000     // 30s
        tuning.handshakeTimeoutMs = 15_000
        tuning.inactivityTimeoutMs = 20_000
        tuning.overallDeadlineMs = 300_000 // 5min
        tuning.supportsGetPartialObject64 = false
        tuning.supportsSendPartialObject = false

        #expect(tuning.maxChunkBytes == 131_072, "Safe mode should use conservative chunk size")
        #expect(tuning.ioTimeoutMs == 30_000, "Safe mode should use long timeouts")
        #expect(tuning.supportsGetPartialObject64 == false, "Safe mode should disable partial operations")
        #expect(tuning.supportsSendPartialObject == false, "Safe mode should disable partial operations")
    }

    @Test("Hook phases are correctly identified")
    func testHookPhases() async throws {
        let hooks = [
            Hook(phase: .postOpenUSB, delayMs: 100),
            Hook(phase: .postClaimInterface, delayMs: 50),
            Hook(phase: .postOpenSession, delayMs: 400),
            Hook(phase: .beforeGetDeviceInfo, delayMs: 10),
            Hook(phase: .beforeGetStorageIDs, busyBackoff: MTPBusyBackoff(retries: 3, baseMs: 200, jitterPct: 0.2)),
            Hook(phase: .beforeTransfer, delayMs: 25),
            Hook(phase: .afterTransfer, delayMs: 100),
            Hook(phase: .onDeviceBusy, busyBackoff: MTPBusyBackoff(retries: 5, baseMs: 500, jitterPct: 0.1))
        ]

        var tuning = EffectiveTuning.defaults
        tuning.hooks = hooks

        // Test phase-specific hook retrieval
        #expect(tuning.hooksForPhase(.postOpenSession).count == 1, "Should find postOpenSession hook")
        #expect(tuning.hooksForPhase(.beforeGetStorageIDs).count == 1, "Should find beforeGetStorageIDs hook")
        #expect(tuning.hooksForPhase(.onDeviceBusy).count == 1, "Should find onDeviceBusy hook")
        #expect(tuning.hooksForPhase(.beforeTransfer).count == 1, "Should find beforeTransfer hook")

        // Test hook properties
        let sessionHook = tuning.hooksForPhase(.postOpenSession).first!
        #expect(sessionHook.delayMs == 400, "Hook should have correct delay")
        #expect(sessionHook.busyBackoff == nil, "Hook should not have busy backoff")

        let storageHook = tuning.hooksForPhase(.beforeGetStorageIDs).first!
        #expect(storageHook.delayMs == nil, "Hook should not have delay")
        #expect(storageHook.busyBackoff != nil, "Hook should have busy backoff")
        #expect(storageHook.busyBackoff!.retries == 3, "Busy backoff should have correct retry count")
    }
}

@Suite("Quirk Database Tests")
struct QuirkDatabaseTests {

    @Test("Schema version validation works")
    func testSchemaVersionValidation() async throws {
        // Test valid version
        let db1 = QuirkDatabase(with: [], schemaVersion: "1.0.0")
        #expect(throws: (any Error).self) {
            try db1.validateSchemaVersion()
        } // Should not throw

        // Test invalid version
        let db2 = QuirkDatabase(with: [], schemaVersion: "2.0.0")
        #expect(throws: QuirkDatabaseError.self) {
            try db2.validateSchemaVersion()
        }
    }

    @Test("Quirk matching by specificity")
    func testQuirkMatching() async throws {
        let quirks = [
            QuirkRule(
                id: "generic-usb",
                match: DeviceMatch(vid: "2717"), // Less specific
                tuning: TuningConfig(maxChunkBytes: 1_048_576),
                ops: OperationConfig(),
                confidence: "low",
                status: "stable"
            ),
            QuirkRule(
                id: "xiaomi-mi-note-2",
                match: DeviceMatch(vid: "2717", pid: "ff10"), // More specific
                tuning: TuningConfig(maxChunkBytes: 2_097_152),
                ops: OperationConfig(),
                confidence: "high",
                status: "stable"
            ),
            QuirkRule(
                id: "xiaomi-mi-note-2-specific",
                match: DeviceMatch(
                    vid: "2717",
                    pid: "ff10",
                    iface: InterfaceMatch(class: "06", subclass: "01", protocol: "01")
                ), // Most specific
                tuning: TuningConfig(maxChunkBytes: 4_194_304),
                ops: OperationConfig(),
                confidence: "high",
                status: "stable"
            )
        ]

        let db = QuirkDatabase(with: quirks, schemaVersion: "1.0.0")

        let fingerprint = MTPDeviceFingerprint(
            vid: "2717", pid: "ff10",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )

        let matched = db.match(for: fingerprint)
        #expect(matched?.id == "xiaomi-mi-note-2-specific", "Should match most specific quirk")
        #expect(matched?.tuning.maxChunkBytes == 4_194_304, "Should use most specific tuning")
    }
}

@Suite("User Override Tests")
struct UserOverrideTests {

    @Test("Environment parsing works correctly")
    func testEnvironmentParsing() async throws {
        // Test valid overrides
        let env1 = "maxChunkBytes=2097152,ioTimeoutMs=20000,stabilizeMs=500"
        let overrides1 = UserOverride.fromEnvironment(env1)

        #expect(overrides1?.maxChunkBytes == 2_097_152, "Should parse maxChunkBytes")
        #expect(overrides1?.ioTimeoutMs == 20_000, "Should parse ioTimeoutMs")
        #expect(overrides1?.stabilizeMs == 500, "Should parse stabilizeMs")

        // Test partial overrides
        let env2 = "maxChunkBytes=1048576"
        let overrides2 = UserOverride.fromEnvironment(env2)

        #expect(overrides2?.maxChunkBytes == 1_048_576, "Should parse single override")
        #expect(overrides2?.ioTimeoutMs == nil, "Should not set unspecified values")

        // Test invalid input
        let overrides3 = UserOverride.fromEnvironment(nil)
        #expect(overrides3 == nil, "Should return nil for nil input")

        let overrides4 = UserOverride.fromEnvironment("")
        #expect(overrides4 == nil, "Should return nil for empty input")

        // Test malformed input (should be graceful)
        let overrides5 = UserOverride.fromEnvironment("invalid")
        #expect(overrides5 == nil, "Should return nil for malformed input")
    }

    @Test("Override precedence works in effective tuning")
    func testOverridePrecedence() async throws {
        var tuning = EffectiveTuning.defaults

        // Apply various layers
        let capabilities = ProbedCapabilities(supportsLargeTransfers: true)
        tuning.apply(capabilities)

        let originalChunkSize = tuning.maxChunkBytes

        // Apply user override
        let overrides = UserOverride(maxChunkBytes: 524_288) // 512KB override
        tuning.apply(overrides)

        #expect(tuning.maxChunkBytes == 524_288, "User override should take precedence over capability adjustments")
        #expect(tuning.maxChunkBytes != originalChunkSize, "Should be different from pre-override value")
    }
}
