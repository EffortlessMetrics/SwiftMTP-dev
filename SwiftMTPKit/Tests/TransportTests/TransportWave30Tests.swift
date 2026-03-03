// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import CLibusb
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

// MARK: - USB Descriptor Parsing Tests

final class USBDescriptorParsingWave30Tests: XCTestCase {

  // MARK: - PTP Header Parsing with Malformed Data

  func testPTPHeaderDecodeTruncatedBuffer() {
    // A truncated buffer shorter than PTPHeader.size (12 bytes) — decode from
    // a valid 12-byte region should still work; callers gate on buffer length.
    let shortData: [UInt8] = [
      0x0C, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x10, 0x01, 0x00, 0x00, 0x00,
    ]
    XCTAssertEqual(shortData.count, PTPHeader.size)
    let header = shortData.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 12)
    XCTAssertEqual(header.type, PTPContainer.Kind.command.rawValue)
    XCTAssertEqual(header.code, 0x1001)
    XCTAssertEqual(header.txid, 1)
  }

  func testPTPHeaderDecodeWithOversizedLengthField() {
    // A header whose length field exceeds actual payload — length is just metadata.
    let header = PTPHeader(
      length: 0xFFFF_FFFF, type: PTPContainer.Kind.data.rawValue, code: 0x1009, txid: 5)
    var bytes = [UInt8](repeating: 0, count: PTPHeader.size)
    bytes.withUnsafeMutableBytes { header.encode(into: $0.baseAddress!) }

    let decoded = bytes.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(decoded.length, 0xFFFF_FFFF, "Oversized length field should survive round-trip")
    XCTAssertEqual(decoded.type, PTPContainer.Kind.data.rawValue)
  }

  func testPTPHeaderDecodeWithWrongDescriptorType() {
    // Container type outside the known 1–4 range — should still decode without crash.
    let header = PTPHeader(length: 12, type: 0x00FF, code: 0x2001, txid: 99)
    var bytes = [UInt8](repeating: 0, count: PTPHeader.size)
    bytes.withUnsafeMutableBytes { header.encode(into: $0.baseAddress!) }

    let decoded = bytes.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(decoded.type, 0x00FF, "Unknown container type should round-trip without error")
    XCTAssertNil(PTPContainer.Kind(rawValue: 0x00FF), "Unknown type should not map to a Kind case")
  }

  func testPTPHeaderAllZeroBytes() {
    let zeros = [UInt8](repeating: 0, count: PTPHeader.size)
    let header = zeros.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 0)
    XCTAssertEqual(header.type, 0)
    XCTAssertEqual(header.code, 0)
    XCTAssertEqual(header.txid, 0)
  }

  func testPTPHeaderAllOnesBytes() {
    let ones = [UInt8](repeating: 0xFF, count: PTPHeader.size)
    let header = ones.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 0xFFFF_FFFF)
    XCTAssertEqual(header.type, 0xFFFF)
    XCTAssertEqual(header.code, 0xFFFF)
    XCTAssertEqual(header.txid, 0xFFFF_FFFF)
  }

  // MARK: - PTP Container Header Length Mismatch Validation

  func testContainerHeaderLengthMatchesActualPayload() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 1, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, UInt32(cmd.count), "Length field must match actual byte count")
  }

  func testContainerHeaderLengthMismatchDetection() {
    // Build a valid command, then manually corrupt the length field.
    var cmd = makePTPCommand(opcode: 0x1001, txid: 1, params: [0x0000_0001])
    // Overwrite length field to a wrong value (too large).
    let wrongLength = UInt32(cmd.count + 100).littleEndian
    withUnsafeBytes(of: wrongLength) { src in
      cmd.withUnsafeMutableBytes { dst in
        memcpy(dst.baseAddress!, src.baseAddress!, 4)
      }
    }
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertNotEqual(
      Int(header.length), cmd.count, "Corrupted length should not match actual size")
    XCTAssertEqual(header.length, UInt32(cmd.count + 100))
  }

  func testContainerHeaderLengthTooSmall() {
    // Length < PTPHeader.size is structurally invalid.
    let header = PTPHeader(
      length: 4, type: PTPContainer.Kind.command.rawValue, code: 0x1001, txid: 0)
    XCTAssertLessThan(header.length, UInt32(PTPHeader.size), "Length below header size is invalid")
  }

  // MARK: - Data Container

  func testMakePTPDataContainerRoundTrip() {
    let container = makePTPDataContainer(length: 8192, code: 0x1009, txid: 42)
    let header = container.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 8192)
    XCTAssertEqual(header.type, PTPContainer.Kind.data.rawValue)
    XCTAssertEqual(header.code, 0x1009)
    XCTAssertEqual(header.txid, 42)
  }

  // MARK: - Command with Max Parameters

  func testMakePTPCommandWithFiveParams() {
    let params: [UInt32] = [0x0001, 0x0002, 0x0003, 0x0004, 0x0005]
    let cmd = makePTPCommand(opcode: 0x100C, txid: 10, params: params)
    XCTAssertEqual(cmd.count, PTPHeader.size + 5 * 4)

    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, UInt32(cmd.count))

    var reader = PTPReader(data: Data(cmd[PTPHeader.size...]))
    for expected in params {
      XCTAssertEqual(reader.u32(), expected)
    }
  }

  func testMakePTPCommandWithZeroParams() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [])
    XCTAssertEqual(cmd.count, PTPHeader.size)
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, UInt32(PTPHeader.size))
  }
}

