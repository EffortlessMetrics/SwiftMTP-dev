// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPObservability

// MARK: - Transfer Speed Calculation Tests

final class TransferSpeedCalculationTests: XCTestCase {

  func testSpeedForSingleChunk() {
    var ewma = ThroughputEWMA()
    // 1 MB in 0.5s = 2 MB/s
    let mb = 1024 * 1024
    ewma.update(bytes: mb, dt: 0.5)
    XCTAssertEqual(ewma.megabytesPerSecond, 2.0, accuracy: 0.01)
  }

  func testSpeedAccumulatesOverMultipleChunks() {
    var ewma = ThroughputEWMA()
    let chunkSize = 512 * 1024 // 512 KB
    // Feed 10 chunks at 1 MB/s each (512KB in 0.5s)
    for _ in 0..<10 {
      ewma.update(bytes: chunkSize, dt: 0.5)
    }
    XCTAssertEqual(ewma.megabytesPerSecond, 1.0, accuracy: 0.05)
  }

  func testSpeedWithVaryingChunkSizes() {
    var ewma = ThroughputEWMA()
    // Small chunk
    ewma.update(bytes: 1024, dt: 0.001)
    let afterSmall = ewma.bytesPerSecond
    // Large chunk
    ewma.update(bytes: 8 * 1024 * 1024, dt: 1.0)
    let afterLarge = ewma.bytesPerSecond
    XCTAssertGreaterThan(afterLarge, 0)
    _ = afterSmall
  }

  func testSpeedWithMicrosecondIntervals() {
    var ewma = ThroughputEWMA()
    // 64 bytes in 10 microseconds
    ewma.update(bytes: 64, dt: 0.00001)
    XCTAssertEqual(ewma.bytesPerSecond, 6_400_000, accuracy: 1.0)
  }

  func testSpeedReportsZeroBeforeAnySamples() {
    let ewma = ThroughputEWMA()
    XCTAssertEqual(ewma.bytesPerSecond, 0)
    XCTAssertEqual(ewma.megabytesPerSecond, 0)
  }

  func testSpeedAfterResetReturnsToZero() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1_000_000, dt: 1.0)
    XCTAssertGreaterThan(ewma.bytesPerSecond, 0)
    ewma.reset()
    XCTAssertEqual(ewma.bytesPerSecond, 0)
  }

  func testSpeedForLargeFileTransfer() {
    var ewma = ThroughputEWMA()
    // Simulate 1 GB transfer in 100 chunks of 10 MB at 100 MB/s
    let chunkBytes = 10 * 1024 * 1024
    for _ in 0..<100 {
      ewma.update(bytes: chunkBytes, dt: 0.1)
    }
    // Should converge to ~100 MB/s
    XCTAssertEqual(ewma.megabytesPerSecond, 100.0, accuracy: 1.0)
  }

  func testSpeedSmoothingDampensOutliers() {
    var ewma = ThroughputEWMA()
    // Establish baseline at 1 MB/s
    let mb = 1024 * 1024
    for _ in 0..<20 {
      ewma.update(bytes: mb, dt: 1.0)
    }
    let baseline = ewma.bytesPerSecond
    // Single outlier at 100 MB/s
    ewma.update(bytes: 100 * mb, dt: 1.0)
    let afterOutlier = ewma.bytesPerSecond
    // EWMA should dampen the spike — not jump to 100 MB/s
    XCTAssertLessThan(afterOutlier, Double(50 * mb))
    XCTAssertGreaterThan(afterOutlier, baseline)
  }
}

// MARK: - Throughput Metrics Aggregation Tests

final class ThroughputMetricsAggregationTests: XCTestCase {

  func testAggregateMinMaxFromRingBuffer() {
    var buf = ThroughputRingBuffer(maxSamples: 50)
    let values: [Double] = [10, 50, 30, 70, 20, 90, 40, 60, 80, 100]
    for v in values { buf.addSample(v) }
    XCTAssertEqual(buf.allSamples.min(), 10.0)
    XCTAssertEqual(buf.allSamples.max(), 100.0)
  }

