// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
@testable import SwiftMTPTransportLibUSB

// MARK: - 1. USB Endpoint Enumeration Edge Cases

/// Tests for InterfaceProbe heuristic scoring with various interface class/subclass combos.
final class InterfaceProbeEdgeCaseTests: XCTestCase {

  // MARK: Canonical MTP (class 0x06 / subclass 0x01)

  func testCanonicalMTPInterfaceScoresAboveThreshold() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
    XCTAssertGreaterThanOrEqual(result.score, 100)
  }

  func testCanonicalMTPWithoutEventEndpointStillCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
  }

  // MARK: PTP class (0x06 / 0x01 / 0x01) vs (0x06 / 0x01 / 0x00)

  func testPTPProtocolZeroStillCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")
    XCTAssertTrue(result.isCandidate)
  }

  // MARK: Vendor-specific (0xFF) with name heuristics

  func testVendorSpecificWithPTPInNameIsCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "PTP Interface")
    XCTAssertTrue(result.isCandidate)
  }

  func testVendorSpecificWithFileTransferInNameIsCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "File Transfer")
    XCTAssertTrue(result.isCandidate)
  }

  func testVendorSpecificWithNoNameHintScoresLow() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x00, interfaceProtocol: 0x00,
      endpoints: eps, interfaceName: "")
    // Without a name hint and no event endpoint, should have low score or not be candidate
    if result.isCandidate {
      XCTAssertLessThan(result.score, 100)
    }
  }

  // MARK: ADB exclusion (0xFF / 0x42 / 0x01)

  func testADBInterfaceIsExcluded() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "ADB Interface")
    XCTAssertFalse(result.isCandidate)
  }

  func testADBSubclassWithoutNameStillExcluded() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0xFF, interfaceSubclass: 0x42, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: Mass storage exclusion (class 0x08)

  func testMassStorageClassIsNotMTPCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x08, interfaceSubclass: 0x06, interfaceProtocol: 0x50,
      endpoints: eps, interfaceName: "")
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: CDC class exclusion (class 0x02)

  func testCDCClassIsNotMTPCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x02, interfaceSubclass: 0x02, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "")
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: Missing endpoints

  func testNoBulkInEndpointIsNotCandidate() {
    let eps = EPCandidates(bulkIn: 0x00, bulkOut: 0x02, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP")
    XCTAssertFalse(result.isCandidate)
  }

  func testNoBulkOutEndpointIsNotCandidate() {
    let eps = EPCandidates(bulkIn: 0x81, bulkOut: 0x00, evtIn: 0x83)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP")
    XCTAssertFalse(result.isCandidate)
  }

  func testNoEndpointsAtAllIsNotCandidate() {
    let eps = EPCandidates(bulkIn: 0x00, bulkOut: 0x00, evtIn: 0x00)
    let result = evaluateMTPInterfaceCandidate(
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      endpoints: eps, interfaceName: "MTP")
    XCTAssertFalse(result.isCandidate)
  }

  // MARK: Candidate sorting by score

  func testHigherScoredCandidateRanksFirst() {
    let high = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0, bulkIn: 0x81, bulkOut: 0x02, eventIn: 0x83,
      score: 165, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    let low = InterfaceCandidate(
      ifaceNumber: 1, altSetting: 0, bulkIn: 0x84, bulkOut: 0x03, eventIn: 0x00,
      score: 60, ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00)
    let sorted = [low, high].sorted { $0.score > $1.score }
    XCTAssertEqual(sorted.first?.ifaceNumber, 0)
  }

  func testMultipleCandidatesSortedByScore() {
    let candidates = [30, 165, 80, 100, 60].enumerated().map { idx, score in
      InterfaceCandidate(
        ifaceNumber: UInt8(idx), altSetting: 0, bulkIn: 0x81, bulkOut: 0x02,
        eventIn: 0x83, score: score, ifaceClass: 0x06, ifaceSubclass: 0x01,
        ifaceProtocol: 0x01)
    }
    let sorted = candidates.sorted { $0.score > $1.score }
    XCTAssertEqual(sorted.map(\.score), [165, 100, 80, 60, 30])
  }

  // MARK: InterfaceCandidate edge values

  func testMaxEndpointAddressValues() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0xFF, altSetting: 0xFF, bulkIn: 0xFF, bulkOut: 0x7F,
      eventIn: 0xFF, score: 100, ifaceClass: 0x06, ifaceSubclass: 0x01,
      ifaceProtocol: 0x01)
    XCTAssertEqual(candidate.ifaceNumber, 0xFF)
    XCTAssertEqual(candidate.bulkIn, 0xFF)
  }

  func testZeroScoreCandidate() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0, bulkIn: 0x81, bulkOut: 0x02,
      eventIn: 0x83, score: 0, ifaceClass: 0x06, ifaceSubclass: 0x01,
      ifaceProtocol: 0x01)
    XCTAssertEqual(candidate.score, 0)
  }

  func testNegativeScoreCandidate() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0, bulkIn: 0x81, bulkOut: 0x02,
      eventIn: 0x83, score: -200, ifaceClass: 0xFF, ifaceSubclass: 0x42,
      ifaceProtocol: 0x01)
    XCTAssertLessThan(candidate.score, 0)
  }
}

