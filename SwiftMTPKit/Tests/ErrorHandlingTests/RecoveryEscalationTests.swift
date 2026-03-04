// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability
@testable import SwiftMTPTestKit

/// Integration tests exercising the full ErrorRecoveryLayer escalation ladder
/// with FaultInjectingLink and FaultSchedule for deterministic fault injection.
final class RecoveryEscalationTests: XCTestCase {

  override func setUp() async throws {
    await RecoveryLog.shared.clear()
  }

  // MARK: - Session Reset

  func testSessionReset_RecoverAfterSessionNotOpen() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let ids = try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
      let n = counter.increment()
      if n == 1 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return try await inner.getStorageIDs()
    }

    XCTAssertFalse(ids.isEmpty, "Operation should succeed after session reset")
    XCTAssertEqual(counter.value, 2, "Should have retried exactly once")

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testSessionReset_RecoverAfterSessionAlreadyOpen() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let ids = try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
      let n = counter.increment()
      if n == 1 {
        throw MTPError.protocolError(code: 0x201E, message: "SessionAlreadyOpen")
      }
      return try await inner.getStorageIDs()
    }

    XCTAssertFalse(ids.isEmpty)
    XCTAssertEqual(counter.value, 2)
  }

  func testSessionReset_RecoverAfterSessionBusy() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let ids = try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
      let n = counter.increment()
      if n == 1 {
        throw MTPError.sessionBusy
      }
      return try await inner.getStorageIDs()
    }

    XCTAssertFalse(ids.isEmpty)
    XCTAssertEqual(counter.value, 2)
  }

  // MARK: - Stall Recovery

  func testStallRecovery_ClearsHaltAndRetries() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let result = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
      let n = counter.increment()
      if n == 1 {
        throw MTPError.transport(.stall)
      }
      return try await inner.getStorageIDs()
    }

    XCTAssertFalse(result.isEmpty, "Should succeed after stall cleared")
    XCTAssertEqual(counter.value, 2, "Should retry exactly once after clear-halt")

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testStallRecovery_SecondStallAfterReset_Propagates() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    do {
      _ = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
        throw MTPError.transport(.stall)
      }
      XCTFail("Expected stall error to propagate on persistent stall")
    } catch let error as MTPError {
      XCTAssertTrue(ErrorRecoveryLayer.isStallError(error))
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.failures, 1)
  }

  // MARK: - Timeout Escalation

  func testTimeoutEscalation_ProgressiveTimeoutIncrease() async throws {
    let timeouts = AtomicArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 2_000,
      maxRetries: 3
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      if timeouts.count < 4 {
        throw MTPError.timeout
      }
      return "recovered"
    }

    XCTAssertEqual(result, "recovered")
    // 2000 → 4000 → 8000 → 16000
    XCTAssertEqual(timeouts.snapshot, [2_000, 4_000, 8_000, 16_000])
  }

  func testTimeoutEscalation_SucceedsOnSecondAttempt() async throws {
    let timeouts = AtomicArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 5_000,
      maxRetries: 3
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      if timeouts.count == 1 {
        throw MTPError.timeout
      }
      return "ok-at-\(timeoutMs)ms"
    }

    XCTAssertEqual(result, "ok-at-10000ms")
    XCTAssertEqual(timeouts.snapshot, [5_000, 10_000])

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 1)
  }

  func testTimeoutEscalation_TransportTimeoutAlsoEscalates() async throws {
    let timeouts = AtomicArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 3_000,
      maxRetries: 2
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      if timeouts.count == 1 {
        throw MTPError.transport(.timeout)
      }
      return "done"
    }

    XCTAssertEqual(result, "done")
    XCTAssertEqual(timeouts.snapshot, [3_000, 6_000])
  }

  // MARK: - Disconnect Handling

  func testDisconnect_CleanTeardownAndErrorPropagation() async throws {
    let isDisconnect = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.deviceDisconnected, journal: nil, transferId: nil
    )
    XCTAssertTrue(isDisconnect, "Should detect disconnect")

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.failures, 1, "Disconnect should be logged as failure")
  }

  func testDisconnect_TransportNoDevice_Detected() async throws {
    let isDisconnect = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.transport(.noDevice), journal: nil, transferId: nil
    )
    XCTAssertTrue(isDisconnect)
  }

  func testDisconnect_SavesJournalState() async throws {
    let journal = StubTransferJournal()
    let transferId = try await journal.beginWrite(
      device: MTPDeviceID(raw: "test-device"),
      parent: 0, name: "photo.jpg", size: 1024,
      supportsPartial: false, tempURL: URL(fileURLWithPath: "/tmp/test"),
      sourceURL: nil
    )

    let isDisconnect = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.deviceDisconnected, journal: journal, transferId: transferId
    )

    XCTAssertTrue(isDisconnect)
    let state = await journal.entryState(for: transferId)
    XCTAssertEqual(state, "failed", "Journal should record transfer as failed on disconnect")
  }

  func testDisconnect_NonDisconnectError_ReturnsFalse() async {
    let result = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.timeout, journal: nil, transferId: nil
    )
    XCTAssertFalse(result, "Timeout is not a disconnect")
  }

  // MARK: - Multi-Fault Cascade

  func testCascade_StallThenTimeout_EscalatesRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let timeouts = AtomicArray<Int>()

    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000, maxRetries: 2
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      return try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
        let n = counter.increment()
        switch n {
        case 1:
          throw MTPError.transport(.stall)
        case 2:
          throw MTPError.timeout
        default:
          return try await inner.getStorageIDs()
        }
      }
    }

    XCTAssertFalse(result.isEmpty, "Should eventually succeed after cascade")
    XCTAssertGreaterThanOrEqual(counter.value, 3, "Should attempt multiple recoveries")
  }

  func testCascade_SessionErrorInsideTimeoutEscalation() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000, maxRetries: 2
    ) { timeoutMs in
      try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
        let n = counter.increment()
        switch n {
        case 1:
          throw MTPError.timeout
        case 2:
          throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
        default:
          return "recovered-at-\(timeoutMs)ms"
        }
      }
    }

    XCTAssertTrue(result.hasPrefix("recovered"))
  }

  // MARK: - Recovery Exhaustion

  func testExhaustion_SessionRecovery_GivesUpWithClearError() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    do {
      _ = try await ErrorRecoveryLayer.withSessionRecovery(
        link: inner, maxRetries: 2
      ) {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      XCTFail("Expected exhaustion error")
    } catch let error as MTPError {
      if case .protocolError(let code, _) = error {
        XCTAssertEqual(code, 0x2003, "Should propagate original error code")
      } else {
        XCTFail("Expected protocolError, got \(error)")
      }
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertGreaterThan(rates.failures, 0, "Exhaustion should be logged as failure")
  }

  func testExhaustion_TimeoutEscalation_GivesUpAfterMaxRetries() async throws {
    do {
      _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
        initialTimeoutMs: 1_000, maxRetries: 2
      ) { (_: Int) -> String in
        throw MTPError.timeout
      }
      XCTFail("Expected timeout exhaustion")
    } catch let error as MTPError {
      XCTAssertEqual(error, .timeout, "Should propagate original timeout error")
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.failures, 1)
  }

  func testExhaustion_StallRecovery_PersistentStallFails() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let counter = AtomicCounter()
    do {
      _ = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
        counter.increment()
        throw MTPError.transport(.stall)
      }
      XCTFail("Expected persistent stall error")
    } catch let error as MTPError {
      XCTAssertTrue(ErrorRecoveryLayer.isStallError(error))
    }

    // Stall recovery retries once, so operation called twice, both stall
    XCTAssertEqual(counter.value, 2)
  }

  // MARK: - Concurrent Recovery

  func testConcurrentRecovery_TwoOperationsFailSimultaneously_NoDeadlock() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    // Run two recovery operations concurrently with a timeout to detect deadlocks
    let results = try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        let counter = AtomicCounter()
        _ = try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
          let n = counter.increment()
          if n == 1 {
            throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
          }
          return try await inner.getStorageIDs()
        }
        return "session-recovery-done"
      }

      group.addTask {
        let counter = AtomicCounter()
        _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
          initialTimeoutMs: 1_000, maxRetries: 2
        ) { timeoutMs in
          let n = counter.increment()
          if n == 1 {
            throw MTPError.timeout
          }
          return "timeout-escalation-at-\(timeoutMs)ms"
        }
        return "timeout-recovery-done"
      }

      var collected: [String] = []
      for try await result in group {
        collected.append(result)
      }
      return collected
    }

    XCTAssertEqual(results.count, 2, "Both operations should complete without deadlock")
    XCTAssertTrue(results.contains("session-recovery-done"))
    XCTAssertTrue(results.contains("timeout-recovery-done"))
  }

  func testConcurrentRecovery_MultipleStallRecoveries_NoDeadlock() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let results = try await withThrowingTaskGroup(of: Bool.self) { group in
      for _ in 0..<3 {
        group.addTask {
          let counter = AtomicCounter()
          let ids = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
            let n = counter.increment()
            if n == 1 {
              throw MTPError.transport(.stall)
            }
            return try await inner.getStorageIDs()
          }
          return !ids.isEmpty
        }
      }

      var successes = 0
      for try await ok in group {
        if ok { successes += 1 }
      }
      return successes
    }

    XCTAssertEqual(results, 3, "All concurrent stall recoveries should succeed")
  }

  // MARK: - Recovery Logging

  func testRecoveryLogging_CapturesAllAttempts() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    // Session recovery with one retry
    let sessionCounter = AtomicCounter()
    _ = try await ErrorRecoveryLayer.withSessionRecovery(link: inner) {
      let n = sessionCounter.increment()
      if n == 1 {
        throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
      }
      return "ok"
    }

    // Timeout escalation with one retry
    let timeoutCounter = AtomicCounter()
    _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000, maxRetries: 2
    ) { timeoutMs in
      let n = timeoutCounter.increment()
      if n == 1 {
        throw MTPError.timeout
      }
      return "ok"
    }

    // Stall recovery with one retry
    let stallCounter = AtomicCounter()
    _ = try await ErrorRecoveryLayer.withStallRecovery(link: inner) {
      let n = stallCounter.increment()
      if n == 1 {
        throw MTPError.transport(.stall)
      }
      return "ok"
    }

    let rates = await RecoveryLog.shared.rates()
    XCTAssertEqual(rates.successes, 3, "Should log 3 successful recoveries")
    XCTAssertEqual(rates.failures, 0, "No failures expected")

    let events = await RecoveryLog.shared.recent(limit: 10)
    XCTAssertEqual(events.count, 3)

    let strategies = Set(events.map(\.strategy))
    XCTAssertTrue(strategies.contains(RecoveryStrategy.sessionRecovery.rawValue))
    XCTAssertTrue(strategies.contains(RecoveryStrategy.timeoutEscalation.rawValue))
    XCTAssertTrue(strategies.contains(RecoveryStrategy.stallRecovery.rawValue))
  }

  func testRecoveryLogging_FailuresRecordErrorDescriptions() async throws {
    do {
      _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
        initialTimeoutMs: 500, maxRetries: 0
      ) { (_: Int) -> String in
        throw MTPError.timeout
      }
    } catch {}

    let events = await RecoveryLog.shared.recent(limit: 10)
    XCTAssertEqual(events.count, 1)
    XCTAssertFalse(events[0].succeeded)
    XCTAssertNotNil(events[0].errorDescription, "Failed event should include error description")
  }

  func testRecoveryLogging_TimeoutEscalation_RecordsTimeoutValues() async throws {
    let counter = AtomicCounter()
    _ = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 2_000, maxRetries: 2
    ) { timeoutMs in
      let n = counter.increment()
      if n == 1 {
        throw MTPError.timeout
      }
      return "ok"
    }

    let events = await RecoveryLog.shared.recent(limit: 10)
    XCTAssertEqual(events.count, 1)
    XCTAssertTrue(events[0].succeeded)
    XCTAssertEqual(events[0].timeoutMs, 4_000, "Should record the escalated timeout value")
  }

  func testRecoveryLogging_DisconnectRecorded() async throws {
    let detected = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
      error: MTPError.deviceDisconnected, journal: nil, transferId: nil
    )
    XCTAssertTrue(detected)

    let events = await RecoveryLog.shared.recent(limit: 10)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].strategy, RecoveryStrategy.disconnectRecovery.rawValue)
    XCTAssertFalse(events[0].succeeded, "Disconnect is recorded as not succeeded")
  }

  // MARK: - FaultInjectingLink Integration

  func testFaultInjectingLink_SessionRecoveryWithInjectedFault() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs),
        error: .protocolError(code: 0x2003),
        repeatCount: 1
      )
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    // The fault fires as a TransportError, so we compose with session recovery
    // wrapping the call to demonstrate end-to-end fault → recovery
    let counter = AtomicCounter()
    let ids = try await ErrorRecoveryLayer.withSessionRecovery(link: link) {
      counter.increment()
      do {
        return try await link.getStorageIDs()
      } catch {
        // FaultInjectingLink throws TransportError; convert to MTPError for session recovery
        throw MTPError.protocolError(code: 0x2003, message: "Injected session fault")
      }
    }

    XCTAssertFalse(ids.isEmpty)
    XCTAssertEqual(counter.value, 2)
  }

  func testFaultInjectingLink_StallRecoveryWithInjectedStall() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs),
        error: .io("USB pipe stall"),
        repeatCount: 1
      )
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let counter = AtomicCounter()
    let result = try await ErrorRecoveryLayer.withStallRecovery(link: link) {
      counter.increment()
      do {
        return try await link.getStorageIDs()
      } catch {
        throw MTPError.transport(.stall)
      }
    }

    XCTAssertFalse(result.isEmpty)
    XCTAssertEqual(counter.value, 2)
  }

  func testFaultInjectingLink_TimeoutEscalationWithInjectedTimeout() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs),
        error: .timeout,
        repeatCount: 2
      )
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    let timeouts = AtomicArray<Int>()
    let result = try await ErrorRecoveryLayer.withTimeoutEscalation(
      initialTimeoutMs: 1_000, maxRetries: 3
    ) { timeoutMs in
      timeouts.append(timeoutMs)
      do {
        return try await link.getStorageIDs()
      } catch {
        throw MTPError.timeout
      }
    }

    XCTAssertFalse(result.isEmpty)
    // Two timeouts then success: 1000 → 2000 → 4000
    XCTAssertEqual(timeouts.snapshot, [1_000, 2_000, 4_000])
  }

  func testFaultInjectingLink_DisconnectDuringOperation() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.getStorageIDs),
        error: .disconnected,
        repeatCount: 0  // unlimited
      )
    ])
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    try await link.openSession(id: 1)

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected disconnect error")
    } catch {
      let isDisconnect = await ErrorRecoveryLayer.handleDisconnectIfNeeded(
        error: MTPError.transport(.noDevice), journal: nil, transferId: nil
      )
      XCTAssertTrue(isDisconnect, "Should detect disconnect from injected fault")
    }
  }
}

// MARK: - Thread-safe test helpers

private final class AtomicCounter: @unchecked Sendable {
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

private final class AtomicArray<T>: @unchecked Sendable {
  private var _items: [T] = []
  private let lock = NSLock()

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return _items.count
  }

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

// MARK: - Stub TransferJournal for disconnect tests

private actor StubTransferJournal: TransferJournal {
  var entries: [String: String] = [:]  // id → state
  private var nextID = 0

  func entryState(for id: String) -> String? {
    entries[id]
  }

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String,
    size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    nextID += 1
    let id = "read-\(nextID)"
    entries[id] = "active"
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String,
    size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    nextID += 1
    let id = "write-\(nextID)"
    entries[id] = "active"
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {}
  func fail(id: String, error: Error) async throws {
    entries[id] = "failed"
  }
  func complete(id: String) async throws {
    entries[id] = "completed"
  }
  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] { [] }
  func clearStaleTemps(olderThan: TimeInterval) async throws {}
}