  func testAggregateAverageMatchesMathematicalMean() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    let values: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    for v in values { buf.addSample(v) }
    XCTAssertEqual(buf.average!, 5.5, accuracy: 0.001)
  }

  func testAggregateP50IsMedianForOddCount() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for v in [3.0, 1.0, 2.0, 5.0, 4.0] { buf.addSample(v) }
    // sorted: [1,2,3,4,5], median index = 2 → 3
    XCTAssertEqual(buf.p50!, 3.0, accuracy: 0.001)
  }

  func testAggregateP95ForNormalDistribution() {
    var buf = ThroughputRingBuffer(maxSamples: 200)
    // Values 1..100 uniformly
    for i in 1...100 { buf.addSample(Double(i)) }
    // p95 index = 95 → value 96
    XCTAssertEqual(buf.p95!, 96.0, accuracy: 0.001)
  }

  func testAggregateStandardDeviationViaSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    let values: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
    for v in values { buf.addSample(v) }
    let samples = buf.allSamples
    let mean = samples.reduce(0, +) / Double(samples.count)
    let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(samples.count)
    let stddev = variance.squareRoot()
    XCTAssertEqual(mean, 5.0, accuracy: 0.001)
    XCTAssertEqual(stddev, 2.0, accuracy: 0.001)
  }

  func testAggregateWithSingleSample() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    buf.addSample(42.0)
    XCTAssertEqual(buf.average!, 42.0, accuracy: 0.001)
    XCTAssertEqual(buf.p50!, 42.0, accuracy: 0.001)
    XCTAssertEqual(buf.p95!, 42.0, accuracy: 0.001)
  }

  func testAggregateAfterPartialOverwrite() {
    var buf = ThroughputRingBuffer(maxSamples: 5)
    // Fill: 10, 20, 30, 40, 50
    for v in stride(from: 10.0, through: 50.0, by: 10.0) { buf.addSample(v) }
    // Overwrite first 2: 60, 70 → buffer should be [60, 70, 30, 40, 50]
    buf.addSample(60)
    buf.addSample(70)
    let sorted = buf.allSamples.sorted()
    XCTAssertEqual(sorted, [30, 40, 50, 60, 70])
    XCTAssertEqual(buf.average!, 50.0, accuracy: 0.001)
  }

  func testCombineMultipleEWMAInstances() {
    var ewma1 = ThroughputEWMA()
    var ewma2 = ThroughputEWMA()
    for _ in 0..<20 { ewma1.update(bytes: 1_000_000, dt: 1.0) }
    for _ in 0..<20 { ewma2.update(bytes: 3_000_000, dt: 1.0) }
    let combinedRate = (ewma1.bytesPerSecond + ewma2.bytesPerSecond) / 2.0
    XCTAssertEqual(combinedRate, 2_000_000, accuracy: 100.0)
  }
}

// MARK: - Latency Distribution Tracking Tests

final class LatencyDistributionTests: XCTestCase {

  func testLatencyRecordedInTransactionDuration() {
    let record = TransactionRecord(
      txID: 1, opcode: 0x1008, opcodeLabel: "GetObjectInfo",
      sessionID: 1, startedAt: Date(), duration: 0.025,
      bytesIn: 128, bytesOut: 0, outcomeClass: .ok)
    XCTAssertEqual(record.duration, 0.025, accuracy: 0.0001)
  }

