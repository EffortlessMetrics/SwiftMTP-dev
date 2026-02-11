// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore

/// Tests for actor isolation and async safety in SwiftMTPStore
final class StoreConcurrencyTests: XCTestCase {

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

    // MARK: - StoreActor Isolation Tests

    func testStoreActorIsolated() {
        let actor = store.createActor()
        XCTAssertNotNil(actor)
    }

    func testMultipleActorsCreatedFromSameStore() {
        let actor1 = store.createActor()
        let actor2 = store.createActor()
        
        XCTAssertNotNil(actor1)
        XCTAssertNotNil(actor2)
    }

    func testConcurrentActorUsability() async throws {
        let actor = store.createActor()
        
        // Test that actor can be used concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    _ = try await actor.upsertDevice(
                        id: "concurrent-device-\(i)",
                        manufacturer: "Test",
                        model: "Model"
                    )
                }
            }
        }
    }

    // MARK: - Concurrent Device Operations Tests

    func testConcurrentDeviceUpserts() async throws {
        let actor = store.createActor()
        
        let devices = (0..<10).map { "device-\($0)" }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for deviceId in devices {
                group.addTask {
                    _ = try await actor.upsertDevice(
                        id: deviceId,
                        manufacturer: "Vendor",
                        model: "Model"
                    )
                }
            }
        }
    }

    func testConcurrentProfileUpdates() async throws {
        let actor = store.createActor()
        let fingerprint = MTPDeviceFingerprint(
            vid: "1234",
            pid: "5678",
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
        )
        
        let profile = LearnedProfile(
            fingerprint: fingerprint,
            fingerprintHash: "fingerprint-concurrent",
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
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await actor.updateLearnedProfile(
                        for: "fingerprint-concurrent",
                        deviceId: "device-\(i)",
                        profile: profile
                    )
                }
            }
        }
    }

    // MARK: - Concurrent Transfer Operations Tests

    func testConcurrentTransferCreations() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await actor.createTransfer(
                        id: "transfer-\(UUID().uuidString)",
                        deviceId: "device-\(i % 3)",
                        kind: "read",
                        handle: UInt32(100 + i),
                        parentHandle: nil,
                        name: "file\(i).txt",
                        totalBytes: 1024,
                        supportsPartial: true,
                        localTempURL: "/tmp/temp\(i)",
                        finalURL: nil,
                        etagSize: nil,
                        etagMtime: nil
                    )
                }
            }
        }
    }

    func testConcurrentTransferProgressUpdates() async throws {
        let actor = store.createActor()
        
        // Create a transfer first
        let transferId = "transfer-progress-\(UUID().uuidString)"
        try await actor.createTransfer(
            id: transferId,
            deviceId: "device-1",
            kind: "write",
            handle: nil,
            parentHandle: 100,
            name: "file.txt",
            totalBytes: 10_000,
            supportsPartial: false,
            localTempURL: "/tmp/temp",
            finalURL: nil,
            etagSize: nil,
            etagMtime: nil
        )
        
        // Update progress concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await actor.updateTransferProgress(
                        id: transferId,
                        committed: UInt64((i + 1) * 2000)
                    )
                }
            }
        }
    }

    // MARK: - Concurrent Object Operations Tests

    func testConcurrentObjectUpserts() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await actor.upsertObject(
                        deviceId: "device-1",
                        storageId: 1,
                        handle: i,
                        parentHandle: i > 0 ? i - 1 : nil,
                        name: "file\(i).txt",
                        pathKey: "/\(i)/file\(i).txt",
                        size: 1024,
                        mtime: Date(),
                        format: 0x3004,
                        generation: 1
                    )
                }
            }
        }
    }

    func testConcurrentBatchObjectUpserts() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for batch in 0..<5 {
                group.addTask {
                    let objects = (0..<10).map { i -> (
                        storageId: Int,
                        handle: Int,
                        parentHandle: Int?,
                        name: String,
                        pathKey: String,
                        size: Int64?,
                        mtime: Date?,
                        format: Int,
                        generation: Int
                    ) in
                        let globalIndex = batch * 10 + i
                        return (
                            storageId: 1,
                            handle: globalIndex,
                            parentHandle: globalIndex > 0 ? globalIndex - 1 : nil,
                            name: "file\(globalIndex).txt",
                            pathKey: "/\(globalIndex)/file\(globalIndex).txt",
                            size: 2048,
                            mtime: Date(),
                            format: 0x3004,
                            generation: 1
                        )
                    }
                    try await actor.upsertObjects(deviceId: "device-1", objects: objects)
                }
            }
        }
    }

    // MARK: - Storage Operations Tests

    func testConcurrentStorageUpserts() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await actor.upsertStorage(
                        deviceId: "device-1",
                        storageId: i,
                        description: "Storage \(i)",
                        capacity: 64_000_000_000,
                        free: 32_000_000_000,
                        readOnly: false
                    )
                }
            }
        }
    }

    // MARK: - Profiling Operations Tests

    func testConcurrentProfilingRuns() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let metric = MTPProfileMetric(
                        operation: "read",
                        count: 100,
                        minMs: 10.0,
                        maxMs: 100.0,
                        avgMs: 50.0,
                        p95Ms: 90.0,
                        throughputMBps: 20.0
                    )
                    
                    let deviceInfo = MTPDeviceInfo(
                        manufacturer: "Vendor",
                        model: "Model",
                        version: "1.0",
                        serialNumber: "SN\(i)",
                        operationsSupported: [0x1001],
                        eventsSupported: [0x4002]
                    )
                    
                    let profile = MTPDeviceProfile(
                        timestamp: Date(),
                        deviceInfo: deviceInfo,
                        metrics: [metric]
                    )
                    
                    try await actor.recordProfilingRun(deviceId: "device-\(i)", profile: profile)
                }
            }
        }
    }

    // MARK: - Snapshot Operations Tests

    func testConcurrentSnapshotRecordings() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await actor.recordSnapshot(
                        deviceId: "device-1",
                        generation: i,
                        path: "/snapshot/\(i)",
                        hash: "hash\(i)"
                    )
                }
            }
        }
    }

    // MARK: - Mixed Concurrent Operations Tests

    func testMixedConcurrentOperations() async throws {
        let actor = store.createActor()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Device upsert
            group.addTask {
                _ = try await actor.upsertDevice(
                    id: "mixed-device",
                    manufacturer: "Mixed",
                    model: "Vendor"
                )
            }
            
            // Transfer creation
            group.addTask {
                try await actor.createTransfer(
                    id: "mixed-transfer",
                    deviceId: "mixed-device",
                    kind: "read",
                    handle: 100,
                    parentHandle: nil,
                    name: "mixed.txt",
                    totalBytes: 1024,
                    supportsPartial: true,
                    localTempURL: "/tmp/mixed",
                    finalURL: nil,
                    etagSize: nil,
                    etagMtime: nil
                )
            }
            
            // Object upsert
            group.addTask {
                try await actor.upsertObject(
                    deviceId: "mixed-device",
                    storageId: 1,
                    handle: 200,
                    parentHandle: nil,
                    name: "mixed.txt",
                    pathKey: "/mixed.txt",
                    size: 1024,
                    mtime: Date(),
                    format: 0x3004,
                    generation: 1
                )
            }
            
            // Storage upsert
            group.addTask {
                try await actor.upsertStorage(
                    deviceId: "mixed-device",
                    storageId: 1,
                    description: "Mixed Storage",
                    capacity: 64_000_000_000,
                    free: 32_000_000_000,
                    readOnly: false
                )
            }
        }
    }

    // MARK: - Actor Method Isolation Tests

    func testSaveContextIsIsolated() async throws {
        let actor = store.createActor()
        
        // Multiple concurrent save operations should not cause issues
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await actor.saveContext()
                }
            }
        }
    }

    func testFetchObjectsWithGenerationIsolation() async throws {
        let actor = store.createActor()
        let deviceId = "device-\(UUID().uuidString)"
        
        // Insert objects in generation 1
        try await actor.upsertObject(
            deviceId: deviceId,
            storageId: 1,
            handle: 100,
            parentHandle: nil,
            name: "file.txt",
            pathKey: "/file.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004,
            generation: 1
        )
        
        // Fetch objects from generation 1
        let gen1Objects = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
        XCTAssertEqual(gen1Objects.count, 1)
        
        // Fetch objects from generation 2 (should be empty)
        let gen2Objects = try await actor.fetchObjects(deviceId: deviceId, generation: 2)
        XCTAssertEqual(gen2Objects.count, 0)
    }
}
