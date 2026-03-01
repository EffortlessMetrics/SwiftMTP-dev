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

/// Configurable mock LiveIndexReader used across all test classes in this file.
private actor StubIndexReader: LiveIndexReader {
  private var objectsByDevice: [String: [UInt32: IndexedObject]] = [:]
  private var storagesByDevice: [String: [IndexedStorage]] = [:]
  private var changesByDevice: [String: [IndexedObjectChange]] = [:]
  private var counterByDevice: [String: Int64] = [:]
  private var crawlStateByKey: [String: Date] = [:]
  private var forcedError: Error?

  func setForcedError(_ error: Error?) { forcedError = error }

  func addStorage(_ s: IndexedStorage) {
    storagesByDevice[s.deviceId, default: []].append(s)
  }

  func addObject(_ o: IndexedObject) {
    objectsByDevice[o.deviceId, default: [:]][o.handle] = o
  }

  func setChildren(_ objects: [IndexedObject], deviceId: String) {
    for o in objects { objectsByDevice[deviceId, default: [:]][o.handle] = o }
  }

  func setChanges(_ changes: [IndexedObjectChange], deviceId: String) {
    changesByDevice[deviceId] = changes
  }

  func setCounter(_ counter: Int64, deviceId: String) {
    counterByDevice[deviceId] = counter
  }

  func setCrawlState(_ date: Date?, storageId: UInt32, parentHandle: UInt32?) {
    crawlStateByKey["\(storageId):\(parentHandle?.description ?? "nil")"] = date
  }

  // LiveIndexReader conformance
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
    return crawlStateByKey["\(storageId):\(parentHandle?.description ?? "nil")"]
  }
}

/// Fully controllable XPC service stub. Each operation closure can be customized per test.
private final class StubXPCService: NSObject, MTPXPCService {
  // Closures for customizable behavior; defaults return failure.
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

  func listStorages(
    _ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void
  ) { r(StorageListResponse(success: false)) }

  func listObjects(
    _ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void
  ) { r(ObjectListResponse(success: false)) }

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
private class StubEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
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

/// Mock change observer capturing results.
private class StubChangeObserver: NSObject, NSFileProviderChangeObserver {
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

private func makeDomain(_ id: String = "test") -> NSFileProviderDomain {
  NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "Test")
}

private func makeObject(
  deviceId: String = "dev1", storageId: UInt32 = 1, handle: UInt32, parent: UInt32? = nil,
  name: String, isDirectory: Bool = false, size: UInt64? = nil
) -> IndexedObject {
  IndexedObject(
    deviceId: deviceId, storageId: storageId, handle: handle,
    parentHandle: parent, name: name, pathKey: "/\(name)",
    sizeBytes: isDirectory ? nil : (size ?? 1024), mtime: Date(),
    formatCode: isDirectory ? 0x3001 : 0x3000,
    isDirectory: isDirectory, changeCounter: 1)
}

private func makeStorage(
  deviceId: String = "dev1", storageId: UInt32 = 1, desc: String = "Internal Storage"
) -> IndexedStorage {
  IndexedStorage(
    deviceId: deviceId, storageId: storageId, description: desc,
    capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
}

/// Writes a tiny temp file and returns its URL.
private func writeTempFile(name: String = "fp-test.txt", content: String = "hello") -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
  try? content.data(using: .utf8)!.write(to: url)
  return url
}

// MARK: - 1. Item Enumeration Tests

final class FPEnumerationTests: XCTestCase {

  // 1a) Enumerate storages at device root
  func testEnumerateStoragesAtDeviceRoot() async {
    let reader = StubIndexReader()
    await reader.addStorage(makeStorage(storageId: 1, desc: "Internal"))
    await reader.addStorage(makeStorage(storageId: 2, desc: "SD Card"))

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    let observer = StubEnumerationObserver()
    let exp = expectation(description: "enum storages")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2)
    XCTAssertEqual(observer.items.count, 2)
    let names = observer.items.map(\.filename).sorted()
    XCTAssertEqual(names, ["Internal", "SD Card"])
    XCTAssertNil(observer.nextPage, "Two storages fit in one page")
  }

  // 1b) Enumerate children of a subfolder
  func testEnumerateSubfolderChildren() async {
    let reader = StubIndexReader()
    let parent = makeObject(handle: 10, name: "DCIM", isDirectory: true)
    let child1 = makeObject(handle: 20, parent: 10, name: "IMG_001.jpg")
    let child2 = makeObject(handle: 21, parent: 10, name: "IMG_002.jpg")
    await reader.addObject(parent)
    await reader.addObject(child1)
    await reader.addObject(child2)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: 10, indexReader: reader)