  func testLatencyDistributionViaRingBuffer() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    // Latencies in milliseconds: simulate varying response times
    let latencies: [Double] = [5, 10, 15, 8, 12, 25, 3, 7, 100, 6]
    for l in latencies { buf.addSample(l) }
    XCTAssertEqual(buf.p50!, 10.0, accuracy: 0.001) // sorted[5] of 10 elements
    XCTAssertEqual(buf.allSamples.min(), 3.0)
    XCTAssertEqual(buf.allSamples.max(), 100.0)
  }

  func testLatencyP95IdentifiesTailLatency() {
    var buf = ThroughputRingBuffer(maxSamples: 200)
    // 95 fast operations (5ms), 5 slow operations (500ms)
    for _ in 0..<95 { buf.addSample(5.0) }
    for _ in 0..<5 { buf.addSample(500.0) }
    // p95 should capture the slow tail
    XCTAssertGreaterThan(buf.p95!, 5.0)
  }

  func testLatencyAverageWithBimodalDistribution() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    // Half fast (10ms), half slow (100ms)
    for _ in 0..<50 { buf.addSample(10.0) }
    for _ in 0..<50 { buf.addSample(100.0) }
    XCTAssertEqual(buf.average!, 55.0, accuracy: 0.001)
  }

  func testLatencyTrackingForZeroDuration() {
    let record = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.0,
      bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
    XCTAssertEqual(record.duration, 0.0)
  }

  func testLatencyHistogramBuckets() {
    var buf = ThroughputRingBuffer(maxSamples: 200)
    // 100 samples with values 1..100
    for i in 1...100 { buf.addSample(Double(i)) }
    let samples = buf.allSamples
    let under25 = samples.filter { $0 <= 25 }.count
    let between25and75 = samples.filter { $0 > 25 && $0 <= 75 }.count
    let over75 = samples.filter { $0 > 75 }.count
    XCTAssertEqual(under25, 25)
    XCTAssertEqual(between25and75, 50)
    XCTAssertEqual(over75, 25)
  }
}

// MARK: - Error Rate Monitoring Tests

final class ErrorRateMonitoringTests: XCTestCase {

  private func makeRecord(
    txID: UInt32, outcome: TransactionOutcome, errorDescription: String? = nil
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 256, bytesOut: 0, outcomeClass: outcome,
      errorDescription: errorDescription)
  }

  func testErrorRateFromTransactionLog() async {
    let log = TransactionLog()
    // 8 successes, 2 errors
    for i: UInt32 in 1...8 { await log.append(makeRecord(txID: i, outcome: .ok)) }
    await log.append(makeRecord(txID: 9, outcome: .timeout))
    await log.append(makeRecord(txID: 10, outcome: .deviceError))
    let all = await log.recent(limit: 100)
    let errorCount = all.filter { $0.outcomeClass != .ok }.count
    let errorRate = Double(errorCount) / Double(all.count)
    XCTAssertEqual(errorRate, 0.2, accuracy: 0.001)
  }

  func testErrorRateWithNoErrors() async {
    let log = TransactionLog()
    for i: UInt32 in 1...20 { await log.append(makeRecord(txID: i, outcome: .ok)) }
    let all = await log.recent(limit: 100)
    let errorCount = all.filter { $0.outcomeClass != .ok }.count
    XCTAssertEqual(errorCount, 0)
  }

  func testErrorRateWithAllErrors() async {
    let log = TransactionLog()
    let outcomes: [TransactionOutcome] = [.deviceError, .timeout, .stall, .ioError, .cancelled]
    for (i, outcome) in outcomes.enumerated() {
      await log.append(makeRecord(txID: UInt32(i + 1), outcome: outcome))
    }
    let all = await log.recent(limit: 100)
    let errorRate = Double(all.filter { $0.outcomeClass != .ok }.count) / Double(all.count)
    XCTAssertEqual(errorRate, 1.0, accuracy: 0.001)
  }

  func testErrorBreakdownByOutcomeClass() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, outcome: .timeout))
    await log.append(makeRecord(txID: 2, outcome: .timeout))
    await log.append(makeRecord(txID: 3, outcome: .stall))
    await log.append(makeRecord(txID: 4, outcome: .ioError))
    await log.append(makeRecord(txID: 5, outcome: .ok))
    let all = await log.recent(limit: 100)
    let byOutcome = Dictionary(grouping: all, by: \.outcomeClass)
    XCTAssertEqual(byOutcome[.timeout]?.count, 2)
    XCTAssertEqual(byOutcome[.stall]?.count, 1)
    XCTAssertEqual(byOutcome[.ioError]?.count, 1)
    XCTAssertEqual(byOutcome[.ok]?.count, 1)
  }

  func testErrorRateOverSlidingWindow() async {
    let log = TransactionLog()
    // First 10 all OK
    for i: UInt32 in 1...10 { await log.append(makeRecord(txID: i, outcome: .ok)) }
    // Next 10 half errors
    for i: UInt32 in 11...15 { await log.append(makeRecord(txID: i, outcome: .ok)) }
    for i: UInt32 in 16...20 { await log.append(makeRecord(txID: i, outcome: .timeout)) }
    // Sliding window of last 10
    let window = await log.recent(limit: 10)
    let windowErrors = window.filter { $0.outcomeClass != .ok }.count
    XCTAssertEqual(windowErrors, 5)
  }

  func testConsecutiveErrorDetection() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, outcome: .ok))
    await log.append(makeRecord(txID: 2, outcome: .timeout))
    await log.append(makeRecord(txID: 3, outcome: .timeout))
    await log.append(makeRecord(txID: 4, outcome: .timeout))
    await log.append(makeRecord(txID: 5, outcome: .ok))
    let all = await log.recent(limit: 100)
    // Find max consecutive errors
    var maxConsecutive = 0
    var current = 0
    for r in all {
      if r.outcomeClass != .ok { current += 1; maxConsecutive = max(maxConsecutive, current) }
      else { current = 0 }
    }
    XCTAssertEqual(maxConsecutive, 3)
  }
}

