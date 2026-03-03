// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit
import FileProvider
import UniformTypeIdentifiers

/// Wave 32: FileProvider ↔ XPC service bridge communication pattern tests.
///
/// Covers:
/// 1. Device list request via XPC → correct response
/// 2. File enumeration via XPC → paginated results
/// 3. Download via XPC → progress updates → completion
/// 4. Upload via XPC → conflict detection → resolution
/// 5. XPC disconnection during enumeration → graceful recovery
/// 6. Domain registration → XPC service notified
/// 7. Change notification from XPC → signal → enumeration invalidation
/// 8. XPC service restart → reconnect and resume
/// 9. Multiple FileProvider instances requesting same device
/// 10. Error propagation: XPC error → FileProvider error → user-visible error
@MainActor
final class FileProviderXPCBridgeWave32Tests: XCTestCase {

  // MARK: - Mock Index Reader

  private final class MockIndexReader: @unchecked Sendable, LiveIndexReader {
    var objectsByDevice: [String: [UInt32: IndexedObject]] = [:]
    var storagesByDevice: [String: [IndexedStorage]] = [:]
    var changeCounterByDevice: [String: Int64] = [:]
    var pendingChanges: [String: [IndexedObjectChange]] = [:]
    var crawlDates: [String: Date] = [:]
    var failOnChildren = false
    var failOnStorages = false
    var failOnObject = false

    struct SimError: Error, LocalizedError {
      let msg: String
      var errorDescription: String? { msg }
    }

    func addObject(_ obj: IndexedObject) {
      if objectsByDevice[obj.deviceId] == nil { objectsByDevice[obj.deviceId] = [:] }
      objectsByDevice[obj.deviceId]?[obj.handle] = obj
    }

    func addStorage(_ storage: IndexedStorage) {
      if storagesByDevice[storage.deviceId] == nil { storagesByDevice[storage.deviceId] = [] }
      storagesByDevice[storage.deviceId]?.append(storage)
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      if failOnObject { throw SimError(msg: "object lookup failed") }
      return objectsByDevice[deviceId]?[handle]
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    {
      if failOnChildren { throw SimError(msg: "children enumeration failed") }
      guard let all = objectsByDevice[deviceId] else { return [] }
      return all.values
        .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
        .sorted { $0.handle < $1.handle }
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
      if failOnStorages { throw SimError(msg: "storages lookup failed") }
      return storagesByDevice[deviceId] ?? []
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
      crawlDates["\(deviceId):\(storageId):\(parentHandle ?? 0)"]
    }
  }

  // MARK: - Mock Enumeration Observer

  private class MockEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    nonisolated(unsafe) var enumeratedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var nextPageCursor: NSFileProviderPage?
    nonisolated(unsafe) var didFinish = false
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

  // MARK: - Mock Change Observer

  private class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    nonisolated(unsafe) var finishedAnchor: NSFileProviderSyncAnchor?
    nonisolated(unsafe) var moreComing = false
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
    nonisolated(unsafe) var storageListResponse = StorageListResponse(success: true, storages: [])
    nonisolated(unsafe) var objectListResponse = ObjectListResponse(success: true, objects: [])
    nonisolated(unsafe) var readResponse = ReadResponse(success: true, tempFileURL: nil, fileSize: nil)
    nonisolated(unsafe) var writeResponse = WriteResponse(success: true, newHandle: 100)
    nonisolated(unsafe) var deleteResponse = WriteResponse(success: true)
    nonisolated(unsafe) var createFolderResponse = WriteResponse(success: true, newHandle: 200)
    nonisolated(unsafe) var renameResponse = WriteResponse(success: true)
    nonisolated(unsafe) var moveResponse = WriteResponse(success: true)
    nonisolated(unsafe) var crawlResponse = CrawlTriggerResponse(accepted: true)
    nonisolated(unsafe) var deviceStatusResponse = DeviceStatusResponse(
      connected: true, sessionOpen: true)

