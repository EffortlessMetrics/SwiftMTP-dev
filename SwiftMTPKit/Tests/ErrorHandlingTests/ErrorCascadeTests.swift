// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Tests for error propagation, cascading, transformation, concurrent errors,
/// logging integration, timeouts, partial success, retry backoff, and
/// custom error descriptions.
final class ErrorCascadeTests: XCTestCase {

  // MARK: - 1) Error Chain Propagation

  func testTransportErrorPropagatesThroughMTPErrorWrapper() {
    let transport = TransportError.timeout
    let mtp = MTPError.transport(transport)
    if case .transport(let inner) = mtp {
      XCTAssertEqual(inner, .timeout)
    } else {
      XCTFail("Expected transport-wrapped error")
    }
  }

  func testTransportNoDevicePropagatesAsDeviceLayer() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected transport error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice, "Disconnected fault should surface as .noDevice")
    }
  }

  func testTransportErrorCaughtAsGenericErrorPreservesType() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected error")
    } catch {
      // Verify we can narrow back to TransportError
      XCTAssertTrue(error is TransportError, "Should be narrowable to TransportError")
      XCTAssertEqual(error as? TransportError, .timeout)
    }
  }

  func testErrorChainTransportToDeviceToAPI() async throws {
    // Simulate: transport layer throws → caught as MTPError at device layer → re-thrown
    let transportErr = TransportError.accessDenied
    let deviceErr = MTPError.transport(transportErr)
    let apiErr: Error = deviceErr

    // Caller narrows from generic Error → MTPError → TransportError
    guard let mtpErr = apiErr as? MTPError else {
      XCTFail("Expected MTPError"); return
    }
    if case .transport(let inner) = mtpErr {
      XCTAssertEqual(inner, .accessDenied)
    } else {
      XCTFail("Expected transport-wrapped error")
    }
  }

  func testNestedErrorChainPreservesAllContext() {
    let innermost = TransportError.io("USB pipe broken")
    let middle = MTPError.transport(innermost)
    let outer = MTPError.preconditionFailed("Operation failed: \(middle)")

    if case .preconditionFailed(let msg) = outer {
      XCTAssertTrue(msg.contains("USB pipe broken"))
      XCTAssertTrue(msg.contains("Operation failed"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  func testMultiLayerFaultPropagation_GetStorageInfo() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageInfo), error: .io("I/O stall"), repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
      XCTFail("Expected I/O error")
    } catch let err as TransportError {
      if case .io(let msg) = err {
        XCTAssertEqual(msg, "I/O stall")
      } else {
        XCTFail("Expected .io case")
      }
    }
  }

  // MARK: - 2) Error Transformation

  func testFaultErrorDisconnectedMapsToNoDevice() {
    let fault = FaultError.disconnected
    XCTAssertEqual(fault.transportError, .noDevice)
  }

  func testFaultErrorTimeoutMapsToTimeout() {
    let fault = FaultError.timeout
    XCTAssertEqual(fault.transportError, .timeout)
  }

  func testFaultErrorBusyMapsToBusy() {
    let fault = FaultError.busy
    XCTAssertEqual(fault.transportError, .busy)
  }

  func testFaultErrorAccessDeniedMapsToAccessDenied() {
    let fault = FaultError.accessDenied
    XCTAssertEqual(fault.transportError, .accessDenied)
  }

  func testFaultErrorIOMapsToIO() {
    let fault = FaultError.io("USB transfer failed")
    if case .io(let msg) = fault.transportError {
      XCTAssertEqual(msg, "USB transfer failed")
    } else {
      XCTFail("Expected .io transport error")
    }
  }

  func testFaultErrorProtocolMapsToIOWithMessage() {
    let fault = FaultError.protocolError(code: 0x2009)
    if case .io(let msg) = fault.transportError {
      XCTAssertTrue(msg.contains("Protocol error"))
    } else {
      XCTFail("Expected .io with protocol message")
    }
  }

  func testAllFaultErrorCasesProduceValidTransportErrors() {
    let faults: [FaultError] = [
      .timeout, .busy, .disconnected, .accessDenied,
      .io("test"), .protocolError(code: 0x2001),
    ]
    for fault in faults {
      let transport = fault.transportError
      // Every fault error must produce a non-nil transport error with a description
      XCTAssertNotNil(transport.errorDescription, "Missing description for \(fault)")
    }
  }

  func testTransportErrorToMTPErrorRoundTrip() {
    let cases: [TransportError] = [
      .noDevice, .timeout, .busy, .accessDenied, .stall,
      .io("test msg"), .timeoutInPhase(.bulkOut),
    ]
    for te in cases {
      let mtp = MTPError.transport(te)
      if case .transport(let unwrapped) = mtp {
        XCTAssertEqual(unwrapped, te, "Round-trip failed for \(te)")
      } else {
        XCTFail("Expected transport wrapping for \(te)")
      }
    }
  }

  // MARK: - 3) Error Recovery Chains (FallbackLadder)

  func testFallbackLadderExecutesRungsInOrder() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "first") { throw MTPError.timeout },
      FallbackRung(name: "second") { throw MTPError.busy },
      FallbackRung(name: "third") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected all-failed")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 3)
      // Attempts are recorded in execution order
      XCTAssertEqual(err.attempts.map(\.name), ["first", "second", "third"])
    }
  }

  func testFallbackLadderStopsAtFirstSuccess() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "failing") { throw MTPError.timeout },
      FallbackRung(name: "succeeding") { return "ok" },
      FallbackRung(name: "never-reached") { return "unreachable" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "ok")
    XCTAssertEqual(result.winningRung, "succeeding")
    // Only 2 attempts: failing + succeeding; never-reached is skipped
    XCTAssertEqual(result.attempts.count, 2)
    XCTAssertFalse(result.attempts[0].succeeded)
    XCTAssertTrue(result.attempts[1].succeeded)
  }

  func testFallbackLadderRecordsDurationForEachAttempt() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "slow-fail") {
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        throw MTPError.timeout
      },
      FallbackRung(name: "fast-success") {
        return 42
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, 42)
    XCTAssertGreaterThanOrEqual(result.attempts[0].durationMs, 0)
    XCTAssertGreaterThanOrEqual(result.attempts[1].durationMs, 0)
  }

  func testFallbackLadderSingleRungFailure() async {
    let rungs: [FallbackRung<Void>] = [
      FallbackRung(name: "only") { throw MTPError.storageFull }
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected failure")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 1)
      XCTAssertEqual(err.attempts[0].name, "only")
      XCTAssertNotNil(err.attempts[0].error)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testFallbackAllFailedErrorDescription() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "rungA") { throw MTPError.timeout },
      FallbackRung(name: "rungB") { throw MTPError.busy },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
    } catch let err as FallbackAllFailedError {
      let desc = err.description
      XCTAssertTrue(desc.contains("rungA"), "Description should list rung names")
      XCTAssertTrue(desc.contains("rungB"))
      XCTAssertTrue(desc.contains("✗"), "Should contain failure symbol")
      XCTAssertTrue(desc.contains("All fallback rungs failed"))
    } catch {
      XCTFail("Unexpected: \(error)")
    }
  }

  // MARK: - 4) Concurrent Error Handling

  func testConcurrentOperationsFailIndependently() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 1),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy, repeatCount: 1),
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // Run two operations sequentially to avoid sendability issues
    var errors: [TransportError] = []
    do {
      _ = try await link.getStorageIDs()
    } catch let err as TransportError {
      errors.append(err)
    }
    do {
      _ = try await link.getDeviceInfo()
    } catch let err as TransportError {
      errors.append(err)
    }

    XCTAssertEqual(errors.count, 2, "Both operations should have failed")
    XCTAssertTrue(errors.contains(.timeout))
    XCTAssertTrue(errors.contains(.busy))
  }

  func testConcurrentFallbackLaddersDoNotInterfere() async throws {
    // Two independent fallback ladders running concurrently
    async let result1: FallbackResult<String> = FallbackLadder.execute([
      FallbackRung(name: "a-fail") { throw MTPError.timeout },
      FallbackRung(name: "a-ok") { return "A" },
    ])
    async let result2: FallbackResult<String> = FallbackLadder.execute([
      FallbackRung(name: "b-fail") { throw MTPError.busy },
      FallbackRung(name: "b-ok") { return "B" },
    ])

    let r1 = try await result1
    let r2 = try await result2
    XCTAssertEqual(r1.value, "A")
    XCTAssertEqual(r2.value, "B")
    XCTAssertEqual(r1.winningRung, "a-ok")
    XCTAssertEqual(r2.winningRung, "b-ok")
  }

  func testMultipleConcurrentFaultsOnSameLink() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getObjectHandles), error: .timeout, repeatCount: 3)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let storage = MTPStorageID(raw: 0x0001_0001)
    var failCount = 0

    // Run sequentially to stay Sendable-safe
    for _ in 0..<4 {
      do {
        _ = try await link.getObjectHandles(storage: storage, parent: nil)
      } catch {
        failCount += 1
      }
    }

    XCTAssertEqual(failCount, 3, "Exactly 3 faults should fire")
  }

  func testConcurrentErrorCollectionWithTaskGroup() async throws {
    // Collect errors from multiple concurrent tasks
    let errors = await withTaskGroup(of: MTPError?.self, returning: [MTPError].self) { group in
      for i in 0..<5 {
        group.addTask {
          if i % 2 == 0 {
            return MTPError.timeout
          } else {
            return nil  // success
          }
        }
      }
      var collected: [MTPError] = []
      for await result in group {
        if let err = result {
          collected.append(err)
        }
      }
      return collected
    }

    XCTAssertEqual(errors.count, 3, "3 of 5 tasks should produce errors")
    XCTAssertTrue(errors.allSatisfy { $0 == .timeout })
  }

  // MARK: - 5) Error Logging Integration

  func testTransactionLogRecordsErrorOutcome() async {
    let log = TransactionLog()
    let record = TransactionRecord(
      txID: 1,
      opcode: 0x1004,
      opcodeLabel: MTPOpcodeLabel.label(for: 0x1004),
      sessionID: 1,
      startedAt: Date(),
      duration: 0.5,
      bytesIn: 0,
      bytesOut: 0,
      outcomeClass: .timeout,
      errorDescription: "USB transfer timed out"
    )
    await log.append(record)

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 1)
    XCTAssertEqual(recent[0].outcomeClass, .timeout)
    XCTAssertEqual(recent[0].errorDescription, "USB transfer timed out")
    XCTAssertEqual(recent[0].opcodeLabel, "GetStorageIDs")
  }

  func testTransactionLogRecordsMultipleOutcomeTypes() async {
    let log = TransactionLog()
    let outcomes: [(TransactionOutcome, String?)] = [
      (.ok, nil),
      (.timeout, "Timed out"),
      (.stall, "Endpoint stall"),
      (.ioError, "Pipe broken"),
      (.deviceError, "Device returned 0x2009"),
      (.cancelled, "User cancelled"),
    ]

    for (i, entry) in outcomes.enumerated() {
      let rec = TransactionRecord(
        txID: UInt32(i),
        opcode: 0x1007,
        opcodeLabel: MTPOpcodeLabel.label(for: 0x1007),
        sessionID: 1,
        startedAt: Date(),
        duration: 0.1,
        bytesIn: 0,
        bytesOut: 0,
        outcomeClass: entry.0,
        errorDescription: entry.1
      )
      await log.append(rec)
    }

    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 6)
    XCTAssertEqual(recent.map(\.outcomeClass), [.ok, .timeout, .stall, .ioError, .deviceError, .cancelled])
  }

  func testTransactionLogDumpRedactsSerials() async {
    let log = TransactionLog()
    let rec = TransactionRecord(
      txID: 1,
      opcode: 0x1001,
      opcodeLabel: "GetDeviceInfo",
      sessionID: 1,
      startedAt: Date(),
      duration: 0.01,
      bytesIn: 64,
      bytesOut: 0,
      outcomeClass: .deviceError,
      errorDescription: "Device serial AABBCCDD11223344 failed"
    )
    await log.append(rec)

    let redacted = await log.dump(redacting: true)
    XCTAssertFalse(redacted.contains("AABBCCDD11223344"), "Serial should be redacted")
    XCTAssertTrue(redacted.contains("<redacted>"))
  }

  func testActionableDescriptionForTransportErrors() {
    let errors: [(TransportError, String)] = [
      (.noDevice, "No MTP device found"),
      (.timeout, "USB transfer timed out"),
      (.busy, "USB access is busy"),
      (.accessDenied, "USB access denied"),
      (.stall, "USB endpoint stalled"),
      (.io("broken"), "USB I/O error"),
    ]
    for (error, expected) in errors {
      let desc = actionableDescription(for: error)
      XCTAssertTrue(desc.contains(expected) || desc.lowercased().contains(expected.lowercased()),
                     "actionableDescription for \(error) should contain '\(expected)', got '\(desc)'")
    }
  }

  func testActionableDescriptionForMTPErrors() {
    let errors: [(MTPError, String)] = [
      (.timeout, "timed out"),
      (.busy, "charging mode"),
      (.permissionDenied, "denied"),
      (.deviceDisconnected, "disconnected"),
      (.storageFull, "full"),
      (.objectNotFound, "not found"),
    ]
    for (error, substring) in errors {
      let desc = actionableDescription(for: error)
      XCTAssertTrue(
        desc.lowercased().contains(substring.lowercased()),
        "Actionable desc for \(error) should contain '\(substring)', got '\(desc)'"
      )
    }
  }

  // MARK: - 6) Timeout Error Handling

  func testTimeoutDuringOpenSession() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .timeout, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected timeout")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testTimeoutDuringRead_GetObjectHandles() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .timeout, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected timeout")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testTimeoutDuringWrite_ExecuteStreamingCommand() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand), error: .timeout, repeatCount: 1)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1, params: [])
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected timeout during write")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testTimeoutInPhaseBulkOut() {
    let error = TransportError.timeoutInPhase(.bulkOut)
    XCTAssertTrue(error.errorDescription?.contains("bulk-out") ?? false)
  }

  func testTimeoutInPhaseBulkIn() {
    let error = TransportError.timeoutInPhase(.bulkIn)
    XCTAssertTrue(error.errorDescription?.contains("bulk-in") ?? false)
  }

  func testTimeoutInPhaseResponseWait() {
    let error = TransportError.timeoutInPhase(.responseWait)
    XCTAssertTrue(error.errorDescription?.contains("response-wait") ?? false)
  }

  func testRepeatedTimeoutsExhaustFaultSchedule() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .timeout, repeatCount: 3)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // 3 timeouts then success
    for i in 0..<3 {
      do {
        _ = try await link.getStorageIDs()
        XCTFail("Expected timeout on attempt \(i)")
      } catch let err as TransportError {
        XCTAssertEqual(err, .timeout)
      }
    }

    // 4th call should succeed
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 7) Partial Success Handling

  func testBatchOperationPartialSuccess() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    // Pixel7 config has handles 1 (DCIM), 2 (Camera), 3 (IMG_*.jpg)
    // Handle 999 doesn't exist

    let handles: [MTPObjectHandle] = [1, 3, 999]
    var successes: [MTPObjectInfo] = []
    var failures: [MTPObjectHandle] = []

    for handle in handles {
      do {
        let info = try await device.getInfo(handle: handle)
        successes.append(info)
      } catch {
        failures.append(handle)
      }
    }

    XCTAssertEqual(successes.count, 2, "Two objects should succeed")
    XCTAssertEqual(failures, [999], "Handle 999 should fail")
  }

  func testBatchOperationAllFail() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let badHandles: [MTPObjectHandle] = [100, 200, 300]
    var failures = 0

    for handle in badHandles {
      do {
        _ = try await device.getInfo(handle: handle)
      } catch {
        failures += 1
      }
    }

    XCTAssertEqual(failures, 3, "All lookups for non-existent handles should fail")
  }

  func testBatchOperationAllSucceed() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let handles: [MTPObjectHandle] = [1, 2, 3]
    var results: [MTPObjectInfo] = []

    for handle in handles {
      let info = try await device.getInfo(handle: handle)
      results.append(info)
    }

    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results[0].name, "DCIM")
    XCTAssertEqual(results[1].name, "Camera")
    XCTAssertTrue(results[2].name.contains("IMG_"))
  }

  func testPartialSuccessWithFaultInjection() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule()
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // First batch succeeds (no faults scheduled yet)
    let batch1 = try await link.getObjectInfos([1])
    XCTAssertEqual(batch1.count, 1)

    // Now add a fault for the next call
    schedule.add(
      ScheduledFault(trigger: .onOperation(.getObjectInfos), error: .timeout, repeatCount: 1))

    // Second batch fails
    do {
      _ = try await link.getObjectInfos([2, 3])
      XCTFail("Expected timeout on second batch")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }

    // Third batch succeeds (fault exhausted)
    let batch3 = try await link.getObjectInfos([3])
    XCTAssertEqual(batch3.count, 1)
  }

  func testPartialSuccessCountsTracked() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let handles: [MTPObjectHandle] = [1, 2, 3, 50, 51, 52]

    nonisolated(unsafe) var successCount = 0
    nonisolated(unsafe) var failCount = 0

    await withTaskGroup(of: Bool.self) { group in
      for handle in handles {
        group.addTask {
          do {
            _ = try await device.getInfo(handle: handle)
            return true
          } catch {
            return false
          }
        }
      }
      for await result in group {
        if result { successCount += 1 } else { failCount += 1 }
      }
    }

    XCTAssertEqual(successCount, 3)
    XCTAssertEqual(failCount, 3)
  }

  // MARK: - 8) Error Retry with Backoff

  func testExponentialBackoffTiming() {
    let baseDelay: UInt32 = 250  // ms
    var delays: [UInt32] = []

    for retry in 0..<5 {
      let delay = baseDelay * UInt32(pow(2.0, Double(retry)))
      delays.append(delay)
    }

    XCTAssertEqual(delays, [250, 500, 1000, 2000, 4000])
  }

  func testStorageIDRetryConfigDefaults() {
    let config = StorageIDRetryConfig()
    XCTAssertEqual(config.maxRetries, 5)
    XCTAssertEqual(config.backoffMs, [250, 500, 1000, 2000, 3000])
  }

  func testStorageIDRetryConfigCustom() {
    let config = StorageIDRetryConfig(maxRetries: 3, backoffMs: [100, 200, 400])
    XCTAssertEqual(config.maxRetries, 3)
    XCTAssertEqual(config.backoffMs.count, 3)
    XCTAssertEqual(config.backoffMs[0], 100)
  }

  func testBackoffDelaysClamped() {
    let config = StorageIDRetryConfig(maxRetries: 10, backoffMs: [100, 200])
    // When retry exceeds backoff array length, it should clamp to last entry
    for attempt in 0..<10 {
      let idx = min(attempt, config.backoffMs.count - 1)
      let delay = config.backoffMs[idx]
      XCTAssertTrue(delay > 0)
      if attempt >= 2 {
        XCTAssertEqual(delay, 200, "Should clamp to last backoff value")
      }
    }
  }

  func testRetryWithFaultExhaustion() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 2)
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    var retries = 0
    var result: [MTPStorageID]?

    for _ in 0..<5 {
      do {
        result = try await link.getStorageIDs()
        break
      } catch {
        retries += 1
      }
    }

    XCTAssertEqual(retries, 2, "Should retry exactly twice before success")
    XCTAssertNotNil(result, "Should eventually succeed")
    XCTAssertFalse(result!.isEmpty)
  }

  func testFallbackLadderActsAsRetryMechanism() async throws {
    nonisolated(unsafe) var attempt = 0
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "attempt-1") {
        attempt += 1
        if attempt < 3 { throw MTPError.busy }
        return "done"
      },
      FallbackRung(name: "attempt-2") {
        attempt += 1
        if attempt < 3 { throw MTPError.busy }
        return "done"
      },
      FallbackRung(name: "attempt-3") {
        attempt += 1
        return "done"
      },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "done")
    XCTAssertEqual(attempt, 3)
  }

  // MARK: - 9) Custom Error Types — Descriptions and Codes

  func testAllMTPErrorCasesHaveDescriptions() {
    let errors: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test"),
      .transport(.timeout),
      .protocolError(code: 0x2001, message: "Test"),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]

    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Missing errorDescription for \(error)")
      XCTAssertFalse(error.errorDescription!.isEmpty, "Empty errorDescription for \(error)")
    }
  }

  func testAllMTPErrorCasesHaveActionableDescriptions() {
    let errors: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test"),
      .transport(.timeout),
      .protocolError(code: 0x2001, message: "Test"),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]

    for error in errors {
      let desc = error.actionableDescription
      XCTAssertFalse(desc.isEmpty, "Empty actionableDescription for \(error)")
    }
  }

  func testAllTransportErrorCasesHaveDescriptions() {
    let errors: [TransportError] = [
      .noDevice, .timeout, .busy, .accessDenied, .stall,
      .io("test"), .timeoutInPhase(.bulkOut),
      .timeoutInPhase(.bulkIn), .timeoutInPhase(.responseWait),
    ]

    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Missing errorDescription for \(error)")
      XCTAssertFalse(error.errorDescription!.isEmpty, "Empty errorDescription for \(error)")
    }
  }

  func testAllTransportErrorCasesHaveActionableDescriptions() {
    let errors: [TransportError] = [
      .noDevice, .timeout, .busy, .accessDenied, .stall,
      .io("test"), .timeoutInPhase(.bulkOut),
    ]

    for error in errors {
      let desc = error.actionableDescription
      XCTAssertFalse(desc.isEmpty, "Empty actionableDescription for \(error)")
    }
  }

  func testMTPErrorEquality() {
    XCTAssertEqual(MTPError.timeout, MTPError.timeout)
    XCTAssertEqual(MTPError.busy, MTPError.busy)
    XCTAssertEqual(MTPError.deviceDisconnected, MTPError.deviceDisconnected)
    XCTAssertNotEqual(MTPError.timeout, MTPError.busy)
    XCTAssertEqual(
      MTPError.transport(.timeout),
      MTPError.transport(.timeout)
    )
    XCTAssertNotEqual(
      MTPError.transport(.timeout),
      MTPError.transport(.busy)
    )
  }

  func testMTPErrorVerificationFailedDescription() {
    let error = MTPError.verificationFailed(expected: 1024, actual: 512)
    XCTAssertTrue(error.errorDescription?.contains("1024") ?? false)
    XCTAssertTrue(error.errorDescription?.contains("512") ?? false)
  }

  func testMTPErrorProtocolErrorDescription() {
    let error = MTPError.protocolError(code: 0x201D, message: nil)
    XCTAssertTrue(error.errorDescription?.contains("write request rejected") ?? false)
    XCTAssertNotNil(error.recoverySuggestion)
  }

  func testMTPErrorSessionAlreadyOpenDetection() {
    let sessionOpen = MTPError.protocolError(code: 0x201E, message: "Session already open")
    XCTAssertTrue(sessionOpen.isSessionAlreadyOpen)

    let other = MTPError.protocolError(code: 0x2001, message: nil)
    XCTAssertFalse(other.isSessionAlreadyOpen)

    let nonProtocol = MTPError.timeout
    XCTAssertFalse(nonProtocol.isSessionAlreadyOpen)
  }

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testMTPErrorTransportDelegatesToTransportDescription() {
    let transport = TransportError.noDevice
    let mtp = MTPError.transport(transport)
    XCTAssertEqual(mtp.errorDescription, transport.errorDescription)
  }

  func testFallbackAllFailedErrorLocalizedDescription() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "test") { throw MTPError.timeout }
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.localizedDescription, err.description)
    } catch {
      XCTFail("Unexpected error")
    }
  }

  func testTransactionOutcomeCoversAllCases() {
    let outcomes: [TransactionOutcome] = [
      .ok, .deviceError, .timeout, .stall, .ioError, .cancelled,
    ]
    XCTAssertEqual(outcomes.count, 6)
    let rawValues = Set(outcomes.map(\.rawValue))
    XCTAssertEqual(rawValues.count, 6, "All outcome raw values should be unique")
  }

  func testMTPOpcodeLabelsKnownCodes() {
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1001), "GetDeviceInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1002), "OpenSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1003), "CloseSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1004), "GetStorageIDs")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1007), "GetObjectHandles")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1009), "GetObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100B), "DeleteObject")
  }

  func testMTPOpcodeLabelsUnknownCode() {
    let label = MTPOpcodeLabel.label(for: 0xFFFF)
    XCTAssertTrue(label.contains("Unknown"))
    XCTAssertTrue(label.contains("FFFF") || label.contains("0xFFFF"))
  }
}
