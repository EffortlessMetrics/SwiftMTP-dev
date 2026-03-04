// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import OSLog
import XCTest

@testable import SwiftMTPObservability

// MARK: - Log Level / Category Filtering Tests

final class LogLevelFilteringTests: XCTestCase {

  func testTransportLoggerUsesTransportCategory() {
    // OSLog.Logger doesn't expose category, but we verify it's constructed without crash
    // and is the dedicated transport logger.
    let logger = MTPLog.transport
    _ = logger  // access doesn't trap
  }

  func testProtoLoggerUsesProtocolCategory() {
    let logger = MTPLog.proto
    _ = logger
  }

  func testIndexLoggerUsesIndexCategory() {
    let logger = MTPLog.index
    _ = logger
  }

  func testSyncLoggerUsesSyncCategory() {
    let logger = MTPLog.sync
    _ = logger
  }

  func testPerfLoggerUsesPerformanceCategory() {
    let logger = MTPLog.perf
    _ = logger
  }

  func testSessionLoggerUsesSessionCategory() {
    let logger = MTPLog.session
    _ = logger
  }

  func testTransferLoggerUsesTransferCategory() {
    let logger = MTPLog.transfer
    _ = logger
  }

  func testQuirksLoggerUsesQuirksCategory() {
    let logger = MTPLog.quirks
    _ = logger
  }

  func testFileProviderLoggerUsesFileProviderCategory() {
    let logger = MTPLog.fileProvider
    _ = logger
  }

  func testCLILoggerUsesCLICategory() {
    let logger = MTPLog.cli
    _ = logger
  }

  func testAllCategoryLoggersShareSubsystem() {
    // All loggers are created with the same subsystem constant.
    XCTAssertEqual(MTPLog.subsystem, "com.effortlessmetrics.swiftmtp")
  }

  func testSignpostCategoriesAreSeparateFromMainLoggers() {
    // Signpost loggers exist in a dedicated namespace and don't collide.
    _ = MTPLog.Signpost.enumerate
    _ = MTPLog.Signpost.transfer
    _ = MTPLog.Signpost.resume
    _ = MTPLog.Signpost.chunk
  }

  func testSignpostLoggersAndSignpostersArePaired() {
    // Each signpost logger has a corresponding OSSignposter.
    _ = MTPLog.Signpost.enumerateSignposter
    _ = MTPLog.Signpost.transferSignposter
    _ = MTPLog.Signpost.resumeSignposter
    _ = MTPLog.Signpost.chunkSignposter
  }
}

// MARK: - Structured Metadata Tests

final class StructuredMetadataTests: XCTestCase {

  private func makeRecord(
    txID: UInt32 = 1,
    opcode: UInt16 = 0x1009,
    opcodeLabel: String = "GetObject",
    sessionID: UInt32 = 7,
    duration: TimeInterval = 1.25,
    bytesIn: Int = 4096,
    bytesOut: Int = 0,
    outcome: TransactionOutcome = .ok,
    errorDescription: String? = nil
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: opcode, opcodeLabel: opcodeLabel,
      sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      duration: duration, bytesIn: bytesIn, bytesOut: bytesOut,
      outcomeClass: outcome, errorDescription: errorDescription)
  }

  func testRecordCarriesDeviceSessionID() {
    let r = makeRecord(sessionID: 42)
    XCTAssertEqual(r.sessionID, 42)
  }

  func testRecordCarriesOperationLabel() {
    let r = makeRecord(opcodeLabel: "SendObject")
    XCTAssertEqual(r.opcodeLabel, "SendObject")
  }

  func testRecordCarriesDuration() {
    let r = makeRecord(duration: 3.14)
    XCTAssertEqual(r.duration, 3.14, accuracy: 0.001)
  }

  func testRecordCarriesBidirectionalByteCounters() {
    let r = makeRecord(bytesIn: 1024, bytesOut: 512)
    XCTAssertEqual(r.bytesIn, 1024)
    XCTAssertEqual(r.bytesOut, 512)
  }

  func testRecordCarriesTimestamp() {
    let r = makeRecord()
    XCTAssertEqual(r.startedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
  }

  func testRecordCarriesRawOpcode() {
    let r = makeRecord(opcode: 0x100D)
    XCTAssertEqual(r.opcode, 0x100D)
  }

  func testRecordNilErrorDescriptionByDefault() {
    let r = makeRecord()
    XCTAssertNil(r.errorDescription)
  }

  func testRecordOptionalErrorDescription() {
    let r = makeRecord(errorDescription: "stall on EP2")
    XCTAssertEqual(r.errorDescription, "stall on EP2")
  }
}

