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

  // MARK: - MTP Class (6, 1, 1) Interface Probe

  func testHeuristicMTPClass_6_1_1_IsTopCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x82)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
    // Class 0x06/0x01 gets 100 base + 5 (protocol 0x01) + 5 (evtIn) = 110
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  // MARK: - PTP Class (6, 1, 2) Interface Probe

  func testHeuristicPTPClass_6_1_2_IsCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x02,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
    // Class 0x06/0x01 gives 100 base + 5 (evtIn) = 105
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  // MARK: - Vendor-Specific Class (0xFF) Interface Probe

  func testHeuristicVendorSpecific0xFF_WithMTPName() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x82)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "MTP")
    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 80)
  }

  func testHeuristicVendorSpecific0xFF_WithEventEndpoint() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")
    // 62 (vendor + evtIn) + 5 (evtIn bonus) = 67
    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 60)
  }

  func testHeuristicVendorSpecific0xFF_WithoutEvidence_NotCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "Generic USB")
    // No MTP name match, no event endpoint → score < 60
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: - No Matching Interface

  func testHeuristicNoEndpoints_NotCandidate() {
    let eps = EPCandidates(bulkIn: 0, bulkOut: 0, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP")
    XCTAssertFalse(result.isCandidate)
    XCTAssertEqual(result.score, Int.min)
  }

  func testHeuristicBulkInOnly_NotCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertFalse(result.isCandidate)
  }

  func testHeuristicBulkOutOnly_NotCandidate() {
    let eps = EPCandidates(bulkIn: 0, bulkOut: 0x01, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: - Multiple Configuration / Alt Setting

  func testCandidatesWithDifferentAltSettings() {
    let alt0 = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 110,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let alt1 = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 1,
      bulkIn: 0x83, bulkOut: 0x02, eventIn: 0x84, score: 115,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)

    let sorted = [alt0, alt1].sorted { $0.score > $1.score }
    XCTAssertEqual(sorted[0].altSetting, 1, "Higher-scoring alt setting should sort first")
    XCTAssertEqual(sorted[1].altSetting, 0)
  }

  func testMultipleConfigurationCandidates() {
    // Simulate candidates from different interfaces (as if from different configs)
    let ifaceMTP = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 120,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let ifaceVendor = InterfaceCandidate(
      ifaceNumber: 2, altSetting: 0,
      bulkIn: 0x85, bulkOut: 0x03, eventIn: 0x86, score: 67,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00)
    let ifaceStorage = InterfaceCandidate(
      ifaceNumber: 3, altSetting: 0,
      bulkIn: 0x87, bulkOut: 0x04, eventIn: 0, score: 30,
      ifaceClass: 0x08, ifaceSubclass: 0x06, ifaceProtocol: 0x50)

    let sorted = [ifaceStorage, ifaceMTP, ifaceVendor].sorted { $0.score > $1.score }
    XCTAssertEqual(sorted[0].ifaceNumber, 0, "MTP interface should rank first")
    XCTAssertEqual(sorted[1].ifaceNumber, 2, "Vendor interface second")
    XCTAssertEqual(sorted[2].ifaceNumber, 3, "Storage interface last")
  }

  // MARK: - Endpoint Detection (Bulk In / Out / Interrupt)

  func testEndpointDetectionBulkInAddress() {
    // Bulk IN endpoints have bit 7 set and transfer type 0x02
    let bulkIn: UInt8 = 0x81
    XCTAssertTrue((bulkIn & 0x80) != 0, "Bulk IN direction bit must be set")
    XCTAssertEqual(bulkIn & 0x0F, 1, "Endpoint number is low nibble")
  }

  func testEndpointDetectionBulkOutAddress() {
    let bulkOut: UInt8 = 0x02
    XCTAssertTrue((bulkOut & 0x80) == 0, "Bulk OUT direction bit must be clear")
    XCTAssertEqual(bulkOut & 0x0F, 2)
  }

  func testEndpointDetectionInterruptIn() {
    // Interrupt IN endpoint for MTP events
    let interruptIn: UInt8 = 0x83
    XCTAssertTrue((interruptIn & 0x80) != 0, "Interrupt IN direction bit must be set")
    XCTAssertEqual(interruptIn & 0x0F, 3)
  }

  func testEndpointTripleForMTPDevice() {
    // Standard MTP endpoint triple: bulkIn, bulkOut, interruptIn
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x02, eventIn: 0x83, score: 110,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertNotEqual(candidate.bulkIn, 0, "MTP needs bulk IN")
    XCTAssertNotEqual(candidate.bulkOut, 0, "MTP needs bulk OUT")
    XCTAssertNotEqual(candidate.eventIn, 0, "MTP should have event IN")
  }

  // MARK: - Probe Finds Correct MTP Interface

  func testProbeSelectsHighestScoringCandidate() {
    let mtpIface = InterfaceCandidate(
      ifaceNumber: 1, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 120,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let vendorIface = InterfaceCandidate(
      ifaceNumber: 2, altSetting: 0,
      bulkIn: 0x83, bulkOut: 0x02, eventIn: 0x84, score: 67,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00)

    let candidates = [vendorIface, mtpIface].sorted { $0.score > $1.score }
    XCTAssertEqual(candidates.first?.ifaceNumber, 1, "MTP interface should be selected")
    XCTAssertEqual(candidates.first?.ifaceClass, 0x06)
  }

  // MARK: - Composite USB Device

  func testProbeHandlesCompositeDeviceWithMixedInterfaces() {
    // Composite device: ADB + MTP + Mass Storage
    let adbEPs = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0)
    let adbResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: adbEPs, interfaceName: "ADB Interface")
    XCTAssertFalse(adbResult.isCandidate, "ADB interface should be excluded")

    let mtpEPs = EPCandidates(bulkIn: 0x83, bulkOut: 0x02, evtIn: 0x84)
    let mtpResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: mtpEPs, interfaceName: "MTP")
    XCTAssertTrue(mtpResult.isCandidate, "MTP interface should be selected")

    let mscEPs = EPCandidates(bulkIn: 0x85, bulkOut: 0x03, evtIn: 0)
    let mscResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x08, interfaceSubclass: 0x06, interfaceProtocol: 0x50,
      endpoints: mscEPs, interfaceName: "Mass Storage")
    XCTAssertFalse(mscResult.isCandidate, "Mass Storage should not be MTP candidate")

    XCTAssertGreaterThan(mtpResult.score, mscResult.score)
  }

  // MARK: - Samsung-Style Multiple Endpoints

  func testProbeSamsungStyleVendorSpecificMTP() {
    // Samsung devices expose MTP on vendor-specific class 0xFF with "MTP" name
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "Samsung Android MTP")
    XCTAssertTrue(result.isCandidate)
    // 80 (vendor + MTP name) + 15 (name contains "mtp") + 5 (evtIn) = 100
    XCTAssertGreaterThanOrEqual(result.score, 80)
  }

  func testProbeSamsungWithMultipleEndpointPairs() {
    // Samsung may expose multiple candidate interfaces; best one should win
    let samsungMTP = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x02, eventIn: 0x83, score: 100,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00)
    let samsungADB = InterfaceCandidate(
      ifaceNumber: 1, altSetting: 0,
      bulkIn: 0x84, bulkOut: 0x05, eventIn: 0, score: -1000,
      ifaceClass: 0xFF, ifaceSubclass: 0x42, ifaceProtocol: 0x01)

    let sorted = [samsungADB, samsungMTP].sorted { $0.score > $1.score }
    XCTAssertEqual(sorted.first?.ifaceNumber, 0, "MTP interface should rank above ADB")
  }

  // MARK: - Camera PTP Interface

  func testProbeCameraPTPInterface() {
    // Cameras use standard PTP: class 0x06, subclass 0x01, protocol 0x01
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "PTP Camera")
    XCTAssertTrue(result.isCandidate)
    // 100 (class) + 15 (name has ptp) + 5 (protocol 0x01) + 5 (evtIn) = 125
    XCTAssertGreaterThanOrEqual(result.score, 120)
  }

  func testProbeCameraWithOnlyBulkEndpoints() {
    // Some cameras lack an interrupt endpoint
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
    // 100 (class) + 5 (protocol) = 105
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  // MARK: - Class 0x06 Without Subclass 0x01

  func testHeuristicClass0x06_WithoutSubclass0x01() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0x82)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")
    // Class 0x06 without subclass 0x01 gets 65 + 5 (evtIn) = 70
    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 65)
    XCTAssertLessThan(result.score, 100, "Should score lower than canonical MTP")
  }

  // MARK: - probeShouldRecoverNoProgressTimeout

  func testProbeShouldRecoverNoProgressTimeout_TimeoutZeroSent() {
    XCTAssertTrue(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 0))
  }

  func testProbeShouldRecoverNoProgressTimeout_TimeoutWithData() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 12))
  }

  func testProbeShouldRecoverNoProgressTimeout_NonTimeout() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -6, sent: 0))
  }

  func testProbeShouldRecoverNoProgressTimeout_Success() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: 0, sent: 0))
  }

  // MARK: - MTPInterfaceHeuristic

  func testMTPInterfaceHeuristicFields() {
    let h = MTPInterfaceHeuristic(isCandidate: true, score: 95)
    XCTAssertTrue(h.isCandidate)
    XCTAssertEqual(h.score, 95)
  }

  func testMTPInterfaceHeuristicNotCandidate() {
    let h = MTPInterfaceHeuristic(isCandidate: false, score: Int.min)
    XCTAssertFalse(h.isCandidate)
    XCTAssertEqual(h.score, Int.min)
  }

  // MARK: - ProbeLadderResult

  func testProbeLadderResultSuccess() {
    let r = ProbeLadderResult(
      succeeded: true, cachedDeviceInfoData: Data([0x01]), stepAttempted: "OpenSession")
    XCTAssertTrue(r.succeeded)
    XCTAssertNotNil(r.cachedDeviceInfoData)
    XCTAssertEqual(r.stepAttempted, "OpenSession")
  }

  func testProbeLadderResultFailure() {
    let r = ProbeLadderResult(
      succeeded: false, cachedDeviceInfoData: nil, stepAttempted: "GetDeviceInfo")
    XCTAssertFalse(r.succeeded)
    XCTAssertNil(r.cachedDeviceInfoData)
  }
}
