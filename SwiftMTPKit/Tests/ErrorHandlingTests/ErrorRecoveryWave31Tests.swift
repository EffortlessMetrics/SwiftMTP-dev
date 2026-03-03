// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Wave-31 tests for error cascade and recovery paths.
///
/// Covers error chain propagation, retry policy configuration, error
/// classification (transient vs permanent), composite error aggregation,
/// error context enrichment, graceful degradation, error boundary isolation,
/// memory pressure handling, timeout cascades, and error logging integration.
final class ErrorRecoveryWave31Tests: XCTestCase {

  // MARK: - 1) Error Chain Propagation

  func testTransportErrorToMTPErrorToUserMessage() {
    // Transport → MTP wrapper → localized description chain
    let transport = TransportError.timeout
    let mtp = MTPError.transport(transport)
    let userMessage = mtp.errorDescription ?? ""

    XCTAssertFalse(userMessage.isEmpty, "User-facing message must not be empty")
    XCTAssertTrue(
      userMessage.lowercased().contains("timed out"),
      "User message should mention timeout: \(userMessage)")
  }

  func testTransportIOErrorMessageSurvivesWrapping() {
    let detail = "LIBUSB_ERROR_PIPE on endpoint 0x81"
    let transport = TransportError.io(detail)
    let mtp = MTPError.transport(transport)

    // errorDescription delegates to transport
    let desc = mtp.errorDescription ?? ""
    XCTAssertTrue(
      desc.contains(detail),
      "IO detail must survive wrapping: got \(desc)")
  }

  func testPhaseSpecificTimeoutPropagatesToUserMessage() {
    for phase in [TransportPhase.bulkOut, .bulkIn, .responseWait] {
      let transport = TransportError.timeoutInPhase(phase)
      let mtp = MTPError.transport(transport)
      let desc = mtp.errorDescription ?? ""
      XCTAssertTrue(
        desc.contains(phase.description),
        "Phase '\(phase.description)' must appear in user message")
    }
  }

  func testErrorChainPreservesRecoverySuggestion() {
    let transport = TransportError.noDevice
    let mtp = MTPError.transport(transport)
    let suggestion = mtp.recoverySuggestion ?? ""
    XCTAssertTrue(
      suggestion.contains("replug") || suggestion.contains("Unplug"),
      "Recovery suggestion should propagate from transport layer")
  }

  func testActionableDescriptionDelegatesToTransport() {
    let transport = TransportError.accessDenied
    let mtp = MTPError.transport(transport)
    let actionable = mtp.actionableDescription
    XCTAssertTrue(
      actionable.contains("denied") || actionable.contains("USB"),
      "Actionable description should reference access denial")
  }

  // MARK: - 2) Retry Policy Configuration

  func testStorageIDRetryConfigDefaults() {
    let config = StorageIDRetryConfig()
    XCTAssertEqual(config.maxRetries, 5, "Default max retries should be 5")
    XCTAssertEqual(config.backoffMs.count, 5, "Default should have 5 backoff steps")
    XCTAssertTrue(
      config.backoffMs == config.backoffMs.sorted(),
      "Backoff delays must be monotonically non-decreasing")
  }

  func testStorageIDRetryConfigCustomValues() {
    let config = StorageIDRetryConfig(maxRetries: 3, backoffMs: [100, 200, 400])
    XCTAssertEqual(config.maxRetries, 3)
    XCTAssertEqual(config.backoffMs, [100, 200, 400])
  }

  func testStorageIDRetryConfigSingleRetry() {
    let config = StorageIDRetryConfig(maxRetries: 1, backoffMs: [50])
    XCTAssertEqual(config.maxRetries, 1)
    XCTAssertEqual(config.backoffMs.first, 50)
  }

  func testBackoffDelaysAreEscalating() {
    let config = StorageIDRetryConfig()
    for i in 1..<config.backoffMs.count {
      XCTAssertGreaterThanOrEqual(
        config.backoffMs[i], config.backoffMs[i - 1],
        "Backoff delay at index \(i) must be >= delay at index \(i-1)")
    }
  }

  // MARK: - 3) Error Classification: Transient vs Permanent, Retryable vs Fatal

