// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore

final class ProfilingTests: XCTestCase {
  func testProfilingManagerMeasurement() async throws {
    let profiler = ProfilingManager()

    // Mock device info
    let info = MTPDeviceInfo(
      manufacturer: "Test",
      model: "Unit",
      version: "1.0",
      serialNumber: "SN123",
      operationsSupported: [],
      eventsSupported: []
    )

    // Measure a dummy operation
    try await profiler.measure("TestOp") {
      try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
    }

    let profile = await profiler.report(info: info)

    XCTAssertEqual(profile.metrics.count, 1)
    XCTAssertEqual(profile.metrics[0].operation, "TestOp")
    XCTAssertEqual(profile.metrics[0].count, 1)
    XCTAssertGreaterThan(profile.metrics[0].avgMs, 5.0)
  }

  func testProfilingManagerStats() async throws {
    let profiler = ProfilingManager()
    let info = MTPDeviceInfo(
      manufacturer: "Test",
      model: "Unit",
      version: "1.0",
      serialNumber: "SN123",
      operationsSupported: [],
      eventsSupported: []
    )

    // Measure multiple iterations
    for i in 1...10 {
      try await profiler.measure("RepeatOp") {
        try await Task.sleep(nanoseconds: UInt64(i) * 1_000_000)
      }
    }

    let profile = await profiler.report(info: info)
    let metric = profile.metrics[0]

    XCTAssertEqual(metric.count, 10)
    XCTAssertGreaterThan(metric.maxMs, metric.minMs)
    XCTAssertGreaterThan(metric.p95Ms, metric.avgMs)
  }
}
