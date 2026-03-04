// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

// MARK: - Helpers

/// A transport whose link introduces configurable delays per operation.
private final class DelayingTransport: @unchecked Sendable, MTPTransport {
  private let inner: MockDeviceData
  let delayNs: UInt64

  init(deviceData: MockDeviceData, delayNs: UInt64 = 50_000_000) {
    self.inner = deviceData
    self.delayNs = delayNs
  }

  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    DelayingMTPLink(deviceData: inner, delayNs: delayNs)
  }
  func close() async throws {}
}

/// A link where every session/info operation sleeps for a configurable duration.
private final class DelayingMTPLink: @unchecked Sendable, MTPLink {
  private let deviceData: MockDeviceData
  private let delayNs: UInt64
  private var sessionID: UInt32?
  let eventStream: AsyncStream<Data> = AsyncStream { $0.finish() }

  init(deviceData: MockDeviceData, delayNs: UInt64) {
    self.deviceData = deviceData
    self.delayNs = delayNs
  }

  func openUSBIfNeeded() async throws {}
  func openSession(id: UInt32) async throws {
    try await Task.sleep(nanoseconds: delayNs)
    sessionID = id
  }
  func closeSession() async throws { sessionID = nil }
  func close() async {}
  func resetDevice() async throws {}
  func startEventPump() {}

  func getDeviceInfo() async throws -> MTPDeviceInfo {
    try await Task.sleep(nanoseconds: delayNs)
    return MTPDeviceInfo(
      manufacturer: "Test", model: "Delaying", version: "1.0",
      serialNumber: "DELAY1", operationsSupported: Set(), eventsSupported: Set())
  }

  func getStorageIDs() async throws -> [MTPStorageID] {
    try await Task.sleep(nanoseconds: delayNs)
    return deviceData.storages.map(\.id)
  }
  func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    try await Task.sleep(nanoseconds: delayNs)
    guard let s = deviceData.storages.first(where: { $0.id == id }) else {
      throw MTPError.objectNotFound
    }
    return s
  }
  func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    try await Task.sleep(nanoseconds: delayNs)
    return []
  }
  func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    try await Task.sleep(nanoseconds: delayNs)
    return []
  }
  func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    try await Task.sleep(nanoseconds: delayNs)
    return []
  }
  func deleteObject(handle: MTPObjectHandle) async throws {
    try await Task.sleep(nanoseconds: delayNs)
  }
  func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    try await Task.sleep(nanoseconds: delayNs)
  }
  func copyObject(handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> MTPObjectHandle { 0 }
  func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    PTPResponseResult(code: 0x2001, txid: command.txid)
  }
  func executeStreamingCommand(
    _ command: PTPContainer, dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    PTPResponseResult(code: 0x2001, txid: command.txid)
  }
}

/// A transport whose link throws a configurable error on any operation after opening.
private final class FailAfterOpenTransport: @unchecked Sendable, MTPTransport {
  private let inner: MockDeviceData
  let errorToThrow: Error

  init(deviceData: MockDeviceData, error: Error) {
    self.inner = deviceData
    self.errorToThrow = error
  }

  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    FailAfterOpenLink(deviceData: inner, error: errorToThrow)
  }
  func close() async throws {}
}

private final class FailAfterOpenLink: @unchecked Sendable, MTPLink {
  private let deviceData: MockDeviceData
  private let errorToThrow: Error
  let eventStream: AsyncStream<Data> = AsyncStream { $0.finish() }

  init(deviceData: MockDeviceData, error: Error) {
    self.deviceData = deviceData
    self.errorToThrow = error
  }

  func openUSBIfNeeded() async throws {}
  func openSession(id: UInt32) async throws {}
  func closeSession() async throws {}
  func close() async {}
  func resetDevice() async throws {}
  func startEventPump() {}

  func getDeviceInfo() async throws -> MTPDeviceInfo {
    return MTPDeviceInfo(
      manufacturer: "Test", model: "FailAfterOpen", version: "1.0",
      serialNumber: "FAIL1", operationsSupported: Set(), eventsSupported: Set())
  }
  func getStorageIDs() async throws -> [MTPStorageID] { throw errorToThrow }
  func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo { throw errorToThrow }
  func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  { throw errorToThrow }
  func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    throw errorToThrow
  }
  func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  { throw errorToThrow }
  func deleteObject(handle: MTPObjectHandle) async throws { throw errorToThrow }
  func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  { throw errorToThrow }
  func copyObject(handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> MTPObjectHandle { throw errorToThrow }
  func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    PTPResponseResult(code: 0x2001, txid: command.txid)
  }
  func executeStreamingCommand(
    _ command: PTPContainer, dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    PTPResponseResult(code: 0x2001, txid: command.txid)
  }
}