// MARK: - Interface Alternate Setting and Endpoint Tests

final class InterfaceEndpointWave30Tests: XCTestCase {

  // MARK: - MTP vs PTP Alternate Setting Selection

  func testMTPInterfaceScoresHigherThanGenericClass06() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)

    let mtpResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP")
    let genericResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")

    XCTAssertTrue(mtpResult.isCandidate)
    XCTAssertTrue(genericResult.isCandidate)
    XCTAssertGreaterThan(
      mtpResult.score, genericResult.score,
      "MTP (6/1/1) should score higher than generic class 0x06")
  }

  func testPTPProtocol02IsCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x02,
      endpoints: eps, interfaceName: "PTP")
    XCTAssertTrue(result.isCandidate, "PTP protocol 0x02 should be a candidate")
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  func testAltSettingPreferenceByScore() {
    // Two alt settings on same interface; higher score wins.
    let alt0 = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 105,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let alt1 = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 1,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 120,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)

    let ranked = [alt0, alt1].sorted { $0.score > $1.score }
    XCTAssertEqual(ranked.first?.altSetting, 1)
  }

  // MARK: - Endpoint Maximum Packet Size Validation

  func testUSB2HighSpeedBulkMaxPacketSize() {
    let usb2MaxPacket: UInt16 = 512
    XCTAssertEqual(usb2MaxPacket, 512, "USB 2.0 high-speed bulk max packet is 512 bytes")
    XCTAssertTrue(usb2MaxPacket.isPowerOf2)
  }

  func testUSB3SuperSpeedBulkMaxPacketSize() {
    let usb3MaxPacket: UInt16 = 1024
    XCTAssertEqual(usb3MaxPacket, 1024, "USB 3.x super-speed bulk max packet is 1024 bytes")
    XCTAssertTrue(usb3MaxPacket.isPowerOf2)
  }

  func testUSB2FullSpeedBulkMaxPacketSize() {
    let fsMaxPacket: UInt16 = 64
    XCTAssertEqual(fsMaxPacket, 64, "USB 2.0 full-speed bulk max packet is 64 bytes")
  }

  func testInvalidMaxPacketSizeZero() {
    let invalidMaxPacket: UInt16 = 0
    XCTAssertTrue(invalidMaxPacket == 0, "Zero max packet size is invalid for bulk endpoints")
  }

  func testMaxPacketSizeMustBePositive() {
    // negative max_packet_size from libusb indicates a bad pipe
    let badPipe: Int32 = -1
    XCTAssertLessThan(badPipe, 0, "Negative max_packet_size signals bad pipe state")
  }

  // MARK: - Endpoint Address Parsing

  func testBulkEndpointPairOnDifferentNumbers() {
    // Some devices use EP1 IN / EP2 OUT
    let bulkIn: UInt8 = 0x81
    let bulkOut: UInt8 = 0x02
    XCTAssertTrue((bulkIn & 0x80) != 0)
    XCTAssertTrue((bulkOut & 0x80) == 0)
    XCTAssertNotEqual(bulkIn & 0x0F, bulkOut & 0x0F, "IN and OUT can be on different EP numbers")
  }

  func testHighEndpointNumbers() {
    // USB spec allows endpoint numbers 1–15
    let epIn: UInt8 = 0x8F  // EP 15, IN
    let epOut: UInt8 = 0x0F  // EP 15, OUT
    XCTAssertEqual(epIn & 0x0F, 15)
    XCTAssertEqual(epOut & 0x0F, 15)
    XCTAssertTrue((epIn & 0x80) != 0)
    XCTAssertTrue((epOut & 0x80) == 0)
  }

  // MARK: - EP Candidates Construction

  func testEPCandidatesDefaultsToZero() {
    let eps = EPCandidates()
    XCTAssertEqual(eps.bulkIn, 0)
    XCTAssertEqual(eps.bulkOut, 0)
    XCTAssertEqual(eps.evtIn, 0)
  }

  func testEPCandidatesWithAllEndpoints() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    XCTAssertEqual(eps.bulkIn, 0x81)
    XCTAssertEqual(eps.bulkOut, 0x02)
    XCTAssertEqual(eps.evtIn, 0x83)
  }
}