// MARK: - 2. Bulk Transfer Error Handling

/// Tests for mid-stream transfer failures using FaultInjectingLink.
final class BulkTransferErrorHandlingTests: XCTestCase {

  func testTimeoutDuringGetStorageIDs() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageIDs)])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    do {
      _ = try await faulty.getStorageIDs()
      XCTFail("Expected timeout error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }
  }

  func testTimeoutRecoveryOnRetry() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageIDs)])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // First call fails
    do { _ = try await faulty.getStorageIDs() } catch { /* expected */ }
    // Second call succeeds (fault consumed)
    let ids = try await faulty.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testBusyRetryExhaustion() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.busyForRetries(3)])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // First 3 calls should fail with busy
    for _ in 0..<3 {
      do {
        _ = try await faulty.executeCommand(
          PTPContainer(type: PTPContainer.Kind.command.rawValue, code: 0x1001, txid: 1))
        XCTFail("Expected busy error")
      } catch let error as TransportError {
        XCTAssertEqual(error, .busy)
      }
    }
    // 4th call succeeds
    let result = try await faulty.executeCommand(
      PTPContainer(type: PTPContainer.Kind.command.rawValue, code: 0x1001, txid: 2))
    XCTAssertTrue(result.isOK)
  }

  func testDisconnectDuringOpenSession() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.openSession), error: .disconnected,
        label: "disconnect-on-open")
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    do {
      try await faulty.openSession(id: 1)
      XCTFail("Expected disconnect error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .noDevice)
    }
  }

  func testPipeStallOnExecuteCommand() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .executeCommand)])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    do {
      _ = try await faulty.executeCommand(
        PTPContainer(type: PTPContainer.Kind.command.rawValue, code: 0x1001, txid: 1))
      XCTFail("Expected IO error")
    } catch let error as TransportError {
      if case .io(let msg) = error {
        XCTAssertTrue(msg.contains("pipe stall") || msg.contains("stall"))
      } else {
        // pipeStall maps to .io("USB pipe stall")
        XCTFail("Expected io error, got \(error)")
      }
    }
  }

  func testAccessDeniedOnOpenUSB() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.openUSB), error: .accessDenied,
        label: "access-denied")
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    do {
      try await faulty.openUSBIfNeeded()
      XCTFail("Expected accessDenied error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .accessDenied)
    }
  }

  func testIOErrorMessagePreserved() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let message = "LIBUSB_ERROR_OVERFLOW at offset 4096"
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .io(message),
        label: "io-overflow")
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    do {
      _ = try await faulty.getDeviceInfo()
      XCTFail("Expected IO error")
    } catch let error as TransportError {
      if case .io(let msg) = error {
        XCTAssertEqual(msg, message)
      } else {
        XCTFail("Expected io error with message")
      }
    }
  }

  func testMultipleFaultsOnDifferentOperations() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getStorageIDs),
      .pipeStall(on: .getDeviceInfo),
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // getDeviceInfo fails with pipe stall
    do {
      _ = try await faulty.getDeviceInfo()
      XCTFail("Expected error")
    } catch let error as TransportError {
      if case .io = error { /* expected */ } else { XCTFail("Expected io error") }
    }

    // getStorageIDs fails with timeout
    do {
      _ = try await faulty.getStorageIDs()
      XCTFail("Expected error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }
  }

  func testFaultScheduleClearRemovesAllFaults() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getStorageIDs),
      .timeoutOnce(on: .getDeviceInfo),
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    schedule.clear()

    // Both operations should succeed now
    _ = try await faulty.getDeviceInfo()
    _ = try await faulty.getStorageIDs()
  }

  func testDynamicallyAddedFaultFires() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule()
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // First call succeeds
    _ = try await faulty.getDeviceInfo()

    // Add fault dynamically
    schedule.add(.timeoutOnce(on: .getDeviceInfo))

    // Second call fails
    do {
      _ = try await faulty.getDeviceInfo()
      XCTFail("Expected timeout")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }
  }
}

// MARK: - 3. USB Descriptor Parsing

/// Tests for PTP container header encoding and parsing edge cases.
final class USBDescriptorParsingTests: XCTestCase {

  func testPTPHeaderMinimumSize() {
    XCTAssertEqual(PTPHeader.size, 12)
  }

  func testPTPHeaderEncodeDecodeRoundTrip() {
    let original = PTPHeader(length: 20, type: 1, code: 0x1001, txid: 42)
    var buffer = [UInt8](repeating: 0, count: PTPHeader.size)
    buffer.withUnsafeMutableBytes { original.encode(into: $0.baseAddress!) }
    let decoded = buffer.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(decoded.length, 20)
    XCTAssertEqual(decoded.type, 1)
    XCTAssertEqual(decoded.code, 0x1001)
    XCTAssertEqual(decoded.txid, 42)
  }

