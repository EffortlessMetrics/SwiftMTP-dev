// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPThroughput

final class ThroughputMicrocrateTests: XCTestCase {
  func testEWMABasics() {
    var ewma = ThroughputEWMA()
    XCTAssertEqual(ewma.count, 0)
    XCTAssertEqual(ewma.bytesPerSecond, 0)

    let first = ewma.update(bytes: 1024, dt: 1.0)
    XCTAssertEqual(first, 1024, accuracy: 0.0001)
    XCTAssertEqual(ewma.count, 1)
    XCTAssertEqual(ewma.bytesPerSecond, 1024, accuracy: 0.0001)
  }

  func testEWMAReset() {
    var ewma = ThroughputEWMA()
    _ = ewma.update(bytes: 2000, dt: 2.0)
    ewma.reset()
    XCTAssertEqual(ewma.count, 0)
    XCTAssertEqual(ewma.bytesPerSecond, 0)
  }

  func testRingBufferWrapAndPercentiles() {
    var ring = ThroughputRingBuffer(maxSamples: 3)
    ring.addSample(10)
    ring.addSample(20)
    ring.addSample(30)
    ring.addSample(40)

    XCTAssertEqual(ring.count, 3)
    XCTAssertEqual(Set(ring.allSamples), Set([20.0, 30.0, 40.0]))
    XCTAssertEqual(ring.p50, 30)
    XCTAssertEqual(ring.p95, 40)
    XCTAssertEqual(ring.average, 30)
  }
}
