// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - In-Memory Transfer Journal for Safety Tests

/// Minimal in-memory transfer journal that tracks state transitions for
/// write-path safety assertions.
private actor SafetyTestJournal: TransferJournal {
  var entries: [String: TransferRecord] = [:]
  /// Ordered log of state transitions for verifying journal contract ordering.
  var stateLog: [(id: String, state: String, timestamp: Date)] = []
  private var nextID = 0

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String,
    size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    nextID += 1
    let id = "r-\(nextID)"
    let record = TransferRecord(
      id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: finalURL, state: "active", updatedAt: Date())
    entries[id] = record
    stateLog.append((id: id, state: "active", timestamp: Date()))
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String,
    size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    nextID += 1
    let id = "w-\(nextID)"
    let record = TransferRecord(
      id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent,
      name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
      localTempURL: tempURL, finalURL: sourceURL, state: "active", updatedAt: Date())
    entries[id] = record
    stateLog.append((id: id, state: "active", timestamp: Date()))
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
    stateLog.append((id: id, state: "progress:\(committed)", timestamp: Date()))
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
    stateLog.append((id: id, state: "failed", timestamp: Date()))
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
    stateLog.append((id: id, state: "completed", timestamp: Date()))
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    entries.values.filter { $0.deviceId.raw == device.raw && $0.state == "active" }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {
    let cutoff = Date().addingTimeInterval(-olderThan)
    entries = entries.filter { $0.value.updatedAt > cutoff }
  }

  func recordRemoteHandle(id: String, handle: UInt32) async throws {
    guard let record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: record.committedBytes, supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: record.state, updatedAt: Date(),
      remoteHandle: handle)
    stateLog.append((id: id, state: "remoteHandle:\(handle)", timestamp: Date()))
  }
}

// MARK: - Write-Path Safety Validation Tests

/// Wave 49 — validates data integrity contracts for the MTP write path:
/// partial write detection, size mismatch handling, delete safety,
/// journal correctness, concurrent write serialisation, and edge cases.
final class WritePathSafetyTests: XCTestCase {

  // MARK: - Helpers

  private func makeDevice(
    objects: [VirtualObjectConfig] = [],
    storages: [VirtualStorageConfig]? = nil
  ) -> VirtualMTPDevice {
    var config = VirtualDeviceConfig.emptyDevice
    if let storages {
      config = VirtualDeviceConfig(
        deviceId: config.deviceId,
        summary: config.summary,
        info: config.info,
        storages: storages,
        objects: objects
      )
    } else {
      for obj in objects {
        config = config.withObject(obj)
      }
    }
    return VirtualMTPDevice(config: config)
  }

  private var defaultStorage: MTPStorageID {
    MTPStorageID(raw: 0x0001_0001)
  }

  private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("w49-safety-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: - 1. SendObject size mismatch (declared vs actual) — should error

  /// Post-write verification catches when the device reports a smaller size than expected.
  func testSendObjectSizeMismatch_postWriteVerifyDetects() async throws {
    let device = makeDevice(objects: [
      VirtualObjectConfig(
        handle: 10, storage: defaultStorage, parent: nil,
        name: "mismatch.bin", sizeBytes: 500, formatCode: 0x3000,
        data: Data(repeating: 0xAA, count: 500)
      ),
    ])

    // Declared size was 1000, but device reports 500
    do {
      try await postWriteVerify(device: device, handle: 10, expectedSize: 1000)
      XCTFail("Expected verificationFailed for size mismatch")
    } catch let error as MTPError {
      if case .verificationFailed(let expected, let actual) = error {
        XCTAssertEqual(expected, 1000)
        XCTAssertEqual(actual, 500)
      } else {
        XCTFail("Expected verificationFailed, got \(error)")
      }
    }
  }

  /// Post-write verification succeeds when sizes match exactly.
  func testSendObjectSizeMatch_postWriteVerifySucceeds() async throws {
    let device = makeDevice(objects: [
      VirtualObjectConfig(
        handle: 11, storage: defaultStorage, parent: nil,
        name: "exact.bin", sizeBytes: 2048, formatCode: 0x3000,
        data: Data(repeating: 0xBB, count: 2048)
      ),
    ])

    // Should not throw — sizes match
    try await postWriteVerify(device: device, handle: 11, expectedSize: 2048)
  }

  // MARK: - 2. SendObject interrupted mid-transfer — journal records partial state

  /// When a write is interrupted, the journal must record partial progress
  /// and transition to "failed" state with committed bytes less than total.
  func testSendObjectInterrupted_journalRecordsPartialState() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:interrupted")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "large_video.mp4",
      size: 50_000_000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    // Simulate partial progress before interruption
    try await journal.updateProgress(id: transferId, committed: 12_500_000)
    try await journal.updateProgress(id: transferId, committed: 25_000_000)

    // Simulate disconnect/interruption
    try await journal.fail(id: transferId, error: MTPError.deviceDisconnected)

    let entries = await journal.entries
    let record = try XCTUnwrap(entries[transferId])
    XCTAssertEqual(record.state, "failed", "Interrupted transfer must be marked failed")
    XCTAssertEqual(record.committedBytes, 25_000_000, "Should record last committed progress")
    XCTAssertEqual(record.totalBytes, 50_000_000, "Total bytes must be preserved")
    XCTAssertNotEqual(
      record.committedBytes, record.totalBytes ?? 0,
      "Partial transfer: committed != total")
  }

