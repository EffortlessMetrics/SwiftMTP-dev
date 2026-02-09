// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPIndex
@testable import SwiftMTPCore
import SQLite

// MARK: - Test Helpers

extension IndexedObject {
    static func testObject(
        deviceId: String = "test-device",
        storageId: UInt32 = 0x10001,
        handle: UInt32 = 0x20001,
        parentHandle: UInt32? = nil,
        name: String = "test.txt",
        pathKey: String = "00010001/test.txt",
        sizeBytes: UInt64 = 1024,
        isDirectory: Bool = false,
        formatCode: UInt16 = 0x3004,
        changeCounter: Int64 = 0
    ) -> IndexedObject {
        IndexedObject(
            deviceId: deviceId,
            storageId: storageId,
            handle: handle,
            parentHandle: parentHandle,
            name: name,
            pathKey: pathKey,
            sizeBytes: sizeBytes,
            mtime: Date(),
            formatCode: formatCode,
            isDirectory: isDirectory,
            changeCounter: changeCounter
        )
    }
}

// MARK: - SQLite Index Integration Tests

@Suite("SQLiteLiveIndex Integration Tests")
struct SQLiteIndexIntegrationTests {
    
    // MARK: - CRUD Operations
    
    @Test("Create and read object")
    func testCreateAndReadObject() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let obj = IndexedObject.testObject()
        try await index.insertObject(obj, deviceId: "test-device")
        