    let observer = StubEnumerationObserver()
    let exp = expectation(description: "enum subfolder")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 2)
    XCTAssertEqual(observer.items.count, 2)
  }

  // 1c) Pagination across multiple pages
  func testEnumerationPagination() async {
    let reader = StubIndexReader()
    // Create 600 objects — should span 2 pages (500 + 100)
    let objects = (1...600).map {
      makeObject(handle: UInt32($0), name: "f\($0).jpg")
    }
    for o in objects { await reader.addObject(o) }

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    // Page 1
    let obs1 = StubEnumerationObserver()
    let exp1 = expectation(description: "page1")
    obs1.onFinish = { exp1.fulfill() }
    enumerator.enumerateItems(
      for: obs1,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)
    await fulfillment(of: [exp1], timeout: 2)
    XCTAssertEqual(obs1.items.count, 500)
    XCTAssertNotNil(obs1.nextPage, "Must supply cursor for next page")

    // Page 2
    let obs2 = StubEnumerationObserver()
    let exp2 = expectation(description: "page2")
    obs2.onFinish = { exp2.fulfill() }
    enumerator.enumerateItems(for: obs2, startingAt: obs1.nextPage!)
    await fulfillment(of: [exp2], timeout: 2)
    XCTAssertEqual(obs2.items.count, 100)
    XCTAssertNil(obs2.nextPage, "Last page must not supply cursor")
  }

  // 1d) Empty folder finishes without error
  func testEnumerateEmptyFolder() async {
    let reader = StubIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: 999, indexReader: reader)

    let observer = StubEnumerationObserver()
    let exp = expectation(description: "empty")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 2)
    XCTAssertEqual(observer.items.count, 0)
    XCTAssertNil(observer.error)
  }

  // 1e) Nil reader finishes gracefully
  func testEnumerateWithNilReader() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: nil)

    let observer = StubEnumerationObserver()
    let exp = expectation(description: "nil reader")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 2)
    XCTAssertEqual(observer.items.count, 0)
  }

  // 1f) Enumeration error propagates to observer
  func testEnumerateReaderError() async {
    let reader = StubIndexReader()
    await reader.setForcedError(NSError(domain: "test", code: 42))

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = StubEnumerationObserver()
    let exp = expectation(description: "error")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByName as! NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 2)
    XCTAssertNotNil(observer.error)
  }
}

// MARK: - 2. File Fetch (Content Materialization) Tests

final class FPFetchContentsTests: XCTestCase {

  @MainActor
  func testFetchContentsSuccessReturnsTempURLAndItem() {
    let reader = StubIndexReader()
    let tempURL = writeTempFile(name: "fetched.bin", content: "binary-data")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let stub = StubXPCService()
    stub.onReadObject = { _ in
      ReadResponse(success: true, tempFileURL: tempURL, fileSize: 11)
    }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader, xpcServiceResolver: { stub })

    let exp = expectation(description: "fetch")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(url)
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "fetched.bin")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testFetchContentsWithCachedMetadata() async {
    let reader = StubIndexReader()
    let obj = makeObject(handle: 42, parent: 10, name: "cached.jpg")
    await reader.addObject(obj)

    let tempURL = writeTempFile(name: "cached-download.jpg")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let stub = StubXPCService()
    stub.onReadObject = { _ in
      ReadResponse(success: true, tempFileURL: tempURL, fileSize: 5)
    }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader, xpcServiceResolver: { stub })

    let exp = expectation(description: "fetch cached")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(url)
      XCTAssertNil(error)
      // Item should use cached name
      if let item = item {
        XCTAssertEqual(item.filename, "cached.jpg")
      }
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }

  @MainActor
  func testFetchContentsNoXPCReturnsError() {
    // Extension with nil XPC resolver → no XPC service available
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { nil })

    let exp = expectation(description: "no xpc")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testFetchContentsForStorageIdentifierFails() {
    let stub = StubXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let exp = expectation(description: "storage id fails")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1"),  // no objectHandle
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 3. File Creation Tests

final class FPCreateItemTests: XCTestCase {

  @MainActor
  func testCreateFolderSuccess() {
    let stub = StubXPCService()
    stub.onCreateFolder = { req in
      XCTAssertEqual(req.name, "NewFolder")
      return WriteResponse(success: true, newHandle: 500)
    }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "NewFolder",
      size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "create folder")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "NewFolder")
      XCTAssertEqual(item?.contentType, .folder)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testCreateFolderFailure() {
    let stub = StubXPCService()
    stub.onCreateFolder = { _ in WriteResponse(success: false) }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "BadFolder",
      size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "create folder fail")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testCreateFileUploadSuccess() {
    let stub = StubXPCService()
    stub.onWriteObject = { req in
      XCTAssertEqual(req.name, "upload.txt")
      return WriteResponse(success: true, newHandle: 600)
    }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    let tmpURL = writeTempFile(name: "fp-upload.txt", content: "file data")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "upload.txt",
      size: 9, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "upload")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "upload.txt")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testCreateFileWithoutStorageIdFails() {
    let stub = StubXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: nil, objectHandle: nil,
      parentHandle: nil, name: "orphan.txt",
      size: 5, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "no storage")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 4. File Modification (Content Update) Tests

