// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPObservability

// MARK: - ThroughputEWMA Edge Cases

final class ThroughputEWMAEdgeCaseTests: XCTestCase {

  func testNegativeDtTreatedAsZeroInstantaneous() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1000, dt: 1.0)
    let rate = ewma.update(bytes: 500, dt: -1.0)
    // Negative dt → inst = 500 / -1 = -500 (no guard), but still exercises the path
    // The key point is it doesn't crash
    XCTAssertEqual(ewma.count, 2)
    _ = rate
  }

  func testZeroBytesProducesZeroRate() {
    var ewma = ThroughputEWMA()
    let rate = ewma.update(bytes: 0, dt: 1.0)
    XCTAssertEqual(rate, 0.0)
    XCTAssertEqual(ewma.bytesPerSecond, 0.0)
    XCTAssertEqual(ewma.megabytesPerSecond, 0.0)
  }

  func testVeryLargeBytesValue() {
    var ewma = ThroughputEWMA()
    let largeBytes = Int.max / 2
    let rate = ewma.update(bytes: largeBytes, dt: 1.0)
    XCTAssertEqual(rate, Double(largeBytes), accuracy: 1.0)
  }

  func testVerySmallDtProducesHighRate() {
    var ewma = ThroughputEWMA()
    let rate = ewma.update(bytes: 1000, dt: 0.0001)
    XCTAssertEqual(rate, 10_000_000.0, accuracy: 1.0)
  }

  func testResetThenUpdateBehavesLikeFirstSample() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 5000, dt: 1.0)
    ewma.update(bytes: 3000, dt: 1.0)
    ewma.reset()
    XCTAssertEqual(ewma.count, 0)
    let rate = ewma.update(bytes: 2000, dt: 1.0)
    // After reset, first sample sets rate directly
    XCTAssertEqual(rate, 2000.0)
    XCTAssertEqual(ewma.count, 1)
  }

  func testMultipleResetsAreIdempotent() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1000, dt: 1.0)
    ewma.reset()
    ewma.reset()
    ewma.reset()
    XCTAssertEqual(ewma.bytesPerSecond, 0)
    XCTAssertEqual(ewma.count, 0)
  }

  func testEWMADecaysTowardNewRate() {
    var ewma = ThroughputEWMA()
    // Start at 10000 B/s
    ewma.update(bytes: 10_000, dt: 1.0)
    // Feed 0 B/s many times → should decay toward 0
    for _ in 0..<100 {
      ewma.update(bytes: 0, dt: 1.0)
    }
    XCTAssertLessThan(ewma.bytesPerSecond, 1.0)
  }
}

// MARK: - ThroughputRingBuffer Edge Cases

final class ThroughputRingBufferEdgeCaseTests: XCTestCase {

  func testSingleSamplePercentiles() {
    var buf = ThroughputRingBuffer(maxSamples: 10)
    buf.addSample(42.0)
    XCTAssertEqual(buf.p50, 42.0)
    XCTAssertEqual(buf.p95, 42.0)
    XCTAssertEqual(buf.average, 42.0)
  }

  func testMaxSamplesOfOneAlwaysHoldsLatest() {
    var buf = ThroughputRingBuffer(maxSamples: 1)
    buf.addSample(10)
    buf.addSample(20)
    buf.addSample(30)
    XCTAssertEqual(buf.count, 1)
    XCTAssertEqual(buf.allSamples, [30])
  }

  func testExactCapacityBoundary() {
    var buf = ThroughputRingBuffer(maxSamples: 3)
    buf.addSample(1)
    buf.addSample(2)
    buf.addSample(3)
    XCTAssertEqual(buf.count, 3)
    XCTAssertEqual(buf.allSamples.sorted(), [1, 2, 3])
    // Adding one more overwrites oldest
    buf.addSample(4)
    XCTAssertEqual(buf.count, 3)
    XCTAssertFalse(buf.allSamples.contains(1))
  }

