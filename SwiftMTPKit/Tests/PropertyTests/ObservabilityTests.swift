// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPObservability

final class ObservabilityTests: XCTestCase {

  // MARK: - Helpers

  private func makeRecord(txID: UInt32 = 1, outcome: TransactionOutcome = .ok) -> TransactionRecord
  {
    TransactionRecord(
      txID: txID,
      opcode: 0x1001,
      opcodeLabel: "GetDeviceInfo",
      sessionID: 42,
      startedAt: Date(),
      duration: 0.05,
      bytesIn: 64,
      bytesOut: 16,
      outcomeClass: outcome
    )
  }

  // MARK: - TransactionLog: append + recent

  func testAppendAndRecentRoundTrip() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 1))
    await log.append(makeRecord(txID: 2))
    let records = await log.recent(limit: 10)
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records[0].txID, 1)
    XCTAssertEqual(records[1].txID, 2)
  }

  func testRecentLimitTruncatesOldest() async {
    let log = TransactionLog()
    for i in 0..<10 {
      await log.append(makeRecord(txID: UInt32(i)))
    }
    let records = await log.recent(limit: 5)
    XCTAssertEqual(records.count, 5)
    XCTAssertEqual(records.first?.txID, 5)
    XCTAssertEqual(records.last?.txID, 9)
  }

  // MARK: - TransactionLog: ring buffer cap

  func testRingBufferCapsAt1000() async {
    let log = TransactionLog()
    for i in 0..<1100 {
      await log.append(makeRecord(txID: UInt32(i)))
    }
    let records = await log.recent(limit: 2000)
    XCTAssertEqual(records.count, 1000)
    // After capping, the oldest retained txID should be 100 (1100 - 1000)
    XCTAssertEqual(records.first?.txID, 100)
    XCTAssertEqual(records.last?.txID, 1099)
  }

  // MARK: - TransactionLog: clear

  func testClearEmptiesLog() async {
    let log = TransactionLog()
    await log.append(makeRecord())
    await log.clear()
    let records = await log.recent(limit: 10)
    XCTAssertTrue(records.isEmpty)
  }

  // MARK: - TransactionLog: dump

  func testDumpProducesValidJSON() async {
    let log = TransactionLog()
    await log.append(makeRecord(txID: 7, outcome: .deviceError))
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("\"txID\""))
    XCTAssertTrue(json.contains("deviceError"))
  }

  func testDumpRedactsHexStrings() async {
    let log = TransactionLog()
    let record = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo", sessionID: 1,
      startedAt: Date(), duration: 0.01, bytesIn: 0, bytesOut: 0,
      outcomeClass: .ioError, errorDescription: "Serial: ABCDEF1234567890")
    await log.append(record)
    let json = await log.dump(redacting: true)
    XCTAssertFalse(json.contains("ABCDEF1234567890"))
    XCTAssertTrue(json.contains("<redacted>"))
  }

  func testDumpWithoutRedactionPreservesData() async {
    let log = TransactionLog()
    let record = TransactionRecord(
      txID: 1, opcode: 0x1001, opcodeLabel: "GetDeviceInfo", sessionID: 1,
      startedAt: Date(), duration: 0.01, bytesIn: 0, bytesOut: 0,
      outcomeClass: .ioError, errorDescription: "Serial: ABCDEF1234567890")
    await log.append(record)
    let json = await log.dump(redacting: false)
    XCTAssertTrue(json.contains("ABCDEF1234567890"))
  }

  // MARK: - actionableDescription

  func testActionableDescriptionBusy() {
    let desc = actionableDescription(for: MTPError.busy)
    XCTAssertTrue(
      desc.contains("File Transfer") || desc.contains("charging mode"),
      "Unexpected busy description: \(desc)")
  }

  func testActionableDescriptionAccessDenied() {
    let desc = actionableDescription(for: TransportError.accessDenied)
    XCTAssertTrue(
      desc.lowercased().contains("usb") || desc.lowercased().contains("access"),
      "Unexpected accessDenied description: \(desc)")
  }

  func testActionableDescriptionWriteProtected() {
    let desc = actionableDescription(for: MTPError.objectWriteProtected)
    XCTAssertTrue(
      desc.lowercased().contains("write-protected") || desc.lowercased().contains("protected"),
      "Unexpected write-protected description: \(desc)")
  }

  func testActionableDescriptionTransportInMTPError() {
    let wrapped = MTPError.transport(.accessDenied)
    let desc = actionableDescription(for: wrapped)
    XCTAssertTrue(
      desc.lowercased().contains("usb") || desc.lowercased().contains("access"),
      "Unexpected transport-wrapped description: \(desc)")
  }

  func testActionableDescriptionFallback() {
    struct UnknownError: Error, CustomStringConvertible {
      var description: String { "unknown" }
    }
    let desc = actionableDescription(for: UnknownError())
    XCTAssertFalse(desc.isEmpty)
  }

  // MARK: - MTPOpcodeLabel

  func testOpcodeLabelKnownCodes() {
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1001), "GetDeviceInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1002), "OpenSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1003), "CloseSession")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x1007), "GetObjectHandles")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100C), "SendObjectInfo")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100D), "SendObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x100B), "DeleteObject")
    XCTAssertEqual(MTPOpcodeLabel.label(for: 0x95C4), "GetPartialObject64")
  }

  func testOpcodeLabelUnknownCode() {
    let label = MTPOpcodeLabel.label(for: 0xDEAD)
    XCTAssertTrue(
      label.contains("Unknown") || label.contains("unknown"),
      "Expected unknown label, got: \(label)")
    XCTAssertTrue(
      label.uppercased().contains("DEAD"),
      "Expected opcode in label, got: \(label)")
  }
}
