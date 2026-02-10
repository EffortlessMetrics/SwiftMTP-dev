// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPQuirks
@testable import SwiftMTPStore

final class QuirksCoverageBoostTests: XCTestCase {

    private func makeTuning(
        maxChunkBytes: Int = 1_048_576,
        ioTimeoutMs: Int = 8_000,
        handshakeTimeoutMs: Int = 6_000,
        inactivityTimeoutMs: Int = 8_000,
        overallDeadlineMs: Int = 60_000,
        stabilizeMs: Int = 0,
        resetOnOpen: Bool = false,
        disableEventPump: Bool = false,
        operations: [String: Bool] = [:],
        hooks: [QuirkHook] = []
    ) -> EffectiveTuning {
        EffectiveTuning(
            maxChunkBytes: maxChunkBytes,
            ioTimeoutMs: ioTimeoutMs,
            handshakeTimeoutMs: handshakeTimeoutMs,
            inactivityTimeoutMs: inactivityTimeoutMs,
            overallDeadlineMs: overallDeadlineMs,
            stabilizeMs: stabilizeMs,
            postClaimStabilizeMs: 250,
            resetOnOpen: resetOnOpen,
            disableEventPump: disableEventPump,
            operations: operations,
            hooks: hooks
        )
    }

    func testEffectiveTuningDefaults() {
        let defaults = EffectiveTuning.defaults()
        XCTAssertEqual(defaults.maxChunkBytes, 1_048_576)
        XCTAssertEqual(defaults.ioTimeoutMs, 8_000)
        XCTAssertEqual(defaults.handshakeTimeoutMs, 6_000)
        XCTAssertEqual(defaults.inactivityTimeoutMs, 8_000)
        XCTAssertEqual(defaults.overallDeadlineMs, 60_000)
        XCTAssertEqual(defaults.stabilizeMs, 0)
        XCTAssertEqual(defaults.postClaimStabilizeMs, 250)
        XCTAssertFalse(defaults.resetOnOpen)
        XCTAssertFalse(defaults.disableEventPump)
        XCTAssertTrue(defaults.operations.isEmpty)
        XCTAssertTrue(defaults.hooks.isEmpty)
    }

    func testEffectiveTuningBuilderAppliesLayersAndClamps() {
        let learnedHook = QuirkHook(phase: .postOpenSession, delayMs: 120)
        var learned = makeTuning(
            maxChunkBytes: 64_000,
            ioTimeoutMs: 120_000,
            handshakeTimeoutMs: 500,
            inactivityTimeoutMs: 90_000,
            overallDeadlineMs: 900_000,
            stabilizeMs: -10,
            resetOnOpen: true,
            operations: ["learned-op": true],
            hooks: [learnedHook]
        )
        learned.operations["learned-only"] = true

        let quirkHook = QuirkHook(phase: .beforeTransfer, delayMs: 50)
        let quirk = DeviceQuirk(
            id: "merge-test",
            vid: 0x18d1,
            pid: 0x4ee1,
            maxChunkBytes: 4_194_304,
            ioTimeoutMs: 4_000,
            handshakeTimeoutMs: 4_000,
            inactivityTimeoutMs: 4_000,
            overallDeadlineMs: 40_000,
            stabilizeMs: 100,
            resetOnOpen: false,
            disableEventPump: true,
            operations: ["quirk-only": true],
            hooks: [quirkHook]
        )

        let tuning = EffectiveTuningBuilder.build(
            capabilities: ["capability-op": true],
            learned: learned,
            quirk: quirk,
            overrides: [
                "maxChunkBytes": "999999999",
                "ioTimeoutMs": "1",
                "handshakeTimeoutMs": "70000",
                "inactivityTimeoutMs": "0",
                "overallDeadlineMs": "999999",
                "stabilizeMs": "9000",
            ]
        )

        XCTAssertEqual(tuning.maxChunkBytes, 16 * 1024 * 1024)
        XCTAssertEqual(tuning.ioTimeoutMs, 1_000)
        XCTAssertEqual(tuning.handshakeTimeoutMs, 60_000)
        XCTAssertEqual(tuning.inactivityTimeoutMs, 1_000)
        XCTAssertEqual(tuning.overallDeadlineMs, 300_000)
        XCTAssertEqual(tuning.stabilizeMs, 5_000)
        XCTAssertFalse(tuning.resetOnOpen)
        XCTAssertTrue(tuning.disableEventPump)
        XCTAssertEqual(tuning.operations["capability-op"], true)
        XCTAssertEqual(tuning.operations["learned-op"], true)
        XCTAssertEqual(tuning.operations["learned-only"], true)
        XCTAssertEqual(tuning.operations["quirk-only"], true)
        XCTAssertEqual(tuning.hooks.count, 2)
        XCTAssertEqual(tuning.hooks[0].phase, .postOpenSession)
        XCTAssertEqual(tuning.hooks[1].phase, .beforeTransfer)
    }