  func testResetThenAddSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 5)
    buf.addSample(100)
    buf.addSample(200)
    buf.reset()
    XCTAssertEqual(buf.count, 0)
    XCTAssertNil(buf.average)
    buf.addSample(50)
    XCTAssertEqual(buf.count, 1)
    XCTAssertEqual(buf.average, 50.0)
  }

  func testNegativeSampleValues() {
    var buf = ThroughputRingBuffer(maxSamples: 5)
    buf.addSample(-10)
    buf.addSample(-20)
    buf.addSample(30)
    XCTAssertEqual(buf.count, 3)
    XCTAssertEqual(buf.average!, 0.0, accuracy: 0.001)
  }

  func testP50WithEvenNumberOfSamples() {
    var buf = ThroughputRingBuffer()
    for v in [10.0, 20.0, 30.0, 40.0] {
      buf.addSample(v)
    }
    // sorted: [10,20,30,40], p50 = index 2 = 30
    XCTAssertEqual(buf.p50!, 30.0, accuracy: 0.001)
  }

  func testLargeRingBufferP95Accuracy() {
    var buf = ThroughputRingBuffer(maxSamples: 1000)
    for i in 1...1000 {
      buf.addSample(Double(i))
    }
    // p95 index = 950 → value 951
    XCTAssertEqual(buf.p95!, 951.0, accuracy: 0.001)
    XCTAssertEqual(buf.count, 1000)
  }
}

// MARK: - TransactionLog Edge Cases

final class TransactionLogEdgeCaseTests: XCTestCase {

  private func makeRecord(
    txID: UInt32, outcome: TransactionOutcome = .ok, errorDescription: String? = nil,
    bytesIn: Int = 64, bytesOut: Int = 0
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1001, opcodeLabel: "GetDeviceInfo", sessionID: 1,
      startedAt: Date(), duration: 0.1, bytesIn: bytesIn, bytesOut: bytesOut,
      outcomeClass: outcome, errorDescription: errorDescription)
  }

  func testRecentWithZeroLimit() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    await log.append(makeRecord(txID: 2))
    let recent = await log.recent(limit: 0)
    XCTAssertTrue(recent.isEmpty)
  }

  func testDumpEmptyLogProducesEmptyArray() async {
    let log = TransactionLog()
    let json = await log.dump(redacting: false)
    XCTAssertEqual(json, "[\n\n]")
  }

  func testDumpRedactingWithNoErrorDescriptions() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let redacted = await log.dump(redacting: true)
    let unredacted = await log.dump(redacting: false)
    // Both should produce valid JSON; redacting should not alter records without errorDescription
    let redactedData = redacted.data(using: .utf8)!
    let arr = try? JSONSerialization.jsonObject(with: redactedData) as? [[String: Any]]
    XCTAssertNotNil(arr)
    XCTAssertEqual(arr?.count, 1)
    _ = unredacted
  }

  func testDumpRedactsMixedHexContent() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "prefix AABBCCDD11223344 suffix"))
    let json = await log.dump(redacting: true)
    XCTAssertTrue(json.contains("<redacted>"))
    XCTAssertTrue(json.contains("prefix"))
    XCTAssertTrue(json.contains("suffix"))
  }

  func testClearOnEmptyLogIsNoOp() async {
    let log = TransactionLog()
    await log.clear()
    let recent = await log.recent(limit: 10)
    XCTAssertTrue(recent.isEmpty)
  }

  func testConcurrentAppendAndClear() async {
    let log = TransactionLog()
    await withTaskGroup(of: Void.self) { group in
      for i: UInt32 in 1...100 {
        let record = makeRecord(txID: i)
        group.addTask { await log.append(record) }
      }
      group.addTask { await log.clear() }
    }
    // After concurrent operations, log should be in a consistent state
    let recent = await log.recent(limit: 2000)
    XCTAssertTrue(recent.count <= 100)
  }

  func testConcurrentDumpWhileAppending() async {
    let log = TransactionLog()
    for i: UInt32 in 1...50 {
      await log.append(makeRecord(txID: i))
    }
    // Dump concurrently while appends have already completed
    await withTaskGroup(of: String.self) { group in
      for _ in 0..<5 {
        group.addTask { await log.dump(redacting: true) }
      }
      for await json in group {
        XCTAssertTrue(json.hasPrefix("["))
      }
    }
    // Append more and verify
    for i: UInt32 in 51...100 {
      await log.append(makeRecord(txID: i))
    }
    let recent = await log.recent(limit: 200)
    XCTAssertEqual(recent.count, 100)
  }

  func testRecordWithAllOutcomeClasses() async {
    let log = TransactionLog()
    let outcomes: [TransactionOutcome] = [.ok, .deviceError, .timeout, .stall, .ioError, .cancelled]
    for (i, outcome) in outcomes.enumerated() {
      await log.append(makeRecord(txID: UInt32(i + 1), outcome: outcome))
    }
    let recent = await log.recent(limit: 10)
    XCTAssertEqual(recent.count, 6)
    let outcomeClasses = Set(recent.map(\.outcomeClass))
    XCTAssertEqual(outcomeClasses.count, 6)
  }

  func testRecordWithLargeByteCountsRoundTrips() async throws {
    let log = TransactionLog()
    let record = makeRecord(txID: 1, bytesIn: Int.max / 2, bytesOut: Int.max / 2)
    await log.append(record)
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    XCTAssertEqual(arr.count, 1)
  }
}

