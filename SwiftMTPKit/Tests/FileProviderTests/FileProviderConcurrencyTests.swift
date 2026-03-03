// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPXPC
import FileProvider
import UniformTypeIdentifiers

/// Tests for concurrent operations, cancellation, progress, and queue management
/// in the File Provider extension.
final class FileProviderConcurrencyTests: XCTestCase {

  // MARK: - Mock LiveIndexReader

  private final class MockLiveIndexReader: @unchecked Sendable, LiveIndexReader {
    private var objects: [String: [UInt32: IndexedObject]] = [:]
    private var storagesByDevice: [String: [IndexedStorage]] = [:]
    private var changeCounterByDevice: [String: Int64] = [:]
    private var pendingChanges: [String: [IndexedObjectChange]] = [:]
    private var crawlDates: [String: Date] = [:]

    func addObject(_ object: IndexedObject) {
      if objects[object.deviceId] == nil { objects[object.deviceId] = [:] }
      objects[object.deviceId]?[object.handle] = object
    }

    func addStorage(_ storage: IndexedStorage) {
      if storagesByDevice[storage.deviceId] == nil { storagesByDevice[storage.deviceId] = [] }
      storagesByDevice[storage.deviceId]?.append(storage)
    }

    func setChangeCounter(_ value: Int64, deviceId: String) {
      changeCounterByDevice[deviceId] = value
    }

    func setChanges(_ changes: [IndexedObjectChange], deviceId: String) {
      pendingChanges[deviceId] = changes
    }

    func setCrawlDate(_ date: Date, deviceId: String, storageId: UInt32, parentHandle: UInt32?) {
      let key = "\(deviceId):\(storageId):\(parentHandle ?? 0)"
      crawlDates[key] = date
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      objects[deviceId]?[handle]
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    {
      guard let all = objects[deviceId] else { return [] }
      return all.values
        .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
        .sorted { $0.handle < $1.handle }
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
      storagesByDevice[deviceId] ?? []
    }

    func currentChangeCounter(deviceId: String) async throws -> Int64 {
      changeCounterByDevice[deviceId] ?? 0
    }

    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
      pendingChanges[deviceId] ?? []
    }

    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    {
      let key = "\(deviceId):\(storageId):\(parentHandle ?? 0)"
      return crawlDates[key]
    }
  }

  // MARK: - Mock Observers

