// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Edge-case tests for error recovery chains, cascading failures, classification
/// boundaries, fault schedule mechanics, concurrent error handling, and error
/// context preservation across wrapping layers.
final class ErrorEdgeCaseTests: XCTestCase {

  // MARK: - 1) Fault Schedule Edge Cases

  func testFaultScheduleAtCallIndex_FiresOnExactIndex() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(2), error: .timeout, repeatCount: 1)
    ])
    // Calls 0 and 1 should not trigger
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil))
    // Call 2 should trigger
    let err = schedule.check(operation: .getStorageIDs, callIndex: 2, byteOffset: nil)
    XCTAssertNotNil(err)
    if case .timeout = err {} else { XCTFail("Expected timeout") }
  }

  func testFaultScheduleAtCallIndex_DoesNotFireOnWrongIndex() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(5), error: .busy, repeatCount: 1)
    ])
    for i in 0..<5 {
      XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: i, byteOffset: nil))
    }
    XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 5, byteOffset: nil))
  }

  func testFaultScheduleUnlimitedRepeat_FiresIndefinitely() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 0)
    ])
    for i in 0..<20 {
      let err = schedule.check(operation: .getStorageIDs, callIndex: i, byteOffset: nil)
      XCTAssertNotNil(err, "Unlimited fault should fire on call \(i)")
    }
  }

  func testFaultScheduleClear_RemovesAllFaults() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 0),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 0),
    ])
    XCTAssertNotNil(schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil))
    schedule.clear()
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil))
    XCTAssertNil(schedule.check(operation: .getDeviceInfo, callIndex: 2, byteOffset: nil))
  }

  func testFaultScheduleAfterDelayTrigger_NeverMatchesInCheck() {
    // afterDelay is handled externally; check() should not match it
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .afterDelay(1.0), error: .timeout, repeatCount: 1)
    ])
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil))
  }

  func testFaultScheduleMixedTriggers_FirstMatchWins() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(0), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    // Call index 0 + getStorageIDs: atCallIndex(0) is first in list
    let err = schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil)
    XCTAssertNotNil(err)
    if case .timeout = err {} else { XCTFail("Expected first-match (timeout), got \(String(describing: err))") }
  }

  func testFaultScheduleConsumedFaultsRemovedFromList() {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    // First fires timeout
    let first = schedule.check(operation: .getStorageIDs, callIndex: 0, byteOffset: nil)
    if case .timeout = first {} else { XCTFail("Expected timeout first") }
    // Second fires busy (timeout consumed)
    let second = schedule.check(operation: .getStorageIDs, callIndex: 1, byteOffset: nil)
    if case .busy = second {} else { XCTFail("Expected busy second") }
    // Third: all consumed
    XCTAssertNil(schedule.check(operation: .getStorageIDs, callIndex: 2, byteOffset: nil))
  }

  func testScheduledFaultPredefined_PipeStall() {
    let fault = ScheduledFault.pipeStall(on: .getObjectHandles)
    if case .onOperation(.getObjectHandles) = fault.trigger {} else {
      XCTFail("Expected onOperation(.getObjectHandles)")
    }
    if case .io(let msg) = fault.error {
      XCTAssertTrue(msg.contains("stall"))
    } else {
      XCTFail("Expected io error")
    }
    XCTAssertNotNil(fault.label)
  }

  func testScheduledFaultPredefined_TimeoutOnce() {
    let fault = ScheduledFault.timeoutOnce(on: .getDeviceInfo)
    if case .onOperation(.getDeviceInfo) = fault.trigger {} else {
      XCTFail("Expected onOperation(.getDeviceInfo)")
    }
    if case .timeout = fault.error {} else { XCTFail("Expected timeout") }
    XCTAssertEqual(fault.repeatCount, 1)
  }

  func testScheduledFaultPredefined_BusyForRetries() {
    let fault = ScheduledFault.busyForRetries(5)
    if case .onOperation(.executeCommand) = fault.trigger {} else {
      XCTFail("Expected onOperation(.executeCommand)")
    }
    if case .busy = fault.error {} else { XCTFail("Expected busy") }
    XCTAssertEqual(fault.repeatCount, 5)
  }

  func testLinkOperationType_CaseIterableCoversAll() {
    let allOps = LinkOperationType.allCases
    XCTAssertTrue(allOps.count >= 12, "Should have at least 12 operation types, got \(allOps.count)")
    XCTAssertTrue(allOps.contains(.openUSB))
    XCTAssertTrue(allOps.contains(.openSession))
    XCTAssertTrue(allOps.contains(.closeSession))
    XCTAssertTrue(allOps.contains(.getDeviceInfo))
    XCTAssertTrue(allOps.contains(.getStorageIDs))
    XCTAssertTrue(allOps.contains(.getStorageInfo))
    XCTAssertTrue(allOps.contains(.getObjectHandles))
    XCTAssertTrue(allOps.contains(.getObjectInfos))
    XCTAssertTrue(allOps.contains(.deleteObject))
    XCTAssertTrue(allOps.contains(.moveObject))
    XCTAssertTrue(allOps.contains(.executeCommand))
    XCTAssertTrue(allOps.contains(.executeStreamingCommand))
  }

  // MARK: - 2) Error Classification Boundaries

  func testTransportIOError_ClassifiedAsPermanent() {
    let err = TransportError.io("USB pipe broken")
    XCTAssertTrue(classifyTransport(err) == .permanent)
  }

  func testTransportIOError_EmptyMessage_ClassifiedAsPermanent() {
    let err = TransportError.io("")
    XCTAssertTrue(classifyTransport(err) == .permanent)
  }

  func testTransportTimeoutInAllPhases_ClassifiedAsTransient() {
    let phases: [TransportPhase] = [.bulkOut, .bulkIn, .responseWait]
    for phase in phases {
      let err = TransportError.timeoutInPhase(phase)
      XCTAssertTrue(classifyTransport(err) == .transient,
                    "timeoutInPhase(\(phase)) should be transient")
    }
  }

  func testMTPNotSupported_ClassifiedAsPermanent() {
    let err = MTPError.notSupported("GetObjectPropList")
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  func testMTPPreconditionFailed_ClassifiedAsPermanent() {
    let err = MTPError.preconditionFailed("handle missing")
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  func testProtocolError201E_SessionAlreadyOpen_Transient() {
    let err = MTPError.protocolError(code: 0x201E, message: nil)
    XCTAssertTrue(classifyMTP(err) == .transient,
                  "SessionAlreadyOpen should be recoverable/transient")
  }

  func testProtocolErrorGenericCode_ClassifiedAsPermanent() {
    let err = MTPError.protocolError(code: 0x2009, message: "ObjectNotFound")
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  func testProtocolErrorZeroCode_ClassifiedAsPermanent() {
    let err = MTPError.protocolError(code: 0x0000, message: nil)
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  func testProtocolErrorMaxCode_ClassifiedAsPermanent() {
    let err = MTPError.protocolError(code: 0xFFFF, message: nil)
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  func testWrappedTransientTransport_ClassifiedAsTransient() {
    let err = MTPError.transport(.timeout)
    XCTAssertTrue(classifyMTP(err) == .transient)
  }

  func testWrappedPermanentTransport_ClassifiedAsPermanent() {
    let err = MTPError.transport(.stall)
    XCTAssertTrue(classifyMTP(err) == .permanent)
  }

  // MARK: - 3) Error Equality Edge Cases

  func testTransportIOErrorEquality_DifferentMessages() {
    XCTAssertNotEqual(TransportError.io("msg A"), TransportError.io("msg B"))
    XCTAssertEqual(TransportError.io("same"), TransportError.io("same"))
  }

  func testTransportTimeoutInPhaseEquality_DifferentPhases() {
    XCTAssertNotEqual(
      TransportError.timeoutInPhase(.bulkIn),
      TransportError.timeoutInPhase(.bulkOut))
    XCTAssertEqual(
      TransportError.timeoutInPhase(.responseWait),
      TransportError.timeoutInPhase(.responseWait))
  }

  func testMTPErrorProtocolEquality_DifferentCodes() {
    XCTAssertNotEqual(
      MTPError.protocolError(code: 0x2001, message: nil),
      MTPError.protocolError(code: 0x2009, message: nil))
  }

  func testMTPErrorProtocolEquality_SameCodeDifferentMessage() {
    XCTAssertNotEqual(
      MTPError.protocolError(code: 0x2001, message: "A"),
      MTPError.protocolError(code: 0x2001, message: "B"))
  }

  func testMTPErrorVerificationEquality_DifferentValues() {
    XCTAssertNotEqual(
      MTPError.verificationFailed(expected: 100, actual: 50),
      MTPError.verificationFailed(expected: 100, actual: 99))
    XCTAssertEqual(
      MTPError.verificationFailed(expected: 42, actual: 42),
      MTPError.verificationFailed(expected: 42, actual: 42))
  }

  // MARK: - 4) Error Context Preservation Through Deep Chains

  func testFiveLevelWrappingPreservesInnermost() {
    let l0 = TransportError.io("USB bulk pipe reset at offset 0x1234")
    let l1 = MTPError.transport(l0)
    let l2 = MTPError.preconditionFailed("Read failed: \(l1.errorDescription ?? "")")
    let l3 = MTPError.notSupported("Retry aborted: \(l2)")
    let l4: Error = l3

    guard case .notSupported(let msg) = l4 as? MTPError else {
      XCTFail("Expected notSupported at top level"); return
    }
    XCTAssertTrue(msg.contains("USB bulk pipe reset"), "Original message lost in 5-level chain")
    XCTAssertTrue(msg.contains("0x1234"), "Offset context lost")
    XCTAssertTrue(msg.contains("Read failed"), "Middle layer context lost")
    XCTAssertTrue(msg.contains("Retry aborted"), "Outer layer context lost")
  }

  func testErrorContextWithSpecialCharacters() {
    let msg = "USB I/O: path=/dev/usb001 status='EPIPE' errno=32"
    let inner = TransportError.io(msg)
    let mtp = MTPError.transport(inner)
    XCTAssertTrue(mtp.errorDescription?.contains("EPIPE") ?? false)
    XCTAssertTrue(mtp.errorDescription?.contains("errno=32") ?? false)
  }

  func testErrorContextWithUnicodeCharacters() {
    let msg = "Gerät getrennt — Übertragung fehlgeschlagen"
    let inner = TransportError.io(msg)
    let mtp = MTPError.transport(inner)
    XCTAssertEqual(mtp.errorDescription, msg)
  }

  // MARK: - 5) Cascading Failures (Operation → Cleanup → Journal)

  func testCascadingFailure_OperationFailsThenCleanupFails() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.closeSession), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Operation fails
    var operationError: TransportError?
    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    } catch let err as TransportError {
      operationError = err
    }
    XCTAssertEqual(operationError, .timeout)

    // Cleanup also fails (cascading)
    var cleanupError: TransportError?
    do {
      try await link.closeSession()
    } catch let err as TransportError {
      cleanupError = err
    }
    XCTAssertEqual(cleanupError, .noDevice, "Cleanup should fail with disconnected")
  }

  func testCascadingFailure_DeleteThenMoveFail() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.deleteObject), error: .accessDenied, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.moveObject), error: .io("Device locked"), repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var errors: [TransportError] = []
    do {
      try await link.deleteObject(handle: 3)
    } catch let err as TransportError {
      errors.append(err)
    }
    do {
      try await link.moveObject(handle: 3, to: MTPStorageID(raw: 0x0001_0001), parent: 1)
    } catch let err as TransportError {
      errors.append(err)
    }

    XCTAssertEqual(errors.count, 2)
    XCTAssertEqual(errors[0], .accessDenied)
    if case .io(let msg) = errors[1] {
      XCTAssertEqual(msg, "Device locked")
    } else {
      XCTFail("Expected io error for move")
    }
  }

  func testCascadingFailure_ThreePhaseFault_ReadInfoDeleteSequence() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .busy, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.deleteObject), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var errors: [TransportError] = []
    do { _ = try await link.getObjectInfos([1]) } catch let e as TransportError { errors.append(e) }
    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    } catch let e as TransportError { errors.append(e) }
    do { try await link.deleteObject(handle: 3) } catch let e as TransportError { errors.append(e) }

    XCTAssertEqual(errors, [.timeout, .busy, .noDevice])
  }

  // MARK: - 6) Recovery Chain Ordering

  func testFallbackLadder_FirstRungSucceeds_SkipsRest() async throws {
    nonisolated(unsafe) var secondCalled = false
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "fast") { 42 },
      FallbackRung(name: "slow") {
        secondCalled = true
        return 99
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "fast")
    XCTAssertEqual(result.attempts.count, 1)
    XCTAssertFalse(secondCalled, "Second rung should not execute")
  }

  func testFallbackLadder_AllFail_ErrorHistoryOrder() async throws {
    let names = ["alpha", "bravo", "charlie", "delta"]
    let rungs: [FallbackRung<Void>] = names.map { name in
      FallbackRung(name: name) { throw MTPError.timeout }
    }

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.map(\.name), names, "Attempt order must match rung order")
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
      XCTAssertTrue(err.attempts.allSatisfy { $0.durationMs >= 0 })
    }
  }

  func testFallbackLadder_MiddleRungSucceeds() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "a") { throw MTPError.timeout },
      FallbackRung(name: "b") { throw MTPError.busy },
      FallbackRung(name: "c") { "found-it" },
      FallbackRung(name: "d") { "unreachable" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "found-it")
    XCTAssertEqual(result.winningRung, "c")
    XCTAssertEqual(result.attempts.count, 3, "Should have 2 failures + 1 success")
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertFalse(result.attempts[1].succeeded)
    XCTAssertTrue(result.attempts[2].succeeded)
  }

  func testFallbackLadder_MixedErrorTypes_PreservedInAttempts() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "r1") { throw MTPError.transport(.stall) },
      FallbackRung(name: "r2") { throw MTPError.storageFull },
      FallbackRung(name: "r3") { throw MTPError.verificationFailed(expected: 100, actual: 0) },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      XCTAssertTrue(err.attempts[0].error?.contains("stall") ?? false)
      XCTAssertTrue(err.attempts[1].error?.contains("storageFull") ?? false
                    || err.attempts[1].error?.contains("Storage") ?? false)
      XCTAssertTrue(err.attempts[2].error?.contains("verification") ?? false
                    || err.attempts[2].error?.contains("Verification") ?? false)
    }
  }

  // MARK: - 7) Concurrent Error Handling Edge Cases

  func testConcurrentFaultScheduleAccess() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 10)
    ])

    // Access from multiple concurrent tasks
    let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
      for i in 0..<10 {
        group.addTask {
          let err = schedule.check(operation: .getStorageIDs, callIndex: i, byteOffset: nil)
          return err != nil
        }
      }
      var collected: [Bool] = []
      for await r in group { collected.append(r) }
      return collected
    }

    let firedCount = results.filter { $0 }.count
    XCTAssertEqual(firedCount, 10, "All 10 faults should fire under concurrent access")
  }

  func testConcurrentDynamicFaultAdditionAndConsumption() async throws {
    let schedule = FaultSchedule()

    // Add faults from one task, consume from another
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for _ in 0..<5 {
          schedule.add(ScheduledFault(
            trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 1))
        }
      }
      group.addTask {
        // Small delay to let additions happen
        try? await Task.sleep(nanoseconds: 1_000_000)
        for i in 0..<10 {
          _ = schedule.check(operation: .getDeviceInfo, callIndex: i, byteOffset: nil)
        }
      }
    }
    // No crash = success (tests thread safety)
  }

  func testConcurrentFallbackLadders_IsolatedResults() async throws {
    async let r1: FallbackResult<Int> = FallbackLadder.execute([
      FallbackRung(name: "1a") { throw MTPError.timeout },
      FallbackRung(name: "1b") { 1 },
    ])
    async let r2: FallbackResult<Int> = FallbackLadder.execute([
      FallbackRung(name: "2a") { throw MTPError.busy },
      FallbackRung(name: "2b") { throw MTPError.storageFull },
      FallbackRung(name: "2c") { 2 },
    ])
    async let r3: FallbackResult<Int> = FallbackLadder.execute([
      FallbackRung(name: "3a") { 3 },
    ])

    let v1 = try await r1.value
    let v2 = try await r2.value
    let v3 = try await r3.value
    XCTAssertEqual(v1, 1)
    XCTAssertEqual(v2, 2)
    XCTAssertEqual(v3, 3)
  }

  func testTaskGroupCollectsAllErrorTypes() async throws {
    let collected = await withTaskGroup(
      of: (String, MTPError).self, returning: [(String, MTPError)].self
    ) { group in
      let pairs: [(String, MTPError)] = [
        ("timeout", .timeout),
        ("busy", .busy),
        ("disconnected", .deviceDisconnected),
        ("storage-full", .storageFull),
        ("not-found", .objectNotFound),
        ("write-protected", .objectWriteProtected),
        ("read-only", .readOnly),
        ("session-busy", .sessionBusy),
      ]
      for (tag, err) in pairs {
        group.addTask { (tag, err) }
      }
      var results: [(String, MTPError)] = []
      for await item in group { results.append(item) }
      return results
    }

    XCTAssertEqual(collected.count, 8)
    let tags = Set(collected.map(\.0))
    XCTAssertTrue(tags.contains("timeout"))
    XCTAssertTrue(tags.contains("busy"))
    XCTAssertTrue(tags.contains("disconnected"))
  }

  // MARK: - 8) Error Description and Localization Edge Cases

  func testMTPErrorInternalErrorFactory() {
    let err = MTPError.internalError("custom message")
    if case .notSupported(let msg) = err {
      XCTAssertEqual(msg, "custom message")
    } else {
      XCTFail("internalError should map to .notSupported")
    }
  }

  func testProtocolErrorDescriptionAtBoundaries() {
    let zero = MTPError.protocolError(code: 0x0000, message: nil)
    XCTAssertNotNil(zero.errorDescription)
    XCTAssertTrue(zero.errorDescription?.contains("0x0000") ?? false)

    let max = MTPError.protocolError(code: 0xFFFF, message: nil)
    XCTAssertNotNil(max.errorDescription)
    XCTAssertTrue(max.errorDescription?.lowercased().contains("ffff") ?? false)
  }

  func testProtocolErrorWithCustomMessage() {
    let err = MTPError.protocolError(code: 0x2005, message: "Operation not supported")
    XCTAssertTrue(err.errorDescription?.contains("Operation not supported") ?? false)
    XCTAssertTrue(err.errorDescription?.contains("2005") ?? false)
  }

  func testProtocolError201D_SpecialHandling() {
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertTrue(err.errorDescription?.contains("write request rejected") ?? false)
    XCTAssertNotNil(err.failureReason)
    XCTAssertTrue(err.failureReason?.contains("rejected") ?? false)
    XCTAssertNotNil(err.recoverySuggestion)
    XCTAssertTrue(err.recoverySuggestion?.contains("writable folder") ?? false)
  }

  func testTransportErrorRecoverySuggestions_Completeness() {
    let withRecovery: [TransportError] = [.noDevice, .accessDenied, .timeout, .busy, .stall]
    for err in withRecovery {
      XCTAssertNotNil(err.recoverySuggestion, "\(err) should have a recovery suggestion")
    }
  }

  func testTransportErrorFailureReasons_Subset() {
    XCTAssertNotNil(TransportError.noDevice.failureReason)
    XCTAssertNotNil(TransportError.accessDenied.failureReason)
    XCTAssertNotNil(TransportError.timeout.failureReason)
  }

  func testActionableDescriptionFallback_PlainError() {
    struct PlainError: Error {}
    let desc = actionableDescription(for: PlainError())
    XCTAssertFalse(desc.isEmpty, "Plain error should still produce a description")
  }

  func testActionableDescriptionFallback_LocalizedError() {
    struct CustomLocal: LocalizedError {
      var errorDescription: String? { "Custom localized msg" }
    }
    let desc = actionableDescription(for: CustomLocal())
    XCTAssertEqual(desc, "Custom localized msg")
  }

  // MARK: - 9) StorageIDOutcome Coverage

  func testStorageIDOutcome_AllCasesInstantiable() {
    let outcomes: [StorageIDOutcome] = [
      .success([MTPStorageID(raw: 0x0001_0001)]),
      .zeroStorages,
      .responseOnly,
      .timeout,
      .permanentError(0x2009),
    ]
    XCTAssertEqual(outcomes.count, 5)
  }

  func testStorageIDOutcome_SuccessWithEmptyArray() {
    if case .success(let ids) = StorageIDOutcome.success([]) {
      XCTAssertTrue(ids.isEmpty)
    } else {
      XCTFail("Expected success case")
    }
  }

  func testStorageIDOutcome_PermanentErrorCode() {
    if case .permanentError(let code) = StorageIDOutcome.permanentError(0x201D) {
      XCTAssertEqual(code, 0x201D)
    } else {
      XCTFail("Expected permanentError case")
    }
  }

  // MARK: - 10) TransactionLog Edge Cases

  func testTransactionLogCapacity_EvictsOldRecords() async {
    let log = TransactionLog()
    for i in 0..<1100 {
      let rec = TransactionRecord(
        txID: UInt32(i), opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
        sessionID: 1, startedAt: Date(), duration: 0.01,
        bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
      await log.append(rec)
    }
    let recent = await log.recent(limit: 2000)
    XCTAssertLessThanOrEqual(recent.count, 1000, "Log should cap at maxRecords")
    XCTAssertEqual(recent.last?.txID, 1099, "Most recent should be preserved")
  }

  func testTransactionLogClear_RemovesAll() async {
    let log = TransactionLog()
    let rec = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.01,
      bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
    await log.append(rec)
    await log.clear()
    let recent = await log.recent(limit: 10)
    XCTAssertTrue(recent.isEmpty)
  }

  func testTransactionLogDump_EmptyLogReturnsValidJSON() async {
    let log = TransactionLog()
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.hasPrefix("["), "Empty dump should be valid JSON array")
  }

  func testTransactionLogDump_RedactsMultipleHexSequences() async {
    let log = TransactionLog()
    let rec = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.01,
      bytesIn: 0, bytesOut: 0, outcomeClass: .deviceError,
      errorDescription: "Serial AABB1122CCDD3344 and ID EE00FF0011223344 failed")
    await log.append(rec)
    let redacted = await log.dump(redacting: true)
    XCTAssertFalse(redacted.contains("AABB1122"))
    XCTAssertFalse(redacted.contains("EE00FF00"))
    XCTAssertTrue(redacted.contains("<redacted>"))
  }

  // MARK: - 11) Timeout Escalation Patterns

  func testTimeoutEscalation_MultiplePhasesInSequence() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getStorageInfo), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Timeout on first operation
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout")
    } catch let e as TransportError {
      XCTAssertEqual(e, .timeout)
    }

    // Timeout escalates to a different operation
    do {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
      XCTFail("Expected timeout")
    } catch let e as TransportError {
      XCTAssertEqual(e, .timeout)
    }

    // Final escalation: disconnect
    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected disconnect")
    } catch let e as TransportError {
      XCTAssertEqual(e, .noDevice)
    }
  }

  func testBackoffConfigClamp_BeyondArrayBounds() {
    let config = StorageIDRetryConfig(maxRetries: 10, backoffMs: [100, 200, 400])
    for attempt in 0..<10 {
      let idx = min(attempt, config.backoffMs.count - 1)
      let delay = config.backoffMs[idx]
      XCTAssertGreaterThan(delay, 0)
      if attempt >= config.backoffMs.count {
        XCTAssertEqual(delay, 400, "Should clamp to last value")
      }
    }
  }

  func testBackoffConfigSingleEntry() {
    let config = StorageIDRetryConfig(maxRetries: 5, backoffMs: [500])
    for attempt in 0..<5 {
      let idx = min(attempt, config.backoffMs.count - 1)
      XCTAssertEqual(config.backoffMs[idx], 500)
    }
  }

  // MARK: - 12) FaultError → TransportError Mapping Exhaustive

  func testFaultErrorProtocolError_DifferentCodes() {
    let codes: [UInt16] = [0x2001, 0x2003, 0x2005, 0x2009, 0x201D, 0x201E]
    for code in codes {
      let fault = FaultError.protocolError(code: code)
      if case .io(let msg) = fault.transportError {
        XCTAssertTrue(msg.contains("Protocol error"), "Code \(code) should map to io with message")
      } else {
        XCTFail("protocolError(\(code)) should map to .io")
      }
    }
  }

  func testFaultErrorIOEmptyString() {
    let fault = FaultError.io("")
    if case .io(let msg) = fault.transportError {
      XCTAssertEqual(msg, "")
    } else {
      XCTFail("Expected io case")
    }
  }

  func testFaultErrorIOLongMessage() {
    let longMsg = String(repeating: "x", count: 10_000)
    let fault = FaultError.io(longMsg)
    if case .io(let msg) = fault.transportError {
      XCTAssertEqual(msg.count, 10_000)
    } else {
      XCTFail("Expected io case")
    }
  }

  // MARK: - 13) Recovery After Fault Exhaustion Across Operations

  func testFaultExhaustion_OperationSucceedsAfterAllFaultsConsumed() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 2),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // 2 timeouts
    for _ in 0..<2 {
      do { _ = try await link.getStorageIDs() } catch {}
    }
    // 1 busy
    do { _ = try await link.getStorageIDs() } catch {}
    // Now succeeds
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty, "Should succeed after all faults consumed")
  }

  func testOpenUSBFault_BlocksEntireSession() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openUSB), error: .accessDenied, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected access denied")
    } catch let err as TransportError {
      XCTAssertEqual(err, .accessDenied)
    }
  }

  // MARK: - Helpers

  private enum ErrorClass { case transient, permanent }

  private func classifyTransport(_ error: TransportError) -> ErrorClass {
    switch error {
    case .timeout, .busy: return .transient
    case .timeoutInPhase: return .transient
    default: return .permanent
    }
  }

  private func classifyMTP(_ error: MTPError) -> ErrorClass {
    switch error {
    case .timeout, .busy, .sessionBusy:
      return .transient
    case .transport(let t):
      return classifyTransport(t)
    case .protocolError(let code, _) where code == 0x201E:
      return .transient
    default:
      return .permanent
    }
  }
}
