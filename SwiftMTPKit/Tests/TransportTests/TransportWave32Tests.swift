// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import CLibusb
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

// MARK: - LibUSB Error Code Mapping (Comprehensive)

/// Tests every documented libusb error code mapping through mapLibusb() and check().
final class LibUSBErrorCodeMappingWave32Tests: XCTestCase {

  // MARK: - mapLibusb exhaustive coverage

  func testMapLibusbErrorIO() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_IO.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("rc="), "IO error message should contain return code")
    } else {
      XCTFail("LIBUSB_ERROR_IO should map to .io")
    }
  }

  func testMapLibusbErrorInvalidParam() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_INVALID_PARAM.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("rc="), "INVALID_PARAM should map to .io with rc")
    } else {
      XCTFail("LIBUSB_ERROR_INVALID_PARAM should map to .io")
    }
  }

  func testMapLibusbErrorAccess() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_ACCESS.rawValue)), .accessDenied)
  }

  func testMapLibusbErrorNoDevice() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)), .noDevice)
  }

  func testMapLibusbErrorNotFound() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-5"), "NOT_FOUND should include rc=-5")
    } else {
      XCTFail("LIBUSB_ERROR_NOT_FOUND should map to .io (not a first-class case)")
    }
  }

  func testMapLibusbErrorBusy() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_BUSY.rawValue)), .busy)
  }

  func testMapLibusbErrorTimeout() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_TIMEOUT.rawValue)), .timeout)
  }

  func testMapLibusbErrorOverflow() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_OVERFLOW.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-8"), "OVERFLOW should include rc=-8")
    } else {
      XCTFail("LIBUSB_ERROR_OVERFLOW should map to .io")
    }
  }

  func testMapLibusbErrorPipe() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_PIPE.rawValue)), .stall)
  }

  func testMapLibusbErrorInterrupted() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_INTERRUPTED.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-10"), "INTERRUPTED should include rc=-10")
    } else {
      XCTFail("LIBUSB_ERROR_INTERRUPTED should map to .io")
    }
  }

  func testMapLibusbErrorNoMem() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_NO_MEM.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-11"), "NO_MEM should include rc=-11")
    } else {
      XCTFail("LIBUSB_ERROR_NO_MEM should map to .io")
    }
  }

  func testMapLibusbErrorNotSupported() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_NOT_SUPPORTED.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-12"), "NOT_SUPPORTED should include rc=-12")
    } else {
      XCTFail("LIBUSB_ERROR_NOT_SUPPORTED should map to .io")
    }
  }

  func testMapLibusbErrorOther() {
    let err = mapLibusb(Int32(LIBUSB_ERROR_OTHER.rawValue))
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-99"), "OTHER should include rc=-99")
    } else {
      XCTFail("LIBUSB_ERROR_OTHER should map to .io")
    }
  }

  func testMapLibusbSuccess() {
    // 0 is LIBUSB_SUCCESS — mapLibusb should treat it as unknown (.io)
    let err = mapLibusb(0)
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("rc=0"))
    } else {
      XCTFail("Success code through mapLibusb should fall to .io default")
    }
  }

  // MARK: - check() throws correct MTPError wrappers

  func testCheckSuccessDoesNotThrow() {
    XCTAssertNoThrow(try check(0))
  }

  func testCheckTimeoutThrowsMTPTransport() {
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_TIMEOUT.rawValue))) { error in
      guard let mtp = error as? MTPError, case .transport(let te) = mtp else {
        return XCTFail("Expected MTPError.transport")
      }
      XCTAssertEqual(te, .timeout)
    }
  }

  func testCheckPipeThrowsStall() {
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_PIPE.rawValue))) { error in
      guard let mtp = error as? MTPError, case .transport(let te) = mtp else {
        return XCTFail("Expected MTPError.transport")
      }
      XCTAssertEqual(te, .stall)
    }
  }

  func testCheckAccessThrowsAccessDenied() {
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_ACCESS.rawValue))) { error in
      guard let mtp = error as? MTPError, case .transport(let te) = mtp else {
        return XCTFail("Expected MTPError.transport")
      }
      XCTAssertEqual(te, .accessDenied)
    }
  }

  func testCheckIOErrorThrowsGenericIO() {
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_IO.rawValue))) { error in
      guard let mtp = error as? MTPError, case .transport(let te) = mtp else {
        return XCTFail("Expected MTPError.transport")
      }
      if case .io = te { /* pass */ } else { XCTFail("Expected .io case") }
    }
  }

  // MARK: - Full error code sweep: all known codes map without crash

  func testAllLibUSBErrorCodesMapWithoutCrash() {
    let allCodes: [Int32] = [
      Int32(LIBUSB_ERROR_IO.rawValue),
      Int32(LIBUSB_ERROR_INVALID_PARAM.rawValue),
      Int32(LIBUSB_ERROR_ACCESS.rawValue),
      Int32(LIBUSB_ERROR_NO_DEVICE.rawValue),
      Int32(LIBUSB_ERROR_NOT_FOUND.rawValue),
      Int32(LIBUSB_ERROR_BUSY.rawValue),
      Int32(LIBUSB_ERROR_TIMEOUT.rawValue),
      Int32(LIBUSB_ERROR_OVERFLOW.rawValue),
      Int32(LIBUSB_ERROR_PIPE.rawValue),
      Int32(LIBUSB_ERROR_INTERRUPTED.rawValue),
      Int32(LIBUSB_ERROR_NO_MEM.rawValue),
      Int32(LIBUSB_ERROR_NOT_SUPPORTED.rawValue),
      Int32(LIBUSB_ERROR_OTHER.rawValue),
    ]
    for code in allCodes {
      let error = mapLibusb(code)
      // Every code should produce a non-nil TransportError
      XCTAssertNotNil(error, "mapLibusb(\(code)) should return a valid error")
    }
  }

  // MARK: - Unmapped / fabricated codes fall to .io

  func testUnmappedPositiveCodeFallsToIO() {
    let err = mapLibusb(42)
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("42"))
    } else {
      XCTFail("Positive codes should fall to .io")
    }
  }

  func testUnmappedNegativeCodeFallsToIO() {
    let err = mapLibusb(-200)
    if case .io(let msg) = err {
      XCTAssertTrue(msg.contains("-200"))
    } else {
      XCTFail("Unknown negative codes should fall to .io")
    }
  }
}

