// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for FaultInjectingLink behavior and MTPDeviceActor error recovery
/// using programmatic fault schedules.
final class FaultInjectionTests: XCTestCase {

  // MARK: - Basic fault injection

  func testGetStorageIDs_DisconnectFault_PropagatesAsNoDevice() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testGetObjectHandles_TimeoutFault_PropagatesAsTimeout() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .timeout, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x00010001), parent: nil)
      XCTFail("Expected error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testGetStorageIDs_BusyFault_PropagatesAsBusy() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .busy)
    }
  }

  func testFault_FiresExactlyRepeatCountTimes() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 2)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout on first call")
    } catch {}

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout on second call")
    } catch {}

    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "Third call should succeed after faults exhausted")
  }

  // MARK: - Multiple faults

  func testTwoSequentialFaults_FireInOrder() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var firstError: TransportError?
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected first fault")
    } catch let err as TransportError {
      firstError = err
    }

    var secondError: TransportError?
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected second fault")
    } catch let err as TransportError {
      secondError = err
    }

    XCTAssertEqual(firstError, .noDevice)
    XCTAssertEqual(secondError, .busy)

    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "Third call should succeed after both faults exhausted")
  }

  // MARK: - Link passthrough

  func testNoFault_PassthroughSucceeds() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule()
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty)
  }

  // MARK: - Fault on executeCommand

  func testExecuteCommand_DisconnectFault_Propagates() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let command = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: 0x00000001,
      params: []
    )

    do {
      _ = try await link.executeCommand(command)
      XCTFail("Expected error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }
}
