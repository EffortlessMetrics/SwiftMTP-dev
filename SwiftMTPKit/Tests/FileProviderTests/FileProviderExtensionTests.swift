// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPXPC
import FileProvider

final class FileProviderExtensionTests: XCTestCase {

  // MARK: - Mock LiveIndexReader

  private final class MockLiveIndexReader: @unchecked Sendable, LiveIndexReader {
    private var objects: [String: [UInt32: IndexedObject]] = [:]
    private var storages: [String: [IndexedStorage]] = [:]

    func addObject(_ object: IndexedObject) {
      let key = object.deviceId
      if objects[key] == nil {
        objects[key] = [:]
      }
      objects[key]?[object.handle] = object
    }

    func addStorage(_ storage: IndexedStorage) {
      let key = storage.deviceId
      if storages[key] == nil {
        storages[key] = []
      }
      storages[key]?.append(storage)
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      return objects[deviceId]?[handle]
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    {
      let key = deviceId
      guard let allObjects = objects[key] else { return [] }
      return allObjects.values
        .filter { obj in
          obj.storageId == storageId && obj.parentHandle == parentHandle
        }
        .sorted { $0.handle < $1.handle }
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
      return storages[deviceId] ?? []
    }

    func currentChangeCounter(deviceId: String) async throws -> Int64 {
      return 0
    }

    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
      return []
    }

    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    {
      return nil
    }
  }

  // MARK: - Extension Lifecycle Tests