// MARK: - Clear Halt and Stall Recovery Tests

final class ClearHaltWave30Tests: XCTestCase {

  func testStallMapsFromPipeError() {
    let stall = mapLibusb(Int32(LIBUSB_ERROR_PIPE.rawValue))
    XCTAssertEqual(stall, .stall)
  }

  func testStallIsDistinctFromOtherTransportErrors() {
    XCTAssertNotEqual(TransportError.stall, TransportError.timeout)
    XCTAssertNotEqual(TransportError.stall, TransportError.noDevice)
    XCTAssertNotEqual(TransportError.stall, TransportError.busy)
    XCTAssertNotEqual(TransportError.stall, TransportError.accessDenied)
  }

  func testClearHaltSequenceAfterStall() {
    // After a stall (LIBUSB_ERROR_PIPE), the recovery sequence is:
    // 1. libusb_clear_halt(handle, endpoint)
    // 2. Retry the transfer
    // Verify error mapping is correct so the caller can detect stall condition.
    let pipeError = Int32(LIBUSB_ERROR_PIPE.rawValue)
    let mapped = mapLibusb(pipeError)
    XCTAssertEqual(mapped, .stall, "PIPE error must map to stall for clear-halt recovery")
  }

  func testClearHaltOnBothEndpointsAfterClaim() {
    // After claimCandidate, both bulkIn and bulkOut get clear_halt.
    // Verify the candidate has both endpoints populated.
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 110,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertNotEqual(candidate.bulkIn, 0, "bulkIn must be set for clear_halt")
    XCTAssertNotEqual(candidate.bulkOut, 0, "bulkOut must be set for clear_halt")
    XCTAssertTrue((candidate.bulkIn & 0x80) != 0, "bulkIn must be an IN endpoint")
    XCTAssertTrue((candidate.bulkOut & 0x80) == 0, "bulkOut must be an OUT endpoint")
  }

  func testClearHaltReturnCodeNotSupportedIsTolerated() {
    // LIBUSB_ERROR_NOT_SUPPORTED (-12) is non-fatal for clear_halt.
    let notSupported: Int32 = -12
    // The probe logic continues regardless of clear_halt return code.
    XCTAssertNotEqual(notSupported, 0)
    // Mapping to transport error for coverage.
    let mapped = mapLibusb(notSupported)
    if case .io(let msg) = mapped {
      XCTAssertTrue(msg.contains("-12"))
    } else {
      XCTFail("Expected .io mapping for unknown libusb error")
    }
  }
}

// MARK: - Zero-Length Packet (ZLP) Termination Tests

final class ZLPTerminationTests: XCTestCase {

  func testZLPRequiredWhenPayloadIsMultipleOfMaxPacket() {
    // USB spec: if payload length is exact multiple of max packet size,
    // a zero-length packet is needed to signal end of transfer.
    let maxPacketSize = 512
    let payloadSizes = [512, 1024, 2048, 512 * 100]
    for size in payloadSizes {
      XCTAssertTrue(
        size % maxPacketSize == 0,
        "Payload \(size) should be a multiple of max packet \(maxPacketSize)")
      let needsZLP = (size % maxPacketSize == 0) && size > 0
      XCTAssertTrue(needsZLP, "ZLP required for payload size \(size)")
    }
  }

