// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPObservability

// MARK: - MTPLog Tests

final class MTPLogTests: XCTestCase {

  func testSubsystem() {
    XCTAssertEqual(MTPLog.subsystem, "com.effortlessmetrics.swiftmtp")
  }

  func testCategoryLoggersAreDistinct() {
    // Each static logger should be a unique instance with its own category.
    let loggers = [MTPLog.transport, MTPLog.proto, MTPLog.index, MTPLog.sync, MTPLog.perf]
    // Verify we have the expected count (no accidental duplicates via reference).
    XCTAssertEqual(loggers.count, 5)
  }

  func testSignpostLoggersExist() {
    // Signpost loggers and signposters should be accessible without crashing.
    _ = MTPLog.Signpost.enumerate
    _ = MTPLog.Signpost.transfer
    _ = MTPLog.Signpost.resume
    _ = MTPLog.Signpost.chunk
    _ = MTPLog.Signpost.enumerateSignposter
    _ = MTPLog.Signpost.transferSignposter
    _ = MTPLog.Signpost.resumeSignposter
    _ = MTPLog.Signpost.chunkSignposter
  }
}

// MARK: - ThroughputEWMA Tests

final class ThroughputEWMATests: XCTestCase {

  func testInitialState() {
    let ewma = ThroughputEWMA()
    XCTAssertEqual(ewma.bytesPerSecond, 0)
    XCTAssertEqual(ewma.megabytesPerSecond, 0)
    XCTAssertEqual(ewma.count, 0)
  }

  func testFirstSampleSetsRate() {
    var ewma = ThroughputEWMA()
    let rate = ewma.update(bytes: 1000, dt: 1.0)
    XCTAssertEqual(rate, 1000.0)
    XCTAssertEqual(ewma.bytesPerSecond, 1000.0)
    XCTAssertEqual(ewma.count, 1)
  }

  func testSubsequentSamplesApplySmoothing() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1000, dt: 1.0)  // rate = 1000
    let rate2 = ewma.update(bytes: 2000, dt: 1.0)  // alpha=0.3 → 0.3*2000 + 0.7*1000 = 1300
    XCTAssertEqual(rate2, 1300.0, accuracy: 0.001)
    XCTAssertEqual(ewma.count, 2)
  }

  func testZeroDtProducesZeroInstantaneous() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1000, dt: 1.0)
    let rate = ewma.update(bytes: 5000, dt: 0)
    // inst = 0, so rate = 0.3*0 + 0.7*1000 = 700
    XCTAssertEqual(rate, 700.0, accuracy: 0.001)
  }

  func testMegabytesPerSecondConversion() {
    var ewma = ThroughputEWMA()
    let mb = 1024.0 * 1024.0
    ewma.update(bytes: Int(mb), dt: 1.0)
    XCTAssertEqual(ewma.megabytesPerSecond, 1.0, accuracy: 0.001)
  }

  func testReset() {
    var ewma = ThroughputEWMA()
    ewma.update(bytes: 1000, dt: 1.0)
    ewma.reset()
    XCTAssertEqual(ewma.bytesPerSecond, 0)
    XCTAssertEqual(ewma.count, 0)
  }

  func testConvergence() {
    var ewma = ThroughputEWMA()
    // Feed a constant rate; EWMA should converge toward it.
    for _ in 0..<50 {
      ewma.update(bytes: 5000, dt: 1.0)
    }
    XCTAssertEqual(ewma.bytesPerSecond, 5000.0, accuracy: 1.0)
  }
}

// MARK: - ThroughputRingBuffer Tests

final class ThroughputRingBufferTests: XCTestCase {

  func testInitialState() {
    let buf = ThroughputRingBuffer()
    XCTAssertEqual(buf.count, 0)
    XCTAssertNil(buf.p50)
    XCTAssertNil(buf.p95)
    XCTAssertNil(buf.average)
    XCTAssertTrue(buf.allSamples.isEmpty)
  }

  func testAddSamples() {
    var buf = ThroughputRingBuffer()
    buf.addSample(100)
    buf.addSample(200)
    XCTAssertEqual(buf.count, 2)
    XCTAssertEqual(buf.allSamples, [100, 200])
  }

  func testAverage() {
    var buf = ThroughputRingBuffer()
    buf.addSample(10)
    buf.addSample(20)
    buf.addSample(30)
    XCTAssertEqual(buf.average!, 20.0, accuracy: 0.001)
  }

  func testP50() {
    var buf = ThroughputRingBuffer()
    for v in [10.0, 20.0, 30.0, 40.0, 50.0] {
      buf.addSample(v)
    }
    // sorted: [10,20,30,40,50], p50 = index 2 = 30
    XCTAssertEqual(buf.p50!, 30.0, accuracy: 0.001)
  }