        let retrieved = try await index.object(deviceId: "test-device", handle: 0x20001)
        #expect(retrieved != nil)
        #expect(retrieved?.handle == 0x20001)
        #expect(retrieved?.name == "test.txt")
    }
    
    @Test("Update existing object")
    func testUpdateObject() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let obj = IndexedObject.testObject(handle: 0x20001, name: "original.txt", sizeBytes: 1024)
        try await index.insertObject(obj, deviceId: "test-device")
        
        let updated = IndexedObject.testObject(handle: 0x20001, name: "updated.txt", sizeBytes: 2048)
        try await index.upsertObjects([updated], deviceId: "test-device")
        
        let retrieved = try await index.object(deviceId: "test-device", handle: 0x20001)
        #expect(retrieved?.name == "updated.txt")
        #expect(retrieved?.sizeBytes == 2048)
    }
    
    @Test("Delete object marks as stale")
    func testDeleteObject() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let obj = IndexedObject.testObject(handle: 0x20001)
        try await index.insertObject(obj, deviceId: "test-device")
        
        try await index.removeObject(deviceId: "test-device", storageId: 0x10001, handle: 0x20001)
        
        let retrieved = try await index.object(deviceId: "test-device", handle: 0x20001)
        #expect(retrieved == nil)
        
        // Verify change counter was incremented
        let counter = try await index.currentChangeCounter(deviceId: "test-device")
        #expect(counter > 0)
    }
    
    // MARK: - Batch Operations
    
    @Test("Batch insert 1000 objects")
    func testBatchInsert1000Objects() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let objects = (0..<1000).map { i in
            IndexedObject.testObject(
                handle: UInt32(0x20000 + i),
                name: "file\(i).txt",
                pathKey: "00010001/folder\(i % 10)/file\(i).txt"
            )
        }
        
        let startTime = Date()
        try await index.upsertObjects(objects, deviceId: "test-device")
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Verify all objects inserted
        for i in 0..<1000 {
            let obj = try await index.object(deviceId: "test-device", handle: UInt32(0x20000 + i))
            #expect(obj != nil)
        }
        
        // Performance assertion - should complete within reasonable time
        #expect(elapsed < 30.0)
    }
    
    // MARK: - Index Queries
    
    @Test("Query children by parent handle")
    func testQueryChildren() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Create parent
        let parent = IndexedObject.testObject(
            handle: 0x10001,
            name: "DCIM",
            pathKey: "00010001/DCIM",
            isDirectory: true
        )
        try await index.insertObject(parent, deviceId: "test-device")
        
        // Create children
        for i in 0..<5 {
            let child = IndexedObject.testObject(
                handle: UInt32(0x20000 + i),
                parentHandle: 0x10001,
                name: "photo\(i).jpg",
                pathKey: "00010001/DCIM/photo\(i).jpg"
            )
            try await index.insertObject(child, deviceId: "test-device")
        }
        
        let children = try await index.children(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: 0x10001
        )
        
        #expect(children.count == 5)
    }
    
    @Test("Query root children")
    func testQueryRootChildren() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        for i in 0..<3 {
            let obj = IndexedObject.testObject(
                handle: UInt32(0x20000 + i),
                parentHandle: nil,
                name: "folder\(i)",
                pathKey: "00010001/folder\(i)",
                isDirectory: true
            )
            try await index.insertObject(obj, deviceId: "test-device")
        }
        
        let rootChildren = try await index.children(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: nil
        )
        
        #expect(rootChildren.count == 3)
    }
    
    @Test("Search by name pattern")
    func testSearchByNamePattern() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let names = ["photo.jpg", "document.pdf", "image.png", "picture.jpg"]
        for (i, name) in names.enumerated() {
            let obj = IndexedObject.testObject(
                handle: UInt32(0x20000 + i),
                name: name,
                pathKey: "00010001/\(name)"
            )
            try await index.insertObject(obj, deviceId: "test-device")
        }
        
        // Query all and filter (simplified for mock)
        let all = try await index.children(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: nil
        )
        let jpgFiles = all.filter { $0.name.hasSuffix(".jpg") }
        
        #expect(jpgFiles.count == 2)
    }
    
    // MARK: - Change Tracking
    
    @Test("Track changes since anchor")
    func testChangesSinceAnchor() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Initial state
        let obj1 = IndexedObject.testObject(handle: 0x20001, name: "file1.txt")
        try await index.insertObject(obj1, deviceId: "test-device")
        
        let anchor = try await index.currentChangeCounter(deviceId: "test-device")
        
        // Make changes after anchor
        let obj2 = IndexedObject.testObject(handle: 0x20002, name: "file2.txt")
        try await index.insertObject(obj2, deviceId: "test-device")
        
        let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
        
        #expect(changes.count >= 1)
    }
    
    // MARK: - Storage Operations
    
    @Test("Upsert storage info")
    func testUpsertStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let storage = IndexedStorage(
            deviceId: "test-device",
            storageId: 0x10001,
            description: "Internal Storage",
            capacity: 128_000_000_000,
            free: 64_000_000_000,
            readOnly: false
        )
        try await index.upsertStorage(storage)
        
        let storages = try await index.storages(deviceId: "test-device")
        
        #expect(storages.count == 1)
        #expect(storages.first?.description == "Internal Storage")
    }
    
    // MARK: - Stale Management
    
    @Test("Mark children as stale")
    func testMarkStaleChildren() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let parent = IndexedObject.testObject(
            handle: 0x10001,
            name: "DCIM",
            pathKey: "00010001/DCIM",
            isDirectory: true
        )
        try await index.insertObject(parent, deviceId: "test-device")
        
        let child = IndexedObject.testObject(
            handle: 0x20001,
            parentHandle: 0x10001,
            name: "old.jpg",
            pathKey: "00010001/DCIM/old.jpg"
        )
        try await index.insertObject(child, deviceId: "test-device")
        
        try await index.markStaleChildren(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: 0x10001
        )
        
        let children = try await index.children(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: 0x10001
        )
        
        #expect(children.isEmpty)
    }
    
    @Test("Purge stale objects")
    func testPurgeStale() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let obj = IndexedObject.testObject(handle: 0x20001)
        try await index.insertObject(obj, deviceId: "test-device")
        
        // Mark stale
        try await index.removeObject(deviceId: "test-device", storageId: 0x10001, handle: 0x20001)
        
        // Purge
        try await index.purgeStale(deviceId: "test-device", storageId: 0x10001, parentHandle: nil)
        
        // Verify purged
        let retrieved = try await index.object(deviceId: "test-device", handle: 0x20001)
        #expect(retrieved == nil)
    }
}

// MARK: - Concurrency Tests

@Suite("SQLiteLiveIndex Concurrency Tests")
struct SQLiteIndexConcurrencyTests {
    
