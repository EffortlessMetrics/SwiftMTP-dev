// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import FileProvider
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPXPC
import UniformTypeIdentifiers

// MARK: - Shared Test Infrastructure

/// Actor-based mock index reader with configurable error injection.
private actor ResilienceIndexReader: LiveIndexReader {
  private var objectsByDevice: [String: [UInt32: IndexedObject]] = [:]
  private var storagesByDevice: [String: [IndexedStorage]] = [:]
  private var changesByDevice: [String: [IndexedObjectChange]] = [:]
  private var counterByDevice: [String: Int64] = [:]
  private var forcedError: Error?

  func setForcedError(_ error: Error?) { forcedError = error }

  func addStorage(_ s: IndexedStorage) {
    storagesByDevice[s.deviceId, default: []].append(s)
  }

  func addObject(_ o: IndexedObject) {
    objectsByDevice[o.deviceId, default: [:]][o.handle] = o
  }

  func setChildren(_ objects: [IndexedObject], deviceId: String) {
    objectsByDevice[deviceId] = [:]
    for o in objects { objectsByDevice[deviceId, default: [:]][o.handle] = o }
  }

  func setChanges(_ changes: [IndexedObjectChange], deviceId: String) {
    changesByDevice[deviceId] = changes
  }

  func setCounter(_ counter: Int64, deviceId: String) {
    counterByDevice[deviceId] = counter
  }

  func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
    if let e = forcedError { throw e }
    return objectsByDevice[deviceId]?[handle]
  }

  func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
    -> [IndexedObject]
  {
    if let e = forcedError { throw e }
    return (objectsByDevice[deviceId] ?? [:]).values
      .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
      .sorted { $0.handle < $1.handle }
  }

  func storages(deviceId: String) async throws -> [IndexedStorage] {
    if let e = forcedError { throw e }
    return storagesByDevice[deviceId] ?? []
  }

  func currentChangeCounter(deviceId: String) async throws -> Int64 {
    if let e = forcedError { throw e }
    return counterByDevice[deviceId] ?? 0
  }

  func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
    if let e = forcedError { throw e }
    return changesByDevice[deviceId] ?? []
  }

  func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
    -> Date?
  {
    if let e = forcedError { throw e }
    return nil
  }
}

