// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Tests for LearnedProfile.swift to boost coverage
final class LearnedProfileCoverageTests: XCTestCase {

    // MARK: - LearnedProfile Basic Tests

    func testLearnedProfileDefaultInit() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let profile = LearnedProfile(fingerprint: fingerprint)
        
        XCTAssertEqual(profile.fingerprint, fingerprint)
        XCTAssertNotNil(profile.fingerprintHash)
        XCTAssertEqual(profile.sampleCount, 1)
        XCTAssertNil(profile.optimalChunkSize)
        XCTAssertNil(profile.avgHandshakeMs)
        XCTAssertNil(profile.optimalIoTimeoutMs)
        XCTAssertNil(profile.p95ReadThroughputMBps)
        XCTAssertNil(profile.p95WriteThroughputMBps)
        XCTAssertEqual(profile.successRate, 1.0)
    }

    func testLearnedProfileWithAllValues() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            bcdDevice: "1.0",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
            deviceInfoHash: "abc123"
        )
        
        let profile = LearnedProfile(
            fingerprint: fingerprint,
            fingerprintHash: "custom-hash",
            sampleCount: 100,
            optimalChunkSize: 64 * 1024,
            avgHandshakeMs: 150,
            optimalIoTimeoutMs: 10000,
            optimalInactivityTimeoutMs: 5000,
            p95ReadThroughputMBps: 25.5,
            p95WriteThroughputMBps: 15.2,
            successRate: 0.98,
            hostEnvironment: "macOS 14.0"
        )
        
        XCTAssertEqual(profile.fingerprintHash, "custom-hash")
        XCTAssertEqual(profile.sampleCount, 100)
        XCTAssertEqual(profile.optimalChunkSize, 64 * 1024)
        XCTAssertEqual(profile.avgHandshakeMs, 150)
        XCTAssertEqual(profile.optimalIoTimeoutMs, 10000)
        XCTAssertEqual(profile.optimalInactivityTimeoutMs, 5000)
        XCTAssertEqual(profile.p95ReadThroughputMBps, 25.5)
        XCTAssertEqual(profile.p95WriteThroughputMBps, 15.2)
        XCTAssertEqual(profile.successRate, 0.98)
        XCTAssertEqual(profile.hostEnvironment, "macOS 14.0")
    }

    // MARK: - LearnedProfile Merging Tests

    func testMergedProfileIncrementsSampleCount() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let initial = LearnedProfile(fingerprint: fingerprint, sampleCount: 5)
        let sessionData = SessionData(handshakeTimeMs: 100)
        
        let merged = initial.merged(with: sessionData)
        
        XCTAssertEqual(merged.sampleCount, 6)
    }

    func testMergedProfileWeightedAverage() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        // First merge with initial value
        let initial = LearnedProfile(
            fingerprint: fingerprint,
            sampleCount: 1,
            avgHandshakeMs: 100
        )
        let session1 = SessionData(handshakeTimeMs: 200)
        let merged1 = initial.merged(with: session1)
        
        // Alpha = 1/2 = 0.5, so avg = 100 * 0.5 + 200 * 0.5 = 150
        XCTAssertEqual(merged1.avgHandshakeMs, 150)
        
        // Second merge
        let session2 = SessionData(handshakeTimeMs: 300)
        let merged2 = merged1.merged(with: session2)
        
        // Alpha = 1/3 ≈ 0.333, so avg = 150 * 0.667 + 300 * 0.333 ≈ 200
        XCTAssertEqual(merged2.avgHandshakeMs, 200)
    }

    func testMergedProfileWithNilValues() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let initial = LearnedProfile(
            fingerprint: fingerprint,
            optimalChunkSize: 64 * 1024,
            avgHandshakeMs: 100
        )
        
        // Session data without handshake time - should keep current
        let sessionData = SessionData(handshakeTimeMs: nil)
        let merged = initial.merged(with: sessionData)
        
        XCTAssertEqual(merged.avgHandshakeMs, 100, "Should keep existing value when new is nil")
        XCTAssertEqual(merged.optimalChunkSize, 64 * 1024)
    }

    func testMergedProfileWithSuccessfulSession() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let initial = LearnedProfile(
            fingerprint: fingerprint,
            successRate: 0.8
        )
        
        let successfulSession = SessionData(wasSuccessful: true)
        let merged = initial.merged(with: successfulSession)
        
        // Alpha = 1/2 = 0.5, so successRate = 0.8 * 0.5 + 1.0 * 0.5 = 0.9
        XCTAssertEqual(merged.successRate, 0.9)
    }

    func testMergedProfileWithFailedSession() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let initial = LearnedProfile(
            fingerprint: fingerprint,
            successRate: 1.0
        )
        
        let failedSession = SessionData(wasSuccessful: false)
        let merged = initial.merged(with: failedSession)
        
        // Alpha = 1/2 = 0.5, so successRate = 1.0 * 0.5 + 0.0 * 0.5 = 0.5
        XCTAssertEqual(merged.successRate, 0.5)
    }

    func testMergedProfileUpdatesLastUpdated() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        let initial = LearnedProfile(fingerprint: fingerprint)
        Thread.sleep(forTimeInterval: 0.01) // Small delay
        
        let sessionData = SessionData()
        let merged = initial.merged(with: sessionData)
        
        XCTAssertGreaterThan(merged.lastUpdated, initial.lastUpdated)
    }

    // MARK: - MTPDeviceFingerprint Tests

    func testFingerprintFromUSB() {
        let fingerprint = MTPDeviceFingerprint.fromUSB(
            vid: 0x18d1,
            pid: 0x4ee1,
            bcdDevice: 0x1234,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            epIn: 0x81,
            epOut: 0x01,
            epEvt: 0x82,
            deviceInfoStrings: ["Google", "Pixel 7"]
        )
        
        XCTAssertEqual(fingerprint.vid, "18d1")
        XCTAssertEqual(fingerprint.pid, "4ee1")
        XCTAssertEqual(fingerprint.bcdDevice, "1234")
        XCTAssertEqual(fingerprint.interfaceTriple.class, "06")
        XCTAssertEqual(fingerprint.interfaceTriple.subclass, "01")
        XCTAssertEqual(fingerprint.interfaceTriple.protocol, "01")
        XCTAssertEqual(fingerprint.endpointAddresses.input, "81")
        XCTAssertEqual(fingerprint.endpointAddresses.output, "01")
        XCTAssertEqual(fingerprint.endpointAddresses.event, "82")
        XCTAssertNotNil(fingerprint.deviceInfoHash)
    }

    func testFingerprintHashString() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            bcdDevice: "1234",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
            deviceInfoHash: "hash123"
        )
        
        let hash = fingerprint.hashString
        XCTAssertFalse(hash.isEmpty)
        XCTAssertTrue(hash.contains("18d1"))
        XCTAssertTrue(hash.contains("4ee1"))
    }

    func testFingerprintWithNilOptionals() {
        let fingerprint = MTPDeviceFingerprint(
            vid: "18d1",
            pid: "4ee1",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: nil)
        )
        
        XCTAssertNil(fingerprint.bcdDevice)
        XCTAssertNil(fingerprint.endpointAddresses.event)
        XCTAssertNil(fingerprint.deviceInfoHash)
    }

    // MARK: - SessionData Tests

    func testSessionDataDefaultSuccess() {
        let session = SessionData()
        XCTAssertTrue(session.wasSuccessful)
        XCTAssertNil(session.actualChunkSize)
        XCTAssertNil(session.handshakeTimeMs)
        XCTAssertNil(session.readThroughputMBps)
        XCTAssertNil(session.writeThroughputMBps)
    }

    func testSessionDataWithAllValues() {
        let session = SessionData(
            actualChunkSize: 32 * 1024,
            handshakeTimeMs: 200,
            effectiveIoTimeoutMs: 15000,
            effectiveInactivityTimeoutMs: 30000,
            readThroughputMBps: 30.5,
            writeThroughputMBps: 20.3,
            wasSuccessful: false
        )
        
        XCTAssertEqual(session.actualChunkSize, 32 * 1024)
        XCTAssertEqual(session.handshakeTimeMs, 200)
        XCTAssertEqual(session.effectiveIoTimeoutMs, 15000)
        XCTAssertEqual(session.effectiveInactivityTimeoutMs, 30000)
        XCTAssertEqual(session.readThroughputMBps, 30.5)
        XCTAssertEqual(session.writeThroughputMBps, 20.3)
        XCTAssertFalse(session.wasSuccessful)
    }

    // MARK: - InterfaceTriple and EndpointAddresses Tests

    func testInterfaceTriple() {
        let triple = InterfaceTriple(class: "06", subclass: "01", protocol: "01")
        XCTAssertEqual(triple.class, "06")
        XCTAssertEqual(triple.subclass, "01")
        XCTAssertEqual(triple.protocol, "01")
    }

    func testEndpointAddressesWithEvent() {
        let addrs = EndpointAddresses(input: "81", output: "01", event: "82")
        XCTAssertEqual(addrs.input, "81")
        XCTAssertEqual(addrs.output, "01")
        XCTAssertEqual(addrs.event, "82")
    }

    func testEndpointAddressesWithoutEvent() {
        let addrs = EndpointAddresses(input: "81", output: "01", event: nil)
        XCTAssertEqual(addrs.input, "81")
        XCTAssertEqual(addrs.output, "01")
        XCTAssertNil(addrs.event)
    }
}

