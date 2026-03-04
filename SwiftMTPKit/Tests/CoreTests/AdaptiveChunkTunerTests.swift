// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore

final class AdaptiveChunkTunerTests: XCTestCase {

  // MARK: - Initialisation

  func testDefaultInitStartsAt512KB() async {
    let tuner = AdaptiveChunkTuner()
    let size = await tuner.currentChunkSize
    XCTAssertEqual(size, 512 * 1024)
  }

  func testInitWithLearnedChunkSize() async {
    let tuner = AdaptiveChunkTuner(initialChunkSize: 2 * 1024 * 1024)
    let size = await tuner.currentChunkSize
    XCTAssertEqual(size, 2 * 1024 * 1024)
  }

  func testInitClampsToMin() async {
    let tuner = AdaptiveChunkTuner(initialChunkSize: 1024)
    let size = await tuner.currentChunkSize
    XCTAssertEqual(size, AdaptiveChunkTuner.minChunkSize)
  }

  func testInitClampsToMax() async {
    let tuner = AdaptiveChunkTuner(initialChunkSize: 100 * 1024 * 1024)
    let size = await tuner.currentChunkSize
    XCTAssertEqual(size, AdaptiveChunkTuner.maxChunkSize)
  }

  // MARK: - Promotion

  func testPromotesTo1MBAbove10MBps() async {
    let tuner = AdaptiveChunkTuner()
    // Simulate sustained 15 MB/s throughput (1 MB in ~0.0667s).
    let bytes = 1_000_000
    let duration = Double(bytes) / 15_000_000  // 15 MB/s
    let newChunk = await tuner.recordChunk(bytes: bytes, duration: duration)
    XCTAssertEqual(newChunk, 1024 * 1024, "Should promote to 1 MB tier")
  }

  func testPromotesTo2MBAbove20MBps() async {
    let tuner = AdaptiveChunkTuner()
    let bytes = 1_000_000
    let duration = Double(bytes) / 25_000_000  // 25 MB/s
    let newChunk = await tuner.recordChunk(bytes: bytes, duration: duration)
    XCTAssertEqual(newChunk, 2 * 1024 * 1024, "Should promote to 2 MB tier")
  }

  func testPromotesTo4MBAbove40MBps() async {
    let tuner = AdaptiveChunkTuner()
    let bytes = 1_000_000
    let duration = Double(bytes) / 50_000_000  // 50 MB/s
    let newChunk = await tuner.recordChunk(bytes: bytes, duration: duration)
    XCTAssertEqual(newChunk, 4 * 1024 * 1024, "Should promote to 4 MB tier")
  }

  func testNoPromotionBelowThreshold() async {
    let tuner = AdaptiveChunkTuner()
    let bytes = 1_000_000
    let duration = Double(bytes) / 5_000_000  // 5 MB/s
    let newChunk = await tuner.recordChunk(bytes: bytes, duration: duration)
    XCTAssertEqual(newChunk, 512 * 1024, "Should stay at 512 KB tier")
  }

  // MARK: - Demotion

  func testDemotesOnThroughputDrop() async {
    let tuner = AdaptiveChunkTuner()
    // First promote to 4 MB tier with high throughput.
    let fastBytes = 4_000_000
    let fastDuration = Double(fastBytes) / 50_000_000
    _ = await tuner.recordChunk(bytes: fastBytes, duration: fastDuration)

    // Feed slow samples to bring average below 10 MB/s threshold.
    // Need >3 samples before demotion kicks in.
    let slowBytes = 500_000
    let slowDuration = Double(slowBytes) / 2_000_000  // 2 MB/s
    for _ in 0..<5 {
      _ = await tuner.recordChunk(bytes: slowBytes, duration: slowDuration)
    }

    let size = await tuner.currentChunkSize
    XCTAssertLessThan(size, 4 * 1024 * 1024, "Should have demoted from 4 MB")
  }

  // MARK: - Error backoff

  func testErrorBackoff() async {
    let tuner = AdaptiveChunkTuner()
    // Promote first.
    let bytes = 1_000_000
    let duration = Double(bytes) / 50_000_000
    _ = await tuner.recordChunk(bytes: bytes, duration: duration)
    let sizeBeforeError = await tuner.currentChunkSize
    XCTAssertGreaterThan(sizeBeforeError, 512 * 1024)

    let sizeAfterError = await tuner.recordError()
    XCTAssertLessThan(sizeAfterError, sizeBeforeError, "Should back off after error")
  }

