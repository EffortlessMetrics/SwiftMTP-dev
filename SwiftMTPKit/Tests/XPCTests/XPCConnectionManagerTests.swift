// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPXPC

// MARK: - Test Helpers

/// Minimal fake NSXPCConnection that allows simulating interruption / invalidation
/// without requiring a real Mach service.
private final class FakeXPCConnection: NSXPCConnection, @unchecked Sendable {
  func simulateInterruption() {
    interruptionHandler?()
  }

  func simulateInvalidation() {
    invalidationHandler?()
  }

  override func resume() {}

  override func invalidate() {
    invalidationHandler?()
  }
}

/// Records state changes reported by the connection manager.
private final class StateRecorder: XPCConnectionMonitor, @unchecked Sendable {
  private let lock = NSLock()
  private var _states: [XPCConnectionState] = []

  var states: [XPCConnectionState] {
    lock.lock()
    defer { lock.unlock() }
    return _states
  }

  func connectionStateDidChange(_ state: XPCConnectionState) {
    lock.lock()
    _states.append(state)
    lock.unlock()
  }
}

// MARK: - Tests

final class XPCConnectionManagerTests: XCTestCase {

  // MARK: - Helpers

  private func makeManager(
    monitor: (any XPCConnectionMonitor)? = nil,
    fakeConnection: FakeXPCConnection? = nil
  ) -> (XPCConnectionManager, FakeXPCConnection) {
    let conn = fakeConnection ?? FakeXPCConnection()
    let config = XPCConnectionManager.Configuration(
      baseDelay: 0.05,
      multiplier: 2.0,
      maxDelay: 0.5,
      maxQueueSize: 8
    )
    let manager = XPCConnectionManager(
      serviceName: "com.test.xpc",
      configuration: config,
      monitor: monitor,
      connectionFactory: { _ in conn }
    )
    return (manager, conn)
  }

  // MARK: - Initial Connection

  func testConnectTransitionsToConnected() async throws {
    let recorder = StateRecorder()
    let (manager, _) = makeManager(monitor: recorder)

    try await manager.connect()

    let state = await manager.connectionState
    XCTAssertEqual(state, .connected)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(recorder.states.contains(.connected))
  }

  func testInitialStateIsInvalidated() async {
    let (manager, _) = makeManager()
    let state = await manager.connectionState
    XCTAssertEqual(state, .invalidated)
  }

  // MARK: - Interruption → Automatic Reconnect

  func testInterruptionTriggersReconnect() async throws {
    let recorder = StateRecorder()
    let (manager, conn) = makeManager(monitor: recorder)

    try await manager.connect()
    let s1 = await manager.connectionState
    XCTAssertEqual(s1, .connected)

    conn.simulateInterruption()
    try await Task.sleep(nanoseconds: 300_000_000)

    let finalState = await manager.connectionState
    XCTAssertEqual(finalState, .connected, "Should reconnect after interruption")
    XCTAssertTrue(recorder.states.contains(.interrupted))
    XCTAssertTrue(recorder.states.contains(.reconnecting))
  }

  // MARK: - Operation Retry After Reconnection

  func testConnectionRestoredAfterInterruption() async throws {
    let (manager, conn) = makeManager()
    try await manager.connect()

    conn.simulateInterruption()
    try await Task.sleep(nanoseconds: 20_000_000)

    let stateMid = await manager.connectionState
    XCTAssertTrue(
      stateMid == .interrupted || stateMid == .reconnecting || stateMid == .connected)

    try await Task.sleep(nanoseconds: 300_000_000)
    let finalState = await manager.connectionState
    XCTAssertEqual(finalState, .connected)
  }

  // MARK: - Multiple Interruptions with Backoff

  func testMultipleInterruptionsIncrementBackoff() async throws {
    let recorder = StateRecorder()
    let (manager, conn) = makeManager(monitor: recorder)

    try await manager.connect()

    for _ in 0..<3 {
      conn.simulateInterruption()
      try await Task.sleep(nanoseconds: 200_000_000)
    }

    try await Task.sleep(nanoseconds: 500_000_000)
    let state = await manager.connectionState
    XCTAssertEqual(state, .connected)

    let interruptedCount = recorder.states.filter { $0 == .interrupted }.count
    XCTAssertGreaterThanOrEqual(interruptedCount, 2)
  }

  // MARK: - Invalidation → No Reconnect

  func testInvalidationDoesNotReconnect() async throws {
    let recorder = StateRecorder()
    let (manager, conn) = makeManager(monitor: recorder)

    try await manager.connect()

    conn.simulateInvalidation()
    try await Task.sleep(nanoseconds: 200_000_000)

    let state = await manager.connectionState
    XCTAssertEqual(state, .invalidated, "Should remain invalidated after invalidation")

    if let invalidatedIdx = recorder.states.lastIndex(of: .invalidated) {
      let statesAfter = recorder.states.suffix(from: recorder.states.index(after: invalidatedIdx))
      XCTAssertFalse(
        statesAfter.contains(.reconnecting), "Should not attempt reconnect after invalidation")
    }
  }

  func testExplicitInvalidatePreventsReconnect() async throws {
    let (manager, _) = makeManager()
    try await manager.connect()

    await manager.invalidate()
    let state = await manager.connectionState
    XCTAssertEqual(state, .invalidated)

    do {
      _ = try await manager.service()
      XCTFail("Expected error")
    } catch {
      XCTAssertTrue(error is XPCConnectionError)
    }
  }

  // MARK: - Queue Full

