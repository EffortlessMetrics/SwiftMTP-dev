// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPObservability

final class RecoveryLogTests: XCTestCase {

  // MARK: - Recording

  func testRecordSuccessEvent() async {
    let log = RecoveryLog()
    let event = RecoveryEvent(
      strategy: "retry", attempt: 1, maxAttempts: 3, succeeded: true)
    await log.record(event)

    let rates = await log.rates()
    XCTAssertEqual(rates.successes, 1)
    XCTAssertEqual(rates.failures, 0)
  }

  func testRecordFailureEvent() async {
    let log = RecoveryLog()
    let event = RecoveryEvent(
      strategy: "retry", attempt: 1, maxAttempts: 3, succeeded: false,
      errorDescription: "timeout")
    await log.record(event)

    let rates = await log.rates()
    XCTAssertEqual(rates.successes, 0)
    XCTAssertEqual(rates.failures, 1)
  }

  func testRecordMixedEvents() async {
    let log = RecoveryLog()
    await log.record(
      RecoveryEvent(strategy: "retry", attempt: 1, maxAttempts: 3, succeeded: false))
    await log.record(
      RecoveryEvent(strategy: "retry", attempt: 2, maxAttempts: 3, succeeded: true))
    await log.record(
      RecoveryEvent(strategy: "reset", attempt: 1, maxAttempts: 1, succeeded: true))

    let rates = await log.rates()
    XCTAssertEqual(rates.successes, 2)
    XCTAssertEqual(rates.failures, 1)
  }

  // MARK: - Recent events

  func testRecentReturnsLatestEvents() async {
    let log = RecoveryLog()
    for i in 1...5 {
      await log.record(
        RecoveryEvent(
          strategy: "s\(i)", attempt: 1, maxAttempts: 1, succeeded: true))
    }

    let recent = await log.recent(limit: 3)
    XCTAssertEqual(recent.count, 3)
    XCTAssertEqual(recent[0].strategy, "s3")
    XCTAssertEqual(recent[2].strategy, "s5")
  }

  func testRecentWithLimitLargerThanCount() async {
    let log = RecoveryLog()
    await log.record(
      RecoveryEvent(strategy: "only", attempt: 1, maxAttempts: 1, succeeded: true))

    let recent = await log.recent(limit: 100)
    XCTAssertEqual(recent.count, 1)
  }

  // MARK: - Clear

  func testClearResetsAll() async {
    let log = RecoveryLog()
    await log.record(
      RecoveryEvent(strategy: "retry", attempt: 1, maxAttempts: 3, succeeded: true))
    await log.clear()

    let rates = await log.rates()
    XCTAssertEqual(rates.successes, 0)
    XCTAssertEqual(rates.failures, 0)

    let recent = await log.recent(limit: 100)
    XCTAssertTrue(recent.isEmpty)
  }

  // MARK: - Event cap (max 500)

  func testEventsAreCappedAtMax() async {
    let log = RecoveryLog()
    for i in 1...510 {
      await log.record(
        RecoveryEvent(
          strategy: "s\(i)", attempt: 1, maxAttempts: 1, succeeded: true))
    }

    let recent = await log.recent(limit: 600)
    XCTAssertLessThanOrEqual(recent.count, 500)
  }

  // MARK: - Concurrent access safety

  func testConcurrentRecordingDoesNotCrash() async {
    let log = RecoveryLog()
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          await log.record(
            RecoveryEvent(
              strategy: "concurrent-\(i)", attempt: 1, maxAttempts: 1,
              succeeded: i % 2 == 0))
        }
      }
    }

    let rates = await log.rates()
    XCTAssertEqual(rates.successes + rates.failures, 100)
  }
}