    func testBuildPolicyTracksProvenance() {
        let learnedPolicy = EffectiveTuningBuilder.buildPolicy(
            capabilities: [:],
            learned: makeTuning(maxChunkBytes: 2_000_000, ioTimeoutMs: 9_000),
            quirk: nil,
            overrides: nil
        )
        XCTAssertEqual(learnedPolicy.sources.chunkSizeSource, .learned)
        XCTAssertEqual(learnedPolicy.sources.ioTimeoutSource, .learned)

        var flags = QuirkFlags()
        flags.supportsPartialWrite = false
        let quirk = DeviceQuirk(
            id: "quirk-policy",
            vid: 1,
            pid: 2,
            maxChunkBytes: 3_000_000,
            ioTimeoutMs: 7_000,
            flags: flags
        )
        let quirkPolicy = EffectiveTuningBuilder.buildPolicy(
            capabilities: [:],
            learned: nil,
            quirk: quirk,
            overrides: nil
        )
        XCTAssertEqual(quirkPolicy.sources.chunkSizeSource, .quirk)
        XCTAssertEqual(quirkPolicy.sources.ioTimeoutSource, .quirk)
        XCTAssertEqual(quirkPolicy.sources.flagsSource, .quirk)
        XCTAssertFalse(quirkPolicy.flags.supportsPartialWrite)

        let overridePolicy = EffectiveTuningBuilder.buildPolicy(
            capabilities: [:],
            learned: nil,
            quirk: quirk,
            overrides: ["ioTimeoutMs": "12000"]
        )
        XCTAssertEqual(overridePolicy.sources.chunkSizeSource, .userOverride)
        XCTAssertEqual(overridePolicy.sources.ioTimeoutSource, .userOverride)
    }

    func testDevicePolicyStoresFallbacksAndSources() {
        var fallbacks = FallbackSelections()
        fallbacks.enumeration = .propList3
        fallbacks.read = .partial64
        fallbacks.write = .partial

        var sources = PolicySources()
        sources.fallbackSource = .probe

        let policy = DevicePolicy(
            tuning: EffectiveTuning.defaults(),
            flags: QuirkFlags(),
            fallbacks: fallbacks,
            sources: sources
        )

        XCTAssertEqual(policy.fallbacks, fallbacks)
        XCTAssertEqual(policy.sources.fallbackSource, .probe)
    }

    func testDeviceQuirkResolvedFlagsSynthesizesFromLegacyFields() {
        let quirk = DeviceQuirk(
            id: "legacy",
            vid: 0x2717,
            pid: 0xff10,
            stabilizeMs: 1,
            resetOnOpen: true,
            disableEventPump: true,
            operations: [
                "supportsGetPartialObject64": false,
                "supportsSendPartialObject": false,
                "preferGetObjectPropList": false,
            ]
        )

        let resolved = quirk.resolvedFlags()
        XCTAssertFalse(resolved.supportsPartialRead64)
        XCTAssertFalse(resolved.supportsPartialWrite)
        XCTAssertFalse(resolved.prefersPropListEnumeration)
        XCTAssertTrue(resolved.resetOnOpen)
        XCTAssertTrue(resolved.disableEventPump)
        XCTAssertTrue(resolved.requireStabilization)
    }

