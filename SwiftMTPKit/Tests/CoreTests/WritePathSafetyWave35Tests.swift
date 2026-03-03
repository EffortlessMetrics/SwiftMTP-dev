// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - In-Memory Transfer Journal

/// Minimal in-memory transfer journal for write-path safety tests.
private actor TestTransferJournal: TransferJournal {
  var entries: [String: TransferRecord] = [:]
  private var nextID = 0

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String,
    size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    nextID += 1
    let id = "read-\(nextID)"
    entries[id] = TransferRecord(
      id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: finalURL, state: "active", updatedAt: Date())
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String,
    size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    nextID += 1
    let id = "write-\(nextID)"
    entries[id] = TransferRecord(
      id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: sourceURL, state: "active", updatedAt: Date())
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {
    guard let record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: committed, supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: record.state, updatedAt: Date())
  }

  func fail(id: String, error: Error) async throws {
    guard let record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: record.committedBytes, supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: "failed", updatedAt: Date())
  }

  func complete(id: String) async throws {
    guard let record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: record.totalBytes ?? record.committedBytes,
      supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: "completed", updatedAt: Date())
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    entries.values.filter { $0.deviceId.raw == device.raw && $0.state == "active" }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {
    let cutoff = Date().addingTimeInterval(-olderThan)
    entries = entries.filter { $0.value.updatedAt > cutoff }
  }
}

// MARK: - Write-Path Safety Tests

/// Tests for MTP write-path data integrity and safety invariants.
final class WritePathSafetyWave35Tests: XCTestCase {

  // MARK: - a. Partial write detection via journal

  /// Simulate a write that is journaled then marked as failed, verifying
  /// the transfer journal correctly records incomplete state.
  func testPartialWriteDetection_journalRecordsIncomplete() async throws {
    let journal = TestTransferJournal()
    let deviceId = MTPDeviceID(raw: "test:partial")
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    // Begin a write entry in the journal
    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "big_file.bin",
      size: 10_000_000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    // Simulate partial progress
    try await journal.updateProgress(id: transferId, committed: 4_000_000)

    // Simulate fault — mark as failed (incomplete transfer)
    try await journal.fail(id: transferId, error: MTPError.transport(.timeout))

    // Verify the journal shows the transfer as failed with partial progress
    let entries = await journal.entries
    let record = try XCTUnwrap(entries[transferId])
    XCTAssertEqual(record.state, "failed")
    XCTAssertEqual(record.committedBytes, 4_000_000)
    XCTAssertEqual(record.totalBytes, 10_000_000)
    XCTAssertNotEqual(record.committedBytes, record.totalBytes)
  }

