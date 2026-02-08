// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for SwiftMTPStoreAdapter
final class StoreAdapterTests: XCTestCase {

    var adapter: SwiftMTPStoreAdapter!

    override func setUp() {
        super.setUp()
        setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
        adapter = SwiftMTPStoreAdapter(store: .shared)
    }

    override func tearDown() {
        adapter = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testAdapterInitializationWithDefaultStore() {
        let defaultAdapter = SwiftMTPStoreAdapter()
        XCTAssertNotNil(defaultAdapter)
    }

    func testAdapterInitializationWithCustomStore() {
        let customStore = SwiftMTPStore.shared
        let customAdapter = SwiftMTPStoreAdapter(store: customStore)
        XCTAssertNotNil(customAdapter)
    }

    // MARK: - Learned Profile Store Tests

    func testLoadNonExistentProfileReturnsNil() async throws {
        let fingerprint = MTPDeviceFingerprint(
            vid: "1234",
            pid: "5678",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )
        
        let profile = try await adapter.loadProfile(for: fingerprint)
        XCTAssertNil(profile)
    }

    func testSaveAndLoadProfileRoundTrip() async throws {
        let fingerprint = MTPDeviceFingerprint(
            vid: "1234",
            pid: "5678",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )
        
        let profile = LearnedProfile(
            fingerprint: fingerprint,
            fingerprintHash: "hash123",
            created: Date(),
            lastUpdated: Date(),
            sampleCount: 10,
            optimalChunkSize: 8192,
            avgHandshakeMs: 50,
            optimalIoTimeoutMs: 5000,
            optimalInactivityTimeoutMs: 30000,
            p95ReadThroughputMBps: 25.0,
            p95WriteThroughputMBps: 15.0,
            successRate: 0.99,
            hostEnvironment: "macOS"
        )
        
        let deviceId = MTPDeviceID(raw: "test-device-id")
        try await adapter.saveProfile(profile, for: deviceId)
        
        let loaded = try await adapter.loadProfile(for: fingerprint)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fingerprintHash, profile.fingerprintHash)
        XCTAssertEqual(loaded?.sampleCount, profile.sampleCount)
    }

    // MARK: - Profiling Store Tests

    func testRecordProfilingRunSucceeds() async throws {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "TestVendor",
            model: "TestModel",
            version: "1.0",
            serialNumber: "SN12345",
            operationsSupported: [0x1001, 0x1002],
            eventsSupported: [0x4002, 0x4003]
        )
        
        let metric = MTPProfileMetric(
            operation: "read",
            count: 100,
            minMs: 10.0,
            maxMs: 100.0,
            avgMs: 50.0,
            p95Ms: 90.0,
            throughputMBps: 20.0
        )
        
        let profile = MTPDeviceProfile(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            metrics: [metric]
        )
        
        let deviceId = MTPDeviceID(raw: "test-device")
        try await adapter.recordProfile(profile, for: deviceId)
        
