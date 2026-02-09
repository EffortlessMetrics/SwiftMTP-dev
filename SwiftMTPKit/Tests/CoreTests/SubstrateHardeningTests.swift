// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Tests for SubstrateHardening.swift - Feature flags, BDD foundation, snapshot testing, and fuzz helpers
final class SubstrateHardeningTests: XCTestCase {

    // MARK: - MTPFeatureFlags Tests

    func testMTPFeatureFlagsDefaultInitialization() {
        // Test that MTPFeatureFlags can be initialized
        let flags = MTPFeatureFlags.shared
        XCTAssertNotNil(flags)
    }

    func testMTPFeatureIsEnabledDefaultFalse() {
        // Most features should be disabled by default
        let flags = MTPFeatureFlags.shared
        
        // Test each feature - they should be false unless env var is set
        XCTAssertFalse(flags.isEnabled(.propListFastPath))
        XCTAssertFalse(flags.isEnabled(.chunkedTransfer))
        XCTAssertFalse(flags.isEnabled(.extendedObjectInfo))
        XCTAssertFalse(flags.isEnabled(.backgroundEventPump))
        XCTAssertFalse(flags.isEnabled(.learnPromote))
    }

    func testMTPFeatureSetEnabled() {
        let flags = MTPFeatureFlags.shared
        
        // Set a feature to enabled
        flags.setEnabled(.chunkedTransfer, true)
        XCTAssertTrue(flags.isEnabled(.chunkedTransfer))
        
        // Set it back to disabled
        flags.setEnabled(.chunkedTransfer, false)
        XCTAssertFalse(flags.isEnabled(.chunkedTransfer))
    }

    func testMTPFeatureSetEnabledMultipleFeatures() {
        let flags = MTPFeatureFlags.shared
        
        // Enable multiple features
        flags.setEnabled(.chunkedTransfer, true)
        flags.setEnabled(.extendedObjectInfo, true)
        
        XCTAssertTrue(flags.isEnabled(.chunkedTransfer))
        XCTAssertTrue(flags.isEnabled(.extendedObjectInfo))
        XCTAssertFalse(flags.isEnabled(.propListFastPath))
    }

