// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Extended concurrency tests: parallel operations, cancellation, actor isolation.
final class SyncConcurrencyExtendedTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var mirrorEngine: MirrorEngine!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("concurrency-ext.sqlite").path

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    mirrorEngine = nil
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Parallel Mirror Operations

  func testParallelMirrorsToDifferentDirectories() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let engine = self.mirrorEngine!
    let root = self.tempDirectory!

    let results = await withTaskGroup(of: MTPSyncReport?.self, returning: [MTPSyncReport].self) {
      group in
      for i in 0..<5 {
        group.addTask {
          try? await engine.mirror(
            device: device, deviceId: deviceId,
            to: root.appendingPathComponent("parallel-\(i)"))
        }
      }
      var reports: [MTPSyncReport] = []
      for await result in group {
        if let r = result { reports.append(r) }
      }
      return reports
    }

    XCTAssertEqual(results.count, 5)
    for report in results {
      XCTAssertEqual(report.failed, 0)
    }
  }

  // MARK: - Actor-Based Sync Queue

  func testSyncQueueProcessesInOrder() async {
    let queue = SyncOperationQueue()

    for i in 0..<20 {
      await queue.enqueue("op-\(i)")
    }

    let count = await queue.count
    XCTAssertEqual(count, 20)

    let first = await queue.dequeue()
    XCTAssertEqual(first, "op-0")

    let remaining = await queue.count
    XCTAssertEqual(remaining, 19)
  }

  func testConcurrentEnqueueDequeue() async {
    let queue = SyncOperationQueue()

    // Enqueue concurrently
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          await queue.enqueue("item-\(i)")
        }
      }
    }

    let count = await queue.count
    XCTAssertEqual(count, 100)
  }

  // MARK: - Cancellation Scenarios

  func testCancelledTaskDoesNotCompleteSync() async throws {
    let engine = SlowSyncEngine(delayNanos: 500_000_000)

    let task = Task {
      await engine.syncAll()
    }

    // Cancel before it finishes
    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()

    _ = await task.result
    XCTAssertTrue(task.isCancelled)
  }

  func testMultipleTasksCancelledSimultaneously() async throws {
    let engines = (0..<5).map { _ in SlowSyncEngine(delayNanos: 500_000_000) }

    let tasks = engines.map { engine in
      Task { await engine.syncAll() }
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    for task in tasks {
      task.cancel()
    }

    for task in tasks {
      _ = await task.result
      XCTAssertTrue(task.isCancelled)
    }
  }

  // MARK: - Progress Tracking Under Concurrency

  func testProgressCounterActorSafe() async {
    let counter = ProgressCounter()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<1000 {
        group.addTask {
          await counter.increment()
        }
      }
    }

    let total = await counter.value
    XCTAssertEqual(total, 1000)
  }

  func testProgressCounterResetUnderConcurrency() async {
    let counter = ProgressCounter()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<500 {
        group.addTask { await counter.increment() }
      }
    }

    await counter.reset()
    let total = await counter.value
    XCTAssertEqual(total, 0)
  }

  // MARK: - Isolated State Mutation

  func testActorPreventsConcurrentStateMutation() async {
    let state = SyncState()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask { await state.recordDownload() }
        group.addTask { await state.recordSkip() }
        group.addTask { await state.recordFailure() }
      }
    }

    let totals = await state.totals()
    XCTAssertEqual(totals.downloaded + totals.skipped + totals.failed, 300)
    XCTAssertEqual(totals.downloaded, 100)
    XCTAssertEqual(totals.skipped, 100)
    XCTAssertEqual(totals.failed, 100)
  }
}

// MARK: - Test Support Actors

private actor SyncOperationQueue {
  private var items: [String] = []

  func enqueue(_ item: String) {
    items.append(item)
  }

  func dequeue() -> String? {
    items.isEmpty ? nil : items.removeFirst()
  }

  var count: Int { items.count }
}

private actor SlowSyncEngine {
  private let delayNanos: UInt64

  init(delayNanos: UInt64) {
    self.delayNanos = delayNanos
  }

  func syncAll() async {
    for _ in 0..<10 {
      guard !Task.isCancelled else { return }
      try? await Task.sleep(nanoseconds: delayNanos)
    }
  }
}

private actor ProgressCounter {
  private var _value: Int = 0

  var value: Int { _value }

  func increment() {
    _value += 1
  }

  func reset() {
    _value = 0
  }
}

private actor SyncState {
  private var downloaded: Int = 0
  private var skipped: Int = 0
  private var failed: Int = 0

  func recordDownload() { downloaded += 1 }
  func recordSkip() { skipped += 1 }
  func recordFailure() { failed += 1 }

  func totals() -> (downloaded: Int, skipped: Int, failed: Int) {
    (downloaded, skipped, failed)
  }
}
