// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPSync

final class MirrorProgressTests: XCTestCase {

  // MARK: - Snapshot Fraction Tests

  func testEmptySnapshotFractionsAreZero() async {
    let progress = MirrorProgress()
    let snap = await progress.snapshot()
    XCTAssertEqual(snap.fileFraction, 0)
    XCTAssertEqual(snap.byteFraction, 0)
    XCTAssertEqual(snap.totalFiles, 0)
    XCTAssertEqual(snap.totalBytes, 0)
  }

  func testSetTotalInitialisesSnapshot() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 10, bytes: 5000)
    let snap = await progress.snapshot()
    XCTAssertEqual(snap.totalFiles, 10)
    XCTAssertEqual(snap.totalBytes, 5000)
    XCTAssertEqual(snap.filesCompleted, 0)
    XCTAssertEqual(snap.bytesTransferred, 0)
    XCTAssertEqual(snap.fileFraction, 0)
    XCTAssertEqual(snap.byteFraction, 0)
  }

  func testCompleteFileUpdatesCountsAndBytes() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 3, bytes: 3000)

    await progress.beginFile(name: "a.jpg", size: 1000)
    await progress.completeFile(size: 1000)

    let snap = await progress.snapshot()
    XCTAssertEqual(snap.filesCompleted, 1)
    XCTAssertEqual(snap.bytesTransferred, 1000)
    XCTAssertEqual(snap.fileFraction, 1.0 / 3.0, accuracy: 0.001)
    XCTAssertEqual(snap.byteFraction, 1000.0 / 3000.0, accuracy: 0.001)
  }

  func testSkipFileCountsTowardFileFraction() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 4, bytes: 4000)

    await progress.skipFile()
    await progress.skipFile()

    let snap = await progress.snapshot()
    XCTAssertEqual(snap.filesSkipped, 2)
    XCTAssertEqual(snap.filesCompleted, 0)
    // Skipped files count toward file fraction (2/4 = 0.5)
    XCTAssertEqual(snap.fileFraction, 0.5, accuracy: 0.001)
    // But not toward byte fraction
    XCTAssertEqual(snap.bytesTransferred, 0)
  }

  func testFailFileCountsTowardFileFraction() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 2, bytes: 2000)

    await progress.beginFile(name: "bad.jpg", size: 1000)
    await progress.failFile()

    let snap = await progress.snapshot()
    XCTAssertEqual(snap.filesFailed, 1)
    XCTAssertEqual(snap.fileFraction, 0.5, accuracy: 0.001)
    XCTAssertEqual(snap.bytesTransferred, 0)
  }

  func testCurrentFileNameSetDuringTransfer() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 1, bytes: 100)

    await progress.beginFile(name: "photo.jpg", size: 100)
    var snap = await progress.snapshot()
    XCTAssertEqual(snap.currentFileName, "photo.jpg")

    await progress.completeFile(size: 100)
    snap = await progress.snapshot()
    XCTAssertNil(snap.currentFileName)
  }

  // MARK: - ETA Tests

  func testETAIsNilBeforeAnyTransfer() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 5, bytes: 5000)
    let snap = await progress.snapshot()
    // bytesTransferred is 0 so bps is 0 → ETA nil
    XCTAssertNil(snap.estimatedTimeRemaining)
  }

  func testETAIsNilWhenComplete() async {
    let progress = MirrorProgress()
    await progress.setTotal(files: 1, bytes: 100)
    await progress.beginFile(name: "a.txt", size: 100)
    await progress.completeFile(size: 100)
    let snap = await progress.snapshot()
    // All bytes transferred → remaining = 0 → ETA nil
    XCTAssertNil(snap.estimatedTimeRemaining)
  }

  // MARK: - Handler Tests

  func testOnUpdateHandlerReceivesSnapshots() async {
    let progress = MirrorProgress()
    let expectation = XCTestExpectation(description: "handler called")
    expectation.expectedFulfillmentCount = 3  // setTotal, beginFile, completeFile

    await progress.onUpdate { _ in
      expectation.fulfill()
    }

    await progress.setTotal(files: 1, bytes: 100)
    await progress.beginFile(name: "x.txt", size: 100)
    await progress.completeFile(size: 100)

    await fulfillment(of: [expectation], timeout: 2)
  }

  func testFullMirrorProgressSequence() async {
    let progress = MirrorProgress()
    let counter = SnapshotCounter()

    await progress.onUpdate { snap in
      counter.increment()
    }

    await progress.setTotal(files: 3, bytes: 3000)

    // File 1: downloaded
    await progress.beginFile(name: "a.jpg", size: 1000)
    await progress.completeFile(size: 1000)

    // File 2: skipped
    await progress.skipFile()

    // File 3: failed
    await progress.beginFile(name: "c.jpg", size: 1000)
    await progress.failFile()

    let final_ = await progress.snapshot()
    XCTAssertEqual(final_.filesCompleted, 1)
    XCTAssertEqual(final_.filesSkipped, 1)
    XCTAssertEqual(final_.filesFailed, 1)
    XCTAssertEqual(final_.totalFiles, 3)
    XCTAssertEqual(final_.bytesTransferred, 1000)
    XCTAssertEqual(final_.fileFraction, 1.0, accuracy: 0.001)

    // We should have received snapshots for each operation:
    // setTotal(1) + beginFile(1) + completeFile(1) + skipFile(1) + beginFile(1) + failFile(1) = 6
    XCTAssertEqual(counter.value, 6)
  }

  // MARK: - Snapshot Value Types

  func testSnapshotByteFractionEdgeCases() {
    // totalBytes == 0 → fraction is 0
    let snap = MirrorProgress.Snapshot(
      totalFiles: 0, filesCompleted: 0, filesSkipped: 0, filesFailed: 0,
      currentFileName: nil, totalBytes: 0, bytesTransferred: 0,
      bytesPerSecond: 0, estimatedTimeRemaining: nil
    )
    XCTAssertEqual(snap.byteFraction, 0)
    XCTAssertEqual(snap.fileFraction, 0)
  }
}

/// Thread-safe counter for verifying handler invocation counts.
private final class SnapshotCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: Int = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return _value
  }

  func increment() {
    lock.lock()
    defer { lock.unlock() }
    _value += 1
  }
}
