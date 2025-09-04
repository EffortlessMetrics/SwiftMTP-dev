// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@preconcurrency import SQLite

@Suite("MirrorEngine Tests")
struct MirrorEngineTests {

    @Test("Initialize mirror engine")
    func testMirrorEngineInitialization() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()

        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
        #expect(mirrorEngine != nil)
    }

    @Test("Path key to local URL conversion")
    func testPathKeyToLocalURL() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        let rootURL = URL(fileURLWithPath: "/tmp/mirror")
        let pathKey = "00010001/folder/file.txt"

        // Test the conversion by accessing private method via extension
        let localURL = mirrorEngine.pathKeyToLocalURL(pathKey, root: rootURL)
        #expect(localURL.path == "/tmp/mirror/folder/file.txt")
    }

    @Test("Skip download when file exists and is current")
    func testShouldSkipDownload() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        // Create a temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_file.txt")
        try "test content".write(to: tempURL, atomically: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = MTPDiff.Row(
            handle: 1,
            storage: 0x10001,
            pathKey: "00010001/test_file.txt",
            size: UInt64("test content".count),
            mtime: Date(),
            format: 0x3000
        )

        let shouldSkip = try mirrorEngine.shouldSkipDownload(of: tempURL, file: file)
        #expect(shouldSkip)
    }

    @Test("Download when file doesn't exist")
    func testShouldDownloadWhenFileDoesntExist() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nonexistent_file.txt")

        let file = MTPDiff.Row(
            handle: 1,
            storage: 0x10001,
            pathKey: "00010001/nonexistent_file.txt",
            size: 100,
            mtime: Date(),
            format: 0x3000
        )

        let shouldSkip = try mirrorEngine.shouldSkipDownload(of: tempURL, file: file)
        #expect(!shouldSkip)
    }

    @Test("Download when file size differs")
    func testShouldDownloadWhenSizeDiffers() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        // Create a temporary file with different size
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_file.txt")
        try "short".write(to: tempURL, atomically: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = MTPDiff.Row(
            handle: 1,
            storage: 0x10001,
            pathKey: "00010001/test_file.txt",
            size: 1000, // Different size
            mtime: Date(),
            format: 0x3000
        )

        let shouldSkip = try mirrorEngine.shouldSkipDownload(of: tempURL, file: file)
        #expect(!shouldSkip)
    }

    @Test("Pattern matching")
    func testPatternMatching() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        // Test exact match
        #expect(mirrorEngine.matchesPattern("DCIM/photo.jpg", pattern: "DCIM/photo.jpg"))

        // Test wildcard match
        #expect(mirrorEngine.matchesPattern("DCIM/photo.jpg", pattern: "DCIM/*.jpg"))

        // Test directory match
        #expect(mirrorEngine.matchesPattern("DCIM/folder/photo.jpg", pattern: "DCIM/**"))

        // Test no match
        #expect(!mirrorEngine.matchesPattern("DCIM/photo.jpg", pattern: "Pictures/*.jpg"))
    }

    @Test("Invalid pattern handling")
    func testInvalidPattern() throws {
        let db = try createInMemoryDatabase()
        let snapshotter = Snapshotter(db: db)
        let diffEngine = DiffEngine(db: db)
        let journal = try MockTransferJournal()
        let mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

        // Invalid regex pattern should return false
        #expect(!mirrorEngine.matchesPattern("test", pattern: "[invalid"))
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

// Mock transfer journal for testing
private class MockTransferJournal: TransferJournal {
    func beginRead(device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool, tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String {
        "mock-transfer-id"
    }

    func beginWrite(device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool, tempURL: URL, sourceURL: URL?) throws -> String {
        "mock-transfer-id"
    }

    func updateProgress(id: String, committed: UInt64) throws {
        // No-op
    }

    func fail(id: String, error: Error) throws {
        // No-op
    }

    func complete(id: String) throws {
        // No-op
    }

    func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord] {
        []
    }

    func clearStaleTemps(olderThan: TimeInterval) throws {
        // No-op
    }
}
