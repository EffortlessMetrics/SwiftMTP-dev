// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPObservability

final class ThroughputCoverageTests: XCTestCase {
  func testEWMAAccessorsExposeCurrentRates() {
    var ewma = ThroughputEWMA()

    XCTAssertEqual(ewma.bytesPerSecond, 0)
    XCTAssertEqual(ewma.megabytesPerSecond, 0)

    _ = ewma.update(bytes: 1_048_576, dt: 1)

    XCTAssertEqual(ewma.bytesPerSecond, 1_048_576, accuracy: 0.0001)
    XCTAssertEqual(ewma.megabytesPerSecond, 1.0, accuracy: 0.0001)
  }

  func testRingBufferAccessorsPercentilesAndReset() {
    var buffer = ThroughputRingBuffer(maxSamples: 5)

    XCTAssertTrue(buffer.allSamples.isEmpty)
    XCTAssertNil(buffer.p50)
    XCTAssertNil(buffer.p95)
    XCTAssertNil(buffer.average)

    [1.0, 2.0, 3.0, 4.0, 5.0].forEach { buffer.addSample($0) }

    XCTAssertEqual(buffer.allSamples.count, 5)
    XCTAssertEqual(buffer.p50, 3.0)
    XCTAssertEqual(buffer.p95, 5.0)
    XCTAssertNotNil(buffer.average)
    XCTAssertEqual(buffer.average ?? 0, 3.0, accuracy: 0.0001)

    buffer.reset()

    XCTAssertEqual(buffer.count, 0)
    XCTAssertTrue(buffer.allSamples.isEmpty)
    XCTAssertNil(buffer.p50)
  }
}
