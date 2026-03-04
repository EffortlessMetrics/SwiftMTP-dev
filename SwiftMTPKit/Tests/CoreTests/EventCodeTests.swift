// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests for MTPEvent parsing, event codes, descriptions, and parameter extraction.
final class EventCodeTests: XCTestCase {

  // MARK: - Helpers

  /// Build a raw PTP event container: [len(4-LE) type(2-LE)=0x0004 code(2-LE) txid(4-LE) params...]
  private func makeEventData(code: UInt16, txid: UInt32 = 0, params: [UInt32] = []) -> Data {
    let length = UInt32(12 + params.count * 4)
    var data = Data()
    data.append(contentsOf: withUnsafeBytes(of: length.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian) { Array($0) })  // event type
    data.append(contentsOf: withUnsafeBytes(of: code.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: txid.littleEndian) { Array($0) })
    for p in params {
      data.append(contentsOf: withUnsafeBytes(of: p.littleEndian) { Array($0) })
    }
    return data
  }

  // MARK: - All 14 Standard Event Codes

  func testCancelTransactionEvent() {
    let data = makeEventData(code: 0x4001, params: [42])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4001)
    if case .cancelTransaction(let txId) = event {
      XCTAssertEqual(txId, 42)
    } else {
      XCTFail("Expected cancelTransaction")
    }
  }

  func testObjectAddedEvent() {
    let data = makeEventData(code: 0x4002, params: [0x100])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4002)
    if case .objectAdded(let handle) = event {
      XCTAssertEqual(handle, 0x100)
    } else {
      XCTFail("Expected objectAdded")
    }
  }

  func testObjectRemovedEvent() {
    let data = makeEventData(code: 0x4003, params: [0x200])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4003)
    if case .objectRemoved(let handle) = event {
      XCTAssertEqual(handle, 0x200)
    } else {
      XCTFail("Expected objectRemoved")
    }
  }

  func testStorageAddedEvent() {
    let data = makeEventData(code: 0x4004, params: [0x00010001])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4004)
    if case .storageAdded(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storageAdded")
    }
  }

  func testStorageRemovedEvent() {
    let data = makeEventData(code: 0x4005, params: [0x00010001])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4005)
    if case .storageRemoved(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storageRemoved")
    }
  }

  func testDevicePropChangedEvent() {
    let data = makeEventData(code: 0x4006, params: [0x5001])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4006)
    if case .devicePropChanged(let prop) = event {
      XCTAssertEqual(prop, 0x5001)
    } else {
      XCTFail("Expected devicePropChanged")
    }
  }

  func testObjectInfoChangedEvent() {
    let data = makeEventData(code: 0x4007, params: [0x300])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4007)
    if case .objectInfoChanged(let handle) = event {
      XCTAssertEqual(handle, 0x300)
    } else {
      XCTFail("Expected objectInfoChanged")
    }
  }

  func testDeviceInfoChangedEvent() {
    let data = makeEventData(code: 0x4008)
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4008)
    if case .deviceInfoChanged = event {} else {
      XCTFail("Expected deviceInfoChanged")
    }
  }

  func testRequestObjectTransferEvent() {
    let data = makeEventData(code: 0x4009, params: [0x400])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x4009)
    if case .requestObjectTransfer(let handle) = event {
      XCTAssertEqual(handle, 0x400)
    } else {
      XCTFail("Expected requestObjectTransfer")
    }
  }

  func testStoreFullEvent() {
    let data = makeEventData(code: 0x400A, params: [0x00010001])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x400A)
    if case .storeFull(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00010001)
    } else {
      XCTFail("Expected storeFull")
    }
  }

  func testDeviceResetEvent() {
    let data = makeEventData(code: 0x400B)
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x400B)
    if case .deviceReset = event {} else {
      XCTFail("Expected deviceReset")
    }
  }

  func testStorageInfoChangedEvent() {
    let data = makeEventData(code: 0x400C, params: [0x00020001])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x400C)
    if case .storageInfoChanged(let sid) = event {
      XCTAssertEqual(sid.raw, 0x00020001)
    } else {
      XCTFail("Expected storageInfoChanged")
    }
  }

  func testCaptureCompleteEvent() {
    let data = makeEventData(code: 0x400D, params: [99])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x400D)
    if case .captureComplete(let txId) = event {
      XCTAssertEqual(txId, 99)
    } else {
      XCTFail("Expected captureComplete")
    }
  }

  func testUnreportedStatusEvent() {
    let data = makeEventData(code: 0x400E)
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0x400E)
    if case .unreportedStatus = event {} else {
      XCTFail("Expected unreportedStatus")
    }
  }

  // MARK: - Unknown Event Codes

  func testUnknownEventPreservesRawCode() {
    let data = makeEventData(code: 0xC001, params: [1, 2, 3])
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    XCTAssertEqual(event.eventCode, 0xC001)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xC001)
      XCTAssertEqual(params, [1, 2, 3])
    } else {
      XCTFail("Expected unknown event")
    }
  }

  func testUnknownEventWithNoParams() {
    let data = makeEventData(code: 0xC999)
    guard let event = MTPEvent.fromRaw(data) else { return XCTFail("Failed to parse") }
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xC999)
      XCTAssertTrue(params.isEmpty)
    } else {
      XCTFail("Expected unknown event")
    }
  }

  // MARK: - Event Description

  func testEventDescriptionContainsReadableText() {
    let cases: [(MTPEvent, String)] = [
      (.cancelTransaction(transactionId: 1), "CancelTransaction"),
      (.objectAdded(0x10), "ObjectAdded"),
      (.objectRemoved(0x20), "ObjectRemoved"),
      (.storageAdded(MTPStorageID(raw: 1)), "StoreAdded"),
      (.storageRemoved(MTPStorageID(raw: 1)), "StoreRemoved"),
      (.devicePropChanged(propertyCode: 0x5001), "DevicePropChanged"),
      (.objectInfoChanged(0x30), "ObjectInfoChanged"),
      (.deviceInfoChanged, "DeviceInfoChanged"),
      (.requestObjectTransfer(0x40), "RequestObjectTransfer"),
      (.storeFull(MTPStorageID(raw: 1)), "StoreFull"),
      (.deviceReset, "DeviceReset"),
      (.storageInfoChanged(MTPStorageID(raw: 1)), "StorageInfoChanged"),
      (.captureComplete(transactionId: 5), "CaptureComplete"),
      (.unreportedStatus, "UnreportedStatus"),
      (.unknown(code: 0xBEEF, params: []), "Unknown"),
    ]
    for (event, expectedSubstring) in cases {
      XCTAssertTrue(
        event.eventDescription.contains(expectedSubstring),
        "\(event.eventDescription) should contain \(expectedSubstring)")
    }
  }

  // MARK: - Edge Cases

  func testTooShortDataReturnsNil() {
    let shortData = Data([0x08, 0x00, 0x00, 0x00, 0x04, 0x00])  // only 6 bytes
    XCTAssertNil(MTPEvent.fromRaw(shortData))
  }

  func testMinimalValidContainer() {
    // 12 bytes: length(4) + type(2) + code(2) + txid(4), no params
    let data = makeEventData(code: 0x400B)
    XCTAssertNotNil(MTPEvent.fromRaw(data))
  }

  func testObjectAddedRequiresParam() {
    // ObjectAdded (0x4002) requires a handle param — no params means nil
    let data = makeEventData(code: 0x4002)
    XCTAssertNil(MTPEvent.fromRaw(data))
  }
}
