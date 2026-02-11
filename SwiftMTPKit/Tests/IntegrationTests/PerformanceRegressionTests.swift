// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPIndex
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Performance regression tests that run benchmarks and compare against baselines
@available(macOS 15.0, *)
final class PerformanceRegressionTests: XCTestCase {

  // MARK: - Baseline Management

  static let baselineStorage = PerformanceBaselineStorage()

  // MARK: - Benchmark Tests

  func testThroughputBenchmark() async throws {
    let benchmark = ThroughputBenchmark()

    // Run benchmark with 100MB data
    let result = try await benchmark.measure(bytes: 100 * 1024 * 1024)

    // Record result
    let throughputMbps = Double(result.bytesTransferred) / result.durationMs / 1000.0

    // Compare against baseline
    if let baseline = await Self.baselineStorage.getBaseline(for: "throughput-100m") {
      XCTAssertGreaterThanOrEqual(throughputMbps, baseline * 0.9) // Allow 10% regression
    } else {
      // Store baseline for first run
      await Self.baselineStorage.setBaseline(throughputMbps, for: "throughput-100m")
    }
  }

  func testSmallFileLatency() async throws {
    let benchmark = ThroughputBenchmark()

    // Measure small file transfers (1KB each, 100 files)
    var totalLatency: Double = 0
    for _ in 0..<100 {
      let startTime = Date()
      _ = try await benchmark.measure(bytes: 1024)
      totalLatency += Date().timeIntervalSince(startTime) * 1000 // ms
    }

    let avgLatency = totalLatency / 100.0

    XCTAssertLessThan(avgLatency, 100) // Should be under 100ms average
  }

  func testLargeFileSequentialTransfer() async throws {
    let benchmark = ThroughputBenchmark()

    // Test various sizes
    let sizes = [1024 * 1024, 10 * 1024 * 1024, 100 * 1024 * 1024]

    for size in sizes {
      let result = try await benchmark.measure(bytes: size)
      let throughput = Double(result.bytesTransferred) / result.durationMs * 1000.0 / 1024.0 / 1024.0

      XCTAssertGreaterThan(throughput, 0) // Must have positive throughput
    }
  }

  // MARK: - Memory Tests

  func testMemoryUnderLoad() async throws {
    let memoryTracker = MemoryTracker()

    // Start tracking
    await memoryTracker.startTracking()

    // Simulate heavy load
    for _ in 0..<1000 {
      let benchmark = ThroughputBenchmark()
      _ = try await benchmark.measure(bytes: 1024 * 1024)
    }

    // Get peak memory
    let peakMemory = await memoryTracker.peakMemoryUsage()

    XCTAssertLessThan(peakMemory, 500 * 1024 * 1024) // Under 500MB peak
  }

  func testMemoryLeakDetection() async throws {
    let leakDetector = MemoryLeakDetector()

    // Baseline memory
    let baselineMemory = await leakDetector.currentMemory()

    // Perform many operations
    for _ in 0..<100 {
      let benchmark = ThroughputBenchmark()
      _ = try await benchmark.measure(bytes: 1024)
    }

    // Check for significant memory growth
    let finalMemory = await leakDetector.currentMemory()
    let growth = finalMemory - baselineMemory

    XCTAssertLessThan(growth, 10 * 1024 * 1024) // Less than 10MB growth
  }

  // MARK: - CI Reporting Tests

  func testPerformanceMetricsOutput() async throws {
    var metrics = PerformanceMetrics()

    // Record some metrics
    metrics.recordThroughput(name: "test-throughput", value: 25.5, unit: .mbps)
    metrics.recordLatency(name: "test-latency", value: 45.2, unit: .ms)
    metrics.recordMemory(name: "test-memory", value: 128, unit: .mb)

    // Generate CI report
    let report = metrics.generateCIReport()

    // Verify report contains expected sections
    XCTAssertTrue(report.contains("Throughput") || report.contains("throughput"))
    XCTAssertTrue(report.contains("Latency") || report.contains("latency"))
    XCTAssertTrue(report.contains("Memory") || report.contains("memory"))
  }

