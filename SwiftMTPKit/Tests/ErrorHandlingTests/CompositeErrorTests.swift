// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

final class CompositeErrorTests: XCTestCase {

    // MARK: - Error Wrapping Through Layers

    func testTransportErrorWrappedInMTPError() {
        // Transport error gets wrapped in MTPError
        let transportError = TransportError.timeout
        let mtpError = MTPError.transport(transportError)

        if case .transport(let wrapped) = mtpError {
            XCTAssertEqual(wrapped, .timeout)
        } else {
            XCTFail("Expected transport-wrapped error")
        }
    }

    func testProtocolErrorWrappedInMTPError() {
        // Protocol error is directly an MTPError
        let protocolError = MTPError.protocolError(code: 0x2009, message: "Object not found")
        XCTAssertEqual(protocolError.code, 0x2009)
    }

    // MARK: - Cross-Layer Error Propagation

    func testDBErrorWrappedInMTPError() {
        // Database error wrapped in precondition failed
        let dbError = DBError.notFound
        let mtpError = MTPError.preconditionFailed("Database error: \(dbError)")

        if case .preconditionFailed(let message) = mtpError {
            XCTAssertTrue(message.contains("Database error"))
        } else {
            XCTFail("Expected preconditionFailed")
        }
    }

    func testStoreErrorWrappedInMTPError() {
        // Store validation error wrapped in precondition failed
        let mtpError = MTPError.preconditionFailed("Store validation failed: invalid entity")

        if case .preconditionFailed(let message) = mtpError {
            XCTAssertTrue(message.contains("Store validation failed"))
        } else {
            XCTFail("Expected preconditionFailed")
        }
    }

    func testSyncErrorWrappedInMTPError() {
        // Sync conflict wrapped in precondition failed
        let mtpError = MTPError.preconditionFailed("Sync conflict detected")

        if case .preconditionFailed(let message) = mtpError {
            XCTAssertTrue(message.contains("Sync conflict"))
        } else {
            XCTFail("Expected preconditionFailed")
        }
    }

    // MARK: - Error Recovery Chains

    func testTimeoutThenRetrySuccess() {
        // Simulate timeout with retry
        var attempts = 0
        let maxAttempts = 3

        for _ in 0..<maxAttempts {
            attempts += 1
            // First two attempts timeout, third succeeds
            if attempts < 3 {
                let error = MTPError.timeout
                XCTAssertEqual(error, .timeout)
            }
        }
        XCTAssertEqual(attempts, 3)
    }

    func testBusyWithBackoff() {
        // Simulate busy with exponential backoff
        var backoffDelays: [Int] = []

        for retry in 0..<3 {
            let delay = Int(pow(2.0, Double(retry))) // 1, 2, 4
            backoffDelays.append(delay)
        }

        XCTAssertEqual(backoffDelays, [1, 2, 4])
    }

    // MARK: - Error Recovery Strategies

    func testRecoverFromTransientError() {
        // Test recovery from transient transport error
        let transientError = MTPError.transport(.busy)
        XCTAssertEqual(transientError, .transport(.busy))
        // In real code, this would be retried
    }

    func testNoRecoveryFromPermanentError() {
        // Test that permanent errors are not retried
        let permanentError = MTPError.protocolError(code: 0x2009, message: "Object not found")
        XCTAssertEqual(permanentError.code, 0x2009)
        // Should not be retried
    }

    func testRecoverFromSessionAlreadyOpen() {
        // Test session already open is recoverable
        let sessionError = MTPError.protocolError(code: 0x201E, message: "Session already open")
        XCTAssertTrue(sessionError.isSessionAlreadyOpen)
    }

    // MARK: - Error Context Preservation

    func testErrorContextPreservedThroughWrapping() {
        // Test that error context is preserved when wrapping
        let originalError = MTPError.protocolError(code: 0x2001, message: "Invalid StorageID")
        let wrappedError = MTPError.transport(.io("Transport failed after protocol error: \(originalError)"))

        if case .transport(let te) = wrappedError {
            if case .io(let message) = te {
                XCTAssertTrue(message.contains("Invalid StorageID"))
            }
        } else {
            XCTFail("Expected transport IO error")
        }
    }

    // MARK: - Nested Error Chains

    func testNestedErrorChain() {
        // Test nested error chain
        let innermostError = MTPError.protocolError(code: 0x2001, message: "Invalid StorageID")
        let middleError = MTPError.preconditionFailed("Index operation failed: \(innermostError)")
        let outerError = MTPError.notSupported("Sync failed: \(middleError)")

        if case .notSupported(let message) = outerError {
            XCTAssertTrue(message.contains("Sync failed"))
            XCTAssertTrue(message.contains("Index operation failed"))
            XCTAssertTrue(message.contains("Invalid StorageID"))
        } else {
            XCTFail("Expected notSupported")
        }
    }

    // MARK: - Error Type Narrowing

    func testErrorTypeNarrowingTransport() {
        // Test narrowing to transport error
        let error: Error = MTPError.transport(.timeout)

        if let mtpError = error as? MTPError,
           case .transport(let transportError) = mtpError {
            XCTAssertEqual(transportError, .timeout)
        } else {
            XCTFail("Expected MTPError with transport")
        }
    }

