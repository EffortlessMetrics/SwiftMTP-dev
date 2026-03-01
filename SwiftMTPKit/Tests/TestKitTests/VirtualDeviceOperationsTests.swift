// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class VirtualDeviceOperationsTests: XCTestCase {

  // MARK: - Error States

  func testDeleteNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      try await device.delete(9999, recursive: false)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testRenameNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      try await device.rename(9999, to: "new.txt")
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testMoveNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      try await device.move(9999, to: nil)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testGetInfoNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      _ = try await device.getInfo(handle: 9999)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testReadNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }
    let dest = tempDir.appendingPathComponent("out.bin")
    do {
      _ = try await device.read(handle: 9999, range: nil, to: dest)
      XCTFail("Expected objectNotFound error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - CRUD Operations

  func testCreateFolderAndListChildren() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id

    let folderHandle = try await device.createFolder(
      parent: nil, name: "Photos", storage: storageId)
    XCTAssertGreaterThan(folderHandle, 0)

    var rootItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      rootItems.append(contentsOf: batch)
    }
    XCTAssertEqual(rootItems.count, 1)
    XCTAssertEqual(rootItems[0].name, "Photos")
  }

  func testWriteAndReadFullFile() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let content = Data("Hello, MTP World!".utf8)
    let sourceURL = try TestUtilities.createTempFile(
      directory: tempDir, filename: "upload.txt", content: content)
    _ = try await device.write(
      parent: nil, name: "upload.txt", size: UInt64(content.count), from: sourceURL)

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      items.append(contentsOf: batch)
    }
    let uploaded = try XCTUnwrap(items.first { $0.name == "upload.txt" })

    let downloadURL = tempDir.appendingPathComponent("download.txt")
    _ = try await device.read(handle: uploaded.handle, range: nil, to: downloadURL)
    XCTAssertEqual(try Data(contentsOf: downloadURL), content)
  }

  func testWriteAndReadPartialRange() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let content = Data("0123456789ABCDEF".utf8)
    let sourceURL = try TestUtilities.createTempFile(
      directory: tempDir, filename: "data.bin", content: content)
    _ = try await device.write(
      parent: nil, name: "data.bin", size: UInt64(content.count), from: sourceURL)

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      items.append(contentsOf: batch)
    }
    let file = try XCTUnwrap(items.first { $0.name == "data.bin" })

    let partialURL = tempDir.appendingPathComponent("partial.bin")
    _ = try await device.read(handle: file.handle, range: 4..<8, to: partialURL)
    XCTAssertEqual(try Data(contentsOf: partialURL), Data("4567".utf8))
  }

  func testRecursiveDelete() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id

    let parent = try await device.createFolder(
      parent: nil, name: "Parent", storage: storageId)
    let child = try await device.createFolder(
      parent: parent, name: "Child", storage: storageId)

    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }
    let fileURL = try TestUtilities.createTempFile(
      directory: tempDir, filename: "nested.txt", content: Data("nested".utf8))
    _ = try await device.write(parent: child, name: "nested.txt", size: 6, from: fileURL)

    try await device.delete(parent, recursive: true)

    var rootItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      rootItems.append(contentsOf: batch)
    }
    XCTAssertTrue(rootItems.isEmpty)
  }

  func testUnicodeFilenames() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id

    let names = ["日本語.txt", "Ünïcödé.pdf", "эмодзи🎉.png", "café.doc"]
    for name in names {
      _ = try await device.createFolder(parent: nil, name: name, storage: storageId)
    }

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      items.append(contentsOf: batch)
    }
    let itemNames = Set(items.map(\.name))
    for name in names {
      XCTAssertTrue(itemNames.contains(name), "Missing unicode name: \(name)")
    }
  }

  func testMoveObjectToNewParent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let folder = try await device.createFolder(
      parent: nil, name: "Dest", storage: storageId)
    let fileURL = try TestUtilities.createTempFile(
      directory: tempDir, filename: "moveme.txt", content: Data("data".utf8))
    _ = try await device.write(parent: nil, name: "moveme.txt", size: 4, from: fileURL)

    var rootItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      rootItems.append(contentsOf: batch)
    }
    let fileObj = try XCTUnwrap(rootItems.first { $0.name == "moveme.txt" })

    try await device.move(fileObj.handle, to: folder)

    var rootAfterMove: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      rootAfterMove.append(contentsOf: batch)
    }
    XCTAssertFalse(rootAfterMove.contains { $0.name == "moveme.txt" })

    var destItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: folder, in: storageId) {
      destItems.append(contentsOf: batch)
    }
    XCTAssertTrue(destItems.contains { $0.name == "moveme.txt" })
  }

  func testNestedFolderCreation() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id

    let l1 = try await device.createFolder(parent: nil, name: "L1", storage: storageId)
    let l2 = try await device.createFolder(parent: l1, name: "L2", storage: storageId)
    let l3 = try await device.createFolder(parent: l2, name: "L3", storage: storageId)

    var l2Children: [MTPObjectInfo] = []
    for try await batch in device.list(parent: l2, in: storageId) {
      l2Children.append(contentsOf: batch)
    }
    XCTAssertEqual(l2Children.count, 1)
    XCTAssertEqual(l2Children[0].name, "L3")

    let info = try await device.getInfo(handle: l3)
    XCTAssertEqual(info.name, "L3")
  }

  func testOperationRecordingParameters() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let storageId = storages[0].id

    _ = try await device.createFolder(parent: nil, name: "TestFolder", storage: storageId)

    let ops = await device.operations
    let createOp = try XCTUnwrap(ops.first { $0.operation == "createFolder" })
    XCTAssertEqual(createOp.parameters["name"], "TestFolder")
  }
}
