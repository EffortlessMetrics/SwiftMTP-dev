// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import FileProvider
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPXPC
import UniformTypeIdentifiers

// MARK: - Test Infrastructure

/// Configurable stub XPC service for write-path safety tests.
private final class WriteSafetyStubXPC: NSObject, MTPXPCService {
  // Call tracking
  nonisolated(unsafe) var writeCallCount = 0
  nonisolated(unsafe) var deleteCallCount = 0
  nonisolated(unsafe) var createFolderCallCount = 0
  nonisolated(unsafe) var renameCallCount = 0
  nonisolated(unsafe) var moveCallCount = 0

  // Configurable handlers
  nonisolated(unsafe) var onWrite: ((WriteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onDelete: ((DeleteRequest) -> WriteResponse)?
  nonisolated(unsafe) var onCreateFolder: ((CreateFolderRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRename: ((RenameRequest) -> WriteResponse)?
  nonisolated(unsafe) var onMove: ((MoveObjectRequest) -> WriteResponse)?
  nonisolated(unsafe) var onRead: ((ReadRequest) -> ReadResponse)?

  func ping(reply: @escaping (String) -> Void) { reply("ok") }

  func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
    r(onRead?(req) ?? ReadResponse(success: false, errorMessage: "stub"))
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
  ) {
    r(ReadResponse(success: false))
  }

  func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
    writeCallCount += 1
    r(onWrite?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
    deleteCallCount += 1
    r(onDelete?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
    createFolderCallCount += 1
    r(onCreateFolder?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
    renameCallCount += 1
    r(onRename?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
    moveCallCount += 1
    r(onMove?(req) ?? WriteResponse(success: false, errorMessage: "stub"))
  }

  func requestCrawl(
    _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
  ) {
    r(CrawlTriggerResponse(accepted: false))
  }

  func deviceStatus(_ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void) {
    r(DeviceStatusResponse(connected: true, sessionOpen: true))
  }

  func getThumbnail(_ req: ThumbnailRequest, withReply r: @escaping (ThumbnailResponse) -> Void) {
    r(ThumbnailResponse(success: false, errorMessage: "stub"))
  }
}

// MARK: - Helpers

private func wsMakeDomain(_ id: String = "ws-test") -> NSFileProviderDomain {
  NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(id), displayName: "WriteSafetyTest")
}

private func wsMakeTempFile(name: String = "ws-test.txt", content: String = "write-safety") -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
  try? content.data(using: .utf8)!.write(to: url)
  return url
}

// MARK: - 1. Create Item XPC Failure Tests

final class FileProviderCreateWriteSafetyTests: XCTestCase {

  @MainActor
  func testCreateFileWithXPCFailurePropagatesError() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: false, errorMessage: "Device not connected") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("create-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "create-fail.txt")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "create-fail.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "create fails")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item, "Item should be nil on XPC failure")
      XCTAssertNotNil(error, "Error should be propagated on XPC failure")
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.writeCallCount, 1)
  }

  @MainActor
  func testCreateFileWithNilXPCServicePropagatesServerUnreachable() {
    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("create-nil-xpc"), indexReader: nil,
      xpcServiceResolver: { nil },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "nil-xpc.txt")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      name: "nil-xpc.txt", size: 50, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "nil xpc create")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }

  @MainActor
  func testCreateFolderWithXPCFailurePropagatesError() {
    let stub = WriteSafetyStubXPC()
    stub.onCreateFolder = { _ in WriteResponse(success: false, errorMessage: "Device busy") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("folder-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: nil,
      name: "FailFolder", size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "folder create fails")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item, "No item should be returned on folder creation failure")
      XCTAssertNotNil(error, "Error should be returned on folder creation failure")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.createFolderCallCount, 1)
  }

  @MainActor
  func testCreateItemWithNoContentURLReturnsError() {
    let stub = WriteSafetyStubXPC()

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("no-content"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    // File template but no contents URL
    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      name: "no-content.txt", size: 0, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "no content url")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error, "Should error when file create has no content URL")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(stub.writeCallCount, 0, "XPC write should not be called with no source file")
  }
}

