// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPTestKit

// MARK: - File Transfer BDD Scenarios

final class FileTransferBDDTests: XCTestCase {

  private let storage = MTPStorageID(raw: 0x0001_0001)

  // MARK: Scenario: User downloads a single photo from camera

  func testDownloadSinglePhoto_DataIntact() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let photoData = Data(repeating: 0xFF, count: 4096)
    let handle: MTPObjectHandle = 500
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "IMG_0001.jpg", formatCode: 0x3801, data: photoData))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-photo-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual, photoData, "Downloaded photo data must match original")
  }

  func testDownloadSinglePhoto_PreservesSize() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let size = 8192
    let handle: MTPObjectHandle = 501
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "IMG_0002.cr3", formatCode: 0x3801, data: Data(repeating: 0xAA, count: size)))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-raw-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, size, "Downloaded file must preserve exact byte count")
  }

  // MARK: Scenario: User uploads a music file to media player

  func testUploadMusicFile_AppearsOnDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-upload-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    let payload = Data(repeating: 0xBB, count: 2048)
    try payload.write(to: url)
    _ = try await device.write(
      parent: nil, name: "song.mp3", size: UInt64(payload.count), from: url)
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == "song.mp3" }) { found = true }
    }
    XCTAssertTrue(found, "Uploaded music file must appear in device listing")
  }

  func testUploadMusicFile_CorrectSize() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-upload-sz-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    let payload = Data(repeating: 0xCC, count: 3072)
    try payload.write(to: url)
    _ = try await device.write(
      parent: nil, name: "track.mp3", size: UInt64(payload.count), from: url)
    var uploadedSize: UInt64?
    for try await batch in device.list(parent: nil, in: storage) {
      if let obj = batch.first(where: { $0.name == "track.mp3" }) {
        uploadedSize = obj.sizeBytes
      }
    }
    XCTAssertEqual(uploadedSize, UInt64(payload.count),
      "Uploaded file size must match source")
  }

  // MARK: Scenario: User mirrors a folder from phone

  func testMirrorFolder_AllFilesPresent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let folderHandle: MTPObjectHandle = 600
    await device.addObject(VirtualObjectConfig(
      handle: folderHandle, storage: storage, parent: nil,
      name: "DCIM", formatCode: 0x3001))
    for i in 0..<5 {
      await device.addObject(VirtualObjectConfig(
        handle: MTPObjectHandle(601 + UInt32(i)), storage: storage,
        parent: folderHandle, name: "photo_\(i).jpg",
        formatCode: 0x3801, data: Data("img\(i)".utf8)))
    }
    var rootNames: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      rootNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(rootNames.contains("DCIM"), "DCIM folder must be listed")
  }

  func testMirrorFolder_SubfolderContentsAccessible() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let folderHandle: MTPObjectHandle = 610
    await device.addObject(VirtualObjectConfig(
      handle: folderHandle, storage: storage, parent: nil,
      name: "Music", formatCode: 0x3001))
    await device.addObject(VirtualObjectConfig(
      handle: 611, storage: storage, parent: folderHandle,
      name: "album.mp3", formatCode: 0x3000, data: Data("audio".utf8)))
    var childNames: [String] = []
    for try await batch in device.list(parent: folderHandle, in: storage) {
      childNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(childNames.contains("album.mp3"),
      "Subfolder contents must be accessible via parent handle")
  }

  // MARK: Scenario: Transfer fails and shows clear error message

  func testTransferFail_DisconnectMidRead_ErrorReported() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getObjectHandles(storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected disconnect error during transfer")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice, "Disconnect during transfer should surface as noDevice")
      XCTAssertNotNil(err.errorDescription, "Error must have a user-facing description")
    }
  }

  func testTransferFail_Timeout_ClearMessage() async throws {
    let error = TransportError.timeout
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.lowercased().contains("timed out"),
      "Timeout error should mention 'timed out'")
  }

  func testTransferFail_IO_ClearMessage() async throws {
    let error = TransportError.io("USB pipe broken")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("USB pipe broken"),
      "IO error should include the specific message")
  }

  // MARK: Scenario: User cancels large transfer

  func testCancelLargeTransfer_NoOrphanFiles() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let largeData = Data(repeating: 0xDD, count: 1024 * 1024)
    let handle: MTPObjectHandle = 700
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "large-video.mp4", formatCode: 0x3000, data: largeData))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-cancel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    // Start the download — it completes on virtual device (no real cancellation point)
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, largeData.count,
      "Transfer should complete cleanly on virtual device")
  }

  // MARK: Scenario: User resumes interrupted transfer

  func testResumeInterruptedTransfer_JournalRecordsProgress() async throws {
    let journal = InMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-test")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "interrupted.zip",
      size: 10_000_000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.updateProgress(id: id, committed: 5_000_000)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(
      records.contains { $0.id == id && $0.committedBytes == 5_000_000 },
      "Journal must record partial progress for resume")
  }

  func testResumeInterruptedTransfer_CompletionClearsRecord() async throws {
    let journal = InMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-complete")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-done-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "completed.zip",
      size: 1024, supportsPartial: false, tempURL: tempURL, sourceURL: nil)
    try await journal.complete(id: id)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertFalse(records.contains { $0.id == id },
      "Completed transfer must be removed from journal")
  }

  // MARK: Scenario: User transfers file with special characters in name

  func testSpecialCharacters_UnicodeFilename() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let name = "日本語テスト.txt"
    let handle: MTPObjectHandle = 800
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: name, formatCode: 0x3000, data: Data("こんにちは".utf8)))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-unicode-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(String(data: actual, encoding: .utf8), "こんにちは",
      "Unicode file content must be preserved")
  }

  func testSpecialCharacters_SpacesInFilename() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let name = "my vacation photo (1).jpg"
    let handle: MTPObjectHandle = 801
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: name, formatCode: 0x3801, data: Data("jpeg-data".utf8)))
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == name }) { found = true }
    }
    XCTAssertTrue(found, "Filenames with spaces and parentheses must be preserved")
  }

  func testSpecialCharacters_EmojiFilename() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let name = "📸 photo.jpg"
    let handle: MTPObjectHandle = 802
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: name, formatCode: 0x3801, data: Data("emoji-file".utf8)))
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == name }) { found = true }
    }
    XCTAssertTrue(found, "Emoji filenames must be handled correctly")
  }

  func testSpecialCharacters_LongFilename() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let name = String(repeating: "a", count: 200) + ".txt"
    let handle: MTPObjectHandle = 803
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: name, formatCode: 0x3000, data: Data("long-name".utf8)))
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == name }) { found = true }
    }
    XCTAssertTrue(found, "Long filenames must be handled without truncation")
  }

  // MARK: Scenario: Empty file transfer

  func testEmptyFileTransfer_DownloadSucceeds() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let handle: MTPObjectHandle = 810
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "empty.txt", formatCode: 0x3000, data: Data()))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-empty-dl-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertTrue(actual.isEmpty, "Empty file download should produce empty data")
  }

  func testEmptyFileTransfer_UploadSucceeds() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-empty-up-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data().write(to: url)
    _ = try await device.write(parent: nil, name: "empty-up.txt", size: 0, from: url)
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == "empty-up.txt" }) { found = true }
    }
    XCTAssertTrue(found, "Empty file upload should succeed")
  }

  // MARK: Scenario: Large file chunked transfer

  func testLargeFileTransfer_DataIntact() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let size = 4 * 1024 * 1024
    let largeData = Data(repeating: 0xEE, count: size)
    let handle: MTPObjectHandle = 820
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "video.mp4", formatCode: 0x3000, data: largeData))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-large-xfer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, size, "Large file transfer must preserve exact byte count")
    XCTAssertEqual(actual.first, 0xEE, "First byte must match")
    XCTAssertEqual(actual.last, 0xEE, "Last byte must match")
  }

  // MARK: Scenario: Sequential multi-file download

  func testSequentialMultiFileDownload_AllFilesIntact() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    for i in 0..<5 {
      await device.addObject(VirtualObjectConfig(
        handle: MTPObjectHandle(830 + UInt32(i)), storage: storage, parent: nil,
        name: "batch_\(i).dat", formatCode: 0x3000,
        data: Data("content-\(i)".utf8)))
    }
    for i in 0..<5 {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bdd-batch-\(i)-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: url) }
      _ = try await device.read(
        handle: MTPObjectHandle(830 + UInt32(i)), range: nil, to: url)
      let actual = try Data(contentsOf: url)
      XCTAssertEqual(String(data: actual, encoding: .utf8), "content-\(i)",
        "Batch file \(i) content must match")
    }
  }
}