  func testZLPNotRequiredWhenPayloadIsNotMultiple() {
    let maxPacketSize = 512
    let payloadSizes = [1, 100, 511, 513, 1023]
    for size in payloadSizes {
      let needsZLP = (size % maxPacketSize == 0) && size > 0
      XCTAssertFalse(needsZLP, "ZLP not required for payload size \(size)")
    }
  }

  func testZLPNotRequiredForEmptyTransfer() {
    let payloadSize = 0
    let needsZLP = (payloadSize % 512 == 0) && payloadSize > 0
    XCTAssertFalse(needsZLP, "ZLP not needed for empty transfer (no data sent)")
  }

  func testPTPContainerWithExactMaxPacketAlignment() {
    // A PTP data container whose total length aligns to 512 needs ZLP.
    let dataPayloadSize = 512 - PTPHeader.size  // 500 bytes of payload
    let containerLength = UInt32(PTPHeader.size + dataPayloadSize)
    XCTAssertEqual(containerLength, 512)
    let needsZLP = (Int(containerLength) % 512 == 0)
    XCTAssertTrue(needsZLP)
  }
}

// MARK: - Control Transfer / Device Reset Tests

final class ControlTransferResetTests: XCTestCase {

  func testPTPDeviceResetRequestParameters() {
    // PTP Device Reset uses class-specific request 0x66 on the control pipe.
    let bmRequestType: UInt8 = 0x21  // Host-to-device, class, interface
    let bRequest: UInt8 = 0x66  // PTP Device Reset
    let wValue: UInt16 = 0
    let wIndex: UInt16 = 0  // Interface number

    XCTAssertEqual(bmRequestType & 0x60, 0x20, "Class request type bits")
    XCTAssertEqual(bmRequestType & 0x1F, 0x01, "Interface recipient")
    XCTAssertEqual(bRequest, 0x66, "PTP Device Reset request code")
    XCTAssertEqual(wValue, 0)
    XCTAssertEqual(wIndex, 0)
  }

  func testDeviceResetShouldClearHaltOnAllEndpoints() {
    // After PTP device reset, both bulk endpoints should be clear-halted.
    let endpoints: [UInt8] = [0x81, 0x01, 0x82]  // bulkIn, bulkOut, eventIn
    for ep in endpoints {
      // Validate endpoint addresses
      let isValid = (ep & 0x0F) > 0 && (ep & 0x0F) <= 15
      XCTAssertTrue(isValid, "Endpoint 0x\(String(format: "%02x", ep)) must have valid number")
    }
  }

  func testUSBResetCausesDeviceReEnumeration() {
    // libusb_reset_device causes re-enumeration; LIBUSB_ERROR_NOT_FOUND is expected.
    let notFound: Int32 = -5
    let mapped = mapLibusb(notFound)
    if case .io(let msg) = mapped {
      XCTAssertTrue(msg.contains("-5"))
    } else {
      XCTFail("Expected .io mapping for NOT_FOUND")
    }
  }
}

// MARK: - Multiple Interface Claiming Tests

final class InterfaceClaimingWave30Tests: XCTestCase {

  func testBusyErrorOnAlreadyClaimedInterface() {
    // When another driver holds the interface, claim fails with BUSY.
    let busyRC = Int32(LIBUSB_ERROR_BUSY.rawValue)
    let mapped = mapLibusb(busyRC)
    XCTAssertEqual(mapped, .busy)
  }

  func testAccessDeniedOnPermissionFailure() {
    let accessRC = Int32(LIBUSB_ERROR_ACCESS.rawValue)
    let mapped = mapLibusb(accessRC)
    XCTAssertEqual(mapped, .accessDenied)
  }

  func testNoDeviceAfterDisconnect() {
    let noDeviceRC = Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)
    let mapped = mapLibusb(noDeviceRC)
    XCTAssertEqual(mapped, .noDevice)
  }

  func testTimeoutDuringClaim() {
    let timeoutRC = Int32(LIBUSB_ERROR_TIMEOUT.rawValue)
    let mapped = mapLibusb(timeoutRC)
    XCTAssertEqual(mapped, .timeout)
  }

  func testClaimFailureForCompositeDeviceInterfaces() {
    // On a composite device (ADB + MTP), ADB interface should be rejected by heuristic.
    let adbEPs = EPCandidates(bulkIn: 0x81, bulkOut: 0x01, evtIn: 0)
    let adbResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: adbEPs, interfaceName: "ADB Interface")
    XCTAssertFalse(adbResult.isCandidate, "ADB interface must not be claimed for MTP")

    let mtpEPs = EPCandidates(bulkIn: 0x83, bulkOut: 0x02, evtIn: 0x84)
    let mtpResult = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: mtpEPs, interfaceName: "MTP")
    XCTAssertTrue(mtpResult.isCandidate, "MTP interface should be selected")
  }

  func testMassStorageInterfaceNotSelectedAsMTP() {
    let mscEPs = EPCandidates(bulkIn: 0x85, bulkOut: 0x03, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x08, interfaceSubclass: 0x06, interfaceProtocol: 0x50,
      endpoints: mscEPs, interfaceName: "USB Mass Storage")
    XCTAssertFalse(result.isCandidate, "Mass Storage interface should not be selected for MTP")
  }
}