    func testDeviceQuirkResolvedFlagsPrefersTypedFlags() {
        var typed = QuirkFlags()
        typed.supportsPartialRead64 = false
        typed.supportsPartialWrite = false
        typed.prefersPropListEnumeration = false

        let quirk = DeviceQuirk(
            id: "typed",
            vid: 0x18d1,
            pid: 0x4ee1,
            resetOnOpen: true,
            operations: [
                "supportsGetPartialObject64": true,
                "supportsSendPartialObject": true,
            ],
            flags: typed
        )

        let resolved = quirk.resolvedFlags()
        XCTAssertEqual(resolved, typed)
    }

    func testFallbackSelectionsCodableRoundTrip() throws {
        var selections = FallbackSelections()
        selections.enumeration = .handlesThenInfo
        selections.read = .wholeObject
        selections.write = .wholeObject

        let data = try JSONEncoder().encode(selections)
        let decoded = try JSONDecoder().decode(FallbackSelections.self, from: data)
        XCTAssertEqual(decoded, selections)
    }

    func testQuirkFlagsCodableRoundTrip() throws {
        var flags = QuirkFlags()
        flags.resetOnOpen = true
        flags.needsLongerOpenTimeout = true
        flags.requiresSessionBeforeDeviceInfo = true
        flags.needsShortReads = true
        flags.disableEventPump = true
        flags.skipPTPReset = true

        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
        XCTAssertEqual(decoded, flags)
    }

    func testUserOverrideInitializerStoresAllFields() {
        let override = UserOverride(
            maxChunkBytes: 2_097_152,
            ioTimeoutMs: 15_000,
            handshakeTimeoutMs: 20_000,
            inactivityTimeoutMs: 12_000,
            overallDeadlineMs: 100_000,
            stabilizeMs: 300,
            disablePartialRead: true,
            disablePartialWrite: false
        )

        XCTAssertEqual(override.maxChunkBytes, 2_097_152)
        XCTAssertEqual(override.ioTimeoutMs, 15_000)
        XCTAssertEqual(override.handshakeTimeoutMs, 20_000)
        XCTAssertEqual(override.inactivityTimeoutMs, 12_000)
        XCTAssertEqual(override.overallDeadlineMs, 100_000)
        XCTAssertEqual(override.stabilizeMs, 300)
        XCTAssertEqual(override.disablePartialRead, true)
        XCTAssertEqual(override.disablePartialWrite, false)
    }

    func testUserOverrideFromEnvironmentParsesKnownValues() {
        let (override, source) = UserOverride.fromEnvironment([
            "SWIFTMTP_OVERRIDES": "maxChunkBytes=2097152,ioTimeoutMs=15000,handshakeTimeoutMs=12000,inactivityTimeoutMs=7000,overallDeadlineMs=90000,stabilizeMs=400,disablePartialRead=true,disablePartialWrite=1,ignored=value,malformed"
        ])

        switch source {
        case .environment:
            break
        case .none:
            XCTFail("Expected environment source when SWIFTMTP_OVERRIDES is set")
        }

        XCTAssertEqual(override.maxChunkBytes, 2_097_152)
        XCTAssertEqual(override.ioTimeoutMs, 15_000)
        XCTAssertEqual(override.handshakeTimeoutMs, 12_000)
        XCTAssertEqual(override.inactivityTimeoutMs, 7_000)
        XCTAssertEqual(override.overallDeadlineMs, 90_000)
        XCTAssertEqual(override.stabilizeMs, 400)
        XCTAssertEqual(override.disablePartialRead, true)
        XCTAssertEqual(override.disablePartialWrite, true)
    }

