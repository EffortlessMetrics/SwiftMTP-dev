// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// End-to-end tests for the full error recovery ladder using ``FallbackLadder``
/// composed with ``ErrorRecoveryLayer`` strategies.
///
/// Recovery ladder (escalation order):
/// 1. **Retry** — simple re-invocation
/// 2. **Stall recovery** — clear endpoint halt via device reset, then retry
/// 3. **Session reset** — close/reopen MTP session, then retry
/// 4. **Handle reopen** — close USB handle, reopen, new session, retry
/// 5. **Reconnect** — full disconnect/reconnect cycle
final class RecoveryLadderE2ETests: XCTestCase {

  override func setUp() async throws {
    await RecoveryLog.shared.clear()
  }

  // MARK: - Ladder Builder

  /// Builds the standard 5-rung recovery ladder.
  private func buildLadder(
    link: any MTPLink,
    operation: @escaping @Sendable () async throws -> [MTPStorageID]
  ) -> [FallbackRung<[MTPStorageID]>] {
    [
      FallbackRung(name: "retry") {
        try await operation()
      },
      FallbackRung(name: "stall-recovery") {
        try await ErrorRecoveryLayer.withStallRecovery(link: link) {
          try await operation()
        }
      },
      FallbackRung(name: "session-reset") {
        try await ErrorRecoveryLayer.withSessionRecovery(link: link, maxRetries: 1) {
          try await operation()
        }
      },
      FallbackRung(name: "handle-reopen") {
        await link.close()
        try await link.openUSBIfNeeded()
        try await link.openSession(id: 1)
        return try await operation()
      },
      FallbackRung(name: "reconnect") {
        await link.close()
        try await link.openUSBIfNeeded()
        try await link.openSession(id: 1)
        return try await operation()
      },
    ]
  }

  // MARK: - Rung 1: Retry Succeeds