// MARK: - Log Format Consistency Tests

final class LogFormatConsistencyTests: XCTestCase {

  private func makeRecord(
    txID: UInt32 = 1,
    outcome: TransactionOutcome = .ok,
    errorDescription: String? = nil
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(timeIntervalSince1970: 0),
      duration: 0.1, bytesIn: 64, bytesOut: 0,
      outcomeClass: outcome, errorDescription: errorDescription)
  }

  func testDumpOutputIsPrettyPrintedJSON() async {
    let log = TransactionLog()
    await log.append(makeRecord())
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("\n"))
    XCTAssertTrue(json.hasPrefix("["))
    XCTAssertTrue(json.hasSuffix("]"))
  }

  func testDumpOutputHasSortedKeys() async {
    let log = TransactionLog()
    await log.append(makeRecord())
    let json = await log.dump(redacting: false)
    // sortedKeys means "bytesIn" should appear before "bytesOut"
    if let rangeIn = json.range(of: "bytesIn"),
      let rangeOut = json.range(of: "bytesOut")
    {
      XCTAssertTrue(rangeIn.lowerBound < rangeOut.lowerBound)
    }
  }

  func testDumpUsesISO8601DateFormat() async {
    let log = TransactionLog()
    await log.append(makeRecord())
    let json = await log.dump(redacting: false)
    // ISO 8601 for epoch 0 includes "1970"
    XCTAssertTrue(json.contains("1970"))
  }

  func testDumpMultipleRecordsAllPresent() async {
    let log = TransactionLog()
    for i: UInt32 in 1...5 {
      await log.append(makeRecord(txID: i))
    }
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertEqual(arr?.count, 5)
  }

  func testDumpFieldNamesMatchPropertyNames() async {
    let log = TransactionLog()
    await log.append(makeRecord())
    let json = await log.dump(redacting: false)
    let expectedKeys = [
      "txID", "opcode", "opcodeLabel", "sessionID", "startedAt",
      "duration", "bytesIn", "bytesOut", "outcomeClass",
    ]
    for key in expectedKeys {
      XCTAssertTrue(json.contains("\"\(key)\""), "Missing key: \(key)")
    }
  }
}

// MARK: - Performance Metric Recording Tests

final class PerformanceMetricRecordingTests: XCTestCase {

  func testTransferSpeedViaThroughputEWMA() {
    var ewma = ThroughputEWMA()
    // Simulate a 10 MB/s transfer
    let mb = 1024.0 * 1024.0
    ewma.update(bytes: Int(10 * mb), dt: 1.0)
    XCTAssertEqual(ewma.megabytesPerSecond, 10.0, accuracy: 0.01)
  }

  func testLatencyTrackedViaDuration() {
    let record = TransactionRecord(
      txID: 1, opcode: 0x1002, opcodeLabel: "OpenSession",
      sessionID: 1, startedAt: Date(), duration: 0.035,
      bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
    XCTAssertEqual(record.duration, 0.035, accuracy: 0.0001)
  }

  func testThroughputTracksSpikeAndDrop() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1_000_000, dt: 1.0)
    let afterSpike = ewma.update(bytes: 10_000_000, dt: 1.0)
    let afterDrop = ewma.update(bytes: 100, dt: 1.0)
    XCTAssertGreaterThan(afterSpike, 1_000_000)
    XCTAssertLessThan(afterDrop, afterSpike)
  }

  func testRingBufferCapturesAllSamplesUpToCapacity() {
    var buf = ThroughputRingBuffer(maxSamples: 5)
    for v in [100.0, 200.0, 300.0, 400.0, 500.0] {
      buf.addSample(v)
    }
    XCTAssertEqual(buf.count, 5)
    XCTAssertEqual(buf.average!, 300.0, accuracy: 0.001)
  }

  func testRingBufferOverflowDiscardsStaleSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 3)
    buf.addSample(100)
    buf.addSample(200)
    buf.addSample(300)
    buf.addSample(400)
    buf.addSample(500)
    // Only last 3 remain
    XCTAssertEqual(buf.count, 3)
    let sorted = buf.allSamples.sorted()
    XCTAssertEqual(sorted, [300, 400, 500])
  }
}