/// Actor that tracks concurrent entry into a guarded region.
private actor ConcurrencyMonitor {
  private var concurrentCount = 0
  private var maxConcurrent = 0
  private(set) var detectedConcurrency = false

  func enter() {
    concurrentCount += 1
    if concurrentCount > maxConcurrent { maxConcurrent = concurrentCount }
    if concurrentCount > 1 { detectedConcurrency = true }
  }

  func exit() { concurrentCount -= 1 }
  func peakConcurrency() -> Int { maxConcurrent }
}

/// Actor that records the order of operations.
private actor OrderRecorder {
  private(set) var order: [Int] = []
  func record(_ n: Int) { order.append(n) }
}

/// Thread-safe counter using an actor.
private actor AtomicCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

// MARK: - Shared mock device helper

private func makeMockData() -> MockDeviceData {
  MockTransportFactory.deviceData(for: .androidPixel7)
}

private func makeActor(transport: MTPTransport? = nil) -> MTPDeviceActor {
  let data = makeMockData()
  let t = transport ?? MockTransport(deviceData: data)
  return MTPDeviceActor(id: data.deviceSummary.id, summary: data.deviceSummary, transport: t)
}

private func makeDelayingActor(delayNs: UInt64 = 50_000_000) -> MTPDeviceActor {
  let data = makeMockData()
  let t = DelayingTransport(deviceData: data, delayNs: delayNs)
  return MTPDeviceActor(id: data.deviceSummary.id, summary: data.deviceSummary, transport: t)
}

// MARK: - DeviceActorIsolationTests

final class DeviceActorIsolationTests: XCTestCase {

  // MARK: - Basic Actor Isolation

  func testActorIsolationSerializesSequentialOperations() async throws {
    let device = makeActor()
    // Sequential withTransaction calls should complete in order
    let r1 = try await device.withTransaction { 1 }
    let r2 = try await device.withTransaction { 2 }
    let r3 = try await device.withTransaction { 3 }
    XCTAssertEqual(r1, 1)
    XCTAssertEqual(r2, 2)
    XCTAssertEqual(r3, 3)
  }

  func testActorIsolationReturnsDifferentTypes() async throws {
    let device = makeActor()
    let intResult = try await device.withTransaction { 42 }
    let stringResult = try await device.withTransaction { "hello" }
    let boolResult = try await device.withTransaction { true }
    XCTAssertEqual(intResult, 42)
    XCTAssertEqual(stringResult, "hello")
    XCTAssertTrue(boolResult)
  }

  // MARK: - Concurrent Requests from Multiple Tasks