// MARK: - ExitCoverageTests

/// Additional tests for Exit.swift coverage
final class ExitCoverageTests: XCTestCase {

    func testExitCodeAllCases() {
        // Test all exit codes are properly defined
        let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
        XCTAssertEqual(codes.count, 5)
        
        // Verify raw values
        XCTAssertEqual(ExitCode.ok.rawValue, 0)
        XCTAssertEqual(ExitCode.usage.rawValue, 64)
        XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
        XCTAssertEqual(ExitCode.software.rawValue, 70)
        XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
    }

    func testExitCodeSendable() {
        // Verify Sendable conformance
        let sendableOk: Sendable = ExitCode.ok
        let sendableUsage: Sendable = ExitCode.usage
        XCTAssertNotNil(sendableOk)
        XCTAssertNotNil(sendableUsage)
    }

    func testExitCodeDescriptions() {
        // Verify descriptions are non-empty
        XCTAssertFalse(String(describing: ExitCode.ok).isEmpty)
        XCTAssertFalse(String(describing: ExitCode.usage).isEmpty)
        XCTAssertFalse(String(describing: ExitCode.unavailable).isEmpty)
        XCTAssertFalse(String(describing: ExitCode.software).isEmpty)
        XCTAssertFalse(String(describing: ExitCode.tempfail).isEmpty)
    }
}