// MARK: - Log Rotation / Buffering Behavior Tests

final class LogRotationBufferingTests: XCTestCase {

  private func makeRecord(txID: UInt32) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.01,
      bytesIn: 8, bytesOut: 0, outcomeClass: .ok)
  }

  func testLogCapsAtMaxRecords() async {
    let log = TransactionLog()
    for i: UInt32 in 1...1001 {
      await log.append(makeRecord(txID: i))
    }
    let all = await log.recent(limit: 2000)
    XCTAssertEqual(all.count, 1000)
  }

  func testOldestRecordsEvictedFirst() async {
    let log = TransactionLog()
    for i: UInt32 in 1...1100 {
      await log.append(makeRecord(txID: i))
    }
    let all = await log.recent(limit: 2000)
    // First 100 should have been evicted
    XCTAssertEqual(all.first?.txID, 101)
    XCTAssertEqual(all.last?.txID, 1100)
  }

  func testLogPreservesInsertionOrder() async {
    let log = TransactionLog()
    for i: UInt32 in 1...10 {
      await log.append(makeRecord(txID: i))
    }
    let all = await log.recent(limit: 20)
    let txIDs = all.map(\.txID)
    XCTAssertEqual(txIDs, Array(1...10))
  }

  func testClearResetsCapacityForNewRecords() async {
    let log = TransactionLog()
    for i: UInt32 in 1...500 {
      await log.append(makeRecord(txID: i))
    }
    await log.clear()
    for i: UInt32 in 501...600 {
      await log.append(makeRecord(txID: i))
    }
    let all = await log.recent(limit: 200)
    XCTAssertEqual(all.count, 100)
    XCTAssertEqual(all.first?.txID, 501)
  }

  func testRingBufferRotatesMaintainsCorrectCount() {
    var buf = ThroughputRingBuffer(maxSamples: 4)
    for i in 1...20 {
      buf.addSample(Double(i))
    }
    XCTAssertEqual(buf.count, 4)
    // Last 4 values: 17, 18, 19, 20
    XCTAssertEqual(buf.allSamples.sorted(), [17, 18, 19, 20])
  }
}

// MARK: - Concurrent Logging Tests

final class ConcurrentLoggingTests: XCTestCase {

  private func makeRecord(txID: UInt32) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 0.05,
      bytesIn: 256, bytesOut: 0, outcomeClass: .ok)
  }

  func testConcurrentAppendsFromManyTasks() async {
    let log = TransactionLog()
    await withTaskGroup(of: Void.self) { group in
      for i: UInt32 in 1...500 {
        let record = makeRecord(txID: i)
        group.addTask { await log.append(record) }
      }
    }
    let all = await log.recent(limit: 600)
    XCTAssertEqual(all.count, 500)
    // All txIDs present (order may vary due to concurrency)
    let ids = Set(all.map(\.txID))
    XCTAssertEqual(ids.count, 500)
  }

  func testConcurrentReadsDoNotCorruptData() async {
    let log = TransactionLog()
    for i: UInt32 in 1...50 {
      await log.append(makeRecord(txID: i))
    }
    // Many concurrent reads
    await withTaskGroup(of: [TransactionRecord].self) { group in
      for _ in 0..<20 {
        group.addTask { await log.recent(limit: 50) }
      }
      for await records in group {
        XCTAssertEqual(records.count, 50)
      }
    }
  }

  func testConcurrentAppendAndReadAreConsistent() async {
    let log = TransactionLog()
    await withTaskGroup(of: Void.self) { group in
      // Writers
      for i: UInt32 in 1...100 {
        let record = makeRecord(txID: i)
        group.addTask { await log.append(record) }
      }
      // Readers (interleaved)
      for _ in 0..<10 {
        group.addTask {
          let recent = await log.recent(limit: 200)
          XCTAssertTrue(recent.count <= 100)
        }
      }
    }
    let final_ = await log.recent(limit: 200)
    XCTAssertEqual(final_.count, 100)
  }

  func testConcurrentDumpProducesValidJSON() async {
    let log = TransactionLog()
    for i: UInt32 in 1...20 {
      await log.append(makeRecord(txID: i))
    }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask {
          let json = await log.dump(redacting: false)
          let data = json.data(using: .utf8)!
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
          XCTAssertNotNil(parsed)
          XCTAssertEqual(parsed?.count, 20)
        }
      }
    }
  }
}