  func testLadder_RetrySucceeds_NoEscalation() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let ladder = buildLadder(link: link) {
      try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "retry")
    XCTAssertFalse(result.value.isEmpty)
    XCTAssertEqual(result.attempts.count, 1)
    XCTAssertTrue(result.attempts[0].succeeded)
  }

  // MARK: - Rung 2: Stall Recovery Succeeds

  func testLadder_StallRecovery_ClearsHaltAndRetries() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    // Call 1 (retry rung): stall → fail
    // Call 2 (stall-recovery, first attempt): stall → caught → resetDevice
    // Call 3 (stall-recovery, retry after reset): succeeds
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 2 {
        throw MTPError.transport(.stall)
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "stall-recovery")
    XCTAssertFalse(result.value.isEmpty)
    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertTrue(result.attempts[1].succeeded)
  }

  // MARK: - Rung 3: Session Reset Succeeds

  func testLadder_SessionReset_ClosesAndReopensSession() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    // Call 1 (retry): fails → rung 1 fails
    // Call 2 (stall-recovery): 0x2003 is not stall → passes through → rung 2 fails
    // Call 3 (session-reset, attempt 0): fails → session recoverable → close/reopen
    // Call 4 (session-reset, attempt 1): succeeds
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 3 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
    XCTAssertFalse(result.value.isEmpty)
    XCTAssertEqual(result.attempts.count, 3)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertTrue(result.attempts[2].succeeded)
  }

  // MARK: - Rung 4: Handle Reopen Succeeds

  func testLadder_HandleReopen_ClosesAndReopensUSB() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    // Calls 1–4 fail with SessionNotOpen:
    //   1: retry rung
    //   2: stall-recovery (passes through, not stall)
    //   3: session-reset attempt 0 → close/reopen
    //   4: session-reset attempt 1 → exhausted
    // Call 5: handle-reopen after close+openUSB+openSession → succeeds
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 4 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "handle-reopen")
    XCTAssertFalse(result.value.isEmpty)
    XCTAssertEqual(result.attempts.count, 4)
  }

  // MARK: - Rung 5: Reconnect Succeeds

  func testLadder_Reconnect_FullDisconnectReconnect() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    // Calls 1–5 fail, call 6 (reconnect rung) succeeds
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 5 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "reconnect")
    XCTAssertFalse(result.value.isEmpty)
    XCTAssertEqual(result.attempts.count, 5)
  }

  // MARK: - All Rungs Fail

  func testLadder_AllFailed_ThrowsWithFullHistory() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let ladder = buildLadder(link: link) {
      throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
    }

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 5)
      XCTAssertTrue(error.attempts.allSatisfy { !$0.succeeded })
      let names = error.attempts.map(\.name)
      XCTAssertEqual(
        names, ["retry", "stall-recovery", "session-reset", "handle-reopen", "reconnect"])
      XCTAssertTrue(error.description.contains("All fallback rungs failed"))
    }
  }

  // MARK: - Escalation: Recovery Prevents Further Escalation

  func testEscalation_RecoveryAtRung1_StopsImmediately() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let ladder = buildLadder(link: link) {
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "retry")
    XCTAssertEqual(result.attempts.count, 1, "Should not escalate beyond rung 1")
  }

  func testEscalation_RecoveryAtRung2_StopsAtStallRecovery() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 2 {
        throw MTPError.transport(.stall)
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "stall-recovery")
    XCTAssertEqual(result.attempts.count, 2, "Should stop at rung 2")
  }

  func testEscalation_RecoveryAtRung3_StopsAtSessionReset() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 3 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
    XCTAssertEqual(result.attempts.count, 3, "Should stop at rung 3")
  }

  // MARK: - Composed Recovery: Stall → Session Escalation

  func testComposed_StallThenSession_EscalatesCorrectly() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    // Calls 1–2: stall (retry fails, stall-recovery catches + resets)
    // Call 3: session error (stall-recovery retry fails with non-stall → rung 2 fails)
    // Call 4: session error (session-reset attempt 0 → close/reopen)
    // Call 5: succeeds (session-reset attempt 1)
    let ladder = buildLadder(link: link) {
      let n = counter.increment()
      if n <= 2 {
        throw MTPError.transport(.stall)
      }
      if n <= 4 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
  }

  // MARK: - Timeout-Specific Escalation Path

  func testTimeoutPath_EscalationSucceeds_NoFallback() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let timeoutsRecorded = RecordingArray<Int>()

    let ladder: [FallbackRung<String>] = [
      FallbackRung(name: "timeout-escalation") {
        try await ErrorRecoveryLayer.withTimeoutEscalation(
          initialTimeoutMs: 1_000, maxRetries: 3
        ) { timeoutMs in
          timeoutsRecorded.append(timeoutMs)
          if counter.increment() <= 2 {
            throw MTPError.timeout
          }
          return "recovered"
        }
      },
      FallbackRung(name: "fallback") {
        return "fallback"
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "timeout-escalation")
    XCTAssertEqual(result.value, "recovered")
    XCTAssertEqual(timeoutsRecorded.snapshot, [1_000, 2_000, 4_000])
  }

  func testTimeoutPath_Exhausted_FallsBackToNextRung() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let timeoutAttempts = CallCounter()

    let ladder: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "timeout-escalation") {
        try await ErrorRecoveryLayer.withTimeoutEscalation(
          initialTimeoutMs: 1_000, maxRetries: 2
        ) { (_: Int) -> [MTPStorageID] in
          timeoutAttempts.increment()
          throw MTPError.timeout
        }
      },
      FallbackRung(name: "session-reset") {
        try await ErrorRecoveryLayer.withSessionRecovery(link: link, maxRetries: 1) {
          return try await link.getStorageIDs()
        }
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
    XCTAssertEqual(timeoutAttempts.value, 3, "Should have exhausted 3 timeout attempts")
  }

  func testTimeoutPath_TransportTimeout_Escalates() async throws {
    let counter = CallCounter()
    let timeoutsRecorded = RecordingArray<Int>()

    let ladder: [FallbackRung<String>] = [
      FallbackRung(name: "timeout-escalation") {
        try await ErrorRecoveryLayer.withTimeoutEscalation(
          initialTimeoutMs: 2_000, maxRetries: 2
        ) { timeoutMs in
          timeoutsRecorded.append(timeoutMs)
          if counter.increment() <= 1 {
            throw MTPError.transport(.timeout)
          }
          return "recovered"
        }
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.value, "recovered")
    XCTAssertEqual(timeoutsRecorded.snapshot, [2_000, 4_000])
  }

  // MARK: - Disconnect-Specific Path

  func testDisconnectPath_EscalatesThroughAllRungs() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let ladder = buildLadder(link: link) {
      throw MTPError.deviceDisconnected
    }

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError on disconnect")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 5)
      XCTAssertTrue(error.attempts.allSatisfy { !$0.succeeded })
      for attempt in error.attempts {
        XCTAssertNotNil(attempt.error)
        XCTAssertTrue(attempt.error!.contains("deviceDisconnected"))
      }
    }
  }

  func testDisconnectPath_HandleDisconnectIntegration() async throws {
    let disconnected = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.deviceDisconnected,
      journal: nil,
      transferId: nil
    )
    XCTAssertTrue(disconnected, "Should detect device disconnection")

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.failures, 1, "Disconnect should be recorded as failure")
  }

  func testDisconnectPath_TransportNoDevice_EscalatesAll() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let ladder = buildLadder(link: link) {
      throw MTPError.transport(.noDevice)
    }

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 5)
    }
  }

  // MARK: - Session Error Variants

  func testSessionAlreadyOpen_RecoveredBySessionReset() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 3 {
        throw MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
  }

  func testSessionBusy_RecoveredBySessionReset() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 3 {
        throw MTPError.sessionBusy
      }
      return try await link.getStorageIDs()
    }

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "session-reset")
  }

  // MARK: - Recovery Log Integration

  func testRecoveryLog_RecordsStallRecoverySuccess() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 2 {
        throw MTPError.transport(.stall)
      }
      return try await link.getStorageIDs()
    }

    _ = try await FallbackLadder.execute(ladder)

    let rates = await RecoveryLog.shared.rates()
    XCTAssertGreaterThanOrEqual(rates.successes, 1)
  }

  func testRecoveryLog_RecordsSessionRecoverySuccess() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let counter = CallCounter()
    let ladder = buildLadder(link: link) {
      if counter.increment() <= 3 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await link.getStorageIDs()
    }

    _ = try await FallbackLadder.execute(ladder)

    let rates = await RecoveryLog.shared.rates()
    XCTAssertGreaterThanOrEqual(rates.successes, 1)
  }

  // MARK: - Concurrent Recovery

  func testConcurrentRecovery_IndependentLadders() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    // Pre-build 5 independent ladders with per-task counters
    let ladders: [[FallbackRung<[MTPStorageID]>]] = (0..<5).map { _ in
      let counter = CallCounter()
      return self.buildLadder(link: link) {
        if counter.increment() <= 1 {
          throw MTPError.transport(.stall)
        }
        return try await link.getStorageIDs()
      }
    }

    try await withThrowingTaskGroup(of: FallbackResult<[MTPStorageID]>.self) { group in
      for ladder in ladders {
        group.addTask {
          try await FallbackLadder.execute(ladder)
        }
      }

      var results: [FallbackResult<[MTPStorageID]>] = []
      for try await result in group {
        results.append(result)
      }

      XCTAssertEqual(results.count, 5)
      for result in results {
        XCTAssertFalse(result.value.isEmpty, "Each task should recover")
      }
    }
  }

  func testConcurrentRecovery_MixedRecoveryLevels() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    let outcomes = RecordingArray<String>()

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Task 1: succeeds immediately (rung 1)
      group.addTask {
        let ladder: [FallbackRung<String>] = [
          FallbackRung(name: "retry") { "immediate" },
        ]
        let result = try await FallbackLadder.execute(ladder)
        outcomes.append(result.winningRung)
      }

      // Task 2: needs stall recovery (rung 2)
      group.addTask {
        let counter = CallCounter()
        let ladder: [FallbackRung<String>] = [
          FallbackRung(name: "retry") {
            if counter.increment() <= 1 { throw MTPError.transport(.stall) }
            return "retried"
          },
          FallbackRung(name: "stall-recovery") {
            try await ErrorRecoveryLayer.withStallRecovery(link: link) {
              return "stall-fixed"
            }
          },
        ]
        let result = try await FallbackLadder.execute(ladder)
        outcomes.append(result.winningRung)
      }

      // Task 3: needs session reset (rung 3)
      group.addTask {
        let counter = CallCounter()
        let ladder: [FallbackRung<String>] = [
          FallbackRung(name: "retry") {
            throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
          },
          FallbackRung(name: "session-reset") {
            try await ErrorRecoveryLayer.withSessionRecovery(link: link, maxRetries: 1) {
              if counter.increment() <= 1 {
                throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
              }
              return "session-fixed"
            }
          },
        ]
        let result = try await FallbackLadder.execute(ladder)
        outcomes.append(result.winningRung)
      }

      for try await _ in group {}
    }

    XCTAssertEqual(outcomes.snapshot.sorted(), ["retry", "session-reset", "stall-recovery"])
  }

  // MARK: - FallbackAttempt History

  func testHistory_DurationTracking() async throws {
    let ladder: [FallbackRung<String>] = [
      FallbackRung(name: "slow-fail") {
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        throw MTPError.timeout
      },
      FallbackRung(name: "fast-succeed") {
        return "done"
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertGreaterThanOrEqual(result.attempts[0].durationMs, 0)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertTrue(result.attempts[1].succeeded)
  }

  func testHistory_ErrorDescriptionsPreserved() async throws {
    let ladder: [FallbackRung<String>] = [
      FallbackRung(name: "stall") {
        throw MTPError.transport(.stall)
      },
      FallbackRung(name: "timeout") {
        throw MTPError.timeout
      },
      FallbackRung(name: "session") {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      },
    ]

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 3)
      for attempt in error.attempts {
        XCTAssertNotNil(attempt.error)
        XCTAssertFalse(attempt.error!.isEmpty)
      }
    }
  }

  // MARK: - Edge Cases

  func testEdge_EmptyLadder_ThrowsAllFailed() async throws {
    let ladder: [FallbackRung<String>] = []

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError for empty ladder")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 0)
    }
  }

  func testEdge_SingleRungSuccess() async throws {
    let ladder: [FallbackRung<Int>] = [
      FallbackRung(name: "only") { 42 },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "only")
    XCTAssertEqual(result.attempts.count, 1)
  }

  func testEdge_SingleRungFailure() async throws {
    let ladder: [FallbackRung<Int>] = [
      FallbackRung(name: "only") { throw MTPError.timeout },
    ]

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 1)
      XCTAssertEqual(error.attempts[0].name, "only")
    }
  }

  func testEdge_NonMTPError_PassesThroughRungs() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)

    struct CustomError: Error {}

    let ladder = buildLadder(link: link) {
      throw CustomError()
    }

    do {
      _ = try await FallbackLadder.execute(ladder)
      XCTFail("Expected FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 5)
      XCTAssertTrue(error.attempts.allSatisfy { !$0.succeeded })
    }
  }

  // MARK: - FaultInjectingLink Integration

  func testFaultInjection_TimeoutOnGetStorageIDs() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getStorageIDs),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await faultyLink.openSession(id: 1)

    // First call throws TransportError.timeout, second succeeds
    let ladder: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "first-try") {
        try await faultyLink.getStorageIDs()
      },
      FallbackRung(name: "second-try") {
        try await faultyLink.getStorageIDs()
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "second-try")
    XCTAssertFalse(result.value.isEmpty)
  }

  func testFaultInjection_PipeStallThenRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .pipeStall(on: .getObjectHandles),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await faultyLink.openSession(id: 1)

    let storageIDs = try await faultyLink.getStorageIDs()
    guard let storageID = storageIDs.first else {
      XCTFail("Expected at least one storage ID")
      return
    }

    // First getObjectHandles fails (pipe stall fault), second succeeds
    let ladder: [FallbackRung<[MTPObjectHandle]>] = [
      FallbackRung(name: "direct") {
        try await faultyLink.getObjectHandles(storage: storageID, parent: nil)
      },
      FallbackRung(name: "after-reset") {
        try await faultyLink.resetDevice()
        return try await faultyLink.getObjectHandles(storage: storageID, parent: nil)
      },
    ]

    let result = try await FallbackLadder.execute(ladder)
    XCTAssertEqual(result.winningRung, "after-reset")
  }
}

// MARK: - Thread-Safe Test Helpers

private final class CallCounter: @unchecked Sendable {
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

private final class RecordingArray<T>: @unchecked Sendable {
  private var _items: [T] = []
  private let lock = NSLock()

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
