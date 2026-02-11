// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPXPC

final class XPCProtocolCoverageTests: XCTestCase {
    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T? {
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
    }

    func testReadRequestRoundTripWithBookmark() throws {
        let bookmark = Data([0x01, 0x02, 0x03])
        let request = ReadRequest(deviceId: "domain-1", objectHandle: 42, bookmark: bookmark)
        let decoded = try roundTrip(request, as: ReadRequest.self)
        XCTAssertEqual(decoded?.deviceId, "domain-1")
        XCTAssertEqual(decoded?.objectHandle, 42)
        XCTAssertEqual(decoded?.bookmark, bookmark)
    }

    func testReadResponseRoundTripWithAndWithoutSize() throws {
        let withSize = ReadResponse(
            success: true,
            errorMessage: nil,
            tempFileURL: URL(fileURLWithPath: "/tmp/sample"),
            fileSize: 1234
        )
        let decodedWithSize = try roundTrip(withSize, as: ReadResponse.self)
        XCTAssertEqual(decodedWithSize?.success, true)
        XCTAssertEqual(decodedWithSize?.fileSize, 1234)

        let withoutSize = ReadResponse(success: false, errorMessage: "boom", tempFileURL: nil, fileSize: nil)
        let decodedWithoutSize = try roundTrip(withoutSize, as: ReadResponse.self)
        XCTAssertEqual(decodedWithoutSize?.success, false)
        XCTAssertEqual(decodedWithoutSize?.errorMessage, "boom")
        XCTAssertNil(decodedWithoutSize?.fileSize)
    }

    func testStorageAndObjectProtocolModelsRoundTrip() throws {
        let storageInfo = StorageInfo(storageId: 7, description: "Internal", capacityBytes: 1000, freeBytes: 500)
        let listRequest = StorageListRequest(deviceId: "domain-2")
        let listResponse = StorageListResponse(success: true, storages: [storageInfo])

        let decodedStorageInfo = try roundTrip(storageInfo, as: StorageInfo.self)
        XCTAssertEqual(decodedStorageInfo?.storageId, 7)
        XCTAssertEqual(decodedStorageInfo?.storageDescription, "Internal")

        let decodedListRequest = try roundTrip(listRequest, as: StorageListRequest.self)
        XCTAssertEqual(decodedListRequest?.deviceId, "domain-2")

        let decodedListResponse = try roundTrip(listResponse, as: StorageListResponse.self)
        XCTAssertEqual(decodedListResponse?.success, true)
        XCTAssertEqual(decodedListResponse?.storages?.count, 1)
        XCTAssertEqual(decodedListResponse?.storages?.first?.freeBytes, 500)

        let objectInfo = ObjectInfo(handle: 10, name: "photo.jpg", sizeBytes: 4096, isDirectory: false, modifiedDate: Date(timeIntervalSince1970: 10))
        let objectRequest = ObjectListRequest(deviceId: "domain-3", storageId: 1, parentHandle: 2)
        let objectResponse = ObjectListResponse(success: true, objects: [objectInfo])
        let objectResponseNoParent = ObjectListRequest(deviceId: "domain-3", storageId: 1, parentHandle: nil)

        let decodedObjectInfo = try roundTrip(objectInfo, as: ObjectInfo.self)
        XCTAssertEqual(decodedObjectInfo?.handle, 10)
        XCTAssertEqual(decodedObjectInfo?.name, "photo.jpg")
        XCTAssertEqual(decodedObjectInfo?.sizeBytes, 4096)

        let decodedObjectRequest = try roundTrip(objectRequest, as: ObjectListRequest.self)
        XCTAssertEqual(decodedObjectRequest?.parentHandle, 2)
        let decodedObjectRequestNoParent = try roundTrip(objectResponseNoParent, as: ObjectListRequest.self)
        XCTAssertNil(decodedObjectRequestNoParent?.parentHandle)

        let decodedObjectResponse = try roundTrip(objectResponse, as: ObjectListResponse.self)
        XCTAssertEqual(decodedObjectResponse?.objects?.count, 1)
        XCTAssertEqual(decodedObjectResponse?.objects?.first?.name, "photo.jpg")
    }

    func testCrawlAndDeviceStatusModelsRoundTrip() throws {
        let crawlWithParent = CrawlTriggerRequest(deviceId: "domain-4", storageId: 9, parentHandle: 11)
        let crawlWithoutParent = CrawlTriggerRequest(deviceId: "domain-4", storageId: 9, parentHandle: nil)
        let accepted = CrawlTriggerResponse(accepted: true, errorMessage: nil)
        let rejected = CrawlTriggerResponse(accepted: false, errorMessage: "not configured")

        let decodedWithParent = try roundTrip(crawlWithParent, as: CrawlTriggerRequest.self)
        XCTAssertEqual(decodedWithParent?.parentHandle, 11)
        let decodedWithoutParent = try roundTrip(crawlWithoutParent, as: CrawlTriggerRequest.self)
        XCTAssertNil(decodedWithoutParent?.parentHandle)

        let decodedAccepted = try roundTrip(accepted, as: CrawlTriggerResponse.self)
        XCTAssertEqual(decodedAccepted?.accepted, true)
        XCTAssertNil(decodedAccepted?.errorMessage)
        let decodedRejected = try roundTrip(rejected, as: CrawlTriggerResponse.self)
        XCTAssertEqual(decodedRejected?.accepted, false)
        XCTAssertEqual(decodedRejected?.errorMessage, "not configured")

        let statusRequest = DeviceStatusRequest(deviceId: "domain-5")
        let statusResponse = DeviceStatusResponse(connected: true, sessionOpen: true, lastCrawlTimestamp: 123456)
        let decodedStatusRequest = try roundTrip(statusRequest, as: DeviceStatusRequest.self)
        XCTAssertEqual(decodedStatusRequest?.deviceId, "domain-5")

        let decodedStatusResponse = try roundTrip(statusResponse, as: DeviceStatusResponse.self)
        XCTAssertEqual(decodedStatusResponse?.connected, true)
        XCTAssertEqual(decodedStatusResponse?.sessionOpen, true)
        XCTAssertEqual(decodedStatusResponse?.lastCrawlTimestamp, 123456)
    }

    func testServiceNameConstant() {
        XCTAssertFalse(MTPXPCServiceName.isEmpty)
        XCTAssertTrue(MTPXPCServiceName.contains("swiftmtp"))
    }
}