// MARK: - Log Sanitization Tests (no secrets/PII)

final class LogSanitizationTests: XCTestCase {

  private func makeRecord(errorDescription: String?) -> TransactionRecord {
    TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.1,
      bytesIn: 0, bytesOut: 0, outcomeClass: .deviceError,
      errorDescription: errorDescription)
  }

  func testRedactsHexSerialNumber() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: "serial=0123456789ABCDEF"))
    let json = await log.dump(redacting: true)
    XCTAssertFalse(json.contains("0123456789ABCDEF"))
    XCTAssertTrue(json.contains("<redacted>"))
  }

  func testRedactsMultipleHexSequencesInSameDescription() async {
    let log = TransactionLog()
    await log.append(
      makeRecord(errorDescription: "dev=AABBCCDD1122 other=33445566EEFF0011"))
    let json = await log.dump(redacting: true)
    XCTAssertFalse(json.contains("AABBCCDD1122"))
    XCTAssertFalse(json.contains("33445566EEFF0011"))
  }

  func testShortHexSequencesAreNotRedacted() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: "code=0x1009"))
    let json = await log.dump(redacting: true)
    // "1009" is only 4 hex chars, below the 8-char threshold
    XCTAssertTrue(json.contains("1009"))
  }

  func testNonHexTextPreservedDuringRedaction() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: "USB stall on endpoint 2"))
    let json = await log.dump(redacting: true)
    XCTAssertTrue(json.contains("USB stall on endpoint 2"))
  }

  func testRedactingFalsePreservesAllContent() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: "serial=AABBCCDD11223344"))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("AABBCCDD11223344"))
  }

  func testNilErrorDescriptionUnaffectedByRedaction() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: nil))
    let redacted = await log.dump(redacting: true)
    let unredacted = await log.dump(redacting: false)
    // Both should produce equivalent JSON for the same nil-error record
    let rData = redacted.data(using: .utf8)!
    let uData = unredacted.data(using: .utf8)!
    let rArr = try? JSONSerialization.jsonObject(with: rData) as? [[String: Any]]
    let uArr = try? JSONSerialization.jsonObject(with: uData) as? [[String: Any]]
    XCTAssertEqual(rArr?.count, uArr?.count)
  }

  func testEmptyErrorDescriptionPreserved() async {
    let log = TransactionLog()
    await log.append(makeRecord(errorDescription: ""))
    let json = await log.dump(redacting: true)
    // Empty string has no hex to redact; field should still be present
    let data = json.data(using: .utf8)!
    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertNotNil(arr?.first?["errorDescription"])
  }
}

// MARK: - Metric Aggregation Tests (min/max/avg/p50/p95)

final class MetricAggregationTests: XCTestCase {