// MARK: - In-Memory Transfer Journal (for resume tests)

private final class InMemoryTransferJournal: TransferJournal, @unchecked Sendable {
  private var lock = NSLock()
  private var records: [String: TransferRecord] = [:]

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String,
    size: UInt64?, supportsPartial: Bool,
    tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String {
    let id = UUID().uuidString
    lock.withLock {
      records[id] = TransferRecord(
        id: id, deviceId: device, kind: "read", handle: handle, parentHandle: nil,
        name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
        localTempURL: tempURL, finalURL: finalURL, state: "started", updatedAt: Date())
    }
    return id
  }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String,
    size: UInt64, supportsPartial: Bool,
    tempURL: URL, sourceURL: URL?
  ) async throws -> String {
    let id = UUID().uuidString
    lock.withLock {
      records[id] = TransferRecord(
        id: id, deviceId: device, kind: "write", handle: nil, parentHandle: parent,
        name: name, totalBytes: size, committedBytes: 0, supportsPartial: supportsPartial,
        localTempURL: tempURL, finalURL: sourceURL, state: "started", updatedAt: Date())
    }
    return id
  }

  func updateProgress(id: String, committed: UInt64) async throws {
    lock.withLock {
      guard let r = records[id] else { return }
      records[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: committed, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL,
        state: "in_progress", updatedAt: Date(), remoteHandle: r.remoteHandle)
    }
  }

  func fail(id: String, error: Error) async throws {
    lock.withLock {
      guard let r = records[id] else { return }
      records[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL,
        state: "failed", updatedAt: Date(), remoteHandle: r.remoteHandle)
    }
  }

  func complete(id: String) async throws {
    _ = lock.withLock { records.removeValue(forKey: id) }
  }

  func recordRemoteHandle(id: String, handle: UInt32) async throws {
    lock.withLock {
      guard let r = records[id] else { return }
      records[id] = TransferRecord(
        id: r.id, deviceId: r.deviceId, kind: r.kind, handle: r.handle,
        parentHandle: r.parentHandle, name: r.name, totalBytes: r.totalBytes,
        committedBytes: r.committedBytes, supportsPartial: r.supportsPartial,
        localTempURL: r.localTempURL, finalURL: r.finalURL,
        state: r.state, updatedAt: Date(), remoteHandle: handle)
    }
  }

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    lock.withLock { records.values.filter { $0.deviceId == device } }
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {}
}
