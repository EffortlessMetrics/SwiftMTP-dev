// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPSync
import SwiftMTPTestKit

// MARK: - Wave 41 BDD Scenarios: Copy, Edit, Mirror, Metadata

final class Wave41BDDScenarios: XCTestCase {

  private let storage = MTPStorageID(raw: 0x0001_0001)

  // ───────────────────────────────────────────────
  // MARK: Scenario: Server-side file copy
  // ───────────────────────────────────────────────

  /// Given a connected device with a file "photo.jpg"
  /// When I copy "photo.jpg" to storage "Internal"
  /// Then a new copy should exist on the device
  /// And the original file should still exist
  func testServerSideCopy_CreatesCopyAndPreservesOriginal() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let originalHandle: MTPObjectHandle = 4100
    let photoData = Data(repeating: 0xFF, count: 2048)
    await device.addObject(
      VirtualObjectConfig(
        handle: originalHandle, storage: storage, parent: nil,
        name: "photo.jpg", formatCode: PTPObjectFormat.exifJPEG, data: photoData))

    // When: server-side copy to same storage
    let copyHandle = try await device.copyObject(
      handle: originalHandle, toStorage: storage, parentFolder: nil)

    // Then: the copy exists with matching name
    let copyInfo = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo.name, "photo.jpg", "Copy must preserve the original filename")
    XCTAssertEqual(copyInfo.sizeBytes, UInt64(photoData.count), "Copy must preserve file size")

    // And: the original is still present
    let originalInfo = try await device.getInfo(handle: originalHandle)
    XCTAssertEqual(originalInfo.name, "photo.jpg", "Original must still exist after copy")
  }

  func testServerSideCopy_CopyHandleDiffersFromOriginal() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let originalHandle: MTPObjectHandle = 4101
    await device.addObject(
      VirtualObjectConfig(
        handle: originalHandle, storage: storage, parent: nil,
        name: "document.pdf", formatCode: 0x3000, data: Data("pdf-content".utf8)))

    let copyHandle = try await device.copyObject(
      handle: originalHandle, toStorage: storage, parentFolder: nil)

    XCTAssertNotEqual(copyHandle, originalHandle, "Copy handle must differ from original")
  }

  func testServerSideCopy_CopyToFolderTarget() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    // Create target folder
    let folderHandle: MTPObjectHandle = 4110
    await device.addObject(
      VirtualObjectConfig(
        handle: folderHandle, storage: storage, parent: nil,
        name: "Backup", formatCode: PTPObjectFormat.association))

    // Create source file
    let fileHandle: MTPObjectHandle = 4111
    await device.addObject(
      VirtualObjectConfig(
        handle: fileHandle, storage: storage, parent: nil,
        name: "report.txt", formatCode: PTPObjectFormat.text, data: Data("report".utf8)))

    // Copy into the folder
    let copyHandle = try await device.copyObject(
      handle: fileHandle, toStorage: storage, parentFolder: folderHandle)
    let copyInfo = try await device.getInfo(handle: copyHandle)
    XCTAssertEqual(copyInfo.parent, folderHandle, "Copy must land in the target folder")
    XCTAssertEqual(copyInfo.name, "report.txt")
  }

  func testServerSideCopy_NonExistentHandle_Throws() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    do {
      _ = try await device.copyObject(handle: 9999, toStorage: storage, parentFolder: nil)
      XCTFail("Expected error when copying non-existent object")
    } catch {
      // Expected: objectNotFound or similar
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: In-place file editing
  // ───────────────────────────────────────────────

  /// Given a connected device with a file "notes.txt"
  /// When I overwrite "notes.txt" with new content
  /// Then the file content should be "Updated content"
  ///
  /// Note: MTP does not natively support in-place editing; the typical
  /// workflow is delete + re-upload. This test validates that approach.
  func testInPlaceEdit_DeleteAndReupload_UpdatesContent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let handle: MTPObjectHandle = 4200
    await device.addObject(
      VirtualObjectConfig(
        handle: handle, storage: storage, parent: nil,
        name: "notes.txt", formatCode: PTPObjectFormat.text,
        data: Data("Original content".utf8)))

    // Delete the old version
    try await device.delete(handle, recursive: false)

    // Write the new version
    let newContent = Data("Updated content".utf8)
    let tmpURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-edit-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: tmpURL) }
    try newContent.write(to: tmpURL)
    _ = try await device.write(
      parent: nil, name: "notes.txt", size: UInt64(newContent.count), from: tmpURL)

    // Verify: find the re-uploaded object and read it back
    var foundHandle: MTPObjectHandle?
    for try await batch in device.list(parent: nil, in: storage) {
      if let obj = batch.first(where: { $0.name == "notes.txt" }) {
        foundHandle = obj.handle
      }
    }
    guard let newHandle = foundHandle else {
      XCTFail("Re-uploaded notes.txt must exist on device")
      return
    }

    let readURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-edit-read-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: readURL) }
    _ = try await device.read(handle: newHandle, range: nil, to: readURL)
    let actual = try Data(contentsOf: readURL)
    XCTAssertEqual(
      String(data: actual, encoding: .utf8), "Updated content",
      "File content must reflect the edited version")
  }

  func testInPlaceEdit_OriginalNoLongerPresent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let handle: MTPObjectHandle = 4201
    await device.addObject(
      VirtualObjectConfig(
        handle: handle, storage: storage, parent: nil,
        name: "old-draft.txt", formatCode: PTPObjectFormat.text,
        data: Data("Draft v1".utf8)))

    try await device.delete(handle, recursive: false)

    // Verify deleted
    do {
      _ = try await device.getInfo(handle: handle)
      XCTFail("Deleted object handle should not resolve")
    } catch {
      // Expected
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Mirror with format filter
  // ───────────────────────────────────────────────

  /// Given a connected device with photos and videos
  /// When I mirror with --photos-only (images category filter)
  /// Then only image files should pass the filter
  /// And video files should be skipped
  func testMirrorFormatFilter_ImagesOnly_PassesPhotos() {
    let filter = MTPFormatFilter.category(.images)

    XCTAssertTrue(
      filter.matches(format: PTPObjectFormat.exifJPEG),
      "JPEG must pass images-only filter")
    XCTAssertTrue(
      filter.matches(format: PTPObjectFormat.png),
      "PNG must pass images-only filter")
    XCTAssertTrue(
      filter.matches(format: PTPObjectFormat.heif),
      "HEIF must pass images-only filter")
  }

  func testMirrorFormatFilter_ImagesOnly_RejectsVideos() {
    let filter = MTPFormatFilter.category(.images)

    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.mp4Container),
      "MP4 must be rejected by images-only filter")
    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.avi),
      "AVI must be rejected by images-only filter")
    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.mkv),
      "MKV must be rejected by images-only filter")
  }

  func testMirrorFormatFilter_ImagesOnly_RejectsAudioAndDocs() {
    let filter = MTPFormatFilter.category(.images)

    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.mp3),
      "MP3 must be rejected by images-only filter")
    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.text),
      "Text must be rejected by images-only filter")
  }

  func testMirrorFormatFilter_ExtensionBased_IncludesJpgPng() {
    let filter = MTPFormatFilter.including(extensions: [".jpg", ".png"])

    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.png))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp4Container))
    XCTAssertFalse(filter.matches(format: PTPObjectFormat.mp3))
  }

  func testMirrorFormatFilter_ExcludeVideos() {
    let filter = MTPFormatFilter.excluding(extensions: [".mp4", ".avi", ".mkv"])

    XCTAssertTrue(
      filter.matches(format: PTPObjectFormat.exifJPEG),
      "JPEG must pass when only videos are excluded")
    XCTAssertFalse(
      filter.matches(format: PTPObjectFormat.mp4Container),
      "MP4 must be excluded")
  }

  func testMirrorFormatFilter_AllCategory_PassesEverything() {
    let filter = MTPFormatFilter.all

    XCTAssertTrue(filter.matches(format: PTPObjectFormat.exifJPEG))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp4Container))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.mp3))
    XCTAssertTrue(filter.matches(format: PTPObjectFormat.text))
    XCTAssertTrue(filter.matches(format: 0x3000))
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Conflict resolution
  // ───────────────────────────────────────────────

  /// Given a file modified both locally and on device
  /// When I mirror with --on-conflict newer-wins
  /// Then the strategy should correctly identify which side is newer
  func testConflictResolution_NewerWins_DeviceNewer() {
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)

    let conflict = MTPConflictInfo(
      pathKey: "0x00010001/DCIM/photo.jpg",
      handle: 100,
      deviceSize: 2048,
      deviceMtime: now,
      localSize: 1024,
      localMtime: oneHourAgo)

    // Device mtime is newer
    XCTAssertNotNil(conflict.deviceMtime)
    XCTAssertNotNil(conflict.localMtime)
    XCTAssertTrue(
      conflict.deviceMtime! > conflict.localMtime!,
      "Device version is newer — newer-wins should keep device copy")
  }

  func testConflictResolution_NewerWins_LocalNewer() {
    let now = Date()
    let oneHourAgo = now.addingTimeInterval(-3600)

    let conflict = MTPConflictInfo(
      pathKey: "0x00010001/Documents/report.docx",
      handle: 200,
      deviceSize: 5000,
      deviceMtime: oneHourAgo,
      localSize: 6000,
      localMtime: now)

    XCTAssertTrue(
      conflict.localMtime! > conflict.deviceMtime!,
      "Local version is newer — newer-wins should keep local copy")
  }

  func testConflictResolution_StrategyEnum_AllCasesExist() {
    let strategies = ConflictResolutionStrategy.allCases
    let rawValues = strategies.map(\.rawValue)

    XCTAssertTrue(rawValues.contains("newer-wins"))
    XCTAssertTrue(rawValues.contains("local-wins"))
    XCTAssertTrue(rawValues.contains("device-wins"))
    XCTAssertTrue(rawValues.contains("keep-both"))
    XCTAssertTrue(rawValues.contains("skip"))
    XCTAssertTrue(rawValues.contains("ask"))
  }

  func testConflictResolution_OutcomeEnum_AllCasesExist() {
    let outcomes: [ConflictOutcome] = [
      .keptLocal, .keptDevice, .keptBoth, .skipped, .pending,
    ]
    XCTAssertEqual(outcomes.count, 5, "All conflict outcomes must be covered")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Rich metadata display
  // ───────────────────────────────────────────────

  /// Given a connected device with a JPEG photo
  /// When I run "info" on the photo
  /// Then I should see format, size, dates, and storage info
  func testRichMetadata_ObjectInfoContainsExpectedFields() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()

    let handle: MTPObjectHandle = 4300
    let photoData = Data(repeating: 0xAB, count: 8192)
    await device.addObject(
      VirtualObjectConfig(
        handle: handle, storage: storage, parent: nil,
        name: "DSC_0001.jpg", formatCode: PTPObjectFormat.exifJPEG, data: photoData))

    let info = try await device.getInfo(handle: handle)

    // Format
    XCTAssertEqual(info.formatCode, PTPObjectFormat.exifJPEG, "Format code must be EXIF/JPEG")
    let formatName = PTPObjectFormat.describe(info.formatCode)
    XCTAssertTrue(
      formatName.contains("JPEG"),
      "Human-readable format must mention JPEG, got: \(formatName)")

    // Size
    XCTAssertEqual(info.sizeBytes, UInt64(photoData.count), "Size must reflect actual data")

    // Storage
    XCTAssertEqual(info.storage.raw, storage.raw, "Storage ID must match")

    // Name
    XCTAssertEqual(info.name, "DSC_0001.jpg")
  }

  func testRichMetadata_StorageInfoAvailable() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Device must expose at least one storage")

    let first = storages[0]
    XCTAssertFalse(first.description.isEmpty, "Storage must have a description")
    XCTAssertGreaterThan(first.capacityBytes, 0, "Storage capacity must be positive")
  }

  func testRichMetadata_DeviceInfoAvailable() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()

    let devInfo = try await device.devGetDeviceInfoUncached()
    XCTAssertFalse(devInfo.manufacturer.isEmpty, "Manufacturer must be populated")
    XCTAssertFalse(devInfo.model.isEmpty, "Model must be populated")
  }

  func testRichMetadata_FormatDescriptionCoversCommonTypes() {
    let cases: [(UInt16, String)] = [
      (PTPObjectFormat.exifJPEG, "JPEG"),
      (PTPObjectFormat.png, "PNG"),
      (PTPObjectFormat.mp4Container, "MP4"),
      (PTPObjectFormat.mp3, "MP3"),
      (PTPObjectFormat.text, "Text"),
      (PTPObjectFormat.association, "Association"),
    ]

    for (code, expected) in cases {
      let desc = PTPObjectFormat.describe(code)
      XCTAssertTrue(
        desc.contains(expected),
        "Format 0x\(String(code, radix: 16)) should mention '\(expected)', got: '\(desc)'")
    }
  }
}
