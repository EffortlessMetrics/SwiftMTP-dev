// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@preconcurrency import SQLite

@Suite("Snapshotter Tests")
struct SnapshotterTests {

    @Test("Initialize snapshotter")
    func testSnapshotterInitialization() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        #expect(snapshotter != nil)
    }

    @Test("Capture device info")
    func testCaptureDeviceInfo() async throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let mockDevice = MockDevice()
        let deviceId = MTPDeviceID(raw: "test-device")

        try await snapshotter.captureDeviceInfo(device: mockDevice, deviceId: deviceId, timestamp: Date())

        // Verify device was stored
        let devices = try db.prepare("SELECT id, model FROM devices")
        let deviceRows = Array(devices)
        #expect(deviceRows.count == 1)
        #expect(deviceRows[0][0] as? String == "test-device")
        #expect(deviceRows[0][1] as? String == "Test Device Model")
    }

    @Test("Capture storage info")
    func testCaptureStorageInfo() async throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let storage = MTPStorageInfo(
            id: MTPStorageID(raw: 0x10001),
            description: "Internal Storage",
            capacityBytes: 1000000,
            freeBytes: 500000,
            isReadOnly: false
        )
        let deviceId = MTPDeviceID(raw: "test-device")

        try await snapshotter.captureStorageInfo(storage: storage, deviceId: deviceId, timestamp: Date())

        // Verify storage was stored
        let storages = try db.prepare("SELECT id, deviceId, description, capacity, free, readOnly FROM storages")
        let storageRows = Array(storages)
        #expect(storageRows.count == 1)
        #expect(storageRows[0][0] as? Int64 == 0x10001)
        #expect(storageRows[0][1] as? String == "test-device")
        #expect(storageRows[0][2] as? String == "Internal Storage")
        #expect(storageRows[0][3] as? Int64 == 1000000)
        #expect(storageRows[0][4] as? Int64 == 500000)
        #expect(storageRows[0][5] as? Int64 == 0) // not read-only
    }

    @Test("Build path components from parent chain")
    func testBuildPathComponents() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        // Test with simple parent chain
        let parentMap: [UInt32: UInt32] = [0x2: 0x1] // child -> parent
        let nameMap: [UInt32: String] = [0x1: "root", 0x2: "file.txt"]

        let components = snapshotter.buildPathComponents(for: 0x2, parentMap: parentMap, nameMap: nameMap)
        #expect(components == ["root", "file.txt"])
    }

    @Test("Build path components with deeper hierarchy")
    func testBuildPathComponentsDeep() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        // Test with deeper hierarchy
        let parentMap: [UInt32: UInt32] = [
            0x2: 0x1,
            0x3: 0x2,
            0x4: 0x3
        ]
        let nameMap: [UInt32: String] = [
            0x1: "root",
            0x2: "folder",
            0x3: "subfolder",
            0x4: "file.txt"
        ]

        let components = snapshotter.buildPathComponents(for: 0x4, parentMap: parentMap, nameMap: nameMap)
        #expect(components == ["root", "folder", "subfolder", "file.txt"])
    }

    @Test("Build path components with cycle detection")
    func testBuildPathComponentsCycle() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        // Create a cycle
        let parentMap: [UInt32: UInt32] = [
            0x1: 0x3, // This creates a cycle
            0x2: 0x1,
            0x3: 0x2
        ]
        let nameMap: [UInt32: String] = [
            0x1: "folder1",
            0x2: "folder2",
            0x3: "folder3"
        ]

        // Should handle cycle gracefully (return partial path)
        let components = snapshotter.buildPathComponents(for: 0x1, parentMap: parentMap, nameMap: nameMap)
        #expect(components.count <= 1000) // Safety limit
    }

    @Test("Mark previous generation as tombstoned")
    func testMarkPreviousGenerationTombstoned() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert some objects from previous generation
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x1, "file1.txt", "00010001/file1.txt", 0x3000, 1, 0])

        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x2, "file2.txt", "00010001/file2.txt", 0x3000, 1, 0])

        // Mark previous generation as tombstoned
        try snapshotter.markPreviousGenerationTombstoned(deviceId: deviceId, currentGen: 2)

        // Verify objects were marked as tombstoned
        let objects = try db.prepare("SELECT tombstone FROM objects WHERE gen = 1")
        let objectRows = Array(objects)
        #expect(objectRows.count == 2)
        #expect(objectRows.allSatisfy { ($0[0] as? Int64) == 1 })
    }

    @Test("Record snapshot")
    func testRecordSnapshot() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")
        let timestamp = Date(timeIntervalSince1970: 1000000)

        try snapshotter.recordSnapshot(deviceId: deviceId, gen: 42, timestamp: timestamp)

        // Verify snapshot was recorded
        let snapshots = try db.prepare("SELECT deviceId, gen, createdAt FROM snapshots")
        let snapshotRows = Array(snapshots)
        #expect(snapshotRows.count == 1)
        #expect(snapshotRows[0][0] as? String == "test-device")
        #expect(snapshotRows[0][1] as? Int64 == 42)
        #expect(snapshotRows[0][2] as? Int64 == 1000000)
    }

    @Test("Get latest generation")
    func testGetLatestGeneration() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert snapshots
        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 1, 1000000])

        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 3, 2000000])

        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 2, 1500000])

        let latestGen = try snapshotter.latestGeneration(for: deviceId)
        #expect(latestGen == 3)
    }

    @Test("Get previous generation")
    func testGetPreviousGeneration() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert snapshots
        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 1, 1000000])

        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 2, 1500000])

        try db.run("""
            INSERT INTO snapshots (deviceId, gen, createdAt)
            VALUES (?, ?, ?)
        """, ["test-device", 3, 2000000])

        let prevGen = try snapshotter.previousGeneration(for: deviceId, before: 3)
        #expect(prevGen == 2)
    }

    // Helper function to create in-memory database with schema
    private func createInMemoryDatabase() throws -> Connection {
        let db = try Connection(.inMemory)
        try db.execute("""
            PRAGMA foreign_keys = ON;
            CREATE TABLE devices(id TEXT PRIMARY KEY, model TEXT, lastSeenAt INTEGER);
            CREATE TABLE storages(id INTEGER, deviceId TEXT, description TEXT, capacity INTEGER, free INTEGER, readOnly INTEGER, lastIndexedAt INTEGER, PRIMARY KEY(id, deviceId), FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE);
            CREATE TABLE objects(deviceId TEXT NOT NULL, storageId INTEGER NOT NULL, handle INTEGER NOT NULL, parentHandle INTEGER, name TEXT NOT NULL, pathKey TEXT NOT NULL, size INTEGER, mtime INTEGER, format INTEGER NOT NULL, gen INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(deviceId, storageId, handle), FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE);
            CREATE TABLE snapshots(deviceId TEXT NOT NULL, gen INTEGER NOT NULL, createdAt INTEGER NOT NULL, PRIMARY KEY(deviceId, gen), FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE);
        """)
        return db
    }
}

