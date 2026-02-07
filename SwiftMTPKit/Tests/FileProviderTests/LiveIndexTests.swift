// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPIndex
import SwiftMTPCore

final class LiveIndexTests: XCTestCase {
    private var index: SQLiteLiveIndex!

    override func setUp() async throws {
        // Use in-memory database for testing
        index = try SQLiteLiveIndex(path: ":memory:")
    }

    func testUpsertAndQuery() async throws {
        let obj = IndexedObject(
            deviceId: "test-device",
            storageId: 1,
            handle: 100,
            parentHandle: nil,
            name: "DCIM",
            pathKey: "/DCIM",
            sizeBytes: nil,
            mtime: nil,
            formatCode: 0x3001,
            isDirectory: true,
            changeCounter: 0
        )

        try await index.upsertObjects([obj], deviceId: "test-device")

        let children = try await index.children(deviceId: "test-device", storageId: 1, parentHandle: nil)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "DCIM")
        XCTAssertTrue(children[0].isDirectory)
    }

    func testChangeCounter() async throws {
        let counter1 = try await index.currentChangeCounter(deviceId: "test-device")
        XCTAssertEqual(counter1, 0)

        let counter2 = try await index.nextChangeCounter(deviceId: "test-device")
        XCTAssertEqual(counter2, 1)

        let counter3 = try await index.currentChangeCounter(deviceId: "test-device")
        XCTAssertEqual(counter3, 1)
    }

    func testStorageUpsert() async throws {
        let storage = IndexedStorage(
            deviceId: "test-device",
            storageId: 1,
            description: "Internal Storage",
            capacity: 64_000_000_000,
            free: 32_000_000_000,
            readOnly: false
        )

        try await index.upsertStorage(storage)

        let storages = try await index.storages(deviceId: "test-device")
        XCTAssertEqual(storages.count, 1)
        XCTAssertEqual(storages[0].description, "Internal Storage")
    }

    func testStaleMarkingAndPurge() async throws {
        let obj = IndexedObject(
            deviceId: "test-device", storageId: 1, handle: 100,
            parentHandle: nil, name: "old-file.txt", pathKey: "/old-file.txt",
            sizeBytes: 1024, mtime: nil, formatCode: 0x3000,
            isDirectory: false, changeCounter: 0
        )

        try await index.upsertObjects([obj], deviceId: "test-device")

        // Mark stale
        try await index.markStaleChildren(deviceId: "test-device", storageId: 1, parentHandle: nil)

        // Stale objects not returned by children query
        let children = try await index.children(deviceId: "test-device", storageId: 1, parentHandle: nil)
        XCTAssertEqual(children.count, 0)

        // Purge removes them permanently
        try await index.purgeStale(deviceId: "test-device", storageId: 1, parentHandle: nil)
    }

    func testChangesSince() async throws {
        let obj1 = IndexedObject(
            deviceId: "test-device", storageId: 1, handle: 100,
            parentHandle: nil, name: "file1.txt", pathKey: "/file1.txt",
            sizeBytes: 1024, mtime: nil, formatCode: 0x3000,
            isDirectory: false, changeCounter: 0
        )

        try await index.upsertObjects([obj1], deviceId: "test-device")
        let anchor = try await index.currentChangeCounter(deviceId: "test-device")

        // Add another object
        let obj2 = IndexedObject(
            deviceId: "test-device", storageId: 1, handle: 101,
            parentHandle: nil, name: "file2.txt", pathKey: "/file2.txt",
            sizeBytes: 2048, mtime: nil, formatCode: 0x3000,
            isDirectory: false, changeCounter: 0
        )
        try await index.upsertObjects([obj2], deviceId: "test-device")

        let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
        XCTAssertTrue(changes.contains(where: { $0.object.name == "file2.txt" }))
    }

    func testRemoveObject() async throws {
        let obj = IndexedObject(
            deviceId: "test-device", storageId: 1, handle: 100,
            parentHandle: nil, name: "to-delete.txt", pathKey: "/to-delete.txt",
            sizeBytes: 512, mtime: nil, formatCode: 0x3000,
            isDirectory: false, changeCounter: 0
        )

        try await index.upsertObjects([obj], deviceId: "test-device")
        let anchor = try await index.currentChangeCounter(deviceId: "test-device")

        try await index.removeObject(deviceId: "test-device", storageId: 1, handle: 100)

        // Object should no longer appear in children
        let children = try await index.children(deviceId: "test-device", storageId: 1, parentHandle: nil)
        XCTAssertEqual(children.count, 0)

        // Should appear as deleted in changes
        let changes = try await index.changesSince(deviceId: "test-device", anchor: anchor)
        XCTAssertTrue(changes.contains(where: { $0.kind == .deleted && $0.object.handle == 100 }))
    }
}
