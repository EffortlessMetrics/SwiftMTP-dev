// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Tests for multi-level error propagation chains, concurrent error handling,
/// retry exhaustion, error classification, observability integration,
/// user-facing message generation, and timeout→disconnect→cleanup sequences.
final class ErrorPropagationChainTests: XCTestCase {

  // MARK: - 1) Error Chain Depth (wrap → wrap → catch preserves original)

  func testThreeLevelErrorChainPreservesOriginal() {
    let original = TransportError.io("USB bulk transfer failed")
    let level1 = MTPError.transport(original)
    let level2 = MTPError.preconditionFailed("Transfer layer: \(level1)")
    let level3: Error = level2

    guard case .preconditionFailed(let msg) = level3 as? MTPError else {
      XCTFail("Expected preconditionFailed at top level")
      return
    }
    XCTAssertTrue(
      msg.contains("USB bulk transfer failed"), "Original message must survive 3-level chain")
    XCTAssertTrue(msg.contains("Transfer layer"), "Intermediate context must survive")
  }

  func testFourLevelErrorChainPreservesAllLayers() {
    let transport = TransportError.timeoutInPhase(.bulkIn)
    let mtp = MTPError.transport(transport)
    let wrapped = MTPError.preconditionFailed(
      "Sync failed: \(mtp.errorDescription ?? String(describing: mtp))")
    let outer = MTPError.notSupported("Operation aborted: \(wrapped)")

    guard case .notSupported(let msg) = outer else {
      XCTFail("Expected notSupported")
      return
    }
    XCTAssertTrue(msg.contains("bulk-in"), "Transport phase must propagate to outermost layer")
    XCTAssertTrue(msg.contains("Sync failed"), "Mid-layer context preserved")
    XCTAssertTrue(msg.contains("Operation aborted"), "Outer context preserved")
  }

  func testErrorChainViaGenericErrorCasting() {
    let innermost = TransportError.stall
    let device = MTPError.transport(innermost)
    let api: Error = device

    // Narrow Error → MTPError → TransportError
    guard let mtpErr = api as? MTPError,
      case .transport(let transportErr) = mtpErr
    else {
      XCTFail("Could not narrow through chain")
      return
    }
    XCTAssertEqual(transportErr, .stall)
  }

  func testErrorDescriptionChainIntegrity() {
    let inner = TransportError.accessDenied
    let mtp = MTPError.transport(inner)
    // MTPError.transport delegates errorDescription to inner TransportError
    XCTAssertEqual(mtp.errorDescription, inner.errorDescription)
    // Actionable description also delegates
    XCTAssertEqual(mtp.actionableDescription, inner.actionableDescription)
  }

  // MARK: - 2) Concurrent Error Handling

  func testConcurrentOperationsCollectDistinctErrors() async throws {
    let errors = await withTaskGroup(of: MTPError.self, returning: [MTPError].self) { group in
      let errorCases: [MTPError] = [
        .timeout, .busy, .deviceDisconnected, .storageFull, .objectNotFound,
      ]
      for err in errorCases {
        group.addTask { err }
      }
      var collected: [MTPError] = []
      for await err in group { collected.append(err) }
      return collected
    }
    XCTAssertEqual(errors.count, 5, "All concurrent errors must be collected")
    XCTAssertTrue(errors.contains(.timeout))
    XCTAssertTrue(errors.contains(.busy))
    XCTAssertTrue(errors.contains(.deviceDisconnected))
  }

