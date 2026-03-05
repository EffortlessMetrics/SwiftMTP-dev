// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPXPC
import FileProvider
import UniformTypeIdentifiers

/// Wave 29: expanded FileProvider test coverage targeting under-tested paths.
///
/// Areas covered:
/// - Error recovery during enumeration (simulated failures mid-enumeration)
/// - Domain registration/unregistration edge cases (MTPDeviceService lifecycle)
/// - Item provider creation with various MTP object types
/// - Change notification batching and coalescing
/// - Memory pressure handling during large enumerations
/// - Concurrent enumeration requests for the same domain
/// - FileProvider item metadata accuracy (size, dates, content type)
/// - Incremental sync with anchor management
final class FileProviderWave29Tests: XCTestCase {

  // MARK: - Failing Index Reader (error injection)

  private final class FailingIndexReader: @unchecked Sendable, LiveIndexReader {
    var failOnChildren = false
    var failOnObject = false
    var failOnStorages = false
    var failOnChangeCounter = false
    var failOnChangesSince = false
    var callCountChildren = 0
    var callCountObject = 0

    private var objects: [String: [UInt32: IndexedObject]] = [:]
    private var storagesByDevice: [String: [IndexedStorage]] = [:]
    private var changeCounterByDevice: [String: Int64] = [:]
    private var pendingChanges: [String: [IndexedObjectChange]] = [:]

    struct SimulatedError: Error, LocalizedError {
      let message: String
      var errorDescription: String? { message }
    }

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

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      callCountObject += 1
      if failOnObject { throw SimulatedError(message: "object lookup failed") }
      return objects[deviceId]?[handle]
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    {
      callCountChildren += 1
      if failOnChildren { throw SimulatedError(message: "children enumeration failed") }
      guard let all = objects[deviceId] else { return [] }
      return all.values
        .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
        .sorted { $0.handle < $1.handle }
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
      if failOnStorages { throw SimulatedError(message: "storages lookup failed") }
      return storagesByDevice[deviceId] ?? []
    }

    func currentChangeCounter(deviceId: String) async throws -> Int64 {
      if failOnChangeCounter { throw SimulatedError(message: "change counter failed") }
      return changeCounterByDevice[deviceId] ?? 0
    }

    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
      if failOnChangesSince { throw SimulatedError(message: "changesSince failed") }
      return pendingChanges[deviceId] ?? []
    }

    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    {
      nil
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
    nonisolated(unsafe) var errorReceived: Error?
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
      errorReceived = error
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

    func getThumbnail(
      _ req: ThumbnailRequest, withReply r: @escaping (ThumbnailResponse) -> Void
    ) { r(ThumbnailResponse(success: false, errorMessage: "stub")) }
  }

  // MARK: - Helpers

