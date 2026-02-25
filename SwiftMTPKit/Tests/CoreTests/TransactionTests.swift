// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

// MARK: - Helpers

private func makeMockDevice() -> MTPDeviceActor {
  let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
  return MTPDeviceActor(
    id: mockData.deviceSummary.id,
    summary: mockData.deviceSummary,
    transport: MockTransport(deviceData: mockData)
  )
}

/// An actor that tracks concurrent entry into a guarded region.
private actor ConcurrencyMonitor {
  private var concurrentCount = 0
  private(set) var detectedConcurrency = false

  func enter() {
    concurrentCount += 1
    if concurrentCount > 1 { detectedConcurrency = true }
  }

  func exit() {
    concurrentCount -= 1
  }
}

/// An actor that records the order in which numbered operations complete.
private actor OrderRecorder {
  private(set) var order: [Int] = []
  func record(_ n: Int) { order.append(n) }
}

// MARK: - Tests

@Suite("MTPDeviceActor Transaction Tests")
struct TransactionTests {

  // MARK: - Basic execution

  @Test("withTransaction executes body and returns result")
  func testWithTransactionExecutesBody() async throws {
    let device = makeMockDevice()
    let result = try await device.withTransaction { 42 }
    #expect(result == 42)
  }

  @Test("withTransaction propagates thrown errors")
  func testWithTransactionPropagatesError() async throws {
    let device = makeMockDevice()
    await #expect(throws: MTPError.sessionBusy) {
      try await device.withTransaction { throw MTPError.sessionBusy }
    }
  }

  @Test("withTransaction releases lock after error so next caller succeeds")
  func testWithTransactionReleasesLockOnError() async throws {
    let device = makeMockDevice()

    // First call throws.
    try? await device.withTransaction { throw MTPError.timeout }

    // Second call should succeed without hanging.
    let ok = try await device.withTransaction { true }
    #expect(ok)
  }

  // MARK: - Serialization

  @Test("withTransaction serializes two concurrent callers")
  func testWithTransactionSerializesExecution() async throws {
    let device = makeMockDevice()
    let recorder = OrderRecorder()

    // Task 1: acquires the transaction, holds for 50 ms, then records "1".
    let t1 = Task<Void, Error> {
      try await device.withTransaction {
        try await Task.sleep(nanoseconds: 50_000_000)
        await recorder.record(1)
      }
    }

    // Let t1 start and acquire the lock before t2 is launched.
    try await Task.sleep(nanoseconds: 5_000_000)

    // Task 2: should queue behind t1 and record "2" only after t1 finishes.
    let t2 = Task<Void, Error> {
      try await device.withTransaction {
        await recorder.record(2)
      }
    }

    try await t1.value
    try await t2.value

    let observed = await recorder.order
    #expect(observed == [1, 2], "t1 must complete before t2 starts its body")
  }

  @Test("withTransaction queues multiple concurrent callers without overlap")
  func testWithTransactionPreventsOverlap() async throws {
    let device = makeMockDevice()
    let monitor = ConcurrencyMonitor()

    let tasks = (0..<5)
      .map { _ in
        Task<Void, Error> {
          try await device.withTransaction {
            await monitor.enter()
            // Brief pause to increase the chance of overlap if serialization were absent.
            try await Task.sleep(nanoseconds: 5_000_000)
            await monitor.exit()
          }
        }
      }

    for t in tasks { try await t.value }

    let wasConcurrent = await monitor.detectedConcurrency
    #expect(!wasConcurrent, "bodies of concurrent withTransaction calls must never overlap")
  }
}