  /// Verify that a fault-injected write on VirtualMTPDevice propagates
  /// as a transport error that can be caught and journaled.
  func testPartialWriteFaultInjection_throwsTransportError() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand),
        error: .disconnected,
        repeatCount: 0,
        label: "disconnect-mid-write"
      )
    ])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    // executeStreamingCommand is used internally for SendObject.
    // The fault should cause it to throw.
    do {
      let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1)  // SendObject
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected transport error from fault injection")
    } catch {
      // Verify we got a transport-level error
      XCTAssertTrue(error is TransportError, "Expected TransportError, got \(type(of: error))")
    }
  }

  // MARK: - b. DeleteObject safety

  /// Delete of a non-existent handle should throw objectNotFound.
  func testDeleteNonExistentObject_throwsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let nonExistentHandle: MTPObjectHandle = 0xDEAD

    do {
      try await device.delete(nonExistentHandle, recursive: false)
      XCTFail("Expected objectNotFound error for non-existent handle")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  /// Delete at the link layer for a missing handle should throw a transport I/O error.
  func testDeleteNonExistentObjectViaLink_throwsError() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let nonExistentHandle: MTPObjectHandle = 0xBEEF

    do {
      try await link.deleteObject(handle: nonExistentHandle)
      XCTFail("Expected error for deleting non-existent object")
    } catch {
      // VirtualMTPLink throws TransportError.io for missing objects
      XCTAssertTrue(error is TransportError)
    }
  }

  /// Fault-injected accessDenied on deleteObject simulates a protected object.
  func testDeleteProtectedObject_throwsAccessDenied() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.deleteObject),
        error: .accessDenied,
        repeatCount: 1,
        label: "delete-protected"
      )
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .pixel7), schedule: schedule)

    do {
      try await link.deleteObject(handle: 3)  // handle 3 exists in pixel7 config
      XCTFail("Expected accessDenied error for protected object")
    } catch let error as TransportError {
      XCTAssertEqual(error, .accessDenied)
    }
  }

  // MARK: - c. Write to read-only storage

  /// Verify that a VirtualMTPDevice with a read-only storage config reports
  /// the storage as read-only in its storage info.
  func testReadOnlyStorageInfo_isReported() async throws {
    let readOnlyStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "Read-Only SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 0,
      isReadOnly: true
    )
    let config = VirtualDeviceConfig.emptyDevice.withStorage(readOnlyStorage)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    let roStorage = storages.first { $0.isReadOnly }
    XCTAssertNotNil(roStorage, "Expected at least one read-only storage")
    XCTAssertTrue(roStorage!.isReadOnly)
  }

  /// VirtualMTPLink reports read-only storage info correctly through getStorageInfo.
  func testReadOnlyStorageViaLink_reportsReadOnly() async throws {
    let readOnlyStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Read-Only Card",
      capacityBytes: 16 * 1024 * 1024 * 1024,
      freeBytes: 0,
      isReadOnly: true
    )
    let config = VirtualDeviceConfig(
      deviceId: MTPDeviceID(raw: "test:ro"),
      summary: MTPDeviceSummary(
        id: MTPDeviceID(raw: "test:ro"), manufacturer: "Test", model: "RO",
        vendorID: 0, productID: 0, bus: 0, address: 0),
      info: MTPDeviceInfo(
        manufacturer: "Test", model: "RO", version: "1.0", serialNumber: "RO001",
        operationsSupported: Set([0x1001, 0x1002, 0x1003, 0x1004].map { UInt16($0) }),
        eventsSupported: Set()),
      storages: [readOnlyStorage]
    )
    let link = VirtualMTPLink(config: config)
    let storageInfo = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
    XCTAssertTrue(storageInfo.isReadOnly)
  }

  // MARK: - d. Concurrent writes serialized through actor

  /// Verify that concurrent write calls to the same VirtualMTPDevice actor
  /// are serialized (no data races) and all succeed.
  func testConcurrentWritesSerialized_allSucceed() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("concurrent-write-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let writeCount = 10
    var sourceURLs: [URL] = []

    // Create source files
    for i in 0..<writeCount {
      let url = tmpDir.appendingPathComponent("src_\(i).dat")
      let data = Data(repeating: UInt8(i), count: 1024)
      try data.write(to: url)
      sourceURLs.append(url)
    }

    // Launch concurrent writes via TaskGroup
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<writeCount {
        let url = sourceURLs[i]
        let name = "concurrent_\(i).dat"
        group.addTask {
          _ = try await device.write(
            parent: 1,  // DCIM folder in pixel7 config
            name: name,
            size: 1024,
            from: url)
        }
      }
      try await group.waitForAll()
    }

    // All writes should have been recorded
    let ops = await device.operations
    let writeOps = ops.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, writeCount)
  }

  // MARK: - e. Write verification (checksum / size mismatch)

  /// Verify that MTPError.verificationFailed captures expected vs actual sizes.
  func testWriteVerificationFailed_capturesSizeMismatch() {
    let error = MTPError.verificationFailed(expected: 10_000, actual: 8_000)

    if case .verificationFailed(let expected, let actual) = error {
      XCTAssertEqual(expected, 10_000)
      XCTAssertEqual(actual, 8_000)
    } else {
      XCTFail("Expected verificationFailed error case")
    }

    // Check error description mentions the mismatch
    XCTAssertTrue(
      error.localizedDescription.contains("8000") || error.localizedDescription.contains("8,000"),
      "Error description should mention actual size")
    XCTAssertTrue(
      error.localizedDescription.contains("10000") || error.localizedDescription.contains("10,000"),
      "Error description should mention expected size")
  }

  /// Verify that two verificationFailed errors with different values are not equal.
  func testWriteVerificationFailed_equatableDistinguishes() {
    let err1 = MTPError.verificationFailed(expected: 100, actual: 50)
    let err2 = MTPError.verificationFailed(expected: 100, actual: 99)
    let err3 = MTPError.verificationFailed(expected: 100, actual: 50)

    XCTAssertNotEqual(err1, err2)
    XCTAssertEqual(err1, err3)
  }

  /// Verify the recovery suggestion for verification failure advises re-send.
  func testWriteVerificationFailed_recoverySuggestion() {
    let error = MTPError.verificationFailed(expected: 5000, actual: 4000)
    XCTAssertNotNil(error.recoverySuggestion)
    XCTAssertTrue(error.recoverySuggestion?.lowercased().contains("re-send") ?? false)
  }

  // MARK: - f. Storage-full handling

  /// Verify MTPError.storageFull is distinct and provides meaningful messages.
  func testStorageFullError_hasProperDescription() {
    let error = MTPError.storageFull

    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription?.lowercased().contains("full") ?? false)
    XCTAssertNotNil(error.recoverySuggestion)
    XCTAssertTrue(error.recoverySuggestion?.lowercased().contains("free") ?? false)
  }

  /// Verify storageFull is distinguishable from other write-related errors.
  func testStorageFullError_isDistinct() {
    XCTAssertNotEqual(MTPError.storageFull, MTPError.readOnly)
    XCTAssertNotEqual(MTPError.storageFull, MTPError.objectWriteProtected)
    XCTAssertNotEqual(MTPError.storageFull, MTPError.permissionDenied)
  }

  /// A VirtualMTPDevice with zero free bytes reports freeBytes == 0 in storage info.
  func testStorageFullCondition_reportedInStorageInfo() async throws {
    let fullStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Full Storage",
      capacityBytes: 64 * 1024 * 1024 * 1024,
      freeBytes: 0,
      isReadOnly: false
    )
    let config = VirtualDeviceConfig(
      deviceId: MTPDeviceID(raw: "test:full"),
      summary: MTPDeviceSummary(
        id: MTPDeviceID(raw: "test:full"), manufacturer: "Test", model: "Full",
        vendorID: 0, productID: 0, bus: 0, address: 0),
      info: MTPDeviceInfo(
        manufacturer: "Test", model: "Full", version: "1.0", serialNumber: "FULL001",
        operationsSupported: Set([0x1001, 0x1002, 0x1003, 0x1004].map { UInt16($0) }),
        eventsSupported: Set()),
      storages: [fullStorage]
    )
    let link = VirtualMTPLink(config: config)
    let info = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
    XCTAssertEqual(info.freeBytes, 0, "Storage should report zero free bytes")
  }

  /// Protocol error code 0x200C (StoreFull) maps correctly in error descriptions.
  func testProtocolStoreFull_errorCode200C() {
    let error = MTPError.protocolError(code: 0x200C, message: nil)
    XCTAssertTrue(
      error.errorDescription?.contains("full") ?? false,
      "Protocol error 0x200C should mention storage full")
  }
}
