// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class FaultInjectingExtendedTests: XCTestCase {

  private func makeLink() -> VirtualMTPLink {
    VirtualMTPLink(config: .emptyDevice)
  }

  // MARK: - Operation-Specific Faults

  func testFaultOnGetDeviceInfo() async throws {
    let base = makeLink()
    let schedule = FaultSchedule([.timeoutOnce(on: .getDeviceInfo)])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout fault")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testFaultOnDeleteObject() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(handle: 42, storage: storageId, parent: nil, name: "test.txt"))
    let base = VirtualMTPLink(config: config)
    let schedule = FaultSchedule([.timeoutOnce(on: .deleteObject)])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do {
      try await link.deleteObject(handle: 42)
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
  }

  func testFaultOnGetStorageInfo() async throws {
    let base = makeLink()
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageInfo)])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 0x00010001))
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
  }

  func testFaultOnGetObjectHandles() async throws {
    let base = makeLink()
    let schedule = FaultSchedule([.timeoutOnce(on: .getObjectHandles)])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do {
      _ = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0x00010001), parent: nil)
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
  }

  // MARK: - Trigger Types

  func testFaultAtCallIndex() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(2), error: .timeout)
    ])

    XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil))
    XCTAssertNotNil(schedule.check(operation: .openSession, callIndex: 2, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .openSession, callIndex: 2, byteOffset: nil))
  }

  func testFaultByteOffset() {
    let schedule = FaultSchedule([.disconnectAtOffset(1024)])

    XCTAssertNil(
      schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 512))
    XCTAssertNotNil(
      schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 1024))
  }

  // MARK: - Error Types

  func testAccessDeniedFault() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .accessDenied)
    ])
    let result = schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil)
    XCTAssertNotNil(result)
    if case .accessDenied = result {} else {
      XCTFail("Expected accessDenied, got \(String(describing: result))")
    }
  }

  func testDisconnectedFaultThroughLink() async throws {
    let base = makeLink()
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected)
    ])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected disconnected fault")
    } catch {
      // TransportError.noDevice
      XCTAssertTrue(
        "\(error)".lowercased().contains("no") || "\(error)".lowercased().contains("device"))
    }
  }

  func testIOFault() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .io("disk full"))
    ])
    let result = schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil)
    if case .io(let msg) = result {
      XCTAssertEqual(msg, "disk full")
    } else {
      XCTFail("Expected io fault")
    }
  }

  func testProtocolErrorFault() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .protocolError(code: 0x2019))
    ])
    let result = schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil)
    if case .protocolError(let code) = result {
      XCTAssertEqual(code, 0x2019)
    } else {
      XCTFail("Expected protocolError fault")
    }
  }

  // MARK: - Repeat & Scheduling

  func testUnlimitedRepeatFault() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 0)
    ])
    for _ in 0..<10 {
      XCTAssertNotNil(
        schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil),
        "Unlimited fault should fire every time")
    }
  }

  func testFaultScheduleClear() {
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo),
      .pipeStall(on: .openSession),
    ])
    XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil))
    schedule.clear()
    XCTAssertNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))
  }

  func testCompoundFaults() async throws {
    let base = makeLink()
    let schedule = FaultSchedule([
      .timeoutOnce(on: .openSession),
      .pipeStall(on: .getDeviceInfo),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy),
    ])
    let link = FaultInjectingLink(wrapping: base, schedule: schedule)

    do { try await link.openSession(id: 1); XCTFail("Expected timeout") } catch {}
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected stall") } catch {}
    do { _ = try await link.getStorageIDs(); XCTFail("Expected busy") } catch {}

    // All consumed; now should succeed
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  // MARK: - Fault Metadata

  func testFaultErrorTransportMapping() {
    let mappings: [(FaultError, String)] = [
      (.timeout, "timeout"),
      (.busy, "busy"),
      (.io("test message"), "test message"),
      (.protocolError(code: 0x2019), "Protocol error"),
    ]
    for (fault, expected) in mappings {
      let transport = fault.transportError
      XCTAssertTrue(
        "\(transport)".contains(expected),
        "Expected \(expected) in \(transport)")
    }
  }

  func testScheduledFaultLabels() {
    let timeout = ScheduledFault.timeoutOnce(on: .getDeviceInfo)
    XCTAssertTrue(timeout.label?.contains("timeout") == true)

    let stall = ScheduledFault.pipeStall(on: .openSession)
    XCTAssertTrue(stall.label?.contains("pipeStall") == true)

    let busy = ScheduledFault.busyForRetries(5)
    XCTAssertTrue(busy.label?.contains("busy") == true)

    let disconnect = ScheduledFault.disconnectAtOffset(2048)
    XCTAssertTrue(disconnect.label?.contains("disconnect") == true)
  }

  func testLinkOperationTypeCaseIterable() {
    XCTAssertGreaterThanOrEqual(LinkOperationType.allCases.count, 12)
    XCTAssertTrue(LinkOperationType.allCases.contains(.openUSB))
    XCTAssertTrue(LinkOperationType.allCases.contains(.executeStreamingCommand))
  }
}
