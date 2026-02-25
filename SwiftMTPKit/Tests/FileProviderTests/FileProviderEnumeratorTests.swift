// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import FileProvider

final class FileProviderEnumeratorTests: XCTestCase {

  private actor MockLiveIndexReader: LiveIndexReader {
    var changeCounter: Int64 = 0

    func setChangeCounter(_ value: Int64) {
      changeCounter = value
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? { nil }
    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    { [] }
    func storages(deviceId: String) async throws -> [IndexedStorage] { [] }
    func currentChangeCounter(deviceId: String) async throws -> Int64 { changeCounter }
    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] { [] }
    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    { nil }
  }

  func testEnumeratorCreationForDeviceRoot() {
    let enumerator = DomainEnumerator(
      deviceId: "device1",
      storageId: nil,
      parentHandle: nil,
      indexReader: nil
    )

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorCreationForStorage() {
    let enumerator = DomainEnumerator(
      deviceId: "device1",
      storageId: 1,
      parentHandle: nil,
      indexReader: nil
    )

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorCreationForNestedFolder() {
    let enumerator = DomainEnumerator(
      deviceId: "device1",
      storageId: 1,
      parentHandle: 100,
      indexReader: nil
    )

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorInvalidation() {
    let enumerator = DomainEnumerator(
      deviceId: "device1",
      storageId: 1,
      parentHandle: nil,
      indexReader: nil
    )

    enumerator.invalidate()
  }

  func testCurrentSyncAnchorWithIndexReader() async {
    let reader = MockLiveIndexReader()
    await reader.setChangeCounter(42)

    let enumerator = DomainEnumerator(
      deviceId: "device1",
      storageId: 1,
      parentHandle: nil,
      indexReader: reader
    )

    let anchorExpectation = expectation(description: "sync anchor callback")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor)
      if let raw = anchor?.rawValue {
        XCTAssertEqual(raw.count, MemoryLayout<Int64>.size)
      }
      anchorExpectation.fulfill()
    }

    await fulfillment(of: [anchorExpectation], timeout: 1.0)
  }
}
