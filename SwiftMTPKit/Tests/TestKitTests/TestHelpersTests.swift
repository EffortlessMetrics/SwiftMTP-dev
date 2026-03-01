// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class TestHelpersTests: XCTestCase {

  // MARK: - TestUtilities

  func testCreateAndCleanupTempDirectory() throws {
    let dir = try TestUtilities.createTempDirectory(prefix: "test-cleanup")
    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    try TestUtilities.cleanupTempDirectory(dir)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
  }

  func testCreateTempFileWithContent() throws {
    let dir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let content = Data("hello world".utf8)
    let fileURL = try TestUtilities.createTempFile(
      directory: dir, filename: "test.txt", content: content)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    XCTAssertEqual(try Data(contentsOf: fileURL), content)
  }

  func testCreateTempFileWithSize() throws {
    let dir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }

    let fileURL = try TestUtilities.createTempFile(
      directory: dir, filename: "random.bin", size: 256)
    let data = try Data(contentsOf: fileURL)
    XCTAssertEqual(data.count, 256)
  }

  // MARK: - TestFixtures

  func testSmallFixtureSize() {
    let small = TestFixtures.smallFile()
    XCTAssertEqual(small.count, 1024)
  }

  func testMediumFixtureSize() {
    let medium = TestFixtures.mediumFile()
    XCTAssertEqual(medium.count, 1_048_576)
  }

  func testTextFixtureContent() {
    let text = TestFixtures.textContent()
    XCTAssertFalse(text.isEmpty)
    XCTAssertTrue(text.contains("SwiftMTP"))
  }

  // MARK: - MockDeviceData

  func testMockDeviceDataPixel7() {
    let pixel = MockDeviceData.pixel7
    XCTAssertEqual(pixel.deviceSummary.manufacturer, "Google")
    XCTAssertEqual(pixel.deviceSummary.model, "Pixel 7")
    XCTAssertFalse(pixel.storageInfo.isEmpty)
    XCTAssertFalse(pixel.operationsSupported.isEmpty)
  }

  func testMockDeviceDataOnePlus3T() {
    let oneplus = MockDeviceData.onePlus3T
    XCTAssertEqual(oneplus.deviceSummary.manufacturer, "OnePlus")
    XCTAssertEqual(oneplus.deviceSummary.model, "ONEPLUS A3010")
    XCTAssertFalse(oneplus.storageInfo.isEmpty)
  }

  // MARK: - OperationRecord

  func testOperationRecordInit() {
    let record = OperationRecord(operation: "test", parameters: ["key": "value"])
    XCTAssertEqual(record.operation, "test")
    XCTAssertEqual(record.parameters["key"], "value")
    XCTAssertTrue(record.timestamp.timeIntervalSinceNow > -10)
  }

  func testOperationRecordDefaultParameters() {
    let record = OperationRecord(operation: "simple")
    XCTAssertEqual(record.operation, "simple")
    XCTAssertTrue(record.parameters.isEmpty)
  }

  // MARK: - TranscriptEntry / TranscriptData

  func testTranscriptEntryInit() {
    let entry = TranscriptEntry(
      operation: "getDeviceInfo",
      response: TranscriptData(code: 0x2001, params: [1, 2], dataSize: 42))
    XCTAssertEqual(entry.operation, "getDeviceInfo")
    XCTAssertNil(entry.error)
    XCTAssertEqual(entry.response?.code, 0x2001)
    XCTAssertEqual(entry.response?.params, [1, 2])
    XCTAssertEqual(entry.response?.dataSize, 42)
  }

  func testTranscriptEntryWithError() {
    let entry = TranscriptEntry(operation: "openSession", error: "timeout occurred")
    XCTAssertEqual(entry.error, "timeout occurred")
    XCTAssertNil(entry.response)
  }

  func testTranscriptDataMinimal() {
    let data = TranscriptData()
    XCTAssertNil(data.code)
    XCTAssertNil(data.params)
    XCTAssertNil(data.dataSize)
  }

  // MARK: - RecordedPacket

  func testRecordedPacketInit() {
    let packet = RecordedPacket(
      direction: "in", data: Data([0x01, 0x02]), timestampMs: 123.456)
    XCTAssertEqual(packet.direction, "in")
    XCTAssertEqual(packet.data.count, 2)
    XCTAssertEqual(packet.timestampMs, 123.456)
    XCTAssertNil(packet.errorCode)
  }

  func testRecordedPacketWithError() {
    let packet = RecordedPacket(
      direction: "in", data: Data(), timestampMs: 0, errorCode: 5)
    XCTAssertEqual(packet.errorCode, 5)
  }
}