/// Controllable XPC service stub for resilience tests.
private final class ResilienceXPCService: NSObject, MTPXPCService {
  nonisolated(unsafe) var onReadObject: ((ReadRequest) -> ReadResponse)?
  nonisolated(unsafe) var onWriteObject: ((WriteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onDeleteObject: ((DeleteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onCreateFolder: ((CreateFolderRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRenameObject: ((RenameRequest) -> WriteResponse)?
  nonisolated(unsafe) var onMoveObject: ((MoveObjectRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRequestCrawl: ((CrawlTriggerRequest) -> CrawlTriggerResponse)?

  func ping(reply: @escaping (String) -> Void) { reply("ok") }

  func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
    r(onReadObject?(req) ?? ReadResponse(success: false, errorMessage: "stub"))
  }

  func listStorages(_ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void)
  {
    r(StorageListResponse(success: false))
  }

  func listObjects(_ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void) {
    r(ObjectListResponse(success: false))
  }

  func getObjectInfo(
    deviceId: String, storageId: UInt32, objectHandle: UInt32,
    withReply r: @escaping (ReadResponse) -> Void
  ) { r(ReadResponse(success: false)) }

  func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(onWriteObject?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(onDeleteObject?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(onCreateFolder?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(onRenameObject?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(onMoveObject?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func requestCrawl(
    _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
  ) {
    r(onRequestCrawl?(req) ?? CrawlTriggerResponse(accepted: false))
  }

  func deviceStatus(
    _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
  ) { r(DeviceStatusResponse(connected: true, sessionOpen: true)) }
}

/// Mock enumeration observer capturing results.
private class ResilienceEnumObserver: NSObject, NSFileProviderEnumerationObserver {
  nonisolated(unsafe) var items: [NSFileProviderItem] = []
  nonisolated(unsafe) var nextPage: NSFileProviderPage?
  nonisolated(unsafe) var error: Error?
  nonisolated(unsafe) var onFinish: (() -> Void)?

  func didEnumerate(_ updatedItems: [NSFileProviderItem]) {
    items.append(contentsOf: updatedItems)
  }

  func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
    self.nextPage = nextPage
    onFinish?()
  }

  func finishEnumeratingWithError(_ error: Error) {
    self.error = error
    onFinish?()
  }
}

/// Mock change observer.
private class ResilienceChangeObserver: NSObject, NSFileProviderChangeObserver {
  nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
  nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
  nonisolated(unsafe) var latestAnchor: NSFileProviderSyncAnchor?
  nonisolated(unsafe) var moreComing: Bool = false
  nonisolated(unsafe) var error: Error?
  nonisolated(unsafe) var onFinish: (() -> Void)?

  func didUpdate(_ items: [NSFileProviderItem]) {
    updatedItems.append(contentsOf: items)
  }

  func didDeleteItems(withIdentifiers ids: [NSFileProviderItemIdentifier]) {
    deletedIdentifiers.append(contentsOf: ids)
  }

  func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
    latestAnchor = anchor
    self.moreComing = moreComing
    onFinish?()
  }

  func finishEnumeratingWithError(_ error: Error) {
    self.error = error
    onFinish?()
  }
}

// MARK: - Helpers

private func makeTestDomain(_ name: String = "resilience-test") -> NSFileProviderDomain {
  NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(name), displayName: name)
}

private func makeObject(
  deviceId: String = "dev1", storageId: UInt32 = 1, handle: UInt32,
  parentHandle: UInt32? = nil, name: String, sizeBytes: UInt64? = 1024,
  isDirectory: Bool = false
) -> IndexedObject {
  IndexedObject(
    deviceId: deviceId, storageId: storageId, handle: handle,
    parentHandle: parentHandle, name: name, pathKey: "/\(name)",
    sizeBytes: sizeBytes, mtime: nil, formatCode: isDirectory ? 0x3001 : 0x3800,
    isDirectory: isDirectory, changeCounter: 0)
}

private func makeStorage(
  deviceId: String = "dev1", storageId: UInt32 = 1,
  description: String = "Internal Storage"
) -> IndexedStorage {
  IndexedStorage(
    deviceId: deviceId, storageId: storageId, description: description,
    capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
}

private func makeZeroAnchorData() -> Data {
  var zero: Int64 = 0
  return Data(bytes: &zero, count: MemoryLayout<Int64>.size)
}

// MARK: - Item Enumeration Edge Cases

final class FileProviderEnumerationResilienceTests: XCTestCase {

  // MARK: 1 — Empty directory returns zero items and no cursor

  func testEnumerateEmptyDirectory() async {
    let reader = ResilienceIndexReader()
    await reader.addStorage(makeStorage())

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 0)
    XCTAssertNil(observer.nextPage)
  }

  // MARK: 2 — Large directory (150 items, single page)

  func testEnumerateManyItems_singlePage() async {
    let reader = ResilienceIndexReader()
    let objects = (1...150).map { i in
      makeObject(handle: UInt32(i), name: "file\(i).jpg")
    }
    await reader.setChildren(objects, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 150)
    XCTAssertNil(observer.nextPage, "All items fit in one page")
  }

  // MARK: 3 — Large directory (600 items, requires paging)

  func testEnumerateManyItems_multiPage() async {
    let reader = ResilienceIndexReader()
    let objects = (1...600).map { i in
      makeObject(handle: UInt32(i), name: "file\(i).jpg")
    }
    await reader.setChildren(objects, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 500, "First page must cap at 500")
    XCTAssertNotNil(observer.nextPage, "Must supply a next-page cursor")
  }

  // MARK: 4 — Enumerate after simulated disconnect (index throws)

  func testEnumerateAfterDisconnect_reportsError() async {
    let reader = ResilienceIndexReader()
    await reader.setForcedError(
      NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "disconnected"])
    )

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertNotNil(observer.error, "Should report error on disconnect")
    XCTAssertEqual(observer.items.count, 0)
  }

  // MARK: 5 — Enumerate with mixed file types

  func testEnumerateMixedFileTypes() async {
    let reader = ResilienceIndexReader()
    let items: [IndexedObject] = [
      makeObject(handle: 1, name: "photo.jpg"),
      makeObject(handle: 2, name: "DCIM", sizeBytes: nil, isDirectory: true),
      makeObject(handle: 3, name: "video.mp4", sizeBytes: 50_000_000),
      makeObject(handle: 4, name: "document.pdf"),
      makeObject(handle: 5, name: "archive.zip"),
    ]
    await reader.setChildren(items, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 5)

    let types = observer.items.map { $0.contentType }
    XCTAssertTrue(types.contains(.folder))
    XCTAssertTrue(types.contains(.jpeg))
  }

  // MARK: 6 — Item identifier round-trip encoding/decoding

  func testItemIdentifierRoundTrip_fileLevel() {
    let item = MTPFileProviderItem(
      deviceId: "my-device", storageId: 3, objectHandle: 42,
      parentHandle: 10, name: "photo.jpg", size: 2048,
      isDirectory: false, modifiedDate: nil)

    let parsed = MTPFileProviderItem.parseItemIdentifier(item.itemIdentifier)
    XCTAssertEqual(parsed?.deviceId, "my-device")
    XCTAssertEqual(parsed?.storageId, 3)
    XCTAssertEqual(parsed?.objectHandle, 42)
  }

  func testItemIdentifierRoundTrip_storageLevel() {
    let item = MTPFileProviderItem(
      deviceId: "dev-abc", storageId: 7, objectHandle: nil,
      name: "SD Card", size: nil, isDirectory: true, modifiedDate: nil)

    let parsed = MTPFileProviderItem.parseItemIdentifier(item.itemIdentifier)
    XCTAssertEqual(parsed?.deviceId, "dev-abc")
    XCTAssertEqual(parsed?.storageId, 7)
    XCTAssertNil(parsed?.objectHandle)
  }

  func testItemIdentifierRoundTrip_deviceLevel() {
    let item = MTPFileProviderItem(
      deviceId: "unique-dev", storageId: nil, objectHandle: nil,
      name: "Device", size: nil, isDirectory: true, modifiedDate: nil)

    let parsed = MTPFileProviderItem.parseItemIdentifier(item.itemIdentifier)
    XCTAssertEqual(parsed?.deviceId, "unique-dev")
    XCTAssertNil(parsed?.storageId)
    XCTAssertNil(parsed?.objectHandle)
  }

  // MARK: 7 — Working set enumeration with nil index reader

  func testEnumerateWithNilReader_finishesImmediately() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: nil)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 0)
    XCTAssertNil(observer.nextPage)
  }

  // MARK: 8 — Enumerate storages when no storage is configured

  func testEnumerateDeviceRoot_noStorages_finishesEmpty() async {
    let reader = ResilienceIndexReader()

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 0)
  }

  // MARK: 9 — Enumerate multiple storages

  func testEnumerateDeviceRoot_multipleStorages() async {
    let reader = ResilienceIndexReader()
    await reader.addStorage(makeStorage(storageId: 1, description: "Internal Storage"))
    await reader.addStorage(makeStorage(storageId: 2, description: "SD Card"))

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)
    let observer = ResilienceEnumObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.items.count, 2)
    let names = observer.items.map { $0.filename }
    XCTAssertTrue(names.contains("Internal Storage"))
    XCTAssertTrue(names.contains("SD Card"))
  }

  // MARK: 10 — Sync anchor with nil reader returns nil

  func testCurrentSyncAnchor_nilReader_returnsNil() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: nil)