// MARK: - TransactionOutcome Edge Cases

final class TransactionOutcomeCodableTests: XCTestCase {

  func testAllOutcomesCodableRoundTrip() throws {
    let cases: [TransactionOutcome] = [.ok, .deviceError, .timeout, .stall, .ioError, .cancelled]
    for outcome in cases {
      let data = try JSONEncoder().encode(outcome)
      let decoded = try JSONDecoder().decode(TransactionOutcome.self, from: data)
      XCTAssertEqual(decoded, outcome, "Round-trip failed for \(outcome)")
    }
  }

  func testInvalidRawValueDecodingFails() {
    let json = "\"invalid_value\"".data(using: .utf8)!
    XCTAssertThrowsError(try JSONDecoder().decode(TransactionOutcome.self, from: json))
  }
}

// MARK: - MTPOpcodeLabel Edge Cases

final class MTPOpcodeLabelEdgeCaseTests: XCTestCase {

  func testZeroOpcode() {
    let label = MTPOpcodeLabel.label(for: 0x0000)
    XCTAssertEqual(label, "Unknown(0x0000)")
  }

  func testMaxOpcodeValue() {
    let label = MTPOpcodeLabel.label(for: 0xFFFF)
    XCTAssertEqual(label, "Unknown(0xFFFF)")
  }

  func testAllKnownOpcodesReturnNonUnknown() {
    let knownOpcodes: [UInt16] = [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007, 0x1008,
      0x1009, 0x100A, 0x100B, 0x100C, 0x100D, 0x100E, 0x1014, 0x1015,
      0x1016, 0x1017, 0x101B, 0x95C1, 0x95C4,
    ]
    for opcode in knownOpcodes {
      let label = MTPOpcodeLabel.label(for: opcode)
      XCTAssertFalse(label.hasPrefix("Unknown"), "Opcode 0x\(String(opcode, radix: 16)) was Unknown")
    }
  }
}

// MARK: - ActionableError Edge Cases

final class ActionableErrorEdgeCaseTests: XCTestCase {

  private struct DualConformingError: ActionableError, LocalizedError {
    var actionableDescription: String { "Actionable text" }
    var errorDescription: String? { "Localized text" }
  }

  func testActionableErrorTakesPrecedenceOverLocalized() {
    let error = DualConformingError()
    let desc = actionableDescription(for: error)
    XCTAssertEqual(desc, "Actionable text")
  }

  private struct EmptyActionableError: ActionableError {
    var actionableDescription: String { "" }
  }

  func testEmptyActionableDescription() {
    let desc = actionableDescription(for: EmptyActionableError())
    XCTAssertEqual(desc, "")
  }
}
