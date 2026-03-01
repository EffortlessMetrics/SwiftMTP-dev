// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class RecordedTransportTests: XCTestCase {

  // MARK: - Helpers

  private func makeResponsePacket(code: UInt16 = 0x2001, txid: UInt32 = 1) -> Data {
    var data = Data(count: 12)
    data.withUnsafeMutableBytes { ptr in
      let p = ptr.baseAddress!
      var len: UInt32 = 12
      memcpy(p, &len, 4)
      var t: UInt16 = 3
      memcpy(p.advanced(by: 4), &t, 2)
      var c = code
      memcpy(p.advanced(by: 6), &c, 2)
      var x = txid
      memcpy(p.advanced(by: 8), &x, 4)
    }
    return data
  }

  private func makeDataPacket(code: UInt16, txid: UInt32, payload: Data) -> Data {
    var header = Data(count: 12)
    let totalLen = UInt32(12 + payload.count)
    header.withUnsafeMutableBytes { ptr in
      let p = ptr.baseAddress!
      var l = totalLen
      memcpy(p, &l, 4)
      var t: UInt16 = 2
      memcpy(p.advanced(by: 4), &t, 2)
      var c = code
      memcpy(p.advanced(by: 6), &c, 2)
      var x = txid
      memcpy(p.advanced(by: 8), &x, 4)
    }
    return header + payload
  }

  // MARK: - Exhaustion

  func testReplayExhaustionThrows() async throws {
    let link = RecordedMTPLink(packets: [])
    link.exhaustedThrows = true

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected exhaustion error")
    } catch {
      XCTAssertTrue("\(error)".contains("exhausted"))
    }
  }

  func testReplayExhaustionDefaultSucceeds() async throws {
    let link = RecordedMTPLink(packets: [])
    // Default exhaustedThrows = false → returns OK
    try await link.openSession(id: 1)
  }

  // MARK: - Captured Writes

  func testCapturedWritesCollectOutPackets() async throws {
    let outData = Data([0x01, 0x02, 0x03])
    let packets = [
      RecordedPacket(direction: "out", data: outData, timestampMs: 0),
      RecordedPacket(direction: "in", data: makeResponsePacket(), timestampMs: 1),
    ]
    let link = RecordedMTPLink(packets: packets)
    try await link.openSession(id: 1)
    XCTAssertEqual(link.capturedWrites, [outData])
  }

  // MARK: - Error Replay

  func testRecordedPacketErrorCodeThrows() async throws {
    let packets = [
      RecordedPacket(direction: "in", data: Data(), timestampMs: 0, errorCode: 42)
    ]
    let link = RecordedMTPLink(packets: packets)
    link.exhaustedThrows = true

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected recorded error")
    } catch {
      XCTAssertTrue("\(error)".contains("Recorded error code: 42"))
    }
  }

  // MARK: - Data Parsing

  func testGetStorageIDsParsesPayload() async throws {
    var payload = Data(count: 12)
    payload.withUnsafeMutableBytes { ptr in
      let p = ptr.baseAddress!
      var count: UInt32 = 2
      memcpy(p, &count, 4)
      var id1: UInt32 = 0x0001_0001
      memcpy(p.advanced(by: 4), &id1, 4)
      var id2: UInt32 = 0x0002_0001
      memcpy(p.advanced(by: 8), &id2, 4)
    }
    let dataPacket = makeDataPacket(code: 0x1004, txid: 1, payload: payload)
    let responsePacket = makeResponsePacket(code: 0x2001, txid: 1)

    let link = RecordedMTPLink(packets: [
      RecordedPacket(direction: "in", data: dataPacket, timestampMs: 0),
      RecordedPacket(direction: "in", data: responsePacket, timestampMs: 1),
    ])

    let ids = try await link.getStorageIDs()
    XCTAssertEqual(ids.count, 2)
    XCTAssertEqual(ids[0].raw, 0x0001_0001)
    XCTAssertEqual(ids[1].raw, 0x0002_0001)
  }

  func testExecuteCommandParsesResponse() async throws {
    let responsePacket = makeResponsePacket(code: 0x2001, txid: 42)
    let link = RecordedMTPLink(packets: [
      RecordedPacket(direction: "in", data: responsePacket, timestampMs: 0)
    ])

    let result = try await link.executeCommand(
      PTPContainer(type: 1, code: 0x1001, txid: 42, params: []))
    XCTAssertEqual(result.code, 0x2001)
    XCTAssertEqual(result.txid, 42)
  }

  // MARK: - Session

  func testOpenAndCloseSession() async throws {
    let link = RecordedMTPLink(packets: [
      RecordedPacket(direction: "in", data: makeResponsePacket(txid: 1), timestampMs: 0),
      RecordedPacket(direction: "in", data: makeResponsePacket(txid: 2), timestampMs: 1),
    ])
    try await link.openSession(id: 1)
    try await link.closeSession()
  }

  func testProtocolErrorResponse() async throws {
    let errorResp = makeResponsePacket(code: 0x2019, txid: 1)
    let link = RecordedMTPLink(packets: [
      RecordedPacket(direction: "in", data: errorResp, timestampMs: 0)
    ])

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected protocol error")
    } catch {
      // Non-0x2001 response code should throw
      XCTAssertFalse("\(error)".isEmpty)
    }
  }

  func testCachedDeviceInfoIsNil() {
    let link = RecordedMTPLink(packets: [])
    XCTAssertNil(link.cachedDeviceInfo)
  }
}