    func testUserOverrideFromEnvironmentMissingValueReturnsNone() {
        let (override, source) = UserOverride.fromEnvironment([:])

        switch source {
        case .none:
            break
        case .environment:
            XCTFail("Expected .none when SWIFTMTP_OVERRIDES is missing")
        }

        XCTAssertNil(override.maxChunkBytes)
        XCTAssertNil(override.ioTimeoutMs)
        XCTAssertNil(override.handshakeTimeoutMs)
        XCTAssertNil(override.inactivityTimeoutMs)
        XCTAssertNil(override.overallDeadlineMs)
        XCTAssertNil(override.stabilizeMs)
        XCTAssertNil(override.disablePartialRead)
        XCTAssertNil(override.disablePartialWrite)
    }

    func testUserOverrideFromEnvironmentParsesDisablePartialWriteTrueLiteral() {
        let (override, source) = UserOverride.fromEnvironment([
            "SWIFTMTP_OVERRIDES": "disablePartialWrite=true"
        ])

        switch source {
        case .environment:
            break
        case .none:
            XCTFail("Expected .environment when SWIFTMTP_OVERRIDES is provided")
        }

        XCTAssertEqual(override.disablePartialWrite, true)
    }

    func testProbedCapabilitiesInitializerStoresValues() {
        let capabilities = ProbedCapabilities(
            partialRead: true,
            partialWrite: false,
            supportsEvents: true
        )

        XCTAssertEqual(
            capabilities,
            ProbedCapabilities(partialRead: true, partialWrite: false, supportsEvents: true)
        )
    }

    func testDeviceQuirkDecodingParsesHexAndTuning() throws {
        let json = """
        {
          "id": "decode-test",
          "status": "stable",
          "confidence": "high",
          "match": {
            "vid": "0x18d1",
            "pid": "4ee1",
            "bcdDevice": "0x0318",
            "iface": {
              "class": "06",
              "subclass": "01",
              "protocol": "01"
            }
          },
          "tuning": {
            "maxChunkBytes": 2097152,
            "ioTimeoutMs": 9000,
            "handshakeTimeoutMs": 7000,
            "inactivityTimeoutMs": 6000,
            "overallDeadlineMs": 120000,
            "stabilizeMs": 250,
            "resetOnOpen": false,
            "disableEventPump": true
          },
          "ops": {
            "supportsGetPartialObject64": true
          }
        }
        """

        let decoded = try JSONDecoder().decode(DeviceQuirk.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, "decode-test")
        XCTAssertEqual(decoded.vid, 0x18d1)
        XCTAssertEqual(decoded.pid, 0x4ee1)
        XCTAssertEqual(decoded.bcdDevice, 0x0318)
        XCTAssertEqual(decoded.ifaceClass, 0x06)
        XCTAssertEqual(decoded.ifaceSubclass, 0x01)
        XCTAssertEqual(decoded.ifaceProtocol, 0x01)
        XCTAssertEqual(decoded.maxChunkBytes, 2_097_152)
        XCTAssertEqual(decoded.ioTimeoutMs, 9_000)
        XCTAssertEqual(decoded.handshakeTimeoutMs, 7_000)
        XCTAssertEqual(decoded.inactivityTimeoutMs, 6_000)
        XCTAssertEqual(decoded.overallDeadlineMs, 120_000)
        XCTAssertEqual(decoded.stabilizeMs, 250)
        XCTAssertEqual(decoded.disableEventPump, true)
        XCTAssertEqual(decoded.operations?["supportsGetPartialObject64"], true)
    }
}

final class StoreModelCoverageBoostTests: XCTestCase {