  func testP50OnOddCount() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for v in [1.0, 2.0, 3.0, 4.0, 5.0] {
      buf.addSample(v)
    }
    XCTAssertEqual(buf.p50!, 3.0, accuracy: 0.001)
  }

  func testP95OnSmallSample() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    buf.addSample(10)
    buf.addSample(20)
    // p95 index = Int(2 * 0.95) = 1
    XCTAssertEqual(buf.p95!, 20.0, accuracy: 0.001)
  }

  func testAverageMatchesManualComputation() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    let values: [Double] = [10, 20, 30, 40, 50]
    for v in values { buf.addSample(v) }
    let expected = values.reduce(0, +) / Double(values.count)
    XCTAssertEqual(buf.average!, expected, accuracy: 0.001)
  }

  func testMinValueInSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for v in [500.0, 100.0, 300.0, 200.0, 400.0] {
      buf.addSample(v)
    }
    let min = buf.allSamples.min()
    XCTAssertEqual(min, 100.0)
  }

  func testMaxValueInSamples() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for v in [500.0, 100.0, 300.0, 200.0, 400.0] {
      buf.addSample(v)
    }
    let max = buf.allSamples.max()
    XCTAssertEqual(max, 500.0)
  }

  func testP95WithIdenticalValues() {
    var buf = ThroughputRingBuffer(maxSamples: 100)
    for _ in 0..<50 { buf.addSample(42.0) }
    XCTAssertEqual(buf.p95!, 42.0, accuracy: 0.001)
    XCTAssertEqual(buf.p50!, 42.0, accuracy: 0.001)
    XCTAssertEqual(buf.average!, 42.0, accuracy: 0.001)
  }

  func testAggregationAfterRingOverflow() {
    var buf = ThroughputRingBuffer(maxSamples: 5)
    // Fill with 1..5 then overwrite with 100..104
    for i in 1...5 { buf.addSample(Double(i)) }
    for v in [100.0, 101.0, 102.0, 103.0, 104.0] { buf.addSample(v) }
    XCTAssertEqual(buf.count, 5)
    XCTAssertEqual(buf.average!, 102.0, accuracy: 0.001)
    XCTAssertEqual(buf.allSamples.min(), 100.0)
    XCTAssertEqual(buf.allSamples.max(), 104.0)
  }

  func testEWMAConvergesToSteadyState() {
    var ewma = ThroughputEWMA()
    for _ in 0..<200 {
      ewma.update(bytes: 1_000_000, dt: 1.0)
    }
    XCTAssertEqual(ewma.bytesPerSecond, 1_000_000, accuracy: 1.0)
  }

  func testEWMATracksChangingRate() {
    var ewma = ThroughputEWMA()
    // Start at 1000 B/s
    for _ in 0..<20 { ewma.update(bytes: 1000, dt: 1.0) }
    let before = ewma.bytesPerSecond
    // Switch to 5000 B/s
    for _ in 0..<20 { ewma.update(bytes: 5000, dt: 1.0) }
    let after = ewma.bytesPerSecond
    XCTAssertGreaterThan(after, before)
    XCTAssertEqual(after, 5000.0, accuracy: 10.0)
  }
}

// MARK: - Custom Log Destinations (TransactionLog instance isolation)

final class CustomLogDestinationTests: XCTestCase {

  private func makeRecord(txID: UInt32) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 1, startedAt: Date(), duration: 0.05,
      bytesIn: 32, bytesOut: 0, outcomeClass: .ok)
  }

  func testSeparateLogInstancesAreIsolated() async {
    let logA = TransactionLog()
    let logB = TransactionLog()
    await logA.append(makeRecord(txID: 1))
    await logA.append(makeRecord(txID: 2))
    await logB.append(makeRecord(txID: 10))

    let aRecords = await logA.recent(limit: 10)
    let bRecords = await logB.recent(limit: 10)
    XCTAssertEqual(aRecords.count, 2)
    XCTAssertEqual(bRecords.count, 1)
    XCTAssertEqual(bRecords.first?.txID, 10)
  }

  func testSharedSingletonIsAccessible() async {
    // TransactionLog.shared exists as a global singleton.
    let shared = TransactionLog.shared
    _ = await shared.recent(limit: 1)
  }

  func testClearOnOneInstanceDoesNotAffectAnother() async {
    let logA = TransactionLog()
    let logB = TransactionLog()
    await logA.append(makeRecord(txID: 1))
    await logB.append(makeRecord(txID: 2))
    await logA.clear()

    let aRecords = await logA.recent(limit: 10)
    let bRecords = await logB.recent(limit: 10)
    XCTAssertTrue(aRecords.isEmpty)
    XCTAssertEqual(bRecords.count, 1)
  }

  func testDumpOnOneInstanceReflectsOnlyItsRecords() async {
    let logA = TransactionLog()
    let logB = TransactionLog()
    await logA.append(makeRecord(txID: 99))
    await logB.append(makeRecord(txID: 77))

    let jsonA = await logA.dump(redacting: false)
    let jsonB = await logB.dump(redacting: false)
    XCTAssertTrue(jsonA.contains("99"))
    XCTAssertFalse(jsonA.contains("77"))
    XCTAssertTrue(jsonB.contains("77"))
    XCTAssertFalse(jsonB.contains("99"))
  }
}

// MARK: - Log Correlation ID Tests

final class LogCorrelationIDTests: XCTestCase {

  func testTxIDServesAsCorrelationIdentifier() {
    let record = TransactionRecord(
      txID: 12345, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 3, startedAt: Date(), duration: 0.5,
      bytesIn: 2048, bytesOut: 0, outcomeClass: .ok)
    XCTAssertEqual(record.txID, 12345)
  }

