// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
import SwiftMTPCLI

/// Tests for DeviceFilter.swift CLI module
final class DeviceFilterTests: XCTestCase {

  // MARK: - DeviceFilter Initialization

  func testDeviceFilterAllNil() {
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
  }

  func testDeviceFilterWithVID() {
    let filter = DeviceFilter(vid: 0x1234, pid: nil, bus: nil, address: nil)
    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertNil(filter.pid)
  }

  func testDeviceFilterWithVIDAndPID() {
    let filter = DeviceFilter(vid: 0x1234, pid: 0x5678, bus: nil, address: nil)
    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(filter.pid, 0x5678)
  }

  func testDeviceFilterWithAllFields() {
    let filter = DeviceFilter(vid: 0x1234, pid: 0x5678, bus: 1, address: 2)
    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(filter.pid, 0x5678)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 2)
  }

  // MARK: - DeviceFilterParse Tests

  func testParseEmptyArgs() {
    var args: [String] = []
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
    XCTAssertTrue(args.isEmpty)
  }

  func testParseWithVIDHex() {
    var args = ["--vid", "0x1234", "other"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(args, ["other"])
  }

  func testParseWithVIDHexUppercase() {
    var args = ["--vid", "0XABCD", "other"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0xABCD)
  }

  func testParseWithVIDDecimal() {
    var args = ["--vid", "4660"]  // 4660 = 0x1234
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x4660)
  }

  func testParseWithPIDHex() {
    var args = ["--pid", "0x5678"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.pid, 0x5678)
  }

  func testParseWithPIDDecimal() {
    var args = ["--pid", "22136"]  // 22136 = 0x5678
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.pid, 0x5678)
  }

  func testParseWithCommonUnprefixedHexVID() {
    var args = ["--vid", "2717"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x2717)
  }

  func testParseUSBIdentifierHelper() {
    XCTAssertEqual(parseUSBIdentifier("0x2717"), 0x2717)
    XCTAssertEqual(parseUSBIdentifier("ff40"), 0xff40)
    XCTAssertEqual(parseUSBIdentifier("2717"), 0x2717)
    XCTAssertEqual(parseUSBIdentifier("22136"), 0x5678)
    XCTAssertNil(parseUSBIdentifier("not-a-number"))
  }

  func testParseWithBus() {
    var args = ["--bus", "1"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.bus, 1)
  }

  func testParseWithAddress() {
    var args = ["--address", "2"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.address, 2)
  }

  func testParseWithAllFilters() {
    var args = ["--vid", "0x1234", "--pid", "0x5678", "--bus", "1", "--address", "2"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(filter.pid, 0x5678)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 2)
    XCTAssertTrue(args.isEmpty)
  }

  func testParseWithExtraArgs() {
    var args = ["--vid", "0x1234", "extra1", "extra2"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(args, ["extra1", "extra2"])
  }

  func testParseIgnoresUnknownFlags() {
    var args = ["--unknown", "value", "--vid", "0x1234"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(args, ["--unknown", "value"])
  }

  func testParseWithMissingValue() {
    var args = ["--vid"]
    let filter = DeviceFilterParse.parse(from: &args)

    // Should not parse vid since there's no value
    XCTAssertNil(filter.vid)
    XCTAssertEqual(args, ["--vid"])
  }

  func testParseWithInvalidVID() {
    var args = ["--vid", "invalid"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertNil(filter.vid)
  }

  func testParseWithInvalidBus() {
    var args = ["--bus", "notanumber"]
    let filter = DeviceFilterParse.parse(from: &args)

    XCTAssertNil(filter.bus)
  }

  // MARK: - selectDevice Tests

  func testSelectDeviceEmptyList() {
    let outcome = selectDevice(
      [MTPDeviceSummary](), filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: false)

    if case .none = outcome {
      // Expected
    } else {
      XCTFail("Expected .none for empty device list")
    }
  }

  func testSelectDeviceSingleDeviceNoFilter() {
    let device = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let outcome = selectDevice(
      [device], filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: false)

    if case .selected(let selected) = outcome {
      XCTAssertEqual(selected.vendorID, 0x1234)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectDeviceMultipleDevicesNoFilter() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5679"),
      manufacturer: "TestCo",
      model: "MTP Device 2",
      vendorID: 0x1234,
      productID: 0x5679,
      bus: 1,
      address: 3
    )

    let outcome = selectDevice(
      [device1, device2], filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: false)

    if case .multiple(let devices) = outcome {
      XCTAssertEqual(devices.count, 2)
    } else {
      XCTFail("Expected .multiple")
    }
  }

  func testSelectDeviceWithVIDFilter() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "Vendor1",
      model: "Device1",
      vendorID: 0x1234,
      productID: 0x5678
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:ABCD:5679"),
      manufacturer: "Vendor2",
      model: "Device2",
      vendorID: 0xABCD,
      productID: 0x5679
    )

    let filter = DeviceFilter(vid: 0x1234, pid: nil, bus: nil, address: nil)
    let outcome = selectDevice([device1, device2], filter: filter, noninteractive: false)

    if case .selected(let selected) = outcome {
      XCTAssertEqual(selected.vendorID, 0x1234)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectDeviceWithPIDFilter() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "TestCo",
      model: "Device1",
      vendorID: 0x1234,
      productID: 0x5678
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:9999"),
      manufacturer: "TestCo",
      model: "Device2",
      vendorID: 0x1234,
      productID: 0x9999
    )

    let filter = DeviceFilter(vid: nil, pid: 0x5678, bus: nil, address: nil)
    let outcome = selectDevice([device1, device2], filter: filter, noninteractive: false)

    if case .selected(let selected) = outcome {
      XCTAssertEqual(selected.productID, 0x5678)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectDeviceWithBusFilter() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@1"),
      manufacturer: "TestCo",
      model: "Device1",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@2"),
      manufacturer: "TestCo",
      model: "Device2",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 2,
      address: 2
    )

    let filter = DeviceFilter(vid: nil, pid: nil, bus: 1, address: nil)
    let outcome = selectDevice([device1, device2], filter: filter, noninteractive: false)

    if case .selected(let selected) = outcome {
      XCTAssertEqual(selected.bus, 1)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectDeviceWithAddressFilter() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@1:2"),
      manufacturer: "TestCo",
      model: "Device1",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@1:3"),
      manufacturer: "TestCo",
      model: "Device2",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 3
    )

    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: 3)
    let outcome = selectDevice([device1, device2], filter: filter, noninteractive: false)

    if case .selected(let selected) = outcome {
      XCTAssertEqual(selected.address, 3)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectDeviceNoMatch() {
    let device = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "TestCo",
      model: "Device",
      vendorID: 0x1234,
      productID: 0x5678
    )

    let filter = DeviceFilter(vid: 0x9999, pid: nil, bus: nil, address: nil)
    let outcome = selectDevice([device], filter: filter, noninteractive: false)

    if case .none = outcome {
      // Expected
    } else {
      XCTFail("Expected .none when no device matches")
    }
  }

  func testSelectDeviceMultipleMatches() {
    let device1 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@1"),
      manufacturer: "TestCo",
      model: "Device1",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1
    )

    let device2 = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678@2"),
      manufacturer: "TestCo",
      model: "Device2",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 2
    )

    // Filter only by vendor, both match
    let filter = DeviceFilter(vid: 0x1234, pid: nil, bus: nil, address: nil)
    let outcome = selectDevice([device1, device2], filter: filter, noninteractive: false)

    if case .multiple(let devices) = outcome {
      XCTAssertEqual(devices.count, 2)
    } else {
      XCTFail("Expected .multiple")
    }
  }

  func testSelectDeviceWithNilBusAndAddress() {
    // Test filtering when device doesn't have bus/address set
    let device = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1234:5678"),
      manufacturer: "TestCo",
      model: "Device",
      vendorID: 0x1234,
      productID: 0x5678
        // bus and address are nil
    )

    // Filter with bus should not match (device.bus is nil, filter.bus is 1)
    let filter = DeviceFilter(vid: nil, pid: nil, bus: 1, address: nil)
    let outcome = selectDevice([device], filter: filter, noninteractive: false)

    if case .none = outcome {
      // Expected - nil bus doesn't match filter bus
    } else {
      XCTFail("Expected .none when device has nil bus and filter has bus")
    }
  }

  func testSelectionOutcomeEnumCases() {
    // Verify we can pattern match on SelectionOutcome
    let device = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: 0x1234,
      productID: 0x5678
    )

    let noneOutcome: SelectionOutcome<MTPDeviceSummary> = .none
    let singleOutcome: SelectionOutcome<MTPDeviceSummary> = .selected(device)
    let multipleOutcome: SelectionOutcome<MTPDeviceSummary> = .multiple([device])

    switch noneOutcome {
    case .none: break
    default: XCTFail("Expected .none")
    }

    switch singleOutcome {
    case .selected(let d): XCTAssertEqual(d.vendorID, 0x1234)
    default: XCTFail("Expected .selected")
    }

    switch multipleOutcome {
    case .multiple(let d): XCTAssertEqual(d.count, 1)
    default: XCTFail("Expected .multiple")
    }
  }
}