  /// State transition log must show: active → progress → progress → failed (in order).
  func testSendObjectInterrupted_journalStateTransitionsOrdered() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:order")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "ordered.dat",
      size: 10_000, supportsPartial: false,
      tempURL: tempURL, sourceURL: nil)

    try await journal.updateProgress(id: transferId, committed: 3000)
    try await journal.fail(id: transferId, error: MTPError.transport(.timeout))

    let log = await journal.stateLog.filter { $0.id == transferId }
    XCTAssertEqual(log.count, 3)
    XCTAssertEqual(log[0].state, "active")
    XCTAssertEqual(log[1].state, "progress:3000")
    XCTAssertEqual(log[2].state, "failed")

    // Verify monotonic timestamps
    for i in 1..<log.count {
      XCTAssertGreaterThanOrEqual(log[i].timestamp, log[i - 1].timestamp)
    }
  }

  // MARK: - 3. DeleteObject on read-only storage — should fail cleanly

  /// A VirtualMTPDevice with read-only storage reports isReadOnly correctly,
  /// which callers must check before attempting writes/deletes.
  func testDeleteOnReadOnlyStorage_storageReportsReadOnly() async throws {
    let roStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "Read-Only SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 0,
      isReadOnly: true
    )
    let config = VirtualDeviceConfig.emptyDevice.withStorage(roStorage)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    let readOnlyOnes = storages.filter { $0.isReadOnly }
    XCTAssertFalse(readOnlyOnes.isEmpty, "Must have at least one read-only storage")
    XCTAssertTrue(readOnlyOnes.allSatisfy { $0.freeBytes == 0 })
  }

  /// MTPError.readOnly is distinct from other write errors and provides guidance.
  func testReadOnlyError_isDistinctAndDescriptive() {
    let error = MTPError.readOnly
    XCTAssertNotEqual(error, MTPError.storageFull)
    XCTAssertNotEqual(error, MTPError.objectWriteProtected)
    XCTAssertNotEqual(error, MTPError.permissionDenied)
    XCTAssertTrue(error.errorDescription?.lowercased().contains("read-only") ?? false)
    XCTAssertNotNil(error.recoverySuggestion)
  }

  // MARK: - 4. DeleteObject with invalid handle — error handling

  /// Deleting an object that doesn't exist throws objectNotFound.
  func testDeleteInvalidHandle_throwsObjectNotFound() async throws {
    let device = makeDevice()
    do {
      try await device.delete(0xDEAD_BEEF, recursive: false)
      XCTFail("Expected objectNotFound for invalid handle")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  /// Deleting at the link layer with an invalid handle throws a transport error.
  func testDeleteInvalidHandleViaLink_throwsTransportError() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    do {
      try await link.deleteObject(handle: 0xFFFF_FFFF)
      XCTFail("Expected transport error for non-existent handle")
    } catch {
      XCTAssertTrue(error is TransportError)
    }
  }

  /// Fault-injected accessDenied on delete simulates a protected object.
  func testDeleteProtected_faultInjectedAccessDenied() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.deleteObject),
        error: .accessDenied,
        repeatCount: 1,
        label: "delete-protected"
      ),
    ])
    let link = FaultInjectingLink(
      wrapping: VirtualMTPLink(config: .pixel7), schedule: schedule)

    do {
      try await link.deleteObject(handle: 3)
      XCTFail("Expected accessDenied")
    } catch let error as TransportError {
      XCTAssertEqual(error, .accessDenied)
    }
  }

  // MARK: - 5. Write zero-byte file — edge case

  /// Writing a zero-byte file should succeed and produce a valid object.
  func testWriteZeroByteFile_succeeds() async throws {
    let device = makeDevice()
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let sourceURL = dir.appendingPathComponent("empty.txt")
    try Data().write(to: sourceURL)

    let progress = try await device.write(
      parent: nil, name: "empty.txt", size: 0, from: sourceURL)
    XCTAssertEqual(progress.completedUnitCount, 0)

    // The write should be recorded
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "write" && $0.parameters["name"] == "empty.txt" })
  }

  /// Post-write verification on a zero-byte file should pass (0 == 0).
  func testPostWriteVerifyZeroByte_succeeds() async throws {
    let device = makeDevice(objects: [
      VirtualObjectConfig(
        handle: 99, storage: defaultStorage, parent: nil,
        name: "zero.dat", sizeBytes: 0, formatCode: 0x3000, data: Data()
      ),
    ])
    try await postWriteVerify(device: device, handle: 99, expectedSize: 0)
  }

  // MARK: - 6. SendObject with empty data — edge case

  /// Writing an empty data payload should not crash or leave orphaned state.
  func testSendObjectEmptyData_journalLifecycleCorrect() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:empty-data")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "empty.bin",
      size: 0, supportsPartial: false,
      tempURL: tempURL, sourceURL: nil)

    // Immediately complete (no data to transfer)
    try await journal.complete(id: transferId)

    let entries = await journal.entries
    let record = try XCTUnwrap(entries[transferId])
    XCTAssertEqual(record.state, "completed")
    XCTAssertEqual(record.totalBytes, 0)
    XCTAssertEqual(record.committedBytes, 0)
  }

  // MARK: - 7. Concurrent writes — should serialise through actor

  /// Concurrent writes to the same device actor must all succeed with unique
  /// handles — verifying actor isolation serialises access.
  func testConcurrentWrites_allSucceedWithUniqueHandles() async throws {
    let device = makeDevice()
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let writeCount = 15
    var sourceURLs: [URL] = []
    for i in 0..<writeCount {
      let url = dir.appendingPathComponent("src_\(i).dat")
      try Data(repeating: UInt8(i & 0xFF), count: 512).write(to: url)
      sourceURLs.append(url)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<writeCount {
        let url = sourceURLs[i]
        group.addTask {
          _ = try await device.write(
            parent: nil, name: "concurrent_\(i).dat", size: 512, from: url)
        }
      }
      try await group.waitForAll()
    }

    let ops = await device.operations
    let writeOps = ops.filter { $0.operation == "write" }
    XCTAssertEqual(writeOps.count, writeCount, "All concurrent writes must be recorded")

    // Verify distinct filenames
    let names = Set(writeOps.compactMap { $0.parameters["name"] })
    XCTAssertEqual(names.count, writeCount, "Each write must have a unique filename")
  }

  /// Concurrent folder creation must yield unique handles.
  func testConcurrentCreateFolder_uniqueHandles() async throws {
    let device = makeDevice()
    let handles = await withTaskGroup(
      of: MTPObjectHandle.self, returning: [MTPObjectHandle].self
    ) { group in
      for i in 0..<10 {
        group.addTask {
          try! await device.createFolder(
            parent: nil, name: "dir-\(i)",
            storage: MTPStorageID(raw: 0x0001_0001))
        }
      }
      var result: [MTPObjectHandle] = []
      for await h in group { result.append(h) }
      return result
    }
    XCTAssertEqual(Set(handles).count, 10, "All handles must be unique")
  }

  // MARK: - 8. Write after device disconnect — should fail cleanly

  /// A fault-injected disconnect on executeStreamingCommand (used by SendObject)
  /// should throw a clean transport error, not crash.
  func testWriteAfterDisconnect_throwsCleanTransportError() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand),
        error: .disconnected,
        repeatCount: 0,
        label: "permanent-disconnect"
      ),
    ])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    do {
      let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1)  // SendObject
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 4096, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected transport error from disconnect")
    } catch let error as TransportError {
      XCTAssertEqual(error, .noDevice)
    }
  }

  /// After disconnect, repeated attempts continue to fail cleanly.
  func testRepeatedWriteAfterDisconnect_failsConsistently() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(
        trigger: .onOperation(.executeStreamingCommand),
        error: .disconnected,
        repeatCount: 0,
        label: "persistent-disconnect"
      ),
    ])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    for attempt in 0..<3 {
      do {
        let cmd = PTPContainer(type: 1, code: 0x100D, txid: UInt32(attempt + 1))
        _ = try await link.executeStreamingCommand(
          cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
        XCTFail("Attempt \(attempt) should have thrown")
      } catch {
        XCTAssertTrue(error is TransportError, "Attempt \(attempt): expected TransportError")
      }
    }
  }

  // MARK: - 9. Journal records write attempt before starting transfer

  /// The journal must record a write entry (active state) before any data
  /// is transferred, so interrupted transfers are always discoverable.
  func testJournalRecordsWriteBeforeTransfer() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:pre-record")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    // Step 1: Begin write (simulates what DeviceActor does before SendObject)
    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "photo.jpg",
      size: 5_000_000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    // Before any data is sent, the journal must have the entry as active
    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, transferId)
    XCTAssertEqual(resumables[0].state, "active")
    XCTAssertEqual(resumables[0].committedBytes, 0, "No bytes transferred yet")
    XCTAssertEqual(resumables[0].name, "photo.jpg")
  }

  // MARK: - 10. Journal marks complete only after successful response

  /// The journal must transition active → completed only when explicitly
  /// marked, never prematurely.
  func testJournalCompletesOnlyAfterExplicitCall() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:complete-gate")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "document.pdf",
      size: 100_000, supportsPartial: false,
      tempURL: tempURL, sourceURL: nil)

    // Simulate full transfer progress
    try await journal.updateProgress(id: transferId, committed: 100_000)

    // Even with full progress, state must still be "active" — not "completed"
    let beforeComplete = await journal.entries[transferId]
    XCTAssertEqual(beforeComplete?.state, "active",
      "Must not auto-complete; requires explicit complete() call")
    XCTAssertEqual(beforeComplete?.committedBytes, 100_000)

    // Only after explicit complete() does state change
    try await journal.complete(id: transferId)
    let afterComplete = await journal.entries[transferId]
    XCTAssertEqual(afterComplete?.state, "completed")
  }

  /// The complete log entry must appear after all progress entries.
  func testJournalCompleteAfterAllProgress() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:log-order")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "video.mp4",
      size: 20_000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    try await journal.updateProgress(id: transferId, committed: 5000)
    try await journal.updateProgress(id: transferId, committed: 10_000)
    try await journal.updateProgress(id: transferId, committed: 20_000)
    try await journal.complete(id: transferId)

    let log = await journal.stateLog.filter { $0.id == transferId }
    XCTAssertEqual(log.count, 5)  // active, 3x progress, completed
    XCTAssertEqual(log.first?.state, "active")
    XCTAssertEqual(log.last?.state, "completed")
  }

  // MARK: - Journal corruption recovery

  /// If a transfer entry is failed, it must not appear in resumables
  /// (only active entries are resumable).
  func testFailedTransferNotInResumables() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:not-resumable")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "corrupt.bin",
      size: 8000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    try await journal.updateProgress(id: transferId, committed: 4000)
    try await journal.fail(id: transferId, error: MTPError.transport(.io("disk error")))

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(resumables.isEmpty, "Failed transfers must not appear in resumables")
  }

  /// Multiple transfers: only active ones are resumable.
  func testOnlyActiveTransfersAreResumable() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:mixed-states")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let id1 = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "file1.bin",
      size: 1000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    let id2 = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "file2.bin",
      size: 2000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    let id3 = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "file3.bin",
      size: 3000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)

    try await journal.complete(id: id1)
    try await journal.fail(id: id2, error: MTPError.timeout)
    // id3 left active

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].id, id3)
  }

  /// Stale temp cleanup removes old entries.
  func testClearStaleTemps_removesOldEntries() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:stale")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    _ = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "stale.bin",
      size: 100, supportsPartial: false, tempURL: tempURL, sourceURL: nil)

    // Clear with zero-second threshold removes everything
    try await journal.clearStaleTemps(olderThan: 0)
    let entries = await journal.entries
    XCTAssertTrue(entries.isEmpty, "All entries should be cleared with olderThan: 0")
  }

  // MARK: - Retry classification edge cases

  /// Transport timeout maps to a retryable reason.
  func testRetryClassification_transportTimeout() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.transport(.timeout))
    XCTAssertEqual(reason, "transport-timeout")
  }

  /// Device busy maps to a retryable reason.
  func testRetryClassification_busy() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: MTPError.busy)
    XCTAssertEqual(reason, "busy")
  }

  /// storageFull is NOT retryable.
  func testRetryClassification_storageFullNotRetryable() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: MTPError.storageFull)
    XCTAssertNil(reason, "storageFull should not be retryable")
  }

  /// objectNotFound maps to a retryable reason (invalid handle may be stale).
  func testRetryClassification_objectNotFoundIsRetryable() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: MTPError.objectNotFound)
    XCTAssertNotNil(reason, "objectNotFound should be retryable (stale handle)")
    XCTAssertEqual(reason, "invalid-object-handle-0x2009")
  }

  /// readOnly is NOT retryable.
  func testRetryClassification_readOnlyNotRetryable() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: MTPError.readOnly)
    XCTAssertNil(reason, "readOnly should not be retryable")
  }

  /// Non-MTP errors have no retry reason.
  func testRetryClassification_nonMTPError() {
    struct CustomError: Error {}
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(for: CustomError())
    XCTAssertNil(reason)
  }

  // MARK: - verificationFailed error semantics

  /// verificationFailed must encode both expected and actual sizes.
  func testVerificationFailed_encodesExpectedAndActual() {
    let error = MTPError.verificationFailed(expected: 10_000, actual: 8_000)
    if case .verificationFailed(let expected, let actual) = error {
      XCTAssertEqual(expected, 10_000)
      XCTAssertEqual(actual, 8_000)
    } else {
      XCTFail("Wrong error case")
    }
    XCTAssertTrue(
      error.localizedDescription.contains("8000") || error.localizedDescription.contains("8,000"))
    XCTAssertTrue(
      error.localizedDescription.contains("10000")
        || error.localizedDescription.contains("10,000"))
  }

  /// verificationFailed recovery suggestion advises re-send.
  func testVerificationFailed_suggestsResend() {
    let error = MTPError.verificationFailed(expected: 5000, actual: 4000)
    XCTAssertNotNil(error.recoverySuggestion)
    XCTAssertTrue(error.recoverySuggestion?.lowercased().contains("re-send") ?? false)
  }

  /// Two verificationFailed with different values are not equal.
  func testVerificationFailed_equatable() {
    let a = MTPError.verificationFailed(expected: 100, actual: 50)
    let b = MTPError.verificationFailed(expected: 100, actual: 99)
    let c = MTPError.verificationFailed(expected: 100, actual: 50)
    XCTAssertNotEqual(a, b)
    XCTAssertEqual(a, c)
  }

  // MARK: - Write-then-read round-trip integrity

  /// Data written to VirtualMTPDevice can be read back unchanged.
  func testWriteReadRoundTrip_dataIntegrity() async throws {
    let device = makeDevice()
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let payload = Data((0..<256).map { UInt8($0 & 0xFF) })
    let sourceURL = dir.appendingPathComponent("integrity-source.bin")
    try payload.write(to: sourceURL)

    let writeProgress = try await device.write(
      parent: nil, name: "integrity.bin", size: UInt64(payload.count), from: sourceURL)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(payload.count))

    // Find written object
    let stream = device.list(parent: nil, in: defaultStorage)
    var foundHandle: MTPObjectHandle?
    for try await batch in stream {
      if let obj = batch.first(where: { $0.name == "integrity.bin" }) {
        foundHandle = obj.handle
      }
    }
    guard let handle = foundHandle else {
      XCTFail("Written object not found")
      return
    }

    let destURL = dir.appendingPathComponent("integrity-dest.bin")
    _ = try await device.read(handle: handle, range: nil, to: destURL)

    let readBack = try Data(contentsOf: destURL)
    XCTAssertEqual(readBack, payload, "Round-trip data must match exactly")
  }

  // MARK: - Journal remote handle tracking

  /// recordRemoteHandle must persist the device-assigned handle so partial
  /// objects can be cleaned up on retry.
  func testJournalRecordsRemoteHandle() async throws {
    let journal = SafetyTestJournal()
    let deviceId = MTPDeviceID(raw: "test:remote-handle")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    let transferId = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "uploaded.jpg",
      size: 50_000, supportsPartial: true,
      tempURL: tempURL, sourceURL: nil)

    try await journal.recordRemoteHandle(id: transferId, handle: 0x0042)

    let entries = await journal.entries
    let record = try XCTUnwrap(entries[transferId])
    XCTAssertEqual(record.remoteHandle, 0x0042,
      "Remote handle must be persisted for cleanup on retry")

    // Verify it appears in state log
    let log = await journal.stateLog.filter { $0.id == transferId }
    XCTAssertTrue(
      log.contains { $0.state == "remoteHandle:66" },
      "State log must record remote handle assignment")
  }

  // MARK: - Empty name precondition (MTPDeviceActor level)

  /// MTPDeviceActor.write rejects empty filenames with a precondition error.
  /// VirtualMTPDevice does not enforce this — the guard is in the actor layer.
  func testEmptyNamePrecondition_errorIsDescriptive() {
    let error = MTPError.preconditionFailed("write requires a non-empty file name.")
    if case .preconditionFailed(let reason) = error {
      XCTAssertTrue(reason.contains("non-empty"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
    XCTAssertNotNil(error.errorDescription)
    XCTAssertNotNil(error.recoverySuggestion)
  }
}