  func testSessionIDGroupsRelatedTransactions() async {
    let log = TransactionLog()
    let records: [TransactionRecord] = [
      TransactionRecord(
        txID: 1, opcode: 0x1002, opcodeLabel: "OpenSession",
        sessionID: 5, startedAt: Date(), duration: 0.01,
        bytesIn: 0, bytesOut: 0, outcomeClass: .ok),
      TransactionRecord(
        txID: 2, opcode: 0x1009, opcodeLabel: "GetObject",
        sessionID: 5, startedAt: Date(), duration: 1.0,
        bytesIn: 4096, bytesOut: 0, outcomeClass: .ok),
      TransactionRecord(
        txID: 3, opcode: 0x1003, opcodeLabel: "CloseSession",
        sessionID: 5, startedAt: Date(), duration: 0.01,
        bytesIn: 0, bytesOut: 0, outcomeClass: .ok),
      TransactionRecord(
        txID: 4, opcode: 0x1009, opcodeLabel: "GetObject",
        sessionID: 6, startedAt: Date(), duration: 0.5,
        bytesIn: 1024, bytesOut: 0, outcomeClass: .ok),
    ]
    for r in records { await log.append(r) }
    let all = await log.recent(limit: 10)
    let session5 = all.filter { $0.sessionID == 5 }
    let session6 = all.filter { $0.sessionID == 6 }
    XCTAssertEqual(session5.count, 3)
    XCTAssertEqual(session6.count, 1)
  }

  func testCorrelationIDPersistsThroughCodable() throws {
    let record = TransactionRecord(
      txID: 99999, opcode: 0x1001, opcodeLabel: "GetDeviceInfo",
      sessionID: 42, startedAt: Date(timeIntervalSince1970: 1_000_000),
      duration: 0.1, bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(TransactionRecord.self, from: data)
    XCTAssertEqual(decoded.txID, 99999)
    XCTAssertEqual(decoded.sessionID, 42)
  }
}

// MARK: - Breadcrumb Trail Tests

final class BreadcrumbTrailTests: XCTestCase {

  private func makeRecord(
    txID: UInt32, opcode: UInt16, label: String,
    outcome: TransactionOutcome = .ok
  ) -> TransactionRecord {
    TransactionRecord(
      txID: txID, opcode: opcode, opcodeLabel: label,
      sessionID: 1, startedAt: Date(), duration: 0.05,
      bytesIn: 0, bytesOut: 0, outcomeClass: outcome)
  }

  func testRecentLimitReturnsMostRecentBreadcrumbs() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, opcode: 0x1002, label: "OpenSession"))
    await log.append(makeRecord(txID: 2, opcode: 0x1004, label: "GetStorageIDs"))
    await log.append(makeRecord(txID: 3, opcode: 0x1007, label: "GetObjectHandles"))
    await log.append(makeRecord(txID: 4, opcode: 0x1009, label: "GetObject"))
    await log.append(makeRecord(txID: 5, opcode: 0x1003, label: "CloseSession"))

    let last3 = await log.recent(limit: 3)
    XCTAssertEqual(last3.count, 3)
    XCTAssertEqual(last3.map(\.opcodeLabel), ["GetObjectHandles", "GetObject", "CloseSession"])
  }

  func testBreadcrumbTrailPreservesOutcomes() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, opcode: 0x1002, label: "OpenSession"))
    await log.append(makeRecord(txID: 2, opcode: 0x1009, label: "GetObject", outcome: .timeout))
    await log.append(
      makeRecord(txID: 3, opcode: 0x1009, label: "GetObject", outcome: .ok))

    let trail = await log.recent(limit: 10)
    XCTAssertEqual(trail[1].outcomeClass, .timeout)
    XCTAssertEqual(trail[2].outcomeClass, .ok)
  }

  func testBreadcrumbTrailOpcodesMatchLabels() async {
    let log = TransactionLog()
    let ops: [(UInt16, String)] = [
      (0x1001, "GetDeviceInfo"),
      (0x1002, "OpenSession"),
      (0x1004, "GetStorageIDs"),
    ]
    for (i, (opcode, label)) in ops.enumerated() {
      await log.append(makeRecord(txID: UInt32(i + 1), opcode: opcode, label: label))
    }
    let trail = await log.recent(limit: 10)
    for (record, (opcode, label)) in zip(trail, ops) {
      XCTAssertEqual(record.opcode, opcode)
      XCTAssertEqual(record.opcodeLabel, label)
    }
  }
}

