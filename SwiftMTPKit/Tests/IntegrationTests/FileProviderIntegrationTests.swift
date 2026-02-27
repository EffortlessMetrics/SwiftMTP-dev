// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@preconcurrency import FileProvider
@testable import SwiftMTPCore
@testable import SwiftMTPFileProvider
import SwiftMTPXPC
import SwiftMTPTestKit
import SwiftMTPIndex

// MARK: - Mock XPC Service

/// Mock XPC service for integration tests — records calls and returns configurable responses.
@MainActor
final class MockXPCService: NSObject, MTPXPCService {
  var pingCalled = false
  var writeRequests: [WriteRequest] = []
  var deleteRequests: [DeleteRequest] = []
  var createFolderRequests: [CreateFolderRequest] = []

  var writeResponse = WriteResponse(success: true)
  var deleteResponse = WriteResponse(success: true)
  var createFolderResponse = WriteResponse(success: true, newHandle: 200)

  func ping(reply: @escaping (String) -> Void) {
    pingCalled = true
    reply("pong")
  }

  func readObject(_ request: ReadRequest, withReply reply: @escaping (ReadResponse) -> Void) {
    reply(ReadResponse(success: false, errorMessage: "not implemented in mock"))
  }

  func listStorages(
    _ request: StorageListRequest, withReply reply: @escaping (StorageListResponse) -> Void
  ) {
    reply(StorageListResponse(success: false))
  }

  func listObjects(
    _ request: ObjectListRequest, withReply reply: @escaping (ObjectListResponse) -> Void
  ) {
    reply(ObjectListResponse(success: false))
  }

  func getObjectInfo(
    deviceId: String, storageId: UInt32, objectHandle: UInt32,
    withReply reply: @escaping (ReadResponse) -> Void
  ) {
    reply(ReadResponse(success: false, errorMessage: "not implemented in mock"))
  }

  func writeObject(_ request: WriteRequest, withReply reply: @escaping (WriteResponse) -> Void) {
    writeRequests.append(request)
    reply(writeResponse)
  }

  func deleteObject(_ request: DeleteRequest, withReply reply: @escaping (WriteResponse) -> Void) {
    deleteRequests.append(request)
    reply(deleteResponse)
  }

  func createFolder(
    _ request: CreateFolderRequest, withReply reply: @escaping (WriteResponse) -> Void
  ) {
    createFolderRequests.append(request)
    reply(createFolderResponse)
  }

  func renameObject(
    _ request: RenameRequest, withReply reply: @escaping (WriteResponse) -> Void
  ) {
    reply(WriteResponse(success: true))
  }

  func moveObject(
    _ request: MoveObjectRequest, withReply reply: @escaping (WriteResponse) -> Void
  ) {
    reply(WriteResponse(success: true))
  }

  func requestCrawl(
    _ request: CrawlTriggerRequest, withReply reply: @escaping (CrawlTriggerResponse) -> Void
  ) {
    reply(CrawlTriggerResponse(accepted: false))
  }

  func deviceStatus(
    _ request: DeviceStatusRequest, withReply reply: @escaping (DeviceStatusResponse) -> Void
  ) {
    reply(DeviceStatusResponse(connected: false, sessionOpen: false))
  }
}

// MARK: - FileProvider Write Integration Tests

/// Integration tests for FileProvider write operations with mock XPC service.
/// These tests exercise the full createItem/modifyItem/deleteItem path without a real device.
final class FileProviderWriteIntegrationTests: XCTestCase {

  private func makeDomain() -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("test-domain"),
      displayName: "Test Domain")
  }

  private func makeFolderTemplate(deviceId: String = "dev1", storageId: UInt32 = 1)
    -> MTPFileProviderItem
  {
    MTPFileProviderItem(
      deviceId: deviceId, storageId: storageId, objectHandle: nil,
      name: "NewFolder", size: nil, isDirectory: true, modifiedDate: nil)
  }

  @MainActor
  func testCreateFolderUsesXPCCreateFolder() async throws {
    let mock = MockXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { mock })
    let template = makeFolderTemplate()

    let exp = expectation(description: "createItem completes")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil, request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(error, "Expected no error for folder creation")
      XCTAssertNotNil(item)
      exp.fulfill()
    }

    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(mock.createFolderRequests.count, 1)
    XCTAssertEqual(mock.createFolderRequests[0].name, "NewFolder")
    XCTAssertEqual(mock.createFolderRequests[0].deviceId, "dev1")
    XCTAssertEqual(mock.createFolderRequests[0].storageId, 1)
  }

  @MainActor
  func testCreateFolderXPCFailureReturnsError() async throws {
    let mock = MockXPCService()
    mock.createFolderResponse = WriteResponse(success: false, errorMessage: "Device busy")
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { mock })
    let template = makeFolderTemplate()

    let exp = expectation(description: "createItem completes with error")
    _ = ext.createItem(
      basedOn: template, fields: [], contents: nil, request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2.0)
  }

  @MainActor
  func testDeleteItemUsesXPCDeleteObject() async throws {
    let mock = MockXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { mock })

    let exp = expectation(description: "deleteItem completes")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:42"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNil(error, "Expected no error for successful delete")
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2.0)
    XCTAssertEqual(mock.deleteRequests.count, 1)
    XCTAssertEqual(mock.deleteRequests[0].deviceId, "dev1")
    XCTAssertEqual(mock.deleteRequests[0].objectHandle, 42)
  }

  @MainActor
  func testDeleteItemXPCFailureReturnsError() async throws {
    let mock = MockXPCService()
    mock.deleteResponse = WriteResponse(success: false, errorMessage: "Not found")
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { mock })

    let exp = expectation(description: "deleteItem completes with error")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("dev1:1:99"),
      baseVersion: NSFileProviderItemVersion(), options: [],
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 2.0)
  }

  @MainActor
  func testModifyItemMetadataOnlyAcknowledgesWithNoXPCCall() async throws {
    let mock = MockXPCService()
    let ext = MTPFileProviderExtension(
      domain: makeDomain(), indexReader: nil,
      xpcServiceResolver: { mock })
    let item = MTPFileProviderItem(
      deviceId: "dev1", storageId: 1, objectHandle: 100,
      name: "photo.jpg", size: 512, isDirectory: false, modifiedDate: nil)

    let exp = expectation(description: "modifyItem completes")
    _ = ext.modifyItem(
      item, baseVersion: NSFileProviderItemVersion(),
      changedFields: [], contents: nil, request: NSFileProviderRequest()
    ) { returnedItem, _, _, error in
      XCTAssertNil(error)
      XCTAssertNotNil(returnedItem)
      exp.fulfill()
    }
    await fulfillment(of: [exp], timeout: 1.0)
    // No XPC calls for metadata-only change
    XCTAssertEqual(mock.writeRequests.count, 0)
    XCTAssertEqual(mock.deleteRequests.count, 0)
  }
}

