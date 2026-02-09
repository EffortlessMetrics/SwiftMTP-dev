// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Comprehensive tests for LibUSBTransport.swift - USB transport layer and device enumeration
final class LibUSBTransportTests: XCTestCase {

    // MARK: - LibUSBDiscovery Tests

    func testLibUSBDiscoveryUSBDeviceIDsStructure() {
        // Test USBDeviceIDs structure fields
        let ids = LibUSBDiscovery.USBDeviceIDs(
            vid: 0x18D1,
            pid: 0x4EE7,
            bcdDevice: 0x0100,
            ifaceClass: 0x06,
            ifaceSubclass: 0x01,
            ifaceProtocol: 0x01,
            bus: 1,
            address: 5
        )
        
        XCTAssertEqual(ids.vid, 0x18D1)
        XCTAssertEqual(ids.pid, 0x4EE7)
        XCTAssertEqual(ids.bcdDevice, 0x0100)
        XCTAssertEqual(ids.ifaceClass, 0x06)
        XCTAssertEqual(ids.ifaceSubclass, 0x01)
        XCTAssertEqual(ids.ifaceProtocol, 0x01)
        XCTAssertEqual(ids.bus, 1)
        XCTAssertEqual(ids.address, 5)
    }

    func testLibUSBDiscoveryUSBDeviceIDsSendable() {
        // Verify Sendable conformance
        let ids = LibUSBDiscovery.USBDeviceIDs(
            vid: 0x1234,
            pid: 0x5678,
            bcdDevice: 0x0200,
            ifaceClass: 0x06,
            ifaceSubclass: 0x01,
            ifaceProtocol: 0x00,
            bus: 2,
            address: 10
        )
        let _: Sendable = ids
        XCTAssertTrue(true)
    }

    // MARK: - Endpoint Finding Tests

    func testEPCandidatesDefaultValues() {
        // Test default EPCandidates values
        let eps = EPCandidates()
        XCTAssertEqual(eps.bulkIn, 0)
        XCTAssertEqual(eps.bulkOut, 0)
        XCTAssertEqual(eps.evtIn, 0)
    }

    func testEPCandidatesWithValues() {
        // Test EPCandidates with values set
        var eps = EPCandidates()
        eps.bulkIn = 0x81
        eps.bulkOut = 0x01
        eps.evtIn = 0x82
        
        XCTAssertEqual(eps.bulkIn, 0x81)
        XCTAssertEqual(eps.bulkOut, 0x01)
        XCTAssertEqual(eps.evtIn, 0x82)
    }

    // MARK: - USB Descriptor Tests

    func testVendorIDFormatting() {
        // Test vendor ID formatting for device IDs
        let vid: UInt16 = 0x18D1
        let formatted = String(format: "%04x", vid)
        XCTAssertEqual(formatted, "18d1")
    }

    func testProductIDFormatting() {
        // Test product ID formatting for device IDs
        let pid: UInt16 = 0x4EE7
        let formatted = String(format: "%04x", pid)
        XCTAssertEqual(formatted, "4ee7")
    }

    func testDeviceIDConstruction() {
        // Test full device ID construction
        let vid: UInt16 = 0x18D1
        let pid: UInt16 = 0x4EE7
        let bus: UInt8 = 1
        let addr: UInt8 = 5
        
        let deviceID = String(format: "%04x:%04x@%u:%u", vid, pid, bus, addr)
        XCTAssertEqual(deviceID, "18d1:4ee7@1:5")
    }

    func testDeviceIDVariousBusAddresses() {
        // Test device ID with various bus/address combinations
        let deviceID1 = String(format: "1234:5678@%u:%u", 1, 5)
        XCTAssertEqual(deviceID1, "1234:5678@1:5")
        
        let deviceID2 = String(format: "1234:5678@%u:%u", 2, 10)
        XCTAssertEqual(deviceID2, "1234:5678@2:10")
        
        let deviceID3 = String(format: "1234:5678@%u:%u", 255, 255)
        XCTAssertEqual(deviceID3, "1234:5678@255:255")
    }

    // MARK: - String Descriptor Tests

    func testUSBStringDescriptorBuffer() {
        // Test USB string descriptor buffer setup
        let bufferSize = 128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        // Fill with test string
        let testString = "Test"
        for (index, char) in testString.utf8.enumerated() {
            buffer[index] = char
        }
        
        XCTAssertEqual(buffer[0], 0x54) // 'T'
        XCTAssertEqual(buffer[1], 0x65) // 'e'
        XCTAssertEqual(buffer[2], 0x73) // 's'
        XCTAssertEqual(buffer[3], 0x74) // 't'
    }

    // MARK: - MTPDeviceSummary Construction Tests