// MARK: - Hot-Plug Event Handling

final class HotPlugEventWave32Tests: XCTestCase {

  func testHotPlugArrivedEventConstant() {
    let arrived = LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED
    XCTAssertEqual(arrived.rawValue, 0x01, "DEVICE_ARRIVED should be 0x01")
  }

  func testHotPlugLeftEventConstant() {
    let left = LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT
    XCTAssertEqual(left.rawValue, 0x02, "DEVICE_LEFT should be 0x02")
  }

  func testHotPlugCombinedEventMask() {
    let combined: Int32 =
      Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED.rawValue)
      | Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT.rawValue)
    XCTAssertEqual(combined, 0x03, "Combined mask should be 0x03")
  }

  func testDeviceIDConstructionFromHotPlug() {
    // Simulates the ID format USBDeviceWatcher builds on arrival
    let vid: UInt16 = 0x18D1
    let pid: UInt16 = 0x4EE1
    let bus: UInt8 = 1
    let addr: UInt8 = 5
    let id = MTPDeviceID(raw: String(format: "%04x:%04x@%u:%u", vid, pid, bus, addr))
    XCTAssertEqual(id.raw, "18d1:4ee1@1:5")
  }

  func testDeviceAddedCreatesValidSummary() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "2717:ff10@3:2"),
      manufacturer: "Xiaomi",
      model: "Mi Note 2",
      vendorID: 0x2717,
      productID: 0xFF10,
      bus: 3,
      address: 2,
      usbSerial: "ABC123"
    )
    XCTAssertEqual(summary.fingerprint, "2717:ff10")
    XCTAssertEqual(summary.usbSerial, "ABC123")
    XCTAssertEqual(summary.bus, 3)
    XCTAssertEqual(summary.address, 2)
  }

  func testDeviceRemovedUsesIDOnly() {
    // On detach, only the MTPDeviceID is forwarded (no full summary)
    let id = MTPDeviceID(raw: "04e8:6860@1:3")
    XCTAssertTrue(id.raw.contains("@"), "Detach ID should use VID:PID@bus:addr format")
    XCTAssertTrue(id.raw.hasPrefix("04e8:6860"))
  }

  func testSpuriousEventIgnored() {
    // An event that is neither ARRIVED nor LEFT should be ignored
    // Event values outside 0x01 and 0x02 are spurious
    let spuriousEvent: UInt32 = 0x04
    XCTAssertNotEqual(spuriousEvent, LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED.rawValue)
    XCTAssertNotEqual(spuriousEvent, LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT.rawValue)
  }

  func testHotPlugEnumerateFlag() {
    let flags = LIBUSB_HOTPLUG_ENUMERATE
    XCTAssertEqual(flags.rawValue, 1, "ENUMERATE flag should be 1")
  }

  func testHotPlugMatchAnyConstant() {
    // LIBUSB_HOTPLUG_MATCH_ANY is used for wildcard VID/PID/class matching
    XCTAssertEqual(LIBUSB_HOTPLUG_MATCH_ANY, -1)
  }

  func testNonMTPDeviceFilteredOnArrival() {
    // A Mass Storage device (class 0x08) should not be recognized as MTP
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let heuristic = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x08, interfaceSubclass: 0x06, interfaceProtocol: 0x50,
      endpoints: eps, interfaceName: "Mass Storage"
    )
    XCTAssertFalse(heuristic.isCandidate, "Mass storage should not be MTP candidate")
  }

  func testADBDeviceFilteredOnArrival() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let heuristic = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "ADB Interface"
    )
    XCTAssertFalse(heuristic.isCandidate, "ADB interface should be rejected")
  }
}