  func testConcurrentRequestsSerializeCorrectly() async throws {
    let device = makeDelayingActor(delayNs: 10_000_000)
    let monitor = ConcurrencyMonitor()

    let tasks = (0..<10)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await monitor.enter()
            try await Task.sleep(nanoseconds: 5_000_000)
            await monitor.exit()
          }
        }
      }

    for t in tasks { try await t.value }
    let wasConcurrent = await monitor.detectedConcurrency
    XCTAssertFalse(wasConcurrent, "Transaction bodies must never execute concurrently")
  }

  func testConcurrentRequestsAllComplete() async throws {
    let device = makeActor()
    let counter = AtomicCounter()
    let taskCount = 20

    let tasks = (0..<taskCount)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await counter.increment()
          }
        }
      }

    for t in tasks { try await t.value }
    let count = await counter.value
    XCTAssertEqual(count, taskCount, "All concurrent tasks must complete")
  }

  func testConcurrentRequestsPreserveOrder() async throws {
    let device = makeDelayingActor(delayNs: 5_000_000)
    let recorder = OrderRecorder()

    // Launch tasks with staggered delays so they queue in order
    let t1 = Task<Void, Error> {
      try await device.withTransaction {
        try await Task.sleep(nanoseconds: 20_000_000)
        await recorder.record(1)
      }
    }

    // Give t1 time to acquire the lock
    try await Task.sleep(nanoseconds: 10_000_000)

    let t2 = Task<Void, Error> {
      try await device.withTransaction {
        await recorder.record(2)
      }
    }

    try await Task.sleep(nanoseconds: 5_000_000)

    let t3 = Task<Void, Error> {
      try await device.withTransaction {
        await recorder.record(3)
      }
    }

    try await t1.value
    try await t2.value
    try await t3.value

    let observed = await recorder.order
    XCTAssertEqual(observed, [1, 2, 3], "Transactions must complete in queued order")
  }

  // MARK: - Task Cancellation During Actor Operations

  func testCancellationDuringTransactionBody() async throws {
    let device = makeDelayingActor(delayNs: 10_000_000)

    let task = Task<Void, Error> {
      try await device.withTransaction {
        // This should throw CancellationError when the task is cancelled
        try await Task.sleep(nanoseconds: 5_000_000_000)
      }
    }

    // Cancel after a brief period
    try await Task.sleep(nanoseconds: 30_000_000)
    task.cancel()

    // The cancelled task should throw CancellationError
    do {
      try await task.value
      // If it doesn't throw, that's also acceptable (race condition)
    } catch is CancellationError {
      // Expected
    }

    // Critically, the actor must still be usable after cancellation
    let ok = try await device.withTransaction { true }
    XCTAssertTrue(ok, "Actor must remain usable after a task cancellation")
  }

  func testCancellationDoesNotBlockSubsequentCallers() async throws {
    let device = makeDelayingActor(delayNs: 10_000_000)

    // Start a long-running transaction
    let longTask = Task<Void, Error> {
      try await device.withTransaction {
        try await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }

    // Let it acquire the lock
    try await Task.sleep(nanoseconds: 30_000_000)

    // Cancel it
    longTask.cancel()

    // Wait for the cancelled task to settle
    _ = try? await longTask.value

    // Subsequent callers must still succeed
    let result = try await device.withTransaction { 99 }
    XCTAssertEqual(result, 99)
  }

  // MARK: - Actor State Consistency After Errors

  func testStateConsistencyAfterThrow() async throws {
    let device = makeActor()

    // First transaction throws
    do {
      try await device.withTransaction {
        throw MTPError.timeout
      }
    } catch {
      XCTAssertEqual(error as? MTPError, .timeout)
    }

    // Actor should still work after error
    let result = try await device.withTransaction { "recovered" }
    XCTAssertEqual(result, "recovered")
  }

  func testStateConsistencyAfterMultipleErrors() async throws {
    let device = makeActor()
    let errors: [MTPError] = [.timeout, .busy, .sessionBusy, .objectNotFound, .deviceDisconnected]

    for error in errors {
      do {
        try await device.withTransaction { throw error }
      } catch {
        // Expected
      }
    }

    // Actor should still be fully operational
    let ok = try await device.withTransaction { true }
    XCTAssertTrue(ok, "Actor must remain usable after multiple different errors")
  }

  func testTransactionReleasesLockOnEveryErrorType() async throws {
    let device = makeActor()

    // Throw various error types
    try? await device.withTransaction { throw MTPError.timeout }
    try? await device.withTransaction { throw MTPError.busy }
    try? await device.withTransaction { throw MTPError.transport(.io("test")) }
    try? await device.withTransaction {
      throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
    }
    try? await device.withTransaction { throw CancellationError() }

    // Lock should not be stuck — this must complete without hanging
    let result = try await device.withTransaction { "still alive" }
    XCTAssertEqual(result, "still alive")
  }

  // MARK: - High Contention Scenarios

  func testHighContentionManySimultaneousOperations() async throws {
    let device = makeActor()
    let counter = AtomicCounter()
    let taskCount = 50

    let tasks = (0..<taskCount)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await counter.increment()
          }
        }
      }

    for t in tasks { try await t.value }
    let count = await counter.value
    XCTAssertEqual(count, taskCount, "All \(taskCount) contending tasks must complete")
  }

  func testHighContentionNoDataRace() async throws {
    let device = makeActor()
    let monitor = ConcurrencyMonitor()
    let taskCount = 30

    let tasks = (0..<taskCount)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await monitor.enter()
            // Simulate non-trivial work
            try await Task.sleep(nanoseconds: 1_000_000)
            await monitor.exit()
          }
        }
      }

    for t in tasks { try await t.value }
    let peak = await monitor.peakConcurrency()
    XCTAssertEqual(peak, 1, "Peak concurrency inside transactions must be exactly 1")
  }

  // MARK: - Actor Behavior During Device Disconnect

  func testActorRemainsUsableAfterDisconnectError() async throws {
    let data = makeMockData()
    let transport = FailAfterOpenTransport(deviceData: data, error: MTPError.deviceDisconnected)
    let device = MTPDeviceActor(
      id: data.deviceSummary.id, summary: data.deviceSummary, transport: transport)

    // The transaction itself won't fail since it's user code, but the actor
    // must survive disconnect-like errors thrown from within
    do {
      try await device.withTransaction {
        throw MTPError.deviceDisconnected
      }
    } catch {
      XCTAssertEqual(error as? MTPError, .deviceDisconnected)
    }

    // Actor should accept new transactions
    let result = try await device.withTransaction { "reconnected" }
    XCTAssertEqual(result, "reconnected")
  }

  func testConcurrentTasksSurviveInterleavedDisconnects() async throws {
    let device = makeActor()
    let counter = AtomicCounter()

    let tasks = (0..<10)
      .map { i in
        Task<Void, Error> {
          do {
            try await device.withTransaction {
              if i % 3 == 0 {
                throw MTPError.deviceDisconnected
              }
              await counter.increment()
            }
          } catch {
            // Expected for every 3rd task
          }
        }
      }

    for t in tasks { try await t.value }

    // 6 tasks should succeed (indices 1,2,4,5,7,8 — skipping 0,3,6,9)
    let count = await counter.value
    XCTAssertEqual(count, 6, "Non-failing tasks must all complete despite interleaved errors")
  }

  // MARK: - Operation Timeout Handling Within Actor

  func testTransactionWithInternalTimeout() async throws {
    let device = makeActor()

    let start = ContinuousClock.now
    do {
      try await device.withTransaction {
        // Simulate operation that checks for timeout
        try await Task.sleep(nanoseconds: 20_000_000)
        throw MTPError.timeout
      }
    } catch {
      XCTAssertEqual(error as? MTPError, .timeout)
    }
    let elapsed = ContinuousClock.now - start

    // Should have taken roughly 20ms, not hung
    XCTAssertLessThan(elapsed, .milliseconds(2000), "Timeout should resolve quickly")
  }

  func testSubsequentOperationAfterTimeoutSucceeds() async throws {
    let device = makeActor()

    try? await device.withTransaction { throw MTPError.timeout }
    try? await device.withTransaction { throw MTPError.timeout }

    // Third attempt should work
    let ok = try await device.withTransaction { true }
    XCTAssertTrue(ok)
  }

  // MARK: - Structured Concurrency with Actor (Task Groups)

  func testTaskGroupWithActorTransactions() async throws {
    let device = makeActor()
    let counter = AtomicCounter()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<15 {
        group.addTask {
          try await device.withTransaction {
            await counter.increment()
          }
        }
      }
      try await group.waitForAll()
    }

    let count = await counter.value
    XCTAssertEqual(count, 15)
  }

  func testTaskGroupWithMixedSuccessAndFailure() async throws {
    let device = makeActor()
    let successCounter = AtomicCounter()

    await withTaskGroup(of: Void.self) { group in
      for i in 0..<12 {
        group.addTask {
          do {
            try await device.withTransaction {
              if i % 4 == 0 { throw MTPError.busy }
              await successCounter.increment()
            }
          } catch {
            // Expected for every 4th task
          }
        }
      }
      await group.waitForAll()
    }

    let successes = await successCounter.value
    XCTAssertEqual(successes, 9, "9 out of 12 tasks should succeed (indices 0,4,8 fail)")
  }

  func testNestedTaskGroupsWithActor() async throws {
    let device = makeActor()
    let counter = AtomicCounter()

    try await withThrowingTaskGroup(of: Void.self) { outer in
      for _ in 0..<3 {
        outer.addTask {
          try await withThrowingTaskGroup(of: Void.self) { inner in
            for _ in 0..<4 {
              inner.addTask {
                try await device.withTransaction {
                  await counter.increment()
                }
              }
            }
            try await inner.waitForAll()
          }
        }
      }
      try await outer.waitForAll()
    }

    let count = await counter.value
    XCTAssertEqual(count, 12, "All 3×4=12 nested tasks must complete")
  }

  // MARK: - Actor Behavior with Sendable Constraints

  func testSendableResultsFromTransactions() async throws {
    let device = makeActor()

    // String is Sendable
    let s: String = try await device.withTransaction { "sendable" }
    XCTAssertEqual(s, "sendable")

    // Int is Sendable
    let n: Int = try await device.withTransaction { 42 }
    XCTAssertEqual(n, 42)

    // Array of Sendable
    let arr: [Int] = try await device.withTransaction { [1, 2, 3] }
    XCTAssertEqual(arr, [1, 2, 3])
  }

  func testSendableDataAcrossTransactionBoundary() async throws {
    let device = makeActor()

    let data = Data([0x01, 0x02, 0x03, 0x04])
    let result: Data = try await device.withTransaction {
      // Data is Sendable and crosses actor boundary safely
      return data
    }
    XCTAssertEqual(result, data)
  }

  func testConcurrentTransactionsWithSendableResults() async throws {
    let device = makeActor()

    let results: [Int] = try await withThrowingTaskGroup(of: Int.self) { group in
      for i in 0..<10 {
        group.addTask {
          try await device.withTransaction { i * i }
        }
      }
      var collected: [Int] = []
      for try await r in group { collected.append(r) }
      return collected.sorted()
    }

    // All squares from 0 to 81
    let expected = (0..<10).map { $0 * $0 }.sorted()
    XCTAssertEqual(results, expected)
  }

  // MARK: - Actor Memory Pressure Under Sustained Load

  func testSustainedLoadDoesNotAccumulateWaiters() async throws {
    let device = makeActor()
    let counter = AtomicCounter()
    let batchSize = 100

    // Run many transactions sequentially — no waiter buildup
    for _ in 0..<batchSize {
      try await device.withTransaction {
        await counter.increment()
      }
    }

    let count = await counter.value
    XCTAssertEqual(count, batchSize)
  }

  func testBurstThenSettlePattern() async throws {
    let device = makeActor()
    let counter = AtomicCounter()

    // Burst: many concurrent tasks
    let tasks = (0..<20)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await counter.increment()
          }
        }
      }
    for t in tasks { try await t.value }

    // Settle: single sequential task should work immediately
    let ok = try await device.withTransaction { true }
    XCTAssertTrue(ok)

    let count = await counter.value
    XCTAssertEqual(count, 20)
  }

  // MARK: - Actor Reentrancy

  func testSequentialTransactionsOnSameActor() async throws {
    // Swift actors are not reentrant for synchronous code,
    // but withTransaction uses a continuation-based lock.
    // Verify sequential calls don't deadlock.
    let device = makeActor()

    for i in 0..<5 {
      let result = try await device.withTransaction { i }
      XCTAssertEqual(result, i)
    }
  }

  // MARK: - Device ID and Summary Isolation

  func testActorPropertiesAccessibleConcurrently() async throws {
    let device = makeActor()

    // Accessing id and summary should be safe from any context
    async let id1 = device.id
    async let id2 = device.id
    async let summary1 = device.summary
    async let summary2 = device.summary

    let (r1, r2) = await (id1, id2)
    let (s1, s2) = await (summary1, summary2)

    XCTAssertEqual(r1, r2, "id should be consistent across concurrent reads")
    XCTAssertEqual(s1.model, s2.model, "summary should be consistent across concurrent reads")
  }

  // MARK: - Mixed Error Patterns Under Contention

  func testAlternatingSuccessAndFailureUnderContention() async throws {
    let device = makeActor()
    let successCounter = AtomicCounter()
    let failureCounter = AtomicCounter()

    let tasks = (0..<20)
      .map { i in
        Task<Void, Error> {
          do {
            try await device.withTransaction {
              if i.isMultiple(of: 2) {
                throw MTPError.busy
              }
              await successCounter.increment()
            }
          } catch {
            await failureCounter.increment()
          }
        }
      }

    for t in tasks { try await t.value }

    let successes = await successCounter.value
    let failures = await failureCounter.value

    XCTAssertEqual(successes, 10)
    XCTAssertEqual(failures, 10)
    XCTAssertEqual(successes + failures, 20)
  }

  func testTransportErrorDoesNotCorruptActorState() async throws {
    let device = makeActor()

    // Simulate transport error inside transaction
    try? await device.withTransaction {
      throw MTPError.transport(.io("USB pipe broken"))
    }

    // Verify actor state is still sound by running a successful transaction
    let result = try await device.withTransaction { "state OK" }
    XCTAssertEqual(result, "state OK")
  }

  func testProtocolErrorDoesNotCorruptActorState() async throws {
    let device = makeActor()

    try? await device.withTransaction {
      throw MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
    }

    let result = try await device.withTransaction { true }
    XCTAssertTrue(result)
  }

  // MARK: - Timing and Fairness

  func testTransactionCompletionOrder() async throws {
    let device = makeDelayingActor(delayNs: 5_000_000)
    let recorder = OrderRecorder()
    let taskCount = 8

    // Launch all tasks as close together as possible
    var tasks: [Task<Void, Error>] = []
    for i in 0..<taskCount {
      let t = Task<Void, Error> {
        try await device.withTransaction {
          await recorder.record(i)
        }
      }
      tasks.append(t)
      // Tiny stagger to establish arrival order
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    for t in tasks { try await t.value }

    let observed = await recorder.order
    XCTAssertEqual(observed.count, taskCount, "All tasks must record their completion")
    // The first task launched should complete first
    XCTAssertEqual(observed.first, 0, "First queued task should complete first")
  }
}