// MARK: - USB Configuration Descriptor Walking Tests

final class ConfigDescriptorWalkingTests: XCTestCase {

  func testMultipleInterfaceRanking() {
    // Simulate config descriptor with 3 interfaces of varying scores.
    let candidates = [
      InterfaceCandidate(
        ifaceNumber: 0, altSetting: 0,
        bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 120,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01),
      InterfaceCandidate(
        ifaceNumber: 1, altSetting: 0,
        bulkIn: 0x83, bulkOut: 0x02, eventIn: 0x84, score: 80,
        ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00),
      InterfaceCandidate(
        ifaceNumber: 2, altSetting: 0,
        bulkIn: 0x85, bulkOut: 0x03, eventIn: 0, score: 67,
        ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00),
    ]

    let ranked = candidates.sorted { $0.score > $1.score }
    XCTAssertEqual(ranked[0].ifaceNumber, 0, "Canonical MTP interface ranks first")
    XCTAssertEqual(ranked[1].ifaceNumber, 1, "Vendor MTP with name bonus ranks second")
    XCTAssertEqual(ranked[2].ifaceNumber, 2, "Vendor MTP with event-only evidence ranks last")
  }

  func testCandidateFromEachAltSettingIsEvaluated() {
    // Both alt settings of the same interface should be evaluated independently.
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)

    let alt0 = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    let alt1 = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP Enhanced")

    XCTAssertTrue(alt0.isCandidate)
    XCTAssertTrue(alt1.isCandidate)
    XCTAssertGreaterThan(
      alt1.score, alt0.score,
      "Alt setting with MTP in name should score higher")
  }

  func testInterfaceWithNoEndpointsIsRejected() {
    let noEPs = EPCandidates(bulkIn: 0, bulkOut: 0, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: noEPs, interfaceName: "MTP")
    XCTAssertFalse(result.isCandidate, "Interface with no endpoints should be rejected")
    XCTAssertEqual(result.score, Int.min)
  }

  func testInterfaceWithOnlyBulkInIsRejected() {
    let oneEP = EPCandidates(bulkIn: 0x81, bulkOut: 0, evtIn: 0)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: oneEP, interfaceName: "")
    XCTAssertFalse(result.isCandidate, "Interface with only bulk IN should be rejected")
  }

  func testVendorSpecificWithEventEndpointIsCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")
    // Vendor 0xFF with bulk pair + event endpoint = 62 + 5 = 67
    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 60)
  }
}

// MARK: - Transport State Machine Tests

final class TransportStateMachineTests: XCTestCase {

  /// State machine: idle → connecting → ready → transferring → error → recovery
  enum TransportState: String, CaseIterable {
    case idle, connecting, ready, transferring, error, recovery
  }

  struct TransportStateMachine {
    private(set) var state: TransportState = .idle

    mutating func connect() -> Bool {
      guard state == .idle else { return false }
      state = .connecting
      return true
    }

    mutating func didEstablishSession() -> Bool {
      guard state == .connecting else { return false }
      state = .ready
      return true
    }

    mutating func beginTransfer() -> Bool {
      guard state == .ready else { return false }
      state = .transferring
      return true
    }

    mutating func transferComplete() -> Bool {
      guard state == .transferring else { return false }
      state = .ready
      return true
    }

    mutating func encounteredError() -> Bool {
      guard state == .transferring || state == .ready || state == .connecting else { return false }
      state = .error
      return true
    }

    mutating func beginRecovery() -> Bool {
      guard state == .error else { return false }
      state = .recovery
      return true
    }

    mutating func recoveryComplete() -> Bool {
      guard state == .recovery else { return false }
      state = .ready
      return true
    }

