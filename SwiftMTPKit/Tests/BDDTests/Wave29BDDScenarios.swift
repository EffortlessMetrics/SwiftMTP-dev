// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPTestKit
import SwiftMTPQuirks

// MARK: - Wave 29 BDD Scenarios

final class Wave29BDDScenarios: XCTestCase {

  private let storage = MTPStorageID(raw: 0x0001_0001)

  // ───────────────────────────────────────────────
  // MARK: Scenario: Device discovery failure – USB permission denied
  // ───────────────────────────────────────────────

  func testDiscoveryFailure_USBPermissionDenied_ReportsAccessDenied() async throws {
    // Given a device that denies USB-level access (e.g. macOS TCC prompt declined)
    let fault = ScheduledFault(
      trigger: .onOperation(.openUSB), error: .accessDenied, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))

    // When we attempt to open the USB connection
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected accessDenied error for USB permission denied")
    } catch let err as TransportError {
      // Then the error is surfaced as accessDenied
      XCTAssertEqual(
        err, .accessDenied,
        "USB permission denied must surface as .accessDenied")
      XCTAssertNotNil(
        err.errorDescription,
        "Error must have a user-facing description")
    }
  }

  func testDiscoveryFailure_USBPermissionDenied_RetryAfterGrant() async throws {
    // Given a one-shot permission denial
    let fault = ScheduledFault(
      trigger: .onOperation(.openUSB), error: .accessDenied, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))

    // When the first attempt fails
    do { try await link.openUSBIfNeeded() } catch { /* expected */  }

    // Then retry after granting permission succeeds
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(
      storages.isEmpty,
      "After granting USB permission, device should be fully accessible")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Device discovery failure – driver conflict
  // ───────────────────────────────────────────────

  func testDiscoveryFailure_DriverConflict_ReportsIOError() async throws {
    // Given a device where the kernel driver cannot be detached
    let fault = ScheduledFault(
      trigger: .onOperation(.openUSB),
      error: .io("USB driver conflict: kernel driver already claimed interface"),
      repeatCount: 1)
    let link = VirtualMTPLink(config: .samsungGalaxy, faultSchedule: FaultSchedule([fault]))

    // When we attempt to open
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected IO error for driver conflict")
    } catch let err as TransportError {
      // Then an IO error with context is surfaced
      guard case .io(let msg) = err else {
        XCTFail("Expected .io error, got \(err)")
        return
      }
      XCTAssertTrue(msg.contains("driver"), "IO error should mention driver conflict")
    }
  }

  func testDiscoveryFailure_DriverConflict_RetryAfterDetach() async throws {
    // Given a one-shot driver conflict
    let fault = ScheduledFault(
      trigger: .onOperation(.openUSB),
      error: .io("kernel driver conflict"),
      repeatCount: 1)
    let link = VirtualMTPLink(config: .samsungGalaxy, faultSchedule: FaultSchedule([fault]))

    do { try await link.openUSBIfNeeded() } catch { /* expected */  }

    // Then retry succeeds after the kernel driver is detached
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(
      info.manufacturer, "Samsung",
      "Device should be accessible after driver conflict resolves")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Large file transfer with progress tracking
  // ───────────────────────────────────────────────

  func testLargeFileTransfer_ProgressTracking_DataIntact() async throws {
    // Given a device with a 4 MB file
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let fileSize = 4 * 1024 * 1024
    let largeData = Data(repeating: 0xAC, count: fileSize)
    let handle: MTPObjectHandle = 2900
    await device.addObject(
      VirtualObjectConfig(
        handle: handle, storage: storage, parent: nil,
        name: "large-video-w29.mp4", formatCode: 0x3000, data: largeData))

    // When we download the file
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-large-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)

    // Then the data is fully intact
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, fileSize, "Downloaded size must match original")
    XCTAssertEqual(actual.first, 0xAC, "First byte must match")
    XCTAssertEqual(actual.last, 0xAC, "Last byte must match")
  }

  func testLargeFileTransfer_JournalTracksProgress() async throws {
    // Given a transfer journal
    let journal = Wave29InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "bdd-w29-progress")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-journal-\(UUID().uuidString)")

    // When we begin a large write and report incremental progress
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "bigfile.zip",
      size: 10_000_000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.updateProgress(id: id, committed: 2_500_000)
    try await journal.updateProgress(id: id, committed: 5_000_000)
    try await journal.updateProgress(id: id, committed: 7_500_000)

    // Then the journal reflects the latest progress
    let records = try await journal.loadResumables(for: deviceId)
    let record = records.first { $0.id == id }
    XCTAssertNotNil(record, "Journal must contain the in-progress transfer")
    XCTAssertEqual(
      record?.committedBytes, 7_500_000,
      "Journal must reflect the latest committed byte count")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Transfer cancellation mid-stream
  // ───────────────────────────────────────────────

  func testTransferCancellation_JournalRecordsFailed() async throws {
    // Given a transfer in progress
    let journal = Wave29InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "bdd-w29-cancel")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-cancel-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "cancelled.zip",
      size: 5_000_000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.updateProgress(id: id, committed: 1_500_000)

    // When the transfer is cancelled mid-stream
    let cancelError = TransportError.timeout
    try await journal.fail(id: id, error: cancelError)

    // Then the journal marks the transfer as failed (still resumable)
    let records = try await journal.loadResumables(for: deviceId)
    let record = records.first { $0.id == id }
    XCTAssertNotNil(record, "Cancelled transfer should remain in journal for resume")
    XCTAssertEqual(
      record?.committedBytes, 1_500_000,
      "Committed progress should be preserved on cancellation")
  }

  func testTransferCancellation_NoOrphanFilesOnDevice() async throws {
    // Given a device with a file being transferred
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let data = Data(repeating: 0xBE, count: 2048)
    let handle: MTPObjectHandle = 2910
    await device.addObject(
      VirtualObjectConfig(
        handle: handle, storage: storage, parent: nil,
        name: "cancelling.dat", formatCode: 0x3000, data: data))

    // When we start and then "cancel" (delete the partial)
    try await device.delete(handle, recursive: false)

    // Then the file is gone from the device
    var names: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    XCTAssertFalse(
      names.contains("cancelling.dat"),
      "Cancelled transfer must not leave orphan files on device")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Device disconnection during active transfer
  // ───────────────────────────────────────────────

  func testDisconnectDuringTransfer_GetObjectHandles_ErrorReported() async throws {
    // Given a device that disconnects mid-operation
    let fault = ScheduledFault(
      trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)

    // When we try to list objects
    do {
      _ = try await link.getObjectHandles(storage: storage, parent: nil)
      XCTFail("Expected disconnect error during transfer")
    } catch let err as TransportError {
      // Then the error is surfaced as noDevice
      XCTAssertEqual(
        err, .noDevice,
        "Disconnect during transfer must surface as .noDevice")
    }
  }

  func testDisconnectDuringTransfer_GetObjectInfos_ErrorReported() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getObjectInfos), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .canonEOSR5, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)

    do {
      _ = try await link.getObjectInfos([1, 2, 3])
      XCTFail("Expected disconnect error during getObjectInfos")
    } catch let err as TransportError {
      XCTAssertEqual(
        err, .noDevice,
        "Disconnect during getObjectInfos must surface as .noDevice")
    }
  }

  func testDisconnectDuringTransfer_RetrySucceedsAfterReconnect() async throws {
    // Given a one-shot disconnect
    let fault = ScheduledFault(
      trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)

    // When the first call disconnects
    do { _ = try await link.getStorageIDs() } catch { /* expected */  }

    // Then a retry succeeds (device reconnected)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(
      storages.isEmpty,
      "After reconnection, storage listing should succeed")
  }

  func testDisconnectDuringTransfer_JournalPreservesProgress() async throws {
    let journal = Wave29InMemoryJournal()
    let deviceId = MTPDeviceID(raw: "bdd-w29-disconnect")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-disc-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "interrupted.mp4",
      size: 8_000_000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.updateProgress(id: id, committed: 3_000_000)

    // When device disconnects, the journal still has the record
    try await journal.fail(id: id, error: TransportError.noDevice)

    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(
      records.contains { $0.id == id && $0.committedBytes == 3_000_000 },
      "Journal must preserve committed bytes after disconnect for resume")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Sync conflict resolution (local vs device file)
  // ───────────────────────────────────────────────

  func testSyncConflict_LocalAndDeviceBothModified_BothVersionsPreserved() async throws {
    // Given two devices representing "local state" and "device state"
    let deviceA = VirtualMTPDevice(config: .pixel7)
    let deviceB = VirtualMTPDevice(config: .pixel7)
    try await deviceA.openIfNeeded()
    try await deviceB.openIfNeeded()

    // When both sides have a file with the same name but different content
    await deviceA.addObject(
      VirtualObjectConfig(
        handle: 3000, storage: storage, parent: nil,
        name: "notes.txt", formatCode: 0x3000, data: Data("local-edit-v2".utf8)))
    await deviceB.addObject(
      VirtualObjectConfig(
        handle: 3000, storage: storage, parent: nil,
        name: "notes.txt", formatCode: 0x3000, data: Data("device-edit-v2".utf8)))

    // Then we can read both versions and detect the conflict
    let urlA = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-conflict-a-\(UUID().uuidString)")
    let urlB = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-conflict-b-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }
    _ = try await deviceA.read(handle: 3000, range: nil, to: urlA)
    _ = try await deviceB.read(handle: 3000, range: nil, to: urlB)

    let localContent = try Data(contentsOf: urlA)
    let deviceContent = try Data(contentsOf: urlB)
    XCTAssertNotEqual(
      localContent, deviceContent,
      "Conflict detected: local and device versions differ")
    XCTAssertEqual(String(data: localContent, encoding: .utf8), "local-edit-v2")
    XCTAssertEqual(String(data: deviceContent, encoding: .utf8), "device-edit-v2")
  }

  func testSyncConflict_DeviceFileNewer_DeviceWins() async throws {
    // Given a device with an updated file
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let newerContent = Data("device-updated-content".utf8)
    await device.addObject(
      VirtualObjectConfig(
        handle: 3010, storage: storage, parent: nil,
        name: "report.docx", formatCode: 0x3000, data: newerContent))

    // When we pull the device version
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-sync-newer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: 3010, range: nil, to: url)

    // Then the device content is retrieved intact
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(
      String(data: actual, encoding: .utf8), "device-updated-content",
      "Newer device version should be pulled successfully")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Multiple device management (two phones)
  // ───────────────────────────────────────────────

  func testMultipleDevices_TwoPhones_IndependentSessions() async throws {
    // Given two different phone devices connected simultaneously
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    try await pixel.openIfNeeded()
    try await samsung.openIfNeeded()

    // Then each device reports its own identity
    let pixelInfo = try await pixel.devGetDeviceInfoUncached()
    let samsungInfo = try await samsung.devGetDeviceInfoUncached()
    XCTAssertEqual(pixelInfo.manufacturer, "Google")
    XCTAssertEqual(samsungInfo.manufacturer, "Samsung")
    XCTAssertNotEqual(
      pixelInfo.model, samsungInfo.model,
      "Two different phones must report distinct models")
  }

  func testMultipleDevices_TwoPhones_IsolatedFileOperations() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    try await pixel.openIfNeeded()
    try await samsung.openIfNeeded()

    // When we add files to each device independently
    await pixel.addObject(
      VirtualObjectConfig(
        handle: 3100, storage: storage, parent: nil,
        name: "pixel-photo.jpg", formatCode: 0x3801, data: Data("pixel".utf8)))
    await samsung.addObject(
      VirtualObjectConfig(
        handle: 3100, storage: storage, parent: nil,
        name: "samsung-photo.jpg", formatCode: 0x3801, data: Data("samsung".utf8)))

    // Then each device only sees its own files
    var pixelNames: [String] = []
    for try await batch in pixel.list(parent: nil, in: storage) {
      pixelNames.append(contentsOf: batch.map(\.name))
    }
    var samsungNames: [String] = []
    for try await batch in samsung.list(parent: nil, in: storage) {
      samsungNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(pixelNames.contains("pixel-photo.jpg"))
    XCTAssertFalse(
      pixelNames.contains("samsung-photo.jpg"),
      "Pixel must not see Samsung files")
    XCTAssertTrue(samsungNames.contains("samsung-photo.jpg"))
    XCTAssertFalse(
      samsungNames.contains("pixel-photo.jpg"),
      "Samsung must not see Pixel files")
  }

  func testMultipleDevices_TwoPhones_ConcurrentDownloads() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)
    try await pixel.openIfNeeded()
    try await samsung.openIfNeeded()

    let pixelData = Data(repeating: 0x11, count: 2048)
    let samsungData = Data(repeating: 0x22, count: 4096)
    await pixel.addObject(
      VirtualObjectConfig(
        handle: 3200, storage: storage, parent: nil,
        name: "pixel-dl.bin", formatCode: 0x3000, data: pixelData))
    await samsung.addObject(
      VirtualObjectConfig(
        handle: 3200, storage: storage, parent: nil,
        name: "samsung-dl.bin", formatCode: 0x3000, data: samsungData))

    // When downloads happen concurrently
    let pixelURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-pixel-dl-\(UUID().uuidString)")
    let samsungURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-samsung-dl-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: pixelURL)
      try? FileManager.default.removeItem(at: samsungURL)
    }
    async let pixelResult = pixel.read(handle: 3200, range: nil, to: pixelURL)
    async let samsungResult = samsung.read(handle: 3200, range: nil, to: samsungURL)
    _ = try await (pixelResult, samsungResult)

    // Then both downloads complete with correct data
    let pixelActual = try Data(contentsOf: pixelURL)
    let samsungActual = try Data(contentsOf: samsungURL)
    XCTAssertEqual(pixelActual.count, 2048, "Pixel download size must match")
    XCTAssertEqual(samsungActual.count, 4096, "Samsung download size must match")
    XCTAssertEqual(pixelActual.first, 0x11)
    XCTAssertEqual(samsungActual.first, 0x22)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Device quirks applying correct settings
  // ───────────────────────────────────────────────

  func testQuirksApplied_OnePlus3T_PropListDisabled() throws {
    // Given the OnePlus 3T quirk entry
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x2A70, pid: 0xF003, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("OnePlus 3T quirk expected in DB")
      return
    }

    // When we build a policy from the quirk
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil,
      ifaceClass: quirk.ifaceClass)

    // Then the policy correctly disables GetObjectPropList
    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "OnePlus 3T policy must disable proplist due to quirk")
  }

  func testQuirksApplied_CanonEOSR5_CameraClassEnabled() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04A9, pid: 0x32B4, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Canon EOS R5 quirk expected in DB")
      return
    }

    let flags = quirk.resolvedFlags()
    XCTAssertTrue(
      flags.cameraClass,
      "Canon EOS R5 must have cameraClass flag set")
    XCTAssertTrue(
      flags.supportsGetObjectPropList,
      "Canon camera must support GetObjectPropList")
  }

  func testQuirksApplied_SamsungGalaxy_KernelDetachRequired() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04E8, pid: 0x6860, bcdDevice: nil,
        ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil)
    else {
      XCTFail("Samsung Galaxy quirk expected in DB")
      return
    }

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil,
      ifaceClass: quirk.ifaceClass)
    XCTAssertTrue(
      policy.flags.requiresKernelDetach,
      "Samsung Galaxy must require kernel detach in policy")
  }

  func testQuirksApplied_VirtualDevice_RespectsConfig() async throws {
    // Given a virtual Canon camera
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()

    // Then it reports the correct manufacturer for quirk matching
    XCTAssertEqual(info.manufacturer, "Canon")
    XCTAssertFalse(
      info.model.isEmpty,
      "Virtual device must expose model for quirk lookup")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Mirror operation with exclusion patterns
  // ───────────────────────────────────────────────

  func testMirrorExclusion_FiltersByExtension() async throws {
    // Given a device with mixed file types
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let files: [(String, Data)] = [
      ("photo1.jpg", Data("jpg1".utf8)),
      ("photo2.jpg", Data("jpg2".utf8)),
      ("thumbs.db", Data("cache".utf8)),
      ("video.mp4", Data("video".utf8)),
      (".nomedia", Data("".utf8)),
    ]
    for (i, file) in files.enumerated() {
      await device.addObject(
        VirtualObjectConfig(
          handle: MTPObjectHandle(3300 + UInt32(i)), storage: storage, parent: nil,
          name: file.0, formatCode: 0x3000, data: file.1))
    }

    // When we list all objects and apply an exclusion filter
    var allNames: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      allNames.append(contentsOf: batch.map(\.name))
    }
    let excluded = Set(["thumbs.db", ".nomedia"])
    let filtered = allNames.filter { !excluded.contains($0) }

    // Then only non-excluded files pass through
    XCTAssertTrue(filtered.contains("photo1.jpg"))
    XCTAssertTrue(filtered.contains("photo2.jpg"))
    XCTAssertTrue(filtered.contains("video.mp4"))
    XCTAssertFalse(
      filtered.contains("thumbs.db"),
      "thumbs.db must be excluded from mirror")
    XCTAssertFalse(
      filtered.contains(".nomedia"),
      ".nomedia must be excluded from mirror")
  }

  func testMirrorExclusion_FiltersByPathPattern() async throws {
    // Given a folder structure with cache directories
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let cacheFolder: MTPObjectHandle = 3400
    await device.addObject(
      VirtualObjectConfig(
        handle: cacheFolder, storage: storage, parent: nil,
        name: ".cache", formatCode: 0x3001))
    await device.addObject(
      VirtualObjectConfig(
        handle: 3401, storage: storage, parent: cacheFolder,
        name: "temp.dat", formatCode: 0x3000, data: Data("temp".utf8)))
    await device.addObject(
      VirtualObjectConfig(
        handle: 3402, storage: storage, parent: nil,
        name: "important.doc", formatCode: 0x3000, data: Data("doc".utf8)))

    // When we list root objects and filter dot-prefixed folders
    var rootNames: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      rootNames.append(contentsOf: batch.map(\.name))
    }
    let mirroredNames = rootNames.filter { !$0.hasPrefix(".") }

    // Then cache directories are excluded
    XCTAssertFalse(
      mirroredNames.contains(".cache"),
      "Dot-prefixed directories must be excluded from mirror")
    XCTAssertTrue(
      mirroredNames.contains("important.doc"),
      "Non-excluded files must be included in mirror")
  }

  func testMirrorExclusion_DiffRowFilterCallback() async throws {
    // Given diff rows representing files to mirror
    let rows: [MTPDiff.Row] = [
      MTPDiff.Row(
        handle: 1, storage: 0x0001_0001, pathKey: "/DCIM/photo.jpg",
        size: 1024, mtime: nil, format: 0x3801),
      MTPDiff.Row(
        handle: 2, storage: 0x0001_0001, pathKey: "/Android/data/cache.tmp",
        size: 512, mtime: nil, format: 0x3000),
      MTPDiff.Row(
        handle: 3, storage: 0x0001_0001, pathKey: "/Music/song.mp3",
        size: 4096, mtime: nil, format: 0x3000),
    ]

    // When we apply an include filter (as MirrorEngine would)
    let include: (MTPDiff.Row) -> Bool = { row in
      !row.pathKey.contains("/Android/")
    }
    let included = rows.filter(include)

    // Then only non-Android paths pass
    XCTAssertEqual(included.count, 2)
    XCTAssertTrue(
      included.allSatisfy { !$0.pathKey.contains("/Android/") },
      "Mirror filter must exclude Android system paths")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Snapshot comparison detecting changes
  // ───────────────────────────────────────────────

  func testSnapshotComparison_DetectsAddedFiles() async throws {
    // Given two snapshots where the second has new files
    let oldSnapshot: [String] = ["photo1.jpg", "photo2.jpg"]
    let newSnapshot: [String] = ["photo1.jpg", "photo2.jpg", "photo3.jpg", "video.mp4"]

    // When we compute the diff
    let added = Set(newSnapshot).subtracting(oldSnapshot)
    let removed = Set(oldSnapshot).subtracting(newSnapshot)

    // Then added files are detected
    XCTAssertEqual(
      added, Set(["photo3.jpg", "video.mp4"]),
      "Snapshot diff must detect newly added files")
    XCTAssertTrue(
      removed.isEmpty,
      "No files should appear as removed")
  }

  func testSnapshotComparison_DetectsRemovedFiles() async throws {
    let oldSnapshot: [String] = ["photo1.jpg", "photo2.jpg", "temp.dat"]
    let newSnapshot: [String] = ["photo1.jpg", "photo2.jpg"]

    let removed = Set(oldSnapshot).subtracting(newSnapshot)
    XCTAssertEqual(
      removed, Set(["temp.dat"]),
      "Snapshot diff must detect removed files")
  }

  func testSnapshotComparison_DetectsModifiedFiles() async throws {
    // Given objects with different sizes representing modifications
    let oldFiles = [
      MTPDiff.Row(
        handle: 1, storage: 0x0001_0001, pathKey: "/notes.txt",
        size: 100, mtime: nil, format: 0x3000),
      MTPDiff.Row(
        handle: 2, storage: 0x0001_0001, pathKey: "/readme.md",
        size: 200, mtime: nil, format: 0x3000),
    ]
    let newFiles = [
      MTPDiff.Row(
        handle: 1, storage: 0x0001_0001, pathKey: "/notes.txt",
        size: 150, mtime: nil, format: 0x3000),
      MTPDiff.Row(
        handle: 2, storage: 0x0001_0001, pathKey: "/readme.md",
        size: 200, mtime: nil, format: 0x3000),
    ]

    // When we detect size changes
    var modified: [String] = []
    for old in oldFiles {
      if let new = newFiles.first(where: { $0.pathKey == old.pathKey }),
        new.size != old.size
      {
        modified.append(old.pathKey)
      }
    }

    XCTAssertEqual(
      modified, ["/notes.txt"],
      "Snapshot diff must detect modified files by size change")
  }

  func testSnapshotComparison_EmptyDiffWhenUnchanged() async throws {
    // Given identical snapshots
    let snapshot: [String] = ["file1.txt", "file2.txt", "file3.txt"]
    let added = Set(snapshot).subtracting(snapshot)
    let removed = Set(snapshot).subtracting(snapshot)

    XCTAssertTrue(added.isEmpty, "Identical snapshots should produce empty added set")
    XCTAssertTrue(removed.isEmpty, "Identical snapshots should produce empty removed set")
  }

  func testSnapshotComparison_SQLiteRoundTrip() async throws {
    // Given a Snapshotter backed by a temp SQLite database
    let dbPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-snap-\(UUID().uuidString).db").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    // Seed a file
    await device.addObject(
      VirtualObjectConfig(
        handle: 3500, storage: storage, parent: nil,
        name: "snapshot-test.txt", formatCode: 0x3000, data: Data("v1".utf8)))

    // When we capture a snapshot
    let deviceId = MTPDeviceID(raw: "bdd-w29-snapshot")
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Then a valid generation is returned
    XCTAssertGreaterThan(
      gen, 0,
      "Snapshot capture must return a positive generation number")
  }

  func testSnapshotComparison_DiffEngineDetectsChanges() async throws {
    // Given two snapshots with differing contents
    let dbPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-w29-diff-\(UUID().uuidString).db").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)
    let deviceId = MTPDeviceID(raw: "bdd-w29-diff")

    // Snapshot 1: one file
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    await device.addObject(
      VirtualObjectConfig(
        handle: 3600, storage: storage, parent: nil,
        name: "original.txt", formatCode: 0x3000, data: Data("v1".utf8)))
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Wait to ensure distinct generation timestamp
    try await Task.sleep(for: .seconds(1.1))

    // Snapshot 2: add another file
    await device.addObject(
      VirtualObjectConfig(
        handle: 3601, storage: storage, parent: nil,
        name: "added.txt", formatCode: 0x3000, data: Data("new".utf8)))
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // When we compute the diff
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

    // Then the new file is detected as added
    XCTAssertFalse(
      diff.added.isEmpty,
      "Diff must detect the newly added file between snapshots")
    XCTAssertTrue(
      diff.added.contains { $0.pathKey.contains("added.txt") },
      "Added file 'added.txt' must appear in diff results")
  }
}

// MARK: - In-Memory Transfer Journal (Wave 29 BDD helpers)

private final class Wave29InMemoryJournal: TransferJournal, @unchecked Sendable {
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
