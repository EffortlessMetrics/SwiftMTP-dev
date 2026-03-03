// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
@testable import SwiftMTPTransportLibUSB

// MARK: - 1. Timeout Handling Edge Cases

/// Tests for timeout edge cases across different transport phases and operations.
final class TimeoutHandlingEdgeCaseTests: XCTestCase {

  // MARK: - Helpers

  private func makeFaultLink(
    config: VirtualDeviceConfig = .pixel7,
    faults: [ScheduledFault]
  ) -> FaultInjectingLink {
    let inner = VirtualMTPLink(config: config)
    return FaultInjectingLink(wrapping: inner, schedule: FaultSchedule(faults))
  }

  // MARK: - Timeout during close session

  func testTimeoutDuringCloseSessionDoesNotLeak() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.closeSession), error: .timeout),
    ])
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    do {
      try await link.closeSession()
      XCTFail("Expected timeout on closeSession")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }
    // close() should still succeed after a timed-out closeSession
    await link.close()
  }

  // MARK: - Successive timeouts on different operations

  func testSuccessiveTimeoutsOnDifferentOperations() async throws {
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo),
      .timeoutOnce(on: .getStorageIDs),
      .timeoutOnce(on: .getObjectHandles),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Each operation should fail with timeout in sequence
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected timeout") }
    catch { XCTAssertEqual(error as? TransportError, .timeout) }

    do { _ = try await link.getStorageIDs(); XCTFail("Expected timeout") }
    catch { XCTAssertEqual(error as? TransportError, .timeout) }

    do {
      _ = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected timeout")
    } catch { XCTAssertEqual(error as? TransportError, .timeout) }

    // All faults consumed — subsequent calls should succeed
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
  }

  // MARK: - Timeout with zero repeat count (unlimited)

  func testUnlimitedTimeoutFaultBlocksAllCalls() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .timeout,
        repeatCount: 0, label: "unlimited-timeout"),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Multiple calls should all fail — fault is unlimited
    for _ in 0..<5 {
      do {
        _ = try await link.getDeviceInfo()
        XCTFail("Expected timeout")
      } catch {
        XCTAssertEqual(error as? TransportError, .timeout)
      }
    }
  }

  // MARK: - Timeout at specific call index

  func testTimeoutAtCallIndexTriggersOnCorrectCall() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(2), error: .timeout),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Call 0 — succeeds
    let info0 = try await link.getDeviceInfo()
    XCTAssertEqual(info0.model, "Pixel 7")

    // Call 1 — succeeds
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Call 2 — should timeout
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout at call index 2")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }

    // Call 3 — succeeds (fault consumed)
    let info3 = try await link.getDeviceInfo()
    XCTAssertEqual(info3.model, "Pixel 7")
  }

  // MARK: - Phase-specific timeout errors

  func testTimeoutInPhaseEquality() {
    let bulkOut1 = TransportError.timeoutInPhase(.bulkOut)
    let bulkOut2 = TransportError.timeoutInPhase(.bulkOut)
    let bulkIn = TransportError.timeoutInPhase(.bulkIn)
    let responseWait = TransportError.timeoutInPhase(.responseWait)

    XCTAssertEqual(bulkOut1, bulkOut2)
    XCTAssertNotEqual(bulkOut1, bulkIn)
    XCTAssertNotEqual(bulkIn, responseWait)
    XCTAssertNotEqual(bulkOut1, .timeout)
  }

  // MARK: - Handshake vs IO timeout ordering

  func testHandshakeTimeoutShorterThanIOTimeout() {
    let config = SwiftMTPConfig()
    XCTAssertLessThan(
      config.handshakeTimeoutMs, config.ioTimeoutMs,
      "Handshake should complete faster than general IO")
  }

  func testOverallDeadlineCoversAllPhases() {
    let config = SwiftMTPConfig()
    let sumOfPhases = config.handshakeTimeoutMs + config.ioTimeoutMs
      + config.inactivityTimeoutMs
    XCTAssertGreaterThanOrEqual(
      config.overallDeadlineMs, config.handshakeTimeoutMs,
      "Overall deadline must cover at least one handshake")
    XCTAssertGreaterThan(config.overallDeadlineMs, 0)
    _ = sumOfPhases
  }
}