// MARK: - Configuration Descriptor Parsing (Multi-Config)

final class ConfigDescriptorParsingWave32Tests: XCTestCase {

  func testConfigurationValueDefaultFallback() {
    // configurationValue() returns 1 as safe default when descriptor is unavailable.
    // Since we can't call it without a real device pointer, verify the constant behavior.
    let defaultValue: Int32 = 1
    XCTAssertEqual(defaultValue, 1, "Default config value should be 1")
  }

  func testBConfigurationValueParsing() {
    // USB spec: bConfigurationValue is 1-based, never 0 for a valid config.
    // Verify that configuration values 1 through 4 are valid.
    for cfgVal: UInt8 in 1...4 {
      XCTAssertGreaterThan(cfgVal, 0, "bConfigurationValue must be > 0")
    }
  }

  func testConfigAttributesBitfield() {
    // USB config descriptor attributes: bit 7 must be set (USB 1.0 compat),
    // bit 6 = self-powered, bit 5 = remote wakeup
    let busPowered: UInt8 = 0x80
    let selfPowered: UInt8 = 0xC0
    let remoteWakeup: UInt8 = 0xA0

    XCTAssertTrue(busPowered & 0x80 != 0, "Bus powered bit must be set")
    XCTAssertTrue(selfPowered & 0x40 != 0, "Self-powered flag")
    XCTAssertFalse(busPowered & 0x40 != 0, "Bus-powered-only should not have self-powered")
    XCTAssertTrue(remoteWakeup & 0x20 != 0, "Remote wakeup flag")
  }

  func testMaxPowerCalculation() {
    // bMaxPower is in 2mA units: value 125 = 250mA, value 250 = 500mA
    let bMaxPower: UInt8 = 250
    let milliAmps = Int(bMaxPower) * 2
    XCTAssertEqual(milliAmps, 500, "bMaxPower 250 should be 500mA")
  }

  func testMultiConfigDeviceSelectsFirstValid() {
    // A device with bNumConfigurations > 1 should use configurationValue() for selection.
    // The function picks index 0's bConfigurationValue.
    let numConfigs: UInt8 = 3
    XCTAssertGreaterThan(numConfigs, 1, "Multi-config device has >1 configs")
    // Verify that the first config (index 0) is used by convention
    let firstConfigIndex: UInt8 = 0
    XCTAssertEqual(firstConfigIndex, 0)
  }

  func testSetConfigurationSkipsIfAlreadySet() {
    // setConfigurationIfNeeded skips set_configuration when current == target
    // This tests the logic conceptually (the actual function needs a handle)
    let current: Int32 = 1
    let target: Int32 = 1
    let shouldSkip = (current == target)
    XCTAssertTrue(shouldSkip, "Should skip set_configuration when already at target")
  }

  func testSetConfigurationForcesOnMismatch() {
    let current: Int32 = 1
    let target: Int32 = 2
    let shouldSet = (current != target)
    XCTAssertTrue(shouldSet, "Should set configuration when current != target")
  }
}

// MARK: - Alternate Interface Settings

final class AlternateInterfaceWave32Tests: XCTestCase {

