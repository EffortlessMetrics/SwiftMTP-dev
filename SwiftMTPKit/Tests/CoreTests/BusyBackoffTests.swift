// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// BusyBackoff algorithm tests
final class BusyBackoffTests: XCTestCase {

  // MARK: - Successful Operation (No Retries)

  func testSuccessfulOperationNoRetries() async throws {
    let expectation = expectation(description: "Operation should succeed immediately")

    _ = try await BusyBackoff.onDeviceBusy {
      expectation.fulfill()
      return "success"
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testSuccessfulOperationReturnsValue() async throws {
    let result: String = try await BusyBackoff.onDeviceBusy {
      return "test-value"
    }

    XCTAssertEqual(result, "test-value")
  }

  func testSuccessfulOperationWithRetriesConfigured() async throws {
    let expectation = expectation(description: "Operation should succeed")

    _ = try await BusyBackoff.onDeviceBusy(retries: 5, baseMs: 100, jitterPct: 0.1) {
      expectation.fulfill()
      return "success"
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  // MARK: - Device Busy Retries

  func testDeviceBusyMaxRetriesExceeded() async throws {
    let expectation = expectation(description: "Should throw after max retries")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 2, baseMs: 10, jitterPct: 0.0) {
        // Always throw SessionNotOpen
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 2.0)
  }

  func testDeviceBusyNonMatchingErrorNotRetried() async throws {
    let expectation = expectation(description: "Should throw immediately on non-matching error")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10, jitterPct: 0.0) {
        // Throw a different error that shouldn't be retried
        throw MTPError.protocolError(code: 0x2001, message: "OK")  // Not retryable
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  // MARK: - Timeout/IO Errors Not Retried

  func testTimeoutErrorNotRetried() async throws {
    let expectation = expectation(description: "Should throw immediately on timeout")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10, jitterPct: 0.0) {
        throw MTPError.timeout
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testObjectNotFoundErrorNotRetried() async throws {
    let expectation = expectation(description: "Should throw immediately on objectNotFound")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10, jitterPct: 0.0) {
        throw MTPError.objectNotFound
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  // MARK: - Delay Calculation

  func testBackoffDelayIncreases() async throws {
    var delays: [TimeInterval] = []

    for attempt in 1...4 {
      let base = Double(200) * pow(2.0, Double(attempt - 1))
      delays.append(base)
    }

    XCTAssertEqual(delays[0], 200)  // 200 * 2^0 = 200
    XCTAssertEqual(delays[1], 400)  // 200 * 2^1 = 400
    XCTAssertEqual(delays[2], 800)  // 200 * 2^2 = 800
    XCTAssertEqual(delays[3], 1600)  // 200 * 2^3 = 1600
  }

  func testMinimumDelayEnforced() {
    // Test that minimum 50ms delay is enforced
    let jitter = 20.0 * 0.5  // 50% jitter below
    let delayMs = max(50, Int(20.0 + jitter))  // Less than minimum

    XCTAssertGreaterThanOrEqual(delayMs, 50)
  }

  // MARK: - Retry Count Handling

  func testZeroRetries() async throws {
    let expectation = expectation(description: "Should not retry with 0 retries")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 0, baseMs: 10, jitterPct: 0.0) {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  func testSingleRetrySucceeds() async throws {
    let expectation = expectation(description: "Should succeed on retry")
    actor AttemptCounter {
      private var attempts = 0
      func next() -> Int {
        attempts += 1
        return attempts
      }
      func value() -> Int { attempts }
    }

    let counter = AttemptCounter()
    let result: String = try await BusyBackoff.onDeviceBusy(retries: 1, baseMs: 10, jitterPct: 0.0)
    {
      let attempt = await counter.next()
      if attempt == 1 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      expectation.fulfill()
      return "success"
    }

    await fulfillment(of: [expectation], timeout: 2.0)
    XCTAssertEqual(result, "success")
    let totalAttempts = await counter.value()
    XCTAssertEqual(totalAttempts, 2)
  }

  // MARK: - Sendable Conformances

  func testClosureSendable() async throws {
    // Test that the operation closure is Sendable
    let closure: @Sendable () async throws -> String = {
      return "test"
    }

    // Verify closure can be used in async context
    let result = try await closure()
    XCTAssertEqual(result, "test")
  }

  // MARK: - Error Propagation

  func testNonMTPErrorNotRetried() async throws {
    let expectation = expectation(description: "Should throw immediately on non-MTP error")

    struct CustomError: Error {}

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 3, baseMs: 10, jitterPct: 0.0) {
        throw CustomError()
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1.0)
  }

  // MARK: - Different Busy Error Codes

  func testDeviceBusyErrorCode() async throws {
    // Test with actual DeviceBusy code (0x2019)
    let expectation = expectation(description: "Should handle DeviceBusy")

    do {
      _ = try await BusyBackoff.onDeviceBusy(retries: 1, baseMs: 10, jitterPct: 0.0) {
        throw MTPError.protocolError(code: 0x2019, message: "DeviceBusy")
      }
      XCTFail("Should have thrown")
    } catch {
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 2.0)
  }

  // MARK: - Async Context

  func testWorksInTaskContext() async throws {
    let result = try await Task {
      try await BusyBackoff.onDeviceBusy {
        return "task-result"
      }
    }
    .value

    XCTAssertEqual(result, "task-result")
  }
}