// MARK: - Diagnostic Report Generation Tests

final class DiagnosticReportGenerationTests: XCTestCase {

  private func makeRecord(
    txID: UInt32, opcode: UInt16 = 0x1009, label: String = "GetObject",
    outcome: TransactionOutcome = .ok, errorDescription: String? = nil,
    bytesIn: Int = 256, duration: TimeInterval = 0.1
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: opcode, opcodeLabel: label,
      sessionID: 1, startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(txID)),
      duration: duration, bytesIn: bytesIn, bytesOut: 0,
      outcomeClass: outcome, errorDescription: errorDescription)
  }

  func testDumpProducesValidJSONArray() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    await log.append(makeRecord(txID: 2))
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.count, 2)
  }

  func testDiagnosticReportIncludesAllFields() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "test err"))
    let json = await log.dump(redacting: false)
    let requiredFields = [
      "txID", "opcode", "opcodeLabel", "sessionID",
      "startedAt", "duration", "bytesIn", "bytesOut",
      "outcomeClass", "errorDescription",
    ]
    for field in requiredFields {
      XCTAssertTrue(json.contains("\"\(field)\""), "Missing field: \(field)")
    }
  }

  func testDiagnosticReportRedactsSensitiveData() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "SN=DEADBEEF12345678"))
    let json = await log.dump(redacting: true)
    XCTAssertFalse(json.contains("DEADBEEF12345678"))
    XCTAssertTrue(json.contains("<redacted>"))
  }

  func testDiagnosticReportEmptyLogIsValidJSON() async {
    let log = TransactionLog()
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any]
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.count, 0)
  }

  func testDiagnosticReportMixedOutcomes() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, outcome: .ok))
    await log.append(makeRecord(txID: 2, outcome: .timeout, errorDescription: "5s timeout"))
    await log.append(makeRecord(txID: 3, outcome: .stall))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("\"ok\""))
    XCTAssertTrue(json.contains("\"timeout\""))
    XCTAssertTrue(json.contains("\"stall\""))
  }

  func testDiagnosticReportUsesISO8601Dates() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    // ISO 8601 date should contain "T" separator
    XCTAssertTrue(json.contains("T"))
    // Our epoch-based dates include "2023"
    XCTAssertTrue(json.contains("2023"))
  }

  func testDiagnosticReportSortedKeys() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    // With sortedKeys, "bytesIn" comes before "duration"
    if let rangeB = json.range(of: "bytesIn"),
      let rangeD = json.range(of: "duration")
    {
      XCTAssertTrue(rangeB.lowerBound < rangeD.lowerBound)
    }
  }

  func testDiagnosticReportWithMaxRecords() async {
    let log = TransactionLog()
    for i: UInt32 in 1...1000 {
      await log.append(makeRecord(txID: i))
    }
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertEqual(parsed?.count, 1000)
  }
}

// MARK: - Log Filtering and Redaction Tests

final class LogFilteringRedactionTests: XCTestCase {