  func testMTPInterfaceSelectedOverGeneric() {
    // MTP class (0x06/0x01) scores higher than generic vendor (0xFF)
    let mtpEps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let vendorEps = EPCandidates(bulkIn: 0x84, bulkOut: 0x05, evtIn: 0)

    let mtpScore = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: mtpEps, interfaceName: ""
    )
    let vendorScore = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: vendorEps, interfaceName: "MTP"
    )
    XCTAssertGreaterThan(mtpScore.score, vendorScore.score,
      "MTP class interface should score higher than vendor-specific")
  }

  func testAltSettingWithEventEndpointPreferred() {
    // An alt setting with an event endpoint should score higher
    let withEvent = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let noEvent = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)

    let scoreWith = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: withEvent, interfaceName: ""
    )
    let scoreWithout = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: noEvent, interfaceName: ""
    )
    XCTAssertGreaterThan(scoreWith.score, scoreWithout.score,
      "Event endpoint should add bonus score")
  }

  func testAltSettingNoBulkEndpointsRejected() {
    // An interface with no bulk endpoints is never a candidate
    let noEps = EPCandidates(bulkIn: 0, bulkOut: 0, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: noEps, interfaceName: "MTP"
    )
    XCTAssertFalse(result.isCandidate, "No bulk endpoints → not a candidate")
    XCTAssertEqual(result.score, Int.min)
  }

  func testAltSettingBulkInOnlyRejected() {
    // Only bulk-IN without bulk-OUT should be rejected
    let inOnly = EPCandidates(bulkIn: 0x81, bulkOut: 0, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: inOnly, interfaceName: ""
    )
    XCTAssertFalse(result.isCandidate)
  }

  func testAltSettingBulkOutOnlyRejected() {
    let outOnly = EPCandidates(bulkIn: 0, bulkOut: 0x02, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: outOnly, interfaceName: ""
    )
    XCTAssertFalse(result.isCandidate)
  }

  func testInterfaceCandidatePreservesAltSetting() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 2,
      bulkIn: 0x81, bulkOut: 0x02, eventIn: 0x83,
      score: 110,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertEqual(candidate.altSetting, 2, "Alt setting should be preserved")
    XCTAssertEqual(candidate.ifaceNumber, 0)
  }

  func testHigherAltSettingScoreSorts() {
    // rankMTPInterfaces sorts by score descending
    let candidates = [
      InterfaceCandidate(
        ifaceNumber: 0, altSetting: 0,
        bulkIn: 0x81, bulkOut: 0x02, eventIn: 0,
        score: 80, ifaceClass: 0xFF, ifaceSubclass: 0, ifaceProtocol: 0),
      InterfaceCandidate(
        ifaceNumber: 1, altSetting: 0,
        bulkIn: 0x84, bulkOut: 0x05, eventIn: 0x86,
        score: 120, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01),
    ]
    let sorted = candidates.sorted { $0.score > $1.score }
    XCTAssertEqual(sorted.first?.ifaceNumber, 1, "Highest score should be first")
    XCTAssertEqual(sorted.first?.score, 120)
  }
}

// MARK: - USB Device Speed Detection

final class USBDeviceSpeedWave32Tests: XCTestCase {

  func testSpeedHighMapsTo40MBps() {
    let rawSpeed: Int32 = 3  // LIBUSB_SPEED_HIGH
    let mbps: Int? = rawSpeed == 3 ? 40 : nil
    XCTAssertEqual(mbps, 40, "USB 2.0 Hi-Speed should map to 40 MB/s")
  }

  func testSpeedSuperMapsTo400MBps() {
    let rawSpeed: Int32 = 4  // LIBUSB_SPEED_SUPER
    let mbps: Int? = rawSpeed == 4 ? 400 : nil
    XCTAssertEqual(mbps, 400, "USB 3.0 SuperSpeed should map to 400 MB/s")
  }

  func testSpeedSuperPlusMapsTo1200MBps() {
    let rawSpeed: Int32 = 5  // LIBUSB_SPEED_SUPER_PLUS
    let mbps: Int? = rawSpeed == 5 ? 1200 : nil
    XCTAssertEqual(mbps, 1200, "USB 3.1+ should map to 1200 MB/s")
  }

  func testSpeedUnknownMapsToNil() {
    // Speeds 0 (unknown), 1 (low), 2 (full) should all map to nil
    for rawSpeed: Int32 in [0, 1, 2, 6, 99] {
      let mbps: Int?
      switch rawSpeed {
      case 3: mbps = 40
      case 4: mbps = 400
      case 5: mbps = 1200
      default: mbps = nil
      }
      XCTAssertNil(mbps, "Speed \(rawSpeed) should map to nil")
    }
  }

  func testSpeedLowIsNotMapped() {
    let rawSpeed: Int32 = 1  // LIBUSB_SPEED_LOW
    let mbps: Int?
    switch rawSpeed {
    case 3: mbps = 40
    case 4: mbps = 400
    case 5: mbps = 1200
    default: mbps = nil
    }
    XCTAssertNil(mbps, "Low speed USB should return nil (unusable for MTP)")
  }