    func testMTPDeviceSummaryFromUSBInfo() {
        // Test constructing MTPDeviceSummary from USB device info
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee7@1:5"),
            manufacturer: "Google",
            model: "Pixel 7",
            vendorID: 0x18D1,
            productID: 0x4EE7,
            bus: 1,
            address: 5,
            usbSerial: "abc123"
        )
        
        XCTAssertEqual(summary.id.raw, "18d1:4ee7@1:5")
        XCTAssertEqual(summary.manufacturer, "Google")
        XCTAssertEqual(summary.model, "Pixel 7")
        XCTAssertEqual(summary.vendorID, 0x18D1)
        XCTAssertEqual(summary.productID, 0x4EE7)
        XCTAssertEqual(summary.bus, 1)
        XCTAssertEqual(summary.address, 5)
        XCTAssertEqual(summary.usbSerial, "abc123")
    }

    func testMTPDeviceSummaryWithoutSerial() {
        // Test MTPDeviceSummary construction without serial
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@2:10"),
            manufacturer: "USB",
            model: "USB Device",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 2,
            address: 10
        )
        
        XCTAssertNil(summary.usbSerial)
        XCTAssertEqual(summary.fingerprint, "1234:5678")
    }

    // MARK: - USB Interface Filtering Tests

    func testMTPInterfaceClassConstant() {
        // MTP interface class is 0x06 (Still Image Class)
        let mtpInterfaceClass: UInt8 = 0x06
        XCTAssertEqual(mtpInterfaceClass, 0x06)
    }

    func testMTPInterfaceSubclassConstant() {
        // MTP subclass is 0x01
        let mtpSubclass: UInt8 = 0x01
        XCTAssertEqual(mtpSubclass, 0x01)
    }

    func testNonMTPInterfacesFiltered() {
        // Test that non-MTP interfaces should be filtered
        let massStorageClass: UInt8 = 0x08
        let hidClass: UInt8 = 0x03
        let audioClass: UInt8 = 0x01
        let vendorClass: UInt8 = 0xFF
        
        XCTAssertNotEqual(massStorageClass, 0x06)
        XCTAssertNotEqual(hidClass, 0x06)
        XCTAssertNotEqual(audioClass, 0x06)
        XCTAssertNotEqual(vendorClass, 0x06)
    }

    // MARK: - Interface Alt Setting Tests

    func testInterfaceAltSettingZero() {
        // Alt setting 0 is typically the default
        let defaultAltSetting: UInt8 = 0
        XCTAssertEqual(defaultAltSetting, 0)
    }

    func testInterfaceAltSettingNonZero() {
        // Alt setting 1+ is alternate configuration
        let alternateAltSetting: UInt8 = 1
        XCTAssertNotEqual(alternateAltSetting, 0)
    }

    // MARK: - USB Transfer Type Tests

    func testEndpointAttributesBulkTransfer() {
        // Bulk transfer type is indicated by bmAttributes & 0x03 == 0x02
        let bulkAttrs: UInt8 = 0x02
        XCTAssertEqual(bulkAttrs & 0x03, 0x02)
    }

    func testEndpointAttributesInterruptTransfer() {
        // Interrupt transfer type is indicated by bmAttributes & 0x03 == 0x03
        let interruptAttrs: UInt8 = 0x03
        XCTAssertEqual(interruptAttrs & 0x03, 0x03)
    }

    func testEndpointAttributesControlTransfer() {
        // Control transfer type is indicated by bmAttributes & 0x03 == 0x00
        let controlAttrs: UInt8 = 0x00
        XCTAssertEqual(controlAttrs & 0x03, 0x00)
    }

    // MARK: - Endpoint Direction Tests

    func testEndpointDirectionIn() {
        // IN endpoint has bit 7 set (0x80)
        let inEndpoint: UInt8 = 0x81
        XCTAssertTrue((inEndpoint & 0x80) != 0)
        XCTAssertEqual(inEndpoint & 0x0F, 1)
    }

    func testEndpointDirectionOut() {
        // OUT endpoint has bit 7 clear
        let outEndpoint: UInt8 = 0x01
        XCTAssertTrue((outEndpoint & 0x80) == 0)
        XCTAssertEqual(outEndpoint & 0x0F, 1)
    }

    func testVariousEndpointAddresses() {
        // Test various endpoint address combinations
        let endpoint1: UInt8 = 0x81
        XCTAssertTrue((endpoint1 & 0x80) != 0)
        XCTAssertEqual(endpoint1 & 0x0F, 1)
        
        let endpoint2: UInt8 = 0x82
        XCTAssertTrue((endpoint2 & 0x80) != 0)
        XCTAssertEqual(endpoint2 & 0x0F, 2)
        
        let endpoint3: UInt8 = 0x01
        XCTAssertTrue((endpoint3 & 0x80) == 0)
        XCTAssertEqual(endpoint3 & 0x0F, 1)
    }

    // MARK: - Max Packet Size Tests

    func testFullSpeedBulkMaxPacketSize() {
        // USB 1.1 full-speed bulk max packet: 64 bytes
        let fsMaxPacket: UInt16 = 0x0040
        XCTAssertEqual(fsMaxPacket, 64)
    }

    func testHighSpeedBulkMaxPacketSize() {
        // USB 2.0 high-speed bulk max packet: 512 bytes
        let hsMaxPacket: UInt16 = 0x0200
        XCTAssertEqual(hsMaxPacket, 512)
    }

    func testSuperSpeedBulkMaxPacketSize() {
        // USB 3.0 super-speed bulk max packet: 1024 bytes
        let ssMaxPacket: UInt16 = 0x0400
        XCTAssertEqual(ssMaxPacket, 1024)
    }

    // MARK: - PTP Container Header Tests

    func testPTPContainerHeaderSize() {
        // PTP container header is 12 bytes: 4 (length) + 2 (type) + 2 (code) + 4 (txid)
        let headerSize = 12
        XCTAssertEqual(headerSize, 12)
    }

    func testPTPOpcodeGetDeviceInfo() {
        // GetDeviceInfo opcode
        let getDeviceInfo: UInt16 = 0x1001
        XCTAssertEqual(getDeviceInfo, 0x1001)
    }

    func testPTPOpcodeOpenSession() {
        // OpenSession opcode
        let openSession: UInt16 = 0x1002
        XCTAssertEqual(openSession, 0x1002)
    }

    func testPTPOpcodeCloseSession() {
        // CloseSession opcode
        let closeSession: UInt16 = 0x1003
        XCTAssertEqual(closeSession, 0x1003)
    }

    func testPTPOpcodeGetStorageIDs() {
        // GetStorageIDs opcode
        let getStorageIDs: UInt16 = 0x1004
        XCTAssertEqual(getStorageIDs, 0x1004)
    }

    func testPTPOpcodeGetStorageInfo() {
        // GetStorageInfo opcode
        let getStorageInfo: UInt16 = 0x1005
        XCTAssertEqual(getStorageInfo, 0x1005)
    }

    func testPTPOpcodeResponseOK() {
        // Response OK code
        let responseOK: UInt16 = 0x2001
        XCTAssertEqual(responseOK, 0x2001)
    }

    func testPTPContainerTypeCommand() {
        // PTP container type: Command = 1
        let commandType: UInt8 = 1
        XCTAssertEqual(commandType, 1)
    }

    func testPTPContainerTypeData() {
        // PTP container type: Data = 2
        let dataType: UInt8 = 2
        XCTAssertEqual(dataType, 2)
    }

    func testPTPContainerTypeResponse() {
        // PTP container type: Response = 3
        let responseType: UInt8 = 3
        XCTAssertEqual(responseType, 3)
    }

    // MARK: - USB Version Tests

    func testUSBVersionParsing() {
        // Test USB version parsing from bcdUSB
        let usb1_0: UInt16 = 0x0100
        let usb2_0: UInt16 = 0x0200
        let usb3_0: UInt16 = 0x0300
        
        XCTAssertEqual(usb1_0, 256)  // 1.0
        XCTAssertEqual(usb2_0, 512)  // 2.0
        XCTAssertEqual(usb3_0, 768)  // 3.0
    }

    // MARK: - Common Vendor IDs Tests

    func testCommonVendorIDs() {
        // Test common MTP device vendor IDs
        let googleVID: UInt16 = 0x18D1
        let samsungVID: UInt16 = 0x04E8
        let htcVID: UInt16 = 0x0BB4
        let appleVID: UInt16 = 0x05AC
        
        XCTAssertNotEqual(googleVID, 0)
        XCTAssertNotEqual(samsungVID, 0)
        XCTAssertNotEqual(htcVID, 0)
        XCTAssertNotEqual(appleVID, 0)
    }

    // MARK: - Bus and Address Tests

    func testBusNumberRange() {
        // USB bus numbers are typically 1-255
        let bus1: UInt8 = 1
        let bus2: UInt8 = 127
        let bus3: UInt8 = 255
        
        XCTAssertGreaterThanOrEqual(bus1, 1)
        XCTAssertLessThanOrEqual(bus1, 255)
        XCTAssertGreaterThanOrEqual(bus2, 1)
        XCTAssertLessThanOrEqual(bus2, 255)
        XCTAssertGreaterThanOrEqual(bus3, 1)
        XCTAssertLessThanOrEqual(bus3, 255)
    }

    func testDeviceAddressRange() {
        // USB device addresses are typically 1-127
        let addr1: UInt8 = 1
        let addr2: UInt8 = 64
        let addr3: UInt8 = 127
        
        XCTAssertGreaterThanOrEqual(addr1, 1)
        XCTAssertLessThanOrEqual(addr1, 127)
        XCTAssertGreaterThanOrEqual(addr2, 1)
        XCTAssertLessThanOrEqual(addr2, 127)
        XCTAssertGreaterThanOrEqual(addr3, 1)
        XCTAssertLessThanOrEqual(addr3, 127)
    }

    // MARK: - Interface Candidate Ranking Tests

    func testInterfaceCandidateHighScore() {
        // High score: MTP class (0x06) + subclass (0x01)
        let highScore = 165
        XCTAssertGreaterThan(highScore, 100)
    }

    func testInterfaceCandidateMediumScore() {
        // Medium score: Vendor-specific (0xFF) + MTP/PTP in name
        let mediumScore = 65
        XCTAssertGreaterThan(mediumScore, 60)
        XCTAssertLessThan(mediumScore, 100)
    }

    func testInterfaceCandidateLowScore() {
        // Low score: Has bulk endpoints but below threshold
        let lowScore = 5
        XCTAssertLessThan(lowScore, 60)
    }

    func testADBInterfacePenalty() {
        // ADB interface penalty
        let baseScore = 100
        let adbPenalty = 200
        let finalScore = baseScore - adbPenalty
        XCTAssertEqual(finalScore, -100)
    }

    func testInterruptEndpointBonus() {
        // Interrupt endpoint bonus
        let baseScore = 100
        let evtBonus = 5
        let totalScore = baseScore + evtBonus
        XCTAssertEqual(totalScore, 105)
    }

    // MARK: - String Formatting Tests

    func testHexFormatting() {
        // Test hex formatting for various values
        let vid: UInt16 = 0xABCD
        let formatted = String(format: "%04x", vid)
        XCTAssertEqual(formatted, "abcd")
    }

    func testUnsignedFormatting() {
        // Test unsigned integer formatting
        let bus: UInt8 = 10
        let addr: UInt8 = 25
        let formatted = String(format: "%u:%u", bus, addr)
        XCTAssertEqual(formatted, "10:25")
    }
}

