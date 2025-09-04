// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@preconcurrency import SQLite

@Suite("DiffEngine Tests")
struct DiffEngineTests {

    @Test("Initialize diff engine")
    func testDiffEngineInitialization() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)
        #expect(diffEngine != nil)
    }

    @Test("Compute diff with no previous generation")
    func testDiffNoPreviousGeneration() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert objects in current generation
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 1)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x2, pathKey: "00010001/file2.txt", gen: 1)

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: 1)

        #expect(diff.added.count == 2)
        #expect(diff.removed.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.totalChanges == 2)
        #expect(!diff.isEmpty)
    }

    @Test("Compute diff with added files")
    func testDiffWithAddedFiles() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert objects in old generation
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 1)

        // Insert objects in new generation (old + new)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 2)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x2, pathKey: "00010001/file2.txt", gen: 2)

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: 1, newGen: 2)

        #expect(diff.added.count == 1)
        #expect(diff.added[0].pathKey == "00010001/file2.txt")
        #expect(diff.removed.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.totalChanges == 1)
    }

    @Test("Compute diff with removed files")
    func testDiffWithRemovedFiles() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert objects in old generation
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 1)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x2, pathKey: "00010001/file2.txt", gen: 1)

        // Insert only one object in new generation
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 2)

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: 1, newGen: 2)

        #expect(diff.removed.count == 1)
        #expect(diff.removed[0].pathKey == "00010001/file2.txt")
        #expect(diff.added.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.totalChanges == 1)
    }

    @Test("Compute diff with modified files")
    func testDiffWithModifiedFiles() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert object in old generation
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x1, "file1.txt", "00010001/file1.txt", 1000, 1000000, 0x3000, 1, 0])

        // Insert same object in new generation with different size
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x1, "file1.txt", "00010001/file1.txt", 2000, 1000000, 0x3000, 2, 0])

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: 1, newGen: 2)

        #expect(diff.modified.count == 1)
        #expect(diff.modified[0].pathKey == "00010001/file1.txt")
        #expect(diff.modified[0].size == 2000)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.totalChanges == 1)
    }

    @Test("Compute diff with modified files by mtime")
    func testDiffWithModifiedFilesByMtime() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert object in old generation
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x1, "file1.txt", "00010001/file1.txt", 1000, 1000000, 0x3000, 1, 0])

        // Insert same object in new generation with different mtime
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, ["test-device", 0x10001, 0x1, "file1.txt", "00010001/file1.txt", 1000, 2000000, 0x3000, 2, 0])

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: 1, newGen: 2)

        #expect(diff.modified.count == 1)
        #expect(diff.modified[0].pathKey == "00010001/file1.txt")
        #expect(diff.modified[0].mtime == Date(timeIntervalSince1970: 2000000))
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.totalChanges == 1)
    }

    @Test("Compute diff with no changes")
    func testDiffWithNoChanges() throws {
        let db = try createInMemoryDatabase()
        let diffEngine = DiffEngine(db: db)

        let deviceId = MTPDeviceID(raw: "test-device")

        // Insert same objects in both generations
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 1)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x2, pathKey: "00010001/file2.txt", gen: 1)

        try insertTestObject(db: db, deviceId: deviceId, handle: 0x1, pathKey: "00010001/file1.txt", gen: 2)
        try insertTestObject(db: db, deviceId: deviceId, handle: 0x2, pathKey: "00010001/file2.txt", gen: 2)

        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: 1, newGen: 2)

        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.totalChanges == 0)
        #expect(diff.isEmpty)
    }

    @Test("MTPDiff properties")
    func testMTPDiffProperties() {
        var diff = MTPDiff()
        #expect(diff.isEmpty)
        #expect(diff.totalChanges == 0)

        diff.added = [MTPDiff.Row(handle: 1, storage: 0x10001, pathKey: "test", size: nil, mtime: nil, format: 0x3000)]
        #expect(!diff.isEmpty)
        #expect(diff.totalChanges == 1)
    }

    @Test("MTPDiff.Row initialization")
    func testMTPDiffRowInitialization() {
        let row = MTPDiff.Row(handle: 1, storage: 0x10001, pathKey: "test", size: 1000, mtime: Date(), format: 0x3000)
        #expect(row.handle == 1)
        #expect(row.storage == 0x10001)
        #expect(row.pathKey == "test")
        #expect(row.size == 1000)
        #expect(row.format == 0x3000)
    }

    // Helper function to insert test objects
    private func insertTestObject(db: Connection, deviceId: MTPDeviceID, handle: UInt32, pathKey: String, gen: Int) throws {
        try db.run("""
            INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [deviceId.raw, 0x10001, handle, "test.txt", pathKey, 1000, 1000000, 0x3000, gen, 0])
    }

    // Helper function to create in-memory database with schema
    private func createInMemoryDatabase() throws -> Connection {
        let db = try Connection(.inMemory)
        try db.execute("""
            CREATE TABLE objects(deviceId TEXT NOT NULL, storageId INTEGER NOT NULL, handle INTEGER NOT NULL, parentHandle INTEGER, name TEXT NOT NULL, pathKey TEXT NOT NULL, size INTEGER, mtime INTEGER, format INTEGER NOT NULL, gen INTEGER NOT NULL, tombstone INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(deviceId, storageId, handle));
        """)
        return db
    }
}