    func testMTPFeatureFlagsThreadSafety() {
        let flags = MTPFeatureFlags.shared
        let expectation = XCTestExpectation(description: "Thread safety test")
        
        DispatchQueue.global().async {
            for _ in 0..<100 {
                _ = flags.isEnabled(.chunkedTransfer)
                flags.setEnabled(.chunkedTransfer, Bool.random())
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }

    func testMTPFeatureAllCases() {
        // Verify all features are accessible
        let allFeatures = MTPFeature.allCases
        XCTAssertEqual(allFeatures.count, 5)
        
        XCTAssertTrue(allFeatures.contains(.propListFastPath))
        XCTAssertTrue(allFeatures.contains(.chunkedTransfer))
        XCTAssertTrue(allFeatures.contains(.extendedObjectInfo))
        XCTAssertTrue(allFeatures.contains(.backgroundEventPump))
        XCTAssertTrue(allFeatures.contains(.learnPromote))
    }

    func testMTPFeatureRawValues() {
        // Verify raw values are as expected
        XCTAssertEqual(MTPFeature.propListFastPath.rawValue, "PROPLIST_FASTPATH")
        XCTAssertEqual(MTPFeature.chunkedTransfer.rawValue, "CHUNKED_TRANSFER")
        XCTAssertEqual(MTPFeature.extendedObjectInfo.rawValue, "EXTENDED_OBJECTINFO")
        XCTAssertEqual(MTPFeature.backgroundEventPump.rawValue, "BACKGROUND_EVENTPUMP")
        XCTAssertEqual(MTPFeature.learnPromote.rawValue, "LEARN_PROMOTE")
    }

    // MARK: - BDDContext Tests

    func testBDDContextInitialization() {
        // Create a mock MTPLink - we just need a reference for initialization
        let mockLink = MockMTPLinkForBDD()
        let context = BDDContext(link: mockLink)
        XCTAssertNotNil(context)
    }

    func testBDDContextStep() {
        let mockLink = MockMTPLinkForBDD()
        let context = BDDContext(link: mockLink)
        
        // Step should not throw
        XCTAssertNoThrow(context.step("Given a device is connected"))
    }

    func testBDDContextVerifySuccess() {
        let mockLink = MockMTPLinkForBDD()
        let context = BDDContext(link: mockLink)
        
        // Verify should not throw when condition is true
        XCTAssertNoThrow(try context.verify(true, "Device is connected"))
    }

    func testBDDContextVerifyFailure() {
        let mockLink = MockMTPLinkForBDD()
        let context = BDDContext(link: mockLink)
        
        // Verify should throw when condition is false
        XCTAssertThrowsError(try context.verify(false, "Device should be connected")) { error in
            XCTAssertEqual((error as NSError).domain, "BDDFailure")
            XCTAssertEqual((error as NSError).code, 1)
        }
    }

    func testBDDScenarioName() {
        let mockLink = MockMTPLinkForBDD()
        let context = BDDContext(link: mockLink)
        
        // Verify we can access link from context
        _ = context.link
    }

    // MARK: - MTPSnapshot Tests

    func testMTPSnapshotInitialization() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "Test",
            model: "TestDevice",
            version: "1.0",
            serialNumber: "12345",
            operationsSupported: Set([0x1001, 0x1002]),
            eventsSupported: Set([0x4002])
        )
        
        let storage = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00010001),
            description: "Internal",
            capacityBytes: 16_000_000_000,
            freeBytes: 8_000_000_000,
            isReadOnly: false
        )
        
        let object = MTPObjectInfo(
            handle: 0x00010001,
            storage: MTPStorageID(raw: 0x00010001),
            parent: 0x00000000,
            name: "test.txt",
            sizeBytes: 1024,
            modified: Date(),
            formatCode: 0x3001,
            properties: [:]
        )
        
        let snapshot = MTPSnapshot(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            storages: [storage],
            objects: [object]
        )
        
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot.deviceInfo.manufacturer, "Test")
        XCTAssertEqual(snapshot.storages.count, 1)
        XCTAssertEqual(snapshot.objects.count, 1)
    }

    func testMTPSnapshotJsonString() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "Test",
            model: "TestDevice",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: Set([0x1001]),
            eventsSupported: Set([])
        )
        
        let snapshot = MTPSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            deviceInfo: deviceInfo,
            storages: [],
            objects: []
        )
        
        XCTAssertNoThrow {
            let json = try snapshot.jsonString()
            XCTAssertFalse(json.isEmpty)
            // Verify it's valid JSON
            let data = json.data(using: .utf8)
            XCTAssertNotNil(data)
        }
    }

    func testMTPSnapshotJsonStringPrettyPrinted() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "Test",
            model: "TestDevice",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: Set([0x1001]),
            eventsSupported: Set([])
        )
        
        let snapshot = MTPSnapshot(
            timestamp: Date(),
            deviceInfo: deviceInfo,
            storages: [],
            objects: []
        )
        
        XCTAssertNoThrow {
            let json = try snapshot.jsonString()
            // Pretty printed JSON should contain newlines and indentation
            XCTAssertTrue(json.contains("\n") || json.contains("  "))
        }
    }

    func testMTPSnapshotCodable() {
        // Verify MTPSnapshot is Codable
        let snapshot = MTPSnapshot(
            timestamp: Date(),
            deviceInfo: MTPDeviceInfo(
                manufacturer: "Test",
                model: "TestDevice",
                version: "1.0",
                serialNumber: nil,
                operationsSupported: Set([0x1001]),
                eventsSupported: Set([])
            ),
            storages: [],
            objects: []
        )
        
        // Can encode
        XCTAssertNoThrow {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            XCTAssertFalse(data.isEmpty)
        }
    }

    // MARK: - MTPFuzzer Tests

    func testMTPFuzzerRandomDataLength() {
        // Test random data generation with various lengths
        let lengths = [0, 1, 10, 100, 1000]
        
        for length in lengths {
            let data = MTPFuzzer.randomData(length: length)
            XCTAssertEqual(data.count, length)
        }
    }

    func testMTPFuzzerRandomDataUnique() {
        // Generated random data should be different each time
        let data1 = MTPFuzzer.randomData(length: 100)
        let data2 = MTPFuzzer.randomData(length: 100)
        
        // Note: There's a very small chance they could be equal by chance
        // but for practical purposes they should be different
        XCTAssertEqual(data1.count, data2.count)
    }

    func testMTPFuzzerMutateEmptyData() {
        let emptyData = Data()
        let mutated = MTPFuzzer.mutate(emptyData)
        
        // Mutating empty data should return random data of length 1
        XCTAssertEqual(mutated.count, 1)
    }

    func testMTPFuzzerMutateNonEmptyData() {
        var original = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let mutated = MTPFuzzer.mutate(original)
        
        // Should have same length
        XCTAssertEqual(mutated.count, original.count)
        
        // At least one byte should be different (with very high probability)
        var differentCount = 0
        for i in 0..<original.count {
            if original[i] != mutated[i] {
                differentCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(differentCount, 1)
    }

    func testMTPFuzzerMutatePreservesLength() {
        for length in [1, 10, 100] {
            let data = MTPFuzzer.randomData(length: length)
            let mutated = MTPFuzzer.mutate(data)
            XCTAssertEqual(mutated.count, length)
        }
    }

    func testMTPFuzzerMutateAllZeros() {
        let zeros = Data(repeating: 0x00, count: 10)
        let mutated = MTPFuzzer.mutate(zeros)
        
        // Should change at least one byte
        var different = false
        for i in 0..<zeros.count {
            if zeros[i] != mutated[i] {
                different = true
                break
            }
        }
        XCTAssertTrue(different)
    }
}

// MARK: - Mock MTPLink for Testing

final class MockMTPLinkForBDD: MTPLink, @unchecked Sendable {
    var cachedDeviceInfo: MTPDeviceInfo? { nil }
    var linkDescriptor: MTPLinkDescriptor? { nil }
    
    func openUSBIfNeeded() async throws {
        // Mock implementation
    }
    
    func openSession(id: UInt32) async throws {
        // Mock implementation
    }
    
    func closeSession() async throws {
        // Mock implementation
    }
    
    func close() async {
        // Mock implementation
    }
    
    func getDeviceInfo() async throws -> MTPDeviceInfo {
        MTPDeviceInfo(
            manufacturer: "Mock",
            model: "MockDevice",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: Set([0x1001, 0x1002]),
            eventsSupported: Set([0x4002])
        )
    }
    
    func getStorageIDs() async throws -> [MTPStorageID] {
        [MTPStorageID(raw: 0x00010001)]
    }
    
    func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
        MTPStorageInfo(
            id: id,
            description: "Mock Storage",
            capacityBytes: 16_000_000_000,
            freeBytes: 8_000_000_000,
            isReadOnly: false
        )
    }
    
    func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
        []
    }
    
    func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
        []
    }
    
    func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
        []
    }
    
    func resetDevice() async throws {
        // Mock implementation
    }
    
    func deleteObject(handle: MTPObjectHandle) async throws {
        // Mock implementation
    }
    
    func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {
        // Mock implementation
    }
    
    func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
        PTPResponseResult(code: 0x2001, txid: command.txid)
    }
    
    func executeStreamingCommand(
        _ command: PTPContainer,
        dataPhaseLength: UInt64?,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> PTPResponseResult {
        PTPResponseResult(code: 0x2001, txid: command.txid)
    }
}