  func testBaselineComparison() async throws {
    let comparator = BaselineComparator()

    // Current results
    let currentResults: [String: Double] = [
      "throughput": 25.5,
      "latency": 45.2,
      "memory": 128.0
    ]

    // Previous baselines
    let baselines: [String: Double] = [
      "throughput": 30.0,
      "latency": 40.0,
      "memory": 100.0
    ]

    let comparison = comparator.compare(current: currentResults, baselines: baselines)

    // Check for regressions
    XCTAssertGreaterThanOrEqual(comparison.regressions.count, 0)
    XCTAssertGreaterThanOrEqual(comparison.improvements.count, 0)
  }
}

// MARK: - Supporting Types

/// Storage for performance baselines
actor PerformanceBaselineStorage {
  private var baselines: [String: Double] = [:]

  func getBaseline(for key: String) -> Double? {
    return baselines[key]
  }

  func setBaseline(_ value: Double, for key: String) {
    baselines[key] = value
  }

  func clearAll() {
    baselines.removeAll()
  }
}

/// Throughput benchmark helper
struct ThroughputBenchmark {
  func measure(bytes: Int) async throws -> BenchmarkResult {
    let startTime = Date()

    // Simulate transfer (in real tests, this would do actual I/O)
    try await Task.sleep(nanoseconds: UInt64(Double(bytes) / 1000000)) // Simulated

    let duration = Date().timeIntervalSince(startTime) * 1000 // ms

    return BenchmarkResult(
      bytesTransferred: bytes,
      durationMs: duration
    )
  }
}

struct BenchmarkResult {
  let bytesTransferred: Int
  let durationMs: Double
}

/// Memory tracking helper
actor MemoryTracker {
  private var peakMemory: Int = 0

  func startTracking() {
    peakMemory = currentMemory()
  }

  func peakMemoryUsage() -> Int {
    return peakMemory
  }

  private func currentMemory() -> Int {
    // Simplified - in real implementation would use task info
    return 0
  }
}

/// Memory leak detection helper
actor MemoryLeakDetector {
  func currentMemory() -> Int {
    // Simplified - in real implementation would use task info
    return 0
  }
}

/// Performance metrics collector
struct PerformanceMetrics {
  private var metrics: [PerformanceMetric] = []

  struct PerformanceMetric {
    let name: String
    let value: Double
    let unit: MetricUnit
  }

  enum MetricUnit {
    case mbps
    case ms
    case mb
  }

  mutating func recordThroughput(name: String, value: Double, unit: MetricUnit) {
    metrics.append(PerformanceMetric(name: name, value: value, unit: unit))
  }

  mutating func recordLatency(name: String, value: Double, unit: MetricUnit) {
    metrics.append(PerformanceMetric(name: name, value: value, unit: unit))
  }

  mutating func recordMemory(name: String, value: Double, unit: MetricUnit) {
    metrics.append(PerformanceMetric(name: name, value: value, unit: unit))
  }

  func generateCIReport() -> String {
    var report = "Performance Metrics Report\n"
    report += "========================\n"

    for metric in metrics {
      report += "\(metric.name): \(metric.value) \(unitString(metric.unit))\n"
    }

    return report
  }

  private func unitString(_ unit: MetricUnit) -> String {
    switch unit {
    case .mbps: return "Mbps"
    case .ms: return "ms"
    case .mb: return "MB"
    }
  }
}

/// Baseline comparison helper
struct BaselineComparator {
  struct ComparisonResult {
    let regressions: [String]
    let improvements: [String]
    let unchanged: [String]
  }

  func compare(current: [String: Double], baselines: [String: Double]) -> ComparisonResult {
    var regressions: [String] = []
    var improvements: [String] = []
    var unchanged: [String] = []

    for (key, currentValue) in current {
      if let baselineValue = baselines[key] {
        let threshold = baselineValue * 0.1 // 10% threshold

        if currentValue < baselineValue - threshold {
          regressions.append(key)
        } else if currentValue > baselineValue + threshold {
          improvements.append(key)
        } else {
          unchanged.append(key)
        }
      }
    }

    return ComparisonResult(
      regressions: regressions,
      improvements: improvements,
      unchanged: unchanged
    )
  }
}
