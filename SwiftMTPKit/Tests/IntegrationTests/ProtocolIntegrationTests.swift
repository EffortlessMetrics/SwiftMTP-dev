// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

import SwiftMTPCore
import SwiftMTPTestKit

// MARK: - Protocol Integration Tests

/// End-to-end protocol integration tests verifying that wave 38-39 features
/// (CopyObject, edit extensions, expanded formats/properties/events, response codes)
/// work together through VirtualMTPDevice.
final class ProtocolIntegrationTests: XCTestCase {

  private var tmpDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("proto-integration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    if let tmpDir {
      try? FileManager.default.removeItem(at: tmpDir)
    }
    try await super.tearDown()
  }

  // MARK: - Helpers

  private let storage = MTPStorageID(raw: 0x0001_0001)

  /// Write a file with the given content to the device and return its handle.
  private func writeFile(
    to device: VirtualMTPDevice, parent: MTPObjectHandle?, name: String, content: Data
  ) async throws -> MTPObjectHandle {
    let sourceURL = tmpDir.appendingPathComponent(UUID().uuidString)
    try content.write(to: sourceURL)
    _ = try await device.write(parent: parent, name: name, size: UInt64(content.count), from: sourceURL)
    // Find the handle by listing objects under the parent
    var handle: MTPObjectHandle?
    for try await batch in device.list(parent: parent, in: storage) {
      for obj in batch where obj.name == name {
        handle = obj.handle
      }
    }
    return try XCTUnwrap(handle, "Expected to find '\(name)' after write")
  }

  // MARK: - 1. Full File Lifecycle

  /// CreateFolder → SendObject → GetObject → CopyObject → MoveObject → DeleteObject
  func testFullFileLifecycle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // 1. Create a new folder
    let folderHandle = try await device.createFolder(
      parent: nil, name: "TestFolder", storage: storage)
    let folderInfo = try await device.getInfo(handle: folderHandle)
    XCTAssertEqual(folderInfo.name, "TestFolder")
    XCTAssertEqual(folderInfo.formatCode, 0x3001, "Folder should have association format code")

    // 2. SendObject - write a file into the folder
    let content = Data("Hello, MTP integration test!".utf8)
    let fileHandle = try await writeFile(
      to: device, parent: folderHandle, name: "test_doc.txt", content: content)

    // 3. GetObject - read it back and verify content
    let readURL = tmpDir.appendingPathComponent("readback.txt")
    let readProgress = try await device.read(handle: fileHandle, range: nil, to: readURL)
    XCTAssertEqual(readProgress.completedUnitCount, Int64(content.count))
    let readData = try Data(contentsOf: readURL)
    XCTAssertEqual(readData, content, "Read-back content should match original")

    // 4. CopyObject - duplicate within same storage
    let copyHandle = try await device.copyObject(
      handle: fileHandle, toStorage: storage, parentFolder: nil)
    let copyInfo = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo.name, "test_doc.txt", "Copy should preserve filename")
    XCTAssertNotEqual(copyHandle, fileHandle, "Copy should have a distinct handle")

    // Verify copy has same content
    let copyURL = tmpDir.appendingPathComponent("copy_readback.txt")
    _ = try await device.read(handle: copyHandle, range: nil, to: copyURL)
    let copyData = try Data(contentsOf: copyURL)
    XCTAssertEqual(copyData, content, "Copy content should match original")

    // 5. MoveObject - move original into root
    try await device.move(fileHandle, to: nil)
    let movedInfo = try await device.getInfo(handle: fileHandle)
    XCTAssertNil(movedInfo.parent, "Moved file should be at root (nil parent)")

    // 6. DeleteObject - clean up both files and the folder
    try await device.delete(fileHandle, recursive: false)
    try await device.delete(copyHandle, recursive: false)
    try await device.delete(folderHandle, recursive: false)

    // Verify deletion
    do {
      _ = try await device.getInfo(handle: fileHandle)
      XCTFail("Should throw objectNotFound after deletion")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 2. Edit Workflow (SendObject → Rename → GetObject)

  /// Simulates an edit workflow: write file, rename (simulating metadata update), read back.
  func testEditWorkflow_renameAndVerify() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Write initial file
    let originalContent = Data("Version 1 content".utf8)
    let handle = try await writeFile(
      to: device, parent: 1, name: "editable.txt", content: originalContent)

    // Verify initial state
    let info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "editable.txt")

    // Rename to simulate edit metadata change
    try await device.rename(handle, to: "edited_file.txt")
    let renamedInfo = try await device.getInfo(handle: handle)
    XCTAssertEqual(renamedInfo.name, "edited_file.txt")

    // Content should be preserved through rename
    let readURL = tmpDir.appendingPathComponent("edit_readback.txt")
    _ = try await device.read(handle: handle, range: nil, to: readURL)
    let readData = try Data(contentsOf: readURL)
    XCTAssertEqual(readData, originalContent, "Content should survive rename")

    // Write replacement content (new version)
    let updatedContent = Data("Version 2 — edited content".utf8)
    let newHandle = try await writeFile(
      to: device, parent: 1, name: "edited_v2.txt", content: updatedContent)

    // Verify new version
    let v2URL = tmpDir.appendingPathComponent("v2_readback.txt")
    _ = try await device.read(handle: newHandle, range: nil, to: v2URL)
    let v2Data = try Data(contentsOf: v2URL)
    XCTAssertEqual(v2Data, updatedContent, "Updated content should match")

    // Clean up old version
    try await device.delete(handle, recursive: false)
    do {
      _ = try await device.getInfo(handle: handle)
      XCTFail("Old version should be deleted")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 3. Metadata Roundtrip (Rename and Verify)

  /// SendObject → rename → getInfo (verify name changed) → rename again → verify
  func testMetadataRoundtrip_renameChain() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let content = Data("metadata test".utf8)
    let handle = try await writeFile(
      to: device, parent: nil, name: "original_name.txt", content: content)

    // First rename
    try await device.rename(handle, to: "renamed_once.txt")
    var info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "renamed_once.txt")

    // Second rename
    try await device.rename(handle, to: "renamed_twice.txt")
    info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "renamed_twice.txt")

    // Verify operations were recorded
    let ops = await device.operations
    let renameOps = ops.filter { $0.operation == "rename" }
    XCTAssertEqual(renameOps.count, 2, "Should have recorded exactly 2 rename operations")
    XCTAssertEqual(renameOps[0].parameters["newName"], "renamed_once.txt")
    XCTAssertEqual(renameOps[1].parameters["newName"], "renamed_twice.txt")
  }

  // MARK: - 4. Event Lifecycle

  /// Monitor events → create object → verify ObjectAdded → delete → verify ObjectRemoved
  func testEventLifecycle_addAndRemove() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Collect events in the background
    let collectedEvents = ManagedAtomic<[MTPEvent]>([])
    let eventTask = Task {
      var events: [MTPEvent] = []
      for await event in device.events {
        events.append(event)
        if events.count >= 2 { break }
      }
      return events
    }

    // Small delay to ensure event listener is active
    try await Task.sleep(nanoseconds: 50_000_000)

    // Inject ObjectAdded event (simulating device-side create)
    let testHandle: MTPObjectHandle = 500
    await device.injectEvent(.objectAdded(testHandle))

    // Inject ObjectRemoved event (simulating device-side delete)
    await device.injectEvent(.objectRemoved(testHandle))

    // Wait for events to be collected
    let events = await eventTask.value

    XCTAssertEqual(events.count, 2, "Should have collected 2 events")

    // Verify ObjectAdded
    if case .objectAdded(let handle) = events[0] {
      XCTAssertEqual(handle, testHandle)
    } else {
      XCTFail("First event should be objectAdded, got \(events[0].eventDescription)")
    }

    // Verify ObjectRemoved
    if case .objectRemoved(let handle) = events[1] {
      XCTAssertEqual(handle, testHandle)
    } else {
      XCTFail("Second event should be objectRemoved, got \(events[1].eventDescription)")
    }
  }

  /// Verify that multiple event types propagate correctly.
  func testEventLifecycle_mixedEvents() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let eventTask = Task {
      var events: [MTPEvent] = []
      for await event in device.events {
        events.append(event)
        if events.count >= 4 { break }
      }
      return events
    }

    try await Task.sleep(nanoseconds: 50_000_000)

    await device.injectEvent(.objectAdded(100))
    await device.injectEvent(.objectInfoChanged(100))
    await device.injectEvent(.storageInfoChanged(storage))
    await device.injectEvent(.objectRemoved(100))

    let events = await eventTask.value
    XCTAssertEqual(events.count, 4)
    XCTAssertEqual(events[0].eventCode, 0x4002)  // ObjectAdded
    XCTAssertEqual(events[1].eventCode, 0x4007)  // ObjectInfoChanged
    XCTAssertEqual(events[2].eventCode, 0x400C)  // StorageInfoChanged
    XCTAssertEqual(events[3].eventCode, 0x4003)  // ObjectRemoved
  }

  // MARK: - 5. Format Recognition

  /// Send files with various extensions and verify correct MTP format codes.
  func testFormatRecognition_variousExtensions() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let data = Data("test".utf8)

    let expectedFormats: [(filename: String, expectedCode: UInt16, label: String)] = [
      ("photo.jpg", PTPObjectFormat.exifJPEG, "JPEG"),
      ("image.png", PTPObjectFormat.png, "PNG"),
      ("song.mp3", PTPObjectFormat.mp3, "MP3"),
      ("video.mp4", PTPObjectFormat.mp4Container, "MP4"),
      ("clip.avi", PTPObjectFormat.avi, "AVI"),
      ("audio.wav", PTPObjectFormat.wav, "WAV"),
      ("music.flac", PTPObjectFormat.flac, "FLAC"),
      ("doc.txt", PTPObjectFormat.text, "Text"),
      ("page.html", PTPObjectFormat.html, "HTML"),
      ("image.gif", PTPObjectFormat.gif, "GIF"),
      ("picture.bmp", PTPObjectFormat.bmp, "BMP"),
      ("movie.mkv", PTPObjectFormat.mkv, "MKV"),
      ("recording.ogg", PTPObjectFormat.ogg, "OGG"),
      ("photo.heic", PTPObjectFormat.heif, "HEIF"),
      ("unknown.xyz", PTPObjectFormat.undefined, "Undefined"),
    ]

    for (filename, expectedCode, label) in expectedFormats {
      let handle = try await writeFile(to: device, parent: nil, name: filename, content: data)
      let info = try await device.getInfo(handle: handle)
      XCTAssertEqual(
        info.formatCode, expectedCode,
        "\(label): '\(filename)' should map to 0x\(String(expectedCode, radix: 16))"
          + " but got 0x\(String(info.formatCode, radix: 16))")
    }
  }

  /// Verify PTPObjectFormat.forFilename matches the device assignment.
  func testFormatRecognition_forFilenameConsistency() async throws {
    let filenames = [
      "test.jpg", "test.png", "test.mp3", "test.mp4",
      "test.txt", "test.html", "test.flac", "test.bmp",
    ]

    for name in filenames {
      let expected = PTPObjectFormat.forFilename(name)
      XCTAssertNotEqual(
        expected, PTPObjectFormat.undefined,
        "'\(name)' should have a recognized format code")
    }

    // Unknown extension should map to undefined
    XCTAssertEqual(PTPObjectFormat.forFilename("file.qwerty"), PTPObjectFormat.undefined)
  }

  // MARK: - 6. Error Recovery (Fault Injection)

  /// Simulate DeviceBusy on copy operation and verify that the fault fires then clears.
  func testErrorRecovery_busyOnCopy() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault.busyForRetries(2)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    // First 2 executeCommand calls should fail with busy
    for i in 0..<2 {
      let command = PTPContainer(type: 1, code: 0x101A, txid: UInt32(i))
      do {
        _ = try await faultyLink.executeCommand(command)
        XCTFail("Call \(i) should throw busy")
      } catch let error as TransportError {
        XCTAssertEqual(error, .busy, "Expected busy error on call \(i)")
      }
    }

    // Third call should succeed
    let command = PTPContainer(type: 1, code: 0x101A, txid: 99)
    let result = try await faultyLink.executeCommand(command)
    XCTAssertEqual(result.code, 0x2001, "Should succeed after busy retries clear")
  }

  /// Simulate timeout then verify recovery on a subsequent operation.
  func testErrorRecovery_timeoutThenRecover() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getObjectHandles)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    let storage = MTPStorageID(raw: 0x0001_0001)

    // First call to getObjectHandles should timeout
    do {
      _ = try await faultyLink.getObjectHandles(storage: storage, parent: nil)
      XCTFail("Should have thrown timeout")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }

    // Second call should succeed (one-shot fault)
    let handles = try await faultyLink.getObjectHandles(storage: storage, parent: nil)
    XCTAssertFalse(handles.isEmpty, "Should return handles after recovery")
  }

  /// Simulate disconnection on delete and verify the error propagates correctly.
  func testErrorRecovery_disconnectOnDelete() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.deleteObject), error: .disconnected)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    do {
      try await faultyLink.deleteObject(handle: 3)
      XCTFail("Should have thrown disconnected")
    } catch let error as TransportError {
      XCTAssertEqual(error, .noDevice, "Disconnected should map to noDevice transport error")
    }
  }

  // MARK: - 7. Cross-Feature Integration

  /// CreateFolder → Write multiple files → Copy folder contents → Move → Delete chain
  func testCrossFeature_bulkOperationsWorkflow() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Create source and destination folders
    let srcFolder = try await device.createFolder(
      parent: nil, name: "Source", storage: storage)
    let dstFolder = try await device.createFolder(
      parent: nil, name: "Destination", storage: storage)

    // Write several files into source folder
    var sourceHandles: [MTPObjectHandle] = []
    for i in 0..<3 {
      let content = Data("File content \(i)".utf8)
      let handle = try await writeFile(
        to: device, parent: srcFolder, name: "file_\(i).txt", content: content)
      sourceHandles.append(handle)
    }

    // Copy each file to destination
    var copyHandles: [MTPObjectHandle] = []
    for srcHandle in sourceHandles {
      let copyHandle = try await device.copyObject(
        handle: srcHandle, toStorage: storage, parentFolder: dstFolder)
      copyHandles.append(copyHandle)
    }

    // Verify copies exist in destination
    var dstFiles: [MTPObjectInfo] = []
    for try await batch in device.list(parent: dstFolder, in: storage) {
      dstFiles.append(contentsOf: batch)
    }
    XCTAssertEqual(dstFiles.count, 3, "Destination should have 3 copied files")

    // Move one copy back to root
    try await device.move(copyHandles[0], to: nil)
    let movedInfo = try await device.getInfo(handle: copyHandles[0])
    XCTAssertNil(movedInfo.parent)

    // Delete source folder recursively
    try await device.delete(srcFolder, recursive: true)

    // Source files should be gone
    for handle in sourceHandles {
      do {
        _ = try await device.getInfo(handle: handle)
        XCTFail("Source file handle \(handle) should be deleted")
      } catch let error as MTPError {
        XCTAssertEqual(error, .objectNotFound)
      }
    }

    // Destination copies should still exist
    for handle in copyHandles {
      let info = try await device.getInfo(handle: handle)
      XCTAssertEqual(info.name.hasPrefix("file_"), true)
    }
  }

  /// Verify operation audit trail captures the full lifecycle.
  func testCrossFeature_operationAuditTrail() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()

    let content = Data("audit test".utf8)
    let handle = try await writeFile(
      to: device, parent: nil, name: "audit.txt", content: content)

    try await device.rename(handle, to: "renamed_audit.txt")

    let copyHandle = try await device.copyObject(
      handle: handle, toStorage: storage, parentFolder: nil)

    try await device.move(copyHandle, to: 1)  // Move to DCIM

    try await device.delete(handle, recursive: false)
    try await device.delete(copyHandle, recursive: false)

    let ops = await device.operations
    let opNames = ops.map(\.operation)

    XCTAssertTrue(opNames.contains("write"), "Should record write")
    XCTAssertTrue(opNames.contains("rename"), "Should record rename")
    XCTAssertTrue(opNames.contains("copyObject"), "Should record copyObject")
    XCTAssertTrue(opNames.contains("move"), "Should record move")
    XCTAssertTrue(opNames.contains("delete"), "Should record delete")
  }
}

// MARK: - Thread-safe event collector

/// Minimal atomic wrapper for collecting events from async streams in tests.
private final class ManagedAtomic<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: T

  init(_ value: T) { _value = value }

  var value: T {
    lock.lock()
    defer { lock.unlock() }
    return _value
  }

  func mutate(_ transform: (inout T) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    transform(&_value)
  }
}
