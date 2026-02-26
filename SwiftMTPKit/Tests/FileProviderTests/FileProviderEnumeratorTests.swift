// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import FileProvider

final class FileProviderEnumeratorTests: XCTestCase {

  private actor MockLiveIndexReader: LiveIndexReader {
    var changeCounter: Int64 = 0
    var stubbedChanges: [IndexedObjectChange] = []
    var stubbedChildren: [IndexedObject] = []

    func setChangeCounter(_ value: Int64) {
      changeCounter = value
    }

    func setChanges(_ changes: [IndexedObjectChange]) {
      stubbedChanges = changes
    }

    func setChildren(_ children: [IndexedObject]) {
      stubbedChildren = children
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? { nil }
    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    { stubbedChildren }
    func storages(deviceId: String) async throws -> [IndexedStorage] { [] }
    func currentChangeCounter(deviceId: String) async throws -> Int64 { changeCounter }
    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
      stubbedChanges
    }
    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    { nil }
  }

  private class MockEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    nonisolated(unsafe) var enumeratedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var nextPageCursor: NSFileProviderPage?
    nonisolated(unsafe) var didFinish: Bool = false
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didEnumerate(_ items: [NSFileProviderItem]) {
      enumeratedItems.append(contentsOf: items)
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
      nextPageCursor = nextPage
      didFinish = true
      onFinish?()
    }

    func finishEnumeratingWithError(_ error: Error) {
      didFinish = true
      onFinish?()
    }
  }

  private class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didUpdate(_ items: [NSFileProviderItem]) {
      updatedItems.append(contentsOf: items)
    }

    func didDeleteItems(withIdentifiers identifiers: [NSFileProviderItemIdentifier]) {
      deletedIdentifiers.append(contentsOf: identifiers)
    }

    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
      onFinish?()
    }

    func finishEnumeratingWithError(_ error: Error) {
      onFinish?()
    }
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

  func testSyncAnchorEncodingRoundTrip() async {
    let reader = MockLiveIndexReader()
    await reader.setChangeCounter(999)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let anchorExp = expectation(description: "anchor")
    var capturedAnchor: NSFileProviderSyncAnchor?
    enumerator.currentSyncAnchor { anchor in
      capturedAnchor = anchor
      anchorExp.fulfill()
    }
    await fulfillment(of: [anchorExp], timeout: 1.0)

    guard let data = capturedAnchor?.rawValue else {
      XCTFail("No anchor data")
      return
    }
    XCTAssertEqual(data.count, MemoryLayout<Int64>.size)
    var decoded: Int64 = 0
    _ = withUnsafeMutableBytes(of: &decoded) { data.copyBytes(to: $0) }
    XCTAssertEqual(decoded, 999)
  }

  func testEnumerateChangesCallsDidUpdateForUpsertedItems() async {
    let reader = MockLiveIndexReader()
    let obj = IndexedObject(
      deviceId: "device1", storageId: 1, handle: 100,
      parentHandle: nil, name: "photo.jpg", pathKey: "/photo.jpg",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3800,
      isDirectory: false, changeCounter: 1)
    await reader.setChanges([IndexedObjectChange(kind: .upserted, object: obj)])
    await reader.setChangeCounter(1)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = MockChangeObserver()
    let finishExp = expectation(description: "finish")
    observer.onFinish = { finishExp.fulfill() }

    var zeroAnchor: Int64 = 0
    let anchorData = Data(bytes: &zeroAnchor, count: MemoryLayout<Int64>.size)
    enumerator.enumerateChanges(for: observer, from: NSFileProviderSyncAnchor(anchorData))

    await fulfillment(of: [finishExp], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "photo.jpg")
    XCTAssertTrue(observer.deletedIdentifiers.isEmpty)
  }

  func testEnumerateChangesCallsDidDeleteItemsForDeletedItems() async {
    let reader = MockLiveIndexReader()
    let obj = IndexedObject(
      deviceId: "device1", storageId: 1, handle: 200,
      parentHandle: nil, name: "old.txt", pathKey: "/old.txt",
      sizeBytes: 512, mtime: nil, formatCode: 0x3000,
      isDirectory: false, changeCounter: 2)
    await reader.setChanges([IndexedObjectChange(kind: .deleted, object: obj)])
    await reader.setChangeCounter(2)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = MockChangeObserver()
    let finishExp = expectation(description: "finish")
    observer.onFinish = { finishExp.fulfill() }

    var zeroAnchor: Int64 = 0
    let anchorData = Data(bytes: &zeroAnchor, count: MemoryLayout<Int64>.size)
    enumerator.enumerateChanges(for: observer, from: NSFileProviderSyncAnchor(anchorData))

    await fulfillment(of: [finishExp], timeout: 2.0)
    XCTAssertTrue(observer.updatedItems.isEmpty)
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first?.rawValue, "device1:1:200")
  }

  // MARK: - Paged Enumeration Tests

  /// Builds `count` synthetic `IndexedObject` values for paging tests.
  private func makeObjects(count: Int) -> [IndexedObject] {
    (0..<count).map { i in
      IndexedObject(
        deviceId: "device1", storageId: 1, handle: UInt32(i + 1),
        parentHandle: nil, name: "file\(i).jpg", pathKey: "/file\(i).jpg",
        sizeBytes: 1024, mtime: nil, formatCode: 0x3800,
        isDirectory: false, changeCounter: 0)
    }
  }

  func testPagedEnumeration_firstPageOf1200_yields500ItemsAndCursor() async {
    let reader = MockLiveIndexReader()
    await reader.setChildren(makeObjects(count: 1200))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = MockEnumerationObserver()
    let finishExp = expectation(description: "page 1 finish")
    observer.onFinish = { finishExp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [finishExp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 500, "Page 1 must yield exactly 500 items")
    XCTAssertNotNil(observer.nextPageCursor, "Page 1 must supply a next-page cursor")
  }

  func testPagedEnumeration_secondPageOf1200_yields500ItemsAndCursor() async {
    let reader = MockLiveIndexReader()
    await reader.setChildren(makeObjects(count: 1200))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    // Build a cursor encoding offset 500 (result of page 1)
    var offset500: UInt64 = 500
    let cursorData = Data(bytes: &offset500, count: MemoryLayout<UInt64>.size)
    let page2Cursor = NSFileProviderPage(cursorData)

    let observer = MockEnumerationObserver()
    let finishExp = expectation(description: "page 2 finish")
    observer.onFinish = { finishExp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: page2Cursor)

    await fulfillment(of: [finishExp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 500, "Page 2 must yield exactly 500 items")
    XCTAssertNotNil(observer.nextPageCursor, "Page 2 must supply a next-page cursor")
  }

  func testPagedEnumeration_thirdPageOf1200_yields200ItemsAndNoCursor() async {
    let reader = MockLiveIndexReader()
    await reader.setChildren(makeObjects(count: 1200))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    // Build a cursor encoding offset 1000 (result of page 2)
    var offset1000: UInt64 = 1000
    let cursorData = Data(bytes: &offset1000, count: MemoryLayout<UInt64>.size)
    let page3Cursor = NSFileProviderPage(cursorData)

    let observer = MockEnumerationObserver()
    let finishExp = expectation(description: "page 3 finish")
    observer.onFinish = { finishExp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: page3Cursor)

    await fulfillment(of: [finishExp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 200, "Page 3 must yield exactly 200 items")
    XCTAssertNil(observer.nextPageCursor, "Page 3 (last page) must not supply a cursor")
  }
}
