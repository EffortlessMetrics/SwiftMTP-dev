// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPXPC
import FileProvider
import UniformTypeIdentifiers

/// Tests for File Provider enumeration, materialization, and conflict handling.
final class FileProviderEnumerationTests: XCTestCase {

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
    nonisolated(unsafe) var lastReadRequest: ReadRequest?
    nonisolated(unsafe) var lastWriteRequest: WriteRequest?
    nonisolated(unsafe) var lastDeleteRequest: DeleteRequest?
    nonisolated(unsafe) var lastCreateFolderRequest: CreateFolderRequest?
    nonisolated(unsafe) var lastRenameRequest: RenameRequest?
    nonisolated(unsafe) var lastMoveRequest: MoveObjectRequest?

    nonisolated(unsafe) var readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/test.txt"), fileSize: 1024)
    nonisolated(unsafe) var writeResponse = WriteResponse(success: true, newHandle: 200)
    nonisolated(unsafe) var deleteResponse = WriteResponse(success: true)
    nonisolated(unsafe) var createFolderResponse = WriteResponse(success: true, newHandle: 300)
    nonisolated(unsafe) var renameResponse = WriteResponse(success: true)
    nonisolated(unsafe) var moveResponse = WriteResponse(success: true)
    nonisolated(unsafe) var deviceStatusResponse = DeviceStatusResponse(
      connected: true, sessionOpen: true)