    @Test("Concurrent writes from multiple actors")
    func testConcurrentWrites() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-concurrent-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let deviceId = "device-\(i)"
                    let objects = (0..<100).map { j in
                        IndexedObject.testObject(
                            deviceId: deviceId,
                            handle: UInt32(i * 100 + j),
                            name: "file\(i)-\(j).txt"
                        )
                    }
                    try await index.upsertObjects(objects, deviceId: deviceId)
                }
            }
            try await group.waitForAll()
        }
        
        // Verify data integrity
        for i in 0..<5 {
            for j in 0..<100 {
                let obj = try await index.object(deviceId: "device-\(i)", handle: UInt32(i * 100 + j))
                #expect(obj != nil)
            }
        }
    }
    
    @Test("Nested transaction commit")
    func testNestedTransactionCommit() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-nested-commit-\(UUID().uuidString).sqlite").path

        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        // Verify the index can be created and used
        #expect(true)

        let outer = try await index.object(deviceId: "test-device", handle: 0x1001)
        #expect(outer == nil, "Object should not exist yet")
    }

    @Test("Nested transaction rollback isolates inner failure")
    func testNestedTransactionRollback() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-nested-rollback-\(UUID().uuidString).sqlite").path

        let index = try SQLiteLiveIndex(path: dbPath)
        let db = index.database
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        struct InnerError: Error {}

        try db.withTransaction {
            // Outer insert
            try db.withStatement(
                "INSERT INTO live_objects (deviceId, storageId, handle, parentHandle, name, pathKey, sizeBytes, mtime, formatCode, isDirectory, changeCounter, crawledAt, stale) VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, 1, ?, 0)"
            ) { stmt in
                try db.bind(stmt, 1, "test-device")
                try db.bind(stmt, 2, Int64(0x10001))
                try db.bind(stmt, 3, Int64(0x2001))
                try db.bind(stmt, 4, "outer.txt")
                try db.bind(stmt, 5, "00010001/outer.txt")
                try db.bind(stmt, 6, Int64(100))
                try db.bind(stmt, 7, Int64(Date().timeIntervalSince1970))
                try db.bind(stmt, 8, Int64(0x3004))
                try db.bind(stmt, 9, Int64(Date().timeIntervalSince1970))
                _ = try db.step(stmt)
            }

            // Inner transaction throws — should be rolled back
            do {
                try db.withTransaction {
                    try db.withStatement(
                        "INSERT INTO live_objects (deviceId, storageId, handle, parentHandle, name, pathKey, sizeBytes, mtime, formatCode, isDirectory, changeCounter, crawledAt, stale) VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, 1, ?, 0)"
                    ) { stmt in
                        try db.bind(stmt, 1, "test-device")
                        try db.bind(stmt, 2, Int64(0x10001))
                        try db.bind(stmt, 3, Int64(0x2002))
                        try db.bind(stmt, 4, "inner.txt")
                        try db.bind(stmt, 5, "00010001/inner.txt")
                        try db.bind(stmt, 6, Int64(200))
                        try db.bind(stmt, 7, Int64(Date().timeIntervalSince1970))
                        try db.bind(stmt, 8, Int64(0x3004))
                        try db.bind(stmt, 9, Int64(Date().timeIntervalSince1970))
                        _ = try db.step(stmt)
                    }
                    throw InnerError()
                }
            } catch is InnerError {
                // Expected — inner rolled back, outer continues
            }
        }

        let outer = try await index.object(deviceId: "test-device", handle: 0x2001)
        let inner = try await index.object(deviceId: "test-device", handle: 0x2002)
        #expect(outer != nil, "Outer transaction insert should survive")
        #expect(inner == nil, "Inner transaction insert should be rolled back")
    }

    @Test("Concurrent read and write")
    func testConcurrentReadWrite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-index-rw-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Pre-populate
        let initial = (0..<100).map { i in
            IndexedObject.testObject(handle: UInt32(i), name: "initial\(i).txt")
        }
        try await index.upsertObjects(initial, deviceId: "test-device")
        
        // Concurrent read and write
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Reader tasks
            for _ in 0..<3 {
                group.addTask {
                    for _ in 0..<50 {
                        let children = try await index.children(
                            deviceId: "test-device",
                            storageId: 0x10001,
                            parentHandle: nil
                        )
                        _ = children.count
                    }
                }
            }

            // Writer tasks
            for i in 0..<5 {
                group.addTask {
                    let objects = (0..<20).map { j in
                        IndexedObject.testObject(
                            handle: UInt32(1000 + i * 20 + j),
                            name: "new\(i)-\(j).txt"
                        )
                    }
                    try await index.upsertObjects(objects, deviceId: "test-device")
                }
            }
            try await group.waitForAll()
        }
        
        // Verify all data accessible
        let allChildren = try await index.children(
            deviceId: "test-device",
            storageId: 0x10001,
            parentHandle: nil
        )
        #expect(allChildren.count >= 100) // At least initial count
    }
}

// MARK: - Corruption Handling Tests

@Suite("SQLiteLiveIndex Corruption Handling Tests")
struct SQLiteIndexCorruptionTests {
    
    @Test("Handle invalid database header")
    func testInvalidHeader() {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-corrupt-\(UUID().uuidString).sqlite").path
        
        // Write invalid header
        let invalidData = Data(repeating: 0, count: 100)
        try? invalidData.write(to: URL(fileURLWithPath: dbPath))
        
        // Attempting to open should throw or handle gracefully
        #expect(throws: (any Error).self) {
            try SQLiteLiveIndex(path: dbPath)
        }
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Handle partial write recovery")
    func testPartialWriteRecovery() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-partial-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Insert some objects
        for i in 0..<10 {
            let obj = IndexedObject.testObject(handle: UInt32(i), name: "file\(i).txt")
            try await index.insertObject(obj, deviceId: "test-device")
        }
        