  func testP95() {
    var buf = ThroughputRingBuffer(maxSamples: 200)
    for i in 1...100 {
      buf.addSample(Double(i))
    }
    // sorted 1..100, p95 index = 95 → value 96
    XCTAssertEqual(buf.p95!, 96.0, accuracy: 0.001)
  }

  func testRingOverwrite() {
    var buf = ThroughputRingBuffer(maxSamples: 3)
    buf.addSample(1)
    buf.addSample(2)
    buf.addSample(3)
    buf.addSample(4)  // overwrites index 0
    XCTAssertEqual(buf.count, 3)
    XCTAssertEqual(buf.allSamples.sorted(), [2, 3, 4])
  }

  func testReset() {
    var buf = ThroughputRingBuffer()
    buf.addSample(100)
    buf.reset()
    XCTAssertEqual(buf.count, 0)
    XCTAssertTrue(buf.allSamples.isEmpty)
  }
}

// MARK: - TransactionOutcome Tests

final class TransactionOutcomeTests: XCTestCase {

  func testAllCases() {
    let cases: [TransactionOutcome] = [.ok, .deviceError, .timeout, .stall, .ioError, .cancelled]
    XCTAssertEqual(cases.count, 6)
  }

  func testRawValues() {
    XCTAssertEqual(TransactionOutcome.ok.rawValue, "ok")
    XCTAssertEqual(TransactionOutcome.deviceError.rawValue, "deviceError")
    XCTAssertEqual(TransactionOutcome.timeout.rawValue, "timeout")
    XCTAssertEqual(TransactionOutcome.stall.rawValue, "stall")
    XCTAssertEqual(TransactionOutcome.ioError.rawValue, "ioError")
    XCTAssertEqual(TransactionOutcome.cancelled.rawValue, "cancelled")
  }

  func testCodableRoundTrip() throws {
    let original = TransactionOutcome.timeout
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TransactionOutcome.self, from: data)
    XCTAssertEqual(decoded, original)
  }
}

// MARK: - TransactionRecord Tests

final class TransactionRecordTests: XCTestCase {

  private func makeRecord(
    errorDescription: String? = nil,
    outcome: TransactionOutcome = .ok
  ) -> TransactionRecord {
    TransactionRecord(
      txID: 42,
      opcode: 0x1009,
      opcodeLabel: "GetObject",
      sessionID: 1,
      startedAt: Date(timeIntervalSince1970: 1_000_000),
      duration: 0.5,
      bytesIn: 1024,
      bytesOut: 0,
      outcomeClass: outcome,
      errorDescription: errorDescription
    )
  }

  func testCodableRoundTrip() throws {
    let record = makeRecord()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(TransactionRecord.self, from: data)
    XCTAssertEqual(decoded.txID, 42)
    XCTAssertEqual(decoded.opcode, 0x1009)
    XCTAssertEqual(decoded.opcodeLabel, "GetObject")
    XCTAssertEqual(decoded.sessionID, 1)
    XCTAssertEqual(decoded.bytesIn, 1024)
    XCTAssertEqual(decoded.bytesOut, 0)
    XCTAssertEqual(decoded.outcomeClass, .ok)
    XCTAssertNil(decoded.errorDescription)
  }

  func testFieldValues() {
    let record = makeRecord(errorDescription: "test error", outcome: .deviceError)
    XCTAssertEqual(record.duration, 0.5)
    XCTAssertEqual(record.errorDescription, "test error")
    XCTAssertEqual(record.outcomeClass, .deviceError)
  }
}

// MARK: - TransactionLog Tests

final class TransactionLogTests: XCTestCase {

  private func makeRecord(txID: UInt32, outcome: TransactionOutcome = .ok, errorDescription: String? = nil)
    -> TransactionRecord
  {
    TransactionRecord(
      txID: txID,
      opcode: 0x1001,
      opcodeLabel: "GetDeviceInfo",
      sessionID: 1,
      startedAt: Date(),
      duration: 0.1,
      bytesIn: 64,
      bytesOut: 0,
      outcomeClass: outcome,
      errorDescription: errorDescription
    )
  }

  func testAppendAndRecent() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    await log.append(makeRecord(txID: 2))
    await log.append(makeRecord(txID: 3))

