// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPXPC

/// Tests for message serialization edge cases across XPC boundary.
final class XPCSerializationEdgeCaseTests: XCTestCase {

  private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
    let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }

  // MARK: - Boundary values

  func testReadRequestMaxObjectHandle() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: UInt32.max)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.objectHandle, UInt32.max)
  }

  func testReadRequestZeroObjectHandle() throws {
    let req = ReadRequest(deviceId: "dev", objectHandle: 0)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.objectHandle, 0)
  }

  func testReadResponseMaxFileSize() throws {
    let resp = ReadResponse(success: true, fileSize: UInt64.max)
    let decoded = try roundTrip(resp, as: ReadResponse.self)
    XCTAssertEqual(decoded?.fileSize, UInt64.max)
  }

  func testStorageInfoMaxCapacity() throws {
    let info = StorageInfo(storageId: UInt32.max, description: "Max", capacityBytes: UInt64.max, freeBytes: UInt64.max)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.capacityBytes, UInt64.max)
    XCTAssertEqual(decoded?.freeBytes, UInt64.max)
  }

  func testObjectInfoZeroSize() throws {
    let info = ObjectInfo(handle: 0, name: "empty", sizeBytes: 0, isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.sizeBytes, 0)
    XCTAssertNil(decoded?.modifiedDate)
  }

  func testObjectInfoNilSize() throws {
    let info = ObjectInfo(handle: 1, name: "nosize", sizeBytes: nil, isDirectory: false, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertNil(decoded?.sizeBytes)
  }

  // MARK: - Empty strings

  func testReadRequestEmptyDeviceId() throws {
    let req = ReadRequest(deviceId: "", objectHandle: 1)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, "")
  }

  func testStorageInfoEmptyDescription() throws {
    let info = StorageInfo(storageId: 1, description: "", capacityBytes: 0, freeBytes: 0)
    let decoded = try roundTrip(info, as: StorageInfo.self)
    XCTAssertEqual(decoded?.storageDescription, "")
  }

  func testObjectInfoEmptyName() throws {
    let info = ObjectInfo(handle: 1, name: "", sizeBytes: nil, isDirectory: true, modifiedDate: nil)
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, "")
  }

  // MARK: - Unicode strings

  func testDeviceIdWithUnicode() throws {
    let emoji = "📱-device-Ñ-日本語"
    let req = ReadRequest(deviceId: emoji, objectHandle: 42)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.deviceId, emoji)
  }

  func testObjectNameWithSpecialCharacters() throws {
    let name = "photo (1) [backup].jpg"
    let info = ObjectInfo(handle: 1, name: name, sizeBytes: 1024, isDirectory: false, modifiedDate: Date())
    let decoded = try roundTrip(info, as: ObjectInfo.self)
    XCTAssertEqual(decoded?.name, name)
  }

  func testFolderNameWithUnicodeCharacters() throws {
    let name = "文档/照片"
    let req = CreateFolderRequest(deviceId: "dev", storageId: 1, parentHandle: nil, name: name)
    let decoded = try roundTrip(req, as: CreateFolderRequest.self)
    XCTAssertEqual(decoded?.name, name)
  }

  // MARK: - Large bookmark data

  func testReadRequestLargeBookmark() throws {
    let largeBookmark = Data(repeating: 0xAB, count: 64 * 1024)
    let req = ReadRequest(deviceId: "dev", objectHandle: 1, bookmark: largeBookmark)
    let decoded = try roundTrip(req, as: ReadRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 64 * 1024)
    XCTAssertEqual(decoded?.bookmark, largeBookmark)
  }

  func testWriteRequestLargeBookmark() throws {
    let largeBookmark = Data(repeating: 0xCD, count: 128 * 1024)
    let req = WriteRequest(deviceId: "dev", storageId: 1, parentHandle: nil, name: "big.bin", size: 1_000_000, bookmark: largeBookmark)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.bookmark?.count, 128 * 1024)
  }

  // MARK: - Empty collections

  func testStorageListResponseEmptyStorages() throws {
    let resp = StorageListResponse(success: true, storages: [])
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 0)
  }

  func testObjectListResponseEmptyObjects() throws {
    let resp = ObjectListResponse(success: true, objects: [])
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 0)
  }

  func testStorageListResponseNilStorages() throws {
    let resp = StorageListResponse(success: false, errorMessage: "err", storages: nil)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertNil(decoded?.storages)
  }

  func testObjectListResponseNilObjects() throws {
    let resp = ObjectListResponse(success: false, errorMessage: "err", objects: nil)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertNil(decoded?.objects)
  }

  // MARK: - Multiple objects in list

  func testStorageListResponseMultipleStorages() throws {
    var storages: [StorageInfo] = []
    for i in 0..<5 {
      let info = StorageInfo(storageId: UInt32(i), description: "Storage \(i)", capacityBytes: UInt64(i * 1000), freeBytes: UInt64(i * 500))
      storages.append(info)
    }
    let resp = StorageListResponse(success: true, storages: storages)
    let decoded = try roundTrip(resp, as: StorageListResponse.self)
    XCTAssertEqual(decoded?.storages?.count, 5)
    XCTAssertEqual(decoded?.storages?[3].storageDescription, "Storage 3")
  }

  func testObjectListResponseMultipleObjects() throws {
    var objects: [ObjectInfo] = []
    for i in 0..<10 {
      let obj = ObjectInfo(handle: UInt32(i), name: "item\(i)", sizeBytes: UInt64(i * 100), isDirectory: i % 2 == 0, modifiedDate: nil)
      objects.append(obj)
    }
    let resp = ObjectListResponse(success: true, objects: objects)
    let decoded = try roundTrip(resp, as: ObjectListResponse.self)
    XCTAssertEqual(decoded?.objects?.count, 10)
    XCTAssertEqual(decoded?.objects?[5].isDirectory, false)
  }

  // MARK: - Write types edge cases

  func testWriteRequestMaxSize() throws {
    let req = WriteRequest(deviceId: "dev", storageId: 1, parentHandle: nil, name: "huge.bin", size: UInt64.max, bookmark: nil)
    let decoded = try roundTrip(req, as: WriteRequest.self)
    XCTAssertEqual(decoded?.size, UInt64.max)
  }

  func testDeleteRequestNonRecursive() throws {
    let req = DeleteRequest(deviceId: "dev", objectHandle: 42, recursive: false)
    let decoded = try roundTrip(req, as: DeleteRequest.self)
    XCTAssertFalse(decoded!.recursive)
  }

  func testRenameRequestEmptyName() throws {
    let req = RenameRequest(deviceId: "dev", objectHandle: 1, newName: "")
    let decoded = try roundTrip(req, as: RenameRequest.self)
    XCTAssertEqual(decoded?.newName, "")
  }

  func testMoveObjectRequestMaxStorageId() throws {
    let req = MoveObjectRequest(deviceId: "dev", objectHandle: 1, newParentHandle: UInt32.max, newStorageId: UInt32.max)
    let decoded = try roundTrip(req, as: MoveObjectRequest.self)
    XCTAssertEqual(decoded?.newParentHandle, UInt32.max)
    XCTAssertEqual(decoded?.newStorageId, UInt32.max)
  }

  // MARK: - DeviceStatus edge cases

  func testDeviceStatusResponseZeroTimestamp() throws {
    let resp = DeviceStatusResponse(connected: false, sessionOpen: false, lastCrawlTimestamp: 0)
    let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, 0)
  }

  func testDeviceStatusResponseMaxTimestamp() throws {
    let resp = DeviceStatusResponse(connected: true, sessionOpen: true, lastCrawlTimestamp: Int64.max)
    let decoded = try roundTrip(resp, as: DeviceStatusResponse.self)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, Int64.max)
  }

  // MARK: - CrawlTrigger edge cases

  func testCrawlTriggerRequestWithAllFields() throws {
    let req = CrawlTriggerRequest(deviceId: "dev", storageId: UInt32.max, parentHandle: UInt32.max)
    let decoded = try roundTrip(req, as: CrawlTriggerRequest.self)
    XCTAssertEqual(decoded?.storageId, UInt32.max)
    XCTAssertEqual(decoded?.parentHandle, UInt32.max)
  }

  func testCrawlTriggerResponseWithLongErrorMessage() throws {
    let longMsg = String(repeating: "error ", count: 1000)
    let resp = CrawlTriggerResponse(accepted: false, errorMessage: longMsg)
    let decoded = try roundTrip(resp, as: CrawlTriggerResponse.self)
    XCTAssertEqual(decoded?.errorMessage, longMsg)
  }

  // MARK: - NSSecureCoding conformance

  func testAllTypesReportSecureCoding() {
    XCTAssertTrue(ReadRequest.supportsSecureCoding)
    XCTAssertTrue(ReadResponse.supportsSecureCoding)
    XCTAssertTrue(StorageInfo.supportsSecureCoding)
    XCTAssertTrue(StorageListRequest.supportsSecureCoding)
    XCTAssertTrue(StorageListResponse.supportsSecureCoding)
    XCTAssertTrue(ObjectInfo.supportsSecureCoding)
    XCTAssertTrue(ObjectListRequest.supportsSecureCoding)
    XCTAssertTrue(ObjectListResponse.supportsSecureCoding)
    XCTAssertTrue(WriteRequest.supportsSecureCoding)
    XCTAssertTrue(DeleteRequest.supportsSecureCoding)
    XCTAssertTrue(CreateFolderRequest.supportsSecureCoding)
    XCTAssertTrue(WriteResponse.supportsSecureCoding)
    XCTAssertTrue(RenameRequest.supportsSecureCoding)
    XCTAssertTrue(MoveObjectRequest.supportsSecureCoding)
    XCTAssertTrue(CrawlTriggerRequest.supportsSecureCoding)
    XCTAssertTrue(CrawlTriggerResponse.supportsSecureCoding)
    XCTAssertTrue(DeviceStatusRequest.supportsSecureCoding)
    XCTAssertTrue(DeviceStatusResponse.supportsSecureCoding)
  }
}