  func testErrorAtLowestTierStaysAtMin() async {
    let tuner = AdaptiveChunkTuner()
    let size = await tuner.recordError()
    XCTAssertEqual(size, 512 * 1024, "At lowest tier, error should not go below min")
  }

  // MARK: - Snapshot

  func testSnapshotCapturesState() async {
    let tuner = AdaptiveChunkTuner()
    _ = await tuner.recordChunk(bytes: 1_000_000, duration: 0.05)
    let snap = await tuner.snapshot
    XCTAssertEqual(snap.sampleCount, 1)
    XCTAssertGreaterThan(snap.averageThroughput, 0)
    XCTAssertGreaterThan(snap.maxObservedThroughput, 0)
    XCTAssertEqual(snap.errorCount, 0)
  }

  // MARK: - Reset

  func testReset() async {
    let tuner = AdaptiveChunkTuner()
    _ = await tuner.recordChunk(bytes: 1_000_000, duration: 0.01)
    await tuner.reset()
    let snap = await tuner.snapshot
    XCTAssertEqual(snap.sampleCount, 0)
    XCTAssertEqual(snap.currentChunkSize, 512 * 1024)
  }

  // MARK: - Zero duration safety

  func testZeroDurationIsIgnored() async {
    let tuner = AdaptiveChunkTuner()
    let size = await tuner.recordChunk(bytes: 1_000_000, duration: 0)
    XCTAssertEqual(size, 512 * 1024, "Zero duration should be no-op")
    let snap = await tuner.snapshot
    XCTAssertEqual(snap.sampleCount, 0)
  }

  // MARK: - Adjustments log

  func testAdjustmentsLogRecordsChanges() async {
    let tuner = AdaptiveChunkTuner()
    // Trigger a promotion.
    _ = await tuner.recordChunk(bytes: 1_000_000, duration: Double(1_000_000) / 15_000_000)
    let log = await tuner.adjustments
    XCTAssertGreaterThanOrEqual(log.count, 2)  // initial + promoted
    XCTAssertEqual(log.first?.reason, .initial)
    XCTAssertTrue(log.contains { $0.reason == .promoted })
  }
}

// MARK: - DeviceTuningStore Tests

final class DeviceTuningStoreTests: XCTestCase {

  private func tempStoreURL() -> URL {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp.appendingPathComponent("device-tuning.json")
  }

  func testSaveAndLoad() {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = DeviceTuningStore(fileURL: url)
    let record = DeviceTuningRecord(
      vid: "2717", pid: "ff10",
      optimalChunkSize: 2 * 1024 * 1024,
      maxObservedThroughput: 25_000_000,
      errorCount: 0,
      lastTunedDate: "2025-01-15T00:00:00Z"
    )
    store.save(record)

    let loaded = store.load(vid: "2717", pid: "ff10")
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.optimalChunkSize, 2 * 1024 * 1024)
    XCTAssertEqual(loaded?.vid, "2717")
    XCTAssertEqual(loaded?.pid, "ff10")
  }

  func testLoadMissingReturnsNil() {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = DeviceTuningStore(fileURL: url)
    XCTAssertNil(store.load(vid: "ffff", pid: "ffff"))
  }

  func testUpdateFromSnapshot() async {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = DeviceTuningStore(fileURL: url)
    let tuner = AdaptiveChunkTuner()
    _ = await tuner.recordChunk(bytes: 2_000_000, duration: Double(2_000_000) / 30_000_000)
    let snap = await tuner.snapshot
    store.update(vid: "04e8", pid: "6860", from: snap)

    let loaded = store.load(vid: "04e8", pid: "6860")
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.optimalChunkSize, snap.currentChunkSize)
    XCTAssertGreaterThan(loaded?.maxObservedThroughput ?? 0, 0)
  }

  func testMultipleDevices() {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = DeviceTuningStore(fileURL: url)
    store.save(DeviceTuningRecord(
      vid: "aaaa", pid: "1111", optimalChunkSize: 512 * 1024,
      maxObservedThroughput: 5_000_000, errorCount: 0, lastTunedDate: "2025-01-01T00:00:00Z"))
    store.save(DeviceTuningRecord(
      vid: "bbbb", pid: "2222", optimalChunkSize: 4 * 1024 * 1024,
      maxObservedThroughput: 50_000_000, errorCount: 1, lastTunedDate: "2025-01-02T00:00:00Z"))

    let all = store.loadAll()
    XCTAssertEqual(all.count, 2)
    XCTAssertNotNil(all["aaaa:1111"])
    XCTAssertNotNil(all["bbbb:2222"])
  }
}