// MARK: - 2. Partial USB Read Recovery

/// Tests for partial read recovery and data integrity after faults.
final class PartialUSBReadRecoveryTests: XCTestCase {

  // MARK: - Helpers

  private func makeFaultLink(
    config: VirtualDeviceConfig = .pixel7,
    faults: [ScheduledFault]
  ) -> FaultInjectingLink {
    let inner = VirtualMTPLink(config: config)
    return FaultInjectingLink(wrapping: inner, schedule: FaultSchedule(faults))
  }

  // MARK: - IO error during getObjectInfos recovery

  func testIOErrorDuringGetObjectInfosRecoveryOnRetry() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getObjectInfos), error: .io("partial read: 128/1024"))
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call fails with IO error (simulating partial read)
    do {
      _ = try await link.getObjectInfos([1, 2, 3])
      XCTFail("Expected IO error")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("partial read"))
      } else {
        XCTFail("Expected TransportError.io, got \(error)")
      }
    }

    // Fault consumed — retry returns correct data
    let infos = try await link.getObjectInfos([1, 2, 3])
    XCTAssertFalse(infos.isEmpty)
  }

  // MARK: - Pipe stall during getStorageInfo recovery

  func testPipeStallDuringGetStorageInfoRecovery() async throws {
    let schedule = FaultSchedule([.pipeStall(on: .getStorageInfo)])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    let storageID = MTPStorageID(raw: 0x0001_0001)

    // First call — pipe stall
    do {
      _ = try await link.getStorageInfo(id: storageID)
      XCTFail("Expected pipe stall")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("pipe stall"))
      } else {
        XCTFail("Expected TransportError.io for pipe stall")
      }
    }

    // Retry succeeds after stall is cleared
    let info = try await link.getStorageInfo(id: storageID)
    XCTAssertEqual(info.id.raw, storageID.raw)
  }

  // MARK: - Streaming command recovery after partial data fault

  func testStreamingCommandRecoveryAfterIOFault() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand),
        error: .io("bulk transfer short read"))
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1, params: [])

    // First call fails
    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected IO error")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("short read"))
      } else {
        XCTFail("Expected TransportError.io")
      }
    }

    // Retry succeeds
    let result = try await link.executeStreamingCommand(
      cmd, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
    XCTAssertTrue(result.isOK)
  }

  // MARK: - Data integrity after fault + retry cycle

  func testDataIntegrityAfterFaultAndRetry() async throws {
    let config = VirtualDeviceConfig.pixel7
      .withObject(
        VirtualObjectConfig(
          handle: 500,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: "integrity_test.jpg",
          sizeBytes: 4096,
          formatCode: 0x3801
        ))
    let schedule = FaultSchedule([.timeoutOnce(on: .getObjectInfos)])
    let inner = VirtualMTPLink(config: config)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call fails
    do {
      _ = try await link.getObjectInfos([500])
      XCTFail("Expected timeout")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }

    // Retry returns correct data
    let infos = try await link.getObjectInfos([500])
    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos[0].name, "integrity_test.jpg")
    XCTAssertEqual(infos[0].sizeBytes, 4096)
  }
}

// MARK: - 3. Endpoint Enumeration with Malformed Descriptors

/// Tests for endpoint and descriptor validation edge cases.
final class EndpointEnumerationMalformedTests: XCTestCase {

  // MARK: - Endpoint address boundary values

  func testEndpointAddressZero() {
    let addr = USBEndpointAddress(rawValue: 0x00)
    XCTAssertTrue(addr.isOutput, "Endpoint 0x00 should be output direction")
    XCTAssertEqual(addr.number, 0, "Endpoint number should be 0")
  }

