// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Tests for the layered ErrorRecoveryLayer: session recovery, stall recovery,
/// timeout escalation, disconnect handling, and recovery logging.
final class ErrorRecoveryLayerTests: XCTestCase {

  override func setUp() async throws {
    await RecoveryLog.shared.clear()
  }

  // MARK: - Session Recovery

  func testSessionRecovery_SucceedsAfterSessionNotOpen() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = MutableCounter()
    let ids = try await ErrorRecoveryLayer.withSessionRecovery(link: link) {
      let count = counter.increment()
      if count == 1 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    XCTAssertFalse(ids.isEmpty, "Should succeed after session recovery")
    XCTAssertEqual(counter.value, 2)
    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testSessionRecovery_BailsAfterMaxRetries() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    do {
      _ = try await ErrorRecoveryLayer.withSessionRecovery(link: link, maxRetries: 2) {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      XCTFail("Expected error after max retries")
    } catch let error as MTPError {
      if case .protocolError(let code, _) = error {
        XCTAssertEqual(code, 0x2003)
      } else {
        XCTFail("Expected protocolError, got \(error)")
      }
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertGreaterThan(rates.failures, 0, "Should record failures")
  }

  func testSessionRecovery_NonSessionError_PassesThrough() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    do {
      _ = try await ErrorRecoveryLayer.withSessionRecovery(link: link) {
        throw MTPError.deviceDisconnected
      }
      XCTFail("Expected disconnect error to pass through")
    } catch let error as MTPError {
      XCTAssertEqual(error, .deviceDisconnected)
    }
  }

  // MARK: - Stall Recovery

  func testStallRecovery_ClearsHaltAndRetries() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = MutableCounter()
    let result = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
      let count = counter.increment()
      if count == 1 {
        throw MTPError.transport(.stall)
      }
      return try await inner.getStorageIDs()
    }