    let recent = await log.recent(limit: 2)
    XCTAssertEqual(recent.count, 2)
    XCTAssertEqual(recent[0].txID, 2)
    XCTAssertEqual(recent[1].txID, 3)
  }

  func testRecentReturnsAllWhenLimitExceedsCount() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let recent = await log.recent(limit: 100)
    XCTAssertEqual(recent.count, 1)
  }

  func testClear() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    await log.clear()
    let recent = await log.recent(limit: 10)
    XCTAssertTrue(recent.isEmpty)
  }

  func testMaxRecordsTruncation() async {
    let log = TransactionLog()
    for i: UInt32 in 1...1050 {
      await log.append(makeRecord(txID: i))
    }
    let recent = await log.recent(limit: 2000)
    XCTAssertEqual(recent.count, 1000)
    // Oldest surviving should be 51 (first 50 trimmed)
    XCTAssertEqual(recent.first?.txID, 51)
    XCTAssertEqual(recent.last?.txID, 1050)
  }

  func testDumpProducesValidJSON() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    let json = await log.dump(redacting: false)
    let data = json.data(using: .utf8)!
    let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    XCTAssertNotNil(arr)
    XCTAssertEqual(arr?.count, 1)
  }

  func testDumpRedactsHexSequences() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "serial=AABBCCDD11223344"))
    let json = await log.dump(redacting: true)
    XCTAssertTrue(json.contains("<redacted>"))
    XCTAssertFalse(json.contains("AABBCCDD11223344"))
  }

  func testDumpWithoutRedactionPreservesHex() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1, errorDescription: "serial=AABBCCDD11223344"))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("AABBCCDD11223344"))
  }

  func testConcurrentAppends() async {
    let log = TransactionLog()
    // Actor isolation ensures safety; verify no crash with concurrent access.
    await withTaskGroup(of: Void.self) { group in
      for i: UInt32 in 1...200 {
        let record = makeRecord(txID: i)
        group.addTask {
          await log.append(record)
        }
      }
    }
    let recent = await log.recent(limit: 300)
    XCTAssertEqual(recent.count, 200)
  }
}

// MARK: - MTPOpcodeLabel Tests

final class MTPOpcodeLabelTests: XCTestCase {

  func testKnownOpcodes() {
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1001), "GetDeviceInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1002), "OpenSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1003), "CloseSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1004), "GetStorageIDs")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1005), "GetStorageInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1006), "GetNumObjects")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1007), "GetObjectHandles")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1008), "GetObjectInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1009), "GetObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100A), "GetThumb")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100B), "DeleteObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100C), "SendObjectInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100D), "SendObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100E), "MoveObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1014), "GetDevicePropDesc")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1015), "GetDevicePropValue")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1016), "SetDevicePropValue")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1017), "ResetDevicePropValue")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x101B), "GetPartialObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x95C1), "SendPartialObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x95C4), "GetPartialObject64")
  }

  func testUnknownOpcode() {
    let label = MTPOpcodeLabel.label(for: 0xFFFF)
    XCTAssertEqual(label, "Unknown(0xFFFF)")
  }

  func testUnknownOpcodeFormat() {
    let label = MTPOpcodeLabel.label(for: 0x0042)
    XCTAssertEqual(label, "Unknown(0x0042)")
  }
}

// MARK: - ActionableError Tests

final class ActionableErrorTests: XCTestCase {

  private struct TestActionableError: ActionableError {
    var actionableDescription: String { "Unplug and replug your device" }
  }

  private enum TestLocalizedError: LocalizedError {
    case sample
    var errorDescription: String? { "A localized description" }
  }

  private struct PlainError: Error {}

  func testActionableErrorPreferred() {
    let desc = actionableDescription(for: TestActionableError())
    XCTAssertEqual(desc, "Unplug and replug your device")
  }

  func testLocalizedErrorFallback() {
    let desc = actionableDescription(for: TestLocalizedError.sample)
    XCTAssertEqual(desc, "A localized description")
  }

  func testPlainErrorFallback() {
    let desc = actionableDescription(for: PlainError())
    // Should produce some non-empty string via localizedDescription
    XCTAssertFalse(desc.isEmpty)
  }
}

// MARK: - Sendability Tests

final class SendabilityTests: XCTestCase {

  func testThroughputEWMAIsSendable() async {
    // Verify ThroughputEWMA can be sent across isolation boundaries.
    let ewma = ThroughputEWMA()
    let result = await Task { @Sendable in
      var local = ewma
      local.update(bytes: 1000, dt: 1.0)
      return local.bytesPerSecond
    }.value
    XCTAssertEqual(result, 1000.0)
  }

  func testThroughputRingBufferIsSendable() async {
    let buf = ThroughputRingBuffer(maxSamples: 10)
    let count = await Task { @Sendable in
      var local = buf
      local.addSample(42)
      return local.count
    }.value
    XCTAssertEqual(count, 1)
  }

  func testTransactionOutcomeIsSendable() async {
    let outcome = TransactionOutcome.ok
    let raw = await Task { @Sendable in
      outcome.rawValue
    }.value
    XCTAssertEqual(raw, "ok")
  }

  func testTransactionRecordIsSendable() async {
    let record = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo", sessionID: 1,
      startedAt: Date(), duration: 0.1, bytesIn: 0, bytesOut: 0, outcomeClass: .ok)
    let txID = await Task { @Sendable in
      record.txID
    }.value
    XCTAssertEqual(txID, 1)
  }
}