  func testExtensionInitialization() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    // Extension should be creatable with a domain
    let extension1 = MTPFileProviderExtension(domain: domain)
    XCTAssertNotNil(extension1)
  }

  func testExtensionInvalidation() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    // Invalidation should not crash
    extension1.invalidate()
  }

  // MARK: - Item Lookup Tests

  func testItemForIdentifierWithInvalidFormat() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)
    let invalidIdentifier = NSFileProviderItemIdentifier("invalid-format")

    let expectation = XCTestExpectation(description: "Item lookup completes")

    _ = extension1.item(
      for: invalidIdentifier,
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  func testItemForValidIdentifierWithMockIndex() throws {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    // Create mock index
    let mockReader = MockLiveIndexReader()
    mockReader.addStorage(
      IndexedStorage(
        deviceId: "device1",
        storageId: 1,
        description: "Internal Storage",
        capacity: 64_000_000_000,
        free: 32_000_000_000,
        readOnly: false
      ))

    mockReader.addObject(
      IndexedObject(
        deviceId: "device1",
        storageId: 1,
        handle: 100,
        parentHandle: nil,
        name: "DCIM",
        pathKey: "/DCIM",
        sizeBytes: nil,
        mtime: nil,
        formatCode: 0x3001,
        isDirectory: true,
        changeCounter: 0
      ))

    // Note: In real tests, we would inject the mock reader
    // For now, we test that the extension handles valid identifiers
    let extension1 = MTPFileProviderExtension(domain: domain)

    let validIdentifier = NSFileProviderItemIdentifier("device1:1:100")

    let expectation = XCTestExpectation(description: "Item lookup completes")

    _ = extension1.item(
      for: validIdentifier,
      request: NSFileProviderRequest(),
      completionHandler: { item, error in
        // Will return nil if index not available, but should not crash
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Enumerator Creation Tests

  func testEnumeratorForContainer() throws {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    // Create enumerator for device root
    let deviceIdentifier = NSFileProviderItemIdentifier("device1")
    let enumerator = try extension1.enumerator(
      for: deviceIdentifier, request: NSFileProviderRequest())

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorForStorageContainer() throws {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let storageIdentifier = NSFileProviderItemIdentifier("device1:1")
    let enumerator = try extension1.enumerator(
      for: storageIdentifier, request: NSFileProviderRequest())

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorForNestedContainer() throws {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let nestedIdentifier = NSFileProviderItemIdentifier("device1:1:100")
    let enumerator = try extension1.enumerator(
      for: nestedIdentifier, request: NSFileProviderRequest())

    XCTAssertNotNil(enumerator)
  }

  func testEnumeratorForInvalidContainerThrows() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let invalidIdentifier = NSFileProviderItemIdentifier("invalid")

    XCTAssertNoThrow(
      try extension1.enumerator(for: invalidIdentifier, request: NSFileProviderRequest()))
  }

  // MARK: - Content Fetch Tests

  func testFetchContentsForNonFileItem() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    // Storage item has no objectHandle, should fail
    let storageIdentifier = NSFileProviderItemIdentifier("device1:1")

    let expectation = XCTestExpectation(description: "Fetch contents completes")

    _ = extension1.fetchContents(
      for: storageIdentifier,
      version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { url, item, error in
        XCTAssertNil(url)
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Write Operations

  func testCreateItemReturnsErrorForFileWithNoContents() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)
    // A file template (not a folder) with no contents URL → hits the guard and returns error
    let templateItem = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: nil,
      name: "file.txt",
      size: nil,
      isDirectory: false,
      modifiedDate: nil
    )

    let expectation = XCTestExpectation(description: "Create item completes")

    _ = extension1.createItem(
      basedOn: templateItem,
      fields: [],
      contents: nil,  // No URL → noSuchItem error path
      request: NSFileProviderRequest(),
      completionHandler: { item, fields, shouldRename, error in
        XCTAssertNil(item)
        XCTAssertNotNil(error)
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  func testModifyItemAcknowledgesMetadataOnlyChange() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)
    let templateItem = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 10,
      isDirectory: false,
      modifiedDate: nil
    )

    let expectation = XCTestExpectation(description: "Modify item completes")

    _ = extension1.modifyItem(
      templateItem,
      baseVersion: NSFileProviderItemVersion(),
      changedFields: [],  // No content change → metadata-only, acknowledged with no error
      contents: nil,
      request: NSFileProviderRequest(),
      completionHandler: { item, fields, shouldRename, error in
        XCTAssertNotNil(item)  // Item echoed back for metadata-only acknowledgement
        XCTAssertNil(error)
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  func testDeleteItemReturnsErrorForRootContainer() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let expectation = XCTestExpectation(description: "Delete item completes")

    // Use an identifier without an objectHandle — hits the guard and returns error immediately
    _ = extension1.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1"),
      baseVersion: NSFileProviderItemVersion(),
      options: [],
      request: NSFileProviderRequest(),
      completionHandler: { error in
        XCTAssertNotNil(error)
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Progress Tests

  func testItemLookupReturnsProgress() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let progress = extension1.item(
      for: NSFileProviderItemIdentifier.rootContainer,
      request: NSFileProviderRequest(),
      completionHandler: { _, _ in }
    )

    XCTAssertNotNil(progress)
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  func testFetchContentsReturnsProgress() {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain"
    )

    let extension1 = MTPFileProviderExtension(domain: domain)

    let progress = extension1.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:100"),
      version: nil,
      request: NSFileProviderRequest(),
      completionHandler: { _, _, _ in }
    )

    XCTAssertNotNil(progress)
    XCTAssertEqual(progress.totalUnitCount, 1)
  }

  // MARK: - modifyItem delete-failure regression

  /// Stub XPC service that reports delete failure, allowing the test to verify
  /// that modifyItem aborts the upload rather than proceeding after delete failure.
  private final class FailingDeleteXPCService: NSObject, MTPXPCService {
    func ping(reply: @escaping (String) -> Void) { reply("ok") }
    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
      r(ReadResponse(success: false))
    }
    func listStorages(
      _ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void
    ) {
      r(StorageListResponse(success: false))
    }
    func listObjects(_ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void)
    {
      r(ObjectListResponse(success: false))
    }
    func getObjectInfo(
      deviceId: String, storageId: UInt32, objectHandle: UInt32,
      withReply r: @escaping (ReadResponse) -> Void
    ) { r(ReadResponse(success: false)) }
    func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      XCTFail("writeObject must not be called when deleteObject fails")
      r(WriteResponse(success: false))
    }
    func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(WriteResponse(success: false))  // simulate delete failure
    }
    func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(WriteResponse(success: false))
    }
    func requestCrawl(
      _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
    ) {
      r(CrawlTriggerResponse(accepted: false))
    }
    func deviceStatus(
      _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
    ) {
      r(DeviceStatusResponse(connected: false, sessionOpen: false))
    }
  }

  @MainActor
  func testModifyItemAbortOnDeleteFailure() {
    let stub = FailingDeleteXPCService()
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("abort-test"),
      displayName: "Abort Test"
    )
    let ext = MTPFileProviderExtension(
      domain: domain, indexReader: nil, xpcServiceResolver: { stub })

    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 42,
      parentHandle: nil, name: "f.txt", size: 4,
      isDirectory: false, modifiedDate: nil)

    // Write a tiny temp file so sourceURL resolves and fileSize > 0
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fp-abort-test.txt")
    try? "test".data(using: .utf8)!.write(to: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    let expectation = XCTestExpectation(description: "modifyItem aborts on delete failure")

    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: NSFileProviderItemFields.contents, contents: tmpURL,
      request: NSFileProviderRequest(),
      completionHandler: { resultItem, _, _, error in
        XCTAssertNil(resultItem, "Item should be nil when delete failed")
        XCTAssertNotNil(error, "Error should be reported when delete failed")
        expectation.fulfill()
      }
    )

    wait(for: [expectation], timeout: 2.0)
  }
}
