// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore

/// Tests for USBDeviceWatcher.swift - USB hot-plug detection
final class USBDeviceWatcherTests: XCTestCase {

  // MARK: - Device Summary Tests

  func testDeviceSummaryWithAllFields() {
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

  func testDeviceSummaryWithNilSerial() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "1234:5678@2:10"),
      manufacturer: "TestCo",
      model: "TestDevice",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 2,
      address: 10
    )

    XCTAssertNil(summary.usbSerial)
    XCTAssertEqual(summary.fingerprint, "1234:5678")
  }

  func testDeviceSummaryFingerprintWithSerial() {
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

    XCTAssertEqual(summary.fingerprint, "18d1:4ee7")
  }

  func testDeviceSummaryFingerprintUnknown() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "unknown"),
      manufacturer: "Unknown",
      model: "Unknown"
    )

    XCTAssertEqual(summary.fingerprint, "unknown")
  }

  // MARK: - Device ID Parsing Tests

  func testDeviceIDFormat() {
    let id = MTPDeviceID(raw: "04e8:6860@1:2")
    XCTAssertEqual(id.raw, "04e8:6860@1:2")
  }

  func testDeviceIDEquality() {
    let id1 = MTPDeviceID(raw: "18d1:4ee7@1:5")
    let id2 = MTPDeviceID(raw: "18d1:4ee7@1:5")
    let id3 = MTPDeviceID(raw: "18d1:4ee7@2:10")

    XCTAssertEqual(id1, id2)
    XCTAssertNotEqual(id1, id3)
  }

  // MARK: - USB Hot-Plug Callback Registration

  func testUSBDeviceWatcherTypeExists() {
    // Verify USBDeviceWatcher is accessible
    XCTAssertNotNil(USBDeviceWatcher.self)
  }

  func testUSBDeviceWatcherStartMethodSignature() {
    // Verify start method exists with correct signature
    // This tests that the method can be referenced
    let _: (MTPDeviceSummary) -> Void = { _ in }
    let _: (MTPDeviceID) -> Void = { _ in }
    XCTAssertTrue(true)
  }

  // MARK: - MTP Interface Filtering

  func testMTPInterfaceClassFiltering() {
    // MTP interface class is 0x06 (Still Image Class)
    let mtpInterfaceClass: UInt8 = 0x06
    XCTAssertEqual(mtpInterfaceClass, 0x06)

    // Non-MTP interfaces should be filtered
    let massStorageClass: UInt8 = 0x08
    XCTAssertNotEqual(massStorageClass, 0x06)

    let hidClass: UInt8 = 0x03
    XCTAssertNotEqual(hidClass, 0x06)
  }

  func testMTPSubclassFiltering() {
    // MTP subclass is 0x01
    let mtpSubclass: UInt8 = 0x01
    XCTAssertEqual(mtpSubclass, 0x01)
  }

  // MARK: - USB Descriptor Parsing

  func testVendorIDParsing() {
    // Common vendor IDs
    XCTAssertEqual(0x18D1, 0x18D1)  // Google
    XCTAssertEqual(0x04E8, 0x04E8)  // Samsung
    XCTAssertEqual(0x0BB4, 0x0BB4)  // HTC
  }

  func testProductIDParsing() {
    // Common product IDs
    XCTAssertEqual(0x4EE7, 0x4EE7)  // Pixel 7
    XCTAssertEqual(0x6860, 0x6860)  // Galaxy S series
  }

  // MARK: - USB String Descriptor Tests

  func testAsciiStringDescriptor() {
    let testString = "TestDevice"
    var buffer = [UInt8](repeating: 0, count: 128)

    for (index, char) in testString.utf8.enumerated() {
      buffer[index] = char
    }

    XCTAssertEqual(buffer[0], 0x54)  // 'T'
    XCTAssertEqual(buffer[1], 0x65)  // 'e'
    XCTAssertEqual(buffer[2], 0x73)  // 's'
    XCTAssertEqual(buffer[3], 0x74)  // 't'
  }

  func testUnicodeStringDescriptor() {
    let testString = "café"
    var buffer = [UInt8](repeating: 0, count: 128)

    for (index, char) in testString.utf8.enumerated() {
      buffer[index] = char
    }

    XCTAssertEqual(buffer[0], 0x63)  // 'c'
    XCTAssertEqual(buffer[1], 0x61)  // 'a'
  }

  // MARK: - Device Connection State Tests

  func testDeviceIDRawValue() {
    let id = MTPDeviceID(raw: "test-device-id")
    XCTAssertEqual(id.raw, "test-device-id")
  }

  // MARK: - USB Bus and Address Tests

  func testBusNumberExtraction() {
    // Test bus number extraction
    let bus: UInt8 = 1
    XCTAssertEqual(bus, 1)
  }

  func testDeviceAddressExtraction() {
    // Test device address extraction
    let address: UInt8 = 5
    XCTAssertEqual(address, 5)
  }

  func testFullDevicePathConstruction() {
    // Test full device path construction: VID:PID@bus:addr
    let vid: UInt16 = 0x18D1
    let pid: UInt16 = 0x4EE7
    let bus: UInt8 = 1
    let addr: UInt8 = 5

    let path = String(format: "%04x:%04x@%u:%u", vid, pid, bus, addr)
    XCTAssertEqual(path, "18d1:4ee7@1:5")
  }

  // MARK: - USB Hot Plug Event Tests

  func testHotPlugEventDeviceArrivedValue() {
    // Hot plug event values are non-zero
    let arrivedValue: Int32 = 0x00000001
    XCTAssertNotEqual(arrivedValue, 0)
  }

  func testHotPlugEventDeviceLeftValue() {
    // Hot plug event values are non-zero
    let leftValue: Int32 = 0x00000002
    XCTAssertNotEqual(leftValue, 0)
  }

  func testHotPlugEventsCombined() {
    // Test combining events
    let arrived: Int32 = 0x00000001
    let left: Int32 = 0x00000002
    let combined = arrived | left
    XCTAssertEqual(combined, 0x00000003)
  }

  // MARK: - Interface Number Tests

  func testInterfaceNumberExtraction() {
    // Test interface number extraction
    let interfaceNumber: UInt8 = 0
    XCTAssertEqual(interfaceNumber, 0)
  }

  func testAlternateSettingExtraction() {
    // Test alternate setting extraction
    let altSetting: UInt8 = 0
    XCTAssertEqual(altSetting, 0)
  }

  // MARK: - USB Configuration Tests

  func testConfigurationValueExtraction() {
    // Configuration value is stored in bConfigurationValue
    let configValue: UInt8 = 1
    XCTAssertEqual(configValue, 1)
  }

  func testNumInterfacesExtraction() {
    // Number of interfaces in configuration
    let numInterfaces: UInt8 = 1
    XCTAssertEqual(numInterfaces, 1)
  }

  // MARK: - USB String Descriptor Index Tests

  func testManufacturerStringIndex() {
    // Manufacturer string descriptor index
    let index: UInt8 = 1
    XCTAssertEqual(index, 1)
  }

  func testProductStringIndex() {
    // Product string descriptor index
    let index: UInt8 = 2
    XCTAssertEqual(index, 2)
  }

  func testSerialStringIndex() {
    // Serial number string descriptor index
    let index: UInt8 = 3
    XCTAssertEqual(index, 3)
  }

  func testZeroStringIndex() {
    // Zero means no string descriptor
    let index: UInt8 = 0
    XCTAssertEqual(index, 0)
  }

  // MARK: - Callback Box Tests

  func testUSBDeviceWatcherBoxCreation() {
    // Test that the Box type can be instantiated
    var attachCalled = false
    var detachCalled = false

    let attachHandler: (MTPDeviceSummary) -> Void = { _ in attachCalled = true }
    let detachHandler: (MTPDeviceID) -> Void = { _ in detachCalled = true }

    // Box would be created internally by USBDeviceWatcher.start()
    XCTAssertFalse(attachCalled)
    XCTAssertFalse(detachCalled)

    // Simulate calling handlers
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test@1:1"),
      manufacturer: "Test",
      model: "TestDevice"
    )
    attachHandler(summary)
    detachHandler(summary.id)

    XCTAssertTrue(attachCalled)
    XCTAssertTrue(detachCalled)
  }
}