  private func makeRecord(
    txID: UInt32, outcome: TransactionOutcome = .ok,
    errorDescription: String? = nil
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 256, bytesOut: 0, outcomeClass: outcome,
      errorDescription: errorDescription)
  }

  func testFilterRecordsByOutcome() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, outcome: .ok))
    await log.append(makeRecord(txID: 2, outcome: .timeout))
    await log.append(makeRecord(txID: 3, outcome: .ok))
    await log.append(makeRecord(txID: 4, outcome: .stall))
    let all = await log.recent(limit: 100)
    let errors = all.filter { $0.outcomeClass != .ok }
    XCTAssertEqual(errors.count, 2)
    XCTAssertEqual(Set(errors.map(\.txID)), [2, 4])
  }

  func testFilterRecordsByOpcode() async {
    let log = TransactionLog()
    await log.append(TransactionRecord(
      txID: 1, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 256, bytesOut: 0, outcomeClass: .ok))
    await log.append(TransactionRecord(
      txID: 2, opcode: 0x100D, opcodeLabel: "SendObject",
      sessionID: 1, startedAt: Date(), duration: 0.2,
      bytesIn: 0, bytesOut: 512, outcomeClass: .ok))
    let all = await log.recent(limit: 100)
    let getOps = all.filter { $0.opcode == 0x1009 }
    XCTAssertEqual(getOps.count, 1)
  }

  func testRedactionPreservesNonHexText() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "USB timeout on endpoint 3"))
    let json = await log.dump(redacting: true)
    XCTAssertTrue(json.contains("USB timeout on endpoint 3"))
  }

  func testRedactionHandlesExactly8HexChars() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "id=AABBCCDD"))
    let json = await log.dump(redacting: true)
    // Exactly 8 hex chars should be redacted (>= 8 threshold)
    XCTAssertTrue(json.contains("<redacted>"))
  }

  func testRedactionSkips7HexChars() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "code=AABBCCD"))
    let json = await log.dump(redacting: true)
    // 7 hex chars should NOT be redacted
    XCTAssertTrue(json.contains("AABBCCD"))
  }

  func testFilterRecentByLimit() async {
    let log = TransactionLog()
    for i: UInt32 in 1...50 {
      await log.append(makeRecord(txID: i))
    }
    let last5 = await log.recent(limit: 5)
    XCTAssertEqual(last5.count, 5)
    XCTAssertEqual(last5.first?.txID, 46)
    XCTAssertEqual(last5.last?.txID, 50)
  }
}

// MARK: - Performance Baseline Comparison Tests

final class PerformanceBaselineComparisonTests: XCTestCase {

  func testBaselineComparisonWithinTolerance() {
    var ewma = ThroughputEWMA()
    let baseline = 5_000_000.0 // 5 MB/s baseline
    for _ in 0..<50 {
      ewma.update(bytes: 5_000_000, dt: 1.0)
    }
    let deviation = abs(ewma.bytesPerSecond - baseline) / baseline
    XCTAssertLessThan(deviation, 0.01) // < 1% deviation
  }

  func testBaselineRegressionDetection() {
    var ewma = ThroughputEWMA()
    let baseline = 10_000_000.0 // 10 MB/s baseline
    // Simulate regression: only 5 MB/s
    for _ in 0..<50 {
      ewma.update(bytes: 5_000_000, dt: 1.0)
    }
    let deviation = (baseline - ewma.bytesPerSecond) / baseline
    XCTAssertGreaterThan(deviation, 0.4) // > 40% regression
  }

  func testBaselineImprovementDetection() {
    var current = ThroughputEWMA()
    for _ in 0..<50 { current.update(bytes: 15_000_000, dt: 1.0) }
    let baseline = 10_000_000.0
    let improvement = (current.bytesPerSecond - baseline) / baseline
    XCTAssertGreaterThan(improvement, 0.4) // > 40% improvement
  }

  func testBaselineComparisonUsingP50() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    // Baseline p50 = 50, new p50 should be around 75
    for i in 50...100 { buf.addSample(Double(i)) }
    XCTAssertGreaterThan(buf.p50!, 70.0)
  }

  func testBaselineStabilityOverTime() {
    var ewma = ThroughputEWMA()
    var readings: [Double] = []
    for _ in 0..<100 {
      ewma.update(bytes: 1_000_000, dt: 1.0)
      readings.append(ewma.bytesPerSecond)
    }
    // Last 10 readings should be very stable
    let last10 = readings.suffix(10)
    let mean = last10.reduce(0, +) / Double(last10.count)
    for r in last10 {
      XCTAssertEqual(r, mean, accuracy: 1.0)
    }
  }
}