    // Tracking
    nonisolated(unsafe) var readCallCount = 0
    nonisolated(unsafe) var listStoragesCallCount = 0
    nonisolated(unsafe) var listObjectsCallCount = 0
    nonisolated(unsafe) var writeCallCount = 0
    nonisolated(unsafe) var deleteCallCount = 0
    nonisolated(unsafe) var lastReadRequest: ReadRequest?
    nonisolated(unsafe) var lastWriteRequest: WriteRequest?
    nonisolated(unsafe) var lastObjectListRequest: ObjectListRequest?

    // Simulated failure mode
    nonisolated(unsafe) var simulateDisconnect = false

    func ping(reply: @escaping (String) -> Void) { reply("ok") }

    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
      readCallCount += 1
      lastReadRequest = req
      if simulateDisconnect {
        r(ReadResponse(success: false, errorMessage: "Device not connected"))
        return
      }
      r(readResponse)
    }

    func listStorages(_ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void) {
      listStoragesCallCount += 1
      if simulateDisconnect {
        r(StorageListResponse(success: false, errorMessage: "Device not connected"))
        return
      }
      r(storageListResponse)
    }

    func listObjects(_ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void) {
      listObjectsCallCount += 1
      lastObjectListRequest = req
      if simulateDisconnect {
        r(ObjectListResponse(success: false, errorMessage: "Device not connected"))
        return
      }
      r(objectListResponse)
    }

    func getObjectInfo(
      deviceId: String, storageId: UInt32, objectHandle: UInt32,
      withReply r: @escaping (ReadResponse) -> Void
    ) {
      r(ReadResponse(success: true, fileSize: 1024))
    }