        // Verify no error was thrown
    }

    // MARK: - Snapshot Store Tests

    func testRecordSnapshotSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        try await adapter.recordSnapshot(
            deviceId: deviceId,
            generation: 1,
            path: "/path/to/snapshot",
            hash: "abc123"
        )
    }

    func testRecordSnapshotWithNilPathAndHash() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        try await adapter.recordSnapshot(
            deviceId: deviceId,
            generation: 1,
            path: nil,
            hash: nil
        )
    }

    // MARK: - Submission Store Tests

    func testRecordSubmissionSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        try await adapter.recordSubmission(
            id: "submission-123",
            deviceId: deviceId,
            path: "/path/to/submission"
        )
    }

    // MARK: - Transfer Journal Tests

    func testBeginReadTransfer() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        let etag = (size: UInt64(1024), mtime: Date())
        
        let transferId = try await adapter.beginRead(
            device: deviceId,
            handle: 100,
            name: "test.txt",
            size: 1024,
            supportsPartial: true,
            tempURL: tempURL,
            finalURL: nil,
            etag: etag
        )
        
        XCTAssertFalse(transferId.isEmpty)
    }

    func testBeginWriteTransfer() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        
        let transferId = try await adapter.beginWrite(
            device: deviceId,
            parent: 200,
            name: "new_file.txt",
            size: 2048,
            supportsPartial: false,
            tempURL: tempURL,
            sourceURL: nil
        )
        
        XCTAssertFalse(transferId.isEmpty)
    }

    func testUpdateTransferProgress() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        
        let transferId = try await adapter.beginWrite(
            device: deviceId,
            parent: 200,
            name: "new_file.txt",
            size: 2048,
            supportsPartial: false,
            tempURL: tempURL,
            sourceURL: nil
        )
        
        try await adapter.updateProgress(id: transferId, committed: 1024)
    }

    func testCompleteTransfer() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        
        let transferId = try await adapter.beginWrite(
            device: deviceId,
            parent: 200,
            name: "new_file.txt",
            size: 2048,
            supportsPartial: false,
            tempURL: tempURL,
            sourceURL: nil
        )
        
        try await adapter.complete(id: transferId)
    }

    func testFailTransferWithError() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        
        let transferId = try await adapter.beginWrite(
            device: deviceId,
            parent: 200,
            name: "new_file.txt",
            size: 2048,
            supportsPartial: false,
            tempURL: tempURL,
            sourceURL: nil
        )
        
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        try await adapter.fail(id: transferId, error: testError)
    }

    func testLoadResumableTransfersForDevice() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        
        // Create a transfer first
        let tempURL = URL(fileURLWithPath: "/tmp/test_temp")
        let transferId = try await adapter.beginRead(
            device: deviceId,
            handle: 100,
            name: "test.txt",
            size: 1024,
            supportsPartial: true,
            tempURL: tempURL,
            finalURL: nil,
            etag: (size: nil, mtime: nil)
        )
        
        let resumables = try await adapter.loadResumables(for: deviceId)
        XCTAssertFalse(resumables.isEmpty)
    }

    func testLoadResumableTransfersEmptyForUnknownDevice() async throws {
        let unknownDeviceId = MTPDeviceID(raw: "unknown-device")
        let resumables = try await adapter.loadResumables(for: unknownDeviceId)
        XCTAssertTrue(resumables.isEmpty)
    }

    // MARK: - Object Catalog Store Tests

    func testRecordStorageSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let storageInfo = MTPStorageInfo(
            id: MTPStorageID(raw: 1),
            description: "Internal Storage",
            capacityBytes: 64_000_000_000,
            freeBytes: 32_000_000_000,
            isReadOnly: false
        )
        
        try await adapter.recordStorage(deviceId: deviceId, storage: storageInfo)
    }

    func testRecordObjectSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let objectInfo = MTPObjectInfo(
            handle: 100,
            storage: MTPStorageID(raw: 1),
            parent: 0,
            name: "test.txt",
            sizeBytes: 1024,
            modified: Date(),
            formatCode: 0x3004,
            properties: [:]
        )
        
        try await adapter.recordObject(
            deviceId: deviceId,
            object: objectInfo,
            pathKey: "/test.txt",
            generation: 1
        )
    }

    func testRecordObjectsBatchSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        let objects: [(MTPObjectInfo, String)] = [
            (MTPObjectInfo(
                handle: 100,
                storage: MTPStorageID(raw: 1),
                parent: 0,
                name: "folder",
                sizeBytes: nil,
                modified: nil,
                formatCode: 0x3001,
                properties: [:]
            ), "/folder"),
            (MTPObjectInfo(
                handle: 101,
                storage: MTPStorageID(raw: 1),
                parent: 100,
                name: "file.txt",
                sizeBytes: 2048,
                modified: Date(),
                formatCode: 0x3004,
                properties: [:]
            ), "/folder/file.txt")
        ]
        
        try await adapter.recordObjects(deviceId: deviceId, objects: objects, generation: 1)
    }

    func testFinalizeIndexingSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        try await adapter.finalizeIndexing(deviceId: deviceId, generation: 1)
    }

    func testFetchObjectsSucceeds() async throws {
        let deviceId = MTPDeviceID(raw: "test-device")
        
        // Record some objects first
        let objectInfo = MTPObjectInfo(
            handle: 100,
            storage: MTPStorageID(raw: 1),
            parent: 0,
            name: "test.txt",
            sizeBytes: 1024,
            modified: Date(),
            formatCode: 0x3004,
            properties: [:]
        )
        
        try await adapter.recordObject(
            deviceId: deviceId,
            object: objectInfo,
            pathKey: "/test.txt",
            generation: 1
        )
        
        let objects = try await adapter.fetchObjects(deviceId: deviceId, generation: 1)
        XCTAssertFalse(objects.isEmpty)
    }

    // MARK: - Clear Stale Temps Tests

    func testClearStaleTempsCompletes() async throws {
        try await adapter.clearStaleTemps(olderThan: 3600)
    }
}
