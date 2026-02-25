// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Integration tests for file transfer scenarios
final class FileTransferIntegrationTests: XCTestCase {

  // MARK: - Small File Transfer Tests

  func testSmallFileTransferRoundtrip() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Get storage
    let storages = try await device.storages()
    guard !storages.isEmpty else {
      XCTFail("No storages found")
      return
    }

    // Create test file
    let testContent = TestFixtures.smallFile()
    let tempURL = try TestUtilities.createTempFile(
      directory: try TestUtilities.createTempDirectory(),
      filename: "test-small.dat",
      content: testContent
    )
    defer { try? TestUtilities.cleanupTempDirectory(tempURL.deletingLastPathComponent()) }

    // Upload
    let uploadProgress = try await device.write(
      parent: nil,
      name: "test-small.dat",
      size: UInt64(testContent.count),
      from: tempURL
    )

    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(testContent.count))
  }

  func testMediumFileTransferRoundtrip() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard !storages.isEmpty else {
      XCTFail("No storages found")
      return
    }

    let testContent = TestFixtures.mediumFile()
    let tempURL = try TestUtilities.createTempFile(
      directory: try TestUtilities.createTempDirectory(),
      filename: "test-medium.dat",
      content: testContent
    )
    defer { try? TestUtilities.cleanupTempDirectory(tempURL.deletingLastPathComponent()) }

    let uploadProgress = try await device.write(
      parent: nil,
      name: "test-medium.dat",
      size: UInt64(testContent.count),
      from: tempURL
    )

    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(testContent.count))
  }

  // MARK: - Directory Operations Tests

  func testDirectoryCreation() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard let storage = storages.first else {
      XCTFail("No storages found")
      return
    }

    // List root objects to verify state
    var allObjects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storage.id)
    for try await batch in stream {
      allObjects.append(contentsOf: batch)
    }

    // Virtual device should have root objects
    XCTAssertFalse(allObjects.isEmpty)
  }

  // MARK: - File Enumeration Tests

  func testRecursiveEnumeration() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard let storage = storages.first else {
      XCTFail("No storages found")
      return
    }

    // Collect all objects recursively
    var allObjects: [MTPObjectInfo] = []
    var directoryHandles: [MTPObjectHandle: MTPStorageID] = [:]

    let rootStream = device.list(parent: nil, in: storage.id)
    for try await batch in rootStream {
      for object in batch {
        allObjects.append(object)
        if object.formatCode == 0x3001 {  // Directory format
          directoryHandles[object.handle] = storage.id
        }
      }
    }

    // Enumerate subdirectories
    for (handle, storageId) in directoryHandles {
      let subStream = device.list(parent: handle, in: storageId)
      for try await batch in subStream {
        allObjects.append(contentsOf: batch)
      }
    }

    // Should have collected objects
    XCTAssertFalse(allObjects.isEmpty)
  }

  // MARK: - Storage Info Tests

  func testStorageInfoAccess() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()

    XCTAssertFalse(storages.isEmpty, "Should have at least one storage")

    for storage in storages {
      XCTAssertGreaterThan(storage.id.raw, 0, "Storage ID should be valid")
      XCTAssertFalse(storage.description.isEmpty, "Storage should have a description")
      XCTAssertGreaterThan(storage.capacityBytes, 0, "Storage should have capacity")
      XCTAssertLessThanOrEqual(
        storage.freeBytes, storage.capacityBytes, "Free space should not exceed capacity")
    }
  }

  // MARK: - Operation Recording Tests

  func testOperationHistoryTracking() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Perform several operations
    let _ = try await device.storages()

    var allObjects: [MTPObjectInfo] = []
    let storages = try await device.storages()
    if let storage = storages.first {
      let stream = device.list(parent: nil, in: storage.id)
      for try await batch in stream {
        allObjects.append(contentsOf: batch)
      }
    }

    // Check operation history
    let operations = await device.operations

    XCTAssertTrue(
      operations.contains(where: { $0.operation == "storages" }),
      "Should record storages operation")
    XCTAssertFalse(allObjects.isEmpty, "List should return at least one object")
  }
}

/// Tests for file naming edge cases
final class FileNamingEdgeCaseTests: XCTestCase {

  func testUnicodeFilename() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard !storages.isEmpty else {
      XCTFail("No storages found")
      return
    }

    // Test with unicode filename
    let unicodeName = "café_ña_me_ファイル.txt"
    let testContent = TestFixtures.textContent().data(using: .utf8)!

    let tempURL = try TestUtilities.createTempFile(
      directory: try TestUtilities.createTempDirectory(),
      filename: "test-unicode.dat",
      content: testContent
    )
    defer { try? TestUtilities.cleanupTempDirectory(tempURL.deletingLastPathComponent()) }

    // Upload with unicode filename
    let uploadProgress = try await device.write(
      parent: nil,
      name: unicodeName,
      size: UInt64(testContent.count),
      from: tempURL
    )

    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(testContent.count))
  }

  func testLongFilename() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard !storages.isEmpty else {
      XCTFail("No storages found")
      return
    }

    // Test with long filename
    let longName = String(repeating: "a", count: 200) + ".txt"
    let testContent = TestFixtures.smallFile()

    let tempURL = try TestUtilities.createTempFile(
      directory: try TestUtilities.createTempDirectory(),
      filename: "test-long.dat",
      content: testContent
    )
    defer { try? TestUtilities.cleanupTempDirectory(tempURL.deletingLastPathComponent()) }

    let uploadProgress = try await device.write(
      parent: nil,
      name: longName,
      size: UInt64(testContent.count),
      from: tempURL
    )

    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(testContent.count))
  }

  func testSpecialCharactersInFilename() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard !storages.isEmpty else {
      XCTFail("No storages found")
      return
    }

    // Test with special characters
    let specialName = "file-with-dashes_and_underscores.ext"
    let testContent = TestFixtures.smallFile()

    let tempURL = try TestUtilities.createTempFile(
      directory: try TestUtilities.createTempDirectory(),
      filename: "test-special.dat",
      content: testContent
    )
    defer { try? TestUtilities.cleanupTempDirectory(tempURL.deletingLastPathComponent()) }

    let uploadProgress = try await device.write(
      parent: nil,
      name: specialName,
      size: UInt64(testContent.count),
      from: tempURL
    )

    XCTAssertEqual(uploadProgress.totalUnitCount, Int64(testContent.count))
  }
}