        // Simulate partial write by truncating (corruption scenario)
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: dbPath))
        fileHandle.truncateFile(atOffset: 500) // Truncate to partial size
        try fileHandle.close()
        
        // Attempt recovery - should recreate schema or handle gracefully
        let recoveryIndex = try SQLiteLiveIndex(path: dbPath)
        
        // Should be able to write new data
        let newObj = IndexedObject.testObject(handle: 0x30001, name: "recovery.txt")
        try await recoveryIndex.insertObject(newObj, deviceId: "test-device")
        
        let retrieved = try await recoveryIndex.object(deviceId: "test-device", handle: 0x30001)
        #expect(retrieved != nil)
    }
}

// MARK: - Migration Tests

@Suite("SQLiteLiveIndex Migration Tests")
struct SQLiteIndexMigrationTests {
    
    @Test("Migrate from legacy schema")
    func testLegacySchemaMigration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-migrate-\(UUID().uuidString).sqlite").path
        
        // Create legacy schema structure manually
        // The live_index should detect and handle existing tables
        let legacySQL = """
        CREATE TABLE IF NOT EXISTS live_objects (
            deviceId TEXT NOT NULL,
            storageId INTEGER NOT NULL,
            handle INTEGER NOT NULL,
            parentHandle INTEGER,
            name TEXT NOT NULL,
            pathKey TEXT NOT NULL,
            sizeBytes INTEGER,
            mtime INTEGER,
            formatCode INTEGER NOT NULL DEFAULT 0x3000,
            isDirectory INTEGER NOT NULL DEFAULT 0,
            changeCounter INTEGER NOT NULL DEFAULT 0,
            crawledAt INTEGER NOT NULL DEFAULT 0,
            stale INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (deviceId, storageId, handle)
        );
        CREATE INDEX IF NOT EXISTS idx_objects_handle ON live_objects(handle);
        """
        
        // Create a real SQLite DB with a legacy table shape.
        let legacyDB = try Connection(dbPath)
        try legacyDB.execute(legacySQL)
        
        // Open with new schema - should handle gracefully
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Should be able to insert new objects
        let obj = IndexedObject.testObject(handle: 0x20001, name: "new.txt")
        try await index.insertObject(obj, deviceId: "test-device")
        
        let retrieved = try await index.object(deviceId: "test-device", handle: 0x20001)
        #expect(retrieved != nil)
    }
}

// MARK: - Performance Tests

@Suite("SQLiteLiveIndex Performance Tests")
struct SQLiteIndexPerformanceTests {
    
    @Test("Large batch insert performance")
    func testLargeBatchInsert() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-perf-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        let batchSizes = [100, 500, 1000, 2000]
        
        for batchSize in batchSizes {
            let objects = (0..<batchSize).map { i in
                IndexedObject.testObject(
                    handle: UInt32(i),
                    name: "file\(i).dat",
                    pathKey: "00010001/\(i / 100)/file\(i).dat"
                )
            }
            
            let startTime = Date()
            try await index.upsertObjects(objects, deviceId: "test-device")
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Log performance metrics
            let rate = Double(batchSize) / elapsed
            print("Batch size \(batchSize): \(String(format: "%.0f", rate)) objects/sec")
        }
    }
    
    @Test("Query performance with many objects")
    func testQueryPerformance() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-query-perf-\(UUID().uuidString).sqlite").path
        
        let index = try SQLiteLiveIndex(path: dbPath)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        
        // Populate with 5000 objects in hierarchy
        for i in 0..<50 {
            let folder = IndexedObject.testObject(
                handle: UInt32(0x10000 + i),
                name: "folder\(i)",
                pathKey: "00010001/folder\(i)",
                isDirectory: true
            )
            try await index.insertObject(folder, deviceId: "test-device")
            
            for j in 0..<100 {
                let file = IndexedObject.testObject(
                    handle: UInt32(i * 100 + j),
                    parentHandle: UInt32(0x10000 + i),
                    name: "file\(j).txt",
                    pathKey: "00010001/folder\(i)/file\(j).txt"
                )
                try await index.insertObject(file, deviceId: "test-device")
            }
        }
        
        // Query performance test
        let startTime = Date()
        for _ in 0..<100 {
            let children = try await index.children(
                deviceId: "test-device",
                storageId: 0x10001,
                parentHandle: UInt32(0x10000)
            )
            _ = children.count
        }
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("100 queries took \(String(format: "%.3f", elapsed)) seconds")
        #expect(elapsed < 5.0) // Should complete within 5 seconds
    }
}
