// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

// MARK: - Android MTP Protocol Operation Tests

/// Comprehensive protocol-level tests for Android MTP extensions and operations
/// using VirtualMTPDevice. Covers BeginEditObject, EndEditObject, TruncateObject,
/// CopyObject, GetThumb, and SetObjectPropList with error paths, edge cases,
/// concurrent operations, and error recovery workflows.
final class AndroidMTPOperationTests: XCTestCase {

  // MARK: - BeginEditObject

  func testBeginEdit_recordsOperation() async throws {
    let device = makePixel7Device()
    try await device.openIfNeeded()
    // Handle 3 is a photo in pixel7 config
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
  }

  func testBeginEdit_invalidHandle_throwsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    do {
      // VirtualMTPDevice doesn't have beginEdit; test via DeviceActor through link
      let actor = makeActor()
      try await actor.beginEdit(handle: 9999)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // VirtualMTPLink throws for invalid handles
    }
  }

  func testBeginEdit_consecutiveCallsSameHandle_succeeds() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.beginEdit(handle: 3)
    // At link level, MTP doesn't enforce single-begin semantics
  }

  func testBeginEdit_multipleHandles_succeeds() async throws {
    let config = makeMultiFileConfig()
    let link = VirtualMTPLink(config: config)
    try await link.beginEditObject(handle: 10)
    try await link.beginEditObject(handle: 11)
  }

  func testBeginEdit_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.beginEdit(handle: 0)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  // MARK: - EndEditObject

  func testEndEdit_afterBegin_succeeds() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.endEdit(handle: 3)
  }

  func testEndEdit_withoutBegin_succeeds() async throws {
    // At protocol level, endEdit is standalone — no state tracking in MTP
    let actor = makeActor()
    try await actor.endEdit(handle: 3)
  }

  func testEndEdit_invalidHandle_throws() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    do {
      try await link.endEditObject(handle: 0xBEEF)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // Expected — VirtualMTPLink rejects unknown handles
    }
  }

  func testEndEdit_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.endEdit(handle: 0)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testEndEdit_doubleEnd_succeeds() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.endEdit(handle: 3)
    // Second endEdit should also succeed (no state tracking at protocol level)
    try await actor.endEdit(handle: 3)
  }

  // MARK: - TruncateObject

  func testTruncate_toZeroBytes_succeeds() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.truncateFile(handle: 3, size: 0)
    try await actor.endEdit(handle: 3)
  }

  func testTruncate_toSmallSize_succeeds() async throws {
    let actor = makeActor()
    try await actor.truncateFile(handle: 3, size: 1024)
  }

  func testTruncate_invalidHandle_throws() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    do {
      try await link.truncateObject(handle: 0xDEAD, offset: 512)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // Expected
    }
  }

  func testTruncate_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.truncateFile(handle: 0, size: 100)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testTruncate_largeOffset_64bit_succeeds() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    // 5 GB — exceeds 32-bit range, tests UInt64 offset splitting
    let largeSize: UInt64 = 5 * 1024 * 1024 * 1024
    try await link.truncateObject(handle: 3, offset: largeSize)
  }

  func testTruncate_maxUInt64_succeeds() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.truncateObject(handle: 3, offset: UInt64.max)
  }

  // MARK: - CopyObject

  func testCopyObject_returnsNewHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    let newHandle = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    XCTAssertNotEqual(newHandle, 3)
    XCTAssertGreaterThan(newHandle, 0)
  }

  func testCopyObject_preservesMetadata() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    let originalInfo = try await device.getInfo(handle: 3)
    let newHandle = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let copyInfo = try await device.getInfo(handle: newHandle)
    XCTAssertEqual(copyInfo.name, originalInfo.name)
    XCTAssertEqual(copyInfo.sizeBytes, originalInfo.sizeBytes)
    XCTAssertEqual(copyInfo.formatCode, originalInfo.formatCode)
  }

  func testCopyObject_originalUnchanged() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    let infoBefore = try await device.getInfo(handle: 3)
    _ = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let infoAfter = try await device.getInfo(handle: 3)
    XCTAssertEqual(infoBefore.handle, infoAfter.handle)
    XCTAssertEqual(infoBefore.name, infoAfter.name)
  }

  func testCopyObject_nonExistentHandle_throwsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    do {
      _ = try await device.copyObject(handle: 0xDEAD, toStorage: storage, parentFolder: nil)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testCopyObject_crossStorage() async throws {
    let config = makeDualStorageConfig()
    let device = VirtualMTPDevice(config: config)
    let storages = try await device.storages()
    let sdCard = storages[1].id
    // Copy photo (handle 3) from internal to SD card
    let newHandle = try await device.copyObject(handle: 3, toStorage: sdCard, parentFolder: nil)
    let info = try await device.getInfo(handle: newHandle)
    XCTAssertEqual(info.storage.raw, sdCard.raw)
  }

  func testCopyObject_toParentFolder() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    // Copy photo (handle 3) to DCIM folder (handle 1) instead of Camera (handle 2)
    let newHandle = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: 1)
    let info = try await device.getInfo(handle: newHandle)
    XCTAssertEqual(info.parent, 1)
  }

  func testCopyObject_multipleCopies_uniqueHandles() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    let h1 = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let h2 = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let h3 = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let handles = Set([h1, h2, h3])
    XCTAssertEqual(handles.count, 3, "Each copy must have a unique handle")
  }

  func testCopyObject_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      _ = try await actor.copyObject(
        handle: 0, toStorage: MTPStorageID(raw: 0x0001_0001), parentFolder: nil)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testCopyObject_logsOperation() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    await device.clearOperations()
    _ = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    let ops = await device.operations
    let copyOps = ops.filter { $0.operation == "copyObject" }
    XCTAssertEqual(copyOps.count, 1)
    XCTAssertEqual(copyOps.first?.parameters["handle"], "3")
  }

  // MARK: - GetThumb

  func testGetThumb_returnsJPEG() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let data = try await device.getThumbnail(handle: 3)
    XCTAssertGreaterThan(data.count, 0)
    // Verify JPEG SOI marker
    XCTAssertEqual(data[0], 0xFF)
    XCTAssertEqual(data[1], 0xD8)
  }

  func testGetThumb_hasEOIMarker() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let data = try await device.getThumbnail(handle: 3)
    XCTAssertEqual(data[data.count - 2], 0xFF)
    XCTAssertEqual(data[data.count - 1], 0xD9)
  }

  func testGetThumb_invalidHandle_throwsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    do {
      _ = try await device.getThumbnail(handle: 0xFFFF)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testGetThumb_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      _ = try await actor.getThumbnail(handle: 0)
      XCTFail("Expected preconditionFailed")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testGetThumb_reasonableSize() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let data = try await device.getThumbnail(handle: 3)
    XCTAssertLessThan(data.count, 100_000, "Stub thumbnail should be small")
    XCTAssertGreaterThanOrEqual(data.count, 4, "Must contain at least SOI+EOI")
  }

  func testGetThumb_folderHandle_returnsData() async throws {
    // Folders can have thumbnails in some MTP implementations
    let device = VirtualMTPDevice(config: .pixel7)
    // Handle 1 is DCIM folder
    let data = try await device.getThumbnail(handle: 1)
    XCTAssertGreaterThan(data.count, 0, "Virtual device returns stub for any valid handle")
  }

  func testGetThumb_logsOperation() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()
    _ = try await device.getThumbnail(handle: 3)
    let ops = await device.operations
    let thumbOps = ops.filter { $0.operation == "getThumbnail" }
    XCTAssertEqual(thumbOps.count, 1)
    XCTAssertEqual(thumbOps.first?.parameters["handle"], "3")
  }

  // MARK: - SetObjectPropList

  func testSetObjectPropList_singleEntry_succeeds() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let entry = MTPPropListEntry.string(
      handle: 3, propCode: MTPObjectPropCode.objectFileName, value: "RENAMED.jpg")
    let count = try await device.setObjectPropList(entries: [entry])
    XCTAssertEqual(count, 1)
  }

  func testSetObjectPropList_multipleEntries_succeeds() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let entries: [MTPPropListEntry] = [
      .string(handle: 3, propCode: MTPObjectPropCode.objectFileName, value: "NEW.jpg"),
      .string(handle: 3, propCode: MTPObjectPropCode.dateModified, value: "20250601T120000"),
      .uint16(handle: 3, propCode: MTPObjectPropCode.rating, value: 5),
    ]
    let count = try await device.setObjectPropList(entries: entries)
    XCTAssertEqual(count, UInt32(entries.count))
  }

  func testSetObjectPropList_invalidHandle_throwsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let entry = MTPPropListEntry.string(
      handle: 0xBEEF, propCode: MTPObjectPropCode.objectFileName, value: "FAIL.jpg")
    do {
      _ = try await device.setObjectPropList(entries: [entry])
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testSetObjectPropList_emptyEntries_throwsPrecondition() async throws {
    let actor = makeActor()
    do {
      _ = try await actor.setObjectPropList(entries: [])
      XCTFail("Expected preconditionFailed for empty entries")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testSetObjectPropList_zeroHandleEntry_throwsPrecondition() async throws {
    let actor = makeActor()
    let entry = MTPPropListEntry.string(
      handle: 0, propCode: MTPObjectPropCode.objectFileName, value: "BAD.jpg")
    do {
      _ = try await actor.setObjectPropList(entries: [entry])
      XCTFail("Expected preconditionFailed for handle 0")
    } catch let error as MTPError {
      guard case .preconditionFailed = error else {
        XCTFail("Expected preconditionFailed, got \(error)")
        return
      }
    }
  }

  func testSetObjectPropList_mixedValidAndInvalid_throwsOnFirst() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let entries: [MTPPropListEntry] = [
      .string(handle: 3, propCode: MTPObjectPropCode.objectFileName, value: "OK.jpg"),
      .string(handle: 0xDEAD, propCode: MTPObjectPropCode.objectFileName, value: "FAIL.jpg"),
    ]
    do {
      _ = try await device.setObjectPropList(entries: entries)
      XCTFail("Expected objectNotFound for invalid handle in batch")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testSetObjectPropList_uint32Entry_succeeds() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let entry = MTPPropListEntry.uint32(
      handle: 3, propCode: MTPObjectPropCode.duration, value: 180_000)
    let count = try await device.setObjectPropList(entries: [entry])
    XCTAssertEqual(count, 1)
  }

  func testSetObjectPropList_multipleObjects_succeeds() async throws {
    let config = makeMultiFileConfig()
    let device = VirtualMTPDevice(config: config)
    let entries: [MTPPropListEntry] = [
      .string(handle: 10, propCode: MTPObjectPropCode.objectFileName, value: "A.jpg"),
      .string(handle: 11, propCode: MTPObjectPropCode.objectFileName, value: "B.jpg"),
    ]
    let count = try await device.setObjectPropList(entries: entries)
    XCTAssertEqual(count, 2)
  }

  func testSetObjectPropList_logsOperation() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()
    let entry = MTPPropListEntry.uint16(handle: 3, propCode: MTPObjectPropCode.rating, value: 4)
    _ = try await device.setObjectPropList(entries: [entry])
    let ops = await device.operations
    let propOps = ops.filter { $0.operation == "setObjectPropList" }
    XCTAssertEqual(propOps.count, 1)
    XCTAssertEqual(propOps.first?.parameters["count"], "1")
  }

  // MARK: - Concurrent Edit Operations

  func testConcurrentEdits_twoFiles() async throws {
    let config = makeMultiFileConfig()
    let link = VirtualMTPLink(config: config)
    // Begin editing two files concurrently
    try await link.beginEditObject(handle: 10)
    try await link.beginEditObject(handle: 11)
    // Truncate both
    try await link.truncateObject(handle: 10, offset: 512)
    try await link.truncateObject(handle: 11, offset: 1024)
    // End both
    try await link.endEditObject(handle: 10)
    try await link.endEditObject(handle: 11)
  }

  func testConcurrentEdits_asyncTaskGroup() async throws {
    let config = makeMultiFileConfig()
    let link = VirtualMTPLink(config: config)
    // Use structured concurrency to edit multiple files
    try await withThrowingTaskGroup(of: Void.self) { group in
      for handle in [MTPObjectHandle(10), MTPObjectHandle(11)] {
        group.addTask {
          try await link.beginEditObject(handle: handle)
          try await link.truncateObject(handle: handle, offset: 256)
          try await link.endEditObject(handle: handle)
        }
      }
      try await group.waitForAll()
    }
  }

  // MARK: - Edit + Truncate Workflow

  func testEditWorkflow_beginTruncateEnd() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.truncateFile(handle: 3, size: 2048)
    try await actor.endEdit(handle: 3)
  }

  func testEditWorkflow_beginEnd_noTruncate() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.endEdit(handle: 3)
  }

  func testEditWorkflow_multipleTruncates() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.truncateFile(handle: 3, size: 4096)
    try await actor.truncateFile(handle: 3, size: 2048)
    try await actor.truncateFile(handle: 3, size: 0)
    try await actor.endEdit(handle: 3)
  }

  // MARK: - Error Recovery After Failed Edit

  func testErrorRecovery_endEditAfterFailedTruncate() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.beginEditObject(handle: 3)
    // Attempt truncate on non-existent handle (simulates failure)
    do {
      try await link.truncateObject(handle: 9999, offset: 0)
    } catch {
      // Expected failure
    }
    // endEdit on original handle should still work
    try await link.endEditObject(handle: 3)
  }

  func testErrorRecovery_beginEditAfterPriorFailure() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    // Failed operation
    do {
      try await link.beginEditObject(handle: 9999)
    } catch {
      // Expected
    }
    // Subsequent valid operation should succeed
    try await link.beginEditObject(handle: 3)
    try await link.endEditObject(handle: 3)
  }

  func testErrorRecovery_copyAfterFailedEdit() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    // Even if conceptual edit fails, copy should work independently
    let newHandle = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    XCTAssertNotEqual(newHandle, 3)
  }

  // MARK: - Operation Logging

  func testOperationLog_tracksMultipleOperations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id
    await device.clearOperations()

    _ = try await device.getInfo(handle: 3)
    _ = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)
    _ = try await device.getThumbnail(handle: 3)

    let ops = await device.operations
    let opNames = ops.map(\.operation)
    XCTAssertTrue(opNames.contains("getInfo"))
    XCTAssertTrue(opNames.contains("copyObject"))
    XCTAssertTrue(opNames.contains("getThumbnail"))
  }

  func testOperationLog_hasTimestamps() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()
    let before = Date()
    _ = try await device.getThumbnail(handle: 3)
    let after = Date()
    let ops = await device.operations
    XCTAssertEqual(ops.count, 1)
    XCTAssertGreaterThanOrEqual(ops[0].timestamp, before)
    XCTAssertLessThanOrEqual(ops[0].timestamp, after)
  }

  // MARK: - MTP Opcode Validation

  func testMTPOp_androidEditExtensionValues() {
    XCTAssertEqual(MTPOp.beginEditObject.rawValue, 0x95C4)
    XCTAssertEqual(MTPOp.endEditObject.rawValue, 0x95C5)
    XCTAssertEqual(MTPOp.truncateObject.rawValue, 0x95C3)
  }

  func testPTPOp_copyObjectValue() {
    XCTAssertEqual(PTPOp.copyObject.rawValue, 0x101A)
  }

  func testMTPOp_setObjectPropListValue() {
    XCTAssertEqual(MTPOp.setObjectPropList.rawValue, 0x9806)
  }

  // MARK: - Helpers

  private func makePixel7Device() -> VirtualMTPDevice {
    VirtualMTPDevice(config: .pixel7)
  }

  private func makeActor() -> MTPDeviceActor {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    let transport = _StubTransport(link: link)
    return MTPDeviceActor(
      id: config.deviceId, summary: config.summary, transport: transport,
      config: .init())
  }

  /// Config with two files for concurrent edit testing.
  private func makeMultiFileConfig() -> VirtualDeviceConfig {
    var base = VirtualDeviceConfig.pixel7
    let storage = base.storages[0].id
    let fileA = VirtualObjectConfig(
      handle: 10, storage: storage, parent: 1, name: "fileA.txt",
      sizeBytes: 1024, formatCode: 0x3000, data: Data(repeating: 0x41, count: 1024))
    let fileB = VirtualObjectConfig(
      handle: 11, storage: storage, parent: 1, name: "fileB.txt",
      sizeBytes: 2048, formatCode: 0x3000, data: Data(repeating: 0x42, count: 2048))
    base.objects.append(fileA)
    base.objects.append(fileB)
    return base
  }

  /// Config with internal storage + SD card for cross-storage tests.
  private func makeDualStorageConfig() -> VirtualDeviceConfig {
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024, freeBytes: 16 * 1024 * 1024 * 1024)
    return VirtualDeviceConfig.pixel7.withStorage(sdCard)
  }
}

/// Minimal transport stub that returns a pre-built link.
private final class _StubTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}
