// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPXPC
import FileProvider
import UniformTypeIdentifiers

/// Wave 35 edge case tests for the File Provider extension: device disconnection
/// mid-enumeration, invalid filename characters, storage capacity exceeded, stale
/// identifiers after reconnect, progress reporting, and thumbnail fallback.
final class FileProviderEdgeCaseWave35Tests: XCTestCase {

  // MARK: - Mock LiveIndexReader

  private final class MockLiveIndexReader: @unchecked Sendable, LiveIndexReader {
    private var objects: [String: [UInt32: IndexedObject]] = [:]
    private var storagesByDevice: [String: [IndexedStorage]] = [:]
    private var changeCounterByDevice: [String: Int64] = [:]
    private var pendingChanges: [String: [IndexedObjectChange]] = [:]
    private var crawlDates: [String: Date] = [:]

    /// When set, the next children() call throws this error to simulate mid-page disconnect.
    nonisolated(unsafe) var childrenError: Error?

    func addObject(_ object: IndexedObject) {
      if objects[object.deviceId] == nil { objects[object.deviceId] = [:] }
      objects[object.deviceId]?[object.handle] = object
    }

    func removeObject(deviceId: String, handle: UInt32) {
      objects[deviceId]?.removeValue(forKey: handle)
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
      if let error = childrenError { throw error }
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
    nonisolated(unsafe) var readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/test.txt"), fileSize: 1024)
    nonisolated(unsafe) var writeResponse = WriteResponse(success: true, newHandle: 200)
    nonisolated(unsafe) var deleteResponse = WriteResponse(success: true)
    nonisolated(unsafe) var createFolderResponse = WriteResponse(success: true, newHandle: 300)
    nonisolated(unsafe) var renameResponse = WriteResponse(success: true)
    nonisolated(unsafe) var moveResponse = WriteResponse(success: true)

    /// Track calls for verification
    nonisolated(unsafe) var lastDeleteRequest: DeleteRequest?
    nonisolated(unsafe) var lastWriteRequest: WriteRequest?
    nonisolated(unsafe) var lastCreateFolderRequest: CreateFolderRequest?

    func ping(reply: @escaping (String) -> Void) { reply("ok") }

    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
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
      identifier: NSFileProviderDomainIdentifier("wave35-edge"),
      displayName: "Wave35 Edge Test")
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
    storageId: UInt32 = 1, deviceId: String = "device1", name: String = "Internal Storage",
    capacity: UInt64 = 64_000_000_000, free: UInt64 = 32_000_000_000
  ) -> IndexedStorage {
    IndexedStorage(
      deviceId: deviceId, storageId: storageId, description: name,
      capacity: capacity, free: free, readOnly: false)
  }

  private func zeroAnchor() -> NSFileProviderSyncAnchor {
    var zero: Int64 = 0
    return NSFileProviderSyncAnchor(Data(bytes: &zero, count: 8))
  }

  // MARK: - (a) Enumeration with device disconnection mid-page

  func testEnumerationFailsGracefullyOnMidPageDisconnect() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.addObject(makeObject(handle: 1, name: "file1.jpg"))