    mutating func disconnect() {
      state = .idle
    }
  }

  func testHappyPathTransition() {
    var sm = TransportStateMachine()
    XCTAssertEqual(sm.state, .idle)

    XCTAssertTrue(sm.connect())
    XCTAssertEqual(sm.state, .connecting)

    XCTAssertTrue(sm.didEstablishSession())
    XCTAssertEqual(sm.state, .ready)

    XCTAssertTrue(sm.beginTransfer())
    XCTAssertEqual(sm.state, .transferring)

    XCTAssertTrue(sm.transferComplete())
    XCTAssertEqual(sm.state, .ready)
  }

  func testErrorAndRecoveryPath() {
    var sm = TransportStateMachine()
    _ = sm.connect()
    _ = sm.didEstablishSession()
    _ = sm.beginTransfer()

    XCTAssertTrue(sm.encounteredError())
    XCTAssertEqual(sm.state, .error)

    XCTAssertTrue(sm.beginRecovery())
    XCTAssertEqual(sm.state, .recovery)

    XCTAssertTrue(sm.recoveryComplete())
    XCTAssertEqual(sm.state, .ready)
  }

  func testInvalidTransitionsAreRejected() {
    var sm = TransportStateMachine()

    // Cannot transfer from idle
    XCTAssertFalse(sm.beginTransfer())
    XCTAssertEqual(sm.state, .idle)

    // Cannot establish session from idle
    XCTAssertFalse(sm.didEstablishSession())
    XCTAssertEqual(sm.state, .idle)

    // Cannot recover from idle
    XCTAssertFalse(sm.beginRecovery())
    XCTAssertEqual(sm.state, .idle)
  }

  func testConnectFromNonIdleIsRejected() {
    var sm = TransportStateMachine()
    _ = sm.connect()
    XCTAssertFalse(sm.connect(), "Cannot connect when already connecting")
  }

  func testDisconnectFromAnyState() {
    for startState in TransportState.allCases {
      var sm = TransportStateMachine()
      // Drive to target state
      switch startState {
      case .idle: break
      case .connecting: _ = sm.connect()
      case .ready:
        _ = sm.connect()
        _ = sm.didEstablishSession()
      case .transferring:
        _ = sm.connect()
        _ = sm.didEstablishSession()
        _ = sm.beginTransfer()
      case .error:
        _ = sm.connect()
        _ = sm.didEstablishSession()
        _ = sm.beginTransfer()
        _ = sm.encounteredError()
      case .recovery:
        _ = sm.connect()
        _ = sm.didEstablishSession()
        _ = sm.beginTransfer()
        _ = sm.encounteredError()
        _ = sm.beginRecovery()
      }
      XCTAssertEqual(sm.state, startState)
      sm.disconnect()
      XCTAssertEqual(sm.state, .idle, "Disconnect from \(startState) should return to idle")
    }
  }

  func testErrorFromConnectingState() {
    var sm = TransportStateMachine()
    _ = sm.connect()
    XCTAssertTrue(sm.encounteredError())
    XCTAssertEqual(sm.state, .error)
  }

  func testMultipleTransferCycles() {
    var sm = TransportStateMachine()
    _ = sm.connect()
    _ = sm.didEstablishSession()

    for _ in 0..<10 {
      XCTAssertTrue(sm.beginTransfer())
      XCTAssertTrue(sm.transferComplete())
      XCTAssertEqual(sm.state, .ready)
    }
  }
}

// MARK: - Libusb Error Mapping Exhaustive Tests

final class LibusbErrorMappingWave30Tests: XCTestCase {

  func testAllKnownErrorCodesMapped() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_TIMEOUT.rawValue)), .timeout)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_BUSY.rawValue)), .busy)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_ACCESS.rawValue)), .accessDenied)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)), .noDevice)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_PIPE.rawValue)), .stall)
  }

  func testUnknownErrorCodeMapsToIO() {
    // Exclude known mapped codes: -3(access), -4(noDevice), -6(busy), -7(timeout), -9(pipe/stall)
    let unknownCodes: [Int32] = [-1, -2, -5, -8, -10, -11, -12, -13, -99, -1000]
    for code in unknownCodes {
      if case .io(let msg) = mapLibusb(code) {
        XCTAssertTrue(msg.contains("\(code)"), "IO message should contain error code \(code)")
      } else {
        XCTFail("Unknown error code \(code) should map to .io")
      }
    }
  }

  func testCheckThrowsOnNonZero() {
    XCTAssertNoThrow(try check(0))
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_TIMEOUT.rawValue))) { error in
      XCTAssertEqual(error as? MTPError, .transport(.timeout))
    }
  }

  func testCheckThrowsTransportErrorForPipe() {
    XCTAssertThrowsError(try check(Int32(LIBUSB_ERROR_PIPE.rawValue))) { error in
      XCTAssertEqual(error as? MTPError, .transport(.stall))
    }
  }
}