// MARK: - MTPFileProviderItem Tests

final class MTPFileProviderItemIntegrationTests: XCTestCase {

  func testItemIdentifierRoundTrip() {
    let item = MTPFileProviderItem(
      deviceId: "device-abc", storageId: 7, objectHandle: 99,
      name: "test.mp4", size: 1024, isDirectory: false, modifiedDate: nil)
    let identifier = item.itemIdentifier
    let parsed = MTPFileProviderItem.parseItemIdentifier(identifier)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.deviceId, "device-abc")
    XCTAssertEqual(parsed?.storageId, 7)
    XCTAssertEqual(parsed?.objectHandle, 99)
  }

  func testStorageItemIdentifierRoundTrip() {
    let item = MTPFileProviderItem(
      deviceId: "device-xyz", storageId: 3, objectHandle: nil,
      name: "Internal Storage", size: nil, isDirectory: true, modifiedDate: nil)
    let identifier = item.itemIdentifier
    let parsed = MTPFileProviderItem.parseItemIdentifier(identifier)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.deviceId, "device-xyz")
    XCTAssertEqual(parsed?.storageId, 3)
    XCTAssertNil(parsed?.objectHandle)
  }

  func testDeviceRootIdentifierParsed() {
    let item = MTPFileProviderItem(
      deviceId: "mydevice", storageId: nil, objectHandle: nil,
      name: "Pixel 7", size: nil, isDirectory: true, modifiedDate: nil)
    let identifier = item.itemIdentifier
    let parsed = MTPFileProviderItem.parseItemIdentifier(identifier)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.deviceId, "mydevice")
    XCTAssertNil(parsed?.storageId)
  }

  func testRootContainerReturnsNil() {
    let parsed = MTPFileProviderItem.parseItemIdentifier(.rootContainer)
    XCTAssertNil(parsed)
  }

  func testContentTypeFolder() {
    let dir = MTPFileProviderItem(
      deviceId: "d", storageId: 1, objectHandle: 1,
      name: "Photos", size: nil, isDirectory: true, modifiedDate: nil)
    XCTAssertEqual(dir.contentType, .folder)
  }

  func testContentTypeFile() {
    let file = MTPFileProviderItem(
      deviceId: "d", storageId: 1, objectHandle: 2,
      name: "video.mp4", size: 1024, isDirectory: false, modifiedDate: nil)
    XCTAssertNotEqual(file.contentType, .folder)
  }

  func testParentIdentifierForNestedObject() {
    let item = MTPFileProviderItem(
      deviceId: "d", storageId: 5, objectHandle: 10, parentHandle: 7,
      name: "file.jpg", size: nil, isDirectory: false, modifiedDate: nil)
    let parent = item.parentItemIdentifier
    let parsed = MTPFileProviderItem.parseItemIdentifier(parent)
    XCTAssertEqual(parsed?.objectHandle, 7)
  }
}

// MARK: - FileProvider Manager / Domain Lifecycle Tests
// (These require sandbox entitlements and must remain skipped in normal CI)

final class FileProviderSandboxTests: XCTestCase {

  func testDomainRegistrationRequiresSandbox() async throws {
    throw XCTSkip(
      "NSFileProviderManager domain operations require the FileProvider sandbox entitlement")
  }

  func testEnumeratorRequiresDomainHost() async throws {
    throw XCTSkip("DomainEnumerator requires a live NSFileProviderExtension host process")
  }

  func testChangeSignalerRequiresDomainHost() async throws {
    throw XCTSkip("ChangeSignaler requires a valid NSFileProviderDomain from the host process")
  }
}