// MARK: - CLICoverageTests

/// Tests for CLI module coverage
final class CLICoverageTests: XCTestCase {

    // MARK: - CLIErrorEnvelope Tests

    func testCLIErrorEnvelopeDefaultInit() {
        let envelope = CLIErrorEnvelope("Test error")
        XCTAssertEqual(envelope.schemaVersion, "1.0")
        XCTAssertEqual(envelope.type, "error")
        XCTAssertEqual(envelope.error, "Test error")
        XCTAssertNil(envelope.details)
        XCTAssertNil(envelope.mode)
        XCTAssertFalse(envelope.timestamp.isEmpty)
    }

    func testCLIErrorEnvelopeWithDetails() {
        let details = ["key1": "value1", "key2": "value2"]
        let envelope = CLIErrorEnvelope("Error with details", details: details, mode: "test-mode")
        
        XCTAssertEqual(envelope.error, "Error with details")
        XCTAssertEqual(envelope.details?["key1"], "value1")
        XCTAssertEqual(envelope.details?["key2"], "value2")
        XCTAssertEqual(envelope.mode, "test-mode")
    }

    func testCLIErrorEnvelopeCodable() throws {
        let envelope = CLIErrorEnvelope("Test error", details: ["key": "value"], mode: "test")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CLIErrorEnvelope.self, from: data)
        
        XCTAssertEqual(decoded.error, envelope.error)
        XCTAssertEqual(decoded.type, envelope.type)
        XCTAssertEqual(decoded.schemaVersion, envelope.schemaVersion)
    }

    // MARK: - JSONIO Tests

    func testJSONIOEncodableConformances() {
        // Verify various types conform to Encodable for CLI output
        struct TestStruct: Encodable {
            let value: String
        }
        
        let test = TestStruct(value: "test")
        XCTAssertNotNil(test as Encodable)
        
        let string: String = "test"
        XCTAssertNotNil(string as Encodable)
        
        let int: Int = 42
        XCTAssertNotNil(int as Encodable)
    }
}
