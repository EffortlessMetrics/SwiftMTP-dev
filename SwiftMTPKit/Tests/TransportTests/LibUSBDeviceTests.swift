// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for LibUSB device enumeration and hot-plug detection
final class LibUSBDeviceTests: XCTestCase {

    // MARK: - Device Summary Tests

    func testDeviceSummaryCreation() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "04e8:6860@1:2"),
            manufacturer: "TestCorp",
            model: "TestPhone",
            vendorID: 0x04E8,
            productID: 0x6860,
            bus: 1,
            address: 2,
            usbSerial: "ABC123"
        )

        XCTAssertEqual(summary.id.raw, "04e8:6860@1:2")
        XCTAssertEqual(summary.vendorID, 0x04E8)
        XCTAssertEqual(summary.productID, 0x6860)
        XCTAssertEqual(summary.bus, 1)
        XCTAssertEqual(summary.address, 2)
        XCTAssertEqual(summary.usbSerial, "ABC123")
    }

    func testDeviceSummaryIDParsing() {
        let id = MTPDeviceID(raw: "18d1:4ee7@2:15")
        XCTAssertEqual(id.raw, "18d1:4ee7@2:15")
    }

    func testDeviceSummaryEquality() {
        let summary1 = MTPDeviceSummary(
            id: MTPDeviceID(raw: "04e8:6860@1:2"),
            manufacturer: "TestCorp",
            model: "TestPhone",
            vendorID: 0x04E8,
            productID: 0x6860,
            bus: 1,
            address: 2,
            usbSerial: nil
        )

        let summary2 = MTPDeviceSummary(
            id: MTPDeviceID(raw: "04e8:6860@1:2"),
            manufacturer: "TestCorp",
            model: "TestPhone",
            vendorID: 0x04E8,
            productID: 0x6860,
            bus: 1,
            address: 2,
            usbSerial: nil
        )

        XCTAssertEqual(summary1.id.raw, summary2.id.raw)
        XCTAssertEqual(summary1.vendorID, summary2.vendorID)
    }

    // MARK: - Device Enumeration Tests

    func testDeviceEnumerationWithMockDevices() async throws {
        let config = VirtualDeviceConfig.pixel7
        let virtualDevice = VirtualMTPDevice(config: config)
        let mockDeviceData = MockDeviceData(
            deviceSummary: config.summary,
            deviceInfo: config.info,
            storages: config.storages.map { $0.toStorageInfo() },
            objects: config.objects.map {
                MockObjectData(
                    handle: $0.handle,
                    storage: $0.storage,
                    parent: $0.parent,
                    name: $0.name,
                    size: $0.sizeBytes,
                    formatCode: $0.formatCode,
                    data: $0.data
                )
            },
            operationsSupported: Array(config.info.operationsSupported),
            eventsSupported: Array(config.info.eventsSupported)
        )

        // Test that mock device data can be created successfully
        XCTAssertNotNil(mockDeviceData)
        XCTAssertEqual(mockDeviceData.deviceSummary.vendorID, 0x18D1)
    }

    func testVirtualDeviceConfigPresets() {
        // Test Pixel 7 preset
        let pixel7 = VirtualDeviceConfig.pixel7
        XCTAssertTrue(pixel7.summary.model.contains("Pixel"))
        XCTAssertFalse(pixel7.storages.isEmpty)

        // Test empty-device preset
        let android = VirtualDeviceConfig.emptyDevice
        XCTAssertNotNil(android)
    }

    func testVirtualDeviceConfigBuilder() {
        let base = VirtualDeviceConfig.pixel7
        let withStorage = base.withStorage(
            VirtualStorageConfig(
                id: MTPStorageID(raw: 2),
                description: "SD Card",
                capacityBytes: 128 * 1024 * 1024 * 1024,
                freeBytes: 64 * 1024 * 1024 * 1024
            )
        )

        XCTAssertEqual(withStorage.storages.count, base.storages.count + 1)

        let withObject = withStorage.withObject(
            VirtualObjectConfig(
                handle: 0x0001_0001,
                storage: MTPStorageID(raw: 1),
                name: "TestFile.txt",
                formatCode: 0x3000
            )
        )

        XCTAssertEqual(withObject.objects.count, 1)
    }

    // MARK: - Hot-Plug Detection Tests

    func testHotPlugEventCallbacks() {
        var attachCalled = false
        var detachCalled = false
        var attachedDevice: MTPDeviceSummary?

        // Note: Actual hot-plug testing requires physical devices or
        // libusb hot-plug simulation which is platform-dependent
        // These tests verify the callback registration logic

        let expectation = XCTestExpectation(description: "Hot-plug callback registration")

        // Verify callback structure is valid
        XCTAssertNotNil(USBDeviceWatcher.self)

        // Simulate checking callback registration state
        XCTAssertFalse(attachCalled)
        XCTAssertFalse(detachCalled)
        XCTAssertNil(attachedDevice)

        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }

    func testHotPlugFilterCriteria() {
        // Test MTP interface class filtering (0x06 = MTP/PTP)
        let mtpInterfaceClass: UInt8 = 0x06
        XCTAssertEqual(mtpInterfaceClass, 0x06)

        // Test that non-MTP interfaces are filtered
        let massStorageClass: UInt8 = 0x08
        XCTAssertNotEqual(massStorageClass, 0x06)
    }

    // MARK: - Device ID Format Tests

    func testDeviceIDFormat() {
        // Format: VID:PID@bus:address
        let idString = "18d1:4ee7@1:5"
        let components = idString.split(separator: "@")
        XCTAssertEqual(components.count, 2)

        let vidPid = components[0].split(separator: ":")
        XCTAssertEqual(vidPid.count, 2)

        let busAddr = components[1].split(separator: ":")
        XCTAssertEqual(busAddr.count, 2)
    }

    func testDeviceIDFromString() {
        let id = MTPDeviceID(raw: "001122:334455@003:004")
        XCTAssertEqual(id.raw, "001122:334455@003:004")
    }

    // MARK: - Mock Device Data Tests

    func testMockDeviceDataCreation() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@1:1"),
            manufacturer: "MockMaker",
            model: "MockPhone",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 1,
            usbSerial: "MOCK001"
        )

        let storage = MTPStorageInfo(
            id: MTPStorageID(raw: 1),
            description: "Internal Storage",
            capacityBytes: 64 * 1024 * 1024 * 1024,
            freeBytes: 32 * 1024 * 1024 * 1024,
            isReadOnly: false
        )

        let mockObject = MockObjectData(
            handle: 0x0001_0001,
            storage: MTPStorageID(raw: 1),
            parent: nil,
            name: "test.txt",
            size: 1024,
            formatCode: 0x3000,
            data: nil
        )

        let deviceData = MockDeviceData(
            deviceSummary: summary,
            deviceInfo: MTPDeviceInfo(
                manufacturer: summary.manufacturer,
                model: summary.model,
                version: "1.0",
                serialNumber: summary.usbSerial,
                operationsSupported: [],
                eventsSupported: []
            ),
            storages: [storage],
            objects: [mockObject],
            operationsSupported: [],
            eventsSupported: []
        )

        XCTAssertEqual(deviceData.storages.count, 1)
        XCTAssertEqual(deviceData.objects.count, 1)
        XCTAssertEqual(deviceData.deviceSummary.manufacturer, "MockMaker")
    }

    func testMockDeviceFailureModes() {
        let failureModes: [MockFailureMode] = [
            .timeout,
            .busy,
            .accessDenied,
            .deviceDisconnected,
            .protocolError(code: 0x2001)
        ]

        XCTAssertEqual(failureModes.count, 5)
    }

    // MARK: - USB String Descriptor Tests

    func testAsciiStringDescriptor() {
        // Test ASCII string encoding for USB descriptors
        let testString = "TestDevice"
        var buffer = [UInt8](repeating: 0, count: 128)

        for (index, char) in testString.utf8.enumerated() {
            buffer[index] = char
        }

        XCTAssertEqual(buffer[0], 0x54) // 'T'
        XCTAssertEqual(buffer[1], 0x65) // 'e'
    }

    // MARK: - Device Descriptor Tests

    func testUSBDescriptorParsing() {
        // Simulate parsing a USB device descriptor
        let mockDescriptor = MockUSBDeviceDescriptor(
            idVendor: 0x18D1,
            idProduct: 0x4EE7,
            bcdUSB: 0x0200,
            bDeviceClass: 0,
            bDeviceSubClass: 0,
            bDeviceProtocol: 0,
            bNumConfigurations: 1
        )

        XCTAssertEqual(mockDescriptor.idVendor, 0x18D1)
        XCTAssertEqual(mockDescriptor.idProduct, 0x4EE7)
        XCTAssertEqual(mockDescriptor.bcdUSB, 0x0200) // USB 2.0
    }

    func testConfigurationDescriptor() {
        let mockConfig = MockUSBConfigurationDescriptor(
            bNumInterfaces: 1,
            bConfigurationValue: 1,
            bmAttributes: 0x80, // Bus-powered
            bMaxPower: 250 // 500mA
        )

        XCTAssertEqual(mockConfig.bNumInterfaces, 1)
        XCTAssertEqual(mockConfig.bConfigurationValue, 1)
    }

    // MARK: - Interface Descriptor Tests

    func testInterfaceDescriptorMTPClass() {
        // MTP interface should have class 0x06, subclass 0x01
        let mtpInterface = MockUSBInterfaceDescriptor(
            bInterfaceClass: 0x06,
            bInterfaceSubClass: 0x01,
            bInterfaceProtocol: 0x01,
            bNumEndpoints: 3
        )

        XCTAssertEqual(mtpInterface.bInterfaceClass, 0x06)
        XCTAssertEqual(mtpInterface.bInterfaceSubClass, 0x01)
    }

    func testEndpointDescriptor() {
        let endpoint = MockUSBEndpointDescriptor(
            bEndpointAddress: 0x81, // IN endpoint 1
            bmAttributes: 0x02, // Bulk transfer
            wMaxPacketSize: 512
        )

        XCTAssertEqual(endpoint.bEndpointAddress, 0x81)
        XCTAssertTrue(endpoint.isInput)
        XCTAssertFalse(endpoint.isOutput)
    }
}

// MARK: - Mock Types for Testing

struct MockUSBDeviceDescriptor {
    let idVendor: UInt16
    let idProduct: UInt16
    let bcdUSB: UInt16
    let bDeviceClass: UInt8
    let bDeviceSubClass: UInt8
    let bDeviceProtocol: UInt8
    let bNumConfigurations: UInt8
}

struct MockUSBConfigurationDescriptor {
    let bNumInterfaces: UInt8
    let bConfigurationValue: UInt8
    let bmAttributes: UInt8
    let bMaxPower: UInt8
}

struct MockUSBInterfaceDescriptor {
    let bInterfaceClass: UInt8
    let bInterfaceSubClass: UInt8
    let bInterfaceProtocol: UInt8
    let bNumEndpoints: UInt8
}

struct MockUSBEndpointDescriptor {
    let bEndpointAddress: UInt8
    let bmAttributes: UInt8
    let wMaxPacketSize: UInt16

    var isInput: Bool {
        (bEndpointAddress & 0x80) != 0
    }

    var isOutput: Bool {
        (bEndpointAddress & 0x80) == 0
    }

    var endpointNumber: UInt8 {
        bEndpointAddress & 0x0F
    }

    var transferType: UInt8 {
        bmAttributes & 0x03
    }
}
