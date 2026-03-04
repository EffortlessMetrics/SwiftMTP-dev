// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests for MTP spec alignment: DeviceBusy retry, TransactionCancelled handling, error semantics.
final class SpecAlignmentTests: XCTestCase {

  /// Actor-isolated counter for safe mutation in @Sendable closures.
  private actor AttemptCounter {
    var count = 0
    func increment() -> Int {
      count += 1
      return count
    }
    func value() -> Int { count }
  }

  // MARK: - DeviceBusy (0x2019) Triggers Retry

  func testDeviceBusyIsRetryableInBusyBackoff() async throws {
    let counter = AttemptCounter()
    let result: Int = try await BusyBackoff.onDeviceBusy(retries: 2, baseMs: 10) {
      let attempt = await counter.increment()
      if attempt < 2 {
        throw MTPError.protocolError(code: 0x2019, message: "DeviceBusy")
      }
      return 42
    }
    XCTAssertEqual(result, 42)
    let total = await counter.value()
    XCTAssertEqual(total, 2, "Should have retried once after DeviceBusy")
  }

  func testDeviceBusyExhaustsRetries() async {
    do {
      let _: Int = try await BusyBackoff.onDeviceBusy(retries: 1, baseMs: 10) {
        throw MTPError.protocolError(code: 0x2019, message: "DeviceBusy")
      }
      XCTFail("Should have thrown")
    } catch let error as MTPError {
      if case .protocolError(let code, _) = error {
        XCTAssertEqual(code, 0x2019)
      } else {
        XCTFail("Expected protocolError, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testSessionNotOpenIsRetryableAsNotReady() async throws {
    let counter = AttemptCounter()
    let result: String = try await BusyBackoff.onDeviceBusy(retries: 2, baseMs: 10) {
      let attempt = await counter.increment()
      if attempt < 2 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return "ok"
    }
    XCTAssertEqual(result, "ok")
    let total = await counter.value()
    XCTAssertGreaterThan(total, 1)
  }

  func testNonBusyErrorIsNotRetried() async {
    let counter = AttemptCounter()
    do {
      let _: Int = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10) {
        _ = await counter.increment()
        throw MTPError.protocolError(code: 0x200F, message: "AccessDenied")
      }
      XCTFail("Should have thrown")
    } catch {
      let total = await counter.value()
      XCTAssertEqual(total, 1, "Non-busy errors should not be retried")
    }
  }

  func testMTPBusyErrorIsRetryable() async throws {
    let counter = AttemptCounter()
    let result: Int = try await BusyBackoff.onDeviceBusy(retries: 2, baseMs: 10) {
      let attempt = await counter.increment()
      if attempt < 2 {
        throw MTPError.busy
      }
      return 7
    }
    XCTAssertEqual(result, 7)
    let total = await counter.value()
    XCTAssertEqual(total, 2)
  }

  // MARK: - TransactionCancelled (0x201F) Handling

  func testTransactionCancelledErrorDescription() {
    let error = MTPError.protocolError(code: 0x201F, message: nil)
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("TransactionCancelled"), "Description: \(desc)")
    XCTAssertTrue(desc.contains("0x201F"), "Should contain error code hex: \(desc)")
  }

  func testTransactionCancelledIsNotRetryable() async {
    let counter = AttemptCounter()
    do {
      let _: Int = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10) {
        _ = await counter.increment()
        throw MTPError.protocolError(code: 0x201F, message: "TransactionCancelled")
      }
      XCTFail("Should have thrown")
    } catch {
      let total = await counter.value()
      XCTAssertEqual(total, 1, "TransactionCancelled should not be retried")
    }
  }

  // MARK: - Error Code Names

  func testDeviceBusyErrorHasRecoverySuggestion() {
    let error = MTPError.protocolError(code: 0x2019, message: nil)
    let recovery = error.recoverySuggestion ?? ""
    XCTAssertFalse(recovery.isEmpty, "DeviceBusy should have recovery suggestion")
  }

  func testSessionAlreadyOpenDetection() {
    let error = MTPError.protocolError(code: 0x201E, message: nil)
    XCTAssertTrue(error.isSessionAlreadyOpen)

    let other = MTPError.protocolError(code: 0x2001, message: nil)
    XCTAssertFalse(other.isSessionAlreadyOpen)
  }
}