  func testPTPHeaderZeroLength() {
    let header = PTPHeader(length: 0, type: 1, code: 0x1001, txid: 0)
    var buffer = [UInt8](repeating: 0, count: PTPHeader.size)
    buffer.withUnsafeMutableBytes { header.encode(into: $0.baseAddress!) }
    let decoded = buffer.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(decoded.length, 0)
  }

  func testPTPHeaderMaxLengthValue() {
    let header = PTPHeader(length: UInt32.max, type: 0xFFFF, code: 0xFFFF, txid: UInt32.max)
    var buffer = [UInt8](repeating: 0, count: PTPHeader.size)
    buffer.withUnsafeMutableBytes { header.encode(into: $0.baseAddress!) }
    let decoded = buffer.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(decoded.length, UInt32.max)
    XCTAssertEqual(decoded.type, 0xFFFF)
    XCTAssertEqual(decoded.code, 0xFFFF)
    XCTAssertEqual(decoded.txid, UInt32.max)
  }

  func testMakePTPCommandNoParams() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [])
    XCTAssertEqual(cmd.count, 12)  // header only
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 12)
    XCTAssertEqual(header.code, 0x1001)
    XCTAssertEqual(header.type, PTPContainer.Kind.command.rawValue)
  }

  func testMakePTPCommandWithFiveParams() {
    let params: [UInt32] = [1, 2, 3, 4, 5]
    let cmd = makePTPCommand(opcode: 0x1002, txid: 7, params: params)
    XCTAssertEqual(cmd.count, 12 + 5 * 4)  // 32 bytes
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 32)
    XCTAssertEqual(header.txid, 7)
  }

  func testMakePTPCommandParamEncoding() {
    let cmd = makePTPCommand(opcode: 0x1004, txid: 1, params: [0xDEADBEEF])
    // Param at offset 12, little-endian
    XCTAssertEqual(cmd[12], 0xEF)
    XCTAssertEqual(cmd[13], 0xBE)
    XCTAssertEqual(cmd[14], 0xAD)
    XCTAssertEqual(cmd[15], 0xDE)
  }

  func testMakePTPDataContainerHeaderType() {
    let data = makePTPDataContainer(length: 100, code: 0x1009, txid: 3)
    XCTAssertEqual(data.count, PTPHeader.size)
    let header = data.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.type, PTPContainer.Kind.data.rawValue)
    XCTAssertEqual(header.length, 100)
    XCTAssertEqual(header.code, 0x1009)
    XCTAssertEqual(header.txid, 3)
  }

  func testPTPContainerEncode() {
    let container = PTPContainer(
      length: 16, type: PTPContainer.Kind.command.rawValue, code: 0x1002,
      txid: 10, params: [1])
    var buffer = [UInt8](repeating: 0, count: 16)
    let written = buffer.withUnsafeMutableBytes { ptr -> Int in
      container.encode(into: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self))
    }
    XCTAssertEqual(written, 16)
  }

  func testPTPContainerKindRawValues() {
    XCTAssertEqual(PTPContainer.Kind.command.rawValue, 1)
    XCTAssertEqual(PTPContainer.Kind.data.rawValue, 2)
    XCTAssertEqual(PTPContainer.Kind.response.rawValue, 3)
    XCTAssertEqual(PTPContainer.Kind.event.rawValue, 4)
  }

  func testPTPOpCommonValues() {
    XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
    XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
    XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
    XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
    XCTAssertEqual(PTPOp.getObject.rawValue, 0x1009)
    XCTAssertEqual(PTPOp.sendObject.rawValue, 0x100D)
  }

  func testDescriptorParsingWithTruncatedBuffer() {
    // A buffer too short to contain a full header should not crash
    let shortBuffer: [UInt8] = [0x0C, 0x00, 0x00, 0x00]  // only 4 bytes
    // We can still read partial header (length field)
    let length = shortBuffer.withUnsafeBytes {
      $0.baseAddress!.loadUnaligned(as: UInt32.self)
    }
    XCTAssertEqual(UInt32(littleEndian: length), 12)
  }

  func testAllZeroBufferDecoding() {
    let buffer = [UInt8](repeating: 0, count: PTPHeader.size)
    let header = buffer.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 0)
    XCTAssertEqual(header.type, 0)
    XCTAssertEqual(header.code, 0)
    XCTAssertEqual(header.txid, 0)
  }

  func testAllOnesBufferDecoding() {
    let buffer = [UInt8](repeating: 0xFF, count: PTPHeader.size)
    let header = buffer.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, UInt32.max)
    XCTAssertEqual(header.type, UInt16.max)
    XCTAssertEqual(header.code, UInt16.max)
    XCTAssertEqual(header.txid, UInt32.max)
  }
}

// MARK: - 4. Transport Configuration

/// Tests for transfer configuration edge cases.
final class TransportConfigurationEdgeCaseTests: XCTestCase {

  func testMinimumChunkSize() {
    var config = TransferConfig.default
    config.chunkSize = 512
    XCTAssertEqual(config.chunkSize, 512)
  }