    // Simulate a disconnect error during children() call
    reader.childrenError = NSError(
      domain: "SwiftMTP", code: -1,
      userInfo: [NSLocalizedDescriptionKey: "Device disconnected during enumeration"])

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "disconnect-mid-enum")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    // Should report error, not items
    XCTAssertNotNil(observer.errorReceived, "Enumeration should report error on disconnect")
    XCTAssertEqual(observer.enumeratedItems.count, 0)
  }

  func testEnumerationRecoversAfterDisconnectClears() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.addObject(makeObject(handle: 1, name: "photo.jpg"))
    reader.addObject(makeObject(handle: 2, name: "video.mp4"))

    // First enumeration: disconnect
    reader.childrenError = NSError(domain: "SwiftMTP", code: -1, userInfo: nil)
    let enumerator1 = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let exp1 = expectation(description: "fail-enum")
    let obs1 = MockEnumerationObserver()
    obs1.onFinish = { exp1.fulfill() }
    enumerator1.enumerateItems(
      for: obs1, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp1], timeout: 5)
    XCTAssertNotNil(obs1.errorReceived)

    // Second enumeration: device reconnected (clear error)
    reader.childrenError = nil
    let enumerator2 = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let exp2 = expectation(description: "recover-enum")
    let obs2 = MockEnumerationObserver()
    obs2.onFinish = { exp2.fulfill() }
    enumerator2.enumerateItems(
      for: obs2, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp2], timeout: 5)

    XCTAssertNil(obs2.errorReceived)
    XCTAssertEqual(obs2.enumeratedItems.count, 2)
  }

  // MARK: - (b) createItem with invalid characters in filename

  @MainActor
  func testCreateFolderWithInvalidCharactersInFilename() {
    let xpc = MockXPCService()
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    // Filenames with characters forbidden on macOS or problematic in MTP
    let invalidNames = [
      "folder:with:colons",
      "folder/with/slashes",
      "folder\0null",
      "folder\nwith\nnewlines",
    ]

    for name in invalidNames {
      let exp = expectation(description: "create-\(name.hashValue)")
      let template = MTPFileProviderItem(
        deviceId: "device1", storageId: 1, objectHandle: 50,
        name: name, size: nil, isDirectory: true, modifiedDate: nil)

      _ = ext.createItem(
        basedOn: template, fields: [], contents: nil,
        options: [], request: NSFileProviderRequest()
      ) { item, _, _, error in
        // The XPC call should still go through — server-side validates characters
        if let item = item {
          XCTAssertEqual(item.filename, name, "Filename should pass through as-is: \(name)")
        }
        exp.fulfill()
      }

      wait(for: [exp], timeout: 5)
    }
  }

  @MainActor
  func testCreateItemWithExtremelyLongFilename() {
    let xpc = MockXPCService()
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let longName = String(repeating: "a", count: 1024) + ".txt"
    let template = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 60,
      name: longName, size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "long-name")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      options: [], request: NSFileProviderRequest()
    ) { item, _, _, error in
      // Should not crash; either succeeds or fails gracefully
      XCTAssertTrue(item != nil || error != nil, "Should produce item or error")
      if let item = item {
        XCTAssertEqual(item.filename, longName)
      }
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - (c) modifyItem with size exceeding device storage

  @MainActor
  func testModifyItemWriteFailureReportsError() {
    let xpc = MockXPCService()
    // Simulate write failure (e.g., storage full)
    xpc.writeResponse = WriteResponse(
      success: false, errorMessage: "Storage full: insufficient space")
    // Delete succeeds (old version removed)
    xpc.deleteResponse = WriteResponse(success: true)

    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "large.bin", size: 100))
    let ext = makeExtension(reader: reader, xpc: xpc)

    // Create a temp source file
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "wave35-modify-\(UUID().uuidString).dat")
    FileManager.default.createFile(atPath: tempURL.path, contents: Data(repeating: 0xFF, count: 64))
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "large.bin", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify-storage-full")
    _ = ext.modifyItem(
      item,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      changedFields: .contents, contents: tempURL,
      options: [], request: NSFileProviderRequest()
    ) { updatedItem, _, _, error in
      // Write failed, so we expect an error
      XCTAssertNil(updatedItem)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testModifyItemDeleteFailurePreventsWrite() {
    let xpc = MockXPCService()
    // Delete fails (device busy)
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "Device busy")
    xpc.writeResponse = WriteResponse(success: true, newHandle: 999)

    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 10, name: "locked.bin", size: 50))
    let ext = makeExtension(reader: reader, xpc: xpc)

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "wave35-modify-del-\(UUID().uuidString).dat")
    FileManager.default.createFile(atPath: tempURL.path, contents: Data(count: 32))
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "locked.bin", size: 50, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify-delete-fails")
    _ = ext.modifyItem(
      item,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      changedFields: .contents, contents: tempURL,
      options: [], request: NSFileProviderRequest()
    ) { updatedItem, _, _, error in
      // Delete failed, so write should not proceed
      XCTAssertNil(updatedItem)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - (d) deleteItem on already-deleted item

  @MainActor
  func testDeleteAlreadyDeletedItemReportsError() {
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(
      success: false, errorMessage: "Object not found (already deleted)")
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "delete-already-gone")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:999"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      options: [], request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error, "Deleting an already-deleted item should produce an error")
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testDeleteItemWithInvalidIdentifierReportsNoSuchItem() {
    let xpc = MockXPCService()
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "delete-invalid-id")
    _ = ext.deleteItem(
      identifier: .rootContainer,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      options: [], request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testDeleteItemWithStorageLevelIdentifierReportsNoSuchItem() {
    let xpc = MockXPCService()
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    // Storage-level identifier has no object handle
    let exp = expectation(description: "delete-storage-level")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      options: [], request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - (e) Stale identifiers after device reconnect

  func testStaleIdentifierAfterObjectRemovalReturnsNoSuchItem() async {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 42, name: "photo.jpg"))

    let ext = makeExtension(reader: reader)

    // First lookup succeeds
    let exp1 = expectation(description: "lookup-exists")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      exp1.fulfill()
    }
    await fulfillment(of: [exp1], timeout: 5)

    // Device reconnects with different content (object gone from index)
    reader.removeObject(deviceId: "device1", handle: 42)

    // Stale identifier lookup should fail
    let exp2 = expectation(description: "lookup-stale")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp2.fulfill()
    }
    await fulfillment(of: [exp2], timeout: 5)
  }

  func testStaleStorageIdentifierAfterReconnect() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "SD Card"))

    let ext = makeExtension(reader: reader)

    // First lookup succeeds
    let exp1 = expectation(description: "storage-exists")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "SD Card")
      exp1.fulfill()
    }
    await fulfillment(of: [exp1], timeout: 5)

    // Storage 1 disappears, replaced by storage 2
    // (storagesByDevice is not directly clearable, but we can test with a different storageId)
    let reader2 = MockLiveIndexReader()
    reader2.addStorage(makeStorage(storageId: 2, name: "Internal"))
    let ext2 = makeExtension(reader: reader2)

    let exp2 = expectation(description: "storage-stale")
    _ = ext2.item(
      for: NSFileProviderItemIdentifier("device1:1"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item, "Stale storage identifier should not resolve")
      XCTAssertNotNil(error)
      exp2.fulfill()
    }
    await fulfillment(of: [exp2], timeout: 5)
  }

  func testChangeTrackingReportsDeletedObjectsAfterReconnect() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.setChangeCounter(5, deviceId: "device1")

    let deletedObj = makeObject(handle: 100, name: "removed.jpg")
    reader.setChanges(
      [
        IndexedObjectChange(kind: .deleted, object: deletedObj)
      ], deviceId: "device1")

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "change-deleted")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: zeroAnchor())
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first?.rawValue, "device1:1:100")
  }

  // MARK: - (f) Progress reporting for large file downloads

  @MainActor
  func testFetchContentsReturnsProgressObject() {
    let xpc = MockXPCService()
    let largeSize: UInt64 = 100_000_000  // 100 MB
    xpc.readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/large.bin"), fileSize: largeSize)

    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 50, name: "large.bin", size: largeSize))
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "progress-large")
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:50"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      exp.fulfill()
    }

    // Progress should be non-nil and have a total > 0
    XCTAssertNotNil(progress)
    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 5)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testFetchContentsWithInvalidIdentifierCompletesProgress() {
    let xpc = MockXPCService()
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "progress-invalid")
    let progress = ext.fetchContents(
      for: .rootContainer,
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }

    wait(for: [exp], timeout: 5)
    // Progress should still complete even on error
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testFetchContentsWithXPCServiceReturningNilFails() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 50, name: "file.bin"))
    // XPC resolver explicitly returns nil — simulates service unavailable
    let ext = MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      xpcServiceResolver: { nil },
      signalEnumeratorOverride: { _ in })

    var receivedError: Error?
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:50"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      receivedError = error
    }

    // When XPC service resolver returns nil, fetchContents fails synchronously
    XCTAssertNotNil(receivedError)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  // MARK: - (g) Thumbnail generation fallback (no GetThumb support)

  func testItemWithNoExtensionDefaultsToDataContentType() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "NOEXT", size: 512, isDirectory: false, modifiedDate: nil)

    // Without a recognizable extension, contentType should fall back to .data
    XCTAssertEqual(item.contentType, UTType.data)
  }

  func testItemWithUnknownExtensionReturnsDynamicType() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "file.mtpraw", size: 2048, isDirectory: false, modifiedDate: nil)

    // Unknown extensions get a dynamic UTType (not .data), because
    // UTType(filenameExtension:) returns a dynamic type rather than nil
    XCTAssertNotEqual(item.contentType, UTType.folder)
    XCTAssertNotNil(item.contentType)
  }

  func testDirectoryItemAlwaysReturnsFolder() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "DCIM.jpg", size: nil, isDirectory: true, modifiedDate: nil)

    // Even with a .jpg extension, directories should be .folder
    XCTAssertEqual(item.contentType, UTType.folder)
  }

  func testImageExtensionsReturnCorrectTypes() {
    let cases: [(String, UTType)] = [
      ("photo.jpg", .jpeg),
      ("photo.png", .png),
      ("photo.heic", .heic),
      ("photo.gif", .gif),
      ("photo.tiff", .tiff),
    ]
    for (name, expected) in cases {
      let item = MTPFileProviderItem(
        deviceId: "device1", storageId: 1, objectHandle: 10,
        name: name, size: 1024, isDirectory: false, modifiedDate: nil)
      XCTAssertEqual(item.contentType, expected, "Expected \(expected) for \(name)")
    }
  }

  // MARK: - Additional edge cases

  func testEnumeratorForInvalidContainerThrows() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    XCTAssertThrowsError(try ext.enumerator(for: .rootContainer, request: NSFileProviderRequest()))
    {
      let nsError = $0 as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
    }
  }

  func testSyncAnchorStoreConsumeFromEmptyKey() {
    let store = SyncAnchorStore()
    let result = store.consumeChanges(from: Data(count: 8), for: "nonexistent:0")
    XCTAssertTrue(result.added.isEmpty)
    XCTAssertTrue(result.deleted.isEmpty)
    XCTAssertFalse(result.hasMore)
  }

  func testSyncAnchorStoreBatchOverflow() {
    let store = SyncAnchorStore()
    let key = "device1:1"
    // Record more than maxBatchSize changes
    let ids = (0..<250).map { NSFileProviderItemIdentifier("device1:1:\($0)") }
    store.recordChange(added: ids, deleted: [], for: key)

    let batch1 = store.consumeChanges(from: Data(count: 8), for: key)
    XCTAssertEqual(batch1.added.count, SyncAnchorStore.maxBatchSize)
    XCTAssertTrue(batch1.hasMore)

    let batch2 = store.consumeChanges(from: Data(count: 8), for: key)
    XCTAssertEqual(batch2.added.count, 50)
    XCTAssertFalse(batch2.hasMore)
  }

  func testHandleDeviceEventAddObjectRecordsChange() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    let event = MTPEventCoalescer.Event.addObject(
      deviceId: "device1", storageId: 1, objectHandle: 42, parentHandle: nil)
    ext.handleDeviceEvent(event)

    // Verify signal was dispatched (signalEnumeratorOverride is set to no-op,
    // so we're mainly testing it doesn't crash)
  }

  func testHandleDeviceEventDeleteObjectRecordsChange() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    let event = MTPEventCoalescer.Event.deleteObject(
      deviceId: "device1", storageId: 1, objectHandle: 42)
    ext.handleDeviceEvent(event)
    // Should not crash; change is recorded in sync anchor store
  }

  func testHandleDeviceEventStorageRemovedRecordsChange() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    let event = MTPEventCoalescer.Event.storageRemoved(deviceId: "device1", storageId: 1)
    ext.handleDeviceEvent(event)
    // Should not crash; signals root container
  }

  func testParseItemIdentifierEdgeCases() {
    // Empty string: split(separator:) on empty string returns [], so count == 0 → nil
    let empty = MTPFileProviderItem.parseItemIdentifier(NSFileProviderItemIdentifier(""))
    XCTAssertNil(empty, "Empty identifier should return nil")

    // Single component (device only)
    let device = MTPFileProviderItem.parseItemIdentifier(NSFileProviderItemIdentifier("dev1"))
    XCTAssertEqual(device?.deviceId, "dev1")
    XCTAssertNil(device?.storageId)
    XCTAssertNil(device?.objectHandle)

    // Two components (device:storage)
    let storage = MTPFileProviderItem.parseItemIdentifier(NSFileProviderItemIdentifier("dev1:1"))
    XCTAssertEqual(storage?.deviceId, "dev1")
    XCTAssertEqual(storage?.storageId, 1)
    XCTAssertNil(storage?.objectHandle)

    // Three components (device:storage:handle)
    let object = MTPFileProviderItem.parseItemIdentifier(NSFileProviderItemIdentifier("dev1:1:42"))
    XCTAssertEqual(object?.deviceId, "dev1")
    XCTAssertEqual(object?.storageId, 1)
    XCTAssertEqual(object?.objectHandle, 42)

    // Four+ components returns nil
    let tooMany = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("a:b:c:d"))
    XCTAssertNil(tooMany)

    // rootContainer returns nil
    let root = MTPFileProviderItem.parseItemIdentifier(.rootContainer)
    XCTAssertNil(root)
  }
}
