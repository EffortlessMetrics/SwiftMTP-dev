// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import FileProvider
import UniformTypeIdentifiers

final class FileProviderItemTests: XCTestCase {

  // MARK: - Item Creation Tests

  func testFileItemCreation() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.filename, "test.txt")
    XCTAssertEqual(item.documentSize?.intValue, 1024)
    XCTAssertNotEqual(item.contentType, .folder)
  }

  func testDirectoryItemCreation() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "DCIM",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.filename, "DCIM")
    XCTAssertNil(item.documentSize)
    XCTAssertEqual(item.contentType, .folder)
  }

  func testStorageItemCreation() {
    // Storage items have nil objectHandle
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: nil,
      parentHandle: nil,
      name: "Internal Storage",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.filename, "Internal Storage")
    XCTAssertEqual(item.itemIdentifier.rawValue, "device1:1")
    XCTAssertEqual(item.contentType, .folder)
  }

  // MARK: - Item Identifier Tests

  func testFileItemIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.itemIdentifier.rawValue, "device1:1:100")
  }

  func testStorageItemIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 2,
      objectHandle: nil,
      parentHandle: nil,
      name: "SD Card",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.itemIdentifier.rawValue, "device1:2")
  }

  func testDeviceRootItemIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: nil,
      objectHandle: nil,
      parentHandle: nil,
      name: "device1",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.itemIdentifier.rawValue, "device1")
  }

  // MARK: - Parent Item Identifier Tests

  func testFileParentIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,  // At storage root
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "device1:1")
  }

  func testNestedFileParentIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: 50,  // Nested in folder 50
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "device1:1:50")
  }

  func testStorageParentIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: nil,
      parentHandle: nil,
      name: "Internal Storage",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "device1")
  }

  func testDeviceRootParentIdentifier() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: nil,
      objectHandle: nil,
      parentHandle: nil,
      name: "device1",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.parentItemIdentifier, .rootContainer)
  }

  // MARK: - Content Type Tests

  func testDirectoryContentType() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "DCIM",
      size: nil,
      isDirectory: true,
      modifiedDate: nil
    )

    XCTAssertEqual(item.contentType, .folder)
  }

  func testTextFileContentType() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "readme.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.contentType.identifier, "public.plain-text")
  }

  func testImageFileContentType() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "photo.jpg",
      size: 2048,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.contentType, .jpeg)
  }

  func testUnknownFileContentType() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "unknown.xyz",
      size: 100,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertTrue(item.contentType.conforms(to: .data))
  }

  func testCaseInsensitiveContentType() {
    let item1 = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "PHOTO.JPG",
      size: 2048,
      isDirectory: false,
      modifiedDate: nil
    )

    let item2 = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 101,
      parentHandle: nil,
      name: "photo.jpg",
      size: 2048,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item1.contentType, item2.contentType)
  }

  // MARK: - Modified Date Tests

  func testModifiedDate() {
    let date = Date()
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: date
    )

    XCTAssertEqual(item.contentModificationDate, date)
  }

  func testNilModifiedDate() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertNil(item.contentModificationDate)
  }

  // MARK: - Item Parsing Tests

  func testParseDeviceRootIdentifier() {
    let identifier = NSFileProviderItemIdentifier("device1")
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, "device1")
    XCTAssertNil(components?.storageId)
    XCTAssertNil(components?.objectHandle)
  }

  func testParseStorageIdentifier() {
    let identifier = NSFileProviderItemIdentifier("device1:5")
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, "device1")
    XCTAssertEqual(components?.storageId, 5)
    XCTAssertNil(components?.objectHandle)
  }

  func testParseObjectIdentifier() {
    let identifier = NSFileProviderItemIdentifier("device1:5:100")
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, "device1")
    XCTAssertEqual(components?.storageId, 5)
    XCTAssertEqual(components?.objectHandle, 100)
  }

  func testParseRootContainerReturnsNil() {
    let identifier = NSFileProviderItemIdentifier.rootContainer
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNil(components)
  }

  func testParseInvalidIdentifier() {
    let identifier = NSFileProviderItemIdentifier("invalid")
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, "invalid")
  }

  func testParseIdentifierWithExtraColons() {
    // Extra colons are currently treated as invalid identifier format.
    let identifier = NSFileProviderItemIdentifier("device1:5:100:extra")
    let components = MTPFileProviderItem.parseItemIdentifier(identifier)

    XCTAssertNil(components)
  }

  // MARK: - Size Tests

  func testLargeFileSize() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "large.zip",
      size: 4_000_000_000,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.documentSize?.int64Value, 4_000_000_000)
  }

  func testZeroFileSize() {
    let item = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "empty.txt",
      size: 0,
      isDirectory: false,
      modifiedDate: nil
    )

    XCTAssertEqual(item.documentSize?.intValue, 0)
  }

  // MARK: - Item Equality

  func testItemEquality() {
    let date = Date()
    let item1 = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: date
    )

    let item2 = MTPFileProviderItem(
      deviceId: "device1",
      storageId: 1,
      objectHandle: 100,
      parentHandle: nil,
      name: "test.txt",
      size: 1024,
      isDirectory: false,
      modifiedDate: date
    )

    XCTAssertEqual(item1.itemIdentifier, item2.itemIdentifier)
  }
}