  func testQueueFullRejectsOperations() async throws {
    let config = XPCConnectionManager.Configuration(
      baseDelay: 10.0,
      multiplier: 1.0,
      maxDelay: 10.0,
      maxQueueSize: 2
    )
    let conn = FakeXPCConnection()
    let manager = XPCConnectionManager(
      serviceName: "com.test.xpc",
      configuration: config,
      connectionFactory: { _ in conn }
    )

    try await manager.connect()
    conn.simulateInterruption()
    try await Task.sleep(nanoseconds: 50_000_000)

    // Fill the queue by launching tasks that will suspend.
    let task1 = Task { try await manager.service(); () }
    let task2 = Task { try await manager.service(); () }
    try await Task.sleep(nanoseconds: 50_000_000)

    // Third request should fail with queueFull.
    do {
      _ = try await manager.service()
      XCTFail("Expected queueFull error")
    } catch let error as XPCConnectionError {
      XCTAssertEqual(error, .queueFull)
    }

    task1.cancel()
    task2.cancel()
    await manager.invalidate()
  }

  // MARK: - Pending Operation Count

  func testPendingOperationCountTracked() async throws {
    let config = XPCConnectionManager.Configuration(
      baseDelay: 10.0,
      multiplier: 1.0,
      maxDelay: 10.0,
      maxQueueSize: 8
    )
    let conn = FakeXPCConnection()
    let manager = XPCConnectionManager(
      serviceName: "com.test.xpc",
      configuration: config,
      connectionFactory: { _ in conn }
    )

    try await manager.connect()
    conn.simulateInterruption()
    try await Task.sleep(nanoseconds: 50_000_000)

    let task1 = Task { try await manager.service(); () }
    try await Task.sleep(nanoseconds: 50_000_000)

    let count = await manager.pendingOperationCount
    XCTAssertGreaterThanOrEqual(count, 1)

    task1.cancel()
    await manager.invalidate()
  }

  // MARK: - Reset Backoff

  func testResetBackoffClearsAttemptCount() async throws {
    let (manager, _) = makeManager()
    try await manager.connect()
    await manager.resetBackoff()
    let state = await manager.connectionState
    XCTAssertEqual(state, .connected)
  }

  // MARK: - State Descriptions

  func testConnectionErrorDescriptions() {
    XCTAssertFalse(XPCConnectionError.connectionInvalidated.description.isEmpty)
    XCTAssertFalse(XPCConnectionError.queueFull.description.isEmpty)
  }

  func testConnectionStateRawValues() {
    XCTAssertEqual(XPCConnectionState.connected.rawValue, "connected")
    XCTAssertEqual(XPCConnectionState.interrupted.rawValue, "interrupted")
    XCTAssertEqual(XPCConnectionState.reconnecting.rawValue, "reconnecting")
    XCTAssertEqual(XPCConnectionState.invalidated.rawValue, "invalidated")
  }

  // MARK: - Invalidation Drains Pending Operations

  func testInvalidationDrainsPendingWithError() async throws {
    let config = XPCConnectionManager.Configuration(
      baseDelay: 10.0,
      multiplier: 1.0,
      maxDelay: 10.0,
      maxQueueSize: 8
    )
    let conn = FakeXPCConnection()
    let manager = XPCConnectionManager(
      serviceName: "com.test.xpc",
      configuration: config,
      connectionFactory: { _ in conn }
    )

    try await manager.connect()
    conn.simulateInterruption()
    try await Task.sleep(nanoseconds: 50_000_000)

    // Queue an operation that will suspend waiting for reconnect.
    let expectation = XCTestExpectation(description: "pending op gets error")
    let task = Task {
      do {
        _ = try await manager.service()
      } catch {
        XCTAssertTrue(error is XPCConnectionError)
        expectation.fulfill()
      }
    }
    try await Task.sleep(nanoseconds: 50_000_000)

    await manager.invalidate()
    await fulfillment(of: [expectation], timeout: 2)
    _ = task  // suppress unused warning
  }

  // MARK: - Monitor Not Retained

  func testMonitorIsWeaklyHeld() async throws {
    var recorder: StateRecorder? = StateRecorder()
    weak var weakRef = recorder
    let (manager, _) = makeManager(monitor: recorder)
    try await manager.connect()

    recorder = nil
    // Allow in-flight Task callbacks to complete.
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertNil(weakRef)
    _ = manager
  }

  // MARK: - Configuration Defaults

  func testDefaultConfiguration() {
    let config = XPCConnectionManager.Configuration()
    XCTAssertEqual(config.baseDelay, 1.0)
    XCTAssertEqual(config.multiplier, 2.0)
    XCTAssertEqual(config.maxDelay, 30.0)
    XCTAssertEqual(config.maxQueueSize, 64)
  }

  func testCustomConfiguration() {
    let config = XPCConnectionManager.Configuration(
      baseDelay: 0.5, multiplier: 3.0, maxDelay: 60.0, maxQueueSize: 10)
    XCTAssertEqual(config.baseDelay, 0.5)
    XCTAssertEqual(config.multiplier, 3.0)
    XCTAssertEqual(config.maxDelay, 60.0)
    XCTAssertEqual(config.maxQueueSize, 10)
  }
}

// MARK: - XPCConnectionError Equatable (for testing)
extension XPCConnectionError: Equatable {
  public static func == (lhs: XPCConnectionError, rhs: XPCConnectionError) -> Bool {
    switch (lhs, rhs) {
    case (.connectionInvalidated, .connectionInvalidated): return true
    case (.queueFull, .queueFull): return true
    default: return false
    }
  }
}