  func testMaximumChunkSize() {
    var config = TransferConfig.default
    config.chunkSize = 8 * 1024 * 1024  // 8 MB
    XCTAssertEqual(config.chunkSize, 8 * 1024 * 1024)
  }

  func testZeroTimeoutValue() {
    var config = TransferConfig.default
    config.timeoutMs = 0
    XCTAssertEqual(config.timeoutMs, 0)
  }

  func testVeryLargeTimeoutValue() {
    var config = TransferConfig.default
    config.timeoutMs = 120_000  // 2 minutes
    XCTAssertEqual(config.timeoutMs, 120_000)
  }

  func testDefaultConfigValues() {
    let config = TransferConfig.default
    XCTAssertEqual(config.timeoutMs, 10_000)
    XCTAssertEqual(config.chunkSize, 2 * 1024 * 1024)
  }

  func testChunkSizePowerOfTwo() {
    let powers = (9...23).map { 1 << $0 }  // 512 to 8MB
    for size in powers {
      var config = TransferConfig.default
      config.chunkSize = size
      XCTAssertEqual(config.chunkSize, size)
      XCTAssertEqual(config.chunkSize & (config.chunkSize - 1), 0, "Expected power of two")
    }
  }

  func testMTPLinkDescriptorFieldValues() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0,
      interfaceClass: 0x06,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      bulkInEndpoint: 0x81,
      bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83,
      usbSpeedMBps: 40
    )
    XCTAssertEqual(desc.interfaceClass, 0x06)
    XCTAssertEqual(desc.bulkInEndpoint, 0x81)
    XCTAssertEqual(desc.interruptEndpoint, 0x83)
    XCTAssertEqual(desc.usbSpeedMBps, 40)
  }

  func testMTPLinkDescriptorWithoutOptionalFields() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 1,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x00,
      interfaceProtocol: 0x00,
      bulkInEndpoint: 0x84,
      bulkOutEndpoint: 0x05
    )
    XCTAssertNil(desc.interruptEndpoint)
    XCTAssertNil(desc.usbSpeedMBps)
  }

  func testMTPLinkDescriptorEquality() {
    let a = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02)
    let b = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02)
    XCTAssertEqual(a, b)
  }

  func testMTPLinkDescriptorInequality() {
    let a = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02)
    let b = MTPLinkDescriptor(
      interfaceNumber: 1, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02)
    XCTAssertNotEqual(a, b)
  }

  func testMTPLinkDescriptorHashable() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02)
    var set = Set<MTPLinkDescriptor>()
    set.insert(desc)
    set.insert(desc)
    XCTAssertEqual(set.count, 1)
  }

  func testUSBEndpointAddressDirectionBits() {
    // IN endpoints have bit 7 set
    let inAddr = USBEndpointAddress(rawValue: 0x81)
    XCTAssertTrue(inAddr.isInput)
    XCTAssertFalse(inAddr.isOutput)
    XCTAssertEqual(inAddr.number, 1)

    // OUT endpoints have bit 7 clear
    let outAddr = USBEndpointAddress(rawValue: 0x02)
    XCTAssertFalse(outAddr.isInput)
    XCTAssertTrue(outAddr.isOutput)
    XCTAssertEqual(outAddr.number, 2)
  }

  func testUSBEndpointAddressBoundaryValues() {
    let ep0 = USBEndpointAddress(rawValue: 0x00)
    XCTAssertEqual(ep0.number, 0)
    XCTAssertTrue(ep0.isOutput)

    let ep15In = USBEndpointAddress(rawValue: 0x8F)
    XCTAssertEqual(ep15In.number, 0x0F)
    XCTAssertTrue(ep15In.isInput)
  }

  // MARK: - No-progress timeout recovery

  func testShouldRecoverNoProgressTimeoutWithZeroSent() {
    let result = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 0)
    XCTAssertTrue(result)
  }

  func testShouldNotRecoverNoProgressTimeoutWithPartialSent() {
    let result = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 10)
    XCTAssertFalse(result)
  }

  func testShouldNotRecoverNonTimeoutError() {
    let result = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -1, sent: 0)
    XCTAssertFalse(result)
  }

  func testProbeShouldRecoverMatchesZeroSentTimeout() {
    XCTAssertTrue(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 0))
  }

  func testProbeShouldNotRecoverPartialSent() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 1))
  }

  func testProbeShouldNotRecoverNonTimeoutRC() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -5, sent: 0))
  }
}

// MARK: - 5. Connection Lifecycle

/// Tests for open/close/reopen sequences and concurrent access.
final class ConnectionLifecycleTests: XCTestCase {