// Mock device for testing
private class MockDevice: MTPDevice {
    var id: MTPDeviceID { MTPDeviceID(raw: "mock-device") }

    var info: MTPDeviceInfo {
        get async throws {
            MTPDeviceInfo(
                manufacturer: "Test Manufacturer",
                model: "Test Device Model",
                version: "1.0",
                serialNumber: "12345",
                operationsSupported: [],
                eventsSupported: []
            )
        }
    }

    func storages() async throws -> [MTPStorageInfo] {
        []
    }

    func list(parent: UInt32?, in storage: UInt32) -> AsyncThrowingStream<[MTPObjectInfo], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func getInfo(handle: UInt32) async throws -> MTPObjectInfo {
        throw MTPError.notSupported("Mock implementation")
    }

    func read(handle: UInt32, range: Range<UInt64>?, to url: URL) async throws -> Progress {
        throw MTPError.notSupported("Mock implementation")
    }

    func write(parent: UInt32?, name: String, size: UInt64, from url: URL) async throws -> Progress {
        throw MTPError.notSupported("Mock implementation")
    }

    func delete(_ handle: UInt32, recursive: Bool) async throws {
        throw MTPError.notSupported("Mock implementation")
    }

    func move(_ handle: UInt32, to newParent: UInt32?) async throws {
        throw MTPError.notSupported("Mock implementation")
    }

    var events: AsyncStream<MTPEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