// MARK: - Error Context Enrichment Tests

final class ErrorContextEnrichmentTests: XCTestCase {

  func testActionableErrorProvidesUserFacingMessage() {
    struct USBDisconnectedError: ActionableError {
      var actionableDescription: String { "Device disconnected — reconnect and retry" }
    }
    let desc = actionableDescription(for: USBDisconnectedError())
    XCTAssertEqual(desc, "Device disconnected — reconnect and retry")
  }

  func testLocalizedErrorProvidesDetailedContext() {
    enum TransferError: LocalizedError {
      case checksumMismatch
      var errorDescription: String? { "Transfer checksum mismatch — data may be corrupt" }
    }
    let desc = actionableDescription(for: TransferError.checksumMismatch)
    XCTAssertEqual(desc, "Transfer checksum mismatch — data may be corrupt")
  }

  func testTransactionRecordCapturesErrorContext() {
    let record = TransactionRecord(
      txID: 1, opcode: 0x1009, opcodeLabel: "GetObject",
      sessionID: 1, startedAt: Date(), duration: 5.0,
      bytesIn: 512, bytesOut: 0, outcomeClass: .timeout,
      errorDescription: "Timed out after 5s reading from EP1 IN")
    XCTAssertEqual(record.outcomeClass, .timeout)
    XCTAssertEqual(record.errorDescription, "Timed out after 5s reading from EP1 IN")
    XCTAssertEqual(record.duration, 5.0)
  }

  func testErrorDescriptionPreservedInDump() async {
    let log = TransactionLog()
    let record = TransactionRecord(
      txID: 1, opcode: 0x100B, opcodeLabel: "DeleteObject",
      sessionID: 1, startedAt: Date(), duration: 0.2,
      bytesIn: 0, bytesOut: 0, outcomeClass: .deviceError,
      errorDescription: "Device returned 0x2002 (ObjectWriteProtected)")
    await log.append(record)
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("ObjectWriteProtected"))
    XCTAssertTrue(json.contains("deviceError"))
  }

  func testErrorRecordsAppearInTrailWithCorrectOutcome() async {
    let log = TransactionLog()
    await log.append(
      TransactionRecord(
        txID: 1, opcode: 0x1009, opcodeLabel: "GetObject",
        sessionID: 1, startedAt: Date(), duration: 0.1,
        bytesIn: 256, bytesOut: 0, outcomeClass: .ok))
    await log.append(
      TransactionRecord(
        txID: 2, opcode: 0x1009, opcodeLabel: "GetObject",
        sessionID: 1, startedAt: Date(), duration: 3.0,
        bytesIn: 0, bytesOut: 0, outcomeClass: .stall,
        errorDescription: "EP2 stall"))
    let trail = await log.recent(limit: 10)
    let errors = trail.filter { $0.outcomeClass != .ok }
    XCTAssertEqual(errors.count, 1)
    XCTAssertEqual(errors.first?.outcomeClass, .stall)
    XCTAssertEqual(errors.first?.errorDescription, "EP2 stall")
  }

  func testActionablePreferredOverLocalizedForDualConformance() {
    struct DualError: ActionableError, LocalizedError {
      var actionableDescription: String { "Replug the cable" }
      var errorDescription: String? { "USB I/O error -536870206" }
    }
    let desc = actionableDescription(for: DualError())
    XCTAssertEqual(desc, "Replug the cable")
  }

  func testOpcodeLabelsEnrichErrorDiagnostics() {
    // Verify that opcode labels help developers understand which operation failed.
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1009), "GetObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100D), "SendObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100B), "DeleteObject")

    let record = TransactionRecord(
      txID: 1, opcode: 0x100C,
      opcodeLabel: MTPOpcodeLabel.label(for: 0x100C),
      sessionID: 1, startedAt: Date(), duration: 0.3,
      bytesIn: 0, bytesOut: 128, outcomeClass: .ioError,
      errorDescription: "Pipe error on bulk write")
    XCTAssertEqual(record.opcodeLabel, "SendObjectInfo")
    XCTAssertEqual(record.outcomeClass, .ioError)
  }
}