  func testOpenCloseSession() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    try await link.closeSession()
    await link.close()
  }

  func testReopenAfterClose() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    try await link.closeSession()
    try await link.openSession(id: 2)
    try await link.closeSession()
  }

  func testMultipleOpenClosesCycles() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    for sessionId in 1...5 {
      try await link.openUSBIfNeeded()
      try await link.openSession(id: UInt32(sessionId))
      _ = try await link.getDeviceInfo()
      try await link.closeSession()
    }
    await link.close()
  }

  func testGetDeviceInfoAfterOpen() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
    try await link.closeSession()
  }

  func testGetStorageInfoAfterOpen() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
    let info = try await link.getStorageInfo(id: ids[0])
    XCTAssertFalse(info.description.isEmpty)
    try await link.closeSession()
  }

  func testConcurrentGetDeviceInfoCalls() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    // Run multiple concurrent info requests
    let results = try await withThrowingTaskGroup(of: MTPDeviceInfo.self) { group in
      for _ in 0..<10 {
        group.addTask {
          try await link.getDeviceInfo()
        }
      }
      var infos: [MTPDeviceInfo] = []
      for try await info in group {
        infos.append(info)
      }
      return infos
    }

    XCTAssertEqual(results.count, 10)
    for info in results {
      XCTAssertEqual(info.model, "Pixel 7")
    }
    try await link.closeSession()
  }

  func testFaultDuringSessionOpenThenRecover() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .openSession)])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    // First open fails
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected timeout")
    } catch {
      // expected
    }

    // Retry succeeds
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    try await link.closeSession()
  }

  func testCloseIsIdempotent() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    await link.close()
    await link.close()  // second close should not crash
  }

  func testResetDeviceDoesNotThrow() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.resetDevice()  // no-op for virtual link
  }

  func testOperationsOnEmptyDevice() async throws {
    let link = VirtualMTPLink(config: .emptyDevice)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty)

    let handles = try await link.getObjectHandles(storage: storageIDs[0], parent: nil)
    XCTAssertTrue(handles.isEmpty)

    try await link.closeSession()
  }

  func testDeleteNonExistentObjectThrows() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    do {
      try await link.deleteObject(handle: 99999)
      XCTFail("Expected error for non-existent object")
    } catch let error as TransportError {
      if case .io = error { /* expected */ } else { XCTFail("Expected io error") }
    }
    try await link.closeSession()
  }

  func testMoveNonExistentObjectThrows() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    do {
      try await link.moveObject(handle: 99999, to: storageIDs[0], parent: nil)
      XCTFail("Expected error for non-existent object")
    } catch let error as TransportError {
      if case .io = error { /* expected */ } else { XCTFail("Expected io error") }
    }
    try await link.closeSession()
  }
}

// MARK: - 6. Large Transfer Simulation

/// Tests for chunked transfer reassembly with various sizes.
final class LargeTransferSimulationTests: XCTestCase {

  func testChunkedReassemblySmall() {
    let totalSize = 100
    let chunkSize = 32
    let chunks = stride(from: 0, to: totalSize, by: chunkSize).map { offset -> Data in
      let end = min(offset + chunkSize, totalSize)
      return Data(repeating: UInt8(offset / chunkSize), count: end - offset)
    }
    let reassembled = chunks.reduce(Data()) { $0 + $1 }
    XCTAssertEqual(reassembled.count, totalSize)
  }

  func testChunkedReassemblyExactMultiple() {
    let chunkSize = 512
    let numChunks = 8
    let totalSize = chunkSize * numChunks
    let chunks = (0..<numChunks).map { i in
      Data(repeating: UInt8(i & 0xFF), count: chunkSize)
    }
    let reassembled = chunks.reduce(Data()) { $0 + $1 }
    XCTAssertEqual(reassembled.count, totalSize)
  }

  func testChunkedReassemblyWithRemainder() {
    let chunkSize = 1024
    let totalSize = 3000  // 2 full chunks + 952 remainder
    let chunks = stride(from: 0, to: totalSize, by: chunkSize).map { offset -> Data in
      let end = min(offset + chunkSize, totalSize)
      return Data(repeating: UInt8(offset / chunkSize), count: end - offset)
    }
    XCTAssertEqual(chunks.count, 3)
    XCTAssertEqual(chunks.last?.count, 952)
    XCTAssertEqual(chunks.reduce(0) { $0 + $1.count }, totalSize)
  }

  func testChunkedReassembly1MB() {
    let chunkSize = 64 * 1024  // 64 KB
    let totalSize = 1024 * 1024  // 1 MB
    let numChunks = totalSize / chunkSize
    let chunks = (0..<numChunks).map { _ in Data(count: chunkSize) }
    let total = chunks.reduce(0) { $0 + $1.count }
    XCTAssertEqual(total, totalSize)
    XCTAssertEqual(numChunks, 16)
  }

  func testChunkedReassemblyLarge8MB() {
    let chunkSize = 2 * 1024 * 1024  // 2 MB (default)
    let totalSize = 8 * 1024 * 1024  // 8 MB
    let numChunks = totalSize / chunkSize
    let chunks = (0..<numChunks).map { _ in Data(count: chunkSize) }
    let total = chunks.reduce(0) { $0 + $1.count }
    XCTAssertEqual(total, totalSize)
    XCTAssertEqual(numChunks, 4)
  }