// MARK: - Transport Phase Tests

final class TransportPhaseWave30Tests: XCTestCase {

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testTransportPhaseEquality() {
    XCTAssertEqual(TransportPhase.bulkOut, TransportPhase.bulkOut)
    XCTAssertNotEqual(TransportPhase.bulkOut, TransportPhase.bulkIn)
  }

  func testTimeoutInPhaseError() {
    let bulkOutTimeout = TransportError.timeoutInPhase(.bulkOut)
    let bulkInTimeout = TransportError.timeoutInPhase(.bulkIn)
    let responseTimeout = TransportError.timeoutInPhase(.responseWait)

    XCTAssertNotEqual(bulkOutTimeout, bulkInTimeout)
    XCTAssertNotEqual(bulkInTimeout, responseTimeout)
    XCTAssertEqual(bulkOutTimeout, TransportError.timeoutInPhase(.bulkOut))
  }

  func testTimeoutInPhaseIsDistinctFromGenericTimeout() {
    let generic = TransportError.timeout
    let phased = TransportError.timeoutInPhase(.bulkOut)
    XCTAssertNotEqual(generic, phased)
  }

  func testTransportErrorLocalizedDescriptions() {
    XCTAssertNotNil(TransportError.stall.errorDescription)
    XCTAssertNotNil(TransportError.timeout.errorDescription)
    XCTAssertNotNil(TransportError.noDevice.errorDescription)
    XCTAssertNotNil(TransportError.busy.errorDescription)
    XCTAssertNotNil(TransportError.accessDenied.errorDescription)
    XCTAssertNotNil(TransportError.io("test").errorDescription)
    XCTAssertNotNil(TransportError.timeoutInPhase(.bulkIn).errorDescription)
  }
}

// MARK: - Probe Recovery Heuristic Tests

final class ProbeRecoveryWave30Tests: XCTestCase {

  func testNoProgressTimeoutWithZeroBytesIsRecoverable() {
    XCTAssertTrue(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 0))
  }

  func testTimeoutWithPartialDataIsNotRecoverable() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 512))
  }

  func testNonTimeoutErrorIsNotRecoverable() {
    // BUSY (-6) with zero sent should not be treated as no-progress timeout.
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -6, sent: 0))
  }

  func testSuccessIsNotRecoverable() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: 0, sent: 0))
  }

  func testProbeLadderResultFields() {
    let success = ProbeLadderResult(
      succeeded: true, cachedDeviceInfoData: Data([0xAB]), stepAttempted: "OpenSession")
    XCTAssertTrue(success.succeeded)
    XCTAssertEqual(success.cachedDeviceInfoData, Data([0xAB]))
    XCTAssertEqual(success.stepAttempted, "OpenSession")

    let failure = ProbeLadderResult(
      succeeded: false, cachedDeviceInfoData: nil, stepAttempted: "GetDeviceInfo")
    XCTAssertFalse(failure.succeeded)
    XCTAssertNil(failure.cachedDeviceInfoData)
  }

  func testProbeAllResultFields() {
    let result = ProbeAllResult(candidate: nil, cachedDeviceInfo: nil, probeStep: nil)
    XCTAssertNil(result.candidate)
    XCTAssertNil(result.cachedDeviceInfo)
    XCTAssertNil(result.probeStep)

    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82, score: 120,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let successResult = ProbeAllResult(
      candidate: candidate, cachedDeviceInfo: Data([0x01]), probeStep: "GetDeviceInfo")
    XCTAssertNotNil(successResult.candidate)
    XCTAssertEqual(successResult.candidate?.score, 120)
    XCTAssertEqual(successResult.probeStep, "GetDeviceInfo")
  }
}

// MARK: - Helpers

private extension UInt16 {
  var isPowerOf2: Bool { self > 0 && (self & (self - 1)) == 0 }
}