  private class MockEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    nonisolated(unsafe) var enumeratedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var nextPageCursor: NSFileProviderPage?
    nonisolated(unsafe) var didFinish: Bool = false
    nonisolated(unsafe) var errorReceived: Error?
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
      errorReceived = error
      didFinish = true
      onFinish?()
    }
  }

  private class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    nonisolated(unsafe) var finishedAnchor: NSFileProviderSyncAnchor?
    nonisolated(unsafe) var moreComing: Bool = false
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didUpdate(_ items: [NSFileProviderItem]) {
      updatedItems.append(contentsOf: items)
    }

    func didDeleteItems(withIdentifiers identifiers: [NSFileProviderItemIdentifier]) {
      deletedIdentifiers.append(contentsOf: identifiers)
    }

    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
      finishedAnchor = anchor
      self.moreComing = moreComing
      onFinish?()
    }

    func finishEnumeratingWithError(_ error: Error) {
      onFinish?()
    }
  }

  // MARK: - Mock XPC Service

  private final class MockXPCService: NSObject, MTPXPCService {
    nonisolated(unsafe) var readCallCount = 0
    nonisolated(unsafe) var readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/test.txt"), fileSize: 1024)
    nonisolated(unsafe) var writeResponse = WriteResponse(success: true, newHandle: 200)
    nonisolated(unsafe) var deleteResponse = WriteResponse(success: true)
    nonisolated(unsafe) var createFolderResponse = WriteResponse(success: true, newHandle: 300)
    nonisolated(unsafe) var renameResponse = WriteResponse(success: true)
    nonisolated(unsafe) var moveResponse = WriteResponse(success: true)

    func ping(reply: @escaping (String) -> Void) { reply("ok") }

    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
      readCallCount += 1
      r(readResponse)
    }

    func listStorages(
      _ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void
    ) {
      r(StorageListResponse(success: true))
    }

    func listObjects(_ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void)
    {
      r(ObjectListResponse(success: true))
    }

    func getObjectInfo(
      deviceId: String, storageId: UInt32, objectHandle: UInt32,
      withReply r: @escaping (ReadResponse) -> Void
    ) { r(ReadResponse(success: true)) }

    func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(writeResponse)
    }

    func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(deleteResponse)
    }

    func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(createFolderResponse)
    }

    func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(renameResponse)
    }

    func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(moveResponse)
    }

    func requestCrawl(
      _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
    ) {
      r(CrawlTriggerResponse(accepted: true))
    }

    func deviceStatus(
      _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
    ) {
      r(DeviceStatusResponse(connected: true, sessionOpen: true))
    }
  }

  // MARK: - Helpers

  private func makeDomain() -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("concurrency-test"),
      displayName: "Concurrency Test")
  }

  private func makeExtension(
    reader: (any LiveIndexReader)?, xpc: MTPXPCService? = nil
  ) -> MTPFileProviderExtension {
    MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      xpcServiceResolver: xpc.map { svc in { svc } },
      signalEnumeratorOverride: { _ in })
  }

  private func makeObject(
    handle: UInt32, parentHandle: UInt32? = nil, name: String,
    size: UInt64? = 1024, isDirectory: Bool = false,
    storageId: UInt32 = 1, deviceId: String = "device1"
  ) -> IndexedObject {
    IndexedObject(
      deviceId: deviceId, storageId: storageId, handle: handle,
      parentHandle: parentHandle, name: name, pathKey: "/\(name)",
      sizeBytes: size, mtime: nil, formatCode: isDirectory ? 0x3001 : 0x3800,
      isDirectory: isDirectory, changeCounter: 0)
  }

  private func makeStorage(
    storageId: UInt32 = 1, deviceId: String = "device1", name: String = "Internal Storage"
  ) -> IndexedStorage {
    IndexedStorage(
      deviceId: deviceId, storageId: storageId, description: name,
      capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
  }

  private func zeroAnchor() -> NSFileProviderSyncAnchor {
    var zero: Int64 = 0
    return NSFileProviderSyncAnchor(Data(bytes: &zero, count: 8))
  }

  // MARK: - Concurrent Enumeration Requests

  func testConcurrentEnumerationOfSameDirectory() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...20 {
      reader.addObject(makeObject(handle: i, name: "file\(i).jpg"))
    }

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let expectations = (0..<5).map { expectation(description: "enum-\($0)") }
    let observers = (0..<5).map { _ in MockEnumerationObserver() }

    for i in 0..<5 {
      observers[i].onFinish = { expectations[i].fulfill() }
      enumerator.enumerateItems(
        for: observers[i],
        startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    }

    await fulfillment(of: expectations, timeout: 5)

    for observer in observers {
      XCTAssertTrue(observer.didFinish)
      XCTAssertEqual(observer.enumeratedItems.count, 20)
      XCTAssertNil(observer.errorReceived)
    }
  }

  func testConcurrentEnumerationOfDifferentDirectories() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    // dir1 children
    for i: UInt32 in 10...15 {
      reader.addObject(makeObject(handle: i, parentHandle: 1, name: "a\(i).jpg"))
    }
    // dir2 children
    for i: UInt32 in 20...25 {
      reader.addObject(makeObject(handle: i, parentHandle: 2, name: "b\(i).jpg"))
    }

    let enum1 = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: 1, indexReader: reader)
    let enum2 = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: 2, indexReader: reader)

    let exp1 = expectation(description: "dir1")
    let exp2 = expectation(description: "dir2")
    let obs1 = MockEnumerationObserver()
    let obs2 = MockEnumerationObserver()
    obs1.onFinish = { exp1.fulfill() }
    obs2.onFinish = { exp2.fulfill() }

    enum1.enumerateItems(
      for: obs1, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    enum2.enumerateItems(
      for: obs2, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp1, exp2], timeout: 5)

    XCTAssertEqual(obs1.enumeratedItems.count, 6)
    XCTAssertEqual(obs2.enumeratedItems.count, 6)
  }

  // MARK: - Concurrent Materialization of Same File

  @MainActor
  func testConcurrentFetchContentsForSameFile() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "photo.jpg", size: 2048))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let expectations = (0..<3).map { expectation(description: "fetch-\($0)") }
    var results: [(URL?, NSFileProviderItem?, Error?)] = Array(repeating: (nil, nil, nil), count: 3)

    for i in 0..<3 {
      _ = ext.fetchContents(
        for: NSFileProviderItemIdentifier("device1:1:42"),
        version: nil, request: NSFileProviderRequest()
      ) { url, item, error in
        results[i] = (url, item, error)
        expectations[i].fulfill()
      }
    }

    wait(for: expectations, timeout: 5)

    for i in 0..<3 {
      XCTAssertNotNil(results[i].0, "fetch \(i) should return URL")
      XCTAssertNotNil(results[i].1, "fetch \(i) should return item")
      XCTAssertNil(results[i].2, "fetch \(i) should not error")
    }
    XCTAssertEqual(xpc.readCallCount, 3)
  }

  // MARK: - Cancellation During Materialization

  @MainActor
  func testFetchContentsProgressIsCancellable() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "big.bin", size: 1_000_000))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in }

    XCTAssertTrue(
      progress.isCancellable || !progress.isCancelled,
      "Progress should be valid and not cancelled initially")
    progress.cancel()
    XCTAssertTrue(progress.isCancelled)
  }

  @MainActor
  func testItemLookupProgressIsCancellable() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    let progress = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:99"),
      request: NSFileProviderRequest()
    ) { _, _ in }

    progress.cancel()
    XCTAssertTrue(progress.isCancelled)
  }

  // MARK: - Progress Reporting Accuracy

  @MainActor
  func testFetchContentsProgressTotalIsOne() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "img.jpg"))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "fetch")
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in exp.fulfill() }

    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 5)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testCreateItemProgressTotalIsOne() {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("up.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("hello".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      name: "up.txt", size: 5, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create")
    let progress = ext.createItem(
      basedOn: item, fields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in exp.fulfill() }

    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 5)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testDeleteItemProgressTotalIsOne() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "delete")
    let progress = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:42"),
      baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { _ in exp.fulfill() }

    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 5)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testModifyItemProgressTotalIsOne() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "doc.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify")
    let progress = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      changedFields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in exp.fulfill() }

    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 5)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  // MARK: - Memory Pressure / Large Result Sets

  func testEnumerateLargeDirectoryCompletesWithoutError() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...1000 {
      reader.addObject(makeObject(handle: i, name: "file\(i).dat", size: UInt64(i * 100)))
    }

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "large-enum")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 10)

    XCTAssertTrue(observer.didFinish)
    // First page should have 500 items (page size limit)
    XCTAssertEqual(observer.enumeratedItems.count, 500)
    XCTAssertNotNil(observer.nextPageCursor, "Should have next page cursor")
    XCTAssertNil(observer.errorReceived)
  }

  func testEnumerateWithExactlyPageSizeItems() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...500 {
      reader.addObject(makeObject(handle: i, name: "file\(i).dat"))
    }

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "exact-page")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 500)
    XCTAssertNil(observer.nextPageCursor, "Exactly page size should not produce next page")
  }

  // MARK: - Background Download Queue Management

  @MainActor
  func testMultipleFetchRequestsAreIndependent() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "a.jpg", size: 100))
    reader.addObject(makeObject(handle: 20, name: "b.jpg", size: 200))
    reader.addObject(makeObject(handle: 30, name: "c.jpg", size: 300))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let handles: [UInt32] = [10, 20, 30]
    let expectations = handles.map { expectation(description: "fetch-\($0)") }
    var items: [NSFileProviderItem?] = [nil, nil, nil]

    for (i, handle) in handles.enumerated() {
      _ = ext.fetchContents(
        for: NSFileProviderItemIdentifier("device1:1:\(handle)"),
        version: nil, request: NSFileProviderRequest()
      ) { _, item, _ in
        items[i] = item
        expectations[i].fulfill()
      }
    }

    wait(for: expectations, timeout: 5)

    for i in 0..<handles.count {
      XCTAssertNotNil(items[i], "Handle \(handles[i]) should return an item")
    }
  }

  @MainActor
  func testFetchWithXPCFailureDoesNotBlockSubsequentFetches() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "a.jpg"))
    reader.addObject(makeObject(handle: 20, name: "b.jpg"))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    // First fetch fails
    xpc.readResponse = ReadResponse(success: false, errorMessage: "device busy")
    let exp1 = expectation(description: "fetch-fail")
    var error1: Error?
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:10"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, err in
      error1 = err
      exp1.fulfill()
    }
    wait(for: [exp1], timeout: 5)
    XCTAssertNotNil(error1)

    // Second fetch succeeds
    xpc.readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/b.jpg"), fileSize: 512)
    let exp2 = expectation(description: "fetch-ok")
    var item2: NSFileProviderItem?
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:20"),
      version: nil, request: NSFileProviderRequest()
    ) { _, item, _ in
      item2 = item
      exp2.fulfill()
    }
    wait(for: [exp2], timeout: 5)
    XCTAssertNotNil(item2)
  }

  // MARK: - Stale Item Eviction via Change Tracking

  func testSyncAnchorStoreEvictsDeletedItems() async {
    let store = SyncAnchorStore()
    let key = "device1:1"

    // Record some additions
    let id1 = NSFileProviderItemIdentifier("device1:1:100")
    let id2 = NSFileProviderItemIdentifier("device1:1:200")
    store.recordChange(added: [id1, id2], deleted: [], for: key)

    // Then record a deletion
    store.recordChange(added: [], deleted: [id1], for: key)

    let result = store.consumeChanges(from: Data(), for: key)
    XCTAssertTrue(result.added.contains(id1))
    XCTAssertTrue(result.added.contains(id2))
    XCTAssertTrue(result.deleted.contains(id1))
  }

  func testSyncAnchorStoreMultipleBatches() {
    let store = SyncAnchorStore()
    let key = "device1:1"

    // Add more than maxBatchSize items
    var ids: [NSFileProviderItemIdentifier] = []
    for i in 0..<250 {
      ids.append(NSFileProviderItemIdentifier("device1:1:\(i)"))
    }
    store.recordChange(added: ids, deleted: [], for: key)

    let batch1 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch1.added.count, 200)
    XCTAssertTrue(batch1.hasMore)

    let batch2 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch2.added.count, 50)
    XCTAssertFalse(batch2.hasMore)
  }

  func testSyncAnchorStoreConsumeFromEmptyKey() {
    let store = SyncAnchorStore()
    let result = store.consumeChanges(from: Data(), for: "nonexistent:key")
    XCTAssertTrue(result.added.isEmpty)
    XCTAssertTrue(result.deleted.isEmpty)
    XCTAssertFalse(result.hasMore)
  }

  // MARK: - Working Set Sync

  func testEnumerateChangesYieldsAddedAndDeletedItems() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "new.jpg", size: 512))
    reader.setChanges(
      [
        IndexedObjectChange(kind: .upserted, object: makeObject(handle: 10, name: "new.jpg")),
        IndexedObjectChange(kind: .deleted, object: makeObject(handle: 20, name: "old.jpg")),
      ], deviceId: "device1")
    reader.setChangeCounter(5, deviceId: "device1")

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "changes")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: zeroAnchor())

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertNotNil(observer.finishedAnchor)
    XCTAssertFalse(observer.moreComing)
  }

  func testCurrentSyncAnchorReflectsLatestChangeCounter() async {
    let reader = MockLiveIndexReader()
    reader.setChangeCounter(42, deviceId: "device1")

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor)
      // Decode anchor and verify
      if let data = anchor?.rawValue, data.count == 8 {
        var value: Int64 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
        XCTAssertEqual(value, 42)
      }
      exp.fulfill()
    }

    await fulfillment(of: [exp], timeout: 5)
  }

  func testEnumerateChangesWithSyncAnchorStorePath() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 50, name: "synced.txt"))

    let store = SyncAnchorStore()
    let key = "device1:1"
    let addedId = NSFileProviderItemIdentifier("device1:1:50")
    store.recordChange(added: [addedId], deleted: [], for: key)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let exp = expectation(description: "anchor-store-changes")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: NSFileProviderSyncAnchor(Data()))

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "synced.txt")
  }

  // MARK: - Concurrent Event Handling

  func testConcurrentDeviceEventsDoNotCorruptSyncAnchorStore() {
    let store = SyncAnchorStore()
    let key = "device1:1"

    let group = DispatchGroup()
    let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

    for i in 0..<100 {
      group.enter()
      queue.async {
        let id = NSFileProviderItemIdentifier("device1:1:\(i)")
        if i % 3 == 0 {
          store.recordChange(added: [], deleted: [id], for: key)
        } else {
          store.recordChange(added: [id], deleted: [], for: key)
        }
        group.leave()
      }
    }

    group.wait()

    // Consume all batches
    var totalAdded = 0
    var totalDeleted = 0
    var hasMore = true
    while hasMore {
      let result = store.consumeChanges(from: Data(), for: key)
      totalAdded += result.added.count
      totalDeleted += result.deleted.count
      hasMore = result.hasMore
    }

    // ~67 adds (i % 3 != 0) and ~34 deletes (i % 3 == 0)
    XCTAssertEqual(totalAdded + totalDeleted, 100)
  }

  @MainActor
  func testHandleMultipleDeviceEventsRapidly() {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    let ext = makeExtension(reader: reader)

    // Rapid-fire events
    for i: UInt32 in 1...50 {
      ext.handleDeviceEvent(
        .addObject(
          deviceId: "device1", storageId: 1, objectHandle: i, parentHandle: nil))
    }
    for i: UInt32 in 1...10 {
      ext.handleDeviceEvent(
        .deleteObject(
          deviceId: "device1", storageId: 1, objectHandle: i))
    }
    ext.handleDeviceEvent(.storageAdded(deviceId: "device1", storageId: 2))
    ext.handleDeviceEvent(.storageRemoved(deviceId: "device1", storageId: 3))

    // Should not crash; no assertions needed beyond survival
  }

  // MARK: - Enumeration + Event Interleaving

  func testEnumerationDuringEventHandling() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...10 {
      reader.addObject(makeObject(handle: i, name: "file\(i).jpg"))
    }

    let ext = makeExtension(reader: reader)

    // Start enumeration
    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "enum-during-events")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    // Fire events while enumerating
    ext.handleDeviceEvent(
      .addObject(
        deviceId: "device1", storageId: 1, objectHandle: 100, parentHandle: nil))

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    ext.handleDeviceEvent(
      .deleteObject(
        deviceId: "device1", storageId: 1, objectHandle: 1))

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertTrue(observer.didFinish)
    XCTAssertNil(observer.errorReceived)
  }

  // MARK: - Extension Lifecycle Under Concurrency

  @MainActor
  func testExtensionInvalidationDuringPendingOperations() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "test.txt"))
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    // Start a fetch, then immediately invalidate
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in }

    ext.invalidate()
    // Should not crash
  }

  @MainActor
  func testMultipleInvalidationsAreIdempotent() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    ext.invalidate()
    ext.invalidate()
    ext.invalidate()
    // Should not crash
  }

  // MARK: - Concurrent Create and Delete

  @MainActor
  func testConcurrentCreateAndDeleteOperations() {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("concurrent.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("test".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let createItem = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      name: "concurrent.txt", size: 4, isDirectory: false, modifiedDate: nil)

    let expCreate = expectation(description: "create")
    let expDelete = expectation(description: "delete")

    _ = ext.createItem(
      basedOn: createItem, fields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in expCreate.fulfill() }

    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:42"),
      baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { _ in expDelete.fulfill() }

    wait(for: [expCreate, expDelete], timeout: 5)
  }

  // MARK: - SyncAnchor Store Thread Safety

  func testCurrentAnchorForUnknownKeyReturnsValidData() {
    let store = SyncAnchorStore()
    let anchor = store.currentAnchor(for: "never-seen")
    XCTAssertEqual(anchor.count, 8, "Anchor should be 8 bytes (Int64)")
  }

  func testAnchorAdvancesAfterRecordChange() {
    let store = SyncAnchorStore()
    let key = "device1:1"

    let anchor1 = store.currentAnchor(for: key)
    Thread.sleep(forTimeInterval: 0.01)
    store.recordChange(
      added: [NSFileProviderItemIdentifier("device1:1:1")], deleted: [], for: key)
    let anchor2 = store.currentAnchor(for: key)

    XCTAssertNotEqual(anchor1, anchor2, "Anchor should advance after change")
  }
}