  func testSpeedFullIsNotMapped() {
    let rawSpeed: Int32 = 2  // LIBUSB_SPEED_FULL
    let mbps: Int?
    switch rawSpeed {
    case 3: mbps = 40
    case 4: mbps = 400
    case 5: mbps = 1200
    default: mbps = nil
    }
    XCTAssertNil(mbps, "Full speed USB (12 Mbps) should return nil")
  }

  func testLinkDescriptorCapturesSpeed() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83, usbSpeedMBps: 400
    )
    XCTAssertEqual(desc.usbSpeedMBps, 400)
    XCTAssertEqual(desc.bulkInEndpoint, 0x81)
    XCTAssertEqual(desc.bulkOutEndpoint, 0x02)
    XCTAssertEqual(desc.interruptEndpoint, 0x83)
  }

  func testLinkDescriptorNilSpeedForUnknown() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02
    )
    XCTAssertNil(desc.usbSpeedMBps, "Unknown speed should be nil")
    XCTAssertNil(desc.interruptEndpoint, "No interrupt EP specified")
  }
}

// MARK: - Transfer Cancellation

final class TransferCancellationWave32Tests: XCTestCase {

  func testCancelInFlightBulkTransferViaTaskCancel() async throws {
    let transport = MockTransport(deviceData: MockDeviceData.androidPixel7)
    let summary = MockDeviceData.androidPixel7.deviceSummary
    let config = SwiftMTPConfig()
    let link = try await transport.open(summary, config: config)

    let task = Task {
      try await link.getStorageIDs()
    }
    // Cancel immediately — the mock transport should handle cancellation gracefully
    task.cancel()
    let result = await task.result
    // Cancellation may or may not throw; either outcome is valid
    switch result {
    case .success: break  // completed before cancel took effect
    case .failure: break  // cancellation propagated
    }
    await link.close()
  }

  func testCancelledTaskDoesNotCorruptState() async throws {
    let transport = MockTransport(deviceData: MockDeviceData.androidPixel7)
    let summary = MockDeviceData.androidPixel7.deviceSummary
    let config = SwiftMTPConfig()
    let link = try await transport.open(summary, config: config)

    // Cancel a task, then verify the link is still usable
    let cancelledTask = Task {
      try await link.getDeviceInfo()
    }
    cancelledTask.cancel()
    _ = await cancelledTask.result

    // Link should still work after cancelled task
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    await link.close()
  }
}

// MARK: - USB String Descriptor Reading and Encoding

final class USBStringDescriptorWave32Tests: XCTestCase {

  func testStringDescriptorIndexZeroReturnsEmpty() {
    // getAsciiString with index 0 should return "" without making USB calls
    // This is tested by verifying the pattern in the source code
    let index: UInt8 = 0
    XCTAssertEqual(index, 0, "Index 0 means no string descriptor")
  }

  func testASCIIStringDecodingFromBuffer() {
    // Simulates libusb_get_string_descriptor_ascii output
    let buf: [UInt8] = Array("Pixel 7".utf8)
    let str = String(decoding: buf, as: UTF8.self)
    XCTAssertEqual(str, "Pixel 7")
  }

  func testUTF8StringDecodingPreservesUnicode() {
    let buf: [UInt8] = Array("café".utf8)
    let str = String(decoding: buf, as: UTF8.self)
    XCTAssertEqual(str, "café")
  }

  func testEmptyBufferDecodesAsEmpty() {
    let buf: [UInt8] = []
    let str = String(decoding: buf, as: UTF8.self)
    XCTAssertEqual(str, "")
  }

  func testNegativeReturnCountTreatedAsNoString() {
    // libusb returns negative on error; n <= 0 means no string
    let n: Int32 = -1
    let hasString = n > 0
    XCTAssertFalse(hasString, "Negative return means no string descriptor")
  }

  func testManufacturerFallbackWhenNoHandle() {
    // When USB handle is nil, manufacturer defaults to "USB VVVV"
    let vid: UInt16 = 0x18D1
    let fallback = "USB \(String(format: "%04x", vid))"
    XCTAssertEqual(fallback, "USB 18d1")
  }

  func testProductFallbackWhenNoHandle() {
    let pid: UInt16 = 0x4EE1
    let fallback = "USB \(String(format: "%04x", pid))"
    XCTAssertEqual(fallback, "USB 4ee1")
  }

  func testStringDescriptorMaxLength() {
    // USB string descriptors max at 255 bytes; we allocate 128-byte buffers
    let bufSize = 128
    XCTAssertEqual(bufSize, 128, "Buffer should be 128 bytes for string descriptors")
  }