// MARK: - Metric Export Format Tests

final class MetricExportFormatTests: XCTestCase {

  private func makeRecord(txID: UInt32) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      duration: 0.5, bytesIn: 1024, bytesOut: 0, outcomeClass: .ok)
  }

  func testExportAsJSONIsUTF8() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    XCTAssertNotNil(json.data(using: .utf8))
  }

  func testExportJSONContainsArrayBrackets() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.hasPrefix("["))
    XCTAssertTrue(json.hasSuffix("]"))
  }

  func testExportJSONIsPrettyPrinted() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    // Pretty printed JSON contains newlines and indentation
    XCTAssertTrue(json.contains("\n"))
    XCTAssertTrue(json.contains("  "))
  }

  func testExportedRecordDecodable() async throws {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 42))
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let records = try decoder.decode([TransactionRecord].self, from: data)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].txID, 42)
    XCTAssertEqual(records[0].opcodeLabel, "GetObject")
  }

  func testExportMultipleRecordsDecodable() async throws {
    let log = TransactionLog()
    for i: UInt32 in 1...5 { await log.append(makeRecord(txID: i)) }
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let records = try decoder.decode([TransactionRecord].self, from: data)
    XCTAssertEqual(records.count, 5)
    XCTAssertEqual(records.map(\.txID), [1, 2, 3, 4, 5])
  }

  func testExportedOutcomeClassesMatchRawValues() async {
    let log = TransactionLog()
    await log.append(TransactionRecord(
      txID: 1, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 0, bytesOut: 0, outcomeClass: .timeout))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("\"timeout\""))
  }

  func testExportEmptyLogProducesEmptyArray() async {
    let log = TransactionLog()
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
    XCTAssertNotNil(arr)
    XCTAssertEqual(arr?.count, 0)
  }
}

// MARK: - Memory Usage Tracking Tests

final class MemoryUsageTrackingTests: XCTestCase {

  func testRingBufferMemoryBoundByMaxSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 10)
    for i in 0..<1000 { buf.addSample(Double(i)) }
    XCTAssertEqual(buf.count, 10)
  }

  func testTransactionLogMemoryBoundByMaxRecords() async {
    let log = TransactionLog()
    for i: UInt32 in 1...2000 {
      await log.append(TransactionRecord(
        txID: i, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
        sessionID: 1, startedAt: Date(), duration: 0.01,
        bytesIn: 8, bytesOut: 0, outcomeClass: .ok))
    }
    let all = await log.recent(limit: 5000)
    XCTAssertEqual(all.count, 1000)
  }

  func testRingBufferResetFreesMemory() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for i in 0..<100 { buf.addSample(Double(i)) }
    XCTAssertEqual(buf.count, 100)
    buf.reset()
    XCTAssertEqual(buf.count, 0)
    XCTAssertTrue(buf.allSamples.isEmpty)
  }

  func testTransactionLogClearFreesRecords() async {
    let log = TransactionLog()
    for i: UInt32 in 1...500 {
      await log.append(TransactionRecord(
        txID: i, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
        sessionID: 1, startedAt: Date(), duration: 0.01,
        bytesIn: 0, bytesOut: 0, outcomeClass: .ok))
    }
    await log.clear()
    let all = await log.recent(limit: 1000)
    XCTAssertEqual(all.count, 0)
  }

  func testEWMAHasConstantMemoryFootprint() {
    var ewma = ThroughputEWMA()
    // EWMA stores only rate + count — doesn't grow with samples
    for i in 0..<10000 {
      ewma.update(bytes: i * 100, dt: 0.1)
    }
    XCTAssertEqual(ewma.count, 10000)
    // If we got here without OOM, constant memory is confirmed
    XCTAssertGreaterThan(ewma.bytesPerSecond, 0)
  }

  func testSmallRingBufferStaysSmall() {
    var buf = ThroughputRingBuffer(maxSamples: 3)
    for i in 0..<10000 { buf.addSample(Double(i)) }
    XCTAssertEqual(buf.count, 3)
  }
}

// MARK: - Opcode Label Diagnostic Tests

