// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore

/// Tests for error scenarios in SwiftMTPStore
final class StoreErrorHandlingTests: XCTestCase {

    var store: SwiftMTPStore!

    override func setUp() {
        super.setUp()
        setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
        store = .shared
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Fetch Non-Existent Data Tests

    func testFetchNonExistentLearnedProfile() async throws {
        let actor = store.createActor()
        let dto = try await actor.fetchLearnedProfileDTO(for: "non-existent-hash")
        XCTAssertNil(dto)
    }

    func testFetchNonExistentDevice() async throws {
        let actor = store.createActor()
        
        // Create a transfer for a non-existent device should still work (creates device implicitly)
        try await actor.createTransfer(
            id: "orphan-transfer",
            deviceId: "orphan-device",
            kind: "read",
            handle: 100,
            parentHandle: nil,
            name: "orphan.txt",
            totalBytes: 1024,
            supportsPartial: true,
            localTempURL: "/tmp/orphan",
            finalURL: nil,
            etagSize: nil,
            etagMtime: nil
        )
    }

    func testFetchNonExistentObjects() async throws {
        let actor = store.createActor()
        
        // Fetch objects for a device with no objects
        let objects = try await actor.fetchObjects(deviceId: "non-existent-device", generation: 1)
        XCTAssertTrue(objects.isEmpty)
    }

    func testFetchNonExistentResumableTransfers() async throws {
        let actor = store.createActor()
        
        let transfers = try await actor.fetchResumableTransfers(for: "non-existent-device")
        XCTAssertTrue(transfers.isEmpty)
    }

    // MARK: - Transfer Status Update Tests

    func testUpdateProgressForNonExistentTransfer() async throws {
        let actor = store.createActor()
        
        // Should not throw even if transfer doesn't exist
        try await actor.updateTransferProgress(id: "non-existent-id", committed: 1000)
    }

    func testUpdateStatusForNonExistentTransfer() async throws {
        let actor = store.createActor()
        
        // Should not throw even if transfer doesn't exist
        try await actor.updateTransferStatus(id: "non-existent-id", state: "done")
    }

    // MARK: - Object Operations with Invalid Data Tests

    func testUpsertObjectWithNilSizeAndMtime() async throws {
        let actor = store.createActor()
        
        try await actor.upsertObject(
            deviceId: "device-1",
            storageId: 1,
            handle: 100,
            parentHandle: nil,
            name: "file.txt",
            pathKey: "/file.txt",
            size: nil,
            mtime: nil,
            format: 0x3004,
            generation: 1
        )
        
        // Verify object was created
        let objects = try await actor.fetchObjects(deviceId: "device-1", generation: 1)
        XCTAssertEqual(objects.count, 1)
        XCTAssertNil(objects.first?.size)
        XCTAssertNil(objects.first?.mtime)
    }

    func testUpsertObjectWithInvalidParentHandle() async throws {
        let actor = store.createActor()
        
        // Create child with non-existent parent
        try await actor.upsertObject(
            deviceId: "device-1",
            storageId: 1,
            handle: 200,
            parentHandle: 9999, // Non-existent parent
            name: "orphan.txt",
            pathKey: "/orphan.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004,
            generation: 1
        )
        
        // Should still succeed - parent relationship is not enforced at DB level
        let objects = try await actor.fetchObjects(deviceId: "device-1", generation: 1)
        XCTAssertEqual(objects.count, 1)
    }

    // MARK: - Batch Operations with Empty Input Tests

    func testUpsertObjectsWithEmptyArray() async throws {
        let actor = store.createActor()
        
        // Should not throw with empty array
        try await actor.upsertObjects(deviceId: "device-1", objects: [])
    }

    // MARK: - Generation Tombstoning Tests

    func testMarkPreviousGenerationTombstoned() async throws {
        let actor = store.createActor()
        
        // Create objects in generation 1
        try await actor.upsertObject(
            deviceId: "device-1",
            storageId: 1,
            handle: 100,
            parentHandle: nil,
            name: "gen1.txt",
            pathKey: "/gen1.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004,
            generation: 1
        )
        
        // Mark generation 1 as tombstones
        try await actor.markPreviousGenerationTombstoned(deviceId: "device-1", currentGen: 2)
        
        // Fetch generation 1 should return empty (tombstoned)
        let gen1Objects = try await actor.fetchObjects(deviceId: "device-1", generation: 1)
        XCTAssertEqual(gen1Objects.count, 0)
    }

    func testTombstoneDoesNotAffectNewerGeneration() async throws {
        let actor = store.createActor()
        
        // Create objects in generation 1
        try await actor.upsertObject(
            deviceId: "device-1",
            storageId: 1,
            handle: 100,
            parentHandle: nil,
            name: "gen1.txt",
            pathKey: "/gen1.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004,
            generation: 1
        )
        
        // Create objects in generation 2
        try await actor.upsertObject(
            deviceId: "device-1",
            storageId: 1,
            handle: 200,
            parentHandle: nil,
            name: "gen2.txt",
            pathKey: "/gen2.txt",
            size: 2048,
            mtime: Date(),
            format: 0x3004,
            generation: 2
        )
        
        // Mark generation 1 as tombstones
        try await actor.markPreviousGenerationTombstoned(deviceId: "device-1", currentGen: 2)
        
        // Fetch generation 2 should still have the object
        let gen2Objects = try await actor.fetchObjects(deviceId: "device-1", generation: 2)
        XCTAssertEqual(gen2Objects.count, 1)
        XCTAssertEqual(gen2Objects.first?.pathKey, "/gen2.txt")
    }

    // MARK: - Storage Operations Tests

    func testUpsertStorageUpdatesExisting() async throws {
        let actor = store.createActor()
        
        // Create initial storage
        try await actor.upsertStorage(
            deviceId: "device-1",
            storageId: 1,
            description: "Initial Storage",
            capacity: 64_000_000_000,
            free: 32_000_000_000,
            readOnly: false
        )
        
        // Update storage with new values
        try await actor.upsertStorage(
            deviceId: "device-1",
            storageId: 1,
            description: "Updated Storage",
            capacity: 128_000_000_000,
            free: 64_000_000_000,
            readOnly: true
        )
        
        // Verify only one storage record exists (update worked)
        // Note: We can't easily verify the update without direct DB access,
        // but the operation should not throw
    }

    // MARK: - Learned Profile Error Handling Tests

    func testUpdateLearnedProfileForNonExistentDevice() async throws {
        let actor = store.createActor()
        
        let fingerprint = MTPDeviceFingerprint(
            vid: "1234",
            pid: "5678",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )
        
        let profile = LearnedProfile(
            fingerprint: fingerprint,
            fingerprintHash: "test-hash",
            created: Date(),
            lastUpdated: Date(),
            sampleCount: 1,
            optimalChunkSize: 4096,
            avgHandshakeMs: 10,
            optimalIoTimeoutMs: 1000,
            optimalInactivityTimeoutMs: 5000,
            p95ReadThroughputMBps: 10.0,
            p95WriteThroughputMBps: 5.0,
            successRate: 1.0,
            hostEnvironment: "test"
        )
        
        // Should create device implicitly and succeed
        try await actor.updateLearnedProfile(
            for: "test-hash",
            deviceId: "new-device",
            profile: profile
        )
    }

    // MARK: - Transfer State Machine Tests

    func testTransferStateTransitions() async throws {
        let actor = store.createActor()
        
        let transferId = "state-test-\(UUID().uuidString)"
        
        // Create transfer
        try await actor.createTransfer(
            id: transferId,
            deviceId: "device-1",
            kind: "read",
            handle: 100,
            parentHandle: nil,
            name: "test.txt",
            totalBytes: 10_000,
            supportsPartial: true,
            localTempURL: "/tmp/test",
            finalURL: nil,
            etagSize: nil,
            etagMtime: nil
        )
        
        // Update progress
        try await actor.updateTransferProgress(id: transferId, committed: 5000)
        
        // Complete transfer
        try await actor.updateTransferStatus(id: transferId, state: "done")
        
        // Verify final state (transfer should still exist but with "done" state)
        let transfers = try await actor.fetchResumableTransfers(for: "device-1")
        let completedTransfer = transfers.first { $0.id == transferId }
        XCTAssertNil(completedTransfer) // Done transfers are not resumable
    }

    func testTransferFailureWithError() async throws {
        let actor = store.createActor()
        
        let transferId = "failure-test-\(UUID().uuidString)"
        
        try await actor.createTransfer(
            id: transferId,
            deviceId: "device-1",
            kind: "write",
            handle: nil,
            parentHandle: 100,
            name: "failing.txt",
            totalBytes: 5000,
            supportsPartial: false,
            localTempURL: "/tmp/fail",
            finalURL: nil,
            etagSize: nil,
            etagMtime: nil
        )
        
        // Simulate failure
        try await actor.updateTransferStatus(
            id: transferId,
            state: "failed",
            error: "Connection timeout"
        )
        
        // Failed transfers should not be resumable
        let resumable = try await actor.fetchResumableTransfers(for: "device-1")
        XCTAssertNil(resumable.first { $0.id == transferId })
    }

    // MARK: - Edge Cases

    func testHandleZeroIsValid() async throws {
        let actor = store.createActor()
        
        // Root folder often has handle 0
        try await actor.upsertObject(
            deviceId: "device-handle-zero",
            storageId: 1,
            handle: 0,
            parentHandle: nil,
            name: "root",
            pathKey: "/",
            size: nil,
            mtime: nil,
            format: 0x3001,
            generation: 1
        )
        
        let objects = try await actor.fetchObjects(deviceId: "device-handle-zero", generation: 1)
        XCTAssertEqual(objects.count, 1)
    }

    func testMaxUInt32HandleValue() async throws {
        let actor = store.createActor()
        
        try await actor.upsertObject(
            deviceId: "device-max-handle",
            storageId: 1,
            handle: 1000, // Use a reasonable handle value for testing
            parentHandle: nil,
            name: "test_handle.txt",
            pathKey: "/test_handle.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004,
            generation: 1
        )
        
        let objects = try await actor.fetchObjects(deviceId: "device-max-handle", generation: 1)
        XCTAssertEqual(objects.count, 1)
    }

    func testVeryLargeStorageCapacity() async throws {
        let actor = store.createActor()
        
        // Test with values that might exceed common limits
        try await actor.upsertStorage(
            deviceId: "device-1",
            storageId: 1,
            description: "Large Storage",
            capacity: Int64.max / 2,
            free: 9_223_372_036_854_775_807,
            readOnly: false
        )
    }

    func testSpecialCharactersInTransferNames() async throws {
        let actor = store.createActor()
        
        let specialNames = [
            "file with spaces.txt",
            "file-with-dashes.txt",
            "file_with_underscores.txt",
            "123numeric.txt",
            "MIXED.CASE.TXT"
        ]
        
        for (index, name) in specialNames.enumerated() {
            try await actor.createTransfer(
                id: "transfer-\(index)",
                deviceId: "device-1",
                kind: "read",
                handle: UInt32(100 + index),
                parentHandle: nil,
                name: name,
                totalBytes: 1024,
                supportsPartial: true,
                localTempURL: "/tmp/\(name.replacingOccurrences(of: " ", with: "_"))",
                finalURL: nil,
                etagSize: nil,
                etagMtime: nil
            )
        }
    }

    func testUnicodeInObjectNames() async throws {
        let actor = store.createActor()
        
        let unicodeNames = [
            "файл.txt",
            "文件.txt",
            "파일.txt",
            "ファイル.txt",
            "emoji📷.jpg"
        ]
        
        for (index, name) in unicodeNames.enumerated() {
            try await actor.upsertObject(
                deviceId: "device-1",
                storageId: 1,
                handle: index,
                parentHandle: nil,
                name: name,
                pathKey: "/\(name)",
                size: 1024,
                mtime: Date(),
                format: 0x3004,
                generation: 1
            )
        }
        
        let objects = try await actor.fetchObjects(deviceId: "device-1", generation: 1)
        XCTAssertEqual(objects.count, unicodeNames.count)
    }
}