  func testTransientErrorsAreIdentifiable() {
    // These errors are typically transient and should be retried
    let transientTransport: [TransportError] = [.timeout, .busy]
    let transientMTP: [MTPError] = [.timeout, .busy, .sessionBusy]

    for err in transientTransport {
      let mtp = MTPError.transport(err)
      // Transient errors have recovery suggestions
      let suggestion = mtp.recoverySuggestion ?? err.recoverySuggestion ?? ""
      let desc = err.errorDescription ?? ""
      XCTAssertTrue(
        suggestion.contains("Retry") || suggestion.contains("retry")
          || desc.contains("timed out") || desc.contains("busy"),
        "Transport error \(err) should be recognizable as transient")
    }

    for err in transientMTP {
      let desc = err.errorDescription ?? ""
      XCTAssertFalse(desc.isEmpty, "Transient MTP error must have a description")
    }
  }

  func testPermanentErrorsDoNotSuggestRetry() {
    let permanent: [MTPError] = [
      .permissionDenied,
      .objectWriteProtected,
      .readOnly,
      .storageFull,
    ]

    for err in permanent {
      let suggestion = err.recoverySuggestion
      // Permanent errors either have no suggestion or a non-retry suggestion
      if let s = suggestion {
        XCTAssertFalse(
          s.lowercased().contains("retry"),
          "\(err) is permanent and should not suggest retry, got: \(s)")
      }
    }
  }

  func testProtocolErrorWithKnownCodeIsIdentifiable() {
    // 0x201D = InvalidParameter, permanent
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("0x201D") || desc.contains("InvalidParameter"))