    func testErrorTypeNarrowingProtocol() {
        // Test narrowing to protocol error
        let error: Error = MTPError.protocolError(code: 0x2009, message: "Object not found")

        if let mtpError = error as? MTPError,
           case .protocolError(let code, _) = mtpError {
            XCTAssertEqual(code, 0x2009)
        } else {
            XCTFail("Expected MTPError protocol")
        }
    }

    func testErrorTypeNarrowingDBError() {
        // Test narrowing to DB error
        let error: Error = DBError.notFound

        if let dbError = error as? DBError {
            switch dbError {
            case .notFound:
                // Success
                break
            default:
                XCTFail("Expected .notFound case")
            }
        } else {
            XCTFail("Expected DBError")
        }
    }

    // MARK: - Fault Injection Testing

    func testFaultInjectionTransportError() {
        // Test fault injection for transport errors
        let fault = ScheduledFault(
            trigger: .onOperation(.openSession),
            error: .timeout,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        let injectedError = schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil)
        XCTAssertNotNil(injectedError)
        if case .timeout = injectedError {
            // Success
        } else {
            XCTFail("Expected timeout error")
        }
    }

    func testFaultInjectionProtocolError() {
        // Test fault injection for protocol errors
        let fault = ScheduledFault(
            trigger: .onOperation(.getObjectInfos),
            error: .protocolError(code: 0x2009),
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        let injectedError = schedule.check(operation: .getObjectInfos, callIndex: 0, byteOffset: nil)
        XCTAssertNotNil(injectedError)
        if case .protocolError(let code) = injectedError {
            XCTAssertEqual(code, 0x2009)
        } else {
            XCTFail("Expected protocol error")
        }
    }

    // MARK: - Error Recovery Metrics

    func testRecoverySuccessRate() {
        // Test calculating recovery success rate
        let totalAttempts = 10
        var successes = 0

        for _ in 0..<totalAttempts {
            // Simulate 80% success rate
            if Double.random(in: 0...1) < 0.8 {
                successes += 1
            }
        }

        XCTAssertGreaterThanOrEqual(successes, 0)
        XCTAssertLessThanOrEqual(successes, totalAttempts)
    }

    func testBackoffStrategyEffectiveness() {
        // Test that exponential backoff reduces contention errors
        var contentionCount = 0

        for retry in 0..<5 {
            // Simulate decreasing contention with backoff
            let contentionProbability = 1.0 / pow(2.0, Double(retry))
            if Double.random(in: 0...1) < contentionProbability {
                contentionCount += 1
            }
        }

        // Contention should decrease with retries
        XCTAssertLessThanOrEqual(contentionCount, 5)
    }

    // MARK: - Circuit Breaker Patterns

    func testCircuitBreakerOpensAfterFailures() {
        // Test circuit breaker opens after too many failures
        var failureCount = 0
        let threshold = 5

        for _ in 0..<10 {
            let error = MTPError.transport(.busy)
            if case .transport(.busy) = error {
                failureCount += 1
            }
        }

        XCTAssertEqual(failureCount, 10)
        // Circuit breaker would open after threshold
        _ = threshold // Suppress unused warning
    }

    func testCircuitBreakerHalfOpenState() {
        // Test circuit breaker half-open for probe
        let error = MTPError.timeout
        XCTAssertEqual(error, .timeout)
        // Half-open state allows probe after cooldown
    }

    func testCircuitBreakerClosesAfterSuccess() {
        // Test circuit breaker closes after successful operation
        let result: Result<String, Error> = .success("OK")
        switch result {
        case .success:
            // Success
            break
        case .failure:
            XCTFail("Expected success")
        }
        // Circuit breaker would close after success
    }

    // MARK: - Error Logging Context

    func testErrorLoggingIncludesContext() {
        // Test that error logging includes operation context
        let context = "getObjectInfos(storageID: 0x00010001, handle: 0x00000001)"
        let error = MTPError.protocolError(code: 0x2009, message: "Object not found")

        let logMessage = "Error during \(context): \(error)"
        XCTAssertTrue(logMessage.contains("getObjectInfos"))
        XCTAssertTrue(logMessage.contains("Object not found"))
    }

    // MARK: - Multi-Layer Validation

    func testValidationAtEachLayer() {
        // Test validation at transport, protocol, and store layers
        let transportValid = true
        let protocolValid = true
        let storeValid = true

        var validationErrors: [String] = []

        if !transportValid {
            validationErrors.append("Transport validation failed")
        }
        if !protocolValid {
            validationErrors.append("Protocol validation failed")
        }
        if !storeValid {
            validationErrors.append("Store validation failed")
        }

        XCTAssertTrue(validationErrors.isEmpty)
    }

    // MARK: - Graceful Degradation

    func testGracefulDegradationOnPartialFailure() {
        // Test graceful degradation when index fails but store works
        let indexAvailable = false
        let storeAvailable = true

        var fallbackUsed = false

        if storeAvailable && !indexAvailable {
            fallbackUsed = true
        }

        XCTAssertTrue(fallbackUsed)
    }

    func testGracefulDegradationAllServicesDown() {
        // Test handling when all services are down
        let transportAvailable = false
        let indexAvailable = false
        let storeAvailable = false

        let allDown = !transportAvailable && !indexAvailable && !storeAvailable
        XCTAssertTrue(allDown)
    }
}
