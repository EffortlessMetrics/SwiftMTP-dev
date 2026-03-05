// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPFileProvider
import FileProvider
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPXPC
import CoreGraphics

// MARK: - Thumbnail Test Infrastructure

private final class ThumbnailStubXPCService: NSObject, MTPXPCService {
  nonisolated(unsafe) var onGetThumbnail: ((ThumbnailRequest) -> ThumbnailResponse)?
  nonisolated(unsafe) var thumbnailCallCount = 0

  func ping(reply: @escaping (String) -> Void) { reply("ok") }

  func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
    r(ReadResponse(success: false, errorMessage: "stub"))
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
    r(WriteResponse(success: false, errorMessage: "stub"))
  }

  func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(WriteResponse(success: false, errorMessage: "stub"))
  }

  func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(WriteResponse(success: false, errorMessage: "stub"))
  }

  func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(WriteResponse(success: false, errorMessage: "stub"))
  }

  func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
    r(WriteResponse(success: false, errorMessage: "stub"))
  }

  func requestCrawl(
    _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
  ) { r(CrawlTriggerResponse(accepted: false)) }

  func deviceStatus(
    _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
  ) { r(DeviceStatusResponse(connected: true, sessionOpen: true)) }

  func getThumbnail(
    _ req: ThumbnailRequest, withReply r: @escaping (ThumbnailResponse) -> Void
  ) {
    thumbnailCallCount += 1
    r(onGetThumbnail?(req) ?? ThumbnailResponse(success: false, errorMessage: "stub"))
  }
}

/// Minimal JPEG-like stub data for thumbnail tests.
private let stubJPEGData: Data = {
  var d = Data([0xFF, 0xD8])  // JPEG SOI
  d.append(contentsOf: [UInt8](repeating: 0x00, count: 62))
  d.append(contentsOf: [0xFF, 0xD9] as [UInt8])  // JPEG EOI
  return d
}()

// MARK: - Thumbnail Tests

final class FileProviderThumbnailTests: XCTestCase {

  // MARK: - fetchThumbnails success

  @MainActor
  func testFetchThumbnailsReturnsDataForValidItem() {
    let stub = ThumbnailStubXPCService()
    stub.onGetThumbnail = { req in
      XCTAssertEqual(req.objectHandle, 42)
      return ThumbnailResponse(success: true, thumbnailData: stubJPEGData)
    }

    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { stub }
    )

    let expectation = self.expectation(description: "thumbnail fetched")
    var receivedData: Data?
    var receivedError: Error?

