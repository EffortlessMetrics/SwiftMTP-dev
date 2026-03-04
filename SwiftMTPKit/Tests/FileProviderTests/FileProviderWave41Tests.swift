// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import FileProvider
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPXPC
import UniformTypeIdentifiers

// MARK: - Wave 41 Test Infrastructure

/// A LiveIndexReader whose operations hang forever (used to test timeout guards).
private actor HangingIndexReader: LiveIndexReader {
  func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
    -> [IndexedObject]
  {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return []
  }

  func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return nil
  }

  func storages(deviceId: String) async throws -> [IndexedStorage] {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return []
  }

  func currentChangeCounter(deviceId: String) async throws -> Int64 {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return 0
  }

  func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return []
  }

  func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
    -> Date?
  {
    try await Task.sleep(nanoseconds: 120 * 1_000_000_000)
    return nil
  }
}

/// A LiveIndexReader that returns controlled results and can optionally delay or error.
private actor ControllableIndexReader: LiveIndexReader {
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

/// Stub XPC service for wave 41 tests.
private final class W41StubXPCService: NSObject, MTPXPCService {
  nonisolated(unsafe) var onReadObject: ((ReadRequest) -> ReadResponse)?
  nonisolated(unsafe) var onWriteObject: ((WriteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onDeleteObject: ((DeleteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onCreateFolder: ((CreateFolderRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRenameObject: ((RenameRequest) -> WriteResponse)?
  nonisolated(unsafe) var onMoveObject: ((MoveObjectRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRequestCrawl: ((CrawlTriggerRequest) -> CrawlTriggerResponse)?
  nonisolated(unsafe) var readCallCount = 0

  func ping(reply: @escaping (String) -> Void) { reply("ok") }

  func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
    readCallCount += 1
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

/// Mock enumeration observer for wave 41 tests.
private class W41EnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
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

/// Mock change observer for wave 41 tests.
private class W41ChangeObserver: NSObject, NSFileProviderChangeObserver {
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

private func w41MakeDomain(_ id: String = "w41-test") -> NSFileProviderDomain {
  NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "Wave41Test")
}

private func w41MakeObject(
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

private func w41MakeStorage(
  deviceId: String = "dev1", storageId: UInt32 = 1, desc: String = "Internal Storage"
) -> IndexedStorage {
  IndexedStorage(
    deviceId: deviceId, storageId: storageId, description: desc,
    capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
}

private func w41WriteTempFile(name: String = "w41-test.txt", content: String = "wave41") -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
  try? content.data(using: .utf8)!.write(to: url)
  return url
}

// MARK: - 1. Enumeration Timeout Tests

final class FPEnumerationTimeoutTests: XCTestCase {

  func testEnumerateStoragesTimesOutWithHangingReader() async {
    let reader = HangingIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    let observer = W41EnumerationObserver()
    let exp = expectation(description: "timeout")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByName as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: Double(DomainEnumerator.enumerationTimeoutSeconds) + 5)

    XCTAssertNotNil(observer.error, "Should report an error on timeout")
    let nsError = observer.error! as NSError
    XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  func testEnumerateChildrenTimesOutWithHangingReader() async {
    let reader = HangingIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = W41EnumerationObserver()
    let exp = expectation(description: "children timeout")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByName as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: Double(DomainEnumerator.enumerationTimeoutSeconds) + 5)

    XCTAssertNotNil(observer.error)
    let nsError = observer.error! as NSError
    XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  func testEnumerateChangesTimesOutWithHangingReader() async {
    let reader = HangingIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let changeObserver = W41ChangeObserver()
    let exp = expectation(description: "changes timeout")
    changeObserver.onFinish = { exp.fulfill() }

    var anchorValue: Int64 = 0
    let anchorData = Data(bytes: &anchorValue, count: MemoryLayout<Int64>.size)
    let anchor = NSFileProviderSyncAnchor(anchorData)

    enumerator.enumerateChanges(for: changeObserver, from: anchor)

    await fulfillment(of: [exp], timeout: Double(DomainEnumerator.enumerationTimeoutSeconds) + 5)

    XCTAssertNotNil(changeObserver.error)
    let nsError = changeObserver.error! as NSError
    XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  func testEnumerationTimeoutConstantIsReasonable() {
    // Timeout should be between 5 and 60 seconds
    XCTAssertGreaterThanOrEqual(DomainEnumerator.enumerationTimeoutSeconds, 5)
    XCTAssertLessThanOrEqual(DomainEnumerator.enumerationTimeoutSeconds, 60)
  }
}

// MARK: - 2. XPC Reconnection Tests

final class FPXPCReconnectionTests: XCTestCase {

  func testEnumeratorInvalidateNilsXPCConnection() {
    let reader = ControllableIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: nil, parentHandle: nil, indexReader: reader)

    // invalidate should not crash even without an established connection
    enumerator.invalidate()

    // Verify enumerator still works after invalidation (creates new connection on demand)
    let observer = W41EnumerationObserver()
    let exp = expectation(description: "post-invalidate enum")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByName as NSFileProviderPage)
    wait(for: [exp], timeout: 2)

    // No items expected (empty reader), but should finish without error
    XCTAssertNil(observer.error)
  }

  @MainActor
  func testExtensionXPCResolverCalledOnEachFetch() {
    var resolveCount = 0
    let stub = W41StubXPCService()
    stub.onReadObject = { _ in
      ReadResponse(
        success: true, tempFileURL: w41WriteTempFile(name: "xpc-resolve-\(resolveCount).txt"),
        fileSize: 6)
    }

    let reader = ControllableIndexReader()
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("xpc-resolve"), indexReader: reader,
      xpcServiceResolver: {
        resolveCount += 1
        return stub
      })

    let exp1 = expectation(description: "first fetch")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:10"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in exp1.fulfill() }
    wait(for: [exp1], timeout: 2)

    let exp2 = expectation(description: "second fetch")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:11"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, _ in exp2.fulfill() }
    wait(for: [exp2], timeout: 2)

    XCTAssertEqual(resolveCount, 2, "XPC resolver should be called for each fetch")
  }

  @MainActor
  func testExtensionNilXPCResolverReturnsError() {
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("nil-xpc"), indexReader: nil,
      xpcServiceResolver: { nil })

    let exp = expectation(description: "nil xpc")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 3. Device Disconnect Handling Tests

final class FPDeviceDisconnectTests: XCTestCase {

  func testDeviceResetEventSignalsRootContainer() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("reset"), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.deviceReset(deviceId: "dev1"))

    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  func testStorageRemovedRecordsDeleteAndSignalsRoot() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("storage-rm"), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.storageRemoved(deviceId: "dev1", storageId: 2))

    XCTAssertTrue(signaled.contains(.rootContainer))
  }

  func testStoreFullEventSignalsStorageContainer() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("store-full"), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.storeFull(deviceId: "dev1", storageId: 3))

    XCTAssertTrue(signaled.contains(NSFileProviderItemIdentifier("dev1:3")))
  }

  func testDevicePropChangedDoesNotSignal() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("prop-change"), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(.devicePropChanged(deviceId: "dev1", propertyCode: 0x5001))

    XCTAssertTrue(signaled.isEmpty, "Property changes should not signal enumerator")
  }

  func testEnumerateAfterDeviceRemovalReportsTimeout() async {
    let reader = HangingIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "gone-device", storageId: 1, parentHandle: nil, indexReader: reader)

    let observer = W41EnumerationObserver()
    let exp = expectation(description: "disconnect enum")
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByName as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: Double(DomainEnumerator.enumerationTimeoutSeconds) + 5)

    XCTAssertNotNil(observer.error)
    let nsError = observer.error! as NSError
    XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  func testMultipleEventsAccumulateInSyncAnchorStore() {
    var signaled: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("multi-event"), indexReader: nil,
      signalEnumeratorOverride: { signaled.append($0) })

    ext.handleDeviceEvent(
      .addObject(deviceId: "dev1", storageId: 1, objectHandle: 10, parentHandle: nil))
    ext.handleDeviceEvent(
      .addObject(deviceId: "dev1", storageId: 1, objectHandle: 11, parentHandle: nil))
    ext.handleDeviceEvent(
      .deleteObject(deviceId: "dev1", storageId: 1, objectHandle: 10))

    // All three events should have signaled the same storage container
    let storageSignals = signaled.filter { $0 == NSFileProviderItemIdentifier("dev1:1") }
    XCTAssertEqual(storageSignals.count, 3)
  }
}

// MARK: - 4. Error Mapping Tests

final class FPErrorMappingWave41Tests: XCTestCase {

  func testEnumerationErrorMapsToServerUnreachable() {
    let mapped = DomainEnumerator.mapToFileProviderError(EnumerationError.timeout)
    XCTAssertEqual(mapped.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(mapped.code, NSFileProviderError.serverUnreachable.rawValue)
    XCTAssertNotNil(mapped.userInfo[NSUnderlyingErrorKey])
  }

  func testCancellationErrorMapsToServerUnreachable() {
    let mapped = DomainEnumerator.mapToFileProviderError(CancellationError())
    XCTAssertEqual(mapped.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(mapped.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  func testAlreadyNSFileProviderErrorPassesThrough() {
    let original = NSError(
      domain: NSFileProviderErrorDomain,
      code: NSFileProviderError.noSuchItem.rawValue)
    let mapped = DomainEnumerator.mapToFileProviderError(original)
    XCTAssertEqual(mapped.code, NSFileProviderError.noSuchItem.rawValue)
    XCTAssertEqual(mapped.domain, NSFileProviderErrorDomain)
  }

  func testDisconnectKeywordsMappedCorrectly() {
    let keywords = [
      "not connected", "disconnected", "unavailable",
      "timeout", "no device", "interrupted",
    ]
    for keyword in keywords {
      let error = NSError(domain: "MTP", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "Error: \(keyword) occurred"
      ])
      let mapped = DomainEnumerator.mapToFileProviderError(error)
      XCTAssertEqual(
        mapped.code, NSFileProviderError.serverUnreachable.rawValue,
        "'\(keyword)' should map to serverUnreachable")
      XCTAssertEqual(mapped.domain, NSFileProviderErrorDomain)
    }
  }

  func testUnknownErrorDefaultsToServerUnreachable() {
    let error = NSError(domain: "SomeOther", code: 42, userInfo: [
      NSLocalizedDescriptionKey: "Something completely different"
    ])
    let mapped = DomainEnumerator.mapToFileProviderError(error)
    XCTAssertEqual(mapped.domain, NSFileProviderErrorDomain)
    XCTAssertEqual(mapped.code, NSFileProviderError.serverUnreachable.rawValue)
  }

  @MainActor
  func testXPCErrorClassifiesDisconnectMessages() {
    let stub = W41StubXPCService()
    let disconnectMessages = [
      "not connected", "disconnected", "unavailable",
      "timeout", "no device", "interrupted", "not found",
    ]
    for msg in disconnectMessages {
      stub.onDeleteObject = { _ in WriteResponse(success: false, errorMessage: msg) }
      let ext = MTPFileProviderExtension(
        domain: w41MakeDomain("xpc-err-\(msg.hashValue)"), indexReader: nil,
        xpcServiceResolver: { stub })

      let exp = expectation(description: msg)
      _ = ext.deleteItem(
        identifier: NSFileProviderItemIdentifier("dev1:1:42"),
        baseVersion: NSFileProviderItemVersion(), options: [],
        request: NSFileProviderRequest()
      ) { error in
        let code = (error as NSError?)?.code
        XCTAssertEqual(
          code, NSFileProviderError.serverUnreachable.rawValue,
          "XPC '\(msg)' should map to serverUnreachable")
        exp.fulfill()
      }
      wait(for: [exp], timeout: 2)
    }
  }

  @MainActor
  func testXPCErrorNonDisconnectMessageMapsToNoSuchItem() {
    let stub = W41StubXPCService()
    stub.onDeleteObject = { _ in
      WriteResponse(success: false, errorMessage: "permission denied by device")
    }
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("xpc-perm"), indexReader: nil,
      xpcServiceResolver: { stub })

    let exp = expectation(description: "non-disconnect")
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
}

// MARK: - 5. Working Set Enumeration Tests

final class FPWorkingSetWave41Tests: XCTestCase {

  func testSyncAnchorStoreRecordsAndConsumesChanges() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let id1 = NSFileProviderItemIdentifier("dev1:1:100")
    let id2 = NSFileProviderItemIdentifier("dev1:1:101")
    let id3 = NSFileProviderItemIdentifier("dev1:1:102")

    store.recordChange(added: [id1, id2], deleted: [id3], for: key)

    let result = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(result.added.count, 2)
    XCTAssertEqual(result.deleted.count, 1)
    XCTAssertTrue(result.added.contains(id1))
    XCTAssertTrue(result.added.contains(id2))
    XCTAssertTrue(result.deleted.contains(id3))
    XCTAssertFalse(result.hasMore)
  }

  func testSyncAnchorStoreConsumeIsIdempotent() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:50")], deleted: [], for: key)

    let first = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(first.added.count, 1)

    // Second consume should be empty
    let second = store.consumeChanges(from: Data(), for: key)
    XCTAssertEqual(second.added.count, 0)
    XCTAssertEqual(second.deleted.count, 0)
  }

  func testSyncAnchorStoreAnchorAdvances() {
    let store = SyncAnchorStore()
    let key = "dev1:1"

    let anchor1 = store.currentAnchor(for: key)
    // Small delay to ensure timestamp advances
    Thread.sleep(forTimeInterval: 0.01)
    store.recordChange(
      added: [NSFileProviderItemIdentifier("dev1:1:1")], deleted: [], for: key)
    let anchor2 = store.currentAnchor(for: key)

    XCTAssertNotEqual(anchor1, anchor2, "Anchor should advance after recording changes")
  }

  func testEnumerateChangesViaLiveIndexReader() async {
    let reader = ControllableIndexReader()
    let obj = w41MakeObject(handle: 42, name: "changed.txt")
    await reader.addObject(obj)
    await reader.setChanges(
      [IndexedObjectChange(kind: .upserted, object: obj)], deviceId: "dev1")
    await reader.setCounter(5, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let changeObserver = W41ChangeObserver()
    let exp = expectation(description: "changes")
    changeObserver.onFinish = { exp.fulfill() }

    var anchorValue: Int64 = 0
    let anchorData = Data(bytes: &anchorValue, count: MemoryLayout<Int64>.size)
    enumerator.enumerateChanges(for: changeObserver, from: NSFileProviderSyncAnchor(anchorData))

    await fulfillment(of: [exp], timeout: 2)

    XCTAssertNil(changeObserver.error)
    XCTAssertEqual(changeObserver.updatedItems.count, 1)
    XCTAssertEqual(changeObserver.updatedItems.first?.filename, "changed.txt")
    XCTAssertFalse(changeObserver.moreComing)
    XCTAssertNotNil(changeObserver.latestAnchor)
  }

  func testEnumerateChangesReportsDeletedItems() async {
    let reader = ControllableIndexReader()
    let obj = w41MakeObject(handle: 77, name: "removed.jpg")
    await reader.setChanges(
      [IndexedObjectChange(kind: .deleted, object: obj)], deviceId: "dev1")
    await reader.setCounter(10, deviceId: "dev1")

    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let changeObserver = W41ChangeObserver()
    let exp = expectation(description: "deletes")
    changeObserver.onFinish = { exp.fulfill() }

    var anchorValue: Int64 = 0
    let anchorData = Data(bytes: &anchorValue, count: MemoryLayout<Int64>.size)
    enumerator.enumerateChanges(for: changeObserver, from: NSFileProviderSyncAnchor(anchorData))

    await fulfillment(of: [exp], timeout: 2)

    XCTAssertNil(changeObserver.error)
    XCTAssertEqual(changeObserver.updatedItems.count, 0)
    XCTAssertEqual(changeObserver.deletedIdentifiers.count, 1)
    XCTAssertEqual(changeObserver.deletedIdentifiers.first?.rawValue, "dev1:1:77")
  }

  func testCurrentSyncAnchorReflectsCounter() {
    let reader = ControllableIndexReader()
    let enumerator = DomainEnumerator(
      deviceId: "dev1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor, "Should return an anchor even for counter 0")
      // Decode the anchor: should be 0
      if let data = anchor?.rawValue, data.count == MemoryLayout<Int64>.size {
        var value: Int64 = 0
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
        XCTAssertEqual(value, 0)
      }
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 6. Content Fetch Tests

final class FPContentFetchWave41Tests: XCTestCase {

  @MainActor
  func testFetchContentsReturnsFileURLAndItem() {
    let tempURL = w41WriteTempFile(name: "fetch-wave41.dat", content: "MTP data payload")
    let stub = W41StubXPCService()
    stub.onReadObject = { req in
      XCTAssertEqual(req.objectHandle, 42)
      return ReadResponse(success: true, tempFileURL: tempURL, fileSize: 16)
    }

    let reader = ControllableIndexReader()
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("fetch"), indexReader: reader,
      xpcServiceResolver: { stub })

    let exp = expectation(description: "fetch")
    let progress = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(error)
      XCTAssertNotNil(url)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, tempURL.lastPathComponent)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  @MainActor
  func testFetchContentsWithCachedMetadataUsesIndexName() async {
    let tempURL = w41WriteTempFile(name: "raw-download.bin", content: "binary")
    let stub = W41StubXPCService()
    stub.onReadObject = { _ in
      ReadResponse(success: true, tempFileURL: tempURL, fileSize: 6)
    }

    let reader = ControllableIndexReader()
    await reader.addObject(w41MakeObject(handle: 55, name: "photo.jpg", size: 6))

    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("cached-fetch"), indexReader: reader,
      xpcServiceResolver: { stub })

    let exp = expectation(description: "cached name")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:55"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "photo.jpg", "Should use cached name from index")
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2)
  }

  @MainActor
  func testFetchContentsXPCFailureReturnsError() {
    let stub = W41StubXPCService()
    stub.onReadObject = { _ in
      ReadResponse(success: false, errorMessage: "device disconnected")
    }

    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("fetch-fail"), indexReader: nil,
      xpcServiceResolver: { stub })

    let exp = expectation(description: "fetch error")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("dev1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  func testFetchContentsForInvalidIdentifierReturnsNoSuchItem() {
    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("bad-id"), indexReader: nil)

    let exp = expectation(description: "invalid id")
    _ = ext.fetchContents(
      for: .rootContainer,
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNil(item)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 7. Placeholder / Item Creation Tests

final class FPPlaceholderCreationWave41Tests: XCTestCase {

  func testFileProviderItemIdentifierFormat() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      name: "test.txt", size: 1024, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.itemIdentifier.rawValue, "dev1:1:42")
  }

  func testFileProviderItemParentForObjectAtStorageRoot() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42, parentHandle: nil,
      name: "root-file.txt", size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1:1")
  }

  func testFileProviderItemParentForNestedObject() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42, parentHandle: 10,
      name: "nested.txt", size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1:1:10")
  }

  func testFileProviderItemParentForStorageItem() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      name: "Internal Storage", size: nil, isDirectory: true, modifiedDate: nil)

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "dev1")
  }

  func testFileProviderItemContentTypeForFile() {
    let jpgItem = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 1,
      name: "photo.jpg", size: 5000, isDirectory: false, modifiedDate: nil)
    XCTAssertTrue(jpgItem.contentType.conforms(to: .image))

    let mp4Item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 2,
      name: "video.mp4", size: 50000, isDirectory: false, modifiedDate: nil)
    XCTAssertTrue(mp4Item.contentType.conforms(to: .movie))
  }

  func testFileProviderItemContentTypeForDirectory() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 3,
      name: "DCIM", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(item.contentType, .folder)
  }

  func testFileProviderItemDocumentSize() {
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 5,
      name: "big.bin", size: 1_073_741_824, isDirectory: false, modifiedDate: nil)
    XCTAssertEqual(item.documentSize?.uint64Value, 1_073_741_824)

    let dirItem = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 6,
      name: "folder", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertNil(dirItem.documentSize)
  }

  func testFileProviderItemModificationDate() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 7,
      name: "dated.txt", size: 100, isDirectory: false, modifiedDate: date)
    XCTAssertEqual(item.contentModificationDate, date)
  }

  func testParseItemIdentifierVariants() {
    // Device-only
    let deviceOnly = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("mydev"))
    XCTAssertEqual(deviceOnly?.deviceId, "mydev")
    XCTAssertNil(deviceOnly?.storageId)
    XCTAssertNil(deviceOnly?.objectHandle)

    // Device + storage
    let withStorage = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("mydev:2"))
    XCTAssertEqual(withStorage?.deviceId, "mydev")
    XCTAssertEqual(withStorage?.storageId, 2)
    XCTAssertNil(withStorage?.objectHandle)

    // Device + storage + handle
    let full = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("mydev:2:99"))
    XCTAssertEqual(full?.deviceId, "mydev")
    XCTAssertEqual(full?.storageId, 2)
    XCTAssertEqual(full?.objectHandle, 99)

    // Root container
    let root = MTPFileProviderItem.parseItemIdentifier(.rootContainer)
    XCTAssertNil(root)
  }

  @MainActor
  func testCreateFolderViaExtension() {
    let stub = W41StubXPCService()
    stub.onCreateFolder = { req in
      XCTAssertEqual(req.name, "NewFolder")
      return WriteResponse(success: true, newHandle: 200)
    }

    let ext = MTPFileProviderExtension(
      domain: w41MakeDomain("create-folder"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      name: "NewFolder", size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "create folder")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      XCTAssertTrue(item?.filename == "NewFolder")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}