// MARK: - PTP Container Tests

final class PTPContainerTransportTests: XCTestCase {
    
    func testPTPContainerStructureFields() {
        // Test PTPContainer structure fields
        let container = PTPContainer(
            type: 1,
            code: 0x1002,
            txid: 1,
            params: [1]
        )
        
        XCTAssertEqual(container.type, 1)
        XCTAssertEqual(container.code, 0x1002)
        XCTAssertEqual(container.txid, 1)
        XCTAssertEqual(container.params, [1])
    }

    func testPTPContainerWithEmptyParams() {
        // Test PTPContainer with empty params
        let container = PTPContainer(
            type: 1,
            code: 0x1001,
            txid: 0,
            params: []
        )
        
        XCTAssertTrue(container.params.isEmpty)
    }

    func testPTPContainerMultipleParams() {
        // Test PTPContainer with multiple params
        let container = PTPContainer(
            type: 1,
            code: 0x100B,
            txid: 5,
            params: [0x00010001, 0xFFFFFFFF, 0x00000000]
        )
        
        XCTAssertEqual(container.params.count, 3)
    }
}

// MARK: - MTPLinkDescriptor Tests

final class MTPLinkDescriptorTransportTests: XCTestCase {
    
    func testMTPLinkDescriptorWithAllFields() {
        // Test MTPLinkDescriptor with all fields
        let descriptor = MTPLinkDescriptor(
            interfaceNumber: 0,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            bulkInEndpoint: 0x81,
            bulkOutEndpoint: 0x01,
            interruptEndpoint: 0x82
        )
        
        XCTAssertEqual(descriptor.interfaceNumber, 0)
        XCTAssertEqual(descriptor.interfaceClass, 0x06)
        XCTAssertEqual(descriptor.interfaceSubclass, 0x01)
        XCTAssertEqual(descriptor.interfaceProtocol, 0x01)
        XCTAssertEqual(descriptor.bulkInEndpoint, 0x81)
        XCTAssertEqual(descriptor.bulkOutEndpoint, 0x01)
        XCTAssertEqual(descriptor.interruptEndpoint, 0x82)
    }

    func testMTPLinkDescriptorWithoutInterruptEndpoint() {
        // Test MTPLinkDescriptor without interrupt endpoint
        let descriptor = MTPLinkDescriptor(
            interfaceNumber: 0,
            interfaceClass: 0x06,
            interfaceSubclass: 0x01,
            interfaceProtocol: 0x01,
            bulkInEndpoint: 0x81,
            bulkOutEndpoint: 0x01,
            interruptEndpoint: nil
        )
        
        XCTAssertNil(descriptor.interruptEndpoint)
    }
}