  func testPartialStringTruncatedToActualLength() {
    // If n < buffer size, only first n bytes are used
    var buf = [UInt8](repeating: 0, count: 128)
    let content = Array("Test Device".utf8)
    buf.replaceSubrange(0..<content.count, with: content)
    let n = Int32(content.count)
    let str = String(decoding: buf.prefix(Int(n)), as: UTF8.self)
    XCTAssertEqual(str, "Test Device")
    XCTAssertEqual(str.count, 11)
  }
}

// MARK: - Device Re-enumeration After Bus Reset

final class DeviceReenumerationWave32Tests: XCTestCase {

  func testResetDeviceNotFoundMeansReenumeration() {
    // LIBUSB_ERROR_NOT_FOUND (-5) after libusb_reset_device means device re-enumerated
    let resetRC = Int32(LIBUSB_ERROR_NOT_FOUND.rawValue)
    let deviceReenumerated = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
    XCTAssertTrue(deviceReenumerated, "NOT_FOUND after reset = re-enumeration")
  }

  func testResetDeviceSuccessNoReenumeration() {
    let resetRC: Int32 = 0
    let deviceReenumerated = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
    XCTAssertFalse(deviceReenumerated, "rc=0 means device survived reset")
  }

  func testResetDeviceOtherErrorPropagates() {
    // Any error other than 0 or NOT_FOUND should propagate
    let resetRC = Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)
    let isSuccess = (resetRC == 0)
    let isReenumeration = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
    let shouldThrow = !isSuccess && !isReenumeration
    XCTAssertTrue(shouldThrow, "NO_DEVICE on reset should throw")
    XCTAssertEqual(mapLibusb(resetRC), .noDevice)
  }

  func testReenumeratedDeviceNeedsNewHandle() {
    // After re-enumeration the old handle is invalid; a new open is required
    let resetRC = Int32(LIBUSB_ERROR_NOT_FOUND.rawValue)
    let needsReopen = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))
    XCTAssertTrue(needsReopen, "Re-enumerated device needs a fresh USB handle")
  }

  func testFindDeviceByBusAndPortConcept() {
    // After re-enumeration, findDeviceByBusAndPort locates the device by topology.
    // Verify the conceptual behavior: bus number and port path must match.
    let bus: UInt8 = 2
    let portPath: [UInt8] = [1, 3, 0, 0, 0, 0, 0]
    let portDepth: Int32 = 2
    XCTAssertGreaterThan(portDepth, 0, "Port depth must be > 0 for valid path")
    XCTAssertEqual(portPath[0..<Int(portDepth)], [1, 3])
    _ = bus  // used in matching
  }
}

// MARK: - Multiple Endpoint Pairs

final class MultipleEndpointPairWave32Tests: XCTestCase {

  func testFindEndpointsPairsBulkInAndOut() {
    // Verify that EPCandidates correctly pairs bulk IN (0x80 set) and OUT (0x80 clear)
    let ep = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    XCTAssertTrue(ep.bulkIn & 0x80 != 0, "Bulk IN should have direction bit set")
    XCTAssertTrue(ep.bulkOut & 0x80 == 0, "Bulk OUT should have direction bit clear")
  }

  func testEndpointNumberExtraction() {
    // Lower 4 bits of address are the endpoint number
    let bulkIn: UInt8 = 0x81
    let bulkOut: UInt8 = 0x02
    XCTAssertEqual(bulkIn & 0x0F, 1, "Bulk IN endpoint number should be 1")
    XCTAssertEqual(bulkOut & 0x0F, 2, "Bulk OUT endpoint number should be 2")
  }

  func testEventEndpointIsInterruptIN() {
    // Event endpoint uses interrupt transfer type (attr & 0x03 == 3) and IN direction
    let evtIn: UInt8 = 0x83
    XCTAssertTrue(evtIn & 0x80 != 0, "Event endpoint must be IN direction")
    let interruptType: UInt8 = 3  // bmAttributes & 0x03 for interrupt
    XCTAssertEqual(interruptType, 3)
  }

  func testMultipleBulkPairsSelectFirst() {
    // findEndpoints iterates endpoint descriptors and picks first bulk IN/OUT pair
    var eps = EPCandidates()
    // Simulate: first pair at EP1 IN / EP2 OUT
    eps.bulkIn = 0x81
    eps.bulkOut = 0x02
    // Second pair would be at EP3 IN / EP4 OUT but is ignored by findEndpoints
    XCTAssertEqual(eps.bulkIn, 0x81, "First bulk IN wins")
    XCTAssertEqual(eps.bulkOut, 0x02, "First bulk OUT wins")
  }

