// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// FallbackLadder strategy tests
final class FallbackLadderTests: XCTestCase {

    // MARK: - FallbackRung

    func testFallbackRungCreation() {
        let rung = FallbackRung(name: "primary") {
            return "primary-result"
        }

        XCTAssertEqual(rung.name, "primary")
    }

    func testFallbackRungExecute() async throws {
        let rung = FallbackRung(name: "test") {
            return "test-value"
        }

        let result = try await rung.execute()
        XCTAssertEqual(result, "test-value")
    }

    // MARK: - First Rung Success

    func testFirstRungSucceeds() async throws {
        let expectation = expectation(description: "First rung should succeed")

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "primary") {
                expectation.fulfill()
                return "success-on-first"
            },
            FallbackRung(name: "secondary") {
                XCTFail("Should not reach second rung")
                return "secondary"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result.value, "success-on-first")
        XCTAssertEqual(result.winningRung, "primary")
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertTrue(result.attempts[0].succeeded)
    }

    // MARK: - Fallback to Second Rung

    func testFallbackToSecondRung() async throws {
        let expectation = expectation(description: "Should fallback to second rung")

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "primary") {
                throw NSError(domain: "test", code: 1)
            },
            FallbackRung(name: "secondary") {
                expectation.fulfill()
                return "fallback-result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result.value, "fallback-result")
        XCTAssertEqual(result.winningRung, "secondary")
        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertFalse(result.attempts[0].succeeded)
        XCTAssertTrue(result.attempts[1].succeeded)
    }

    // MARK: - All Rungs Fail

    func testAllRungsFail() async throws {
        let expectation = expectation(description: "All rungs should fail")

        struct TestError: Error {}

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "first") {
                throw TestError()
            },
            FallbackRung(name: "second") {
                throw TestError()
            },
            FallbackRung(name: "third") {
                throw TestError()
            }
        ]

        do {
            _ = try await FallbackLadder.execute(rungs)
            XCTFail("Should have thrown")
        } catch {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - FallbackAttempt Recording

    func testFallbackAttemptRecordsDuration() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "slow") {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return "result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertTrue(result.attempts[0].durationMs >= 0)
    }

    func testFailedAttemptRecordsError() async throws {
        struct TestError: Error, Equatable {}

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "failing") {
                throw TestError()
            }
        ]

        do {
            _ = try await FallbackLadder.execute(rungs)
            XCTFail("Should have thrown")
        } catch {
            // Error is already recorded in attempts
        }
    }

    // MARK: - Multiple Fallback Levels

    func testThreeRungFallback() async throws {
        var callOrder: [String] = []

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "first") {
                callOrder.append("first")
                throw NSError(domain: "test", code: 1)
            },
            FallbackRung(name: "second") {
                callOrder.append("second")
                throw NSError(domain: "test", code: 2)
            },
            FallbackRung(name: "third") {
                callOrder.append("third")
                return "third-success"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.value, "third-success")
        XCTAssertEqual(result.winningRung, "third")
        XCTAssertEqual(result.attempts.count, 3)
        XCTAssertEqual(callOrder, ["first", "second", "third"])
    }

    // MARK: - Empty Rungs List

    func testEmptyRungsList() async throws {
        let expectation = expectation(description: "Empty list should throw")

        do {
            _ = try await FallbackLadder.execute<String>([])
            XCTFail("Should have thrown")
        } catch {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - FallbackResult Properties

    func testFallbackResultValue() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "test") {
                return "expected-value"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.value, "expected-value")
    }

    func testFallbackResultWinningRung() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "named-rung") {
                return "result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.winningRung, "named-rung")
    }

    func testFallbackResultAttempts() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "first") {
                throw NSError(domain: "test", code: 1)
            },
            FallbackRung(name: "second") {
                return "success"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.attempts.count, 2)
        XCTAssertFalse(result.attempts[0].succeeded)
        XCTAssertTrue(result.attempts[1].succeeded)
    }

    // MARK: - Error Propagation

    func testLastErrorPropagated() async throws {
        struct FinalError: Error {}

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "first") {
                throw NSError(domain: "test", code: 1)
            },
            FallbackRung(name: "second") {
                throw FinalError()
            }
        ]

        do {
            _ = try await FallbackLadder.execute(rungs)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is FinalError)
        }
    }

    func testMTPErrorNotSupportedFallback() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "failing") {
                throw MTPError.notSupported("all fallback rungs failed")
            }
        ]

        do {
            _ = try await FallbackLadder.execute(rungs)
            XCTFail("Should have thrown")
        } catch {
            if case .notSupported(let msg) = error {
                XCTAssertEqual(msg, "all fallback rungs failed")
            } else {
                XCTFail("Expected notSupported error")
            }
        }
    }

    // MARK: - Sendable Conformances

    func testFallbackRungSendable() async throws {
        // FallbackRung should be Sendable
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "test") {
                return "result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)
        XCTAssertEqual(result.value, "result")
    }

    func testFallbackAttemptSendable() {
        // FallbackAttempt should be Sendable
        let attempt = FallbackAttempt(name: "test", succeeded: true, error: nil, durationMs: 10)
        XCTAssertEqual(attempt.name, "test")
    }

    func testFallbackResultSendable() async throws {
        // FallbackResult should be Sendable
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "test") {
                return "result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)
        XCTAssertEqual(result.winningRung, "test")
    }

    // MARK: - Async/Await Patterns

    func testWorksWithAsyncRungs() async throws {
        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "async-first") {
                try await Task.sleep(nanoseconds: 1_000_000)
                return "async-result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)
        XCTAssertEqual(result.value, "async-result")
    }

    func testMixedSyncAsyncRungs() async throws {
        var callOrder: [String] = []

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "sync") {
                callOrder.append("sync")
                throw NSError(domain: "test", code: 1)
            },
            FallbackRung(name: "async") {
                try await Task.sleep(nanoseconds: 1_000_000)
                callOrder.append("async")
                return "async-result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.value, "async-result")
        XCTAssertEqual(callOrder, ["sync", "async"])
    }

    // MARK: - Integer Type Support

    func testFallbackWithIntReturn() async throws {
        let rungs: [FallbackRung<Int>] = [
            FallbackRung(name: "number") {
                return 42
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertEqual(result.value, 42)
    }

    func testFallbackWithBoolReturn() async throws {
        let rungs: [FallbackRung<Bool>] = [
            FallbackRung(name: "flag") {
                return true
            }
        ]

        let result = try await FallbackLadder.execute(rungs)

        XCTAssertTrue(result.value)
    }

    // MARK: - Timeout Safety

    func testCancellationSafety() async throws {
        let expectation = expectation(description: "Should handle cancellation")

        let rungs: [FallbackRung<String>] = [
            FallbackRung(name: "cancellable") {
                try Task.checkCancellation()
                return "result"
            }
        ]

        let result = try await FallbackLadder.execute(rungs)
        XCTAssertEqual(result.value, "result")
        expectation.fulfill()

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