  func testSingleByteChunks() {
    let totalSize = 10
    let chunks = (0..<totalSize).map { Data([UInt8($0)]) }
    let reassembled = chunks.reduce(Data()) { $0 + $1 }
    XCTAssertEqual(reassembled.count, totalSize)
    for i in 0..<totalSize {
      XCTAssertEqual(reassembled[i], UInt8(i))
    }
  }

  func testEmptyTransfer() {
    let chunks: [Data] = []
    let reassembled = chunks.reduce(Data()) { $0 + $1 }
    XCTAssertEqual(reassembled.count, 0)
  }

  func testSingleChunkTransfer() {
    let data = Data(repeating: 0xAB, count: 4096)
    let chunks = [data]
    let reassembled = chunks.reduce(Data()) { $0 + $1 }
    XCTAssertEqual(reassembled, data)
  }

  func testChunkBoundaryAlignmentWith512() {
    // USB 2.0 max packet size boundary
    let packetSize = 512
    let sizes = [packetSize - 1, packetSize, packetSize + 1, packetSize * 2, packetSize * 2 - 1]
    for size in sizes {
      let data = Data(repeating: 0x42, count: size)
      let numChunks = (size + packetSize - 1) / packetSize
      let chunks = (0..<numChunks).map { i -> Data in
        let start = i * packetSize
        let end = min(start + packetSize, size)
        return data[start..<end]
      }
      let total = chunks.reduce(0) { $0 + $1.count }
      XCTAssertEqual(total, size, "Failed for size \(size)")
    }
  }

  func testVirtualDeviceExecuteCommandDuringTransfer() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    // Simulate a getObject command
    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue, code: PTPOp.getObject.rawValue,
      txid: 1, params: [1])
    let result = try await link.executeCommand(cmd)
    XCTAssertTrue(result.isOK)

    try await link.closeSession()
  }

  func testVirtualDeviceStreamingCommand() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue, code: PTPOp.getObject.rawValue,
      txid: 1, params: [1])
    let result = try await link.executeStreamingCommand(
      cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
    XCTAssertTrue(result.isOK)

    try await link.closeSession()
  }
}

// MARK: - 7. Packet Framing Edge Cases

/// Tests for MTP container header encoding/decoding boundary values.
final class PacketFramingEdgeCaseTests: XCTestCase {

  // MARK: Container length boundaries