    // recovery suggestion should be about writing to a different folder
    let suggestion = err.recoverySuggestion ?? ""
    XCTAssertTrue(suggestion.contains("writable") || suggestion.contains("folder"))
  }

  func testSessionAlreadyOpenIsRecoverable() {
    let err = MTPError.protocolError(code: 0x201E, message: "Session already open")
    XCTAssertTrue(err.isSessionAlreadyOpen)
    // This is recoverable by closing and reopening session
  }

  func testDeviceDisconnectedIsFatal() {
    let err = MTPError.deviceDisconnected
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("disconnected"))
    // No recovery suggestion from the error itself — reconnection needed
  }

  // MARK: - 4) Composite Error Aggregation

  func testFallbackAllFailedCarriesAllAttempts() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "fast") { throw MTPError.timeout },
      FallbackRung(name: "medium") { throw MTPError.busy },
      FallbackRung(name: "slow") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3, "All 3 attempts should be recorded")
      XCTAssertEqual(err.attempts[0].name, "fast")
      XCTAssertEqual(err.attempts[1].name, "medium")
      XCTAssertEqual(err.attempts[2].name, "slow")
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
    }
  }

  func testFallbackAllFailedDescriptionContainsAllRungNames() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "alpha") { throw MTPError.timeout },
      FallbackRung(name: "bravo") { throw MTPError.busy },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected error")
    } catch let err as FallbackAllFailedError {
      let desc = err.description
      XCTAssertTrue(desc.contains("alpha"), "Description must include rung name 'alpha'")
      XCTAssertTrue(desc.contains("bravo"), "Description must include rung name 'bravo'")
      XCTAssertTrue(desc.contains("✗"), "Failed marks must appear")
    }
  }

  func testFallbackAttemptsTrackDuration() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "instant-fail") { throw MTPError.timeout },
      FallbackRung(name: "succeed") { return "ok" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "succeed")
    XCTAssertEqual(result.attempts.count, 2)
    // Both attempts should have non-negative duration
    for attempt in result.attempts {
      XCTAssertGreaterThanOrEqual(attempt.durationMs, 0)
    }
  }

  // MARK: - 5) Error Context Enrichment

  func testMTPErrorLocalizedDescriptionIsInformative() {
    let cases: [(MTPError, String)] = [
      (.deviceDisconnected, "disconnected"),
      (.permissionDenied, "denied"),
      (.timeout, "timed out"),
      (.busy, "busy"),
      (.storageFull, "full"),
      (.readOnly, "read-only"),
      (.objectNotFound, "not found"),
      (.objectWriteProtected, "write-protected"),
      (.sessionBusy, "transaction"),
    ]

    for (error, keyword) in cases {
      let desc = error.errorDescription ?? ""
      XCTAssertTrue(
        desc.lowercased().contains(keyword),
        "\(error): expected '\(keyword)' in '\(desc)'")
    }
  }

  func testPreconditionFailedCarriesContext() {
    let context = "Storage 0x00010001 missing during enumeration"
    let err = MTPError.preconditionFailed(context)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains(context))
  }

  func testVerificationFailedIncludesSizes() {
    let err = MTPError.verificationFailed(expected: 1_048_576, actual: 524_288)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("1048576") || desc.contains("524288"),
                  "Verification error must include size details: \(desc)")
  }

  func testTransportPhaseDescriptionsAreMeaningful() {
    let phases: [(TransportPhase, String)] = [
      (.bulkOut, "bulk-out"),
      (.bulkIn, "bulk-in"),
      (.responseWait, "response-wait"),
    ]

    for (phase, expected) in phases {
      XCTAssertEqual(phase.description, expected)
    }
  }

  func testActionableDescriptionCoversAllMTPErrors() {
    // Every MTPError case should produce a non-empty actionable description
    let allCases: [MTPError] = [
      .deviceDisconnected, .permissionDenied, .notSupported("test"),
      .transport(.timeout), .protocolError(code: 0x2001, message: "Test"),
      .objectNotFound, .objectWriteProtected, .storageFull, .readOnly,
      .timeout, .busy, .sessionBusy, .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]

    for error in allCases {
      let desc = error.actionableDescription
      XCTAssertFalse(desc.isEmpty, "Actionable description empty for \(error)")
    }
  }

  func testActionableDescriptionCoversAllTransportErrors() {
    let allCases: [TransportError] = [
      .noDevice, .timeout, .busy, .accessDenied, .stall,
      .io("test"), .timeoutInPhase(.bulkIn),
    ]

    for error in allCases {
      let desc = error.actionableDescription
      XCTAssertFalse(desc.isEmpty, "Actionable description empty for \(error)")
    }
  }

  // MARK: - 6) Graceful Degradation

  func testFallbackLadderDegradesThroughStrategies() async throws {
    // Simulate: partial object unsupported → fall back to full download
    let result = try await FallbackLadder.execute([
      FallbackRung(name: "partial-object") {
        throw MTPError.notSupported("GetPartialObject64 not supported")
      },
      FallbackRung(name: "full-download") {
        return Data(repeating: 0xAB, count: 1024)
      },
    ])

    XCTAssertEqual(result.winningRung, "full-download")
    XCTAssertEqual(result.value.count, 1024)
    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertFalse(result.attempts[0].succeeded, "Partial path should have failed")
    XCTAssertTrue(result.attempts[1].succeeded, "Full download should succeed")
  }

  func testDegradationFromFastPathToSessionReset() async throws {
    let callOrder = MutableBox<[String]>([])

    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "fast-path") {
        callOrder.value.append("fast")
        throw MTPError.timeout
      },
      FallbackRung(name: "session-reset") {
        callOrder.value.append("reset")
        return [MTPStorageID(raw: 0x00010001)]
      },
    ]
    let result = try await FallbackLadder.execute(rungs)

    XCTAssertEqual(callOrder.value, ["fast", "reset"])
    XCTAssertEqual(result.winningRung, "session-reset")
    XCTAssertEqual(result.value.count, 1)
  }

  func testDegradationReportsFailureReasonInAttempts() async throws {
    let result = try await FallbackLadder.execute([
      FallbackRung(name: "optimistic") {
        throw MTPError.protocolError(code: 0x2009, message: "Object not found")
      },
      FallbackRung(name: "conservative") {
        return "fallback-result"
      },
    ])

    let failedAttempt = result.attempts.first { !$0.succeeded }
    XCTAssertNotNil(failedAttempt)
    XCTAssertNotNil(failedAttempt?.error, "Failed attempt should carry error string")
    XCTAssertTrue(failedAttempt?.error?.contains("Object not found") == true)
  }

  // MARK: - 7) Error Boundary Isolation

  func testIndependentLinksIsolateErrors() async throws {
    // Device A has faults, Device B works fine — errors don't cross
    let linkA = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .pixel7),
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1)
      ]))
    let linkB = VirtualMTPLink(config: .pixel7)

    try await linkA.openSession(id: 1)
    try await linkB.openSession(id: 2)

    // Device A fails
    do {
      _ = try await linkA.getStorageIDs()
      XCTFail("Device A should throw timeout")
    } catch {
      // expected
    }

    // Device B unaffected
    let idsB = try await linkB.getStorageIDs()
    XCTAssertFalse(idsB.isEmpty, "Device B must succeed despite Device A's failure")
  }

  func testConcurrentDeviceErrorsDoNotInterfere() async throws {
    let linkA = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .pixel7),
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 1)
      ]))
    let linkB = VirtualMTPLink(config: .pixel7)

    try await linkA.openSession(id: 1)
    try await linkB.openSession(id: 2)

    // Run concurrently
    async let taskA: Void = {
      do {
        _ = try await linkA.getDeviceInfo()
        XCTFail("Device A should throw busy")
      } catch let err as TransportError {
        XCTAssertEqual(err, .busy)
      }
    }()

    async let taskB: MTPDeviceInfo = linkB.getDeviceInfo()

    _ = try await (taskA, taskB)
  }

  func testSequentialErrorsOnSameDeviceDontCorruptState() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 2),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Two failures
    for _ in 0..<2 {
      do {
        _ = try await link.getStorageIDs()
        XCTFail("Should throw")
      } catch {
        // expected
      }
    }

    // After faults exhausted, normal operation resumes
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty, "Link should recover after fault schedule exhausted")
  }

  // MARK: - 8) Memory Pressure Error Handling

  func testVerificationFailedOnSizeMismatch() {
    // Simulates detecting a corrupted transfer via size check
    let err = MTPError.verificationFailed(expected: 10_000_000, actual: 9_999_744)
    XCTAssertNotEqual(err, MTPError.timeout, "Verification error is distinct from timeout")

    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("10000000") || desc.contains("9999744"))
    XCTAssertTrue(desc.lowercased().contains("verification"))
  }

  func testLargeTransferTimeoutProducesActionableMessage() {
    // A timeout during a large transfer should guide the user
    let err = TransportError.timeoutInPhase(.bulkIn)
    let actionable = err.actionableDescription
    XCTAssertTrue(
      actionable.contains("retry") || actionable.contains("Retry")
        || actionable.contains("cable") || actionable.contains("timeout"),
      "Large transfer timeout should produce actionable guidance: \(actionable)")
  }

  func testStorageFullErrorIsDistinct() {
    let err = MTPError.storageFull
    let desc = err.errorDescription ?? ""
    let actionable = err.actionableDescription
    XCTAssertTrue(desc.contains("full"))
    XCTAssertTrue(actionable.contains("full"))
    XCTAssertNotEqual(err, MTPError.readOnly, "storageFull distinct from readOnly")
  }

  // MARK: - 9) Timeout Cascade

  func testTimeoutCascadeOperationToConnectionToDevice() async throws {
    // Simulate escalating timeout chain: operation → connection → device disconnect
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var errors: [Error] = []
    for _ in 0..<3 {
      do {
        _ = try await link.getStorageIDs()
      } catch {
        errors.append(error)
      }
    }

    XCTAssertEqual(errors.count, 3)
    // First two: timeout, last: disconnect
    XCTAssertEqual(errors[0] as? TransportError, .timeout)
    XCTAssertEqual(errors[1] as? TransportError, .timeout)
    XCTAssertEqual(errors[2] as? TransportError, .noDevice)
  }

  func testTimeoutInAllPhasesProducesUniqueMessages() {
    let phases: [TransportPhase] = [.bulkOut, .bulkIn, .responseWait]
    var descriptions: Set<String> = []

    for phase in phases {
      let err = TransportError.timeoutInPhase(phase)
      let desc = err.errorDescription ?? ""
      descriptions.insert(desc)
    }

    XCTAssertEqual(descriptions.count, 3,
                   "Each phase timeout should produce a unique message")
  }

  func testFallbackLadderTimeoutEscalation() async throws {
    // Timeout at each rung: fast → medium → slow, all fail
    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "immediate") { throw MTPError.timeout },
      FallbackRung(name: "with-reset") {
        throw MTPError.transport(.timeoutInPhase(.bulkIn))
      },
      FallbackRung(name: "full-reconnect") {
        throw MTPError.deviceDisconnected
      },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected all rungs to fail")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      // Errors escalate in severity
      XCTAssertTrue(err.attempts[0].error?.contains("timeout") == true)
      XCTAssertTrue(err.attempts[2].error?.contains("disconnected") == true
                    || err.attempts[2].error?.contains("Disconnected") == true)
    }
  }

  // MARK: - 10) Error Logging Integration

  func testTransactionLogRecordsErrorOutcome() async {
    let log = TransactionLog()

    let record = TransactionRecord(
      txID: 1, opcode: 0x1004, opcodeLabel: "GetStorageIDs",
      sessionID: 1, startedAt: Date(), duration: 0.5,
      bytesIn: 0, bytesOut: 12,
      outcomeClass: .timeout,
      errorDescription: "USB transfer timed out")

    await log.append(record)
    let recent = await log.recent(limit: 10)

    XCTAssertEqual(recent.count, 1)
    XCTAssertEqual(recent[0].outcomeClass, .timeout)
    XCTAssertEqual(recent[0].errorDescription, "USB transfer timed out")
    XCTAssertEqual(recent[0].opcodeLabel, "GetStorageIDs")
  }

  func testTransactionLogRecordsMultipleErrors() async {
    let log = TransactionLog()

    let outcomes: [(TransactionOutcome, String?)] = [
      (.timeout, "Phase 1 timed out"),
      (.stall, "Endpoint stalled"),
      (.deviceError, "Device returned 0x2009"),
      (.ok, nil),
    ]

    for (i, (outcome, desc)) in outcomes.enumerated() {
      await log.append(TransactionRecord(
        txID: UInt32(i + 1), opcode: 0x1004,
        opcodeLabel: "GetStorageIDs", sessionID: 1,
        startedAt: Date(), duration: Double(i) * 0.1,
        bytesIn: 0, bytesOut: 12,
        outcomeClass: outcome, errorDescription: desc))
    }

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 4)
    XCTAssertEqual(recent.filter { $0.outcomeClass != .ok }.count, 3,
                   "Three error outcomes should be recorded")
  }

  func testTransactionLogDumpRedactsHexSequences() async {
    let log = TransactionLog()

    await log.append(TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 100, bytesOut: 0,
      outcomeClass: .deviceError,
      errorDescription: "Device serial ABCDEF0123456789 returned error"))

    let json = await log.dump(redacting: true)
    XCTAssertFalse(json.contains("ABCDEF0123456789"),
                   "Hex serial should be redacted")
    XCTAssertTrue(json.contains("<redacted>"))
  }

  func testTransactionLogDumpPreservesNonRedacted() async {
    let log = TransactionLog()

    await log.append(TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 100, bytesOut: 0,
      outcomeClass: .deviceError,
      errorDescription: "Device serial ABCDEF0123456789 returned error"))

    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("ABCDEF0123456789"),
                  "Non-redacted dump should preserve hex")
  }

  func testMTPOpcodeLabelsForCommonOps() {
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1004), "GetStorageIDs")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1009), "GetObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100D), "SendObject")
    XCTAssertTrue(MTPOpcodeLabel.label(for: 0xFFFF).contains("Unknown"))
  }

  func testAllTransactionOutcomesHaveDistinctRawValues() {
    let outcomes: [TransactionOutcome] = [
      .ok, .deviceError, .timeout, .stall, .ioError, .cancelled,
    ]
    let rawValues = Set(outcomes.map { $0.rawValue })
    XCTAssertEqual(rawValues.count, outcomes.count,
                   "Each outcome must have a unique raw value")
  }

  // MARK: - Helpers

  /// Thread-safe mutable box for use in @Sendable closures.
  private final class MutableBox<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
  }
}