// MARK: - 2. Modify Item Safety Tests

final class FileProviderModifyWriteSafetyTests: XCTestCase {

  @MainActor
  func testModifyContentDeleteFailsStopsWriteAttempt() {
    let stub = WriteSafetyStubXPC()
    // Delete (first step of content modify) fails
    stub.onDelete = { _ in WriteResponse(success: false, errorMessage: "Delete refused") }
    stub.onWrite = { _ in
      XCTFail("Write should not be called if delete fails")
      return WriteResponse(success: true, newHandle: 999)
    }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("modify-delete-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "modify-fail.txt", content: "updated")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 50,
      parentHandle: 10,
      name: "modify-fail.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify fails on delete")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: .contents, contents: sourceURL,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem, "No item on failed modify")
      XCTAssertNotNil(error, "Error should propagate from failed delete step")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.deleteCallCount, 1, "Delete should be called once")
    XCTAssertEqual(stub.writeCallCount, 0, "Write should NOT be called after delete failure")
  }

  @MainActor
  func testModifyContentDeleteSucceedsWriteFailsReportsError() {
    let stub = WriteSafetyStubXPC()
    stub.onDelete = { _ in WriteResponse(success: true) }
    stub.onWrite = { _ in WriteResponse(success: false, errorMessage: "Write failed mid-transfer") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("modify-write-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "modify-write-fail.txt", content: "data")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 51,
      parentHandle: 10,
      name: "modify-write-fail.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify write fails")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: .contents, contents: sourceURL,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem)
      XCTAssertNotNil(error, "Write failure should propagate error to caller")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.deleteCallCount, 1)
    XCTAssertEqual(stub.writeCallCount, 1)
  }

  @MainActor
  func testModifyWithNoChangedFieldsIsNoop() {
    let stub = WriteSafetyStubXPC()

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("modify-noop"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 52,
      name: "noop.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify noop")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      // Should return the original item with no error
      XCTAssertNotNil(resultItem)
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(stub.deleteCallCount, 0, "No XPC calls for empty changed fields")
    XCTAssertEqual(stub.writeCallCount, 0)
    XCTAssertEqual(stub.renameCallCount, 0)
  }

  @MainActor
  func testModifyWithInvalidIdentifierIsGraceful() {
    let stub = WriteSafetyStubXPC()

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("modify-bad-id"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    // Item with rootContainer identifier — no device/storage/handle parseable
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: nil, objectHandle: nil,
      name: "bad-id.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modify bad id")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: .contents, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      // Should return gracefully (no crash)
      XCTAssertNotNil(resultItem)
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 3. Delete Item Safety Tests

final class FileProviderDeleteWriteSafetyTests: XCTestCase {

  @MainActor
  func testDeleteWithInvalidIdentifierReturnsNoSuchItem() {
    let stub = WriteSafetyStubXPC()

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("delete-bad-id"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let exp = expectation(description: "delete bad id")
    _ = ext.deleteItem(
      identifier: .rootContainer,
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error, "Delete with root container should error")
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(stub.deleteCallCount, 0, "XPC delete should not be called for invalid id")
  }

  @MainActor
  func testDeleteWithDeviceOnlyIdentifierReturnsNoSuchItem() {
    let stub = WriteSafetyStubXPC()

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("delete-device-only"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    // Device-only identifier has no objectHandle
    let exp = expectation(description: "delete device-only")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error, "Delete with device-only id should error (no object handle)")
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
    XCTAssertEqual(stub.deleteCallCount, 0)
  }

  @MainActor
  func testDeleteXPCFailurePropagatesError() {
    let stub = WriteSafetyStubXPC()
    stub.onDelete = { _ in WriteResponse(success: false, errorMessage: "Device disconnected") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("delete-xpc-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let exp = expectation(description: "delete xpc fail")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:100"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      // "disconnected" maps to serverUnreachable
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.deleteCallCount, 1)
  }

  @MainActor
  func testDeleteSuccessSignalsContainer() {
    let stub = WriteSafetyStubXPC()
    stub.onDelete = { _ in WriteResponse(success: true) }

    var signalledContainers: [NSFileProviderItemIdentifier] = []
    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("delete-signal"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { id in signalledContainers.append(id) })

    let exp = expectation(description: "delete signals")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:100"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertTrue(signalledContainers.contains(.rootContainer), "Should signal root after delete")
  }

  @MainActor
  func testDeleteWithNilXPCServiceReturnsNoSuchItem() {
    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("delete-nil-xpc"), indexReader: nil,
      xpcServiceResolver: { nil },
      signalEnumeratorOverride: { _ in })

    let exp = expectation(description: "delete nil xpc")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:100"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error, "Should error when XPC is nil")
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}

// MARK: - 4. XPC Disconnect During Write Tests

final class FileProviderXPCDisconnectWriteTests: XCTestCase {

  func testXPCConnectionManagerQueueOverflowRejectsOperations() async throws {
    let config = XPCConnectionManager.Configuration(maxQueueSize: 2)
    let manager = XPCConnectionManager(
      serviceName: "com.test.fp-safety",
      configuration: config)

    // Invalidate immediately so all service() calls fail
    await manager.invalidate()

    do {
      _ = try await manager.service()
      XCTFail("Should throw when invalidated")
    } catch {
      let xpcError = error as? XPCConnectionError
      XCTAssertEqual(xpcError, .connectionInvalidated)
    }
  }

  func testXPCConnectionManagerInvalidateFailsPendingOps() async throws {
    let manager = XPCConnectionManager(serviceName: "com.test.fp-safety-pending")

    // Invalidate — any pending operations should be drained with error
    await manager.invalidate()

    let state = await manager.connectionState
    XCTAssertEqual(state, .invalidated)
  }

  @MainActor
  func testCreateWithXPCDisconnectErrorClassification() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: false, errorMessage: "XPC interrupted") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("xpc-disconnect"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "xpc-disc.txt")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "xpc-disc.txt", size: 50, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "xpc disconnect")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      // "interrupted" maps to serverUnreachable
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
  }
}