    XCTAssertFalse(result.isEmpty)
    XCTAssertEqual(counter.value, 2, "Should retry once after stall")
    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testStallRecovery_NonStallError_PassesThrough() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    do {
      _ = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
        throw MTPError.timeout
      }
      XCTFail("Expected timeout to pass through")
    } catch let error as MTPError {
      XCTAssertEqual(error, .timeout)
    }
  }

  // MARK: - Timeout Escalation

  func testTimeoutEscalation_DoublesTimeoutOnRetry() async throws {
    let timeouts = MutableArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000,
      maxRetries: 3
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      if timeouts.count < 3 {
        throw MTPError.timeout
      }
      return "success"
    }

    XCTAssertEqual(result, "success")
    XCTAssertEqual(timeouts.snapshot, [1_000, 2_000, 4_000])
    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testTimeoutEscalation_CapsAt60Seconds() async throws {
    let timeouts = MutableArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 20_000,
      maxRetries: 3
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      if timeouts.count < 3 {
        throw MTPError.timeout
      }
      return "done"
    }

    XCTAssertEqual(result, "done")
    // 20_000 → 40_000 → 60_000 (capped)
    XCTAssertEqual(timeouts.snapshot, [20_000, 40_000, 60_000])
  }

  func testTimeoutEscalation_ExhaustsRetries() async throws {
    do {
      _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
        initialTimeoutMs: 1_000,
        maxRetries: 2
      ) { (_: Int) -> String in
        throw MTPError.timeout
      }
      XCTFail("Expected timeout after exhaustion")
    } catch let error as MTPError {
      XCTAssertEqual(error, .timeout)
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.failures, 1)
  }

  func testTimeoutEscalation_NonTimeoutError_PassesThrough() async throws {
    do {
      _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
        initialTimeoutMs: 1_000,
        maxRetries: 3
      ) { (_: Int) -> String in
        throw MTPError.busy
      }
      XCTFail("Expected busy error to pass through")
    } catch let error as MTPError {
      XCTAssertEqual(error, .busy)
    }
  }

  // MARK: - Disconnect Detection

  func testDisconnectDetection_MTPDeviceDisconnected() async {
    let result = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.deviceDisconnected, journal: nil, transferId: nil
    )
    XCTAssertTrue(result)
  }

  func testDisconnectDetection_TransportNoDevice() async {
    let result = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.transport(.noDevice), journal: nil, transferId: nil
    )
    XCTAssertTrue(result)
  }

  func testDisconnectDetection_RawTransportNoDevice() async {
    let result = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: TransportError.noDevice, journal: nil, transferId: nil
    )
    XCTAssertTrue(result)
  }

  func testDisconnectDetection_NonDisconnect_ReturnsFalse() async {
    let result = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.timeout, journal: nil, transferId: nil
    )
    XCTAssertFalse(result)
  }

  // MARK: - Error Classification

  func testIsSessionRecoverable_SessionNotOpen() {
    XCTAssertTrue(
      ErrorRecoveryLayer.isSessionRecoverable(.protocolError(code: 0x2003, message: nil)))
  }

  func testIsSessionRecoverable_SessionAlreadyOpen() {
    XCTAssertTrue(
      ErrorRecoveryLayer.isSessionRecoverable(.protocolError(code: 0x201E, message: nil)))
  }

  func testIsSessionRecoverable_SessionBusy() {
    XCTAssertTrue(ErrorRecoveryLayer.isSessionRecoverable(.sessionBusy))
  }

  func testIsSessionRecoverable_OtherErrors_ReturnFalse() {
    XCTAssertFalse(ErrorRecoveryLayer.isSessionRecoverable(.timeout))
    XCTAssertFalse(ErrorRecoveryLayer.isSessionRecoverable(.deviceDisconnected))
    XCTAssertFalse(ErrorRecoveryLayer.isSessionRecoverable(.storageFull))
  }

  func testIsStallError() {
    XCTAssertTrue(ErrorRecoveryLayer.isStallError(.transport(.stall)))
    XCTAssertFalse(ErrorRecoveryLayer.isStallError(.transport(.timeout)))
    XCTAssertFalse(ErrorRecoveryLayer.isStallError(.timeout))
  }

  func testIsTimeoutError() {
    XCTAssertTrue(ErrorRecoveryLayer.isTimeoutError(.timeout))
    XCTAssertTrue(ErrorRecoveryLayer.isTimeoutError(.transport(.timeout)))
    XCTAssertTrue(ErrorRecoveryLayer.isTimeoutError(.transport(.timeoutInPhase(.bulkIn))))
    XCTAssertFalse(ErrorRecoveryLayer.isTimeoutError(.busy))
    XCTAssertFalse(ErrorRecoveryLayer.isTimeoutError(.deviceDisconnected))
  }

  func testIsDisconnectError() {
    XCTAssertTrue(ErrorRecoveryLayer.isDisconnectError(MTPError.deviceDisconnected))
    XCTAssertTrue(ErrorRecoveryLayer.isDisconnectError(MTPError.transport(.noDevice)))
    XCTAssertTrue(ErrorRecoveryLayer.isDisconnectError(TransportError.noDevice))
    XCTAssertFalse(ErrorRecoveryLayer.isDisconnectError(MTPError.timeout))
    XCTAssertFalse(ErrorRecoveryLayer.isDisconnectError(TransportError.timeout))
  }

  // MARK: - Recovery Log

  func testRecoveryLog_TracksRates() async {
    await RecoveryLog.shared.record(RecoveryEvent(
      strategy: "test", attempt: 1, maxAttempts: 3, succeeded: true))
    await RecoveryLog.shared.record(RecoveryEvent(
      strategy: "test", attempt: 2, maxAttempts: 3, succeeded: false,
      errorDescription: "fail"))
    await RecoveryLog.shared.record(RecoveryEvent(
      strategy: "test", attempt: 1, maxAttempts: 1, succeeded: true))

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 2)
    XCTAssertEqual(rates.failures, 1)
  }

  func testRecoveryLog_RecentEvents() async {
    for i in 0..<5 {
      await RecoveryLog.shared.record(RecoveryEvent(
        strategy: "test-\(i)", attempt: 1, maxAttempts: 1, succeeded: true))
    }

    let recent = await RecoveryLog.shared.recent(limit: 3)
    XCTAssertEqual(recent.count, 3)
    XCTAssertEqual(recent[0].strategy, "test-2")
    XCTAssertEqual(recent[2].strategy, "test-4")
  }

  func testRecoveryLog_Clear() async {
    await RecoveryLog.shared.record(RecoveryEvent(
      strategy: "test", attempt: 1, maxAttempts: 1, succeeded: true))
    await RecoveryLog.shared.clear()

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 0)
    XCTAssertEqual(rates.failures, 0)
  }

  // MARK: - Composed Recovery

  func testComposedRecovery_TimeoutEscalationWithStallRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = MutableCounter()
    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000, maxRetries: 2
    ) { timeoutMs in
      try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
        let count = counter.increment()
        if count == 1 {
          throw MTPError.timeout
        }
        return "recovered-at-\(timeoutMs)ms"
      }
    }

    XCTAssertEqual(result, "recovered-at-2000ms")
    XCTAssertEqual(counter.value, 2)
  }
}

// MARK: - Thread-safe helpers for Sendable closures

private final class MutableCounter: @unchecked Sendable {
  private var _value = 0
  private let lock = NSLock()

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return _value
  }

  @discardableResult
  func increment() -> Int {
    lock.lock()
    _value += 1
    let v = _value
    lock.unlock()
    return v
  }
}

private final class MutableArray<T>: @unchecked Sendable {
  private var _items: [T] = []
  private let lock = NSLock()

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _items.count
  }

  var snapshot: [T] {
    lock.lock()
    defer { lock.unlock() }
    return _items
  }

  func append(_ item: T) {
    lock.lock()
    _items.append(item)
    lock.unlock()
  }
}