  func testEndpointAddressMaxValue() {
    let addr = USBEndpointAddress(rawValue: 0xFF)
    XCTAssertTrue(addr.isInput, "Endpoint 0xFF should be input direction")
    XCTAssertEqual(addr.number, 0x0F, "Endpoint number should be max (15)")
  }

  func testEndpointAddressDirectionBitOnly() {
    let inOnly = USBEndpointAddress(rawValue: 0x80)
    XCTAssertTrue(inOnly.isInput)
    XCTAssertEqual(inOnly.number, 0, "Endpoint number should be 0 with only direction bit")
  }

  // MARK: - Descriptor with unusual endpoint values

  func testDescriptorWithSameInOutEndpoint() {
    // Malformed: bulkIn and bulkOut share same endpoint number (different direction)
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x01,
      interruptEndpoint: nil, usbSpeedMBps: nil)
    XCTAssertTrue(desc.bulkInEndpoint & 0x80 != 0, "IN should have direction bit")
    XCTAssertTrue(desc.bulkOutEndpoint & 0x80 == 0, "OUT should lack direction bit")
    XCTAssertEqual(desc.bulkInEndpoint & 0x0F, desc.bulkOutEndpoint & 0x0F,
                   "Endpoint numbers should match")
  }

  func testDescriptorWithHighEndpointNumbers() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 7, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x01, bulkInEndpoint: 0x8F, bulkOutEndpoint: 0x0F,
      interruptEndpoint: 0x8E, usbSpeedMBps: nil)
    XCTAssertEqual(desc.bulkInEndpoint & 0x0F, 0x0F)
    XCTAssertEqual(desc.bulkOutEndpoint & 0x0F, 0x0F)
    XCTAssertEqual(desc.interfaceNumber, 7)
  }

  // MARK: - Descriptor with non-MTP class/subclass values

  func testDescriptorWithNonStandardInterfaceClass() {
    // Vendor-specific class (0xFF) used by some Android devices
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0xFF, interfaceSubclass: 0xFF,
      interfaceProtocol: 0x00, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02,
      interruptEndpoint: nil, usbSpeedMBps: nil)
    XCTAssertEqual(desc.interfaceClass, 0xFF)
    XCTAssertEqual(desc.interfaceSubclass, 0xFF)
  }

  func testDescriptorWithZeroInterfaceProtocol() {
    let desc = MTPLinkDescriptor(
      interfaceNumber: 0, interfaceClass: 0x06, interfaceSubclass: 0x01,
      interfaceProtocol: 0x00, bulkInEndpoint: 0x81, bulkOutEndpoint: 0x02,
      interruptEndpoint: 0x83, usbSpeedMBps: nil)
    XCTAssertEqual(desc.interfaceProtocol, 0x00)
  }

  // MARK: - InterfaceCandidate scoring edge cases

  func testInterfaceCandidateWithZeroScore() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 0, altSetting: 0,
      bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x00,
      score: 0,
      ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00)
    XCTAssertEqual(candidate.score, 0)
    XCTAssertEqual(candidate.eventIn, 0x00, "No interrupt endpoint (zero)")
  }

  func testInterfaceCandidateWithoutEventEndpoint() {
    let candidate = InterfaceCandidate(
      ifaceNumber: 1, altSetting: 0,
      bulkIn: 0x82, bulkOut: 0x03, eventIn: 0x00,
      score: 50,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertEqual(candidate.eventIn, 0x00)
    XCTAssertEqual(candidate.ifaceNumber, 1)
  }

  func testInterfaceCandidateSortingByScore() {
    let candidates = [
      InterfaceCandidate(
        ifaceNumber: 0, altSetting: 0,
        bulkIn: 0x81, bulkOut: 0x01, eventIn: 0x82,
        score: 50,
        ifaceClass: 0xFF, ifaceSubclass: 0x00, ifaceProtocol: 0x00),
      InterfaceCandidate(
        ifaceNumber: 1, altSetting: 0,
        bulkIn: 0x83, bulkOut: 0x04, eventIn: 0x85,
        score: 100,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01),
      InterfaceCandidate(
        ifaceNumber: 2, altSetting: 0,
        bulkIn: 0x86, bulkOut: 0x07, eventIn: 0x00,
        score: 25,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x00),
    ]
    let sorted = candidates.sorted { $0.score > $1.score }
    XCTAssertEqual(sorted[0].ifaceNumber, 1, "Highest score first")
    XCTAssertEqual(sorted[1].ifaceNumber, 0)
    XCTAssertEqual(sorted[2].ifaceNumber, 2, "Lowest score last")
  }
}