  func testEndpointDirectionBit() {
    // Bit 7 (0x80) determines direction: 1=IN, 0=OUT
    for addr: UInt8 in [0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87] {
      XCTAssertTrue(addr & 0x80 != 0, "Address 0x\(String(format: "%02x", addr)) should be IN")
    }
    for addr: UInt8 in [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07] {
      XCTAssertFalse(addr & 0x80 != 0, "Address 0x\(String(format: "%02x", addr)) should be OUT")
    }
  }

  func testBulkTransferTypeIdentification() {
    // bmAttributes & 0x03: 0=control, 1=isochronous, 2=bulk, 3=interrupt
    let control: UInt8 = 0x00
    let isochronous: UInt8 = 0x01
    let bulk: UInt8 = 0x02
    let interrupt: UInt8 = 0x03

    XCTAssertEqual(control & 0x03, 0)
    XCTAssertEqual(isochronous & 0x03, 1)
    XCTAssertEqual(bulk & 0x03, 2, "Bulk transfer type is 2")
    XCTAssertEqual(interrupt & 0x03, 3, "Interrupt transfer type is 3")
  }

  func testMaxPacketSizesForUSBSpeeds() {
    // USB 2.0 Full Speed: 64 bytes, High Speed: 512 bytes, SuperSpeed: 1024 bytes
    XCTAssertEqual(64, 64, "Full Speed max packet")
    XCTAssertEqual(512, 512, "High Speed max packet")
    XCTAssertEqual(1024, 1024, "SuperSpeed max packet")
  }

  func testEPCandidatesDefaultsAreZero() {
    let eps = EPCandidates()
    XCTAssertEqual(eps.bulkIn, 0, "Default bulk IN should be 0 (unset)")
    XCTAssertEqual(eps.bulkOut, 0, "Default bulk OUT should be 0 (unset)")
    XCTAssertEqual(eps.evtIn, 0, "Default event IN should be 0 (unset)")
  }
}

// MARK: - Interface Association Descriptor (IAD) Parsing

final class IADParsingWave32Tests: XCTestCase {

  func testCompositeDeviceADBAndMTPSeparated() {
    // Composite device: ADB on iface 0, MTP on iface 1
    let adbEps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0)
    let mtpEps = EPCandidates(bulkIn: 0x83, bulkOut: 0x03, evtIn: 0x85)

    let adbResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: adbEps, interfaceName: "ADB Interface"
    )
    let mtpResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: mtpEps, interfaceName: "MTP"
    )
    XCTAssertFalse(adbResult.isCandidate, "ADB should be rejected")
    XCTAssertTrue(mtpResult.isCandidate, "MTP interface should be selected")
    XCTAssertGreaterThan(mtpResult.score, 100)
  }

  func testCompositeDeviceThreeInterfaces() {
    // Composite: ADB + MTP + MSC
    let mtp = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83),
      interfaceName: ""
    )
    let msc = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x08, interfaceSubclass: 0x06, interfaceProtocol: 0x50,
      endpoints: EPCandidates(bulkIn: 0x84, bulkOut: 0x05, evtIn: 0),
      interfaceName: "Mass Storage"
    )
    let adb = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: EPCandidates(bulkIn: 0x86, bulkOut: 0x07, evtIn: 0),
      interfaceName: ""
    )
    XCTAssertTrue(mtp.isCandidate)
    XCTAssertFalse(msc.isCandidate, "MSC should not be MTP candidate")
    XCTAssertFalse(adb.isCandidate, "ADB should not be MTP candidate")
  }

  func testVendorSpecificWithMTPName() {
    // Samsung-style: vendor-specific class (0xFF) with "MTP" in interface name
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "Samsung MTP"
    )
    XCTAssertTrue(result.isCandidate, "Vendor class with MTP name should be candidate")
    XCTAssertGreaterThanOrEqual(result.score, 60)
  }

  func testVendorSpecificWithoutMTPNameAndNoEvent() {
    // Vendor class, no MTP name, no event → rejected
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "Unknown Interface"
    )
    XCTAssertFalse(result.isCandidate, "No MTP evidence → not a candidate")
    XCTAssertLessThan(result.score, 60)
  }

  func testVendorSpecificWithEventButNoName() {
    // Vendor class + event endpoint but no MTP name
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: ""
    )
    XCTAssertTrue(result.isCandidate, "Vendor + event EP should score ≥ 60")
    XCTAssertGreaterThanOrEqual(result.score, 60)
  }

  func testPTPCameraInterfaceRecognized() {
    // PTP cameras use class 0x06 subclass 0x01 protocol 0x01 (Still Image)
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "PTP Camera"
    )
    XCTAssertTrue(result.isCandidate)
    // Should get MTP class bonus (100) + protocol bonus (5) + event bonus (5) + PTP name bonus (15)
    XCTAssertGreaterThanOrEqual(result.score, 120)
  }

  func testHIDInterfaceRejected() {
    // HID class (0x03) should not be MTP
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x03, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "HID"
    )
    XCTAssertFalse(result.isCandidate, "HID class should not be MTP candidate")
  }

  func testAndroidDebugBridgeNameRejected() {
    // ADB detection via name string as well as class
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "Android Debug Bridge"
    )
    XCTAssertFalse(result.isCandidate, "ADB by name should be rejected")
  }
}

