// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class FaultInjectingTests: XCTestCase {
  func testFaultScheduleTriggersOnOperation() {
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo)
    ])

    let result = schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil)
    XCTAssertNotNil(result)

    // Should not fire again (repeatCount was 1)
    let result2 = schedule.check(operation: .getDeviceInfo, callIndex: 1, byteOffset: nil)
    XCTAssertNil(result2)
  }

  func testBusyForRetries() {
    let schedule = FaultSchedule([
      .busyForRetries(3)
    ])

    for _ in 0..<3 {
      let result = schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil)
      XCTAssertNotNil(result)
    }

    // 4th call should succeed
    let result = schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil)
    XCTAssertNil(result)
  }

  func testDynamicFaultInjection() {
    let schedule = FaultSchedule()

    // No faults initially
    XCTAssertNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))

    // Add fault dynamically
    schedule.add(.pipeStall(on: .openSession))

    let result = schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil)
    XCTAssertNotNil(result)
  }
}