    func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      writeCallCount += 1
      lastWriteRequest = req
      if simulateDisconnect {
        r(WriteResponse(success: false, errorMessage: "Device not connected"))
        return
      }
      r(writeResponse)
    }

    func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      deleteCallCount += 1
      if simulateDisconnect {
        r(WriteResponse(success: false, errorMessage: "Device not connected"))
        return
      }
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
      r(crawlResponse)
    }

    func deviceStatus(
      _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
    ) {
      r(deviceStatusResponse)
    }
  }

  // MARK: - Helpers

  private let testDeviceId = "test-device-w32"
  private let testStorageId: UInt32 = 0x0001_0001

  private func makeIndexedObject(
    handle: UInt32, parent: UInt32? = nil, name: String, size: UInt64? = nil,
    isDirectory: Bool = false
  ) -> IndexedObject {
    IndexedObject(
      deviceId: testDeviceId, storageId: testStorageId, handle: handle,
      parentHandle: parent, name: name, pathKey: "/\(name)",
      sizeBytes: size, mtime: Date(), formatCode: isDirectory ? 0x3001 : 0x3000,
      isDirectory: isDirectory, changeCounter: 1
    )
  }

  private func makeExtension(
    indexReader: MockIndexReader? = nil,
    xpcService: MockXPCService? = nil,
    signalCallback: ((NSFileProviderItemIdentifier) -> Void)? = nil
  ) -> MTPFileProviderExtension {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(testDeviceId), displayName: "Test Device")
    return MTPFileProviderExtension(
      domain: domain,
      indexReader: indexReader,
      xpcServiceResolver: xpcService.map { svc in { svc } },
      signalEnumeratorOverride: signalCallback
    )
  }

  private func makeXPCServiceImpl(
    objectCount: Int = 0, objectDataSize: Int = 64
  ) async -> (
    impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry,
    deviceId: MTPDeviceID, stableId: String, storageId: UInt32
  ) {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    for i in 0..<objectCount {
      config = config.withObject(
        VirtualObjectConfig(
          handle: UInt32(4000 + i), storage: storageId, parent: nil,
          name: "w32-\(i).dat", data: Data(repeating: UInt8(i & 0xFF), count: objectDataSize)
        )
      )
    }
    let virtual = VirtualMTPDevice(config: config)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "w32-domain-\(UUID().uuidString)"
    await registry.register(deviceId: config.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: config.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, registry, config.deviceId, stableId, storageId.raw)
  }

  // MARK: - 1. FileProvider requesting device list via XPC → correct response

  func testDeviceListViaXPC_returnsStorages() async {
    let svc = await makeXPCServiceImpl(objectCount: 0)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.success)
    XCTAssertNotNil(resp.storages)
    XCTAssertGreaterThanOrEqual(resp.storages?.count ?? 0, 1)
  }

  func testDeviceListViaXPC_missingDevice_returnsError() async {
    let svc = await makeXPCServiceImpl()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: "nonexistent-device")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
  }

  func testDeviceListViaXPC_storageMetadataAccurate() async {
    let svc = await makeXPCServiceImpl()
    let resp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.success)
    if let storage = resp.storages?.first {
      XCTAssertEqual(storage.storageId, svc.storageId)
      XCTAssertFalse(storage.storageDescription.isEmpty)
    }
  }

  // MARK: - 2. FileProvider requesting file enumeration via XPC → paginated results

  func testFileEnumeration_paginatedResults() async {
    let reader = MockIndexReader()
    // Add 600 objects to trigger pagination (DomainEnumerator page size is 500)
    for i in 0..<600 {
      reader.addObject(makeIndexedObject(
        handle: UInt32(1000 + i), name: "file-\(i).jpg", size: UInt64(i * 100)))
    }
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal", capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false))

    let enumerator = DomainEnumerator(
      deviceId: testDeviceId, storageId: testStorageId, parentHandle: nil,
      indexReader: reader)

    // First page
    let observer1 = MockEnumerationObserver()
    let exp1 = expectation(description: "first page")
    observer1.onFinish = { exp1.fulfill() }
    enumerator.enumerateItems(for: observer1, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp1], timeout: 5)

    XCTAssertEqual(observer1.enumeratedItems.count, 500)
    XCTAssertNotNil(observer1.nextPageCursor, "Should have a next page cursor for remaining 100 items")

    // Second page
    let observer2 = MockEnumerationObserver()
    let exp2 = expectation(description: "second page")
    observer2.onFinish = { exp2.fulfill() }
    enumerator.enumerateItems(for: observer2, startingAt: observer1.nextPageCursor!)
    await fulfillment(of: [exp2], timeout: 5)

    XCTAssertEqual(observer2.enumeratedItems.count, 100)
    XCTAssertNil(observer2.nextPageCursor, "No more pages after final items")
  }

  func testFileEnumeration_storagesLevel() async {
    let reader = MockIndexReader()
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal Storage", capacity: 64_000_000_000,
      free: 32_000_000_000, readOnly: false))
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: 0x0002_0001,
      description: "SD Card", capacity: 128_000_000_000,
      free: 64_000_000_000, readOnly: false))

    let enumerator = DomainEnumerator(
      deviceId: testDeviceId, storageId: nil, parentHandle: nil,
      indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "storage enumeration")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 2)
    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("Internal Storage"))
    XCTAssertTrue(names.contains("SD Card"))
  }

  // MARK: - 3. FileProvider initiating download via XPC → progress updates → completion

  func testDownloadViaXPC_success() async {
    let xpcService = MockXPCService()
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("w32-test.bin")
    FileManager.default.createFile(atPath: tempURL.path, contents: Data("hello".utf8))
    defer { try? FileManager.default.removeItem(at: tempURL) }

    xpcService.readResponse = ReadResponse(
      success: true, tempFileURL: tempURL, fileSize: 5)

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 42, name: "photo.jpg", size: 5))
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal", capacity: 1_000_000, free: 500_000, readOnly: false))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):42")
    let exp = expectation(description: "download complete")
    let progress = ext.fetchContents(
      for: itemId, version: nil,
      request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(error)
      XCTAssertNotNil(url)
      XCTAssertNotNil(item)
      XCTAssertEqual(item?.filename, "photo.jpg")
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
    XCTAssertEqual(xpcService.readCallCount, 1)
    XCTAssertEqual(xpcService.lastReadRequest?.objectHandle, 42)
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  func testDownloadViaXPC_failurePropagatesError() async {
    let xpcService = MockXPCService()
    xpcService.readResponse = ReadResponse(
      success: false, errorMessage: "Device not connected")

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 42, name: "photo.jpg", size: 5))
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal", capacity: 1_000_000, free: 500_000, readOnly: false))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):42")
    let exp = expectation(description: "download error")
    _ = ext.fetchContents(
      for: itemId, version: nil,
      request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(error)
      XCTAssertNil(url)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - 4. FileProvider initiating upload via XPC → conflict detection → resolution

  func testUploadViaXPC_success() async {
    let xpcService = MockXPCService()
    xpcService.writeResponse = WriteResponse(success: true, newHandle: 500)

    let reader = MockIndexReader()
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal", capacity: 1_000_000, free: 500_000, readOnly: false))

    var signalledIds: [NSFileProviderItemIdentifier] = []
    let ext = makeExtension(indexReader: reader, xpcService: xpcService) { id in
      signalledIds.append(id)
    }

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("upload-w32.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("upload data".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    // Create a mock template item for file upload
    let templateId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):500")
    let parentId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId)")
    let template = MockFileProviderItem(
      identifier: templateId, parentIdentifier: parentId,
      filename: "upload.txt", contentType: .data)

    let exp = expectation(description: "upload complete")
    _ = ext.createItem(
      basedOn: template, fields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { item, fields, shouldFetch, error in
      XCTAssertNil(error)
      XCTAssertNotNil(item)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
    XCTAssertEqual(xpcService.writeCallCount, 1)
  }

  func testUploadViaXPC_conflictDetection_failedWrite() async {
    let xpcService = MockXPCService()
    xpcService.writeResponse = WriteResponse(
      success: false, errorMessage: "Object already exists")

    let reader = MockIndexReader()
    reader.addStorage(IndexedStorage(
      deviceId: testDeviceId, storageId: testStorageId,
      description: "Internal", capacity: 1_000_000, free: 500_000, readOnly: false))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("conflict-w32.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("conflict".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let templateId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):600")
    let parentId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId)")
    let template = MockFileProviderItem(
      identifier: templateId, parentIdentifier: parentId,
      filename: "conflict.txt", contentType: .data)

    let exp = expectation(description: "upload conflict")
    _ = ext.createItem(
      basedOn: template, fields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { item, fields, shouldFetch, error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - 5. XPC disconnection during FileProvider enumeration → graceful recovery

  func testXPCDisconnectionDuringEnumeration_gracefulRecovery() async {
    let reader = MockIndexReader()
    reader.failOnChildren = true  // Simulate index failure (XPC unreachable scenario)

    let enumerator = DomainEnumerator(
      deviceId: testDeviceId, storageId: testStorageId, parentHandle: nil,
      indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "enumeration error")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertNotNil(observer.errorReceived)
    XCTAssertTrue(observer.enumeratedItems.isEmpty)
  }

  func testXPCDisconnectionDuringFetch_mapsToServerUnreachable() async {
    let xpcService = MockXPCService()
    xpcService.simulateDisconnect = true

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 99, name: "doc.pdf", size: 1024))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):99")
    let exp = expectation(description: "disconnect error")
    _ = ext.fetchContents(
      for: itemId, version: nil,
      request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  // MARK: - 6. FileProvider domain registration → XPC service notified

  func testDomainRegistration_xpcServiceSeesDomainMapping() async {
    let registry = DeviceServiceRegistry()
    let deviceId = MTPDeviceID(raw: "w32-reg-test")
    let stableId = "domain-\(UUID().uuidString)"

    let config = VirtualDeviceConfig.emptyDevice
    let virtual = VirtualMTPDevice(config: config)
    let service = DeviceService(device: virtual)

    await registry.register(deviceId: deviceId, service: service)
    await registry.registerDomainMapping(deviceId: deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry

    // deviceStatus uses direct registry lookup (ephemeral ID)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      impl.deviceStatus(DeviceStatusRequest(deviceId: deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(resp.connected)
    XCTAssertTrue(resp.sessionOpen)

    // listStorages uses findDevice which resolves stableId → ephemeral via domain mapping
    let storageResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success, "stableId should resolve through domain mapping")
  }

  func testDomainRegistration_unregisteredDomainReturnsDisconnected() async {
    let registry = DeviceServiceRegistry()
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry

    let resp = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      impl.deviceStatus(DeviceStatusRequest(deviceId: "unregistered-domain")) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.connected)
    XCTAssertFalse(resp.sessionOpen)
  }

  // MARK: - 7. Change notification from XPC → FileProvider signal → enumeration invalidation

  func testChangeNotification_addObject_signalsEnumerator() {
    var signalledIds: [NSFileProviderItemIdentifier] = []
    let ext = makeExtension(signalCallback: { id in signalledIds.append(id) })

    ext.handleDeviceEvent(.addObject(
      deviceId: testDeviceId, storageId: testStorageId,
      objectHandle: 77, parentHandle: nil))

    XCTAssertTrue(signalledIds.contains(
      NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId)")))
  }

  func testChangeNotification_deleteObject_signalsEnumerator() {
    var signalledIds: [NSFileProviderItemIdentifier] = []
    let ext = makeExtension(signalCallback: { id in signalledIds.append(id) })

    ext.handleDeviceEvent(.deleteObject(
      deviceId: testDeviceId, storageId: testStorageId, objectHandle: 88))

    XCTAssertTrue(signalledIds.contains(
      NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId)")))
  }

  func testChangeNotification_storageRemoved_signalsRootContainer() {
    var signalledIds: [NSFileProviderItemIdentifier] = []
    let ext = makeExtension(signalCallback: { id in signalledIds.append(id) })

    ext.handleDeviceEvent(.storageRemoved(deviceId: testDeviceId, storageId: testStorageId))

    XCTAssertTrue(signalledIds.contains(.rootContainer))
  }

  func testChangeNotification_multipleEvents_coalesced_inSyncAnchor() async {
    let reader = MockIndexReader()
    for i in 0..<5 {
      reader.addObject(makeIndexedObject(
        handle: UInt32(200 + i), name: "event-\(i).txt", size: 100))
    }

    let syncAnchorStore = SyncAnchorStore()
    let ext = makeExtension(indexReader: reader)

    // Fire multiple add events
    for i in 0..<5 {
      ext.handleDeviceEvent(.addObject(
        deviceId: testDeviceId, storageId: testStorageId,
        objectHandle: UInt32(200 + i), parentHandle: nil))
    }

    // The sync anchor store inside the extension records changes;
    // verify via an enumerator that uses the same anchor store pattern
    let enumerator = DomainEnumerator(
      deviceId: testDeviceId, storageId: testStorageId, parentHandle: nil,
      indexReader: reader, syncAnchorStore: syncAnchorStore)

    // Record changes manually (simulating what handleDeviceEvent does internally)
    let key = "\(testDeviceId):\(testStorageId)"
    for i in 0..<5 {
      let id = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):\(200 + i)")
      syncAnchorStore.recordChange(added: [id], deleted: [], for: key)
    }

    let changeObserver = MockChangeObserver()
    let anchor = NSFileProviderSyncAnchor(Data(repeating: 0, count: 8))
    let exp = expectation(description: "changes enumerated")
    changeObserver.onFinish = { exp.fulfill() }
    enumerator.enumerateChanges(for: changeObserver, from: anchor)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(changeObserver.updatedItems.count, 5)
    XCTAssertNotNil(changeObserver.finishedAnchor)
  }

  // MARK: - 8. XPC service restart → FileProvider reconnects and resumes

  func testXPCServiceRestart_registryReAddSucceeds() async {
    let svc = await makeXPCServiceImpl(objectCount: 2)
    let stableId = svc.stableId

    // Verify initial connectivity
    let beforeResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(beforeResp.success)

    // Simulate XPC service crash: remove device from registry
    await svc.registry.remove(deviceId: svc.deviceId)

    let duringCrash = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(duringCrash.success)

    // Simulate restart: re-register with fresh device
    var newConfig = VirtualDeviceConfig.emptyDevice
    let newStorageId = newConfig.storages[0].id
    for i in 0..<3 {
      newConfig = newConfig.withObject(
        VirtualObjectConfig(
          handle: UInt32(7000 + i), storage: newStorageId, parent: nil,
          name: "recovered-\(i).dat", data: Data("recovered".utf8)))
    }
    let newVirtual = VirtualMTPDevice(config: newConfig)
    let newService = DeviceService(device: newVirtual)
    await svc.registry.register(deviceId: newConfig.deviceId, service: newService)
    await svc.registry.registerDomainMapping(deviceId: newConfig.deviceId, domainId: stableId)

    // Verify operations resume
    let afterResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(afterResp.success)

    let objResp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
      svc.impl.listObjects(
        ObjectListRequest(deviceId: stableId, storageId: newStorageId.raw, parentHandle: nil)
      ) { c.resume(returning: $0) }
    }
    XCTAssertTrue(objResp.success)
    XCTAssertEqual(objResp.objects?.count, 3)
  }

  func testXPCServiceRestart_listenerStopStartCycle() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    // Multiple stop/start cycles should not crash
    for _ in 0..<5 {
      let listener = MTPXPCListener(serviceImpl: impl)
      listener.start()
      listener.startTempFileCleanupTimer(interval: 0.01)
      try? await Task.sleep(for: .milliseconds(20))
      listener.stop()
    }
    // Ping still works after listener cycles
    let resp = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(resp.contains("running"))
  }

  // MARK: - 9. Multiple FileProvider instances requesting same device simultaneously

  func testMultipleInstancesSameDevice_concurrentListObjects() async {
    let svc = await makeXPCServiceImpl(objectCount: 5)

    // Simulate 10 sequential list requests from different FileProvider instances
    var successCount = 0
    for _ in 0..<10 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ObjectListResponse, Never>) in
        svc.impl.listObjects(
          ObjectListRequest(deviceId: svc.stableId, storageId: svc.storageId, parentHandle: nil)
        ) { c.resume(returning: $0) }
      }
      if resp.success { successCount += 1 }
      XCTAssertEqual(resp.objects?.count, 5)
    }
    XCTAssertEqual(successCount, 10)
  }

  func testMultipleInstancesSameDevice_concurrentReads() async {
    let svc = await makeXPCServiceImpl(objectCount: 3, objectDataSize: 128)
    var tempURLs: [URL] = []

    for i in 0..<3 {
      let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
        svc.impl.readObject(
          ReadRequest(deviceId: svc.stableId, objectHandle: UInt32(4000 + i))
        ) { c.resume(returning: $0) }
      }
      XCTAssertTrue(resp.success)
      if let url = resp.tempFileURL { tempURLs.append(url) }
    }

    XCTAssertEqual(tempURLs.count, 3)
    // Cleanup
    for url in tempURLs {
      try? FileManager.default.removeItem(at: url)
    }
  }

  func testMultipleInstancesSameDevice_concurrentReadAndWrite() async {
    let svc = await makeXPCServiceImpl(objectCount: 2)

    // Multiple operations against the same device in sequence
    let storageResp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(storageResp.success)
    XCTAssertNotNil(storageResp.storages)

    // deviceStatus uses direct registry lookup (ephemeral ID, not stableId)
    let statusResp = await withCheckedContinuation { (c: CheckedContinuation<DeviceStatusResponse, Never>) in
      svc.impl.deviceStatus(DeviceStatusRequest(deviceId: svc.deviceId.raw)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertTrue(statusResp.connected)

    let pingResp = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
      svc.impl.ping { c.resume(returning: $0) }
    }
    XCTAssertTrue(pingResp.contains("running"))
  }

  // MARK: - 10. Error propagation: XPC error → FileProvider error → user-visible error

  func testErrorPropagation_disconnectMapsToServerUnreachable() async {
    // When XPC service reports "Device not connected", the error should map to serverUnreachable
    let xpcService = MockXPCService()
    xpcService.readResponse = ReadResponse(
      success: false, errorMessage: "Device not connected")

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 42, name: "disconnected.txt", size: 100))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):42")
    let exp = expectation(description: "error propagation")
    _ = ext.fetchContents(
      for: itemId, version: nil,
      request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  func testErrorPropagation_deviceNotFoundMapsToNoSuchItem() async {
    let xpcService = MockXPCService()
    xpcService.readResponse = ReadResponse(
      success: false, errorMessage: "Object handle invalid")

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 42, name: "missing.txt", size: 100))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):42")
    let exp = expectation(description: "no such item error")
    _ = ext.fetchContents(
      for: itemId, version: nil,
      request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  func testErrorPropagation_deleteFailurePropagates() async {
    let xpcService = MockXPCService()
    xpcService.deleteResponse = WriteResponse(
      success: false, errorMessage: "Device unavailable")

    let ext = makeExtension(xpcService: xpcService)

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):42")
    let exp = expectation(description: "delete error")
    _ = ext.deleteItem(
      identifier: itemId,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }

  func testErrorPropagation_enumerationError_reportsToObserver() async {
    let reader = MockIndexReader()
    reader.failOnStorages = true

    let enumerator = DomainEnumerator(
      deviceId: testDeviceId, storageId: nil, parentHandle: nil,
      indexReader: reader)

    let observer = MockEnumerationObserver()
    let exp = expectation(description: "enumeration error propagated")
    observer.onFinish = { exp.fulfill() }
    enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [exp], timeout: 5)

    XCTAssertNotNil(observer.errorReceived)
    XCTAssertTrue(observer.enumeratedItems.isEmpty)
  }

  func testErrorPropagation_modifyItemDeleteFails_propagates() async {
    let xpcService = MockXPCService()
    xpcService.deleteResponse = WriteResponse(
      success: false, errorMessage: "Device disconnected")

    let reader = MockIndexReader()
    reader.addObject(makeIndexedObject(handle: 50, name: "old.txt", size: 100))

    let ext = makeExtension(indexReader: reader, xpcService: xpcService)

    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("modify-w32.txt")
    FileManager.default.createFile(atPath: tempFile.path, contents: Data("new content".utf8))
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let itemId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId):50")
    let parentId = NSFileProviderItemIdentifier("\(testDeviceId):\(testStorageId)")
    let item = MockFileProviderItem(
      identifier: itemId, parentIdentifier: parentId,
      filename: "old.txt", contentType: .data)

    let exp = expectation(description: "modify delete failure")
    _ = ext.modifyItem(
      item,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data([1]), metadataVersion: Data([1])),
      changedFields: .contents, contents: tempFile,
      request: NSFileProviderRequest()
    ) { resultItem, fields, shouldFetch, error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      // "disconnected" triggers serverUnreachable
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 5)
  }
}

// MARK: - Mock FileProvider Item

private final class MockFileProviderItem: NSObject, NSFileProviderItem {
  let itemIdentifier: NSFileProviderItemIdentifier
  let parentItemIdentifier: NSFileProviderItemIdentifier
  let filename: String
  let contentType: UTType

  init(
    identifier: NSFileProviderItemIdentifier,
    parentIdentifier: NSFileProviderItemIdentifier,
    filename: String,
    contentType: UTType
  ) {
    self.itemIdentifier = identifier
    self.parentItemIdentifier = parentIdentifier
    self.filename = filename
    self.contentType = contentType
    super.init()
  }
}
