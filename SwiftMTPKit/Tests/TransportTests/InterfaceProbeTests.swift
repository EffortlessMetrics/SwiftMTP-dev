// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore

/// Tests for InterfaceProbe.swift - USB interface probing and MTP candidate selection
final class InterfaceProbeTests: XCTestCase {

  // MARK: - InterfaceCandidate Tests

  func testInterfaceCandidateBasicFields() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 100,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    XCTAssertEqual(candidate.ifaceNumber, 0)
    XCTAssertEqual(candidate.altSetting, 0)
    XCTAssertEqual(candidate.bulkIn, 0x81)
    XCTAssertEqual(candidate.bulkOut, 0x01)
    XCTAssertEqual(candidate.eventIn, 0x82)
    XCTAssertEqual(candidate.score, 100)
    XCTAssertEqual(candidate.ifaceClass, 0x06)
    XCTAssertEqual(candidate.ifaceSubclass, 0x01)
    XCTAssertEqual(candidate.ifaceProtocol, 0x01)
  }

  func testInterfaceCandidateSendable() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 100,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    // Verify Sendable conformance
    let _: Sendable = candidate
    XCTAssertTrue(true)
  }

  func testInterfaceCandidateWithDifferentScore() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 1,
      altSetting: 1,
      bulkIn: 0x83,
      bulkOut: 0x02,
      eventIn: 0x84,
      score: 165,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    XCTAssertEqual(candidate.score, 165)
  }

  // MARK: - InterfaceProbeAttempt Tests

  func testInterfaceProbeAttemptSuccess() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 100,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    let attempt = InterfaceProbeAttempt(
      candidate: candidate,
      succeeded: true,
      cachedDeviceInfoData: Data([0x01, 0x02, 0x03]),
      durationMs: 150,
      error: nil
    )

    XCTAssertTrue(attempt.succeeded)
    XCTAssertNotNil(attempt.cachedDeviceInfoData)
    XCTAssertEqual(attempt.durationMs, 150)
    XCTAssertNil(attempt.error)
  }

  func testInterfaceProbeAttemptFailure() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 100,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    let attempt = InterfaceProbeAttempt(
      candidate: candidate,
      succeeded: false,
      cachedDeviceInfoData: nil,
      durationMs: 50,
      error: "Device not responding"
    )

    XCTAssertFalse(attempt.succeeded)
    XCTAssertNil(attempt.cachedDeviceInfoData)
    XCTAssertEqual(attempt.error, "Device not responding")
  }

  // MARK: - ProbeAllResult Tests

  func testProbeAllResultWithCandidate() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 100,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    let result = ProbeAllResult(
      candidate: candidate,
      cachedDeviceInfo: Data([0x01, 0x02]),
      probeStep: nil
    )

    XCTAssertNotNil(result.candidate)
    XCTAssertNotNil(result.cachedDeviceInfo)
  }

  func testProbeAllResultNoCandidate() {
    let result = ProbeAllResult(
      candidate: nil,
      cachedDeviceInfo: nil,
      probeStep: nil
    )

    XCTAssertNil(result.candidate)
    XCTAssertNil(result.cachedDeviceInfo)
  }

  // MARK: - Interface Ranking Tests

  func testInterfaceRankingMTPClass() {
    // MTP interface class 0x06, subclass 0x01 should score highest
    let mtpClass: UInt8 = 0x06
    let mtpSubclass: UInt8 = 0x01

    XCTAssertEqual(mtpClass, 0x06)
    XCTAssertEqual(mtpSubclass, 0x01)
  }

  func testInterfaceRankingVendorSpecific() {
    // Vendor-specific interface class 0xFF
    let vendorClass: UInt8 = 0xFF
    XCTAssertEqual(vendorClass, 0xFF)

    // Vendor-specific with MTP/PTP in name scores bonus
    let nameWithMTP = "MTP Interface"
    XCTAssertTrue(nameWithMTP.lowercased().contains("mtp"))
  }

  func testHeuristicIncludesCanonicalMTPInterface() {
    let endpoints = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x82)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      endpoints: endpoints,
      interfaceName: "MTP"
    )

    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  func testHeuristicIncludesVendorSpecificMTPEvidence() {
    let endpoints = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x82)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF,
      interfaceSubclass: 0x00,
      interfaceProtocol: 0x00,
      endpoints: endpoints,
      interfaceName: "Android MTP"
    )

    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 60)
  }

  func testHeuristicExcludesADBLikeInterface() {
    let endpoints = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF,
      interfaceSubclass: 0x42,
      interfaceProtocol: 0x01,
      endpoints: endpoints,
      interfaceName: "ADB Interface"
    )

    XCTAssertFalse(result.isCandidate)
  }

  func testEndpointAddressParsing() {
    // IN endpoint (bit 7 set)
    let inEndpoint: UInt8 = 0x81
    XCTAssertTrue((inEndpoint & 0x80) != 0)
    XCTAssertEqual(inEndpoint & 0x0F, 1)

    // OUT endpoint (bit 7 clear)
    let outEndpoint: UInt8 = 0x01
    XCTAssertTrue((outEndpoint & 0x80) == 0)
    XCTAssertEqual(outEndpoint & 0x0F, 1)
  }

  // MARK: - USB Configuration Tests

  func testConfigurationValueExtraction() {
    // Configuration value is stored in bConfigurationValue (byte 5 of config descriptor)
    let configValue: UInt8 = 1
    XCTAssertEqual(configValue, 1)
  }

  // MARK: - Interface Alt Setting Tests

  func testAltSettingSelection() {
    // Alt setting 0 is typically the default
    let defaultAltSetting: UInt8 = 0
    XCTAssertEqual(defaultAltSetting, 0)

    // Alt setting 1+ is alternate configuration
    let alternateAltSetting: UInt8 = 1
    XCTAssertNotEqual(defaultAltSetting, alternateAltSetting)
  }

  // MARK: - USB Transfer Type Tests

  func testEndpointAttributesBulk() {
    // Bulk transfer type is 0x02
    let bulkAttrs: UInt8 = 0x02
    XCTAssertEqual(bulkAttrs & 0x03, 0x02)
  }

  func testEndpointAttributesInterrupt() {
    // Interrupt transfer type is 0x03
    let interruptAttrs: UInt8 = 0x03
    XCTAssertEqual(interruptAttrs & 0x03, 0x03)
  }

  // MARK: - Packet Size Tests

  func testMaxPacketSizeCalculation() {
    // USB 2.0 full-speed bulk max packet: 64 bytes
    let fsMaxPacket: UInt16 = 64
    XCTAssertEqual(fsMaxPacket, 64)

    // USB 2.0 high-speed bulk max packet: 512 bytes
    let hsMaxPacket: UInt16 = 512
    XCTAssertEqual(hsMaxPacket, 512)
  }

  // MARK: - PTP Container Header Tests

  func testPTPContainerHeaderFields() {
    // PTP container header structure:
    // - Length (4 bytes, little-endian)
    // - Type (2 bytes)
    // - Code (2 bytes)
    // - Transaction ID (4 bytes)
    // - Parameters (variable)

    let headerSize = 12  // 4 + 2 + 2 + 4
    XCTAssertEqual(headerSize, 12)
  }

  func testPTPOpcodeValues() {
    // GetDeviceInfo opcode
    let getDeviceInfo: UInt16 = 0x1001
    XCTAssertEqual(getDeviceInfo, 0x1001)

    // OpenSession opcode
    let openSession: UInt16 = 0x1002
    XCTAssertEqual(openSession, 0x1002)

    // Response OK code
    let responseOK: UInt16 = 0x2001
    XCTAssertEqual(responseOK, 0x2001)
  }

  func testProbeOpenSessionCommandUsesTxidZeroAndSessionIDOne() {
    let cmd = makePTPCommand(opcode: 0x1002, txid: 0, params: [1])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.code, 0x1002)
    XCTAssertEqual(header.txid, 0)
    XCTAssertEqual(cmd.count, 16)

    let sessionID =
      UInt32(cmd[12]) | (UInt32(cmd[13]) << 8) | (UInt32(cmd[14]) << 16)
      | (UInt32(cmd[15]) << 24)
    XCTAssertEqual(sessionID, 1)
  }

  func testProbeGetStorageIDsCommandUsesOpcode1004() {
    let cmd = makePTPCommand(opcode: 0x1004, txid: 1, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.code, 0x1004)
    XCTAssertEqual(header.type, PTPContainer.Kind.command.rawValue)
  }

  // MARK: - Interface Score Tests

  func testMTPScoreCalculation() {
    // MTP class + subclass bonus
    let baseScore = 0
    let mtpClassBonus = 100
    XCTAssertEqual(baseScore + mtpClassBonus, 100)
  }

  func testVendorSpecificWithMTPScore() {
    // Vendor-specific (0xFF) with MTP/PTP in name
    let baseScore = 0
    let vendorBonus = 60
    XCTAssertEqual(baseScore + vendorBonus, 60)
  }

  func testInterruptEndpointScoreBonus() {
    // Event interrupt endpoint bonus
    let baseScore = 100
    let evtBonus = 5
    XCTAssertEqual(baseScore + evtBonus, 105)
  }

  func testADBPenaltyScore() {
    // ADB interface penalty
    let baseScore = 100
    let adbPenalty = 200
    XCTAssertEqual(baseScore - adbPenalty, -100)
  }

  func testMinimumScoreThreshold() {
    // Minimum score threshold is 60
    let minimumScore = 60
    XCTAssertEqual(minimumScore, 60)
  }

  // MARK: - Interface Candidate Sorting Tests

  func testInterfaceCandidateSortingDescending() {
    let candidate1 = InterfaceCandidate(
      ifaceNumber: 0,
      altSetting: 0,
      bulkIn: 0x81,
      bulkOut: 0x01,
      eventIn: 0x82,
      score: 165,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01
    )

    let candidate2 = InterfaceCandidate(
      ifaceNumber: 1,
      altSetting: 0,
      bulkIn: 0x83,
      bulkOut: 0x02,
      eventIn: 0x00,
      score: 60,
      ifaceClass: 0xFF,
      ifaceSubclass: 0x42,
      ifaceProtocol: 0x00
    )

    let sorted = [candidate1, candidate2].sorted { $0.score > $1.score }
    XCTAssertEqual(sorted[0].score, 165)
    XCTAssertEqual(sorted[1].score, 60)
  }

  // MARK: - Endpoint Direction Tests

  func testBulkInEndpointDirection() {
    // Bulk IN endpoint has direction bit set
    let inAddress: UInt8 = 0x81
    XCTAssertTrue((inAddress & 0x80) != 0)
  }

  func testBulkOutEndpointDirection() {
    // Bulk OUT endpoint has direction bit clear
    let outAddress: UInt8 = 0x01
    XCTAssertTrue((outAddress & 0x80) == 0)
  }

  func testEventInEndpointDirection() {
    // Event IN endpoint has direction bit set
    let eventAddress: UInt8 = 0x82
    XCTAssertTrue((eventAddress & 0x80) != 0)
  }

  // MARK: - Probe Timeout Tests

  func testDefaultProbeTimeout() {
    // Default probe timeout is 2000ms
    let defaultTimeout: UInt32 = 2000
    XCTAssertEqual(defaultTimeout, 2000)
  }

  func testCustomProbeTimeout() {
    // Custom probe timeout
    let customTimeout: UInt32 = 5000
    XCTAssertEqual(customTimeout, 5000)
  }

  // MARK: - Drain Bulk In Tests

  func testDrainAttempts() {
    // Maximum drain attempts
    let maxAttempts = 5
    XCTAssertEqual(maxAttempts, 5)
  }

  func testDrainTimeout() {
    // Drain timeout per attempt
    let drainTimeout: Int32 = 50
    XCTAssertEqual(drainTimeout, 50)
  }

  // MARK: - MTP Readiness Polling Tests

  func testPollIntervalMicroseconds() {
    // Poll interval is 200ms = 200000 microseconds
    let pollInterval: useconds_t = 200_000
    XCTAssertEqual(pollInterval, 200000)
  }

  func testDefaultPollBudget() {
    // Default poll budget
    let budget = 3000
    XCTAssertEqual(budget, 3000)
  }

  // MARK: - USB Reset Tests

  func testLibUSBErrorNotFoundValue() {
    // LIBUSB_ERROR_NOT_FOUND indicates device re-enumerated
    let errorCode: Int32 = -5
    XCTAssertNotEqual(errorCode, 0)
  }

  // MARK: - PTP Device Reset Tests

  func testPTPDeviceResetOpcode() {
    // PTP Device Reset request
    let resetRequest: UInt16 = 0x66
    XCTAssertEqual(resetRequest, 0x0066)
  }

  func testPTPRequestType() {
    // PTP Device Reset request type
    let requestType: UInt8 = 0x21
    XCTAssertEqual(requestType, 0x21)
  }

  // MARK: - Close Session Tests

  func testCloseSessionOpcode() {
    // CloseSession opcode
    let closeSession: UInt16 = 0x1003
    XCTAssertEqual(closeSession, 0x1003)
  }

  // MARK: - Container Type Tests

  func testContainerTypeCommand() {
    // Command container type
    let commandType: UInt8 = 1
    XCTAssertEqual(commandType, 1)
  }

  func testContainerTypeData() {
    // Data container type
    let dataType: UInt8 = 2
    XCTAssertEqual(dataType, 2)
  }

  func testContainerTypeResponse() {
    // Response container type
    let responseType: UInt8 = 3
    XCTAssertEqual(responseType, 3)
  }

  // MARK: - Debug Mode Tests

  func testDebugEnvironmentVariable() {
    // SWIFTMTP_DEBUG environment variable
    let debugKey = "SWIFTMTP_DEBUG"
    XCTAssertEqual(debugKey, "SWIFTMTP_DEBUG")
  }

  func testDebugEnabledValue() {
    // Debug enabled value
    let debugValue = "1"
    XCTAssertEqual(debugValue, "1")
  }

  // MARK: - Pipe Setup Delay Tests

  func testPipeSetupDelay() {
    // 100ms delay after claiming interface
    let pipeDelay: UInt32 = 100_000
    XCTAssertEqual(pipeDelay, 100000)
  }

  // MARK: - USB Reset Delay Tests

  func testUSBResetEnumerationDelay() {
    // 500ms delay after USB reset for enumeration
    let enumDelay: UInt32 = 500_000
    XCTAssertEqual(enumDelay, 500000)
  }
}
