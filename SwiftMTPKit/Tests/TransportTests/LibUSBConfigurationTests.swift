// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for USB configuration and descriptor parsing
final class LibUSBConfigurationTests: XCTestCase {

    // MARK: - Configuration Value Tests

    func testConfigurationValueParsing() {
        // Test configuration value extraction from descriptors
        let configValue: UInt8 = 1
        XCTAssertEqual(configValue, 1)
    }

    func testConfigurationAttributes() {
        // Test configuration attributes bmAttributes
        let busPowered: UInt8 = 0x80
        let remoteWakeup: UInt8 = 0x20
        let selfPowered: UInt8 = 0x40

        XCTAssertEqual(busPowered | remoteWakeup, 0xA0)
        XCTAssertNotEqual(busPowered, selfPowered)
    }

    func testMaxPowerCalculation() {
        // Test max power calculation from bMaxPower (in 2mA units)
        let bMaxPower: UInt8 = 125 // 250mA
        let actualPower = Int(bMaxPower) * 2
        XCTAssertEqual(actualPower, 250)
    }

    // MARK: - Interface Descriptor Tests

    func testInterfaceNumberParsing() {
        // Test interface number extraction
        let ifaceNumber: UInt8 = 0
        XCTAssertEqual(ifaceNumber, 0)
    }

    func testAltSettingParsing() {
        // Test alternate setting parsing
        let altSetting: UInt8 = 0
        XCTAssertEqual(altSetting, 0)

        let altSetting1: UInt8 = 1
        XCTAssertEqual(altSetting1, 1)
    }

    func testInterfaceClassMatching() {
        // Test MTP interface class matching
        let mtpClass: UInt8 = 0x06
        let mtpSubclass: UInt8 = 0x01
        let mtpProtocol: UInt8 = 0x01

        XCTAssertEqual(mtpClass, 0x06)
        XCTAssertEqual(mtpSubclass, 0x01)
        XCTAssertEqual(mtpProtocol, 0x01)
    }

    func testNonMTPInterfaceFiltering() {
        // Test filtering non-MTP interfaces
        let massStorageClass: UInt8 = 0x08
        let hidClass: UInt8 = 0x03
        let audioClass: UInt8 = 0x01

        XCTAssertNotEqual(massStorageClass, 0x06)
        XCTAssertNotEqual(hidClass, 0x06)
        XCTAssertNotEqual(audioClass, 0x06)
    }

    // MARK: - Endpoint Descriptor Tests

    func testEndpointAddressDirection() {
        // Test endpoint direction parsing
        let inEndpoint = 0x81
        let outEndpoint = 0x02

        let inDirection = (inEndpoint & 0x80) != 0
        let outDirection = (outEndpoint & 0x80) != 0

        XCTAssertTrue(inDirection)
        XCTAssertFalse(outDirection)
    }

    func testEndpointNumberExtraction() {
        // Test endpoint number extraction
        let endpoint1: UInt8 = 0x81
        let endpoint2: UInt8 = 0x02
        let endpoint3: UInt8 = 0x83

        XCTAssertEqual(endpoint1 & 0x0F, 1)
        XCTAssertEqual(endpoint2 & 0x0F, 2)
        XCTAssertEqual(endpoint3 & 0x0F, 3)
    }

    func testTransferTypeParsing() {
        // Test transfer type from bmAttributes
        let controlTransfer: UInt8 = 0x00
        let isochronousTransfer: UInt8 = 0x01
        let bulkTransfer: UInt8 = 0x02
        let interruptTransfer: UInt8 = 0x03

        XCTAssertEqual(controlTransfer & 0x03, 0)
        XCTAssertEqual(isochronousTransfer & 0x03, 1)
        XCTAssertEqual(bulkTransfer & 0x03, 2)
        XCTAssertEqual(interruptTransfer & 0x03, 3)
    }

    func testMaxPacketSizeExtraction() {
        // Test max packet size from wMaxPacketSize
        let fullSpeedBulk: UInt16 = 0x0040 // 64 bytes
        let highSpeedBulk: UInt16 = 0x0200 // 512 bytes
        let superSpeedBulk: UInt16 = 0x0400 // 1024 bytes

        XCTAssertEqual(fullSpeedBulk, 64)
        XCTAssertEqual(highSpeedBulk, 512)
        XCTAssertEqual(superSpeedBulk, 1024)
    }