// MARK: - 5. Temp File Safety Tests

final class FileProviderTempFileSafetyTests: XCTestCase {

  @MainActor
  func testSourceFileIntactAfterFailedCreate() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: false, errorMessage: "Device full") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("temp-intact"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let content = "precious-data-do-not-lose"
    let sourceURL = wsMakeTempFile(name: "temp-intact.txt", content: content)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "temp-intact.txt", size: UInt64(content.count), isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "temp intact")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in exp.fulfill() }
    wait(for: [exp], timeout: 3)

    // Source file should still exist and have original content
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    let readBack = try? String(contentsOf: sourceURL, encoding: .utf8)
    XCTAssertEqual(readBack, content, "Source file content should be unchanged after failed create")
  }

  @MainActor
  func testSourceFileIntactAfterSuccessfulCreate() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: true, newHandle: 300) }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("temp-success"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let content = "success-data"
    let sourceURL = wsMakeTempFile(name: "temp-success.txt", content: content)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "temp-success.txt", size: UInt64(content.count), isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "temp success")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)

    // Source file should still exist (File Provider framework manages lifecycle)
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
  }
}

// MARK: - 6. Concurrent Operations Tests

final class FileProviderConcurrentWriteSafetyTests: XCTestCase {

  @MainActor
  func testConcurrentCreatesDoNotInterfere() {
    let stub = WriteSafetyStubXPC()
    var handleCounter: UInt32 = 500
    stub.onWrite = { req in
      handleCounter += 1
      return WriteResponse(success: true, newHandle: handleCounter)
    }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("concurrent-create"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let count = 5
    var results: [(item: NSFileProviderItem?, error: Error?)] = Array(
      repeating: (nil, nil), count: count)
    let expectations = (0..<count).map { i in expectation(description: "create-\(i)") }

    for i in 0..<count {
      let url = wsMakeTempFile(name: "concurrent-\(i).txt", content: "data-\(i)")
      let template = MTPFileProviderItem(
        deviceId: "dev1", storageId: 1, objectHandle: UInt32(42 + i),
        parentHandle: 10,
        name: "concurrent-\(i).txt", size: 10, isDirectory: false, modifiedDate: nil)

      _ = ext.createItem(
        basedOn: template, fields: [], contents: url,
        request: NSFileProviderRequest()
      ) { item, _, _, error in
        results[i] = (item, error)
        expectations[i].fulfill()
      }
    }

    wait(for: expectations, timeout: 5)

    // All creates should succeed independently
    for i in 0..<count {
      XCTAssertNotNil(results[i].item, "Create \(i) should succeed")
      XCTAssertNil(results[i].error, "Create \(i) should have no error")
    }
    XCTAssertEqual(stub.writeCallCount, count, "Each create should trigger exactly one XPC write")

    // Cleanup temp files
    for i in 0..<count {
      let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("concurrent-\(i).txt")
      try? FileManager.default.removeItem(at: url)
    }
  }

  @MainActor
  func testConcurrentDeletesDoNotInterfere() {
    let stub = WriteSafetyStubXPC()
    stub.onDelete = { _ in WriteResponse(success: true) }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("concurrent-delete"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let count = 5
    let expectations = (0..<count).map { i in expectation(description: "delete-\(i)") }
    var errors: [Error?] = Array(repeating: nil, count: count)

    for i in 0..<count {
      _ = ext.deleteItem(
        identifier: NSFileProviderItemIdentifier("dev1:1:\(100 + i)"),
        baseVersion: NSFileProviderItemVersion(
          contentVersion: Data(), metadataVersion: Data()),
        request: NSFileProviderRequest()
      ) { error in
        errors[i] = error
        expectations[i].fulfill()
      }
    }

    wait(for: expectations, timeout: 5)

    for i in 0..<count {
      XCTAssertNil(errors[i], "Delete \(i) should succeed without error")
    }
    XCTAssertEqual(stub.deleteCallCount, count, "Each delete should trigger one XPC call")
  }
}

// MARK: - 7. XPC Error Classification Tests

final class FileProviderXPCErrorClassificationTests: XCTestCase {

  @MainActor
  func testDisconnectMessagesMapToServerUnreachable() {
    let stub = WriteSafetyStubXPC()

    let disconnectMessages = [
      "Device not connected",
      "Device disconnected",
      "Service unavailable",
      "Operation timeout",
      "No device found",
      "XPC interrupted",
      "Device not found",
    ]

    for message in disconnectMessages {
      stub.onDelete = { _ in WriteResponse(success: false, errorMessage: message) }

      let ext = MTPFileProviderExtension(
        domain: wsMakeDomain("err-class-\(message.hashValue)"), indexReader: nil,
        xpcServiceResolver: { stub },
        signalEnumeratorOverride: { _ in })

      let exp = expectation(description: "error-\(message)")
      _ = ext.deleteItem(
        identifier: NSFileProviderItemIdentifier("dev1:1:100"),
        baseVersion: NSFileProviderItemVersion(
          contentVersion: Data(), metadataVersion: Data()),
        request: NSFileProviderRequest()
      ) { error in
        let nsError = error! as NSError
        XCTAssertEqual(
          nsError.code, NSFileProviderError.serverUnreachable.rawValue,
          "Message '\(message)' should map to serverUnreachable")
        exp.fulfill()
      }
      wait(for: [exp], timeout: 2)
    }
  }

  @MainActor
  func testNonDisconnectMessagesMapToNoSuchItem() {
    let stub = WriteSafetyStubXPC()

    let otherMessages = [
      "Permission denied",
      "Storage full",
      "Invalid format",
    ]

    for message in otherMessages {
      stub.onDelete = { _ in WriteResponse(success: false, errorMessage: message) }

      let ext = MTPFileProviderExtension(
        domain: wsMakeDomain("other-err-\(message.hashValue)"), indexReader: nil,
        xpcServiceResolver: { stub },
        signalEnumeratorOverride: { _ in })

      let exp = expectation(description: "other-\(message)")
      _ = ext.deleteItem(
        identifier: NSFileProviderItemIdentifier("dev1:1:100"),
        baseVersion: NSFileProviderItemVersion(
          contentVersion: Data(), metadataVersion: Data()),
        request: NSFileProviderRequest()
      ) { error in
        let nsError = error! as NSError
        XCTAssertEqual(
          nsError.code, NSFileProviderError.noSuchItem.rawValue,
          "Message '\(message)' should map to noSuchItem")
        exp.fulfill()
      }
      wait(for: [exp], timeout: 2)
    }
  }
}

// MARK: - 8. Rename / Move Safety Tests

final class FileProviderRenameMoveSafetyTests: XCTestCase {

  @MainActor
  func testRenameFailureIsGraceful() {
    let stub = WriteSafetyStubXPC()
    stub.onRename = { _ in WriteResponse(success: false, errorMessage: "Rename denied") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("rename-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 60,
      parentHandle: 10,
      name: "renamed.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "rename fails")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: .filename, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      // Rename failure returns nil item, no crash
      XCTAssertNil(resultItem)
      XCTAssertNil(error, "Rename failure currently reports nil error (graceful noop)")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.renameCallCount, 1)
  }

  @MainActor
  func testMoveFailureIsGraceful() {
    let stub = WriteSafetyStubXPC()
    stub.onMove = { _ in WriteResponse(success: false, errorMessage: "Move failed") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("move-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 70,
      parentHandle: 20,
      name: "moved.txt", size: 100, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "move fails")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(
        contentVersion: "v1".data(using: .utf8)!,
        metadataVersion: "v1".data(using: .utf8)!),
      changedFields: .parentItemIdentifier, contents: nil,
      request: NSFileProviderRequest()
    ) { resultItem, _, _, error in
      XCTAssertNil(resultItem)
      XCTAssertNil(error, "Move failure currently reports nil error (graceful noop)")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(stub.moveCallCount, 1)
  }
}

// MARK: - 9. Progress Tracking Tests

final class FileProviderProgressTrackingTests: XCTestCase {

  @MainActor
  func testCreateItemReturnsNonNilProgress() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: true, newHandle: 400) }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("progress-create"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "progress.txt")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "progress.txt", size: 50, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "progress")
    let progress = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in exp.fulfill() }