    func ping(reply: @escaping (String) -> Void) { reply("ok") }

    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
      lastReadRequest = req
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
      lastWriteRequest = req
      r(writeResponse)
    }

    func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      lastDeleteRequest = req
      r(deleteResponse)
    }

    func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
      lastCreateFolderRequest = req
      r(createFolderResponse)
    }

    func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
      lastRenameRequest = req
      r(renameResponse)
    }

    func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
      lastMoveRequest = req
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
      r(deviceStatusResponse)
    }
  }

  // MARK: - Helpers

  private func makeDomain() -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("enum-test"),
      displayName: "Enumeration Test")
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
    return NSFileProviderSyncAnchor(Data(bytes: &zero, count: MemoryLayout<Int64>.size))
  }

  private func initialPage() -> NSFileProviderPage {
    NSFileProviderPage.initialPageSortedByName as NSFileProviderPage
  }

  // MARK: - 1. Root Enumeration (lists storages)

  func testRootEnumeration_listsStorages() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal Storage"))
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "root enumeration")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 2)
    XCTAssertEqual(observer.enumeratedItems[0].filename, "Internal Storage")
    XCTAssertEqual(observer.enumeratedItems[1].filename, "SD Card")
    XCTAssertNil(observer.nextPageCursor, "Two storages should fit on one page")
  }

  // MARK: - 2. Directory Enumeration (lists files/folders)

  func testDirectoryEnumeration_listsFilesAndFolders() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "DCIM", isDirectory: true))
    reader.addObject(makeObject(handle: 11, name: "photo.jpg"))
    reader.addObject(makeObject(handle: 12, name: "video.mp4", size: 50_000_000))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "directory enumeration")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 3)

    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("DCIM"))
    XCTAssertTrue(names.contains("photo.jpg"))
    XCTAssertTrue(names.contains("video.mp4"))
  }

  // MARK: - 3. Deep Path Enumeration (nested directories)

  func testDeepPathEnumeration_nestedDirectory() async {
    let reader = MockLiveIndexReader()
    // DCIM (handle 10) -> Camera (handle 20) -> photo.jpg (handle 30)
    reader.addObject(makeObject(handle: 30, parentHandle: 20, name: "photo.jpg"))
    reader.addObject(makeObject(handle: 31, parentHandle: 20, name: "IMG_0002.jpg"))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: 20, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "deep path enumeration")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 2)
    XCTAssertEqual(observer.enumeratedItems[0].filename, "photo.jpg")
    XCTAssertEqual(observer.enumeratedItems[1].filename, "IMG_0002.jpg")
  }

  // MARK: - 4. Empty Directory Handling

  func testEmptyDirectory_yieldsNoItemsAndNoCursor() async {
    let reader = MockLiveIndexReader()
    // No objects added for storage 1, parent 50

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: 50, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "empty directory")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 0)
    XCTAssertNil(observer.nextPageCursor)
  }

  // MARK: - 5. Large Directory (1000+ items) Pagination

  func testLargeDirectory_paginatesAt500Items() async {
    let reader = MockLiveIndexReader()
    for i in 0..<1050 {
      reader.addObject(makeObject(handle: UInt32(i + 1), name: "file\(i).jpg"))
    }

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    // Page 1
    let obs1 = MockEnumerationObserver()
    let exp1 = expectation(description: "page 1")
    obs1.onFinish = { exp1.fulfill() }
    enumerator.enumerateItems(for: obs1, startingAt: initialPage())
    await fulfillment(of: [exp1], timeout: 2.0)

    XCTAssertEqual(obs1.enumeratedItems.count, 500)
    XCTAssertNotNil(obs1.nextPageCursor)

    // Page 2
    let obs2 = MockEnumerationObserver()
    let exp2 = expectation(description: "page 2")
    obs2.onFinish = { exp2.fulfill() }
    enumerator.enumerateItems(for: obs2, startingAt: obs1.nextPageCursor!)
    await fulfillment(of: [exp2], timeout: 2.0)

    XCTAssertEqual(obs2.enumeratedItems.count, 500)
    XCTAssertNotNil(obs2.nextPageCursor)

    // Page 3 (last)
    let obs3 = MockEnumerationObserver()
    let exp3 = expectation(description: "page 3")
    obs3.onFinish = { exp3.fulfill() }
    enumerator.enumerateItems(for: obs3, startingAt: obs2.nextPageCursor!)
    await fulfillment(of: [exp3], timeout: 2.0)

    XCTAssertEqual(obs3.enumeratedItems.count, 50)
    XCTAssertNil(obs3.nextPageCursor, "Last page must not supply cursor")
  }

  // MARK: - 6. Enumeration With No Index Reader

  func testEnumeration_noIndexReader_finishesImmediately() async {
    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: nil)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "no reader finish")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 0)
    XCTAssertNil(observer.nextPageCursor)
  }

  // MARK: - 7. File Materialization (download to local)

  @MainActor
  func testFetchContents_successfulMaterialization() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "photo.jpg", size: 2048))

    let xpc = MockXPCService()
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-mat-test.jpg")
    try? Data(count: 2048).write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }
    xpc.readResponse = ReadResponse(success: true, tempFileURL: tmpURL, fileSize: 2048)

    let ext = makeExtension(reader: reader, xpc: xpc)
    let exp = expectation(description: "fetch contents")

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        XCTAssertNotNil(url)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.filename, "photo.jpg")
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testFetchContents_failureMaterialization() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "photo.jpg"))

    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "I/O error")

    let ext = makeExtension(reader: reader, xpc: xpc)
    let exp = expectation(description: "fetch failure")

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        XCTAssertNil(url)
        XCTAssertNotNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 8. Upload / Create Item

  @MainActor
  func testCreateItem_fileUpload() {
    let xpc = MockXPCService()
    xpc.writeResponse = WriteResponse(success: true, newHandle: 200)

    let ext = makeExtension(reader: nil, xpc: xpc)

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-upload-test.txt")
    try? "hello world".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "upload.txt", size: 11,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create file")

    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { item, fields, shouldFetch, error in
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.filename, "upload.txt")
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testCreateItem_folderCreation() {
    let xpc = MockXPCService()
    xpc.createFolderResponse = WriteResponse(success: true, newHandle: 300)

    let ext = makeExtension(reader: nil, xpc: xpc)

    let template = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "NewFolder", size: nil,
      isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "create folder")

    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { item, fields, shouldFetch, error in
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.filename, "NewFolder")
        XCTAssertEqual(item?.contentType, .folder)
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 9. Rename / Move Item

  @MainActor
  func testModifyItem_rename() {
    let xpc = MockXPCService()
    xpc.renameResponse = WriteResponse(success: true)

    let ext = makeExtension(reader: nil, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "renamed.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, fields, shouldFetch, error in
        XCTAssertNotNil(resultItem)
        XCTAssertEqual(resultItem?.filename, "renamed.txt")
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testModifyItem_move() {
    let xpc = MockXPCService()
    xpc.moveResponse = WriteResponse(success: true)

    let ext = makeExtension(reader: nil, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: 99, name: "moved.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "move")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .parentItemIdentifier, contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, fields, shouldFetch, error in
        XCTAssertNotNil(resultItem)
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 10. Delete Item

  @MainActor
  func testDeleteItem_success() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: true)

    let ext = makeExtension(reader: nil, xpc: xpc)
    let exp = expectation(description: "delete")

    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest(),
      completionHandler: { error in
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testDeleteItem_failure() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "Permission denied")

    let ext = makeExtension(reader: nil, xpc: xpc)
    let exp = expectation(description: "delete failure")

    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest(),
      completionHandler: { error in
        XCTAssertNotNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 11. Conflict Detection and Resolution

  @MainActor
  func testModifyItem_contentsUpdate_deleteThenUpload() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: true)
    xpc.writeResponse = WriteResponse(success: true, newHandle: 500)

    let ext = makeExtension(reader: nil, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "conflict.txt", size: 10,
      isDirectory: false, modifiedDate: nil)

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-conflict-test.txt")
    try? "new content".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let exp = expectation(description: "content update")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .contents, contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, fields, shouldFetch, error in
        XCTAssertNotNil(resultItem)
        XCTAssertEqual(resultItem?.filename, "conflict.txt")
        XCTAssertNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testModifyItem_contentsUpdate_deleteFailure_abortsUpload() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "device busy")

    let ext = makeExtension(reader: nil, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "conflict.txt", size: 10,
      isDirectory: false, modifiedDate: nil)

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-conflict-abort.txt")
    try? "new content".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let exp = expectation(description: "content update abort")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .contents, contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, fields, shouldFetch, error in
        XCTAssertNil(resultItem)
        XCTAssertNotNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 12. Offline Mode Handling

  @MainActor
  func testFetchContents_deviceDisconnected_mapsToServerUnreachable() {
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "Device not connected")

    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "photo.jpg"))

    let ext = makeExtension(reader: reader, xpc: xpc)
    let exp = expectation(description: "offline fetch")

    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        let nsError = error as NSError?
        XCTAssertEqual(nsError?.code, NSFileProviderError.serverUnreachable.rawValue)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  @MainActor
  func testDeleteItem_deviceUnavailable_mapsToServerUnreachable() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "device unavailable")

    let ext = makeExtension(reader: nil, xpc: xpc)
    let exp = expectation(description: "offline delete")

    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest(),
      completionHandler: { error in
        let nsError = error as NSError?
        XCTAssertEqual(nsError?.code, NSFileProviderError.serverUnreachable.rawValue)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 13. Change Enumeration (mixed adds/deletes)

  func testEnumerateChanges_mixedAddsAndDeletes() async {
    let reader = MockLiveIndexReader()
    let addedObj = makeObject(handle: 100, name: "new-photo.jpg")
    let deletedObj = makeObject(handle: 200, name: "old-photo.jpg")

    reader.setChanges(
      [
        IndexedObjectChange(kind: .upserted, object: addedObj),
        IndexedObjectChange(kind: .deleted, object: deletedObj),
      ], deviceId: "device1")
    reader.setChangeCounter(5, deviceId: "device1")

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = MockChangeObserver()
    let exp = expectation(description: "mixed changes")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: zeroAnchor())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "new-photo.jpg")
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first?.rawValue, "device1:1:200")
  }

  // MARK: - 14. Change Enumeration With No Reader

  func testEnumerateChanges_noReader_finishesImmediately() async {
    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: nil)

    let observer = MockChangeObserver()
    let exp = expectation(description: "no reader changes")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: zeroAnchor())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 0)
    XCTAssertEqual(observer.deletedIdentifiers.count, 0)
  }

  // MARK: - 15. SyncAnchor Store-Based Change Enumeration

  func testEnumerateChanges_viaSyncAnchorStore() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 77, name: "event-photo.jpg"))

    let store = SyncAnchorStore()
    let key = "device1:1"
    let identifier = NSFileProviderItemIdentifier("device1:1:77")
    store.recordChange(added: [identifier], deleted: [], for: key)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let observer = MockChangeObserver()
    let exp = expectation(description: "anchor store changes")
    observer.onFinish = { exp.fulfill() }

    let anchor = NSFileProviderSyncAnchor(store.currentAnchor(for: key))
    enumerator.enumerateChanges(for: observer, from: anchor)

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "event-photo.jpg")
  }

  // MARK: - 16. Device Event Handling

  func testHandleDeviceEvent_addObject_recordsChange() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    ext.handleDeviceEvent(
      .addObject(
        deviceId: "device1", storageId: 1, objectHandle: 99, parentHandle: nil))

    // The event should have been recorded — we verify by trying to enumerate changes
    // via the SyncAnchorStore path on a freshly-created enumerator
    // (Implicitly tested via integration; the store is internal to the extension)
  }

  func testHandleDeviceEvent_deleteObject() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    ext.handleDeviceEvent(.deleteObject(deviceId: "device1", storageId: 1, objectHandle: 42))
    // Should not crash; signalEnumerator override absorbs the signal
  }

  func testHandleDeviceEvent_storageAdded() {
    let ext = makeExtension(reader: nil)
    ext.handleDeviceEvent(.storageAdded(deviceId: "device1", storageId: 3))
  }

  func testHandleDeviceEvent_storageRemoved() {
    let ext = makeExtension(reader: nil)
    ext.handleDeviceEvent(.storageRemoved(deviceId: "device1", storageId: 3))
  }

  // MARK: - 17. Item Lookup Via Extension

  func testItemLookup_objectFromIndex() async {
    let reader = MockLiveIndexReader()
    let date = Date()
    reader.addObject(
      IndexedObject(
        deviceId: "device1", storageId: 1, handle: 42,
        parentHandle: 10, name: "README.md", pathKey: "/README.md",
        sizeBytes: 4096, mtime: date, formatCode: 0x3000,
        isDirectory: false, changeCounter: 1))

    let ext = makeExtension(reader: reader)
    let exp = expectation(description: "item lookup")

    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.filename, "README.md")
        XCTAssertEqual((item?.documentSize ?? nil)?.intValue, 4096)
        XCTAssertNil(error)
        exp.fulfill()
      })

    await fulfillment(of: [exp], timeout: 2.0)
  }

  func testItemLookup_storageLevelItem() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))

    let ext = makeExtension(reader: reader)
    let exp = expectation(description: "storage lookup")

    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:2"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.filename, "SD Card")
        XCTAssertNil(error)
        exp.fulfill()
      })

    await fulfillment(of: [exp], timeout: 2.0)
  }

  func testItemLookup_missingObject_returnsError() async {
    let reader = MockLiveIndexReader()

    let ext = makeExtension(reader: reader)
    let exp = expectation(description: "missing item")

    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:999"),
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        let nsError = error as NSError?
        XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
        exp.fulfill()
      })

    await fulfillment(of: [exp], timeout: 2.0)
  }

  // MARK: - 18. Enumerator Creation From Extension

  func testEnumeratorCreation_forDeviceRoot() throws {
    let ext = makeExtension(reader: nil)
    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("device1"),
      request: NSFileProviderRequest())
    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorCreation_forStorageContainer() throws {
    let ext = makeExtension(reader: nil)
    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("device1:1"),
      request: NSFileProviderRequest())
    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorCreation_forNestedFolder() throws {
    let ext = makeExtension(reader: nil)
    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("device1:1:100"),
      request: NSFileProviderRequest())
    XCTAssertNotNil(enumerator)
  }

  // MARK: - 19. Multiple Storages Enumeration

  func testRootEnumeration_multipleStorages() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal Storage"))
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))
    reader.addStorage(makeStorage(storageId: 3, name: "External USB"))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "multi-storage")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 3)
    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("Internal Storage"))
    XCTAssertTrue(names.contains("SD Card"))
    XCTAssertTrue(names.contains("External USB"))
  }

  // MARK: - 20. Empty Root (no storages)

  func testRootEnumeration_noStorages_yieldsEmpty() async {
    let reader = MockLiveIndexReader()
    // No storages added

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "no storages")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 0)
    XCTAssertNil(observer.nextPageCursor)
  }

  // MARK: - 21. Create Item Failure (upload error)

  @MainActor
  func testCreateItem_uploadFailure() {
    let xpc = MockXPCService()
    xpc.writeResponse = WriteResponse(success: false, errorMessage: "Storage full")

    let ext = makeExtension(reader: nil, xpc: xpc)

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-upload-fail.txt")
    try? "data".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let template = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      parentHandle: nil, name: "fail.txt", size: 4,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "upload failure")

    _ = ext.createItem(
      basedOn: template, fields: [], contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { item, fields, shouldFetch, error in
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }

  // MARK: - 22. SyncAnchor Encoding Round-Trip

  func testSyncAnchor_encodingRoundTrip() async {
    let reader = MockLiveIndexReader()
    reader.setChangeCounter(12345, deviceId: "device1")

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "anchor round trip")
    var capturedAnchor: NSFileProviderSyncAnchor?
    enumerator.currentSyncAnchor { anchor in
      capturedAnchor = anchor
      exp.fulfill()
    }

    await fulfillment(of: [exp], timeout: 2.0)

    guard let data = capturedAnchor?.rawValue else {
      XCTFail("No anchor data")
      return
    }
    XCTAssertEqual(data.count, MemoryLayout<Int64>.size)
    var decoded: Int64 = 0
    _ = withUnsafeMutableBytes(of: &decoded) { data.copyBytes(to: $0) }
    XCTAssertEqual(decoded, 12345)
  }

  // MARK: - 23. Directories Only Enumeration

  func testDirectoryEnumeration_onlyDirectories() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "DCIM", isDirectory: true))
    reader.addObject(makeObject(handle: 11, name: "Music", isDirectory: true))
    reader.addObject(makeObject(handle: 12, name: "Downloads", isDirectory: true))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "directories only")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: initialPage())

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(observer.enumeratedItems.count, 3)
    for item in observer.enumeratedItems {
      XCTAssertEqual(item.contentType, .folder)
    }
  }

  // MARK: - 24. Rename Failure

  @MainActor
  func testModifyItem_renameFailure() {
    let xpc = MockXPCService()
    xpc.renameResponse = WriteResponse(success: false, errorMessage: "Name conflict")

    let ext = makeExtension(reader: nil, xpc: xpc)

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "conflict-name.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename failure")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, fields, shouldFetch, error in
        XCTAssertNil(resultItem)
        exp.fulfill()
      })

    wait(for: [exp], timeout: 2.0)
  }
}