final class FPModifyItemTests: XCTestCase {

  @MainActor
  func testModifyContentDeleteThenReupload() {
    let stub = StubXPCService()
    stub.onDeleteObject = { _ in WriteResponse(success: true) }
    stub.onWriteObject = { _ in WriteResponse(success: true, newHandle: 701) }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "updated.txt",
      size: 4, isDirectory: false, modifiedDate: nil)

    let tmpURL = writeTempFile(name: "fp-modify.txt", content: "new content")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let exp = expectation(description: "modify")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .contents, contents: tmpURL,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(resultItem)
      XCTAssertEqual(resultItem?.filename, "updated.txt")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testModifyWithNoChangedFieldsIsNoOp() {
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { nil })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "unchanged.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "no-op")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNotNil(resultItem)
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testModifyItemWithoutXPCIsNoOp() {
    // No XPC service → modifyItem returns the item as-is with no error
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { nil })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "test.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "no xpc modify")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .contents, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      // No contents URL → no-op path
      XCTAssertNotNil(resultItem)
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 5. Item Deletion Tests

final class FPDeleteItemTests: XCTestCase {

  @MainActor
  func testDeleteItemSuccess() {
    let stub = StubXPCService()
    stub.onDeleteObject = { req in
      XCTAssertEqual(req.objectHandle, 42)
      XCTAssertTrue(req.recursive)
      return WriteResponse(success: true)
    }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    let exp = expectation(description: "delete")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testDeleteItemFailureReportsError() {
    let stub = StubXPCService()
    stub.onDeleteObject = { _ in
      WriteResponse(success: false, errorMessage: "device unavailable")
    }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let exp = expectation(description: "delete fail")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testDeleteItemWithoutObjectHandleFails() {
    let stub = StubXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let exp = expectation(description: "delete no handle")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      let code = (error as NSError?)?.code
      XCTAssertEqual(code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 6. Item Renaming / Moving Tests

final class FPRenameAndMoveTests: XCTestCase {

  @MainActor
  func testRenameItem() {
    let stub = StubXPCService()
    stub.onRenameObject = { req in
      XCTAssertEqual(req.newName, "renamed.txt")
      return WriteResponse(success: true)
    }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "renamed.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(resultItem)
      XCTAssertEqual(resultItem?.filename, "renamed.txt")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testRenameFailureReturnsNilItem() {
    let stub = StubXPCService()
    stub.onRenameObject = { _ in WriteResponse(success: false) }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "fail.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename fail")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testMoveItem() {
    let stub = StubXPCService()
    stub.onMoveObject = { req in
      XCTAssertEqual(req.newParentHandle, 99)
      return WriteResponse(success: true)
    }

    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { signaled.append($0) })

    // Item whose parentItemIdentifier encodes the new parent
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 99, name: "moved.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "move")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .parentItemIdentifier, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(resultItem)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  @MainActor
  func testMoveFailureReturnsNilItem() {
    let stub = StubXPCService()
    stub.onMoveObject = { _ in WriteResponse(success: false) }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 99, name: "moved.txt",
      size: 10, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "move fail")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .parentItemIdentifier, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 7. Working Set / Change Tracking Tests

final class FPWorkingSetTests: XCTestCase {

  func testSyncAnchorStoreAddAndDeleteEvents() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let addedId = NSFileProviderItemIdentifier("dev1:1:100")
    let deletedId = NSFileProviderItemIdentifier("dev1:1:200")

    store.recordChange(added: [addedId], deleted: [deletedId], for: key)

    let anchor = store.currentAnchor(for: key)
    let result = store.consumeChanges(from: anchor, for: key)

    XCTAssertEqual(result.added, [addedId])
    XCTAssertEqual(result.deleted, [deletedId])
    XCTAssertFalse(result.hasMore)
  }

  func testSyncAnchorStoreHasMoreBatching() {
    let store = SyncAnchorStore()
    let key = "dev1:1"
    let items = (0..<250).map { NSFileProviderItemIdentifier("dev1:1:\($0)") }
    store.recordChange(added: items, deleted: [], for: key)

    let anchor = store.currentAnchor(for: key)
    let batch1 = store.consumeChanges(from: anchor, for: key)
    XCTAssertEqual(batch1.added.count, 200)
    XCTAssertTrue(batch1.hasMore)

    let batch2 = store.consumeChanges(from: anchor, for: key)
    XCTAssertEqual(batch2.added.count, 50)
    XCTAssertFalse(batch2.hasMore)
  }

  func testEnumerateChangesWithSyncAnchorStore() async {
    let store = SyncAnchorStore()
    let reader = StubIndexReader()

    let obj = makeObject(handle: 42, name: "new.jpg")
    await reader.addObject(obj)

    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:42")],
      deleted: [NSFileProviderItemIdentifier("dev1:1:99")],
      for: "dev1:1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let observer = StubChangeObserver()
    let exp = expectation(description: "changes")
    observer.onFinish = { exp.fulfill() }

    let anchor = NSFileProviderSyncAnchor(store.currentAnchor(for: "dev1:1"))
    enumerator.enumerateChanges(for: observer, from: anchor)
    await fulfillment(of: [exp], timeout: 2)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "new.jpg")
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first?.rawValue, "dev1:1:99")
  }

  func testCurrentSyncAnchorWithSyncAnchorStore() {
    let store = SyncAnchorStore()
    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:1")],
      deleted: [], for: "dev1:1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: nil, syncAnchorStore: store)

    let exp = expectation(description: "anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor)
      XCTAssertEqual(anchor?.rawValue.count, 8)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  func testCurrentSyncAnchorWithNilReaderAndNoStore() {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: nil, syncAnchorStore: nil)

    let exp = expectation(description: "nil anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNil(anchor)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 8. Error Handling (device disconnect, permission denied) Tests

final class FPErrorHandlingTests: XCTestCase {

  @MainActor
  func testDisconnectErrorMapsToServerUnreachable() {
    let disconnectMessages = ["Device not connected", "device disconnected", "USB unavailable"]
    for msg in disconnectMessages {
      let stub = StubXPCService()
      stub.onDeleteObject = { _ in
        WriteResponse(success: false, errorMessage: msg)
      }

      let ext = MTPFileProviderExtension(
        domain: makeDomain("err-\(msg.hashValue)"), indexReader: nil,
        xpcServiceResolver: { stub })

      let exp = expectation(description: "disconnect \(msg)")
      _ = ext.deleteItem(
        identifier: NSFileProviderItemIdentifier("dev1:1:42"),
        baseVersion: NSFileProviderItemVersion(), options: [],
        request: NSFileProviderRequest()
      ) { error in
        let code = (error as NSError?)?.code
        XCTAssertEqual(code, NSFileProviderError.serverUnreachable.rawValue,
                       "'\(msg)' should map to serverUnreachable")
        exp.fulfill()
      }
      wait(for: [exp], timeout: 2)
    }
  }

  @MainActor
  func testGenericErrorMapsToNoSuchItem() {
    let stub = StubXPCService()
    stub.onDeleteObject = { _ in
      WriteResponse(success: false, errorMessage: "permission denied")
    }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let exp = expectation(description: "generic error")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      let code = (error as NSError?)?.code
      XCTAssertEqual(code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testNilErrorMessageMapsToNoSuchItem() {
    let stub = StubXPCService()
    stub.onDeleteObject = { _ in WriteResponse(success: false, errorMessage: nil) }

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let exp = expectation(description: "nil message")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      let code = (error as NSError?)?.code
      XCTAssertEqual(code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  func testIndexReaderErrorPropagatesInEnumerateChanges() async {
    let reader = StubIndexReader()
    await reader.setForcedError(NSError(domain: "test", code: 99))

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: nil)

    let observer = StubChangeObserver()
    let exp = expectation(description: "error changes")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateChanges(
      for: observer, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [exp], timeout: 2)
    XCTAssertNotNil(observer.error)
  }

  func testItemLookupForRootContainerReturnsError() {
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil)

    let exp = expectation(description: "root container")
    _ = ext.item(
      for: .rootContainer, request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  func testItemLookupForCachedObject() async {
    let reader = StubIndexReader()
    let obj = makeObject(handle: 42, name: "cached.txt")
    await reader.addObject(obj)

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader)

    let exp = expectation(description: "cached item")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "cached.txt")
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }

  func testItemLookupForMissingObjectReturnsNoSuchItem() async {
    let reader = StubIndexReader()
    // Don't add any objects

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader)

    let exp = expectation(description: "missing item")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:999"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      let code = (error as NSError?)?.code
      XCTAssertEqual(code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }

  func testItemLookupForStorageLevelIdentifier() async {
    let reader = StubIndexReader()
    await reader.addStorage(makeStorage(storageId: 1, desc: "Internal"))

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader)

    let exp = expectation(description: "storage lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "Internal")
      XCTAssertEqual(item?.contentType, .folder)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }

  func testItemLookupForMissingStorageReturnsNoSuchItem() async {
    let reader = StubIndexReader()
    // Don't add the storage

    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: reader)

    let exp = expectation(description: "missing storage")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:99"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }
}

// MARK: - 9. Thumbnail Generation (content type inference) Tests

final class FPThumbnailTests: XCTestCase {

  func testImageContentTypeForVariousExtensions() {
    let cases: [(String, UTType)] = [
      ("photo.jpg", .jpeg),
      ("photo.jpeg", .jpeg),
      ("image.png", .png),
      ("animation.gif", .gif),
      ("raw.heic", .heic),
    ]

    for (filename, expectedType) in cases {
      let item = MTPFileProviderItem(
        deviceId: "dev1", storageId: 1, objectHandle: 1,
        name: filename, size: 1024, isDirectory: false, modifiedDate: nil)
      XCTAssertEqual(item.contentType, expectedType, "Failed for \(filename)")
    }
  }

  func testVideoContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 1,
      name: "video.mp4", size: 10_000_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, .mpeg4Movie)
  }

  func testDirectoryAlwaysReturnsFolder() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 1,
      name: "photo.jpg",  // Even with image extension, directory → .folder
      size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.contentType, .folder)
  }

  func testNoExtensionDefaultsToData() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 1,
      name: "Makefile", size: 512, isDirectory: false, modifiedDate: nil)
    XCTAssertTrue(item.contentType.conforms(to: .data))
  }
}

// MARK: - 10. Progress Reporting Tests

final class FPProgressTests: XCTestCase {

  func testItemLookupProgressTotalUnitCount() {
    let ext = MTPFileProviderExtension(domain: makeDomain(), indexReader: nil)
    let progress = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      request: NSFileProviderRequest()
    ) { _, _ in }
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  func testFetchContentsProgressTotalUnitCount() {
    let ext = MTPFileProviderExtension(domain: makeDomain(), indexReader: nil)
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in }
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  @MainActor
  func testCreateItemProgressTotalUnitCount() {
    let stub = StubXPCService()
    stub.onWriteObject = { _ in WriteResponse(success: true, newHandle: 1) }
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let tmpURL = writeTempFile(name: "fp-progress.txt")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      name: "p.txt", size: 5, isDirectory: false, modifiedDate: nil)

    let progress = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in }
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  @MainActor
  func testDeleteItemProgressTotalUnitCount() {
    let stub = StubXPCService()
    stub.onDeleteObject = { _ in WriteResponse(success: true) }
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let progress = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { _ in }
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  @MainActor
  func testModifyItemProgressTotalUnitCount() {
    let stub = StubXPCService()
    stub.onRenameObject = { _ in WriteResponse(success: true) }
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil, xpcServiceResolver: { stub })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      name: "r.txt", size: 10, isDirectory: false, modifiedDate: nil)

    let progress = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in }
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  func testProgressCompletesOnSynchronousErrorPath() {
    let ext = MTPFileProviderExtension(domain: makeDomain(), indexReader: nil)

    let exp = expectation(description: "error path complete")
    let progress = ext.item(
      for: .rootContainer, request: NSFileProviderRequest()
    ) { _, _ in exp.fulfill() }

    wait(for: [exp], timeout: 2)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }
}

// MARK: - Device Event Handling Tests

final class FPDeviceEventTests: XCTestCase {

  func testHandleAddObjectEvent() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(
      .addObject(deviceId: "dev1", storageId: 1, objectHandle: 42, parentHandle: 10))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:1")))
  }

  func testHandleDeleteObjectEvent() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(
      .deleteObject(deviceId: "dev1", storageId: 2, objectHandle: 99))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:2")))
  }

  func testHandleStorageAddedEvent() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.storageAdded(deviceId: "dev1", storageId: 3))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:3")))
  }

  func testHandleStorageRemovedEvent() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.storageRemoved(deviceId: "dev1", storageId: 1))

    XCTAssertTrue(signaled.contains(.rootContainer))
  }
}
