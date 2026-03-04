// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCLI
@testable import SwiftMTPCore

final class ProgressRendererTests: XCTestCase {

  // MARK: - Progress bar

  func testProgressBarAtZeroPercent() {
    let bar = ProgressRenderer.renderProgressBar(
      completed: 0, total: 1000, bytesPerSecond: 0, eta: nil, barWidth: 10)
    XCTAssertTrue(bar.hasPrefix("[░░░░░░░░░░] 0%"))
  }

  func testProgressBarAtFiftyPercent() {
    let bar = ProgressRenderer.renderProgressBar(
      completed: 500, total: 1000, bytesPerSecond: 100_000, eta: 5, barWidth: 10)
    XCTAssertTrue(bar.contains("50%"))
    XCTAssertTrue(bar.contains("█████░░░░░"))
    XCTAssertTrue(bar.contains("ETA"))
  }

  func testProgressBarAtOneHundredPercent() {
    let bar = ProgressRenderer.renderProgressBar(
      completed: 1000, total: 1000, bytesPerSecond: 200_000, eta: 0, barWidth: 10)
    XCTAssertTrue(bar.contains("100%"))
    XCTAssertTrue(bar.contains("██████████"))
    XCTAssertFalse(bar.contains("░"))
  }

  func testProgressBarWithNoTotal() {
    let bar = ProgressRenderer.renderProgressBar(
      completed: 0, total: 0, bytesPerSecond: 0, eta: nil, barWidth: 10)
    XCTAssertTrue(bar.contains("0%"))
  }

  func testProgressBarOmitsETAWhenNil() {
    let bar = ProgressRenderer.renderProgressBar(
      completed: 500, total: 1000, bytesPerSecond: 100, eta: nil, barWidth: 10)
    XCTAssertFalse(bar.contains("ETA"))
  }

  // MARK: - Byte formatting

  func testFormatBytesSmall() {
    XCTAssertEqual(ProgressRenderer.formatBytes(0), "0 B")
    XCTAssertEqual(ProgressRenderer.formatBytes(512), "512 B")
    XCTAssertEqual(ProgressRenderer.formatBytes(999), "999 B")
  }

  func testFormatBytesKB() {
    XCTAssertEqual(ProgressRenderer.formatBytes(1_000), "1.0 KB")
    XCTAssertEqual(ProgressRenderer.formatBytes(456_000), "456.0 KB")
  }

  func testFormatBytesMB() {
    XCTAssertEqual(ProgressRenderer.formatBytes(1_000_000), "1.0 MB")
    XCTAssertEqual(ProgressRenderer.formatBytes(1_200_000), "1.2 MB")
    XCTAssertEqual(ProgressRenderer.formatBytes(999_999_999), "1000.0 MB")
  }

  func testFormatBytesGB() {
    XCTAssertEqual(ProgressRenderer.formatBytes(1_000_000_000), "1.0 GB")
    XCTAssertEqual(ProgressRenderer.formatBytes(2_500_000_000), "2.5 GB")
  }

  // MARK: - Duration formatting

  func testFormatDurationSeconds() {
    XCTAssertEqual(ProgressRenderer.formatDuration(0), "0:00")
    XCTAssertEqual(ProgressRenderer.formatDuration(32), "0:32")
    XCTAssertEqual(ProgressRenderer.formatDuration(59), "0:59")
  }

  func testFormatDurationMinutes() {
    XCTAssertEqual(ProgressRenderer.formatDuration(60), "1:00")
    XCTAssertEqual(ProgressRenderer.formatDuration(125), "2:05")
  }

  func testFormatDurationHours() {
    XCTAssertEqual(ProgressRenderer.formatDuration(3600), "1:00:00")
    XCTAssertEqual(ProgressRenderer.formatDuration(3923), "1:05:23")
  }

  func testFormatDurationRoundsUp() {
    // 31.1 seconds rounds up to 32
    XCTAssertEqual(ProgressRenderer.formatDuration(31.1), "0:32")
  }

  // MARK: - File counter

  func testFileProgress() {
    let line = ProgressRenderer.renderFileProgress(
      current: 3, total: 17, filename: "photo_001.jpg")
    XCTAssertEqual(line, "[3/17] photo_001.jpg")
  }

  func testFileProgressSingleFile() {
    let line = ProgressRenderer.renderFileProgress(
      current: 1, total: 1, filename: "video.mp4")
    XCTAssertEqual(line, "[1/1] video.mp4")
  }

  // MARK: - TransferProgressReporter

  func testReporterCallsHandler() async {
    let reporter = TransferProgressReporter()
    let expectation = XCTestExpectation(description: "handler called")

    await reporter.onUpdate { update in
      XCTAssertEqual(update.filename, "test.jpg")
      XCTAssertEqual(update.bytesTransferred, 500)
      XCTAssertEqual(update.totalBytes, 1000)
      expectation.fulfill()
    }

    await reporter.report(
      TransferProgressReporter.Update(
        filename: "test.jpg",
        bytesTransferred: 500,
        totalBytes: 1000,
        filesCompleted: 0,
        totalFiles: 1,
        bytesPerSecond: 250,
        estimatedTimeRemaining: 2.0
      ))

    await fulfillment(of: [expectation], timeout: 1)
  }

  func testUpdateFractionComplete() {
    let update = TransferProgressReporter.Update(
      filename: "file.bin",
      bytesTransferred: 250,
      totalBytes: 1000,
      filesCompleted: 0,
      totalFiles: 1,
      bytesPerSecond: 100,
      estimatedTimeRemaining: nil
    )
    XCTAssertEqual(update.fractionComplete, 0.25, accuracy: 0.001)
  }

  func testUpdateFractionCompleteZeroTotal() {
    let update = TransferProgressReporter.Update(
      filename: "empty",
      bytesTransferred: 0,
      totalBytes: 0,
      filesCompleted: 0,
      totalFiles: 0,
      bytesPerSecond: 0,
      estimatedTimeRemaining: nil
    )
    XCTAssertEqual(update.fractionComplete, 0)
  }
}
