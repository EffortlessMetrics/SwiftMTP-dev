// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import FileProvider
import SwiftMTPCore
import SwiftMTPIndex

final class SyncAnchorTests: XCTestCase {

  // MARK: - Helpers

  private actor MockIndexReader: LiveIndexReader {
    private var objects: [UInt32: IndexedObject] = [:]

    func addObject(_ obj: IndexedObject) { objects[obj.handle] = obj }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      objects[handle]
    }
    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    { [] }
    func storages(deviceId: String) async throws -> [IndexedStorage] { [] }
    func currentChangeCounter(deviceId: String) async throws -> Int64 { 0 }
    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] { [] }
    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    { nil }
  }

  private class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didUpdate(_ items: [NSFileProviderItem]) {
      updatedItems.append(contentsOf: items)
    }
    func didDeleteItems(withIdentifiers ids: [NSFileProviderItemIdentifier]) {
      deletedIdentifiers.append(contentsOf: ids)
    }
    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
      onFinish?()
    }
    func finishEnumeratingWithError(_ error: Error) { onFinish?() }
  }

  // MARK: - SyncAnchorStore Tests

  func testInitialAnchorIsNonNil() {
    let store = SyncAnchorStore()
    let anchor = store.currentAnchor(for: "dev1:1")
    XCTAssertEqual(anchor.count, 8, "Anchor must be an 8-byte timestamp")
  }

  func testRecordAndConsumeChange_addsItems() {
    let store = SyncAnchorStore()
    let key = "dev1:1"
    let id = NSFileProviderItemIdentifier("dev1:1:42")

    store.recordChange(added: [id], deleted: [], for: key)

    let anchor = store.currentAnchor(for: key)
    let result = store.consumeChanges(from: anchor, for: key)

    XCTAssertEqual(result.added.count, 1)
    XCTAssertEqual(result.added.first, id)
    XCTAssertTrue(result.deleted.isEmpty)
    XCTAssertFalse(result.hasMore)
  }

  func testConsumeChanges_capsAt200Items() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let items = (0..<300).map { NSFileProviderItemIdentifier("dev1:1:\($0)") }
    store.recordChange(added: items, deleted: [], for: key)

    let anchor = store.currentAnchor(for: key)
    let result = store.consumeChanges(from: anchor, for: key)

    XCTAssertEqual(result.added.count, 200)
    XCTAssertTrue(result.hasMore, "Remaining 100 items must set hasMore=true")

    // Second consume drains the rest
    let result2 = store.consumeChanges(from: anchor, for: key)
    XCTAssertEqual(result2.added.count, 100)
    XCTAssertFalse(result2.hasMore)
  }

  func testAnchorBumpsAfterRecordChange() {
    let store = SyncAnchorStore()
    let key = "dev1:2"

    let before = store.currentAnchor(for: key)
    // Small sleep to ensure timestamp advances
    Thread.sleep(forTimeInterval: 0.002)
    store.recordChange(added: [NSFileProviderItemIdentifier("dev1:2:1")], deleted: [], for: key)
    let after = store.currentAnchor(for: key)

    // Both are 8-byte; after must be >= before
    var ts1: Int64 = 0
    var ts2: Int64 = 0
    _ = withUnsafeMutableBytes(of: &ts1) { before.copyBytes(to: $0) }
    _ = withUnsafeMutableBytes(of: &ts2) { after.copyBytes(to: $0) }
    XCTAssertGreaterThanOrEqual(ts2, ts1)
  }

  // MARK: - DomainEnumerator + SyncAnchorStore Integration

  func testEnumerateChanges_callsDidUpdate() async {
    let store = SyncAnchorStore()
    let reader = MockIndexReader()

    let obj = IndexedObject(
      deviceId: "dev1", storageId: 1, handle: 42,
      parentHandle: nil, name: "photo.jpg", pathKey: "/photo.jpg",
      sizeBytes: 1024, mtime: nil, formatCode: 0x3800,
      isDirectory: false, changeCounter: 1)
    await reader.addObject(obj)

    let key = "dev1:1"
    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:42")],
      deleted: [],
      for: key)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let observer = MockChangeObserver()
    let finishExp = expectation(description: "enumerateChanges finishes")
    observer.onFinish = { finishExp.fulfill() }

    let anchor = NSFileProviderSyncAnchor(store.currentAnchor(for: key))
    enumerator.enumerateChanges(for: observer, from: anchor)

    await fulfillment(of: [finishExp], timeout: 2.0)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "photo.jpg")
    XCTAssertTrue(observer.deletedIdentifiers.isEmpty)
  }

  func testEnumerateChanges_callsDidDeleteItems() async {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    store.recordChange(
      added: [],
      deleted: [NSFileProviderItemIdentifier("dev1:1:99")],
      for: key)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: nil, syncAnchorStore: store)

    let observer = MockChangeObserver()
    let finishExp = expectation(description: "enumerateChanges finishes")
    observer.onFinish = { finishExp.fulfill() }

    let anchor = NSFileProviderSyncAnchor(store.currentAnchor(for: key))
    enumerator.enumerateChanges(for: observer, from: anchor)

    await fulfillment(of: [finishExp], timeout: 2.0)

    XCTAssertTrue(observer.updatedItems.isEmpty)
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first?.rawValue, "dev1:1:99")
  }

  // MARK: - signalEnumerator on device event

  func testSignalEnumerator_calledOnEvent() {
    var signaledIdentifiers: [NSFileProviderItemIdentifier] = []

    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("signal-test"),
      displayName: "Signal Test")
    let ext = MTPFileProviderExtension(
      domain: domain,
      indexReader: nil,
      signalEnumeratorOverride: { id in signaledIdentifiers.append(id) })

    ext.handleDeviceEvent(
      .addObject(deviceId: "dev1", storageId: 1, objectHandle: 42, parentHandle: nil))

    XCTAssertTrue(
      signaledIdentifiers.contains(NSFileProviderItemIdentifier("dev1:1")),
      "signalEnumerator must be called for the affected storage container")
  }

  func testSignalEnumerator_deleteObjectEvent() {
    var signaledIdentifiers: [NSFileProviderItemIdentifier] = []

    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("signal-delete-test"),
      displayName: "Signal Delete Test")
    let ext = MTPFileProviderExtension(
      domain: domain,
      indexReader: nil,
      signalEnumeratorOverride: { id in signaledIdentifiers.append(id) })

    ext.handleDeviceEvent(.deleteObject(deviceId: "dev2", storageId: 2, objectHandle: 10))

    XCTAssertTrue(
      signaledIdentifiers.contains(NSFileProviderItemIdentifier("dev2:2")),
      "signalEnumerator must be called for the affected storage container on delete")
  }
}
