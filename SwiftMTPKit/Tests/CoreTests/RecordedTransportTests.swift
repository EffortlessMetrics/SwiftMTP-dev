// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

final class RecordedTransportTests: XCTestCase {

  // MARK: - Helpers

  private func loadFixture(named name: String) throws -> [RecordedPacket] {
    let fixtureURL =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
    let data = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    return try decoder.decode([RecordedPacket].self, from: data)
  }

  // MARK: - Tests

  func testReplayProbePixel7() async throws {
    let packets = try loadFixture(named: "probe-pixel7.json")
    let link = RecordedMTPLink(packets: packets)

    try await link.openSession(id: 1)
    let info = try await PTPLayer.getDeviceInfo(on: link)
    try await link.closeSession()

    XCTAssert(info.model.contains("Pixel"), "Expected model to contain 'Pixel', got '\(info.model)'")
    XCTAssertEqual(info.manufacturer, "Google")
  }

  func testReplayBusyResponse() async throws {
    let packets = try loadFixture(named: "probe-canary.json")
    let link = RecordedMTPLink(packets: packets)

    try await link.openSession(id: 1)

    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected getDeviceInfo to throw on busy response")
    } catch let error as MTPError {
      switch error {
      case .protocolError(let code, _):
        XCTAssertEqual(code, 0x2019, "Expected DeviceBusy (0x2019), got 0x\(String(code, radix: 16))")
      default:
        XCTFail("Expected .protocolError, got \(error)")
      }
    }
  }

  func testCapturedWritesRecorded() async throws {
    let packets = try loadFixture(named: "probe-pixel7.json")
    let link = RecordedMTPLink(packets: packets)

    try await link.openSession(id: 1)

    let writes = link.capturedWrites
    XCTAssertFalse(writes.isEmpty, "Expected capturedWrites to be non-empty after openSession")

    // OpenSession command container: length=16 (type=1, code=0x1002, txid=1, param=1)
    let openSessionBytes = writes[0]
    XCTAssertEqual(openSessionBytes.count, 16)
    // type byte at offset 4 should be 1 (command)
    XCTAssertEqual(openSessionBytes[4], 0x01)
    // code bytes at offset 6-7 should be 0x1002 (little-endian)
    XCTAssertEqual(openSessionBytes[6], 0x02)
    XCTAssertEqual(openSessionBytes[7], 0x10)
  }
}