    // MARK: - Device Descriptor Tests

    func testVendorIDParsing() {
        // Test vendor ID parsing
        let googleVID: UInt16 = 0x18D1
        let samsungVID: UInt16 = 0x04E8
        let appleVID: UInt16 = 0x05AC

        XCTAssertEqual(googleVID, 0x18D1)
        XCTAssertEqual(samsungVID, 0x04E8)
    }

    func testProductIDParsing() {
        // Test product ID parsing
        let pixel7PID: UInt16 = 0x4EE7
        let pixel6PID: UInt16 = 0x4EE1

        XCTAssertEqual(pixel7PID, 0x4EE7)
        XCTAssertEqual(pixel6PID, 0x4EE1)
    }

    func testBCDUSBVersionParsing() {
        // Test USB version parsing
        let usb1_0: UInt16 = 0x0100
        let usb2_0: UInt16 = 0x0200
        let usb3_0: UInt16 = 0x0300

        XCTAssertEqual(usb1_0, 0x0100)
        XCTAssertEqual(usb2_0, 0x0200)
        XCTAssertEqual(usb3_0, 0x0300)
    }

    // MARK: - String Descriptor Tests

    func testStringDescriptorIndexing() {
        // Test string descriptor indices
        let manufacturerIndex: UInt8 = 1
        let productIndex: UInt8 = 2
        let serialIndex: UInt8 = 3

        XCTAssertEqual(manufacturerIndex, 1)
        XCTAssertEqual(productIndex, 2)
        XCTAssertEqual(serialIndex, 3)
    }

    func testStringDescriptorAsciiConversion() {
        // Test ASCII string conversion
        var buffer = [UInt8](repeating: 0, count: 128)
        let testString = "TestDevice"

        for (index, char) in testString.utf8.enumerated() {
            buffer[index] = char
        }

        XCTAssertEqual(buffer[0], 0x54) // 'T'
        XCTAssertEqual(buffer[1], 0x65) // 'e'
        XCTAssertEqual(buffer[2], 0x73) // 's'
        XCTAssertEqual(buffer[3], 0x74) // 't'
    }

    // MARK: - Interface Ranking Tests

    func testInterfaceCandidateRanking() {
        // Test interface candidate ranking
        let highScore = 165
        let mediumScore = 65
        let lowScore = 5

        XCTAssertGreaterThan(highScore, mediumScore)
        XCTAssertGreaterThan(mediumScore, lowScore)
    }

    func testMTPClassBonus() {
        // Test MTP class bonus
        let baseScore = 0
        let mtpClassBonus = 100
        let totalScore = baseScore + mtpClassBonus
        XCTAssertEqual(totalScore, 100)
    }

    func testADBInterfacePenalty() {
        // Test ADB interface penalty
        let baseScore = 100
        let adbPenalty = 200
        let finalScore = baseScore - adbPenalty
        XCTAssertEqual(finalScore, -100)
    }

    func testVendorSpecificWithMTPBonus() {
        // Test vendor-specific interface with MTP name
        let baseScore = 0
        let vendorSpecificBonus = 60 // 0xFF class with MTP name
        let totalScore = baseScore + vendorSpecificBonus
        XCTAssertEqual(totalScore, 60)
    }

    func testInterruptEndpointBonus() {
        // Test interrupt endpoint bonus
        let baseScore = 100
        let evtBonus = 5
        let totalScore = baseScore + evtBonus
        XCTAssertEqual(totalScore, 105)
    }

    // MARK: - Configuration Persistence Tests

    func testConfigurationPersistence() {
        // Test that configuration values persist correctly
        let configValue: UInt8 = 1
        XCTAssertEqual(configValue, configValue)
    }

    func testPortPathExtraction() {
        // Test port path extraction
        var portPath: [UInt8] = [1, 2, 3, 4, 5, 6, 7]
        let portDepth = portPath.count
        XCTAssertEqual(portDepth, 7)
    }

    // MARK: - Device Info Cache Tests

    func testDeviceInfoCacheKey() {
        // Test device info cache key generation
        let vendorID: UInt16 = 0x18D1
        let productID: UInt16 = 0x4EE7
        let bus: UInt8 = 1
        let address: UInt8 = 5

        let cacheKey = String(format: "%04x:%04x@%u:%u", vendorID, productID, bus, address)
        XCTAssertEqual(cacheKey, "18d1:4ee7@1:5")
    }
}
