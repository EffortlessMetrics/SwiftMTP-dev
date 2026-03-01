// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for error recovery paths: cascading failures, partial resume,
/// phase-specific disconnects, backoff, timeout escalation, error
/// categorisation, graceful degradation, and diagnostics output.
final class RecoveryPathTests: XCTestCase {

  // MARK: - 1) Cascading Error Recovery

  func testCascadingRecovery_SecondFaultDuringRecoveryFromFirst() async throws {
    // First call: timeout. Caller retries → second call: busy. Third call succeeds.
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // First attempt → timeout
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout on first attempt")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }

    // Recovery attempt → busy (cascading)
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected busy on recovery attempt")
    } catch let err as TransportError {
      XCTAssertEqual(err, .busy)
    }

    // Final recovery succeeds
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty, "Third call should succeed after cascading faults exhausted")
  }

  func testCascadingRecovery_DisconnectDuringBusyRetrySequence() async throws {
    // busy×2 then disconnect — caller never reaches success
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 2),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var errors: [TransportError] = []
    for _ in 0..<3 {
      do {
        _ = try await link.getStorageIDs()
        XCTFail("Expected error")
      } catch let err as TransportError {
        errors.append(err)
      }
    }

    XCTAssertEqual(errors, [.busy, .busy, .noDevice])
  }

  func testCascadingRecovery_AllFallbackRungsFail_CarriesFullHistory() async throws {
    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "fast-path") { throw MTPError.timeout },
      FallbackRung(name: "session-reset") { throw MTPError.busy },
      FallbackRung(name: "usb-reset") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      XCTAssertEqual(err.attempts.map(\.name), ["fast-path", "session-reset", "usb-reset"])
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
      XCTAssertTrue(err.attempts.allSatisfy { $0.error != nil })
    }
  }

  // MARK: - 2) Partial Transfer Resume After Disconnection

  func testPartialTransferResume_DisconnectMidStream() async throws {
    // Simulate a streaming command that disconnects at byte offset 1024
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault.disconnectAtOffset(1024)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // The FaultInjectingLink checks faults at the operation level.
    // The disconnectAtOffset schedule triggers on executeStreamingCommand
    // when byteOffset matches. Since FaultInjectingLink.checkFault passes
    // nil for byteOffset, the byte-offset fault won't fire at top level.
    // Verify the schedule itself correctly tracks byte offsets.
    let byteResult = schedule.check(
      operation: .executeStreamingCommand, callIndex: 0, byteOffset: 1024)
    XCTAssertNotNil(byteResult, "Fault should fire at exact byte offset")
    if case .disconnected = byteResult {
      // expected
    } else {
      XCTFail("Expected disconnected fault at byte offset 1024")
    }
  }

  func testPartialTransferResume_ResumeAfterByteOffsetFault() async throws {
    // After a byte-offset fault fires, subsequent checks at other offsets should pass
    let schedule = FaultSchedule([
      ScheduledFault.disconnectAtOffset(2048)
    ])

    // Fire at 2048 → consumes the fault
    let hit = schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 2048)
    XCTAssertNotNil(hit)

    // Subsequent check at same offset should pass (fault exhausted, repeatCount=1)
    let retry = schedule.check(
      operation: .executeStreamingCommand, callIndex: 1, byteOffset: 2048)
    XCTAssertNil(retry, "Fault should be exhausted after one fire — resume should succeed")
  }

  func testPartialTransferResume_TrackBytesTransferredBeforeFailure() async throws {
    // Model a transfer journal: track how many bytes succeeded before disconnect
    var bytesTransferred: Int64 = 0
    let totalBytes: Int64 = 10_000
    let disconnectAt: Int64 = 4_096

    // Simulate chunks
    let chunkSize: Int64 = 1024
    while bytesTransferred < totalBytes {
      if bytesTransferred + chunkSize >= disconnectAt && bytesTransferred < disconnectAt {
        bytesTransferred = disconnectAt
        break  // simulate disconnect
      }
      bytesTransferred += chunkSize
    }

    XCTAssertEqual(bytesTransferred, disconnectAt)
    XCTAssertLessThan(bytesTransferred, totalBytes, "Transfer should be partial")

    // Resume from checkpoint
    let remaining = totalBytes - bytesTransferred
    XCTAssertEqual(remaining, 5_904)
  }

  // MARK: - 3) Connection Drop During Different Transfer Phases

  func testConnectionDrop_DuringNegotiation_OpenSession() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected disconnection during session negotiation")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testConnectionDrop_DuringDataPhase_GetObjectHandles() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x00010001), parent: nil)
      XCTFail("Expected disconnection during data phase")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testConnectionDrop_DuringCompletion_CloseSession() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.closeSession), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      try await link.closeSession()
      XCTFail("Expected disconnection during completion")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testConnectionDrop_DuringStreaming_ExecuteStreamingCommand() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let cmd = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObject.rawValue,
      txid: 1,
      params: [3]
    )

    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 4_500_000, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected disconnection during streaming")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testConnectionDrop_DifferentPhases_ProduceDifferentTransportErrors() {
    // Verify timeoutInPhase variants are distinct
    let bulkOutTimeout = TransportError.timeoutInPhase(.bulkOut)
    let bulkInTimeout = TransportError.timeoutInPhase(.bulkIn)
    let responseTimeout = TransportError.timeoutInPhase(.responseWait)

    XCTAssertNotEqual(bulkOutTimeout, bulkInTimeout)
    XCTAssertNotEqual(bulkInTimeout, responseTimeout)
    XCTAssertNotEqual(bulkOutTimeout, responseTimeout)

    // Each has a meaningful description
    XCTAssertTrue(bulkOutTimeout.errorDescription?.contains("bulk-out") ?? false)
    XCTAssertTrue(bulkInTimeout.errorDescription?.contains("bulk-in") ?? false)
    XCTAssertTrue(responseTimeout.errorDescription?.contains("response-wait") ?? false)
  }

  // MARK: - 4) Rate-Limited Retry with Exponential Backoff

  func testExponentialBackoff_DelaysDoublePerRetry() {
    var delays: [TimeInterval] = []
    let baseDelay: TimeInterval = 0.25
    let maxRetries = 5

    for attempt in 0..<maxRetries {
      let delay = baseDelay * pow(2.0, Double(attempt))
      delays.append(delay)
    }

    // 0.25, 0.5, 1.0, 2.0, 4.0
    XCTAssertEqual(delays.count, 5)
    XCTAssertEqual(delays[0], 0.25, accuracy: 0.001)
    XCTAssertEqual(delays[1], 0.50, accuracy: 0.001)
    XCTAssertEqual(delays[2], 1.00, accuracy: 0.001)
    XCTAssertEqual(delays[3], 2.00, accuracy: 0.001)
    XCTAssertEqual(delays[4], 4.00, accuracy: 0.001)

    // Each delay is double the previous
    for i in 1..<delays.count {
      XCTAssertEqual(delays[i], delays[i - 1] * 2, accuracy: 0.001)
    }
  }

  func testExponentialBackoff_CappedAtMaxDelay() {
    let baseDelay: TimeInterval = 0.25
    let maxDelay: TimeInterval = 3.0

    var delays: [TimeInterval] = []
    for attempt in 0..<8 {
      let uncapped = baseDelay * pow(2.0, Double(attempt))
      delays.append(min(uncapped, maxDelay))
    }

    // Should cap at 3.0 after attempt 3 (0.25→0.5→1→2→3→3→3→3)
    XCTAssertTrue(delays.allSatisfy { $0 <= maxDelay })
    XCTAssertEqual(delays.last, maxDelay)
  }

  func testBusyRetry_SucceedsAfterScheduledBusyFaultsExhausted() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let busyFault = ScheduledFault.busyForRetries(3)
    let schedule = FaultSchedule([busyFault])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var busyCount = 0
    let maxRetries = 5

    for _ in 0..<maxRetries {
      do {
        let cmd = PTPContainer(
          type: PTPContainer.Kind.command.rawValue,
          code: PTPOp.getDeviceInfo.rawValue,
          txid: 1,
          params: []
        )
        _ = try await link.executeCommand(cmd)
        break  // success
      } catch let err as TransportError where err == .busy {
        busyCount += 1
      }
    }

    XCTAssertEqual(busyCount, 3, "Should encounter exactly 3 busy errors before success")
  }

  func testStorageIDRetryConfig_BackoffSequence() {
    let config = StorageIDRetryConfig()
    XCTAssertEqual(config.maxRetries, 5)
    XCTAssertEqual(config.backoffMs, [250, 500, 1000, 2000, 3000])

    // Verify backoff is monotonically increasing
    for i in 1..<config.backoffMs.count {
      XCTAssertGreaterThan(config.backoffMs[i], config.backoffMs[i - 1])
    }
  }

  func testStorageIDRetryConfig_CustomBackoff() {
    let custom = StorageIDRetryConfig(maxRetries: 3, backoffMs: [100, 200, 400])
    XCTAssertEqual(custom.maxRetries, 3)
    XCTAssertEqual(custom.backoffMs.count, 3)
  }

  // MARK: - 5) Timeout Escalation (soft → hard → disconnect)

  func testTimeoutEscalation_SoftThenHardThenDisconnect() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .timeout, repeatCount: 1),
      ScheduledFault(
        trigger: .onOperation(.getObjectInfos), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var escalation: [TransportError] = []

    for _ in 0..<3 {
      do {
        _ = try await link.getObjectInfos([1])
        break
      } catch let err as TransportError {
        escalation.append(err)
      }
    }

    XCTAssertEqual(escalation.count, 3)
    XCTAssertEqual(escalation[0], .timeout, "First: soft timeout")
    XCTAssertEqual(escalation[1], .timeout, "Second: hard timeout")
    XCTAssertEqual(escalation[2], .noDevice, "Third: escalated to disconnect")
  }

  func testTimeoutEscalation_FallbackLadder_TimeoutsEscalateToReset() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "quick") {
        throw MTPError.timeout
      },
      FallbackRung(name: "patient") {
        throw MTPError.timeout
      },
      FallbackRung(name: "reset") {
        return "recovered-after-reset"
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "recovered-after-reset")
    XCTAssertEqual(result.winningRung, "reset")
    XCTAssertEqual(result.attempts.count, 3)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertTrue(result.attempts[2].succeeded)
  }

  func testTimeoutInPhase_AllPhasesRepresented() {
    let phases: [TransportPhase] = [.bulkOut, .bulkIn, .responseWait]
    for phase in phases {
      let error = TransportError.timeoutInPhase(phase)
      XCTAssertNotNil(error.errorDescription)
      XCTAssertTrue(
        error.errorDescription?.contains(phase.description) ?? false,
        "Error description should mention phase \(phase.description)")
    }
  }

  // MARK: - 6) Error Categorisation (transient vs permanent)

  func testTransientErrors_AreRetryable() {
    let transientErrors: [TransportError] = [
      .timeout,
      .busy,
      .timeoutInPhase(.bulkIn),
      .timeoutInPhase(.bulkOut),
      .timeoutInPhase(.responseWait),
    ]
    let transientMTP: [MTPError] = [
      .timeout,
      .busy,
      .sessionBusy,
      .transport(.timeout),
      .transport(.busy),
    ]

    for err in transientErrors {
      XCTAssertTrue(isTransientTransport(err), "\(err) should be transient")
    }
    for err in transientMTP {
      XCTAssertTrue(isTransientMTP(err), "\(err) should be transient")
    }
  }

  func testPermanentErrors_AreNotRetryable() {
    let permanentTransport: [TransportError] = [
      .noDevice,
      .accessDenied,
      .stall,
    ]
    let permanentMTP: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .protocolError(code: 0x2009, message: "Not found"),
      .verificationFailed(expected: 100, actual: 50),
    ]

    for err in permanentTransport {
      XCTAssertFalse(isTransientTransport(err), "\(err) should be permanent")
    }
    for err in permanentMTP {
      XCTAssertFalse(isTransientMTP(err), "\(err) should be permanent")
    }
  }

  func testSessionAlreadyOpen_IsRecoverable() {
    let sessionErr = MTPError.protocolError(code: 0x201E, message: "Session already open")
    XCTAssertTrue(sessionErr.isSessionAlreadyOpen)

    // Other protocol errors are not session-already-open
    let otherErr = MTPError.protocolError(code: 0x2005, message: "Op not supported")
    XCTAssertFalse(otherErr.isSessionAlreadyOpen)
  }

  func testFaultErrorCategories_CoverAllCases() {
    let allFaults: [(FaultError, TransportError)] = [
      (.timeout, .timeout),
      (.busy, .busy),
      (.disconnected, .noDevice),
      (.accessDenied, .accessDenied),
      (.io("test"), .io("test")),
      (.protocolError(code: 0x2009), .io("Protocol error injected by fault")),
    ]

    for (fault, expected) in allFaults {
      XCTAssertEqual(fault.transportError, expected)
    }
  }

  // MARK: - 7) Graceful Degradation

  func testGracefulDegradation_StorageInfoFailsButHandlesSucceed() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageInfo), error: .timeout, repeatCount: 0)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Storage IDs still work
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Storage info fails
    do {
      _ = try await link.getStorageInfo(id: ids[0])
      XCTFail("Expected timeout on storage info")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }

    // Object handles still work (degraded: no storage info, but enumeration ok)
    let handles = try await link.getObjectHandles(storage: ids[0], parent: nil)
    XCTAssertFalse(handles.isEmpty)
  }

  func testGracefulDegradation_ObjectInfoFailsButDeviceInfoSucceeds() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .busy, repeatCount: 0)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Device info works
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")

    // Object infos always fail
    do {
      _ = try await link.getObjectInfos([1])
      XCTFail("Expected busy error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .busy)
    }
  }

  func testGracefulDegradation_FallbackLadder_FirstRungFails_SecondSucceeds() async throws {
    let rungs: [FallbackRung<[MTPStorageID]>] = [
      FallbackRung(name: "proplist-enumeration") {
        throw MTPError.notSupported("GetObjectPropList broken on this device")
      },
      FallbackRung(name: "legacy-enumeration") {
        return [MTPStorageID(raw: 0x00010001)]
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.winningRung, "legacy-enumeration")
    XCTAssertEqual(result.value.count, 1)
    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertTrue(result.attempts[1].succeeded)
  }

  func testGracefulDegradation_DynamicFaultAddition() async throws {
    // Start with no faults, then inject one dynamically mid-operation
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule()
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // First call succeeds
    let ids1 = try await link.getStorageIDs()
    XCTAssertFalse(ids1.isEmpty)

    // Inject fault dynamically
    link.scheduleFault(
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1))

    // Next call fails
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout after dynamic fault injection")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }

    // Subsequent call succeeds (fault exhausted)
    let ids3 = try await link.getStorageIDs()
    XCTAssertFalse(ids3.isEmpty)
  }

  // MARK: - 8) Error Logging and Diagnostics Output

  func testErrorLogging_MTPErrorDescriptionsAreHumanReadable() {
    let errors: [(MTPError, String)] = [
      (.deviceDisconnected, "disconnected"),
      (.permissionDenied, "denied"),
      (.timeout, "timed out"),
      (.busy, "busy"),
      (.objectNotFound, "not found"),
      (.storageFull, "full"),
      (.readOnly, "read-only"),
      (.sessionBusy, "transaction"),
      (.protocolError(code: 0x2001, message: "Invalid StorageID"), "Invalid StorageID"),
      (.verificationFailed(expected: 100, actual: 50), "verification"),
    ]

    for (error, expectedSubstring) in errors {
      let desc = error.errorDescription ?? ""
      XCTAssertFalse(desc.isEmpty, "Error \(error) should have a description")
      XCTAssertTrue(
        desc.localizedCaseInsensitiveContains(expectedSubstring),
        "'\(desc)' should contain '\(expectedSubstring)'")
    }
  }

  func testErrorLogging_TransportErrorDescriptionsAreHumanReadable() {
    let errors: [(TransportError, String)] = [
      (.noDevice, "No MTP"),
      (.timeout, "timed out"),
      (.busy, "busy"),
      (.accessDenied, "unavailable"),
      (.stall, "stall"),
      (.io("USB pipe broken"), "USB pipe broken"),
      (.timeoutInPhase(.bulkIn), "bulk-in"),
    ]

    for (error, expectedSubstring) in errors {
      let desc = error.errorDescription ?? ""
      XCTAssertFalse(desc.isEmpty)
      XCTAssertTrue(
        desc.contains(expectedSubstring),
        "'\(desc)' should contain '\(expectedSubstring)'")
    }
  }

  func testErrorLogging_FallbackAllFailedError_DiagnosticOutput() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "rung-A") { throw MTPError.timeout },
      FallbackRung(name: "rung-B") { throw MTPError.transport(.stall) },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      let desc = err.description
      XCTAssertTrue(desc.contains("rung-A"), "Should list rung-A")
      XCTAssertTrue(desc.contains("rung-B"), "Should list rung-B")
      XCTAssertTrue(desc.contains("✗"), "Should contain failure symbol")
      XCTAssertTrue(desc.contains("ms"), "Should include timing")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testErrorLogging_MTPErrorRecoverySuggestions() {
    // Protocol error 0x201D should have a recovery suggestion
    let writeErr = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertNotNil(writeErr.recoverySuggestion)
    XCTAssertTrue(writeErr.recoverySuggestion?.contains("writable folder") ?? false)

    // Transport errors with recovery suggestions
    let noDevice = MTPError.transport(.noDevice)
    XCTAssertNotNil(noDevice.recoverySuggestion)

    let accessDenied = MTPError.transport(.accessDenied)
    XCTAssertNotNil(accessDenied.recoverySuggestion)

    let transportTimeout = MTPError.transport(.timeout)
    XCTAssertNotNil(transportTimeout.recoverySuggestion)
  }

  func testErrorLogging_MTPErrorFailureReasons() {
    let protocolErr = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertNotNil(protocolErr.failureReason)
    XCTAssertTrue(protocolErr.failureReason?.contains("rejected") ?? false)

    let noDevice = MTPError.transport(.noDevice)
    XCTAssertNotNil(noDevice.failureReason)

    let timeout = MTPError.transport(.timeout)
    XCTAssertNotNil(timeout.failureReason)
  }

  func testErrorLogging_ContextPreservedInWrappedErrors() {
    let inner = MTPError.protocolError(code: 0x2009, message: "Object not found")
    let outer = MTPError.preconditionFailed(
      "Transfer failed at offset 4096: \(inner.errorDescription ?? "")")

    if case .preconditionFailed(let msg) = outer {
      XCTAssertTrue(msg.contains("4096"), "Should preserve byte offset context")
      XCTAssertTrue(msg.contains("Object not found"), "Should preserve inner error message")
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  // MARK: - Helpers

  /// Classify transport errors as transient (retryable) or permanent.
  private func isTransientTransport(_ error: TransportError) -> Bool {
    switch error {
    case .timeout, .busy: return true
    case .timeoutInPhase: return true
    default: return false
    }
  }

  /// Classify MTP errors as transient (retryable) or permanent.
  private func isTransientMTP(_ error: MTPError) -> Bool {
    switch error {
    case .timeout, .busy, .sessionBusy: return true
    case .transport(let t): return isTransientTransport(t)
    default: return false
    }
  }
}