final class OpcodeLabelDiagnosticTests: XCTestCase {

  func testAllStandardMTPOpcodesCovered() {
    let standardOpcodes: [UInt16] = [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007,
      0x1008, 0x1009, 0x100A, 0x100B, 0x100C, 0x100D, 0x100E,
      0x1014, 0x1015, 0x1016, 0x1017, 0x101B,
    ]
    for opcode in standardOpcodes {
      let label = MTPOpcodeLabel.label(for: opcode)
      XCTAssertFalse(
        label.hasPrefix("Unknown"),
        "Standard opcode 0x\(String(opcode, radix: 16)) is not labeled")
    }
  }

  func testAndroidExtensionOpcodesCovered() {
    let androidOpcodes: [UInt16] = [0x95C1, 0x95C4]
    for opcode in androidOpcodes {
      let label = MTPOpcodeLabel.label(for: opcode)
      XCTAssertFalse(label.hasPrefix("Unknown"))
    }
  }

  func testUnknownOpcodeFormatIncludesHex() {
    let label = MTPOpcodeLabel.label(for: 0xBEEF)
    XCTAssertEqual(label, "Unknown(0xBEEF)")
  }

  func testUnknownOpcodeZeroPadded() {
    let label = MTPOpcodeLabel.label(for: 0x0001)
    XCTAssertEqual(label, "Unknown(0x0001)")
  }

  func testOpcodeLabelsAreHumanReadable() {
    let label = MTPOpcodeLabel.label(for: 0x1009)
    XCTAssertEqual(label, "GetObject")
    // No underscores, no hex — camelCase label
    XCTAssertFalse(label.contains("_"))
    XCTAssertFalse(label.contains("0x"))
  }
}

// MARK: - Transaction Record Codable Round-Trip Tests

final class TransactionRecordCodableTests: XCTestCase {

  func testRoundTripWithAllOutcomes() throws {
    let outcomes: [TransactionOutcome] = [.ok, .deviceError, .timeout, .stall, .ioError, .cancelled]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for outcome in outcomes {
      let record = TransactionRecord(
        txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
        sessionID: 1, startedAt: Date(timeIntervalSince1970: 1_000_000),
        duration: 0.1, bytesIn: 0, bytesOut: 0,
        outcomeClass: outcome, errorDescription: "test")
      let data = try encoder.encode(record)
      let decoded = try decoder.decode(TransactionRecord.self, from: data)
      XCTAssertEqual(decoded.outcomeClass, outcome)
      XCTAssertEqual(decoded.errorDescription, "test")
    }
  }

  func testRoundTripWithNilErrorDescription() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = TransactionRecord(
      txID: 99, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 5, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      duration: 1.5, bytesIn: 4096, bytesOut: 0, outcomeClass: .ok)
    let data = try encoder.encode(record)
    let decoded = try decoder.decode(TransactionRecord.self, from: data)
    XCTAssertEqual(decoded.txID, 99)
    XCTAssertNil(decoded.errorDescription)
  }

  func testRoundTripPreservesAllFields() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)
    let record = TransactionRecord(
      txID: 42, opcode: 0x100D, opcodeLabel: "SendObject",
      sessionID: 7, startedAt: startDate,
      duration: 2.5, bytesIn: 0, bytesOut: 8192,
      outcomeClass: .ioError, errorDescription: "bulk write pipe error")
    let data = try encoder.encode(record)
    let decoded = try decoder.decode(TransactionRecord.self, from: data)
    XCTAssertEqual(decoded.txID, 42)
    XCTAssertEqual(decoded.opcode, 0x100D)
    XCTAssertEqual(decoded.opcodeLabel, "SendObject")
    XCTAssertEqual(decoded.sessionID, 7)
    XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, startDate.timeIntervalSince1970, accuracy: 1)
    XCTAssertEqual(decoded.duration, 2.5, accuracy: 0.001)
    XCTAssertEqual(decoded.bytesIn, 0)
    XCTAssertEqual(decoded.bytesOut, 8192)
    XCTAssertEqual(decoded.outcomeClass, .ioError)
    XCTAssertEqual(decoded.errorDescription, "bulk write pipe error")
  }
}