  func testMinimumContainerLength() {
    // Minimum valid PTP container is 12 bytes (header only, no params)
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 12)
  }

  func testContainerLengthWithOneParam() {
    let cmd = makePTPCommand(opcode: 0x1002, txid: 0, params: [1])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 16)
  }

  func testContainerLengthWithMaxParams() {
    let cmd = makePTPCommand(opcode: 0x1007, txid: 0, params: [1, 2, 3, 4, 5])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 32)
  }

  // MARK: Transaction ID boundaries

  func testTxidZero() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.txid, 0)
  }

  func testTxidMaxValue() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: UInt32.max, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.txid, UInt32.max)
  }

  func testTxidIncrementSequence() {
    let commands = (0..<10).map { i in
      makePTPCommand(opcode: 0x1001, txid: UInt32(i), params: [])
    }
    for (i, cmd) in commands.enumerated() {
      let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      XCTAssertEqual(header.txid, UInt32(i))
    }
  }

  // MARK: Opcode boundary values

  func testOpcodeMinimumValue() {
    let cmd = makePTPCommand(opcode: 0x0000, txid: 0, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.code, 0x0000)
  }

  func testOpcodeMaximumValue() {
    let cmd = makePTPCommand(opcode: 0xFFFF, txid: 0, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.code, 0xFFFF)
  }

  func testVendorExtensionOpcodeRange() {
    // MTP vendor extension opcodes: 0x9800-0x9FFF
    let cmd = makePTPCommand(opcode: 0x9800, txid: 1, params: [])
    let header = cmd.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.code, 0x9800)
  }

  // MARK: Data container framing

  func testDataContainerWithZeroPayload() {
    let data = makePTPDataContainer(length: 12, code: 0x1009, txid: 1)
    let header = data.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, 12)  // header only, no payload
    XCTAssertEqual(header.type, PTPContainer.Kind.data.rawValue)
  }

  func testDataContainerWithLargeLength() {
    let length: UInt32 = 16 * 1024 * 1024 + 12  // 16 MB payload + header
    let data = makePTPDataContainer(length: length, code: 0x1009, txid: 1)
    let header = data.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, length)
  }

  func testDataContainerMaxLength() {
    let data = makePTPDataContainer(length: UInt32.max, code: 0x1009, txid: 1)
    let header = data.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    XCTAssertEqual(header.length, UInt32.max)
  }

  // MARK: Response result validation

  func testPTPResponseResultOK() {
    let result = PTPResponseResult(code: 0x2001, txid: 1)
    XCTAssertTrue(result.isOK)
    XCTAssertNil(result.data)
    XCTAssertTrue(result.params.isEmpty)
  }

  func testPTPResponseResultError() {
    let result = PTPResponseResult(code: 0x2002, txid: 1)
    XCTAssertFalse(result.isOK)
  }

  func testPTPResponseResultWithData() {
    let payload = Data([0x01, 0x02, 0x03])
    let result = PTPResponseResult(code: 0x2001, txid: 1, data: payload)
    XCTAssertTrue(result.isOK)
    XCTAssertEqual(result.data, payload)
  }

  func testPTPResponseResultWithParams() {
    let result = PTPResponseResult(code: 0x2001, txid: 5, params: [0x10001, 0x20001])
    XCTAssertEqual(result.params.count, 2)
    XCTAssertEqual(result.txid, 5)
  }

  // MARK: Little-endian encoding verification

  func testLittleEndianByteOrder() {
    let cmd = makePTPCommand(opcode: 0x1234, txid: 0x56789ABC, params: [])
    // opcode at offset 6-7, little-endian
    XCTAssertEqual(cmd[6], 0x34)  // low byte
    XCTAssertEqual(cmd[7], 0x12)  // high byte
    // txid at offset 8-11, little-endian
    XCTAssertEqual(cmd[8], 0xBC)
    XCTAssertEqual(cmd[9], 0x9A)
    XCTAssertEqual(cmd[10], 0x78)
    XCTAssertEqual(cmd[11], 0x56)
  }

  func testContainerLengthLittleEndian() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [1, 2, 3])
    // length at offset 0-3 = 24 = 0x18
    XCTAssertEqual(cmd[0], 0x18)
    XCTAssertEqual(cmd[1], 0x00)
    XCTAssertEqual(cmd[2], 0x00)
    XCTAssertEqual(cmd[3], 0x00)
  }

  func testContainerTypeLittleEndian() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 0, params: [])
    // type at offset 4-5 = command = 1
    XCTAssertEqual(cmd[4], 0x01)
    XCTAssertEqual(cmd[5], 0x00)
  }

  // MARK: PTPContainer.encode matches makePTPCommand

  func testPTPContainerEncodeConsistentWithMakePTPCommand() {
    let container = PTPContainer(
      length: 16, type: PTPContainer.Kind.command.rawValue, code: 0x1002,
      txid: 42, params: [1])
    var containerBuf = [UInt8](repeating: 0, count: 16)
    _ = containerBuf.withUnsafeMutableBytes { ptr in
      container.encode(into: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self))
    }
    let cmdBuf = makePTPCommand(opcode: 0x1002, txid: 42, params: [1])
    XCTAssertEqual(containerBuf, cmdBuf)
  }

  // MARK: TransportError variants

  func testTransportErrorEquality() {
    XCTAssertEqual(TransportError.stall, TransportError.stall)
    XCTAssertNotEqual(TransportError.stall, TransportError.timeout)
    XCTAssertEqual(
      TransportError.timeoutInPhase(.bulkIn), TransportError.timeoutInPhase(.bulkIn))
    XCTAssertNotEqual(
      TransportError.timeoutInPhase(.bulkIn), TransportError.timeoutInPhase(.bulkOut))
  }

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testTransportErrorTimeoutInPhaseAllPhases() {
    let phases: [TransportPhase] = [.bulkOut, .bulkIn, .responseWait]
    for phase in phases {
      let error = TransportError.timeoutInPhase(phase)
      if case .timeoutInPhase(let p) = error {
        XCTAssertEqual(p, phase)
      } else {
        XCTFail("Expected timeoutInPhase")
      }
    }
  }

  // MARK: FaultError → TransportError mapping

  func testFaultErrorMapsToCorrectTransportError() {
    let mappings: [(FaultError, TransportError)] = [
      (.timeout, .timeout),
      (.busy, .busy),
      (.disconnected, .noDevice),
      (.accessDenied, .accessDenied),
      (.io("test"), .io("test")),
    ]
    for (fault, expected) in mappings {
      XCTAssertEqual(fault.transportError, expected)
    }
  }

  func testFaultErrorProtocolErrorMapsToIO() {
    let fault = FaultError.protocolError(code: 0x2002)
    if case .io = fault.transportError { /* expected */ }
    else { XCTFail("Expected io transport error") }
  }

  // MARK: ScheduledFault label generation

  func testScheduledFaultLabels() {
    XCTAssertEqual(ScheduledFault.pipeStall(on: .executeCommand).label, "pipeStall(executeCommand)")
    XCTAssertEqual(ScheduledFault.disconnectAtOffset(2048).label, "disconnect@2048")
    XCTAssertEqual(ScheduledFault.busyForRetries(5).label, "busy×5")
    XCTAssertEqual(ScheduledFault.timeoutOnce(on: .openUSB).label, "timeout(openUSB)")
  }

  // MARK: FaultTrigger variants

  func testAllFaultTriggerVariants() {
    let triggers: [FaultTrigger] = [
      .onOperation(.getDeviceInfo),
      .atCallIndex(0),
      .atByteOffset(0),
      .afterDelay(1.0),
    ]
    XCTAssertEqual(triggers.count, 4)
    if case .onOperation(let op) = triggers[0] { XCTAssertEqual(op, .getDeviceInfo) }
    if case .atCallIndex(let idx) = triggers[1] { XCTAssertEqual(idx, 0) }
    if case .atByteOffset(let off) = triggers[2] { XCTAssertEqual(off, 0) }
    if case .afterDelay(let d) = triggers[3] { XCTAssertEqual(d, 1.0) }
  }

  // MARK: LinkOperationType coverage

  func testAllLinkOperationTypes() {
    let allOps = LinkOperationType.allCases
    XCTAssertGreaterThanOrEqual(allOps.count, 12)
    XCTAssertTrue(allOps.contains(.openUSB))
    XCTAssertTrue(allOps.contains(.openSession))
    XCTAssertTrue(allOps.contains(.closeSession))
    XCTAssertTrue(allOps.contains(.getDeviceInfo))
    XCTAssertTrue(allOps.contains(.getStorageIDs))
    XCTAssertTrue(allOps.contains(.executeCommand))
    XCTAssertTrue(allOps.contains(.executeStreamingCommand))
  }

  // MARK: MTPError transport wrapping

  func testMTPErrorWrapsTransportError() {
    let transport = TransportError.timeout
    let mtp = MTPError.transport(transport)
    if case .transport(let inner) = mtp {
      XCTAssertEqual(inner, .timeout)
    } else {
      XCTFail("Expected transport error wrapper")
    }
  }

  func testMTPErrorSessionAlreadyOpenDetection() {
    let err = MTPError.protocolError(code: 0x201E, message: "Session Already Open")
    XCTAssertTrue(err.isSessionAlreadyOpen)

    let other = MTPError.protocolError(code: 0x2001, message: nil)
    XCTAssertFalse(other.isSessionAlreadyOpen)
  }
}

