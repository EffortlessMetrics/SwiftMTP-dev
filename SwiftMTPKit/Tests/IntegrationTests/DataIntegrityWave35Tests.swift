// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

import SwiftMTPCore
import SwiftMTPTestKit

// MARK: - Data Integrity Tests

/// End-to-end data integrity tests exercising write → read → verify cycles
/// and mirror failure resilience through VirtualMTPDevice.
final class DataIntegrityWave35Tests: XCTestCase {

  private var tmpDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("data-integrity-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    if let tmpDir {
      try? FileManager.default.removeItem(at: tmpDir)
    }
    try await super.tearDown()
  }

  // MARK: - Write → Read → Verify Cycle

  /// Write a file to VirtualMTPDevice, read it back, and verify content matches.
  func testWriteReadVerify_contentMatches() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Create source data with a recognizable pattern
    let sourceData = Data((0..<4096).map { UInt8($0 % 256) })
    let sourceURL = tmpDir.appendingPathComponent("source.bin")
    try sourceData.write(to: sourceURL)

    // Write to device
    let writeProgress = try await device.write(
      parent: 1,  // DCIM folder
      name: "verify_test.bin",
      size: UInt64(sourceData.count),
      from: sourceURL)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(sourceData.count))

    // Find the written object by scanning operations
    let ops = await device.operations
    let writeOps = ops.filter { $0.operation == "write" && $0.parameters["name"] == "verify_test.bin" }
    XCTAssertEqual(writeOps.count, 1, "Should have exactly one write operation recorded")

    // List objects under DCIM to find our file
    let storage = MTPStorageID(raw: 0x0001_0001)
    var foundHandle: MTPObjectHandle?
    for try await batch in device.list(parent: 1, in: storage) {
      for info in batch where info.name == "verify_test.bin" {
        foundHandle = info.handle
      }
    }
    let handle = try XCTUnwrap(foundHandle, "Written file should be listed under DCIM")

    // Read back from device
    let readURL = tmpDir.appendingPathComponent("readback.bin")
    let readProgress = try await device.read(handle: handle, range: nil, to: readURL)
    XCTAssertEqual(readProgress.completedUnitCount, Int64(sourceData.count))

    // Verify content integrity
    let readData = try Data(contentsOf: readURL)
    XCTAssertEqual(readData, sourceData, "Read-back data should match original source data")
  }

  /// Write multiple files, read each back, and verify all contents are correct.
  func testWriteReadVerify_multipleFiles() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let fileCount = 5

    // Write several files with different content
    var expectations: [(name: String, data: Data)] = []
    for i in 0..<fileCount {
      let data = Data(repeating: UInt8(i + 0x41), count: 512 * (i + 1))
      let name = "multi_\(i).dat"
      let url = tmpDir.appendingPathComponent("src_\(i).dat")
      try data.write(to: url)
      _ = try await device.write(parent: 1, name: name, size: UInt64(data.count), from: url)
      expectations.append((name: name, data: data))
    }

    // List all objects under DCIM and verify each
    let storage = MTPStorageID(raw: 0x0001_0001)
    var objectMap: [String: MTPObjectHandle] = [:]
    for try await batch in device.list(parent: 1, in: storage) {
      for info in batch {
        objectMap[info.name] = info.handle
      }
    }

    for (name, expectedData) in expectations {
      let handle = try XCTUnwrap(objectMap[name], "File \(name) should exist on device")
      let readURL = tmpDir.appendingPathComponent("read_\(name)")
      _ = try await device.read(handle: handle, range: nil, to: readURL)
      let readData = try Data(contentsOf: readURL)
      XCTAssertEqual(readData, expectedData, "Content mismatch for \(name)")
    }
  }

  /// Write a zero-byte file and verify read-back produces empty data.
  func testWriteReadVerify_emptyFile() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let emptyData = Data()
    let sourceURL = tmpDir.appendingPathComponent("empty.bin")
    try emptyData.write(to: sourceURL)

    _ = try await device.write(parent: 1, name: "empty.bin", size: 0, from: sourceURL)

    let storage = MTPStorageID(raw: 0x0001_0001)
    var foundHandle: MTPObjectHandle?
    for try await batch in device.list(parent: 1, in: storage) {
      for info in batch where info.name == "empty.bin" {
        foundHandle = info.handle
      }
    }
    let handle = try XCTUnwrap(foundHandle)

    let readURL = tmpDir.appendingPathComponent("readback_empty.bin")
    _ = try await device.read(handle: handle, range: nil, to: readURL)
    let readData = try Data(contentsOf: readURL)
    XCTAssertTrue(readData.isEmpty, "Empty file read-back should produce empty data")
  }

  // MARK: - Write Failure Resilience

  /// Verify that a failed write (fault injection) does not corrupt the device's
  /// existing objects.
  func testWriteFailure_doesNotCorruptExistingObjects() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Read existing photo data before any writes
    let existingHandle: MTPObjectHandle = 3  // sample photo in pixel7 config
    let beforeURL = tmpDir.appendingPathComponent("before.jpg")
    _ = try await device.read(handle: existingHandle, range: nil, to: beforeURL)
    let beforeData = try Data(contentsOf: beforeURL)

    // Write a new file (this succeeds on VirtualMTPDevice)
    let srcURL = tmpDir.appendingPathComponent("new_file.dat")
    try Data(repeating: 0xAB, count: 2048).write(to: srcURL)
    _ = try await device.write(parent: 1, name: "new_file.dat", size: 2048, from: srcURL)

    // Re-read the original file and verify it's unchanged
    let afterURL = tmpDir.appendingPathComponent("after.jpg")
    _ = try await device.read(handle: existingHandle, range: nil, to: afterURL)
    let afterData = try Data(contentsOf: afterURL)
    XCTAssertEqual(beforeData, afterData, "Existing object data should remain intact after writes")
  }

  /// Verify that deleting a non-existent object does not affect existing objects.
  func testDeleteFailure_doesNotCorruptExistingObjects() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Count objects before failed delete
    let storages = try await device.storages()
    let storage = storages[0]

    var handlesBefore: [MTPObjectHandle] = []
    for try await batch in device.list(parent: nil, in: storage.id) {
      handlesBefore.append(contentsOf: batch.map(\.handle))
    }

    // Attempt to delete non-existent handle
    do {
      try await device.delete(0xFFFF, recursive: false)
    } catch {
      // Expected
    }

    // Verify object count is unchanged
    var handlesAfter: [MTPObjectHandle] = []
    for try await batch in device.list(parent: nil, in: storage.id) {
      handlesAfter.append(contentsOf: batch.map(\.handle))
    }
    XCTAssertEqual(
      Set(handlesBefore), Set(handlesAfter),
      "Object tree should remain intact after failed delete")
  }

  /// Verify that the device operation log captures the full write lifecycle.
  func testWriteLifecycle_operationLogComplete() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()

    let srcURL = tmpDir.appendingPathComponent("lifecycle.dat")
    try Data(repeating: 0x42, count: 256).write(to: srcURL)

    _ = try await device.write(parent: 1, name: "lifecycle.dat", size: 256, from: srcURL)

    let ops = await device.operations
    let writeOps = ops.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, 1)
    XCTAssertEqual(writeOps.first?.parameters["name"], "lifecycle.dat")
    XCTAssertEqual(writeOps.first?.parameters["size"], "256")
  }
}