    func testDeviceAndLearnedProfileInitializers() {
        let seenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let device = DeviceEntity(
            id: "device-1",
            vendorId: 0x18d1,
            productId: 0x4ee1,
            manufacturer: "Google",
            model: "Pixel",
            serialNumber: "ABC123",
            lastSeenAt: seenAt
        )

        XCTAssertEqual(device.id, "device-1")
        XCTAssertEqual(device.vendorId, 0x18d1)
        XCTAssertEqual(device.productId, 0x4ee1)
        XCTAssertEqual(device.manufacturer, "Google")
        XCTAssertEqual(device.model, "Pixel")
        XCTAssertEqual(device.serialNumber, "ABC123")
        XCTAssertEqual(device.lastSeenAt, seenAt)
        XCTAssertTrue(device.profiles.isEmpty)
        XCTAssertTrue(device.profilingRuns.isEmpty)
        XCTAssertTrue(device.snapshots.isEmpty)

        let created = Date(timeIntervalSince1970: 1_700_000_100)
        let updated = Date(timeIntervalSince1970: 1_700_000_200)
        let profile = LearnedProfileEntity(
            fingerprintHash: "fp-hash",
            created: created,
            lastUpdated: updated,
            sampleCount: 3,
            optimalChunkSize: 1_048_576,
            avgHandshakeMs: 950,
            optimalIoTimeoutMs: 7_500,
            optimalInactivityTimeoutMs: 8_500,
            p95ReadThroughputMBps: 42.5,
            p95WriteThroughputMBps: 21.0,
            successRate: 0.97,
            hostEnvironment: "unit-test"
        )

        XCTAssertEqual(profile.fingerprintHash, "fp-hash")
        XCTAssertEqual(profile.created, created)
        XCTAssertEqual(profile.lastUpdated, updated)
        XCTAssertEqual(profile.sampleCount, 3)
        XCTAssertEqual(profile.optimalChunkSize, 1_048_576)
        XCTAssertEqual(profile.avgHandshakeMs, 950)
        XCTAssertEqual(profile.optimalIoTimeoutMs, 7_500)
        XCTAssertEqual(profile.optimalInactivityTimeoutMs, 8_500)
        XCTAssertEqual(profile.p95ReadThroughputMBps, 42.5)
        XCTAssertEqual(profile.p95WriteThroughputMBps, 21.0)
        XCTAssertEqual(profile.successRate, 0.97)
        XCTAssertEqual(profile.hostEnvironment, "unit-test")
    }

    func testStorageAndObjectInitializers() {
        let indexedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let storage = MTPStorageEntity(
            deviceId: "device-1",
            storageId: 65_536,
            storageDescription: "Internal storage",
            capacityBytes: 128_000_000_000,
            freeBytes: 64_000_000_000,
            isReadOnly: false,
            lastIndexedAt: indexedAt
        )

        XCTAssertEqual(storage.compoundId, "device-1:65536")
        XCTAssertEqual(storage.deviceId, "device-1")
        XCTAssertEqual(storage.storageId, 65_536)
        XCTAssertEqual(storage.storageDescription, "Internal storage")
        XCTAssertEqual(storage.capacityBytes, 128_000_000_000)
        XCTAssertEqual(storage.freeBytes, 64_000_000_000)
        XCTAssertFalse(storage.isReadOnly)
        XCTAssertEqual(storage.lastIndexedAt, indexedAt)
        XCTAssertTrue(storage.objects.isEmpty)

        let modifiedAt = Date(timeIntervalSince1970: 1_700_001_111)
        let object = MTPObjectEntity(
            deviceId: "device-1",
            storageId: 65_536,
            handle: 42,
            parentHandle: 7,
            name: "photo.jpg",
            pathKey: "00010000/DCIM/photo.jpg",
            sizeBytes: 9_001,
            modifiedAt: modifiedAt,
            formatCode: 0x3801,
            generation: 12,
            tombstone: 1
        )

        XCTAssertEqual(object.compoundId, "device-1:65536:42")
        XCTAssertEqual(object.deviceId, "device-1")
        XCTAssertEqual(object.storageId, 65_536)
        XCTAssertEqual(object.handle, 42)
        XCTAssertEqual(object.parentHandle, 7)
        XCTAssertEqual(object.name, "photo.jpg")
        XCTAssertEqual(object.pathKey, "00010000/DCIM/photo.jpg")
        XCTAssertEqual(object.sizeBytes, 9_001)
        XCTAssertEqual(object.modifiedAt, modifiedAt)
        XCTAssertEqual(object.formatCode, 0x3801)
        XCTAssertEqual(object.generation, 12)
        XCTAssertEqual(object.tombstone, 1)
    }