// MARK: - Device Profile Variants

/// Tests with different virtual device profiles to ensure transport behavior is consistent.
final class DeviceProfileTransportTests: XCTestCase {

  func testPixel7ProfileOperations() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
    try await link.closeSession()
  }

  func testSamsungGalaxyProfileOperations() async throws {
    let link = VirtualMTPLink(config: .samsungGalaxy)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Samsung")
    try await link.closeSession()
  }

  func testCanonEOSR5ProfileOperations() async throws {
    let link = VirtualMTPLink(config: .canonEOSR5)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Canon")
    try await link.closeSession()
  }

  func testEmptyDeviceProfileOperations() async throws {
    let link = VirtualMTPLink(config: .emptyDevice)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.model, "Empty Device")
    let handles = try await link.getObjectHandles(
      storage: (try await link.getStorageIDs())[0], parent: nil)
    XCTAssertTrue(handles.isEmpty)
    try await link.closeSession()
  }

  func testFaultInjectingLinkPassesThroughOnNoFaults() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let faulty = FaultInjectingLink(wrapping: inner, schedule: FaultSchedule())
    try await faulty.openUSBIfNeeded()
    try await faulty.openSession(id: 1)
    let info = try await faulty.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
    try await faulty.closeSession()
    await faulty.close()
  }

  func testFaultInjectingLinkCachedDeviceInfoDelegatesToInner() {
    let inner = VirtualMTPLink(config: .pixel7)
    let faulty = FaultInjectingLink(wrapping: inner, schedule: FaultSchedule())
    // VirtualMTPLink returns nil for cachedDeviceInfo
    XCTAssertNil(faulty.cachedDeviceInfo)
  }

  func testFaultInjectingLinkLinkDescriptorDelegatesToInner() {
    let inner = VirtualMTPLink(config: .pixel7)
    let faulty = FaultInjectingLink(wrapping: inner, schedule: FaultSchedule())
    // VirtualMTPLink returns nil for linkDescriptor (default impl)
    XCTAssertNil(faulty.linkDescriptor)
  }

  func testFaultScheduleUnlimitedRepeatCount() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .timeout,
        repeatCount: 0, label: "infinite-timeout")
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // Should fail every time (unlimited)
    for _ in 0..<5 {
      do {
        _ = try await faulty.getDeviceInfo()
        XCTFail("Expected timeout")
      } catch let error as TransportError {
        XCTAssertEqual(error, .timeout)
      }
    }
  }

  func testFaultTriggerAtCallIndex() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .atCallIndex(2), error: .busy,
        label: "busy-at-call-2")
    ])
    let faulty = FaultInjectingLink(wrapping: link, schedule: schedule)

    // Call 0: openUSBIfNeeded - succeeds
    try await faulty.openUSBIfNeeded()
    // Call 1: openSession - succeeds
    try await faulty.openSession(id: 1)
    // Call 2: getDeviceInfo - should fail (call index 2)
    do {
      _ = try await faulty.getDeviceInfo()
      XCTFail("Expected busy error at call index 2")
    } catch let error as TransportError {
      XCTAssertEqual(error, .busy)
    }
    // Call 3: should succeed
    let info = try await faulty.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
    try await faulty.closeSession()
  }
}