    let identifier = NSFileProviderItemIdentifier("dev1:1:42")
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { id, data, error in
        XCTAssertEqual(id, identifier)
        receivedData = data
        receivedError = error
      },
      completionHandler: { _ in
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 5)
    XCTAssertNotNil(receivedData)
    XCTAssertEqual(receivedData, stubJPEGData)
    XCTAssertNil(receivedError)
    XCTAssertEqual(stub.thumbnailCallCount, 1)
  }

  // MARK: - fetchThumbnails caching

  @MainActor
  func testFetchThumbnailsCachesAndReusesThumbnailData() {
    let stub = ThumbnailStubXPCService()
    stub.onGetThumbnail = { _ in
      ThumbnailResponse(success: true, thumbnailData: stubJPEGData)
    }

    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { stub }
    )

    let identifier = NSFileProviderItemIdentifier("dev1:1:42")

    // First fetch — should hit XPC
    let exp1 = expectation(description: "first fetch")
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, _, _ in },
      completionHandler: { _ in exp1.fulfill() }
    )
    waitForExpectations(timeout: 5)
    XCTAssertEqual(stub.thumbnailCallCount, 1)

    // Second fetch — should use cache (no additional XPC call)
    let exp2 = expectation(description: "second fetch")
    var cachedData: Data?
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, data, _ in cachedData = data },
      completionHandler: { _ in exp2.fulfill() }
    )
    waitForExpectations(timeout: 5)
    XCTAssertEqual(stub.thumbnailCallCount, 1, "Cache should prevent second XPC call")
    XCTAssertEqual(cachedData, stubJPEGData)
  }

  // MARK: - fetchThumbnails failure (device error)

  @MainActor
  func testFetchThumbnailsHandlesDeviceError() {
    let stub = ThumbnailStubXPCService()
    stub.onGetThumbnail = { _ in
      ThumbnailResponse(success: false, errorMessage: "No thumbnail available")
    }

    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { stub }
    )

    let expectation = self.expectation(description: "thumbnail failed")
    var receivedData: Data?

    let identifier = NSFileProviderItemIdentifier("dev1:1:42")
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, data, _ in
        receivedData = data
      },
      completionHandler: { _ in
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 5)
    XCTAssertNil(receivedData, "Should return nil data on failure")
  }

  // MARK: - fetchThumbnails invalid identifier

  @MainActor
  func testFetchThumbnailsRejectsInvalidIdentifier() {
    let stub = ThumbnailStubXPCService()

    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { stub }
    )

    let expectation = self.expectation(description: "thumbnail rejected")
    var receivedError: Error?

    // Storage-level identifier (no object handle) — cannot have a thumbnail
    let identifier = NSFileProviderItemIdentifier("dev1:1")
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, _, error in
        receivedError = error
      },
      completionHandler: { _ in
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 5)
    XCTAssertNotNil(receivedError, "Should return error for storage-level identifier")
    XCTAssertEqual(stub.thumbnailCallCount, 0, "Should not call XPC for invalid identifier")
  }

  // MARK: - fetchThumbnails without XPC service

  @MainActor
  func testFetchThumbnailsWithoutXPCService() {
    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { nil }
    )

    let expectation = self.expectation(description: "no xpc")
    var receivedError: Error?

    let identifier = NSFileProviderItemIdentifier("dev1:1:42")
    _ = ext.fetchThumbnails(
      for: [identifier],
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, _, error in
        receivedError = error
      },
      completionHandler: { _ in
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 5)
    XCTAssertNotNil(receivedError, "Should return error when XPC is unavailable")
  }

  // MARK: - Multiple thumbnails in batch

  @MainActor
  func testFetchThumbnailsBatchMultipleItems() {
    let stub = ThumbnailStubXPCService()
    stub.onGetThumbnail = { req in
      ThumbnailResponse(success: true, thumbnailData: stubJPEGData)
    }

    let ext = MTPFileProviderExtension(
      domain: NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier("test"), displayName: "Test"),
      indexReader: nil,
      xpcServiceResolver: { stub }
    )

    let ids = [
      NSFileProviderItemIdentifier("dev1:1:10"),
      NSFileProviderItemIdentifier("dev1:1:20"),
      NSFileProviderItemIdentifier("dev1:1:30"),
    ]

    let expectation = self.expectation(description: "batch thumbnails")
    var receivedCount = 0

    _ = ext.fetchThumbnails(
      for: ids,
      requestedSize: CGSize(width: 64, height: 64),
      perThumbnailCompletionHandler: { _, data, _ in
        if data != nil { receivedCount += 1 }
      },
      completionHandler: { _ in
        expectation.fulfill()
      }
    )

    waitForExpectations(timeout: 5)
    XCTAssertEqual(receivedCount, 3)
    XCTAssertEqual(stub.thumbnailCallCount, 3)
  }

  // MARK: - ThumbnailRequest/Response NSSecureCoding

  @MainActor
  func testThumbnailRequestSecureCoding() {
    let original = ThumbnailRequest(deviceId: "dev1", objectHandle: 42)
    let data = try! NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try! NSKeyedUnarchiver.unarchivedObject(
      ofClass: ThumbnailRequest.self, from: data)

    XCTAssertEqual(decoded?.deviceId, "dev1")
    XCTAssertEqual(decoded?.objectHandle, 42)
  }

  @MainActor
  func testThumbnailResponseSecureCoding() {
    let original = ThumbnailResponse(
      success: true, errorMessage: nil, thumbnailData: stubJPEGData)
    let data = try! NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try! NSKeyedUnarchiver.unarchivedObject(
      ofClass: ThumbnailResponse.self, from: data)

    XCTAssertEqual(decoded?.success, true)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertEqual(decoded?.thumbnailData, stubJPEGData)
  }

  @MainActor
  func testThumbnailResponseSecureCodingFailure() {
    let original = ThumbnailResponse(
      success: false, errorMessage: "No thumbnail", thumbnailData: nil)
    let data = try! NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try! NSKeyedUnarchiver.unarchivedObject(
      ofClass: ThumbnailResponse.self, from: data)

    XCTAssertEqual(decoded?.success, false)
    XCTAssertEqual(decoded?.errorMessage, "No thumbnail")
    XCTAssertNil(decoded?.thumbnailData)
  }
}