  func testConcurrentFaultInjectionsOnSeparateLinks() async throws {
    // Two independent links with different faults must not interfere
    let inner1 = VirtualMTPLink(config: .pixel7)
    let sched1 = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1)
    ])
    let link1 = FaultInjectingLink(wrapping: inner1, schedule: sched1)
    try await link1.openSession(id: 1)

    let inner2 = VirtualMTPLink(config: .pixel7)
    let sched2 = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 1)
    ])
    let link2 = FaultInjectingLink(wrapping: inner2, schedule: sched2)
    try await link2.openSession(id: 2)

    // link1: getStorageIDs fails with timeout, getDeviceInfo succeeds
    do {
      _ = try await link1.getStorageIDs()
      XCTFail("Expected timeout on link1")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
    let info1 = try await link1.getDeviceInfo()
    XCTAssertEqual(info1.model, "Pixel 7")

    // link2: getDeviceInfo fails with busy, getStorageIDs succeeds
    do {
      _ = try await link2.getDeviceInfo()
      XCTFail("Expected busy on link2")
    } catch let err as TransportError {
      XCTAssertEqual(err, .busy)
    }
    let ids2 = try await link2.getStorageIDs()
    XCTAssertFalse(ids2.isEmpty)
  }

  func testTaskGroupFirstErrorWins() async throws {
    // Verify the first error from a task group can be captured
    let firstError: MTPError? = await withTaskGroup(of: MTPError?.self) { group in
      group.addTask { MTPError.timeout }
      group.addTask { nil }  // success
      group.addTask { MTPError.busy }

      for await result in group {
        if let err = result { return err }
      }
      return nil
    }
    XCTAssertNotNil(firstError, "Should capture at least one error")
  }

  // MARK: - 3) Error Recovery with Retry Exhaustion

  func testRetryExhaustionThrowsLastError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 10)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let maxRetries = 3
    var lastError: TransportError?
    var retryCount = 0

    for _ in 0..<maxRetries {
      do {
        _ = try await link.getStorageIDs()
        break
      } catch let err as TransportError {
        lastError = err
        retryCount += 1
      }
    }

    XCTAssertEqual(retryCount, maxRetries, "All retries must be exhausted")
    XCTAssertEqual(lastError, .busy, "Last error must be preserved")
  }

  func testFallbackLadderAllRungsExhausted_CarriesHistory() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "fast") { throw MTPError.timeout },
      FallbackRung(name: "medium") { throw MTPError.busy },
      FallbackRung(name: "slow") { throw MTPError.sessionBusy },
      FallbackRung(name: "reset") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 4, "All 4 rungs must be attempted")
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
      XCTAssertTrue(err.attempts.allSatisfy { $0.error != nil })
      // Verify the errors are recorded in order
      XCTAssertTrue(
        err.attempts[0].error?.contains("timeout") ?? false,
        "First rung error: \(err.attempts[0].error ?? "nil")")
      XCTAssertTrue(
        err.attempts[3].error?.lowercased().contains("disconnect") ?? false,
        "Last rung error: \(err.attempts[3].error ?? "nil")")
    }
  }

  func testRetryWithEscalatingErrors() async throws {
    // Simulate: busy → timeout → disconnected (escalating severity)
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var errors: [TransportError] = []
    for _ in 0..<3 {
      do {
        _ = try await link.getStorageIDs()
      } catch let err as TransportError {
        errors.append(err)
      }
    }

    XCTAssertEqual(errors, [.busy, .timeout, .noDevice], "Errors should escalate in severity")
  }

  // MARK: - 4) Error Logging and Observability Integration

  func testTransactionLogCapturesErrorChain() async {
    let log = TransactionLog()
    let chainedDesc = "Transport timeout during bulk-in phase of GetObject"

    let record = TransactionRecord(
      txID: 42,
      opcode: 0x1009,
      opcodeLabel: MTPOpcodeLabel.label(for: 0x1009),
      sessionID: 1,
      startedAt: Date(),
      duration: 5.0,
      bytesIn: 0,
      bytesOut: 0,
      outcomeClass: .timeout,
      errorDescription: chainedDesc
    )
    await log.append(record)

    let recent = await log.recent(limit: 1)
    XCTAssertEqual(recent.count, 1)
    XCTAssertEqual(recent[0].outcomeClass, .timeout)
    XCTAssertEqual(recent[0].errorDescription, chainedDesc)
    XCTAssertEqual(recent[0].opcodeLabel, "GetObject")
  }

  func testTransactionLogMultipleErrorOutcomesInSequence() async {
    let log = TransactionLog()
    let entries: [(TransactionOutcome, String)] = [
      (.timeout, "Phase 1 timeout"),
      (.ioError, "Retry I/O failure"),
      (.deviceError, "Device rejected after retry"),
    ]

    for (i, entry) in entries.enumerated() {
      let rec = TransactionRecord(
        txID: UInt32(i + 1),
        opcode: 0x1004,
        opcodeLabel: MTPOpcodeLabel.label(for: 0x1004),
        sessionID: 1,
        startedAt: Date(),
        duration: Double(i) * 0.5,
        bytesIn: 0,
        bytesOut: 0,
        outcomeClass: entry.0,
        errorDescription: entry.1
      )
      await log.append(rec)
    }

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 3)
    XCTAssertEqual(recent.map(\.outcomeClass), [.timeout, .ioError, .deviceError])
  }

  func testActionableDescriptionFallbackForNonActionableError() {
    // Non-ActionableError still gets a description via LocalizedError fallback
    struct CustomError: LocalizedError {
      var errorDescription: String? { "Custom localized message" }
    }
    let desc = actionableDescription(for: CustomError())
    XCTAssertEqual(desc, "Custom localized message")
  }

  // MARK: - 5) User-Facing Error Message Generation

  func testUserFacingMessages_AllMTPErrors() {
    let expectations: [(MTPError, String)] = [
      (.deviceDisconnected, "Reconnect"),
      (.permissionDenied, "System Settings"),
      (.timeout, "timed out"),
      (.busy, "File Transfer"),
      (.storageFull, "full"),
      (.objectNotFound, "not found"),
      (.objectWriteProtected, "write-protected"),
      (.readOnly, "read-only"),
      (.sessionBusy, "already in progress"),
      (.verificationFailed(expected: 100, actual: 50), "corrupted"),
    ]

    for (error, substring) in expectations {
      let msg = error.actionableDescription
      XCTAssertTrue(
        msg.localizedCaseInsensitiveContains(substring),
        "Actionable message for \(error) should contain '\(substring)', got '\(msg)'"
      )
    }
  }

  func testUserFacingMessages_AllTransportErrors() {
    let expectations: [(TransportError, String)] = [
      (.noDevice, "File Transfer"),
      (.timeout, "timed out"),
      (.busy, "busy"),
      (.accessDenied, "denied"),
      (.stall, "stall"),
      (.io("pipe reset"), "pipe reset"),
      (.timeoutInPhase(.bulkOut), "bulk-out"),
    ]

    for (error, substring) in expectations {
      let msg = error.actionableDescription
      XCTAssertTrue(
        msg.localizedCaseInsensitiveContains(substring),
        "Actionable message for \(error) should contain '\(substring)', got '\(msg)'"
      )
    }
  }

  func testUserFacingMessages_ProtocolErrorWithRecovery() {
    let error = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertNotNil(error.recoverySuggestion)
    XCTAssertTrue(error.recoverySuggestion?.contains("writable folder") ?? false)
    XCTAssertNotNil(error.failureReason)
    XCTAssertTrue(error.failureReason?.contains("rejected") ?? false)
  }

  // MARK: - 6) Error Classification (transient vs permanent)

  func testTransientErrorClassification() {
    let transient: [MTPError] = [
      .timeout, .busy, .sessionBusy,
      .transport(.timeout), .transport(.busy),
      .transport(.timeoutInPhase(.bulkIn)),
      .transport(.timeoutInPhase(.bulkOut)),
      .transport(.timeoutInPhase(.responseWait)),
    ]
    for err in transient {
      XCTAssertTrue(classifyError(err) == .transient, "\(err) should be transient")
    }
  }

  func testPermanentErrorClassification() {
    let permanent: [MTPError] = [
      .deviceDisconnected, .permissionDenied, .objectNotFound,
      .objectWriteProtected, .storageFull, .readOnly,
      .notSupported("x"),
      .protocolError(code: 0x2009, message: nil),
      .verificationFailed(expected: 100, actual: 50),
      .transport(.noDevice), .transport(.accessDenied), .transport(.stall),
    ]
    for err in permanent {
      XCTAssertTrue(classifyError(err) == .permanent, "\(err) should be permanent")
    }
  }

  func testErrorClassificationDrivesRetryDecision() {
    // Transient → should retry
    let transient = MTPError.busy
    XCTAssertTrue(shouldRetry(transient))

    // Permanent → should not retry
    let permanent = MTPError.objectNotFound
    XCTAssertFalse(shouldRetry(permanent))

    // Edge: preconditionFailed is not retryable
    let precondition = MTPError.preconditionFailed("missing handle")
    XCTAssertFalse(shouldRetry(precondition))
  }

  func testTransportIOErrorIsClassifiedPermanent() {
    // I/O errors with descriptive messages are not transient
    let ioErr = MTPError.transport(.io("USB pipe broken"))
    XCTAssertTrue(classifyError(ioErr) == .permanent)
  }

  // MARK: - 7) Timeout → Disconnect → Cleanup Chain

  func testTimeoutThenDisconnectSequence() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .timeout, repeatCount: 2),
      ScheduledFault(
        trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var sequence: [String] = []
    let storage = MTPStorageID(raw: 0x0001_0001)

    for _ in 0..<3 {
      do {
        _ = try await link.getObjectHandles(storage: storage, parent: nil)
      } catch let err as TransportError {
        switch err {
        case .timeout: sequence.append("timeout")
        case .noDevice: sequence.append("disconnect")
        default: sequence.append("other:\(err)")
        }
      }
    }

    XCTAssertEqual(
      sequence, ["timeout", "timeout", "disconnect"],
      "Should see 2 timeouts then disconnect escalation")
  }

  func testCleanupAfterDisconnect() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.closeSession), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Cleanup (closeSession) fails with disconnect — should not crash
    var cleanupFailed = false
    do {
      try await link.closeSession()
    } catch {
      cleanupFailed = true
    }
    XCTAssertTrue(cleanupFailed, "Cleanup should fail gracefully on disconnect")
  }

  func testFallbackLadderTimeoutToResetToSuccess() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "normal") { throw MTPError.timeout },
      FallbackRung(name: "extended-timeout") { throw MTPError.timeout },
      FallbackRung(name: "reset-and-retry") { return "recovered" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "recovered")
    XCTAssertEqual(result.winningRung, "reset-and-retry")
    XCTAssertEqual(result.attempts.count, 3)
    // First two failed, third succeeded
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertTrue(result.attempts[2].succeeded)
  }

  func testDisconnectDuringMultiOperationSequence() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageInfo), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // getStorageIDs works fine
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // getStorageInfo disconnects mid-sequence
    do {
      _ = try await link.getStorageInfo(id: ids[0])
      XCTFail("Expected disconnect")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  // MARK: - 8) Additional Edge Cases

  func testEmptyFallbackLadderThrows() async throws {
    let rungs: [FallbackRung<Int>] = []
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError for empty ladder")
    } catch is FallbackAllFailedError {
      // expected — empty ladder has zero attempts, all "failed"
    }
  }

  func testProtocolError201E_RecoveryViaSessionReopen() {
    // 0x201E = SessionAlreadyOpen — recoverable by closing and reopening
    let err = MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
    XCTAssertTrue(err.isSessionAlreadyOpen)
    // Classify as transient since caller can close+reopen
    XCTAssertTrue(classifyError(err) == .transient)
  }

  func testVerificationFailedContainsSizeInfo() {
    let err = MTPError.verificationFailed(expected: 4_194_304, actual: 4_194_000)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("4194304"), "Expected size must appear in description")
    XCTAssertTrue(desc.contains("4194000"), "Actual size must appear in description")
  }

  func testFaultScheduleExhaustion_OperationsSucceedAfter() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 2)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Two failures
    for _ in 0..<2 {
      do {
        _ = try await link.getDeviceInfo()
        XCTFail("Expected timeout")
      } catch let err as TransportError {
        XCTAssertEqual(err, .timeout)
      }
    }

    // Third and fourth calls succeed — fault exhausted
    let info1 = try await link.getDeviceInfo()
    let info2 = try await link.getDeviceInfo()
    XCTAssertEqual(info1.model, "Pixel 7")
    XCTAssertEqual(info2.model, "Pixel 7")
  }

  func testMixedFaultsAcrossOperations() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Different operations get different faults
    do { _ = try await link.getStorageIDs() } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
    do { _ = try await link.getDeviceInfo() } catch let err as TransportError {
      XCTAssertEqual(err, .busy)
    }

    // Both operations succeed after faults exhausted
    let ids = try await link.getStorageIDs()
    let info = try await link.getDeviceInfo()
    XCTAssertFalse(ids.isEmpty)
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - Helpers

  private enum ErrorClass { case transient, permanent }

  private func classifyError(_ error: MTPError) -> ErrorClass {
    switch error {
    case .timeout, .busy, .sessionBusy:
      return .transient
    case .transport(let t):
      return classifyTransportError(t)
    case .protocolError(let code, _) where code == 0x201E:
      return .transient  // SessionAlreadyOpen is recoverable
    default:
      return .permanent
    }
  }

  private func classifyTransportError(_ error: TransportError) -> ErrorClass {
    switch error {
    case .timeout, .busy: return .transient
    case .timeoutInPhase: return .transient
    default: return .permanent
    }
  }

  private func shouldRetry(_ error: MTPError) -> Bool {
    classifyError(error) == .transient
  }
}