    let exp = expectation(description: "anchor callback")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNil(anchor)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 1.0)
  }

  // MARK: 11 — Enumerate changes with no changes returns empty

  func testEnumerateChanges_noChanges_returnsEmpty() async {
    let reader = ResilienceIndexReader()
    await reader.setCounter(5, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = ResilienceChangeObserver()
    let exp = expectation(description: "finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(
      for: observer, from: NSFileProviderSyncAnchor(makeZeroAnchorData()))

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 0)
    XCTAssertEqual(observer.deletedIdentifiers.count, 0)
  }
}

// MARK: - File Transfer Edge Cases

final class FileProviderTransferResilienceTests: XCTestCase {

  // MARK: 1 — Import zero-byte file via createItem

  @MainActor
  func testCreateItem_zeroByteFile_succeeds() {
    let xpc = ResilienceXPCService()
    xpc.onWriteObject = { req in
      XCTAssertEqual(req.size, 0)
      return WriteResponse(success: true, newHandle: 200)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("zero-byte-test.txt")
    FileManager.default.createFile(atPath: tmpURL.path, contents: Data(), attributes: nil)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "empty.txt", size: 0,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { item, _, _, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 2 — Import file with very long name (255 chars)

  @MainActor
  func testCreateItem_veryLongFilename() {
    let longName = String(repeating: "a", count: 251) + ".txt"  // 255 chars
    let xpc = ResilienceXPCService()
    xpc.onWriteObject = { req in
      XCTAssertEqual(req.name, longName)
      return WriteResponse(success: true, newHandle: 201)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("long-name-test.txt")
    try? "data".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: longName, size: 4,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { item, _, _, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        XCTAssertEqual(item?.filename, longName)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 3 — Import file with unicode/emoji filename

  @MainActor
  func testCreateItem_unicodeEmojiFilename() {
    let unicodeName = "📸 Пляж — 海滩.jpg"
    let xpc = ResilienceXPCService()
    xpc.onWriteObject = { req in
      XCTAssertEqual(req.name, unicodeName)
      return WriteResponse(success: true, newHandle: 202)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("emoji-test.jpg")
    try? Data(count: 100).write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: unicodeName, size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { item, _, _, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        XCTAssertEqual(item?.filename, unicodeName)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 4 — Fetch contents for deleted item (index returns nil)

  @MainActor
  func testFetchContents_deletedItem_returnsError() {
    let reader = ResilienceIndexReader()
    let xpc = ResilienceXPCService()
    xpc.onReadObject = { _ in
      return ReadResponse(success: false, errorMessage: "Object not found")
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: reader, xpcServiceResolver: { xpc })

    let exp = expectation(description: "fetch")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:999"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        XCTAssertNil(url)
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 5 — Concurrent fetch requests complete independently

  @MainActor
  func testConcurrentFetchRequests_completeIndependently() {
    let xpc = ResilienceXPCService()
    let callLock = NSLock()
    nonisolated(unsafe) var callCount = 0
    xpc.onReadObject = { _ in
      callLock.lock()
      callCount += 1
      callLock.unlock()
      return ReadResponse(success: false, errorMessage: "stub")
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let exp1 = expectation(description: "fetch1")
    let exp2 = expectation(description: "fetch2")
    let exp3 = expectation(description: "fetch3")

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:100"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { _, _, _ in exp1.fulfill() })

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:101"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { _, _, _ in exp2.fulfill() })

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:102"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { _, _, _ in exp3.fulfill() })

    wait(for: [exp1, exp2, exp3], timeout: 3.0)
    let finalCount: Int
    callLock.lock()
    finalCount = callCount
    callLock.unlock()
    XCTAssertEqual(finalCount, 3)
  }

  // MARK: 6 — Progress reporting for fetch

  @MainActor
  func testFetchContents_progressReporting() {
    let xpc = ResilienceXPCService()
    xpc.onReadObject = { _ in ReadResponse(success: false, errorMessage: "stub") }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let exp = expectation(description: "fetch")
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:50"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { _, _, _ in exp.fulfill() })

    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 7 — Delete item with valid handle via XPC

  @MainActor
  func testDeleteItem_validHandle_succeeds() {
    let xpc = ResilienceXPCService()
    xpc.onDeleteObject = { req in
      XCTAssertEqual(req.objectHandle, 42)
      return WriteResponse(success: true)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let exp = expectation(description: "delete")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest(),
      completionHandler: { error in
        XCTAssertNil(error)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 8 — Create folder via XPC

  @MainActor
  func testCreateFolder_succeeds() {
    let xpc = ResilienceXPCService()
    xpc.onCreateFolder = { req in
      XCTAssertEqual(req.name, "NewFolder")
      return WriteResponse(success: true, newHandle: 300)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "NewFolder", size: nil,
      isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "create folder")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { item, _, _, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        XCTAssertEqual(item?.contentType, .folder)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 9 — Fetch contents with no XPC service returns error

  func testFetchContents_noXPCService_returnsError() {
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { nil })

    let exp = expectation(description: "fetch")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:100"), version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        XCTAssertNil(url)
        XCTAssertNotNil(error)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 10 — Rename via modifyItem

  @MainActor
  func testModifyItem_rename_succeeds() {
    let xpc = ResilienceXPCService()
    xpc.onRenameObject = { req in
      XCTAssertEqual(req.newName, "renamed.txt")
      return WriteResponse(success: true)
    }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 50,
      parentHandle: nil, name: "renamed.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, _, _, error in
        XCTAssertNotNil(resultItem)
        XCTAssertEqual(resultItem?.filename, "renamed.txt")
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }

  // MARK: 11 — Move via modifyItem

  @MainActor
  func testModifyItem_move_succeeds() {
    let xpc = ResilienceXPCService()
    xpc.onMoveObject = { _ in WriteResponse(success: true) }
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil, xpcServiceResolver: { xpc })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 60,
      parentHandle: 10, name: "file.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "move")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .parentItemIdentifier, contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, _, _, error in
        XCTAssertNotNil(resultItem)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 2.0)
  }
}

// MARK: - Domain & Lifecycle Tests

final class FileProviderDomainResilienceTests: XCTestCase {

  // MARK: 1 — MTPDeviceService attach/detach lifecycle

  func testDeviceService_attachThenDetach() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "test-domain-1", displayName: "Test Phone",
      createdAt: Date(), lastSeenAt: Date())

    // attach — should not crash
    await service.deviceAttached(identity: identity)
    // detach — should not crash
    await service.deviceDetached(domainId: identity.domainId)
  }

  // MARK: 2 — MTPDeviceService reconnect lifecycle

  func testDeviceService_reconnect() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "test-domain-2", displayName: "Test Camera",
      createdAt: Date(), lastSeenAt: Date())

    await service.deviceAttached(identity: identity)
    await service.deviceDetached(domainId: identity.domainId)
    await service.deviceReconnected(domainId: identity.domainId)
  }

  // MARK: 3 — Extended absence cleanup does not crash for empty state

  func testDeviceService_cleanupWithNoDevices() async {
    let service = MTPDeviceService()
    await service.cleanupAbsentDevices()
  }

  // MARK: 4 — Signal enumerator for changes via handleDeviceEvent

  func testHandleDeviceEvent_addObject_signalsContainer() {
    nonisolated(unsafe) var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.addObject(
      deviceId: "dev1", storageId: 1, objectHandle: 100, parentHandle: nil))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:1")))
  }

  // MARK: 5 — handleDeviceEvent deleteObject signals container

  func testHandleDeviceEvent_deleteObject_signalsContainer() {
    nonisolated(unsafe) var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.deleteObject(deviceId: "dev1", storageId: 1, objectHandle: 200))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:1")))
  }

  // MARK: 6 — handleDeviceEvent storageAdded signals storage container

  func testHandleDeviceEvent_storageAdded() {
    nonisolated(unsafe) var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.storageAdded(deviceId: "dev1", storageId: 2))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:2")))
  }

  // MARK: 7 — handleDeviceEvent storageRemoved signals root

  func testHandleDeviceEvent_storageRemoved_signalsRoot() {
    nonisolated(unsafe) var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: nil,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.storageRemoved(deviceId: "dev1", storageId: 1))

    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  // MARK: 8 — File provider item properties for various content types

  func testItemProperties_pngContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 10,
      name: "screenshot.png", size: 5000,
      isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.contentType, .png)
  }

  func testItemProperties_mp4ContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 11,
      name: "clip.mp4", size: 1_000_000,
      isDirectory: false, modifiedDate: nil)

    XCTAssertTrue(item.contentType.conforms(to: .movie))
  }

  func testItemProperties_noExtensionFallsBackToData() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 12,
      name: "noext", size: 100,
      isDirectory: false, modifiedDate: nil)

    XCTAssertTrue(item.contentType.conforms(to: .data))
  }

  // MARK: 9 — SyncAnchorStore: record and consume round-trip

  func testSyncAnchorStore_recordAndConsume() {
    let store = SyncAnchorStore()
    let key = "dev1:1"
    let id1 = NSFileProviderItemIdentifier("dev1:1:10")
    let id2 = NSFileProviderItemIdentifier("dev1:1:20")

    store.recordChange(added: [id1], deleted: [id2], for: key)

    let anchor = store.currentAnchor(for: key)
    let result = store.consumeChanges(from: anchor, for: key)

    XCTAssertEqual(result.added.count, 1)
    XCTAssertEqual(result.deleted.count, 1)
    XCTAssertEqual(result.added.first, id1)
    XCTAssertEqual(result.deleted.first, id2)
  }

  // MARK: 10 — SyncAnchorStore: consume empty returns empty

  func testSyncAnchorStore_consumeEmpty() {
    let store = SyncAnchorStore()
    let result = store.consumeChanges(from: Data(), for: "nonexistent")

    XCTAssertEqual(result.added.count, 0)
    XCTAssertEqual(result.deleted.count, 0)
    XCTAssertFalse(result.hasMore)
  }

  // MARK: 11 — Extension enumerator for root container throws (rootContainer not parseable)

  func testEnumerator_rootContainer_throws() {
    let ext = MTPFileProviderExtension(domain: makeTestDomain(), indexReader: nil)
    XCTAssertThrowsError(
      try ext.enumerator(for: .rootContainer, request: NSFileProviderRequest()))
  }

  // MARK: 12 — Item lookup for storage-level identifier without index

  func testItemLookup_storageLevel_noIndex() {
    let ext = MTPFileProviderExtension(domain: makeTestDomain(), indexReader: nil)

    let exp = expectation(description: "lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        exp.fulfill()
      })
    wait(for: [exp], timeout: 1.0)
  }

  // MARK: 13 — Item lookup for object-level via index

  func testItemLookup_objectLevel_fromIndex() async {
    let reader = ResilienceIndexReader()
    await reader.addObject(
      makeObject(handle: 77, name: "cached.txt", sizeBytes: 512))

    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: reader)

    let exp = expectation(description: "lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:77"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        XCTAssertEqual(item?.filename, "cached.txt")
        exp.fulfill()
      })
    await fulfillment(of: [exp], timeout: 2.0)
  }

  // MARK: 14 — Item lookup for missing object returns noSuchItem

  func testItemLookup_missingObject_returnsNoSuchItem() async {
    let reader = ResilienceIndexReader()

    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: reader)

    let exp = expectation(description: "lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:999"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNil(item)
        let nsError = error as NSError?
        XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
        exp.fulfill()
      })
    await fulfillment(of: [exp], timeout: 2.0)
  }

  // MARK: 15 — Storage-level lookup from index

  func testItemLookup_storageLevel_fromIndex() async {
    let reader = ResilienceIndexReader()
    await reader.addStorage(makeStorage(storageId: 5, description: "External SD"))

    let ext = MTPFileProviderExtension(
      domain: makeTestDomain(), indexReader: reader)

    let exp = expectation(description: "lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:5"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNotNil(item)
        XCTAssertNil(error)
        XCTAssertEqual(item?.filename, "External SD")
        exp.fulfill()
      })
    await fulfillment(of: [exp], timeout: 2.0)
  }
}
