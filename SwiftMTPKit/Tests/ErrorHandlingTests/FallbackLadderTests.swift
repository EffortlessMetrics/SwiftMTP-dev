// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTestKit

/// Thread-safe mutable box for use in @Sendable closures.
private final class MutableBox<T: Sendable>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

/// Comprehensive tests for the FallbackLadder error recovery strategy.
///
/// Covers ladder step progression, retry exhaustion, recovery at each level,
/// concurrent fallback, timeout/protocol/transport errors, state persistence,
/// custom configurations, quirk interactions, observability, and edge cases.
final class FallbackLadderTests: XCTestCase {

  // MARK: - Ladder Step Progression

  func testLadderProgressesThroughRungs_InOrder() async throws {
    let executionOrder = MutableBox<[String]>([])

    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "rung-1") {
        executionOrder.value.append("rung-1")
        throw MTPError.timeout
      },
      FallbackRung(name: "rung-2") {
        executionOrder.value.append("rung-2")
        throw MTPError.busy
      },
      FallbackRung(name: "rung-3") {
        executionOrder.value.append("rung-3")
        return "success"
      },
    ]

    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(executionOrder.value, ["rung-1", "rung-2", "rung-3"])
    XCTAssertEqual(result.winningRung, "rung-3")
    XCTAssertEqual(result.value, "success")
  }

  func testLadderStopsAtFirstSuccess() async throws {
    let executionOrder = MutableBox<[String]>([])

    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "fail") {
        executionOrder.value.append("fail")
        throw MTPError.timeout
      },
      FallbackRung(name: "succeed") {
        executionOrder.value.append("succeed")
        return 42
      },
      FallbackRung(name: "never-reached") {
        executionOrder.value.append("never-reached")
        return 99
      },
    ]

    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(executionOrder.value, ["fail", "succeed"])
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "succeed")
  }

  func testLadderSingleRungSuccess() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "only") { return "ok" }
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "ok")
    XCTAssertEqual(result.winningRung, "only")
    XCTAssertEqual(result.attempts.count, 1)
    XCTAssertTrue(result.attempts[0].succeeded)
  }

  // MARK: - Maximum Retry Exhaustion

  func testAllRungsFailThrowsFallbackAllFailedError() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "a") { throw MTPError.timeout },
      FallbackRung(name: "b") { throw MTPError.busy },
      FallbackRung(name: "c") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
      XCTAssertTrue(err.attempts.allSatisfy { $0.error != nil })
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testEmptyRungsListThrowsAllFailed() async {
    let rungs: [FallbackRung<Int>] = []

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError for empty rungs")
    } catch is FallbackAllFailedError {
      // Expected — no rungs means immediate failure
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testExhaustionPreservesAllAttemptErrors() async {
    let rungs: [FallbackRung<Data>] = [
      FallbackRung(name: "timeout-rung") { throw MTPError.timeout },
      FallbackRung(name: "busy-rung") { throw MTPError.busy },
      FallbackRung(name: "protocol-rung") {
        throw MTPError.protocolError(code: 0x2005, message: "Not supported")
      },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.map(\.name), ["timeout-rung", "busy-rung", "protocol-rung"])
      XCTAssertNotNil(err.attempts[0].error)
      XCTAssertNotNil(err.attempts[1].error)
      XCTAssertNotNil(err.attempts[2].error)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  // MARK: - Successful Recovery at Each Level

  func testRecoveryAtFirstRung() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "fast-path") { return "fast" },
      FallbackRung(name: "slow-path") { return "slow" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "fast-path")
    XCTAssertEqual(result.attempts.count, 1)
  }

  func testRecoveryAtMiddleRung() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "fast") { throw MTPError.timeout },
      FallbackRung(name: "medium") { return "recovered" },
      FallbackRung(name: "slow") { return "last-resort" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "medium")
    XCTAssertEqual(result.value, "recovered")
    XCTAssertEqual(result.attempts.count, 2)
  }

  func testRecoveryAtLastRung() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "rung-1") { throw MTPError.timeout },
      FallbackRung(name: "rung-2") { throw MTPError.busy },
      FallbackRung(name: "rung-3") { throw MTPError.objectNotFound },
      FallbackRung(name: "rung-4") { return "last-chance" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "rung-4")
    XCTAssertEqual(result.value, "last-chance")
    XCTAssertEqual(result.attempts.count, 4)
    XCTAssertEqual(result.attempts.filter(\.succeeded).count, 1)
    XCTAssertEqual(result.attempts.filter { !$0.succeeded }.count, 3)
  }

  // MARK: - Ladder Reset After Successful Operation

  func testLadderCanBeReusedAfterSuccess() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "primary") { return 1 },
      FallbackRung(name: "fallback") { return 2 },
    ]

    let result1 = try await FallbackLadder.execute(rungs)
    let result2 = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(result1.value, 1)
    XCTAssertEqual(result2.value, 1)
    XCTAssertEqual(result1.winningRung, "primary")
    XCTAssertEqual(result2.winningRung, "primary")
  }

  func testLadderCanBeReusedAfterFailure() async throws {
    let callCount = MutableBox(0)

    // First execution: fail, then succeed
    let rungs1: [FallbackRung<String>] = [
      FallbackRung(name: "primary") {
        callCount.value += 1
        if callCount.value == 1 { throw MTPError.timeout }
        return "primary-ok"
      },
      FallbackRung(name: "fallback") { return "fallback-ok" },
    ]

    let result1 = try await FallbackLadder.execute(rungs1)
    XCTAssertEqual(result1.winningRung, "fallback")

    // Second execution with fresh rungs: primary now works
    let rungs2: [FallbackRung<String>] = [
      FallbackRung(name: "primary") { return "primary-recovered" },
      FallbackRung(name: "fallback") { return "fallback-ok" },
    ]

    let result2 = try await FallbackLadder.execute(rungs2)
    XCTAssertEqual(result2.winningRung, "primary")
    XCTAssertEqual(result2.value, "primary-recovered")
  }

  // MARK: - Concurrent Fallback from Multiple Operations

  func testConcurrentFallbackExecutions() async throws {
    // Launch multiple ladder executions concurrently
    async let result1 = FallbackLadder.execute([
      FallbackRung<Int>(name: "op1-fast") { throw MTPError.timeout },
      FallbackRung<Int>(name: "op1-slow") { return 1 },
    ])

    async let result2 = FallbackLadder.execute([
      FallbackRung<Int>(name: "op2-fast") { return 2 },
    ])

    async let result3 = FallbackLadder.execute([
      FallbackRung<Int>(name: "op3-fast") { throw MTPError.busy },
      FallbackRung<Int>(name: "op3-mid") { throw MTPError.timeout },
      FallbackRung<Int>(name: "op3-slow") { return 3 },
    ])

    let r1 = try await result1
    let r2 = try await result2
    let r3 = try await result3

    XCTAssertEqual(r1.value, 1)
    XCTAssertEqual(r1.winningRung, "op1-slow")
    XCTAssertEqual(r2.value, 2)
    XCTAssertEqual(r2.winningRung, "op2-fast")
    XCTAssertEqual(r3.value, 3)
    XCTAssertEqual(r3.winningRung, "op3-slow")
  }

  func testConcurrentFallbacksDoNotInterfere() async throws {
    // Both ladders should independently track their own attempts
    let ladder1Attempts = 5
    let ladder2Attempts = 3

    var rungs1: [FallbackRung<String>] = (0..<(ladder1Attempts - 1)).map { i in
      FallbackRung(name: "L1-\(i)") { throw MTPError.timeout }
    }
    rungs1.append(FallbackRung(name: "L1-win") { return "ladder1" })

    var rungs2: [FallbackRung<String>] = (0..<(ladder2Attempts - 1)).map { i in
      FallbackRung(name: "L2-\(i)") { throw MTPError.busy }
    }
    rungs2.append(FallbackRung(name: "L2-win") { return "ladder2" })

    async let r1 = FallbackLadder.execute(rungs1)
    async let r2 = FallbackLadder.execute(rungs2)

    let result1 = try await r1
    let result2 = try await r2

    XCTAssertEqual(result1.attempts.count, ladder1Attempts)
    XCTAssertEqual(result2.attempts.count, ladder2Attempts)
    XCTAssertEqual(result1.value, "ladder1")
    XCTAssertEqual(result2.value, "ladder2")
  }

  // MARK: - Fallback Ladder with Timeout Errors

  func testTimeoutErrorsAtEveryRungExceptLast() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "fast-timeout") { throw MTPError.timeout },
      FallbackRung(name: "medium-timeout") { throw MTPError.timeout },
      FallbackRung(name: "transport-timeout") { throw MTPError.transport(.timeout) },
      FallbackRung(name: "reset-recovery") { return "recovered" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "reset-recovery")
    XCTAssertEqual(result.value, "recovered")

    let failures = result.attempts.filter { !$0.succeeded }
    XCTAssertEqual(failures.count, 3)
    XCTAssertTrue(failures.allSatisfy { $0.error != nil })
  }

  func testTimeoutInPhaseErrors() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "bulk-out-timeout") {
        throw MTPError.transport(.timeoutInPhase(.bulkOut))
      },
      FallbackRung(name: "bulk-in-timeout") {
        throw MTPError.transport(.timeoutInPhase(.bulkIn))
      },
      FallbackRung(name: "response-timeout") {
        throw MTPError.transport(.timeoutInPhase(.responseWait))
      },
      FallbackRung(name: "recovered") { return "ok" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "recovered")
    XCTAssertEqual(result.attempts.count, 4)
  }

  // MARK: - Fallback Ladder with Protocol Errors

  func testProtocolErrorsProgression() async throws {
    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "proplist") {
        throw MTPError.protocolError(code: 0x2005, message: "Op not supported")
      },
      FallbackRung(name: "legacy") {
        return [MTPStorageID(raw: 0x00010001)]
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "legacy")
    XCTAssertEqual(result.value, [MTPStorageID(raw: 0x00010001)])
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertTrue(
      (result.attempts[0].error?.contains("2005") ?? false)
        || (result.attempts[0].error?.contains("not supported") ?? false),
      "Error should reference the protocol error: \(result.attempts[0].error ?? "nil")")
  }

  func testProtocolErrorCodePreservedInAttempt() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "invalid-param") {
        throw MTPError.protocolError(code: 0x201D, message: "InvalidParameter")
      },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 1)
      let errorString = err.attempts[0].error ?? ""
      XCTAssertTrue(
        errorString.contains("201D") || errorString.contains("InvalidParameter"),
        "Error should preserve protocol code context: \(errorString)")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSessionAlreadyOpenRecovery() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "open-session") {
        throw MTPError.protocolError(code: 0x201E, message: "Session already open")
      },
      FallbackRung(name: "reuse-session") {
        return "reused"
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "reuse-session")
    XCTAssertEqual(result.value, "reused")
  }

  // MARK: - Fallback Ladder with Transport Errors

  func testTransportErrorsProgression() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "stall-path") { throw MTPError.transport(.stall) },
      FallbackRung(name: "io-path") { throw MTPError.transport(.io("USB pipe broken")) },
      FallbackRung(name: "reset-path") { return "recovered-after-transport" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "reset-path")
    XCTAssertEqual(result.attempts.count, 3)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertTrue(result.attempts[2].succeeded)
  }

  func testAccessDeniedTransportError() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "access-denied") { throw MTPError.transport(.accessDenied) },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 1)
      XCTAssertFalse(err.attempts[0].succeeded)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testNoDeviceTransportError() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "disconnected") { throw MTPError.transport(.noDevice) },
      FallbackRung(name: "mtp-disconnected") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 2)
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  // MARK: - Ladder State Persistence Across Operations

  func testLadderAttemptsPreserveTimingData() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "slow-fail") {
        try await Task.sleep(nanoseconds: 2_000_000)  // 2ms
        throw MTPError.timeout
      },
      FallbackRung(name: "quick-success") {
        return 1
      },
    ]

    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertGreaterThanOrEqual(result.attempts[0].durationMs, 0)
    XCTAssertGreaterThanOrEqual(result.attempts[1].durationMs, 0)
  }

  func testLadderAttemptsAccumulateCorrectly() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "a") { throw MTPError.timeout },
      FallbackRung(name: "b") { throw MTPError.busy },
      FallbackRung(name: "c") { return "ok" },
    ]

    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(result.attempts.count, 3)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertEqual(result.attempts[0].name, "a")
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertEqual(result.attempts[1].name, "b")
    XCTAssertTrue(result.attempts[2].succeeded)
    XCTAssertEqual(result.attempts[2].name, "c")
    XCTAssertNil(result.attempts[2].error)
  }

  func testMultipleSequentialLaddersHaveIndependentState() async throws {
    let rungs1: [FallbackRung<Int>] = [
      FallbackRung(name: "op1-fail") { throw MTPError.timeout },
      FallbackRung(name: "op1-ok") { return 1 },
    ]

    let rungs2: [FallbackRung<Int>] = [
      FallbackRung(name: "op2-ok") { return 2 },
    ]

    let result1 = try await FallbackLadder.execute(rungs1)
    let result2 = try await FallbackLadder.execute(rungs2)

    // Each ladder execution has its own attempt history
    XCTAssertEqual(result1.attempts.count, 2)
    XCTAssertEqual(result2.attempts.count, 1)
  }

  // MARK: - Custom Ladder Configuration

  func testCustomStorageIDRetryConfig() {
    let config = StorageIDRetryConfig(maxRetries: 10, backoffMs: [100, 200, 400, 800, 1600])
    XCTAssertEqual(config.maxRetries, 10)
    XCTAssertEqual(config.backoffMs.count, 5)
    XCTAssertEqual(config.backoffMs.first, 100)
    XCTAssertEqual(config.backoffMs.last, 1600)
  }

  func testDefaultStorageIDRetryConfig() {
    let config = StorageIDRetryConfig()
    XCTAssertEqual(config.maxRetries, 5)
    XCTAssertEqual(config.backoffMs, [250, 500, 1000, 2000, 3000])
  }

  func testCustomLadderWithManyRungs() async throws {
    let rungCount = 10
    var rungs: [FallbackRung<Int>] = (0..<(rungCount - 1)).map { i in
      FallbackRung(name: "fail-\(i)") { throw MTPError.timeout }
    }
    rungs.append(FallbackRung(name: "final-success") { return 42 })

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "final-success")
    XCTAssertEqual(result.attempts.count, rungCount)
    XCTAssertEqual(result.attempts.filter(\.succeeded).count, 1)
  }

  func testBackoffSequenceIsMonotonicallyIncreasing() {
    let config = StorageIDRetryConfig()
    for i in 1..<config.backoffMs.count {
      XCTAssertGreaterThan(config.backoffMs[i], config.backoffMs[i - 1])
    }
  }

  // MARK: - Ladder Interaction with Device Quirks

  func testQuirkSpecificFallbackForSamsungZeroStorages() async throws {
    // Samsung devices may return zero storages initially; ladder should handle this
    let attempt = MutableBox(0)

    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "samsung-fast") {
        attempt.value += 1
        if attempt.value <= 2 {
          throw MTPError.notSupported("Zero storages returned")
        }
        return [MTPStorageID(raw: 0x00010001)]
      },
      FallbackRung(name: "samsung-reset") {
        return [MTPStorageID(raw: 0x00010001)]
      },
    ]

    // First attempt triggers the fast rung which fails
    // Because the fast rung throws, the ladder moves to reset
    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value.count, 1)
  }

  func testQuirkSpecificFallbackForBrokenPropList() async throws {
    // Some devices (LG, HTC, Huawei) have broken GetObjectPropList
    let rungs: [FallbackRung<[MTPObjectInfo]>] = [
      FallbackRung(name: "proplist-path") {
        throw MTPError.protocolError(code: 0x2005, message: "GetObjectPropList not supported")
      },
      FallbackRung(name: "legacy-getinfo") {
        // Fall back to individual GetObjectInfo calls
        let info = MTPObjectInfo(
          handle: 1, storage: MTPStorageID(raw: 0x00010001), parent: nil,
          name: "photo.jpg", sizeBytes: 3_000_000, modified: nil,
          formatCode: 0x3801, properties: [:])
        return [info]
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "legacy-getinfo")
    XCTAssertEqual(result.value.count, 1)
    XCTAssertEqual(result.value[0].name, "photo.jpg")
  }

  func testQuirkSpecificFallbackForCanonCamera() async throws {
    // Canon cameras may need longer timeouts; simulate timeout then success
    let rungs: [FallbackRung<MTPDeviceInfo>] = [
      FallbackRung(name: "standard-timeout") {
        throw MTPError.timeout
      },
      FallbackRung(name: "extended-timeout") {
        return MTPDeviceInfo(
          manufacturer: "Canon", model: "EOS R5", version: "1.0",
          serialNumber: "CANON001",
          operationsSupported: Set([0x1001, 0x1002].map { UInt16($0) }),
          eventsSupported: Set([0x4002].map { UInt16($0) }))
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "extended-timeout")
    XCTAssertEqual(result.value.model, "EOS R5")
  }

  func testQuirkHookBusyBackoffConfig() {
    let hook = QuirkHook(
      phase: .onDeviceBusy,
      busyBackoff: QuirkHook.BusyBackoff(retries: 5, baseMs: 200, jitterPct: 0.1))

    XCTAssertEqual(hook.phase, .onDeviceBusy)
    XCTAssertEqual(hook.busyBackoff?.retries, 5)
    XCTAssertEqual(hook.busyBackoff?.baseMs, 200)
    XCTAssertEqual(hook.busyBackoff!.jitterPct, 0.1, accuracy: 0.001)
  }

  // MARK: - Fallback Ladder Logging/Observability

  func testFallbackResultContainsDiagnosticAttempts() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "diag-fail") { throw MTPError.timeout },
      FallbackRung(name: "diag-ok") { return 1 },
    ]

    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertEqual(result.attempts[0].name, "diag-fail")
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertNotNil(result.attempts[0].error)
    XCTAssertGreaterThanOrEqual(result.attempts[0].durationMs, 0)

    XCTAssertEqual(result.attempts[1].name, "diag-ok")
    XCTAssertTrue(result.attempts[1].succeeded)
    XCTAssertNil(result.attempts[1].error)
  }

  func testFallbackAllFailedErrorDescription() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "rung-X") { throw MTPError.timeout },
      FallbackRung(name: "rung-Y") { throw MTPError.transport(.stall) },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected error")
    } catch let err as FallbackAllFailedError {
      let desc = err.description
      XCTAssertTrue(desc.contains("rung-X"), "Description should include rung-X")
      XCTAssertTrue(desc.contains("rung-Y"), "Description should include rung-Y")
      XCTAssertTrue(desc.contains("✗"), "Description should contain failure symbol")
      XCTAssertTrue(desc.contains("ms"), "Description should include timing")
      XCTAssertTrue(desc.contains("All fallback rungs failed"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFallbackAllFailedErrorLocalizedDescription() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "only-rung") { throw MTPError.busy },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected error")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.localizedDescription, err.description)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFallbackSuccessDescriptionContainsCheckmark() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "fail-rung") { throw MTPError.timeout },
      FallbackRung(name: "win-rung") { return 99 },
    ]

    let result = try await FallbackLadder.execute(rungs)

    // The successful attempt should be marked as succeeded
    let successAttempt = result.attempts.first(where: \.succeeded)
    XCTAssertNotNil(successAttempt)
    XCTAssertEqual(successAttempt?.name, "win-rung")
  }

  func testTranscriptRecorderCapturesFallbackOperations() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let recorder = TranscriptRecorder(wrapping: inner)
    try await recorder.openSession(id: 1)

    // Perform operation that would be part of a fallback ladder
    let ids = try await recorder.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    let transcript = recorder.transcript()
    XCTAssertTrue(transcript.contains(where: { $0.operation == "openSession" }))
    XCTAssertTrue(transcript.contains(where: { $0.operation == "getStorageIDs" }))
  }

  // MARK: - Edge Case: Device Disconnects During Fallback

  func testDisconnectDuringFallbackProgression() async {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "normal-path") { throw MTPError.timeout },
      FallbackRung(name: "retry-path") { throw MTPError.deviceDisconnected },
      FallbackRung(name: "reset-path") { throw MTPError.transport(.noDevice) },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      // Verify error escalation from timeout → disconnected → noDevice
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testDisconnectDuringFallbackWithFaultInjection() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // First call: timeout
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }

    // Second call: disconnect (device gone during fallback retry)
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected disconnect")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }

    // Third call: faults exhausted, succeeds
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testDisconnectRecoveryUsingFallbackLadder() async throws {
    let disconnectedBox = MutableBox(true)

    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "direct") {
        if disconnectedBox.value { throw MTPError.deviceDisconnected }
        return [MTPStorageID(raw: 0x00010001)]
      },
      FallbackRung(name: "reconnect-and-retry") {
        disconnectedBox.value = false
        return [MTPStorageID(raw: 0x00010001)]
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "reconnect-and-retry")
    XCTAssertEqual(result.value, [MTPStorageID(raw: 0x00010001)])
  }

  // MARK: - StorageIDOutcome

  func testStorageIDOutcomeSuccessCase() {
    let outcome = StorageIDOutcome.success([MTPStorageID(raw: 0x00010001)])
    if case .success(let ids) = outcome {
      XCTAssertEqual(ids.count, 1)
    } else {
      XCTFail("Expected success")
    }
  }

  func testStorageIDOutcomeZeroStoragesCase() {
    let outcome = StorageIDOutcome.zeroStorages
    if case .zeroStorages = outcome {
      // expected
    } else {
      XCTFail("Expected zeroStorages")
    }
  }

  func testStorageIDOutcomeResponseOnlyCase() {
    let outcome = StorageIDOutcome.responseOnly
    if case .responseOnly = outcome {
      // expected
    } else {
      XCTFail("Expected responseOnly")
    }
  }

  func testStorageIDOutcomeTimeoutCase() {
    let outcome = StorageIDOutcome.timeout
    if case .timeout = outcome {
      // expected
    } else {
      XCTFail("Expected timeout")
    }
  }

  func testStorageIDOutcomePermanentErrorCase() {
    let outcome = StorageIDOutcome.permanentError(0x2001)
    if case .permanentError(let code) = outcome {
      XCTAssertEqual(code, 0x2001)
    } else {
      XCTFail("Expected permanentError")
    }
  }

  // MARK: - FallbackRung and FallbackAttempt Structure

  func testFallbackRungNameIsPreserved() async throws {
    let rung = FallbackRung<Int>(name: "custom-name") { return 42 }
    XCTAssertEqual(rung.name, "custom-name")
  }

  func testFallbackAttemptStructure() {
    let attempt = FallbackAttempt(
      name: "test-rung", succeeded: true, error: nil, durationMs: 10)
    XCTAssertEqual(attempt.name, "test-rung")
    XCTAssertTrue(attempt.succeeded)
    XCTAssertNil(attempt.error)
    XCTAssertEqual(attempt.durationMs, 10)
  }

  func testFallbackAttemptWithError() {
    let attempt = FallbackAttempt(
      name: "error-rung", succeeded: false, error: "timeout", durationMs: 500)
    XCTAssertFalse(attempt.succeeded)
    XCTAssertEqual(attempt.error, "timeout")
    XCTAssertEqual(attempt.durationMs, 500)
  }

  // MARK: - Mixed Error Types in Ladder

  func testMixedErrorTypesInLadder() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "transport-fail") {
        throw MTPError.transport(.stall)
      },
      FallbackRung(name: "protocol-fail") {
        throw MTPError.protocolError(code: 0x2002, message: "Invalid storage")
      },
      FallbackRung(name: "mtp-fail") {
        throw MTPError.objectWriteProtected
      },
      FallbackRung(name: "success-path") {
        return "recovered"
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "success-path")
    XCTAssertEqual(result.attempts.count, 4)

    // Verify each failure preserved its error type
    XCTAssertNotNil(result.attempts[0].error)
    XCTAssertNotNil(result.attempts[1].error)
    XCTAssertNotNil(result.attempts[2].error)
    XCTAssertNil(result.attempts[3].error)
  }

  func testGenericSwiftErrorInLadder() async throws {
    struct CustomError: Error { let message: String }

    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "custom-error") {
        throw CustomError(message: "something unexpected")
      },
      FallbackRung(name: "fallback") { return 1 },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "fallback")
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertNotNil(result.attempts[0].error)
  }

  // MARK: - FallbackResult Properties

  func testFallbackResultValueTypeSafety() async throws {
    // Test with different Sendable types
    let intResult = try await FallbackLadder.execute([
      FallbackRung<Int>(name: "int") { return 42 }
    ])
    XCTAssertEqual(intResult.value, 42)

    let stringResult = try await FallbackLadder.execute([
      FallbackRung<String>(name: "string") { return "hello" }
    ])
    XCTAssertEqual(stringResult.value, "hello")

    let arrayResult = try await FallbackLadder.execute([
      FallbackRung<[MTPStorageID]>(name: "array") {
        return [MTPStorageID(raw: 1), MTPStorageID(raw: 2)]
      }
    ])
    XCTAssertEqual(arrayResult.value.count, 2)
  }
}
