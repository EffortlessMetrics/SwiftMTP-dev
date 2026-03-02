// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPXPC

/// Comprehensive serialization tests for all XPC message types.
final class XPCSerializationTests: XCTestCase {

  // MARK: - Helpers

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  private func archiveData<T: NSObject & NSSecureCoding>(_ value: T) throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
  }

  // MARK: - ReadRequest serialization

  func testReadRequestBasicRoundTrip() throws {
    let req = ReadRequest(deviceId: "device-123", objectHandle: 42)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, "device-123")
    XCTAssertEqual(decoded?.objectHandle, 42)
    XCTAssertNil(decoded?.bookmark)
  }

  func testReadRequestWithBookmarkRoundTrip() throws {
    let bookmark = Data(repeating: 0xAB, count: 256)
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: bookmark)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark, bookmark)
  }

  func testReadRequestWithNilBookmark() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: 5, bookmark: nil)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertNil(decoded?.bookmark)
  }

  // MARK: - ReadResponse serialization

  func testReadResponseSuccessRoundTrip() throws {
    let url = URL(fileURLWithPath: "/tmp/test.bin")
    let resp = ReadResponse(success: true, tempFileURL: url, fileSize: 1024)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertTrue(decoded!.success)
    XCTAssertEqual(decoded?.tempFileURL, url)
    XCTAssertEqual(decoded?.fileSize, 1024)
  }

  func testReadResponseFailureRoundTrip() throws {
    let resp = ReadResponse(success: false, errorMessage: "Device disconnected")
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertFalse(decoded!.success)
    XCTAssertEqual(decoded?.errorMessage, "Device disconnected")
    XCTAssertNil(decoded?.tempFileURL)
    XCTAssertNil(decoded?.fileSize)
  }

  func testReadResponseAllNilOptionals() throws {
    let resp = ReadResponse(success: true)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertTrue(decoded!.success)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertNil(decoded?.tempFileURL)
    XCTAssertNil(decoded?.fileSize)
  }

  // MARK: - StorageInfo serialization

  func testStorageInfoBasicRoundTrip() throws {
    let info = StorageInfo(
      storageId: 1, description: "Internal Storage", capacityBytes: 64_000_000_000,
      freeBytes: 32_000_000_000)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageId, 1)
    XCTAssertEqual(decoded?.storageDescription, "Internal Storage")
    XCTAssertEqual(decoded?.capacityBytes, 64_000_000_000)
    XCTAssertEqual(decoded?.freeBytes, 32_000_000_000)
  }

  func testStorageInfoZeroValues() throws {
    let info = StorageInfo(storageId: 0, description: "", capacityBytes: 0, freeBytes: 0)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageId, 0)
    XCTAssertEqual(decoded?.storageDescription, "")
    XCTAssertEqual(decoded?.capacityBytes, 0)
    XCTAssertEqual(decoded?.freeBytes, 0)
  }

  // MARK: - StorageListRequest/Response serialization

  func testStorageListRequestRoundTrip() throws {
    let req = StorageListRequest(deviceId: "my-device")
    let decoded = try roundTrip(req, as: StorageListRequest.self)
    XCTAssertEqual(decoded?.deviceId, "my-device")
  }

  func testStorageListResponseWithStorages() throws {
    let s1 = StorageInfo(storageId: 1, description: "Internal", capacityBytes: 100, freeBytes: 50)
    let s2 = StorageInfo(storageId: 2, description: "SD Card", capacityBytes: 200, freeBytes: 150)
    let resp = StorageListResponse(success: true, storages: [s1, s2])
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertTrue(decoded!.success)
    XCTAssertEqual(decoded?.storages?.count, 2)
    XCTAssertEqual(decoded?.storages?[0].storageDescription, "Internal")
    XCTAssertEqual(decoded?.storages?[1].storageDescription, "SD Card")
  }

  func testStorageListResponseNilStorages() throws {
    let resp = StorageListResponse(success: false, errorMessage: "fail", storages: nil)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertFalse(decoded!.success)
    XCTAssertNil(decoded?.storages)
  }

  func testStorageListResponseEmptyArray() throws {
    let resp = StorageListResponse(success: true, storages: [])
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 0)
  }

  // MARK: - ObjectInfo serialization

  func testObjectInfoFileRoundTrip() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info = ObjectInfo(
      handle: 42, name: "photo.jpg", sizeBytes: 5_000_000, isDirectory: false, modifiedDate: date)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.handle, 42)
    XCTAssertEqual(decoded?.name, "photo.jpg")
    XCTAssertEqual(decoded?.sizeBytes, 5_000_000)
    XCTAssertFalse(decoded!.isDirectory)
    XCTAssertEqual(
      decoded?.modifiedDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1.0)
  }

  func testObjectInfoDirectoryRoundTrip() throws {
    let info = ObjectInfo(
      handle: 10, name: "DCIM", sizeBytes: nil, isDirectory: true, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertTrue(decoded!.isDirectory)
    XCTAssertNil(decoded?.sizeBytes)
    XCTAssertNil(decoded?.modifiedDate)
  }

  func testObjectInfoNilModifiedDate() throws {
    let info = ObjectInfo(
      handle: 1, name: "test", sizeBytes: 100, isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertNil(decoded?.modifiedDate)
  }

  // MARK: - ObjectListRequest/Response serialization

  func testObjectListRequestWithParentHandle() throws {
    let req = ObjectListRequest(deviceId: "dev", storageId: 1, parentHandle: 500)
    let decoded = try roundTrip(req, as: ObjectListRequest.self)
    XCTAssertEqual(decoded?.deviceId, "dev")
    XCTAssertEqual(decoded?.storageId, 1)
    XCTAssertEqual(decoded?.parentHandle, 500)
  }

  func testObjectListRequestNilParentHandle() throws {
    let req = ObjectListRequest(deviceId: "dev", storageId: 2, parentHandle: nil)
    let decoded = try roundTrip(req, as: ObjectListRequest.self)
    XCTAssertNil(decoded?.parentHandle)
  }

  func testObjectListResponseWithObjects() throws {
    let o1 = ObjectInfo(
      handle: 1, name: "a.txt", sizeBytes: 10, isDirectory: false, modifiedDate: nil)
    let o2 = ObjectInfo(
      handle: 2, name: "dir", sizeBytes: nil, isDirectory: true, modifiedDate: nil)
    let resp = ObjectListResponse(success: true, objects: [o1, o2])
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 2)
  }

  func testObjectListResponseEmptyObjects() throws {
    let resp = ObjectListResponse(success: true, objects: [])
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 0)
  }

  func testObjectListResponseNilObjects() throws {
    let resp = ObjectListResponse(success: false, errorMessage: "err", objects: nil)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertNil(decoded?.objects)
  }

  // MARK: - WriteRequest serialization

  func testWriteRequestFullRoundTrip() throws {
    let bookmark = Data(repeating: 0xCC, count: 64)
    let req = WriteRequest(
      deviceId: "dev", storageId: 3, parentHandle: 10, name: "upload.bin", size: 999_999,
      bookmark: bookmark)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.deviceId, "dev")
    XCTAssertEqual(decoded?.storageId, 3)
    XCTAssertEqual(decoded?.parentHandle, 10)
    XCTAssertEqual(decoded?.name, "upload.bin")
    XCTAssertEqual(decoded?.size, 999_999)
    XCTAssertEqual(decoded?.bookmark, bookmark)
  }

  func testWriteRequestNilOptionals() throws {
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil, name: "f", size: 0, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertNil(decoded?.parentHandle)
    XCTAssertNil(decoded?.bookmark)
    XCTAssertEqual(decoded?.size, 0)
  }

  // MARK: - WriteResponse serialization

  func testWriteResponseSuccessWithHandle() throws {
    let resp = WriteResponse(success: true, newHandle: 42)
    let decoded = try roundTrip(resp, as: WriteResponse.self)
    XCTAssertTrue(decoded!.success)
    XCTAssertEqual(decoded?.newHandle, 42)
    XCTAssertNil(decoded?.errorMessage)
  }

  func testWriteResponseFailureWithMessage() throws {
    let resp = WriteResponse(success: false, errorMessage: "disk full")
    let decoded = try roundTrip(resp, as: WriteResponse.self)
    XCTAssertFalse(decoded!.success)
    XCTAssertEqual(decoded?.errorMessage, "disk full")
    XCTAssertNil(decoded?.newHandle)
  }

  func testWriteResponseAllNilOptionals() throws {
    let resp = WriteResponse(success: true)
    let decoded = try roundTrip(resp, as: WriteResponse.self)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertNil(decoded?.newHandle)
  }

  // MARK: - DeleteRequest serialization

  func testDeleteRequestRecursiveRoundTrip() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: 100, recursive: true)
    let decoded = try roundTrip(req, as: DeleteRequest.self)
    XCTAssertEqual(decoded?.objectHandle, 100)
    XCTAssertTrue(decoded!.recursive)
  }

  func testDeleteRequestNonRecursiveRoundTrip() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: 50, recursive: false)
    let decoded = try roundTrip(req, as: DeleteRequest.self)
    XCTAssertFalse(decoded!.recursive)
  }

  // MARK: - CreateFolderRequest serialization

  func testCreateFolderRequestRoundTrip() throws {
    let req = CreateFolderRequest(deviceId: "dev", storageId: 1, parentHandle: 5, name: "NewFolder")
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.storageId, 1)
    XCTAssertEqual(decoded?.parentHandle, 5)
    XCTAssertEqual(decoded?.name, "NewFolder")
  }

  func testCreateFolderRequestNilParent() throws {
    let req = CreateFolderRequest(deviceId: "dev", storageId: 1, parentHandle: nil, name: "Root")
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertNil(decoded?.parentHandle)
  }

  // MARK: - RenameRequest serialization

  func testRenameRequestRoundTrip() throws {
    let req = RenameRequest(deviceId: "dev", objectHandle: 77, newName: "renamed.txt")
    let decoded = try roundTrip(req, as: RenameRequest.self)
    XCTAssertEqual(decoded?.objectHandle, 77)
    XCTAssertEqual(decoded?.newName, "renamed.txt")
  }

  // MARK: - MoveObjectRequest serialization

  func testMoveObjectRequestRoundTrip() throws {
    let req = MoveObjectRequest(
      deviceId: "dev", objectHandle: 10, newParentHandle: 20, newStorageId: 2)
    let decoded = try roundTrip(req, as: MoveObjectRequest.self)
    XCTAssertEqual(decoded?.objectHandle, 10)
    XCTAssertEqual(decoded?.newParentHandle, 20)
    XCTAssertEqual(decoded?.newStorageId, 2)
  }

  func testMoveObjectRequestNilParent() throws {
    let req = MoveObjectRequest(
      deviceId: "dev", objectHandle: 10, newParentHandle: nil, newStorageId: 1)
    let decoded = try roundTrip(req, as: MoveObjectRequest.self)
    XCTAssertNil(decoded?.newParentHandle)
  }

  // MARK: - CrawlTriggerRequest/Response serialization

  func testCrawlTriggerRequestRoundTrip() throws {
    let req = CrawlTriggerRequest(deviceId: "dev", storageId: 1, parentHandle: 99)
    let decoded = try roundTrip(req, as: CrawlTriggerRequest.self)
    XCTAssertEqual(decoded?.storageId, 1)
    XCTAssertEqual(decoded?.parentHandle, 99)
  }

  func testCrawlTriggerRequestNilParent() throws {
    let req = CrawlTriggerRequest(deviceId: "dev", storageId: 1)
    let decoded = try roundTrip(req, as: CrawlTriggerRequest.self)
    XCTAssertNil(decoded?.parentHandle)
  }

  func testCrawlTriggerResponseAccepted() throws {
    let resp = CrawlTriggerResponse(accepted: true)
    let decoded = try roundTrip(resp, as: CrawlTriggerResponse.self)
    XCTAssertTrue(decoded!.accepted)
    XCTAssertNil(decoded?.errorMessage)
  }

  func testCrawlTriggerResponseRejectedWithError() throws {
    let resp = CrawlTriggerResponse(accepted: false, errorMessage: "busy")
    let decoded = try roundTrip(resp, as: CrawlTriggerResponse.self)
    XCTAssertFalse(decoded!.accepted)
    XCTAssertEqual(decoded?.errorMessage, "busy")
  }

  // MARK: - DeviceStatusRequest/Response serialization

  func testDeviceStatusRequestRoundTrip() throws {
    let req = DeviceStatusRequest(deviceId: "my-device-id")
    let decoded = try roundTrip(req, as: DeviceStatusRequest.self)
    XCTAssertEqual(decoded?.deviceId, "my-device-id")
  }

  func testDeviceStatusResponseRoundTrip() throws {
    let resp = DeviceStatusResponse(
      connected: true, sessionOpen: false, lastCrawlTimestamp: 1_700_000_000)
    let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
    XCTAssertTrue(decoded!.connected)
    XCTAssertFalse(decoded!.sessionOpen)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, 1_700_000_000)
  }

  func testDeviceStatusResponseDefaultTimestamp() throws {
    let resp = DeviceStatusResponse(connected: false, sessionOpen: false)
    let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, 0)
  }

  // MARK: - Large payload handling (>1MB)

  func testReadRequestLargeBookmarkPayload() throws {
    let largeBookmark = Data(repeating: 0xDE, count: 2 * 1024 * 1024)  // 2MB
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: largeBookmark)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 2 * 1024 * 1024)
    XCTAssertEqual(decoded?.bookmark, largeBookmark)
  }

  func testWriteRequestLargeBookmarkPayload() throws {
    let largeBookmark = Data(repeating: 0xAA, count: 4 * 1024 * 1024)  // 4MB
    let req = WriteRequest(
      deviceId: "d", storageId: 1, parentHandle: nil, name: "big.bin",
      size: UInt64(largeBookmark.count), bookmark: largeBookmark)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark, largeBookmark)
  }

  func testObjectListResponseLargeObjectCount() throws {
    let objects = (0..<500)
      .map { i in
        ObjectInfo(
          handle: UInt32(i), name: "file_\(i).dat", sizeBytes: UInt64(i * 1000), isDirectory: false,
          modifiedDate: nil)
      }
    let resp = ObjectListResponse(success: true, objects: objects)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 500)
    XCTAssertEqual(decoded?.objects?.last?.name, "file_499.dat")
  }

  func testStorageListResponseLargeStorageCount() throws {
    let storages = (0..<100)
      .map { i in
        StorageInfo(
          storageId: UInt32(i), description: "Storage \(i)", capacityBytes: UInt64(i) * 1_000_000,
          freeBytes: UInt64(i) * 500_000)
      }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 100)
  }

  // MARK: - Unicode in XPC strings

  func testDeviceIdWithEmoji() throws {
    let req = ReadRequest(deviceId: "📱-device-🔌", objectHandle: 1)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, "📱-device-🔌")
  }

  func testObjectNameWithCJKCharacters() throws {
    let info = ObjectInfo(
      handle: 1, name: "写真_2024年.jpg", sizeBytes: 100, isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, "写真_2024年.jpg")
  }

  func testStorageDescriptionWithArabicText() throws {
    let info = StorageInfo(
      storageId: 1, description: "التخزين الداخلي", capacityBytes: 100, freeBytes: 50)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageDescription, "التخزين الداخلي")
  }

  func testFolderNameWithCombiningCharacters() throws {
    // e + combining acute accent
    let name = "re\u{0301}sume\u{0301}.pdf"
    let req = CreateFolderRequest(deviceId: "dev", storageId: 1, parentHandle: nil, name: name)
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.name, name)
  }

  func testRenameWithMixedScripts() throws {
    let newName = "αβγ_файл_日本語.txt"
    let req = RenameRequest(deviceId: "dev", objectHandle: 1, newName: newName)
    let decoded = try roundTrip(req, as: RenameRequest.self)
    XCTAssertEqual(decoded?.newName, newName)
  }

  func testErrorMessageWithUnicode() throws {
    let msg = "Ошибка: устройство отключено 🔴"
    let resp = ReadResponse(success: false, errorMessage: msg)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.errorMessage, msg)
  }

  // MARK: - Empty message handling

  func testEmptyReadRequest() throws {
    let req = ReadRequest(deviceId: "", objectHandle: 0, bookmark: nil)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, "")
    XCTAssertEqual(decoded?.objectHandle, 0)
  }

  func testEmptyWriteRequest() throws {
    let req = WriteRequest(
      deviceId: "", storageId: 0, parentHandle: nil, name: "", size: 0, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.deviceId, "")
    XCTAssertEqual(decoded?.name, "")
    XCTAssertEqual(decoded?.size, 0)
  }

  func testEmptyRenameRequest() throws {
    let req = RenameRequest(deviceId: "", objectHandle: 0, newName: "")
    let decoded = try roundTrip(req, as: RenameRequest.self)
    XCTAssertEqual(decoded?.newName, "")
  }

  func testEmptyCreateFolderRequest() throws {
    let req = CreateFolderRequest(deviceId: "", storageId: 0, parentHandle: nil, name: "")
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.name, "")
  }

  // MARK: - Date serialization

  func testObjectInfoDateDistantPast() throws {
    let date = Date.distantPast
    let info = ObjectInfo(
      handle: 1, name: "old.txt", sizeBytes: 1, isDirectory: false, modifiedDate: date)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(
      decoded?.modifiedDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1.0)
  }

  func testObjectInfoDateDistantFuture() throws {
    let date = Date.distantFuture
    let info = ObjectInfo(
      handle: 2, name: "future.txt", sizeBytes: 1, isDirectory: false, modifiedDate: date)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(
      decoded?.modifiedDate?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1.0)
  }

  func testObjectInfoDateEpochZero() throws {
    let date = Date(timeIntervalSince1970: 0)
    let info = ObjectInfo(
      handle: 3, name: "epoch.txt", sizeBytes: 1, isDirectory: false, modifiedDate: date)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.modifiedDate?.timeIntervalSince1970 ?? -1, 0, accuracy: 1.0)
  }

  // MARK: - Data blob serialization

  func testReadRequestBookmarkWithRandomData() throws {
    var randomBytes = [UInt8](repeating: 0, count: 512)
    for i in 0..<randomBytes.count { randomBytes[i] = UInt8(i % 256) }
    let data = Data(randomBytes)
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: data)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark, data)
  }

  func testWriteRequestBookmarkEmptyData() throws {
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil, name: "f", size: 0, bookmark: Data())
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark, Data())
  }

  func testWriteRequestBookmarkSingleByte() throws {
    let req = WriteRequest(
      deviceId: "dev", storageId: 1, parentHandle: nil, name: "f", size: 1, bookmark: Data([0xFF]))
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark, Data([0xFF]))
  }

  // MARK: - Archive size verification

  func testArchiveSizeGrowsWithPayload() throws {
    let smallReq = ReadRequest(
      deviceId: "d", objectHandle: 1, bookmark: Data(repeating: 0, count: 10))
    let largeReq = ReadRequest(
      deviceId: "d", objectHandle: 1, bookmark: Data(repeating: 0, count: 100_000))
    let smallData = try archiveData(smallReq)
    let largeData = try archiveData(largeReq)
    XCTAssertTrue(largeData.count > smallData.count)
    XCTAssertTrue(largeData.count > 100_000, "Archive should contain the full payload")
  }

  // MARK: - Array serialization in responses

  func testObjectListPreservesOrder() throws {
    let objects = (0..<20)
      .map { i in
        ObjectInfo(
          handle: UInt32(i), name: "item_\(i)", sizeBytes: nil, isDirectory: i % 2 == 0,
          modifiedDate: nil)
      }
    let resp = ObjectListResponse(success: true, objects: objects)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    for i in 0..<20 {
      XCTAssertEqual(decoded?.objects?[i].handle, UInt32(i))
      XCTAssertEqual(decoded?.objects?[i].name, "item_\(i)")
      XCTAssertEqual(decoded?.objects?[i].isDirectory, i % 2 == 0)
    }
  }

  func testStorageListPreservesOrder() throws {
    let storages: [StorageInfo] = (0..<5)
      .map { i in
        let cap = UInt64(i * 100)
        let free = UInt64(i * 50)
        return StorageInfo(
          storageId: UInt32(i), description: "vol\(i)", capacityBytes: cap, freeBytes: free)
      }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    for i in 0..<5 {
      XCTAssertEqual(decoded?.storages?[i].storageId, UInt32(i))
      XCTAssertEqual(decoded?.storages?[i].storageDescription, "vol\(i)")
    }
  }

  // MARK: - Secure coding compliance

  func testAllTypesSupportsSecureCoding() {
    XCTAssertTrue(ReadRequest.supportsSecureCoding)
    XCTAssertTrue(ReadResponse.supportsSecureCoding)
    XCTAssertTrue(StorageInfo.supportsSecureCoding)
    XCTAssertTrue(StorageListRequest.supportsSecureCoding)
    XCTAssertTrue(StorageListResponse.supportsSecureCoding)
    XCTAssertTrue(ObjectInfo.supportsSecureCoding)
    XCTAssertTrue(ObjectListRequest.supportsSecureCoding)
    XCTAssertTrue(ObjectListResponse.supportsSecureCoding)
    XCTAssertTrue(WriteRequest.supportsSecureCoding)
    XCTAssertTrue(WriteResponse.supportsSecureCoding)
    XCTAssertTrue(DeleteRequest.supportsSecureCoding)
    XCTAssertTrue(CreateFolderRequest.supportsSecureCoding)
    XCTAssertTrue(RenameRequest.supportsSecureCoding)
    XCTAssertTrue(MoveObjectRequest.supportsSecureCoding)
    XCTAssertTrue(CrawlTriggerRequest.supportsSecureCoding)
    XCTAssertTrue(CrawlTriggerResponse.supportsSecureCoding)
    XCTAssertTrue(DeviceStatusRequest.supportsSecureCoding)
    XCTAssertTrue(DeviceStatusResponse.supportsSecureCoding)
  }

  // MARK: - Nested array depth

  func testDeeplyNestedObjectListViaMultipleStorages() throws {
    // 50 storages each with a description containing nested brackets
    let storages = (0..<50)
      .map { i in
        StorageInfo(
          storageId: UInt32(i),
          description: String(repeating: "[", count: 50) + "deep"
            + String(repeating: "]", count: 50), capacityBytes: 1, freeBytes: 0)
      }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 50)
  }

  // MARK: - Boolean field correctness

  func testDeleteRequestRecursiveFalseDoesNotDefault() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: 1, recursive: false)
    let decoded = try roundTrip(req, as: DeleteRequest.self)
    XCTAssertFalse(decoded!.recursive)
  }

  func testDeviceStatusResponseBoolCombinations() throws {
    for connected in [true, false] {
      for sessionOpen in [true, false] {
        let resp = DeviceStatusResponse(connected: connected, sessionOpen: sessionOpen)
        let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
        XCTAssertEqual(decoded?.connected, connected)
        XCTAssertEqual(decoded?.sessionOpen, sessionOpen)
      }
    }
  }

  func testReadResponseSuccessBoolPreserved() throws {
    for success in [true, false] {
      let resp = ReadResponse(success: success)
      let decoded = try roundTrip(resp, as: ReadResponse.self)
      XCTAssertEqual(decoded?.success, success)
    }
  }
}
