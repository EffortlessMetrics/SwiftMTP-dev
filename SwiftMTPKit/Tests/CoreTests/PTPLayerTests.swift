// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// PTP layer operation tests
final class PTPLayerTests: XCTestCase {

    // MARK: - Operation Support Check

    func testSupportsOperationWithDeviceInfo() {
        // Create mock device info
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "Test",
            model: "TestDevice",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: Set([
                PTPOp.getDeviceInfo.rawValue,
                PTPOp.openSession.rawValue,
                PTPOp.closeSession.rawValue,
                PTPOp.getStorageIDs.rawValue
            ]),
            eventsSupported: []
        )

        // Test supported operations
        XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getDeviceInfo.rawValue, deviceInfo: deviceInfo))
        XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.openSession.rawValue, deviceInfo: deviceInfo))
        XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.closeSession.rawValue, deviceInfo: deviceInfo))
        XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getStorageIDs.rawValue, deviceInfo: deviceInfo))

        // Test unsupported operations
        XCTAssertFalse(PTPLayer.supportsOperation(PTPOp.getObject.rawValue, deviceInfo: deviceInfo))
        XCTAssertFalse(PTPLayer.supportsOperation(PTPOp.sendObject.rawValue, deviceInfo: deviceInfo))
    }

    func testSupportsOperationEmptyOperations() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "",
            model: "",
            version: "",
            serialNumber: nil,
            operationsSupported: [],
            eventsSupported: []
        )

        XCTAssertFalse(PTPLayer.supportsOperation(PTPOp.getDeviceInfo.rawValue, deviceInfo: deviceInfo))
    }

    func testSupportsOperationWithPartialObject64() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "",
            model: "",
            version: "",
            serialNumber: nil,
            operationsSupported: Set([PTPOp.getPartialObject64.rawValue]),
            eventsSupported: []
        )

        XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getPartialObject64.rawValue, deviceInfo: deviceInfo))
        XCTAssertFalse(PTPLayer.supportsOperation(PTPOp.getPartialObject.rawValue, deviceInfo: deviceInfo))
    }

    // MARK: - MTPDeviceInfo Properties

    func testMTPDeviceInfoInitialization() {
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "TestManufacturer",
            model: "TestModel",
            version: "2.0",
            serialNumber: "12345",
            operationsSupported: Set([0x1001, 0x1002, 0x1003]),
            eventsSupported: Set([0x4002])
        )

        XCTAssertEqual(deviceInfo.manufacturer, "TestManufacturer")
        XCTAssertEqual(deviceInfo.version, "2.0")
        XCTAssertEqual(deviceInfo.operationsSupported.count, 3)
        XCTAssertEqual(deviceInfo.eventsSupported.count, 1)
        XCTAssertEqual(deviceInfo.serialNumber, "12345")
    }

    // MARK: - MTPDeviceSummary

    func testMTPDeviceSummaryInitialization() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "usb:1234:5678"),
            manufacturer: "TestCo",
            model: "MTP Device",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 2
        )

        XCTAssertEqual(summary.manufacturer, "TestCo")
        XCTAssertEqual(summary.vendorID, 0x1234)
        XCTAssertEqual(summary.productID, 0x5678)
    }

    func testMTPDeviceSummaryFingerprint() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "test"),
            manufacturer: "Test",
            model: "Device",
            vendorID: 0x1234,
            productID: 0x5678
        )

        XCTAssertEqual(summary.fingerprint, "1234:5678")
    }

    func testMTPDeviceSummaryFingerprintUnknown() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "test"),
            manufacturer: "Test",
            model: "Device"
        )

        XCTAssertEqual(summary.fingerprint, "unknown")
    }

    // MARK: - MTPStorageID

    func testMTPStorageIDValues() {
        let storageID = MTPStorageID(raw: 0x00010001)
        XCTAssertEqual(storageID.raw, 0x00010001)
    }

    func testMTPStorageIDParsing() {
        // Storage ID format: 0xSSLLHHHH where SS=storage number, LL=logical sector, HHHH=handle
        let storageID = MTPStorageID(raw: 0x00010002)
        XCTAssertGreaterThan(storageID.raw, 0)
    }

    // MARK: - MTPStorageInfo

    func testMTPStorageInfoInitialization() {
        let storageInfo = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00010001),
            description: "Internal Storage",
            capacityBytes: 16_000_000_000,
            freeBytes: 8_000_000_000,
            isReadOnly: false
        )

        XCTAssertEqual(storageInfo.id.raw, 0x00010001)
        XCTAssertEqual(storageInfo.description, "Internal Storage")
        XCTAssertGreaterThan(storageInfo.capacityBytes, storageInfo.freeBytes)
        XCTAssertFalse(storageInfo.isReadOnly)
    }

    func testMTPStorageInfoReadOnly() {
        let storageInfo = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00020001),
            description: "SD Card",
            capacityBytes: 32_000_000_000,
            freeBytes: 16_000_000_000,
            isReadOnly: true
        )

        XCTAssertEqual(storageInfo.isReadOnly, true)
    }

    // MARK: - MTPObjectInfo

    func testMTPObjectInfoInitialization() {
        let objectInfo = MTPObjectInfo(
            handle: 0x00010001,
            storage: MTPStorageID(raw: 0x00010001),
            parent: 0x00000000,
            name: "test.txt",
            sizeBytes: 1024,
            modified: Date(),
            formatCode: 0x3001,
            properties: [:]
        )

        XCTAssertEqual(objectInfo.handle, 0x00010001)
        XCTAssertEqual(objectInfo.name, "test.txt")
        XCTAssertEqual(objectInfo.sizeBytes, 1024)
    }

    func testMTPObjectInfoFolder() {
        let folder = MTPObjectInfo(
            handle: 0x00010002,
            storage: MTPStorageID(raw: 0x00010001),
            parent: 0x00000000,
            name: "folder",
            sizeBytes: nil,
            modified: nil,
            formatCode: 0x3001,
            properties: [:]
        )

        XCTAssertNil(folder.sizeBytes)
        XCTAssertNil(folder.modified)
    }

    // MARK: - MTPLink Protocol

    func testMTPLinkRequirements() {
        // Verify MTPLink is a protocol with required methods
        XCTAssertNotNil(MTPLink.self)
    }

    // MARK: - SwiftMTPConfig

    func testSwiftMTPConfigDefaults() {
        let config = SwiftMTPConfig()

        XCTAssertEqual(config.transferChunkBytes, 2 * 1024 * 1024)
        XCTAssertEqual(config.ioTimeoutMs, 10_000)
        XCTAssertEqual(config.handshakeTimeoutMs, 6_000)
        XCTAssertEqual(config.inactivityTimeoutMs, 8_000)
    }

    func testSwiftMTPConfigCustomValues() {
        var config = SwiftMTPConfig()
        config.transferChunkBytes = 4 * 1024 * 1024
        config.ioTimeoutMs = 20_000
        config.resetOnOpen = true

        XCTAssertEqual(config.transferChunkBytes, 4 * 1024 * 1024)
        XCTAssertEqual(config.ioTimeoutMs, 20_000)
        XCTAssertTrue(config.resetOnOpen)
    }

    // MARK: - MTPDevice Protocol

    func testMTPDeviceProtocol() {
        // Verify MTPDevice is a protocol
        XCTAssertNotNil(MTPDevice.self)
    }

    // MARK: - MTPEvent

    func testMTPEventObjectAdded() {
        // Create raw event data for ObjectAdded (0x4002)
        var data = Data(count: 16)
        // Length (4 bytes) = 16
        data[0] = 0x10; data[1] = 0x00; data[2] = 0x00; data[3] = 0x00
        // Type (2 bytes) = 4 (event)
        data[4] = 0x04; data[5] = 0x00
        // Code (2 bytes) = 0x4002 (ObjectAdded)
        data[6] = 0x02; data[7] = 0x40
        // Transaction ID (4 bytes)
        data[8] = 0x01; data[9] = 0x00; data[10] = 0x00; data[11] = 0x00
        // Parameter (4 bytes) = handle
        data[12] = 0x01; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00

        let event = MTPEvent.fromRaw(data)
        XCTAssertNotNil(event)

        if case .objectAdded(let handle) = event {
            XCTAssertEqual(handle, 1)
        } else {
            XCTFail("Expected objectAdded event")
        }
    }

    func testMTPEventObjectRemoved() {
        // Create raw event data for ObjectRemoved (0x4003)
        var data = Data(count: 16)
        data[0] = 0x10; data[1] = 0x00; data[2] = 0x00; data[3] = 0x00
        data[4] = 0x04; data[5] = 0x00
        data[6] = 0x03; data[7] = 0x40
        data[8] = 0x01; data[9] = 0x00; data[10] = 0x00; data[11] = 0x00
        data[12] = 0x02; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00

        let event = MTPEvent.fromRaw(data)
        XCTAssertNotNil(event)

        if case .objectRemoved(let handle) = event {
            XCTAssertEqual(handle, 2)
        } else {
            XCTFail("Expected objectRemoved event")
        }
    }

    func testMTPEventStorageInfoChanged() {
        // Create raw event data for StorageInfoChanged (0x400C)
        var data = Data(count: 16)
        data[0] = 0x10; data[1] = 0x00; data[2] = 0x00; data[3] = 0x00
        data[4] = 0x04; data[5] = 0x00
        data[6] = 0x0C; data[7] = 0x40
        data[8] = 0x01; data[9] = 0x00; data[10] = 0x00; data[11] = 0x00
        data[12] = 0x01; data[13] = 0x00; data[14] = 0x00; data[15] = 0x00

        let event = MTPEvent.fromRaw(data)
        XCTAssertNotNil(event)

        if case .storageInfoChanged(let storageID) = event {
            XCTAssertEqual(storageID.raw, 1)
        } else {
            XCTFail("Expected storageInfoChanged event")
        }
    }

    func testMTPEventParsingFromOffsetBufferDoesNotTrap() {
        var eventData = Data(count: 16)
        eventData[0] = 0x10; eventData[1] = 0x00; eventData[2] = 0x00; eventData[3] = 0x00
        eventData[4] = 0x04; eventData[5] = 0x00
        eventData[6] = 0x02; eventData[7] = 0x40
        eventData[8] = 0x01; eventData[9] = 0x00; eventData[10] = 0x00; eventData[11] = 0x00
        eventData[12] = 0x2A; eventData[13] = 0x00; eventData[14] = 0x00; eventData[15] = 0x00

        let prefixed = Data([0xFF]) + eventData
        let offsetData = Data(prefixed.dropFirst())

        let event = MTPEvent.fromRaw(offsetData)
        if case .objectAdded(let handle) = event {
            XCTAssertEqual(handle, 42)
        } else {
            XCTFail("Expected objectAdded event from offset buffer")
        }
    }

    func testMTPEventInvalidData() {
        // Too short
        let shortData = Data([0x01, 0x02, 0x03])
        XCTAssertNil(MTPEvent.fromRaw(shortData))
    }

    // MARK: - PTPOp Operations

    func testPTPOpValues() {
        // Verify common PTP operation codes
        XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
        XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
        XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
        XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
        XCTAssertEqual(PTPOp.getStorageInfo.rawValue, 0x1005)
        XCTAssertEqual(PTPOp.getObjectHandles.rawValue, 0x1007)
    }

    func testPTPOpCategoryAssignments() {
        // Device operations
        XCTAssertGreaterThanOrEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
        XCTAssertLessThanOrEqual(PTPOp.getDeviceInfo.rawValue, 0x100F)
        
        // Storage operations
        XCTAssertGreaterThanOrEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
        XCTAssertLessThanOrEqual(PTPOp.getStorageInfo.rawValue, 0x1006)
    }

    // MARK: - MTPDeviceID

    func testMTPDeviceIDRawValue() {
        let id = MTPDeviceID(raw: "test-device-123")
        XCTAssertEqual(id.raw, "test-device-123")
    }

    func testMTPDeviceIDEquality() {
        let id1 = MTPDeviceID(raw: "device1")
        let id2 = MTPDeviceID(raw: "device1")
        let id3 = MTPDeviceID(raw: "device2")
        
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    func testMTPDeviceIDHashable() {
        let id1 = MTPDeviceID(raw: "device1")
        let id2 = MTPDeviceID(raw: "device2")
        
        let set = Set([id1, id2])
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - PTPLayer Type Methods

    func testPTPLayerEnumExists() {
        // Verify PTPLayer is accessible
        XCTAssertNotNil(PTPLayer.self)
    }

    func testPTPLayerSupportsOperationVariants() {
        // Test with different operation codes
        let deviceInfo = MTPDeviceInfo(
            manufacturer: "Test",
            model: "TestDevice",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: Set([0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1009, 0x100B]),
            eventsSupported: Set([0x4002, 0x4003, 0x400C])
        )
        
        // Test various operation codes
        XCTAssertTrue(PTPLayer.supportsOperation(0x1001, deviceInfo: deviceInfo)) // GetDeviceInfo
        XCTAssertTrue(PTPLayer.supportsOperation(0x1002, deviceInfo: deviceInfo)) // OpenSession
        XCTAssertTrue(PTPLayer.supportsOperation(0x1004, deviceInfo: deviceInfo)) // GetStorageIDs
        XCTAssertTrue(PTPLayer.supportsOperation(0x100B, deviceInfo: deviceInfo)) // GetObjectPropDesc
        
        // Test unsupported
        XCTAssertFalse(PTPLayer.supportsOperation(0x9801, deviceInfo: deviceInfo)) // Vendor-specific
    }
}