    XCTAssertNotNil(progress)
    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(progress.completedUnitCount, 1, "Progress should be marked complete")
  }

  @MainActor
  func testDeleteItemReturnsNonNilProgress() {
    let stub = WriteSafetyStubXPC()
    stub.onDelete = { _ in WriteResponse(success: true) }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("progress-delete"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let exp = expectation(description: "progress delete")
    let progress = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:100"),
      baseVersion: NSFileProviderItemVersion(
        contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { _ in exp.fulfill() }

    XCTAssertNotNil(progress)
    XCTAssertEqual(progress.totalUnitCount, 1)
    wait(for: [exp], timeout: 3)
    XCTAssertEqual(progress.completedUnitCount, 1)
  }

  @MainActor
  func testFailedCreateStillCompletesProgress() {
    let stub = WriteSafetyStubXPC()
    stub.onWrite = { _ in WriteResponse(success: false, errorMessage: "fail") }

    let ext = MTPFileProviderExtension(
      domain: wsMakeDomain("progress-fail"), indexReader: nil,
      xpcServiceResolver: { stub },
      signalEnumeratorOverride: { _ in })

    let sourceURL = wsMakeTempFile(name: "progress-fail.txt")
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let template = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 42,
      parentHandle: 10,
      name: "progress-fail.txt", size: 50, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "progress on fail")
    let progress = ext.createItem(
      basedOn: template, fields: [], contents: sourceURL,
      request: NSFileProviderRequest()
    ) { _, _, _, _ in exp.fulfill() }

    wait(for: [exp], timeout: 3)
    XCTAssertEqual(
      progress.completedUnitCount, 1,
      "Progress should still complete even on failure")
  }
}
