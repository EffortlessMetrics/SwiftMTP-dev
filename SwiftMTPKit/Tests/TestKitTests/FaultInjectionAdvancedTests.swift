// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

// MARK: - Fault Injection at Specific Operation Counts

final class FaultInjectionOperationCountTests: XCTestCase {

  private func makeLink(
    config: VirtualDeviceConfig = .emptyDevice,
    schedule: FaultSchedule = FaultSchedule()
  ) -> FaultInjectingLink {
    FaultInjectingLink(wrapping: VirtualMTPLink(config: config), schedule: schedule)
  }

  func testFaultAtExactCallIndex0() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(0), error: .timeout)
    ])
    let link = makeLink(schedule: schedule)

    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout at call index 0")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    // Next call succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testFaultAtHighCallIndex() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(5), error: .busy)
    ])
    let link = makeLink(schedule: schedule)

    // Calls 0-4: succeed
    for _ in 0..<5 {
      _ = try await link.getDeviceInfo()
    }
    // Call 5: fault
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected busy at call index 5")
    } catch {
      XCTAssertTrue("\(error)".contains("busy"))
    }
    // Call 6: succeeds again
    _ = try await link.getDeviceInfo()
  }

  func testMultipleFaultsAtDifferentCallIndices() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(1), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(3), error: .busy),
    ])
    let link = makeLink(schedule: schedule)

    // Call 0: OK
    _ = try await link.getDeviceInfo()
    // Call 1: timeout
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected timeout") } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    // Call 2: OK
    _ = try await link.getStorageIDs()
    // Call 3: busy
    do { _ = try await link.getStorageIDs(); XCTFail("Expected busy") } catch {
      XCTAssertTrue("\(error)".contains("busy"))
    }
    // Call 4: OK
    _ = try await link.getDeviceInfo()
  }
}

// MARK: - Probabilistic Fault Injection

final class FaultInjectionProbabilisticTests: XCTestCase {

  func testUnlimitedFaultFiresEveryTime() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 0)
    ])
    for i in 0..<50 {
      let result = schedule.check(operation: .getDeviceInfo, callIndex: i, byteOffset: nil)
      XCTAssertNotNil(result, "Unlimited fault should fire on call \(i)")
    }
  }

  func testLimitedRepeatFaultFiresExactly3Times() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 3)
    ])
    for i in 0..<3 {
      XCTAssertNotNil(
        schedule.check(operation: .getStorageIDs, callIndex: i, byteOffset: nil),
        "Should fire on call \(i)")
    }
    XCTAssertNil(
      schedule.check(operation: .getStorageIDs, callIndex: 3, byteOffset: nil),
      "Should not fire after 3 uses")
  }

  func testSingleShotFaultFiresOnce() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .disconnected, repeatCount: 1)
    ])
    XCTAssertNotNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .openSession, callIndex: 1, byteOffset: nil))
  }
}

// MARK: - Fault Injection with Recovery

final class FaultInjectionRecoveryTests: XCTestCase {

  private func makeLink(schedule: FaultSchedule) -> FaultInjectingLink {
    FaultInjectingLink(wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)
  }

  func testRecoveryAfterTimeout() async throws {
    let link = makeLink(schedule: FaultSchedule([.timeoutOnce(on: .getDeviceInfo)]))

    // First call fails
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected timeout") } catch {}

    // Retry succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testRecoveryAfterMultipleBusyRetries() async throws {
    let link = makeLink(schedule: FaultSchedule([.busyForRetries(3)]))

    var failCount = 0
    for _ in 0..<5 {
      do {
        _ = try await link.executeCommand(PTPContainer(type: 1, code: 0x1001, txid: 1))
        break // success
      } catch {
        failCount += 1
      }
    }
    XCTAssertEqual(failCount, 3)
  }

  func testRecoverySequenceOfDifferentFaults() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .io("retry later")),
    ])
    let link = makeLink(schedule: schedule)

    var errors: [String] = []
    for _ in 0..<3 {
      do {
        _ = try await link.getDeviceInfo()
      } catch {
        errors.append("\(error)")
      }
    }
    XCTAssertEqual(errors.count, 3)
    XCTAssertTrue(errors[0].contains("timeout"))
    XCTAssertTrue(errors[1].contains("busy"))
    XCTAssertTrue(errors[2].contains("retry later"))

    // Fourth call recovers
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }
}

// MARK: - Cascading Faults

final class FaultInjectionCascadingTests: XCTestCase {

  func testSequentialFaultsOnDifferentOperations() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .timeout),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected),
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)

    // openSession -> timeout
    do { try await link.openSession(id: 1); XCTFail("Expected timeout") }
    catch { XCTAssertTrue("\(error)".contains("timeout")) }

    // getDeviceInfo -> busy
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected busy") }
    catch { XCTAssertTrue("\(error)".contains("busy")) }

    // getStorageIDs -> disconnected
    do { _ = try await link.getStorageIDs(); XCTFail("Expected disconnected") }
    catch {
      let desc = "\(error)".lowercased()
      XCTAssertTrue(desc.contains("no") || desc.contains("device"))
    }

    // All faults consumed - operations succeed
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }

  func testFaultOnOneOperationDoesNotAffectOthers() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 0)
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)

    // getDeviceInfo always faults
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected timeout") } catch {}

    // Other operations are unaffected
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
    try await link.openSession(id: 1)
  }

  func testDynamicFaultAddedAfterInitialFaultConsumed() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout)
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)

    // Consume initial fault
    do { _ = try await link.getDeviceInfo(); XCTFail("Expected timeout") } catch {}

    // Add new fault dynamically
    link.scheduleFault(ScheduledFault(
      trigger: .onOperation(.getStorageIDs), error: .busy))

    do { _ = try await link.getStorageIDs(); XCTFail("Expected busy") }
    catch { XCTAssertTrue("\(error)".contains("busy")) }

    // Both faults now consumed
    _ = try await link.getDeviceInfo()
    _ = try await link.getStorageIDs()
  }
}