    func testTransferAndSubmissionInitializers() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_002_000)
        let transfer = TransferEntity(
            id: "tx-1",
            deviceId: "device-1",
            kind: "read",
            handle: 99,
            parentHandle: 10,
            name: "archive.zip",
            totalBytes: 1_024_000,
            committedBytes: 512_000,
            supportsPartial: true,
            localTempURL: "/tmp/archive.zip.part",
            finalURL: "/tmp/archive.zip",
            state: "paused",
            updatedAt: updatedAt
        )

        XCTAssertEqual(transfer.id, "tx-1")
        XCTAssertEqual(transfer.deviceId, "device-1")
        XCTAssertEqual(transfer.kind, "read")
        XCTAssertEqual(transfer.handle, 99)
        XCTAssertEqual(transfer.parentHandle, 10)
        XCTAssertEqual(transfer.name, "archive.zip")
        XCTAssertEqual(transfer.totalBytes, 1_024_000)
        XCTAssertEqual(transfer.committedBytes, 512_000)
        XCTAssertTrue(transfer.supportsPartial)
        XCTAssertEqual(transfer.localTempURL, "/tmp/archive.zip.part")
        XCTAssertEqual(transfer.finalURL, "/tmp/archive.zip")
        XCTAssertEqual(transfer.state, "paused")
        XCTAssertEqual(transfer.updatedAt, updatedAt)
        XCTAssertNil(transfer.lastError)
        XCTAssertNil(transfer.etagSize)
        XCTAssertNil(transfer.etagMtime)

        let createdAt = Date(timeIntervalSince1970: 1_700_002_500)
        let submission = SubmissionEntity(
            id: "submission-1",
            deviceId: "device-1",
            createdAt: createdAt,
            path: "/tmp/submission.json",
            status: "done"
        )

        XCTAssertEqual(submission.id, "submission-1")
        XCTAssertEqual(submission.deviceId, "device-1")
        XCTAssertEqual(submission.createdAt, createdAt)
        XCTAssertEqual(submission.path, "/tmp/submission.json")
        XCTAssertEqual(submission.status, "done")
    }

    func testSnapshotAndProfilingInitializers() {
        let runDate = Date(timeIntervalSince1970: 1_700_003_000)
        let run = ProfilingRunEntity(timestamp: runDate, appVersion: "2.1.0")
        XCTAssertEqual(run.timestamp, runDate)
        XCTAssertEqual(run.appVersion, "2.1.0")
        XCTAssertTrue(run.metrics.isEmpty)

        let metric = ProfilingMetricEntity(
            operation: "GetObject",
            count: 11,
            minMs: 1.2,
            maxMs: 8.8,
            avgMs: 3.5,
            p95Ms: 7.4,
            throughputMBps: 22.0
        )

        XCTAssertEqual(metric.operation, "GetObject")
        XCTAssertEqual(metric.count, 11)
        XCTAssertEqual(metric.minMs, 1.2)
        XCTAssertEqual(metric.maxMs, 8.8)
        XCTAssertEqual(metric.avgMs, 3.5)
        XCTAssertEqual(metric.p95Ms, 7.4)
        XCTAssertEqual(metric.throughputMBps, 22.0)

        let createdAt = Date(timeIntervalSince1970: 1_700_003_333)
        let snapshot = SnapshotEntity(
            generation: 7,
            createdAt: createdAt,
            artifactPath: "/tmp/snapshot.json",
            artifactHash: "abc123"
        )

        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertEqual(snapshot.createdAt, createdAt)
        XCTAssertEqual(snapshot.artifactPath, "/tmp/snapshot.json")
        XCTAssertEqual(snapshot.artifactHash, "abc123")
    }
}