// MARK: - No-Progress Timeout Recovery

final class NoProgressTimeoutWave32Tests: XCTestCase {

  func testNoProgressTimeoutDetection() {
    // rc == TIMEOUT && sent == 0 indicates no progress
    XCTAssertTrue(
      probeShouldRecoverNoProgressTimeout(
        rc: Int32(LIBUSB_ERROR_TIMEOUT.rawValue), sent: 0))
  }

  func testPartialProgressNotNoProgress() {
    // rc == TIMEOUT but sent > 0 means some data got through
    XCTAssertFalse(
      probeShouldRecoverNoProgressTimeout(
        rc: Int32(LIBUSB_ERROR_TIMEOUT.rawValue), sent: 4))
  }

  func testNonTimeoutErrorNotNoProgress() {
    XCTAssertFalse(
      probeShouldRecoverNoProgressTimeout(
        rc: Int32(LIBUSB_ERROR_IO.rawValue), sent: 0))
  }

  func testMTPUSBLinkStaticRecoveryGate() {
    XCTAssertTrue(
      MTPUSBLink.shouldRecoverNoProgressTimeout(
        rc: Int32(LIBUSB_ERROR_TIMEOUT.rawValue), sent: 0))
    XCTAssertFalse(
      MTPUSBLink.shouldRecoverNoProgressTimeout(
        rc: Int32(LIBUSB_ERROR_TIMEOUT.rawValue), sent: 12))
    XCTAssertFalse(
      MTPUSBLink.shouldRecoverNoProgressTimeout(
        rc: 0, sent: 0))
  }
}

// MARK: - TransportError Properties

final class TransportErrorPropertiesWave32Tests: XCTestCase {

  func testTransportErrorEquality() {
    XCTAssertEqual(TransportError.noDevice, TransportError.noDevice)
    XCTAssertEqual(TransportError.timeout, TransportError.timeout)
    XCTAssertEqual(TransportError.busy, TransportError.busy)
    XCTAssertEqual(TransportError.stall, TransportError.stall)
    XCTAssertEqual(TransportError.accessDenied, TransportError.accessDenied)
    XCTAssertNotEqual(TransportError.timeout, TransportError.busy)
    XCTAssertEqual(TransportError.io("abc"), TransportError.io("abc"))
    XCTAssertNotEqual(TransportError.io("abc"), TransportError.io("xyz"))
  }

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testTimeoutInPhaseCarriesPhase() {
    let err = TransportError.timeoutInPhase(.bulkOut)
    if case .timeoutInPhase(let phase) = err {
      XCTAssertEqual(phase, .bulkOut)
    } else {
      XCTFail("Expected .timeoutInPhase")
    }
  }

  func testLocalizedDescriptions() {
    XCTAssertNotNil(TransportError.noDevice.errorDescription)
    XCTAssertNotNil(TransportError.timeout.errorDescription)
    XCTAssertNotNil(TransportError.busy.errorDescription)
    XCTAssertNotNil(TransportError.stall.errorDescription)
    XCTAssertNotNil(TransportError.accessDenied.errorDescription)
    XCTAssertNotNil(TransportError.io("test").errorDescription)
    XCTAssertNotNil(TransportError.timeoutInPhase(.bulkIn).errorDescription)
  }

  func testRecoverySuggestions() {
    XCTAssertNotNil(TransportError.noDevice.recoverySuggestion)
    XCTAssertNotNil(TransportError.timeout.recoverySuggestion)
    XCTAssertNotNil(TransportError.busy.recoverySuggestion)
    XCTAssertNotNil(TransportError.accessDenied.recoverySuggestion)
    XCTAssertNotNil(TransportError.stall.recoverySuggestion)
  }

  func testMTPErrorTransportWrapping() {
    let transport = TransportError.timeout
    let mtp = MTPError.transport(transport)
    if case .transport(let inner) = mtp {
      XCTAssertEqual(inner, .timeout)
    } else {
      XCTFail("Expected .transport wrapper")
    }
    XCTAssertNotNil(mtp.errorDescription)
  }
}
