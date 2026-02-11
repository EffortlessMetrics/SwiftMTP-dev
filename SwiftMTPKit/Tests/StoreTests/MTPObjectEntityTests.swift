// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore

/// Tests for MTPObjectEntity model
final class MTPObjectEntityTests: XCTestCase {

    // MARK: - Compound ID Tests

    func testCompoundIdFormat() {
        let entity = createTestEntity(
            deviceId: "device123",
            storageId: 1,
            handle: 42
        )
        
        XCTAssertEqual(entity.compoundId, "device123:1:42")
    }

    func testCompoundIdUniqueness() {
        let entity1 = createTestEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 100
        )
        
        let entity2 = createTestEntity(
            deviceId: "device2",
            storageId: 1,
            handle: 100
        )
        
        XCTAssertNotEqual(entity1.compoundId, entity2.compoundId)
    }

    func testCompoundIdWithDifferentStorageIds() {
        let entity1 = createTestEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 100
        )
        
        let entity2 = createTestEntity(
            deviceId: "device1",
            storageId: 2,
            handle: 100
        )
        
        XCTAssertNotEqual(entity1.compoundId, entity2.compoundId)
    }

    // MARK: - Initialization Tests

    func testEntityInitialization() {
        let entity = MTPObjectEntity(
            deviceId: "test-device",
            storageId: 5,
            handle: 123,
            parentHandle: 100,
            name: "test.txt",
            pathKey: "/test/test.txt",
            sizeBytes: 1024,
            modifiedAt: Date(timeIntervalSince1970: 1000),
            formatCode: 0x3001,
            generation: 1
        )
        
        XCTAssertEqual(entity.deviceId, "test-device")
        XCTAssertEqual(entity.storageId, 5)
        XCTAssertEqual(entity.handle, 123)
        XCTAssertEqual(entity.parentHandle, 100)
        XCTAssertEqual(entity.name, "test.txt")
        XCTAssertEqual(entity.pathKey, "/test/test.txt")
        XCTAssertEqual(entity.sizeBytes, 1024)
        XCTAssertEqual(entity.formatCode, 0x3001)
        XCTAssertEqual(entity.generation, 1)
        XCTAssertEqual(entity.tombstone, 0)
    }

    func testEntityWithNilOptionals() {
        let entity = MTPObjectEntity(
            deviceId: "test-device",
            storageId: 1,
            handle: 1,
            parentHandle: nil,
            name: "root.txt",
            pathKey: "/root.txt",
            sizeBytes: nil,
            modifiedAt: nil,
            formatCode: 0x3001,
            generation: 1
        )
        
        XCTAssertNil(entity.parentHandle)
        XCTAssertNil(entity.sizeBytes)
        XCTAssertNil(entity.modifiedAt)
    }

    func testDefaultTombstoneValue() {
        let entity = createTestEntity()
        XCTAssertEqual(entity.tombstone, 0)
    }

    // MARK: - Parent/Child Relationship Tests

    func testParentHandleNilForRoot() {
        let rootEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 0,
            parentHandle: nil,
            name: "root",
            pathKey: "/",
            formatCode: 0x3001,
            generation: 1
        )
        
        XCTAssertNil(rootEntity.parentHandle)
    }

    func testParentHandleSetCorrectly() {
        let parentEntity = createTestEntity(handle: 100, name: "parent")
        let childEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 200,
            parentHandle: parentEntity.handle,
            name: "child",
            pathKey: "/parent/child",
            formatCode: 0x3001,
            generation: 1
        )
        
        XCTAssertEqual(childEntity.parentHandle, 100)
    }

    // MARK: - Path Key Tests

    func testPathKeyUniquenessForDifferentHandles() {
        let entity1 = createTestEntity(handle: 1, pathKey: "/a")
        let entity2 = createTestEntity(handle: 2, pathKey: "/a")
        
        // Same pathKey but different handles means different objects
        XCTAssertNotEqual(entity1.handle, entity2.handle)
        XCTAssertEqual(entity1.pathKey, entity2.pathKey)
    }

    func testPathKeyFormatPreserved() {
        let pathKey = "/DCIM/Camera/photo.jpg"
        let entity = createTestEntity(pathKey: pathKey)
        
        XCTAssertEqual(entity.pathKey, pathKey)
    }

    // MARK: - Format Code Tests

    func testFormatCodeForDifferentObjectTypes() {
        let directoryEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 1,
            name: "folder",
            pathKey: "/folder",
            formatCode: 0x3001, // Association (directory)
            generation: 1
        )
        
        let fileEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 2,
            name: "file.txt",
            pathKey: "/file.txt",
            formatCode: 0x3004, // Text file
            generation: 1
        )
        
        XCTAssertEqual(directoryEntity.formatCode, 0x3001)
        XCTAssertEqual(fileEntity.formatCode, 0x3004)
    }

    // MARK: - Generation Tests

    func testGenerationIncrementedOnUpdate() {
        let entity = createTestEntity(generation: 1)
        XCTAssertEqual(entity.generation, 1)
        
        // Simulate update with new generation
        let updatedEntity = MTPObjectEntity(
            deviceId: entity.deviceId,
            storageId: entity.storageId,
            handle: entity.handle,
            parentHandle: entity.parentHandle,
            name: entity.name,
            pathKey: entity.pathKey,
            sizeBytes: entity.sizeBytes,
            modifiedAt: entity.modifiedAt,
            formatCode: entity.formatCode,
            generation: 2
        )
        
        XCTAssertEqual(updatedEntity.generation, 2)
    }

    // MARK: - Size Tests

    func testSizeBytesWithVariousValues() {
        let zeroSize = createTestEntity(sizeBytes: 0)
        XCTAssertEqual(zeroSize.sizeBytes, 0)
        
        let largeSize = createTestEntity(sizeBytes: 10_000_000_000)
        XCTAssertEqual(largeSize.sizeBytes, 10_000_000_000)
        
        let nilSize = createTestEntity(sizeBytes: nil)
        XCTAssertNil(nilSize.sizeBytes)
    }

    // MARK: - Unicode and Special Characters Tests

    func testUnicodeFileNames() {
        let unicodeEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 1,
            name: "файл.txt",
            pathKey: "/файл.txt",
            formatCode: 0x3004,
            generation: 1
        )
        
        XCTAssertEqual(unicodeEntity.name, "файл.txt")
    }

    func testEmojiInFileNames() {
        let emojiEntity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 1,
            name: "📷photo.jpg",
            pathKey: "/📷photo.jpg",
            formatCode: 0x3004,
            generation: 1
        )
        
        XCTAssertTrue(emojiEntity.name.contains("📷"))
    }

    func testSpecialCharactersInPath() {
        let entity = MTPObjectEntity(
            deviceId: "device1",
            storageId: 1,
            handle: 1,
            name: "file with spaces.txt",
            pathKey: "/folder with spaces/file with spaces.txt",
            formatCode: 0x3004,
            generation: 1
        )
        
        XCTAssertTrue(entity.pathKey.contains(" "))
        XCTAssertTrue(entity.name.contains(" "))
    }

    // MARK: - Equality Tests

    func testEntitiesWithSameCompoundIdAreEqual() {
        let entity1 = createTestEntity(handle: 1)
        let entity2 = MTPObjectEntity(
            deviceId: entity1.deviceId,
            storageId: entity1.storageId,
            handle: entity1.handle,
            parentHandle: entity1.parentHandle,
            name: entity1.name,
            pathKey: entity1.pathKey,
            sizeBytes: entity1.sizeBytes,
            modifiedAt: entity1.modifiedAt,
            formatCode: entity1.formatCode,
            generation: entity1.generation
        )
        
        XCTAssertEqual(entity1.compoundId, entity2.compoundId)
    }

    // MARK: - Helper Methods

    private func createTestEntity(
        deviceId: String = "test-device",
        storageId: Int = 1,
        handle: Int = 1,
        parentHandle: Int? = nil,
        name: String = "test.txt",
        pathKey: String = "/test.txt",
        sizeBytes: Int64? = 1024,
        modifiedAt: Date? = Date(),
        formatCode: Int = 0x3004,
        generation: Int = 1
    ) -> MTPObjectEntity {
        return MTPObjectEntity(
            deviceId: deviceId,
            storageId: storageId,
            handle: handle,
            parentHandle: parentHandle,
            name: name,
            pathKey: pathKey,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            formatCode: formatCode,
            generation: generation
        )
    }
}