// MARK: - Fault Injection Timing (Before/During/After)

final class FaultInjectionTimingTests: XCTestCase {

  func testFaultBeforeOperationPreventsExecution() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageInfo)])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)

    do {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
  }

  func testByteOffsetFaultDuringStreaming() {
    let schedule = FaultSchedule([.disconnectAtOffset(4096)])

    // Before target offset: no fault
    XCTAssertNil(
      schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 0))
    XCTAssertNil(
      schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 2048))
    // At target offset: fault fires
    XCTAssertNotNil(
      schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 4096))
  }

  func testAfterDelayTriggerDoesNotMatchSynchronously() {
    // afterDelay is handled externally; schedule.check should return nil
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .afterDelay(1.0), error: .timeout)
    ])
    let result = schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil)
    XCTAssertNil(result, "afterDelay trigger should not match in synchronous check")
  }
}

// MARK: - Fault Injection with Timeout Simulation

final class FaultInjectionTimeoutSimulationTests: XCTestCase {

  func testTimeoutOnAllLinkOperationTypes() async throws {
    for opType in LinkOperationType.allCases {
      let schedule = FaultSchedule([.timeoutOnce(on: opType)])
      let result = schedule.check(operation: opType, callIndex: 0, byteOffset: nil)
      XCTAssertNotNil(result, "Timeout should fire for \(opType)")
      if case .timeout = result {} else {
        XCTFail("Expected .timeout for \(opType), got \(String(describing: result))")
      }
    }
  }

  func testTimeoutTransportErrorMapping() {
    let fault = FaultError.timeout
    let transport = fault.transportError
    XCTAssertTrue("\(transport)".contains("timeout"))
  }

  func testTimeoutDoesNotAffectSubsequentCalls() async throws {
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice),
      schedule: FaultSchedule([.timeoutOnce(on: .getDeviceInfo)]))

    do { _ = try await link.getDeviceInfo() } catch {}

    // Subsequent calls succeed
    let info1 = try await link.getDeviceInfo()
    let info2 = try await link.getDeviceInfo()
    XCTAssertEqual(info1.manufacturer, info2.manufacturer)
  }
}

// MARK: - Fault Patterns (Intermittent, Permanent, Transient)

final class FaultPatternTests: XCTestCase {

  func testPermanentFaultPattern() {
    // repeatCount: 0 = unlimited = permanent
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .disconnected, repeatCount: 0)
    ])
    for i in 0..<20 {
      XCTAssertNotNil(
        schedule.check(operation: .getDeviceInfo, callIndex: i, byteOffset: nil),
        "Permanent fault should fire on call \(i)")
    }
  }

  func testTransientFaultPattern() {
    // repeatCount: 1 = fires once then gone
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1)
    ])
    XCTAssertNotNil(schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil))
  }

  func testIntermittentFaultPatternViaMultipleScheduled() {
    // Simulate intermittent: faults at call 0, 2, 4 (manually scheduled)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(0), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(2), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(4), error: .timeout),
    ])
    XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: 1, byteOffset: nil))
    XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 2, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: 3, byteOffset: nil))
    XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 4, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: 5, byteOffset: nil))
  }

  func testBurstFaultPatternWithRepeatCount() {
    // 5 faults in a row, then recovery
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .busy, repeatCount: 5)
    ])
    for _ in 0..<5 {
      XCTAssertNotNil(schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil))
    }
    XCTAssertNil(schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil))
  }

  func testMixedPermanentAndTransientFaults() async throws {
    let schedule = FaultSchedule([
      // Permanent disconnect on getDeviceInfo
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .disconnected, repeatCount: 0),
      // Transient busy on getStorageIDs
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .emptyDevice), schedule: schedule)

    // getStorageIDs: one fault then recovers
    do { _ = try await link.getStorageIDs(); XCTFail("Expected busy") } catch {}
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // getDeviceInfo: always faults
    for _ in 0..<3 {
      do { _ = try await link.getDeviceInfo(); XCTFail("Expected disconnect") } catch {}
    }
  }

  func testAllFaultErrorTypes() {
    let errors: [FaultError] = [
      .timeout, .busy, .disconnected, .accessDenied,
      .io("test"), .protocolError(code: 0x2005),
    ]
    for error in errors {
      let transport = error.transportError
      XCTAssertNotNil(transport, "Transport mapping should exist for \(error)")
    }
  }

  func testPipeStallConvenienceFactory() {
    let fault = ScheduledFault.pipeStall(on: .openUSB)
    if case .io(let msg) = fault.error {
      XCTAssertTrue(msg.contains("pipe stall"))
    } else {
      XCTFail("pipeStall should produce .io error")
    }
    XCTAssertTrue(fault.label?.contains("pipeStall") == true)
  }

  func testDisconnectAtOffsetConvenienceFactory() {
    let fault = ScheduledFault.disconnectAtOffset(8192)
    if case .atByteOffset(let offset) = fault.trigger {
      XCTAssertEqual(offset, 8192)
    } else {
      XCTFail("Expected atByteOffset trigger")
    }
    if case .disconnected = fault.error {} else {
      XCTFail("Expected .disconnected error")
    }
  }

  func testBusyForRetriesConvenienceFactory() {
    let fault = ScheduledFault.busyForRetries(10)
    XCTAssertEqual(fault.repeatCount, 10)
    if case .busy = fault.error {} else {
      XCTFail("Expected .busy error")
    }
  }
}