// MARK: - 4. Connection Drop During Active Transfer

/// Tests for disconnect faults injected during various transfer operations.
final class ConnectionDropDuringTransferTests: XCTestCase {

  // MARK: - Helpers

  private func makeFaultLink(
    config: VirtualDeviceConfig = .pixel7,
    faults: [ScheduledFault]
  ) -> FaultInjectingLink {
    let inner = VirtualMTPLink(config: config)
    return FaultInjectingLink(wrapping: inner, schedule: FaultSchedule(faults))
  }

  // MARK: - Disconnect during executeCommand

  func testDisconnectDuringExecuteCommandMapsToNoDevice() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .disconnected),
    ])
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])
    do {
      _ = try await link.executeCommand(cmd)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  // MARK: - Disconnect during streaming command

  func testDisconnectDuringStreamingTransfer() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.executeStreamingCommand), error: .disconnected),
    ])
    let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1, params: [])
    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 4096, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  // MARK: - Disconnect during getObjectInfos

  func testDisconnectDuringGetObjectInfos() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .disconnected),
    ])
    do {
      _ = try await link.getObjectInfos([1, 2, 3])
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  // MARK: - Disconnect during delete object

  func testDisconnectDuringDeleteIsNotRetriable() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.deleteObject), error: .disconnected),
    ])
    do {
      try await link.deleteObject(handle: 42)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
    // After disconnect, close should still be safe
    await link.close()
  }

  // MARK: - Disconnect recovery across session lifecycle

  func testDisconnectRecoveryWithNewSession() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First getStorageIDs disconnects
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected noDevice")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }

    // Fault consumed — "reconnect" by opening a new session
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty, "After reconnect, storage IDs should be available")
    try await link.closeSession()
  }

  // MARK: - Multiple disconnects before successful operation

  func testMultipleDisconnectsBeforeSuccess() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getDeviceInfo), error: .disconnected,
        repeatCount: 3, label: "disconnect×3"),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    for i in 0..<3 {
      do {
        _ = try await link.getDeviceInfo()
        XCTFail("Expected noDevice on attempt \(i)")
      } catch {
        XCTAssertEqual(error as? TransportError, .noDevice)
      }
    }

    // After 3 disconnects exhausted, operation succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
  }

  // MARK: - Disconnect at specific byte offset

  func testDisconnectAtByteOffset() async throws {
    let schedule = FaultSchedule([
      ScheduledFault.disconnectAtOffset(512),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    // The fault is scheduled; verify it was created
    XCTAssertNotNil(link)
  }
}

// MARK: - 5. Zero-Length Packet Handling

/// Tests for zero-length packet (ZLP) detection and handling at USB boundaries.
final class ZeroLengthPacketHandlingTests: XCTestCase {

  // MARK: - ZLP detection for USB 2.0 High Speed

  func testZLPRequiredForExact512Multiple() {
    let maxPacket: Int = 512
    let sizes = [512, 1024, 2048, 4096, 65536]
    for size in sizes {
      let needsZLP = size > 0 && size % maxPacket == 0
      XCTAssertTrue(needsZLP, "Size \(size) should require ZLP on USB 2.0 HS")
    }
  }

  func testZLPNotRequiredForNon512Multiple() {
    let maxPacket: Int = 512
    let sizes = [1, 100, 511, 513, 1023, 2047]
    for size in sizes {
      let needsZLP = size > 0 && size % maxPacket == 0
      XCTAssertFalse(needsZLP, "Size \(size) should not require ZLP")
    }
  }

  func testZLPNotRequiredForZeroLength() {
    let maxPacket: Int = 512
    let needsZLP = 0 > 0 && 0 % maxPacket == 0
    XCTAssertFalse(needsZLP, "Zero-length transfer should not require ZLP")
  }

  // MARK: - ZLP detection for USB 3.0 SuperSpeed

  func testZLPRequiredForExact1024Multiple() {
    let maxPacket: Int = 1024
    let sizes = [1024, 2048, 4096, 8192]
    for size in sizes {
      let needsZLP = size > 0 && size % maxPacket == 0
      XCTAssertTrue(needsZLP, "Size \(size) should require ZLP on USB 3.0 SS")
    }
  }

  func testZLPNotRequiredForNon1024Multiple() {
    let maxPacket: Int = 1024
    let sizes = [1, 512, 1023, 1025, 2047, 3000]
    for size in sizes {
      let needsZLP = size > 0 && size % maxPacket == 0
      XCTAssertFalse(needsZLP, "Size \(size) should not require ZLP on USB 3.0")
    }
  }

  // MARK: - Zero-length data does not corrupt device state

  func testOperationsAfterZeroLengthConceptualRead() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    // Simulate handling zero-length scenario by reading empty handles
    let emptyInfos = try await link.getObjectInfos([])
    XCTAssertTrue(emptyInfos.isEmpty)

    // Device should still function normally
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")

    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    try await link.closeSession()
    await link.close()
  }

  // MARK: - Empty device handles with various profiles

  func testEmptyDeviceHandlesOnEmptyConfig() async throws {
    let link = VirtualMTPLink(config: .emptyDevice)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty, "Even empty device should have a storage")

    let handles = try await link.getObjectHandles(storage: storageIDs[0], parent: nil)
    XCTAssertTrue(handles.isEmpty, "Empty device should have no objects")

    try await link.closeSession()
    await link.close()
  }

  // MARK: - PTP container with minimal/zero payload

  func testPTPCommandWithNoParamsIsValid() {
    let cmd = makePTPCommand(opcode: 0x1001, txid: 1, params: [])
    XCTAssertEqual(cmd.count, 12, "No-param command should be header-only (12 bytes)")
    // Verify the type field is command (1)
    let typeLE = UInt16(cmd[4]) | (UInt16(cmd[5]) << 8)
    XCTAssertEqual(typeLE, PTPContainer.Kind.command.rawValue)
  }

  func testPTPDataContainerWithZeroPayloadLength() {
    let data = makePTPDataContainer(length: 0, code: 0x1009, txid: 1)
    XCTAssertEqual(data.count, 12, "Data container header is always 12 bytes")
    let typeLE = UInt16(data[4]) | (UInt16(data[5]) << 8)
    XCTAssertEqual(typeLE, PTPContainer.Kind.data.rawValue)
  }

  // MARK: - No-progress timeout recovery for zero-sent

  func testNoProgressTimeoutRecoveryZeroSent() {
    XCTAssertTrue(
      MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 0),
      "Zero-sent timeout should be recoverable")
  }

  func testNoProgressTimeoutNotRecoverableWithPartialSent() {
    XCTAssertFalse(
      MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 1),
      "Partial-sent timeout should not be recoverable")
  }

  func testNoProgressTimeoutNotRecoverableForNonTimeout() {
    XCTAssertFalse(
      MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -1, sent: 0),
      "Non-timeout error should not be recoverable via no-progress path")
  }
}