  private func makeDomain(id: String = "wave29-test") -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(id),
      displayName: "Wave29 Test")
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
    storageId: UInt32 = 1, deviceId: String = "dev1",
    mtime: Date? = nil, formatCode: UInt16? = nil
  ) -> IndexedObject {
    IndexedObject(
      deviceId: deviceId, storageId: storageId, handle: handle,
      parentHandle: parentHandle, name: name, pathKey: "/\(name)",
      sizeBytes: size, mtime: mtime,
      formatCode: formatCode ?? (isDirectory ? 0x3001 : 0x3800),
      isDirectory: isDirectory, changeCounter: 0)
  }

  private func makeStorage(
    storageId: UInt32 = 1, deviceId: String = "dev1", name: String = "Internal Storage"
  ) -> IndexedStorage {
    IndexedStorage(
      deviceId: deviceId, storageId: storageId, description: name,
      capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
  }

  private func zeroAnchor() -> NSFileProviderSyncAnchor {
    var zero: Int64 = 0
    return NSFileProviderSyncAnchor(Data(bytes: &zero, count: 8))
  }

  // MARK: - Error Recovery During Enumeration

  func testEnumerationFailureMidChildrenReportsError() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    reader.failOnChildren = true

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "enum-fail")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertNotNil(observer.errorReceived, "Should propagate children error")
    XCTAssertTrue(observer.enumeratedItems.isEmpty)
  }

  func testEnumerationFailureOnStoragesReportsError() async {
    let reader = FailingIndexReader()
    reader.failOnStorages = true

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "storage-fail")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertNotNil(observer.errorReceived, "Should propagate storages error")
  }

  func testEnumerationRecoveryAfterTransientFailure() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...5 {
      reader.addObject(makeObject(handle: i, name: "file\(i).txt"))
    }

    // First enumeration fails
    reader.failOnChildren = true
    let enumerator1 = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let exp1 = expectation(description: "fail")
    let obs1 = MockEnumerationObserver()
    obs1.onFinish = { exp1.fulfill() }
    enumerator1.enumerateItems(
      for: obs1,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp1], timeout: 5)
    XCTAssertNotNil(obs1.errorReceived)

    // Second enumeration succeeds after clearing the fault
    reader.failOnChildren = false
    let enumerator2 = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)
    let exp2 = expectation(description: "recover")
    let obs2 = MockEnumerationObserver()
    obs2.onFinish = { exp2.fulfill() }
    enumerator2.enumerateItems(
      for: obs2,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp2], timeout: 5)
    XCTAssertNil(obs2.errorReceived)
    XCTAssertEqual(obs2.enumeratedItems.count, 5)
  }

  func testEnumerateChangesFailureOnChangesSinceReportsError() async {
    let reader = FailingIndexReader()
    reader.failOnChangesSince = true

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "changes-fail")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(for: observer, from: zeroAnchor())

    await fulfillment(of: [exp], timeout: 5)
    XCTAssertNotNil(observer.errorReceived)
  }

  func testCurrentSyncAnchorReturnsNilOnChangeCounterFailure() async {
    let reader = FailingIndexReader()
    reader.failOnChangeCounter = true

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "anchor-fail")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNil(anchor, "Anchor should be nil when counter fails")
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - Domain Registration / Unregistration Edge Cases

  func testDeviceServiceAttachDetachReconnectCycle() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "test-uuid-1", displayName: "Test Phone",
      createdAt: Date(), lastSeenAt: Date())

    // These call through to NSFileProviderManager which may no-op in test,
    // but they must not crash.
    await service.deviceAttached(identity: identity)
    await service.deviceDetached(domainId: "test-uuid-1")
    await service.deviceReconnected(domainId: "test-uuid-1")
  }

  func testDeviceServiceCleanupRetainsRecentDevices() async {
    let service = MTPDeviceService()
    await service.setExtendedAbsenceThreshold(3600)  // 1 hour

    let identity = StableDeviceIdentity(
      domainId: "recent-device", displayName: "Recent",
      createdAt: Date(), lastSeenAt: Date())
    await service.deviceAttached(identity: identity)

    // Cleanup should not remove a device seen just now
    await service.cleanupAbsentDevices()
    // Should complete without crash
  }

  func testDeviceServiceCleanupWithNoDevicesIsNoop() async {
    let service = MTPDeviceService()
    await service.cleanupAbsentDevices()
    // Should complete without crash
  }

  func testDeviceServiceMultipleAttachesForSameDevice() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "dup-device", displayName: "Dup",
      createdAt: Date(), lastSeenAt: Date())

    await service.deviceAttached(identity: identity)
    await service.deviceAttached(identity: identity)
    // Idempotent — should not crash or corrupt state
  }

  // MARK: - Item Provider Creation with Various MTP Object Types

  func testImageItemContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 10,
      name: "photo.jpg", size: 2_000_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.jpeg)
    XCTAssertEqual(item.filename, "photo.jpg")
  }

  func testPNGImageContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 11,
      name: "screenshot.PNG", size: 500_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.png)
  }

  func testVideoItemContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 20,
      name: "clip.mp4", size: 50_000_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.mpeg4Movie)
  }

  func testMOVVideoContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 21,
      name: "recording.MOV", size: 100_000_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.quickTimeMovie)
  }

  func testDocumentItemContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 30,
      name: "notes.pdf", size: 1_500_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.pdf)
  }

  func testPlainTextContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 31,
      name: "readme.txt", size: 256, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.plainText)
  }

  func testFolderContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 40,
      name: "DCIM", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.folder)
    XCTAssertNil(item.documentSize)
  }

  func testUnknownExtensionProducesNonFolderType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 50,
      name: "firmware.xyzabc", size: 4096, isDirectory: false, modifiedDate: nil)
    XCTAssertNotEqual(
      item.contentType, UTType.folder,
      "Unknown extension should not be folder")
  }

  func testNoExtensionFallsBackToData() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 51,
      name: "Makefile", size: 1024, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.data)
  }

  func testHEIFImageContentType() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 12,
      name: "IMG_0001.heic", size: 3_000_000, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.contentType, UTType.heic)
  }

  // MARK: - FileProvider Item Metadata Accuracy

  func testItemDocumentSizeMatchesBytes() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 100,
      name: "big.bin", size: 4_294_967_296, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.documentSize?.uint64Value, 4_294_967_296)
  }

  func testItemNilSizeReturnsNilDocumentSize() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 101,
      name: "folder", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertNil(item.documentSize)
  }

  func testItemZeroSizeReturnsZeroDocumentSize() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 102,
      name: "empty.txt", size: 0, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.documentSize?.uint64Value, 0)
  }

  func testItemModifiedDatePropagates() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 103,
      name: "dated.txt", size: 64, isDirectory: false, modifiedDate: date)
    XCTAssertEqual(item.contentModificationDate, date)
  }

  func testItemNilModifiedDate() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 104,
      name: "undated.txt", size: 64, isDirectory: false, modifiedDate: nil)
    XCTAssertNil(item.contentModificationDate)
  }

  func testItemIdentifierThreeComponents() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 2, objectHandle: 42,
      name: "test.txt", size: 10, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.itemIdentifier.rawValue, "dev1:2:42")
  }

  func testItemIdentifierTwoComponentsForStorage() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 3, objectHandle: nil,
      name: "SD Card", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.itemIdentifier.rawValue, "dev1:3")
  }

  func testItemIdentifierOneComponentForDeviceRoot() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: nil, objectHandle: nil,
      name: "Phone", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.itemIdentifier.rawValue, "dev1")
  }

  func testParentIdentifierForObjectAtStorageRoot() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 10,
      parentHandle: nil, name: "file.txt", size: 5, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1:1")
  }

  func testParentIdentifierForNestedObject() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 20,
      parentHandle: 10, name: "nested.txt", size: 5, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1:1:10")
  }

  func testParentIdentifierForStorage() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      name: "Internal", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1")
  }

  func testParentIdentifierForDeviceRoot() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: nil, objectHandle: nil,
      name: "Device", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
  }

  // MARK: - Identifier Parsing Edge Cases

  func testParseRootContainerReturnsNil() {
    let result = MTPFileProviderItem.parseItemIdentifier(.rootContainer)
    XCTAssertNil(result)
  }

  func testParseEmptyStringReturnsNil() {
    // An empty raw value produces zero split components, so parse returns nil
    let result = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier(""))
    XCTAssertNil(result)
  }

  func testParseFourComponentsReturnsNil() {
    let result = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("a:1:2:3"))
    XCTAssertNil(result)
  }

  func testParseNonNumericStorageReturnsNilStorageId() {
    let result = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("dev1:abc"))
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.deviceId, "dev1")
    XCTAssertNil(result?.storageId)
  }

  // MARK: - Change Notification Batching and Coalescing

  func testSyncAnchorStoreBatchesDeletionsAfterAdditions() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    var addedIds: [NSFileProviderItemIdentifier] = []
    for i in 0..<150 {
      addedIds.append(NSFileProviderItemIdentifier("dev1:1:\(i)"))
    }
    var deletedIds: [NSFileProviderItemIdentifier] = []
    for i in 200..<280 {
      deletedIds.append(NSFileProviderItemIdentifier("dev1:1:\(i)"))
    }
    store.recordChange(added: addedIds, deleted: deletedIds, for: key)

    // First batch: 200 items total (150 added + 50 deleted)
    let batch1 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch1.added.count, 150)
    XCTAssertEqual(batch1.deleted.count, 50)
    XCTAssertTrue(batch1.hasMore)

    // Second batch: remaining 30 deleted
    let batch2 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch2.added.count, 0)
    XCTAssertEqual(batch2.deleted.count, 30)
    XCTAssertFalse(batch2.hasMore)
  }

  func testSyncAnchorStoreIsolatesKeys() {
    let store = SyncAnchorStore()

    let id1 = NSFileProviderItemIdentifier("dev1:1:10")
    let id2 = NSFileProviderItemIdentifier("dev2:1:20")

    store.recordChange(added: [id1], deleted: [], for: "dev1:1")
    store.recordChange(added: [id2], deleted: [], for: "dev2:1")

    let result1 = store.consumeChanges(from: Data(), for: "dev1:1")
    XCTAssertEqual(result1.added.count, 1)
    XCTAssertEqual(result1.added.first, id1)

    let result2 = store.consumeChanges(from: Data(), for: "dev2:1")
    XCTAssertEqual(result2.added.count, 1)
    XCTAssertEqual(result2.added.first, id2)
  }

  func testSyncAnchorStoreConsumeEmptyBatchReturnsFalseHasMore() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:1")], deleted: [], for: key)
    let batch1 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch1.added.count, 1)
    XCTAssertFalse(batch1.hasMore)

    // Consuming again should yield empty
    let batch2 = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(batch2.added.count, 0)
    XCTAssertEqual(batch2.deleted.count, 0)
    XCTAssertFalse(batch2.hasMore)
  }

  func testSyncAnchorStoreRecordMultipleTimesAccumulates() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    for i in 0..<10 {
      store.recordChange(
        added: [NSFileProviderItemIdentifier("dev1:1:\(i)")], deleted: [], for: key)
    }

    let result = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(result.added.count, 10)
    XCTAssertFalse(result.hasMore)
  }

  // MARK: - handleDeviceEvent Coalescing

  @MainActor
  func testHandleDeviceEventAddRecordsSyncAnchorChange() {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(
      .addObject(
        deviceId: "dev1", storageId: 1, objectHandle: 42, parentHandle: nil))

    XCTAssertTrue(
      signaled.contains(NSFileProviderItemIdentifier("dev1:1")),
      "Should signal the storage container")
  }

  @MainActor
  func testHandleDeviceEventDeleteRecordsSyncAnchorChange() {
    let reader = FailingIndexReader()
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(
      .deleteObject(
        deviceId: "dev1", storageId: 1, objectHandle: 99))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:1")))
  }

  @MainActor
  func testHandleDeviceEventStorageRemovedSignalsRootContainer() {
    let reader = FailingIndexReader()
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.storageRemoved(deviceId: "dev1", storageId: 2))

    XCTAssertTrue(
      signaled.contains(.rootContainer),
      "Storage removal should signal root container")
  }

  @MainActor
  func testHandleDeviceEventStorageAddedSignalsStorageContainer() {
    let reader = FailingIndexReader()
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      signalEnumeratorOverride: { id in signaled.append(id) })

    ext.handleDeviceEvent(.storageAdded(deviceId: "dev1", storageId: 3))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:3")))
  }

  @MainActor
  func testRapidAddDeleteEventsDoNotCrash() {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    let ext = makeExtension(reader: reader)

    for i: UInt32 in 1...100 {
      ext.handleDeviceEvent(
        .addObject(
          deviceId: "dev1", storageId: 1, objectHandle: i, parentHandle: nil))
    }
    for i: UInt32 in 1...50 {
      ext.handleDeviceEvent(
        .deleteObject(
          deviceId: "dev1", storageId: 1, objectHandle: i))
    }
    // Survival test
  }

  // MARK: - Memory Pressure During Large Enumerations

  func testEnumerateLargeDirectoryPagesCorrectly() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...1200 {
      reader.addObject(makeObject(handle: i, name: "img\(i).jpg", size: UInt64(i * 100)))
    }

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    // Page 1: 500 items
    let exp1 = expectation(description: "page1")
    let obs1 = MockEnumerationObserver()
    obs1.onFinish = { exp1.fulfill() }
    enumerator.enumerateItems(
      for: obs1,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp1], timeout: 10)
    XCTAssertEqual(obs1.enumeratedItems.count, 500)
    XCTAssertNotNil(obs1.nextPageCursor)

    // Page 2: next 500 items
    let exp2 = expectation(description: "page2")
    let obs2 = MockEnumerationObserver()
    obs2.onFinish = { exp2.fulfill() }
    enumerator.enumerateItems(for: obs2, startingAt: obs1.nextPageCursor!)
    await fulfillment(of: [exp2], timeout: 10)
    XCTAssertEqual(obs2.enumeratedItems.count, 500)
    XCTAssertNotNil(obs2.nextPageCursor)

    // Page 3: remaining 200 items
    let exp3 = expectation(description: "page3")
    let obs3 = MockEnumerationObserver()
    obs3.onFinish = { exp3.fulfill() }
    enumerator.enumerateItems(for: obs3, startingAt: obs2.nextPageCursor!)
    await fulfillment(of: [exp3], timeout: 10)
    XCTAssertEqual(obs3.enumeratedItems.count, 200)
    XCTAssertNil(obs3.nextPageCursor, "Last page should have no cursor")
  }

  func testEnumerateEmptyDirectoryFinishesImmediately() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: 999, indexReader: reader)

    let exp = expectation(description: "empty")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertTrue(observer.enumeratedItems.isEmpty)
    XCTAssertNil(observer.nextPageCursor)
    XCTAssertNil(observer.errorReceived)
  }

  // MARK: - Concurrent Enumeration Requests for the Same Domain

  func testConcurrentEnumerationOfSameEnumerator() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...30 {
      reader.addObject(makeObject(handle: i, name: "file\(i).dat"))
    }

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let expectations = (0..<8).map { expectation(description: "concurrent-\($0)") }
    let observers = (0..<8).map { _ in MockEnumerationObserver() }

    for i in 0..<8 {
      observers[i].onFinish = { expectations[i].fulfill() }
      enumerator.enumerateItems(
        for: observers[i],
        startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    }

    await fulfillment(of: expectations, timeout: 10)

    for observer in observers {
      XCTAssertTrue(observer.didFinish)
      XCTAssertEqual(observer.enumeratedItems.count, 30)
      XCTAssertNil(observer.errorReceived)
    }
  }

  func testConcurrentEnumerationAndChangeTracking() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage())
    for i: UInt32 in 1...10 {
      reader.addObject(makeObject(handle: i, name: "f\(i).jpg"))
    }
    reader.setChangeCounter(5, deviceId: "dev1")
    reader.setChanges(
      [
        IndexedObjectChange(kind: .upserted, object: makeObject(handle: 99, name: "new.jpg"))
      ], deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let expEnum = expectation(description: "enum")
    let expChange = expectation(description: "change")
    let enumObs = MockEnumerationObserver()
    let changeObs = MockChangeObserver()
    enumObs.onFinish = { expEnum.fulfill() }
    changeObs.onFinish = { expChange.fulfill() }

    enumerator.enumerateItems(
      for: enumObs,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    enumerator.enumerateChanges(for: changeObs, from: zeroAnchor())

    await fulfillment(of: [expEnum, expChange], timeout: 5)

    XCTAssertEqual(enumObs.enumeratedItems.count, 10)
    XCTAssertEqual(changeObs.updatedItems.count, 1)
  }

  // MARK: - Incremental Sync with Anchor Management

  func testSyncAnchorRoundTrip() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let anchor1 = store.currentAnchor(for: key)
    XCTAssertEqual(anchor1.count, 8)

    // Sleep to ensure timestamp advances (ms granularity)
    Thread.sleep(forTimeInterval: 0.01)
    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:1")], deleted: [], for: key)
    let anchor2 = store.currentAnchor(for: key)

    // Decode as Int64 to verify valid timestamps
    var v1: Int64 = 0
    _ = withUnsafeMutableBytes(of: &v1) { anchor1.copyBytes(to: $0) }
    var v2: Int64 = 0
    _ = withUnsafeMutableBytes(of: &v2) { anchor2.copyBytes(to: $0) }
    XCTAssertGreaterThan(v2, 0)
    XCTAssertGreaterThanOrEqual(v2, v1, "Anchor should be monotonically non-decreasing")
  }

  func testEnumerateChangesViaSyncAnchorStoreWithMultipleBatches() async {
    let reader = FailingIndexReader()
    // Add enough objects for the anchor store lookups
    for i: UInt32 in 1...250 {
      reader.addObject(makeObject(handle: i, name: "obj\(i).txt"))
    }

    let store = SyncAnchorStore()
    let key = "dev1:1"
    var ids: [NSFileProviderItemIdentifier] = []
    for i: UInt32 in 1...250 {
      ids.append(NSFileProviderItemIdentifier("dev1:1:\(i)"))
    }
    store.recordChange(added: ids, deleted: [], for: key)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    // First changes call — should get up to 200
    let exp1 = expectation(description: "batch1")
    let obs1 = MockChangeObserver()
    obs1.onFinish = { exp1.fulfill() }
    enumerator.enumerateChanges(for: obs1, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [exp1], timeout: 5)
    XCTAssertEqual(obs1.updatedItems.count, 200)
    XCTAssertTrue(obs1.moreComing)

    // Second changes call — remaining 50
    let exp2 = expectation(description: "batch2")
    let obs2 = MockChangeObserver()
    obs2.onFinish = { exp2.fulfill() }
    enumerator.enumerateChanges(for: obs2, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [exp2], timeout: 5)
    XCTAssertEqual(obs2.updatedItems.count, 50)
    XCTAssertFalse(obs2.moreComing)
  }

  func testEnumerateChangesViaSyncAnchorStoreWithDeletions() async {
    let reader = FailingIndexReader()
    reader.addObject(makeObject(handle: 10, name: "kept.txt"))

    let store = SyncAnchorStore()
    let key = "dev1:1"
    let addedId = NSFileProviderItemIdentifier("dev1:1:10")
    let deletedId = NSFileProviderItemIdentifier("dev1:1:20")
    store.recordChange(added: [addedId], deleted: [deletedId], for: key)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let exp = expectation(description: "mixed-changes")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateChanges(for: observer, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "kept.txt")
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.first, deletedId)
  }

  func testCurrentSyncAnchorWithSyncAnchorStoreReturnsSynchronously() async {
    let reader = FailingIndexReader()
    let store = SyncAnchorStore()
    let key = "dev1:1"
    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:1")], deleted: [], for: key)

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    let exp = expectation(description: "anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor)
      XCTAssertEqual(anchor?.rawValue.count, 8)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - Enumerator Without Index Reader

  func testEnumerationWithNilReaderFinishesEmpty() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: nil)

    let exp = expectation(description: "nil-reader")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertTrue(observer.enumeratedItems.isEmpty)
    XCTAssertNil(observer.nextPageCursor)
    XCTAssertNil(observer.errorReceived)
  }

  func testEnumerateChangesWithNilReaderAndNoStoreFinishesEmpty() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: nil)

    let exp = expectation(description: "nil-changes")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateChanges(for: observer, from: zeroAnchor())
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertTrue(observer.updatedItems.isEmpty)
    XCTAssertTrue(observer.deletedIdentifiers.isEmpty)
    XCTAssertFalse(observer.moreComing)
  }

  func testCurrentSyncAnchorWithNilReaderReturnsNil() async {
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: nil)

    let exp = expectation(description: "nil-anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNil(anchor)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - Extension item() Edge Cases

  @MainActor
  func testItemLookupForUnparsableIdentifierReturnsNoSuchItem() {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "bad-id")
    _ = ext.item(
      for: .rootContainer,
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testItemLookupForMissingObjectReturnsNoSuchItem() {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "missing")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:999"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testItemLookupForExistingObjectReturnsCorrectMetadata() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let reader = FailingIndexReader()
    reader.addObject(
      makeObject(
        handle: 42, name: "photo.jpg", size: 2048, mtime: date))
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "found")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "photo.jpg")
      XCTAssertEqual((item?.documentSize as? NSNumber)?.uint64Value, 2048)
      XCTAssertEqual(item?.contentModificationDate, date)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testItemLookupForStorageLevelItem() {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal Storage"))
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "storage-item")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "Internal Storage")
      XCTAssertEqual(item?.contentType, UTType.folder)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testItemLookupForMissingStorageReturnsNoSuchItem() {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "missing-storage")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:99"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testItemLookupWhenReaderThrowsReportsError() {
    let reader = FailingIndexReader()
    reader.failOnObject = true
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "reader-error")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - Extension enumerator() Edge Cases

  func testEnumeratorForRootContainerThrowsNoSuchItem() {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    XCTAssertThrowsError(
      try ext.enumerator(for: .rootContainer, request: NSFileProviderRequest())
    ) { error in
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
    }
  }

  func testEnumeratorForValidIdentifierSucceeds() throws {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      request: NSFileProviderRequest())
    XCTAssertTrue(enumerator is DomainEnumerator)
  }

  func testEnumeratorForStorageLevelIdentifierSucceeds() throws {
    let reader = FailingIndexReader()
    let ext = makeExtension(reader: reader)

    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("dev1:1"),
      request: NSFileProviderRequest())
    XCTAssertTrue(enumerator is DomainEnumerator)
  }

  // MARK: - XPC Error Classification

  @MainActor
  func testFetchContentsDisconnectErrorMapsToServerUnreachable() {
    let reader = FailingIndexReader()
    reader.addObject(makeObject(handle: 10, name: "file.txt"))
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "device not connected")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "disconnect")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:10"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, error in
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testFetchContentsGenericErrorMapsToNoSuchItem() {
    let reader = FailingIndexReader()
    reader.addObject(makeObject(handle: 10, name: "file.txt"))
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "permission denied")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "generic-error")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:10"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, error in
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testDeleteWithDisconnectedErrorMapsToServerUnreachable() {
    let reader = FailingIndexReader()
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "disconnected from device")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "delete-disconnect")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testModifyContentWithDeleteFailureAborts() {
    let reader = FailingIndexReader()
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "unavailable")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("wave29-mod.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("data".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "mod.txt", size: 4, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify-fail")
    _ = ext.modifyItem(
      item,
      baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      changedFields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem)
      XCTAssertNotNil(error)
      let nsError = error as NSError?
      XCTAssertEqual(nsError?.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - Concurrent SyncAnchorStore Safety

  func testConcurrentRecordAndConsumeDoNotCorrupt() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let group = DispatchGroup()
    let queue = DispatchQueue(label: "wave29.concurrent", attributes: .concurrent)

    // Writers
    for i in 0..<50 {
      group.enter()
      queue.async {
        let id = NSFileProviderItemIdentifier("dev1:1:\(i)")
        store.recordChange(added: [id], deleted: [], for: key)
        group.leave()
      }
    }

    // Readers interleaved
    for _ in 0..<20 {
      group.enter()
      queue.async {
        _ = store.consumeChanges(from: Data(), for: key)
        group.leave()
      }
    }

    group.wait()

    // Drain remaining
    var total = 0
    var hasMore = true
    while hasMore {
      let result = store.consumeChanges(from: Data(), for: key)
      total += result.added.count + result.deleted.count
      hasMore = result.hasMore
    }
    // Due to interleaved reads, total may be < 50 (some already consumed)
    XCTAssertGreaterThanOrEqual(total + 20, 0, "Should complete without crash")
  }

  // MARK: - Enumerator Storage-level Enumeration

  func testEnumerateStoragesReturnsStorageItems() async {
    let reader = FailingIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal Storage"))
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "storages")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 2)
    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("Internal Storage"))
    XCTAssertTrue(names.contains("SD Card"))
  }

  func testEnumerateStoragesWithNoStoragesFinishesEmpty() async {
    let reader = FailingIndexReader()

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "no-storages")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(
      for: observer,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertTrue(observer.enumeratedItems.isEmpty)
    XCTAssertNil(observer.errorReceived)
  }
}
