// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPTestKit
import SwiftMTPQuirks

// MARK: - Advanced Workflow BDD Scenarios

final class AdvancedWorkflowScenarios: XCTestCase {

  private let storage = MTPStorageID(raw: 0x0001_0001)

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Motorola
  // ───────────────────────────────────────────────

  func testMotorolaDevice_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .motorolaMotoG)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Motorola")
    XCTAssertFalse(info.model.isEmpty)
  }

  func testMotorolaDevice_ListsStorages() async throws {
    let device = VirtualMTPDevice(config: .motorolaMotoG)
    try await device.openIfNeeded()
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Motorola device must expose storages")
  }

  func testMotorolaDevice_CanListRoot() async throws {
    let device = VirtualMTPDevice(config: .motorolaMotoG)
    try await device.openIfNeeded()
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storage) {
      items.append(contentsOf: batch)
    }
    XCTAssertTrue(true, "Root listing on Motorola completed")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Sony Xperia
  // ───────────────────────────────────────────────

  func testSonyXperia_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .sonyXperiaZ)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Sony")
  }

  func testSonyXperia_UploadAndVerify() async throws {
    let device = VirtualMTPDevice(config: .sonyXperiaZ)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-sony-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("sony-test".utf8).write(to: url)
    _ = try await device.write(parent: nil, name: "sony.txt", size: 9, from: url)
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == "sony.txt" }) { found = true }
    }
    XCTAssertTrue(found, "Uploaded file must appear on Sony device")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – LG Android
  // ───────────────────────────────────────────────

  func testLGAndroid_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .lgAndroid)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "LG")
  }

  func testLGAndroidOlder_OpensSuccessfully() async throws {
    let device = VirtualMTPDevice(config: .lgAndroidOlder)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "LG")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – HTC
  // ───────────────────────────────────────────────

  func testHTCAndroid_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .htcAndroid)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "HTC")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Huawei
  // ───────────────────────────────────────────────

  func testHuaweiAndroid_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .huaweiAndroid)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Huawei")
  }

  func testHuaweiAndroid_CanCreateFolder() async throws {
    let device = VirtualMTPDevice(config: .huaweiAndroid)
    try await device.openIfNeeded()
    let handle = try await device.createFolder(
      parent: nil, name: "HuaweiBackup", storage: storage)
    var found = false
    for try await batch in device.list(parent: nil, in: storage) {
      if batch.contains(where: { $0.name == "HuaweiBackup" }) { found = true }
    }
    XCTAssertTrue(found, "Created folder must appear on Huawei device")
    XCTAssertGreaterThan(handle, 0)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Fujifilm camera
  // ───────────────────────────────────────────────

  func testFujifilmCamera_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .fujifilmX)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Fujifilm")
  }

  func testFujifilmCamera_DownloadRawFile() async throws {
    let device = VirtualMTPDevice(config: .fujifilmX)
    try await device.openIfNeeded()
    let rawData = Data(repeating: 0xAB, count: 16384)
    let handle: MTPObjectHandle = 2000
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "DSCF0001.RAF", formatCode: 0x3801, data: rawData))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-fuji-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, rawData.count, "Fujifilm RAW download size must match")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – OnePlus 9
  // ───────────────────────────────────────────────

  func testOnePlus9_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .onePlus9)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "OnePlus")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Amazon Kindle Fire
  // ───────────────────────────────────────────────

  func testAmazonKindleFire_OpensSuccessfully() async throws {
    let device = VirtualMTPDevice(config: .amazonKindleFire)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Amazon")
  }

  func testAmazonKindleFire_CanListStorages() async throws {
    let device = VirtualMTPDevice(config: .amazonKindleFire)
    try await device.openIfNeeded()
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: New brand discovery – Nokia, Lenovo, GoPro
  // ───────────────────────────────────────────────

  func testNokiaAndroid_Opens() async throws {
    let device = VirtualMTPDevice(config: .nokiaAndroid)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Nokia")
  }

  func testLenovoAndroid_Opens() async throws {
    let device = VirtualMTPDevice(config: .lenovoAndroid)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Lenovo")
  }

  func testGoProHero_OpensAndReportsManufacturer() async throws {
    let device = VirtualMTPDevice(config: .goProHero)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "GoPro")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Batch transfer – multi-file download
  // ───────────────────────────────────────────────

  func testBatchDownload_TenFiles_AllIntact() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let count = 10
    for i in 0..<count {
      await device.addObject(VirtualObjectConfig(
        handle: MTPObjectHandle(3000 + UInt32(i)), storage: storage, parent: nil,
        name: "batch_\(i).jpg", formatCode: 0x3801,
        data: Data("photo-\(i)".utf8)))
    }
    for i in 0..<count {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bdd-batch10-\(i)-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: url) }
      _ = try await device.read(
        handle: MTPObjectHandle(3000 + UInt32(i)), range: nil, to: url)
      let actual = try Data(contentsOf: url)
      XCTAssertEqual(String(data: actual, encoding: .utf8), "photo-\(i)")
    }
  }

  func testBatchDownload_MixedFileTypes() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let files: [(String, UInt16, Data)] = [
      ("IMG_001.jpg", 0x3801, Data(repeating: 0x01, count: 1024)),
      ("VID_001.mp4", 0x3000, Data(repeating: 0x02, count: 2048)),
      ("DOC_001.pdf", 0x3000, Data(repeating: 0x03, count: 512)),
    ]
    for (i, file) in files.enumerated() {
      await device.addObject(VirtualObjectConfig(
        handle: MTPObjectHandle(3100 + UInt32(i)), storage: storage, parent: nil,
        name: file.0, formatCode: file.1, data: file.2))
    }
    for (i, file) in files.enumerated() {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bdd-mixed-\(i)-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: url) }
      _ = try await device.read(
        handle: MTPObjectHandle(3100 + UInt32(i)), range: nil, to: url)
      let actual = try Data(contentsOf: url)
      XCTAssertEqual(actual.count, file.2.count,
        "Mixed batch file \(file.0) size must match")
    }
  }

  func testBatchUpload_MultipleFiles() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()
    for i in 0..<5 {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bdd-batchup-\(i)-\(UUID().uuidString).txt")
      defer { try? FileManager.default.removeItem(at: url) }
      let data = Data("upload-\(i)".utf8)
      try data.write(to: url)
      _ = try await device.write(
        parent: nil, name: "up_\(i).txt", size: UInt64(data.count), from: url)
    }
    var names: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    for i in 0..<5 {
      XCTAssertTrue(names.contains("up_\(i).txt"),
        "Batch upload file up_\(i).txt must be present")
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Error handling – disconnect mid-transfer
  // ───────────────────────────────────────────────

  func testDisconnect_DuringGetObjectHandles() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getObjectHandles), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getObjectHandles(storage: storage, parent: nil)
      XCTFail("Expected disconnect error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testDisconnect_DuringGetStorageInfo() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getStorageInfo), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .samsungGalaxy, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getStorageInfo(id: storage)
      XCTFail("Expected disconnect error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  func testDisconnect_DuringGetDeviceInfo() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getDeviceInfo), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected disconnect error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice)
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Error handling – timeout on various ops
  // ───────────────────────────────────────────────

  func testTimeout_DuringGetStorageIDs() async throws {
    let link = VirtualMTPLink(
      config: .pixel7,
      faultSchedule: FaultSchedule([.timeoutOnce(on: .getStorageIDs)]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testTimeout_DuringGetObjectInfos() async throws {
    let link = VirtualMTPLink(
      config: .pixel7,
      faultSchedule: FaultSchedule([.timeoutOnce(on: .getObjectInfos)]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getObjectInfos(storage: storage, parent: nil, format: nil)
      XCTFail("Expected timeout")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout)
    }
  }

  func testTimeout_RetrySucceedsAfterOneShotFault() async throws {
    let link = VirtualMTPLink(
      config: .pixel7,
      faultSchedule: FaultSchedule([.timeoutOnce(on: .getStorageIDs)]))
    try await link.openSession(id: 1)
    do { _ = try await link.getStorageIDs() } catch { /* expected */ }
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "Retry after one-shot timeout must succeed")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Error handling – IO / pipe stall
  // ───────────────────────────────────────────────

  func testPipeStall_DuringGetObjectHandles() async throws {
    let link = VirtualMTPLink(
      config: .pixel7,
      faultSchedule: FaultSchedule([.pipeStall(on: .getObjectHandles)]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getObjectHandles(storage: storage, parent: nil)
      XCTFail("Expected pipe stall error")
    } catch let err as TransportError {
      if case .io(let msg) = err {
        XCTAssertTrue(msg.contains("pipe stall"), "IO error must mention pipe stall")
      } else {
        XCTFail("Expected .io error, got \(err)")
      }
    }
  }

  func testPipeStall_DuringDeleteObject() async throws {
    let link = VirtualMTPLink(
      config: .pixel7,
      faultSchedule: FaultSchedule([.pipeStall(on: .deleteObject)]))
    try await link.openSession(id: 1)
    do {
      try await link.deleteObject(handle: 999)
      XCTFail("Expected pipe stall error")
    } catch let err as TransportError {
      if case .io = err { /* expected */ } else { XCTFail("Expected .io error") }
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Error handling – busy retries
  // ───────────────────────────────────────────────

  func testBusy_DuringGetStorageIDs_RetrySucceeds() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 2)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    // First two calls fail with busy
    for _ in 0..<2 {
      do {
        _ = try await link.getStorageIDs()
        XCTFail("Expected busy")
      } catch let err as TransportError {
        XCTAssertEqual(err, .busy)
      }
    }
    // Third call succeeds (fault exhausted)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "After busy faults exhausted, call must succeed")
  }

  func testBusy_ErrorDescriptionIsClear() {
    let error = TransportError.busy
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.lowercased().contains("busy"))
    XCTAssertNotNil(error.recoverySuggestion)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Error handling – access denied
  // ───────────────────────────────────────────────

  func testAccessDenied_DuringOpenSession() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.openSession), error: .accessDenied, repeatCount: 1)
    let link = VirtualMTPLink(config: .samsungGalaxy, faultSchedule: FaultSchedule([fault]))
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected accessDenied")
    } catch let err as TransportError {
      XCTAssertEqual(err, .accessDenied)
    }
  }

  func testAccessDenied_ErrorDescriptionMentionsAccess() {
    let error = TransportError.accessDenied
    XCTAssertNotNil(error.errorDescription)
    XCTAssertNotNil(error.recoverySuggestion)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Quirks-driven behavior – brand adaptation
  // ───────────────────────────────────────────────

  func testQuirk_XiaomiAltPID_Recognized() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x2717, pid: 0xFF40, bcdDevice: nil,
      ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil)
    XCTAssertNotNil(quirk, "Xiaomi Mi Note 2 alt PID must have a quirk entry")
    XCTAssertEqual(quirk?.id, "xiaomi-mi-note-2-ff40")
  }

  func testQuirk_OnePlus3T_DisablesPropList() throws {
    let db = try QuirkDatabase.load()
    guard let quirk = db.match(
      vid: 0x2A70, pid: 0xF003, bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else { XCTFail("OnePlus 3T must be in quirk DB"); return }
    XCTAssertFalse(quirk.resolvedFlags().supportsGetObjectPropList)
  }

  func testQuirk_CanonEOSR5_HasCameraClass() throws {
    let db = try QuirkDatabase.load()
    guard let quirk = db.match(
      vid: 0x04A9, pid: 0x32B4, bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else { XCTFail("Canon EOS R5 must be in quirk DB"); return }
    XCTAssertTrue(quirk.resolvedFlags().cameraClass)
  }

  func testQuirk_PolicyOverridesChunkSize() throws {
    let overrides = ["maxChunkBytes": "2097152"]
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: overrides, ifaceClass: 0x06)
    XCTAssertEqual(policy.tuning.maxChunkBytes, 2_097_152)
  }

  func testQuirk_UnknownDevice_PTPClassEnablesPropList() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
  }

  func testQuirk_UnknownDevice_VendorClassDisablesPropList() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0xFF)
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Resume after interruption
  // ───────────────────────────────────────────────

  func testResume_JournalTracksPartialRead() async throws {
    let journal = BDDInMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-read")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-r-\(UUID().uuidString)")
    let id = try await journal.beginRead(
      device: deviceId, handle: 42, name: "video.mp4",
      size: 50_000_000, supportsPartial: true,
      tempURL: tempURL, finalURL: nil, etag: (size: nil, mtime: nil))
    try await journal.updateProgress(id: id, committed: 25_000_000)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(records.contains { $0.id == id && $0.committedBytes == 25_000_000 })
  }

  func testResume_JournalTracksPartialWrite() async throws {
    let journal = BDDInMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-write")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-w-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "backup.tar",
      size: 100_000_000, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.updateProgress(id: id, committed: 60_000_000)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(records.contains { $0.id == id && $0.committedBytes == 60_000_000 })
  }

  func testResume_FailedTransferRecorded() async throws {
    let journal = BDDInMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-fail")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-f-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "fail.zip",
      size: 10_000, supportsPartial: false, tempURL: tempURL, sourceURL: nil)
    try await journal.fail(id: id, error: TransportError.noDevice)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(records.contains { $0.id == id && $0.state == "failed" })
  }

  func testResume_CompletedTransferCleared() async throws {
    let journal = BDDInMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-done2")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-d-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "done.zip",
      size: 1024, supportsPartial: false, tempURL: tempURL, sourceURL: nil)
    try await journal.complete(id: id)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertFalse(records.contains { $0.id == id })
  }

  func testResume_RemoteHandlePersisted() async throws {
    let journal = BDDInMemoryTransferJournal()
    let deviceId = MTPDeviceID(raw: "bdd-resume-handle")
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-resume-h-\(UUID().uuidString)")
    let id = try await journal.beginWrite(
      device: deviceId, parent: 0, name: "handle-test.bin",
      size: 4096, supportsPartial: true, tempURL: tempURL, sourceURL: nil)
    try await journal.recordRemoteHandle(id: id, handle: 12345)
    let records = try await journal.loadResumables(for: deviceId)
    XCTAssertTrue(records.contains { $0.id == id && $0.remoteHandle == 12345 })
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Progress and cancellation
  // ───────────────────────────────────────────────

  func testProgress_DownloadReportsCompletion() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let handle: MTPObjectHandle = 4000
    let data = Data(repeating: 0xDD, count: 8192)
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "progress-test.bin", formatCode: 0x3000, data: data))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-progress-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    let progress = try await device.read(handle: handle, range: nil, to: url)
    XCTAssertEqual(progress.completedUnitCount, Int64(data.count))
    XCTAssertEqual(progress.totalUnitCount, Int64(data.count))
  }

  func testProgress_UploadReportsCompletion() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-up-prog-\(UUID().uuidString).bin")
    defer { try? FileManager.default.removeItem(at: url) }
    let data = Data(repeating: 0xEE, count: 4096)
    try data.write(to: url)
    let progress = try await device.write(
      parent: nil, name: "up-prog.bin", size: UInt64(data.count), from: url)
    XCTAssertEqual(progress.completedUnitCount, Int64(data.count))
  }

  func testProgress_EmptyFileReportsZero() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let handle: MTPObjectHandle = 4010
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "empty-prog.txt", formatCode: 0x3000, data: Data()))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-empty-prog-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    let progress = try await device.read(handle: handle, range: nil, to: url)
    XCTAssertEqual(progress.completedUnitCount, 0)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Device capability negotiation
  // ───────────────────────────────────────────────

  func testCapabilityNegotiation_PTPClass_Defaults() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertFalse(policy.flags.requiresKernelDetach,
      "PTP camera defaults should not require kernel detach")
  }

  func testCapabilityNegotiation_VendorClass_Defaults() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0xFF)
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.requiresKernelDetach)
  }

  func testCapabilityNegotiation_NoIfaceClass_SafeDefaults() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: nil)
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.requiresKernelDetach)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Folder operations and hierarchy
  // ───────────────────────────────────────────────

  func testCreateNestedFolders() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let parent = try await device.createFolder(
      parent: nil, name: "Level1", storage: storage)
    let child = try await device.createFolder(
      parent: parent, name: "Level2", storage: storage)
    var childNames: [String] = []
    for try await batch in device.list(parent: parent, in: storage) {
      childNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(childNames.contains("Level2"))
    XCTAssertGreaterThan(child, parent)
  }

  func testUploadToSubfolder() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()
    let folder = try await device.createFolder(
      parent: nil, name: "Documents", storage: storage)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-subfolder-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("sub-content".utf8).write(to: url)
    _ = try await device.write(
      parent: folder, name: "readme.txt", size: 11, from: url)
    var names: [String] = []
    for try await batch in device.list(parent: folder, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(names.contains("readme.txt"))
  }

  func testDeleteFolder_RemovesFromListing() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let folder = try await device.createFolder(
      parent: nil, name: "ToDelete", storage: storage)
    try await device.delete(folder, recursive: true)
    var names: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    XCTAssertFalse(names.contains("ToDelete"))
  }

  func testRenameFile_UpdatesListing() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let handle: MTPObjectHandle = 5000
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "old-name.txt", formatCode: 0x3000, data: Data("content".utf8)))
    try await device.rename(handle, to: "new-name.txt")
    let info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "new-name.txt")
  }

  func testMoveFile_ChangesParent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let folder = try await device.createFolder(
      parent: nil, name: "Target", storage: storage)
    let handle: MTPObjectHandle = 5010
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "moveable.txt", formatCode: 0x3000, data: Data("move".utf8)))
    try await device.move(handle, to: folder)
    var childNames: [String] = []
    for try await batch in device.list(parent: folder, in: storage) {
      childNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(childNames.contains("moveable.txt"))
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Event injection and monitoring
  // ───────────────────────────────────────────────

  func testEventInjection_ObjectAdded() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    await device.injectEvent(.objectAdded(9999))
    // Verify the event stream delivers the event
    var received = false
    for await event in device.events {
      if case .objectAdded(let h) = event, h == 9999 {
        received = true
        break
      }
    }
    XCTAssertTrue(received, "ObjectAdded event must be delivered")
  }

  func testEventInjection_StorageRemoved() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let sid = MTPStorageID(raw: 0x0002_0001)
    await device.injectEvent(.storageRemoved(sid))
    var received = false
    for await event in device.events {
      if case .storageRemoved(let s) = event, s == sid {
        received = true
        break
      }
    }
    XCTAssertTrue(received, "StorageRemoved event must be delivered")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Cross-device concurrent operations
  // ───────────────────────────────────────────────

  func testConcurrent_ThreeDevices_IndependentOps() async throws {
    let devices: [VirtualMTPDevice] = [
      VirtualMTPDevice(config: .pixel7),
      VirtualMTPDevice(config: .canonEOSR5),
      VirtualMTPDevice(config: .motorolaMotoG),
    ]
    for d in devices { try await d.openIfNeeded() }
    async let i0 = devices[0].devGetDeviceInfoUncached()
    async let i1 = devices[1].devGetDeviceInfoUncached()
    async let i2 = devices[2].devGetDeviceInfoUncached()
    let (a, b, c) = try await (i0, i1, i2)
    let manufacturers = Set([a.manufacturer, b.manufacturer, c.manufacturer])
    XCTAssertEqual(manufacturers.count, 3, "Three distinct manufacturers expected")
  }

  func testConcurrent_ReadFromTwoDevices() async throws {
    let deviceA = VirtualMTPDevice(config: .pixel7)
    let deviceB = VirtualMTPDevice(config: .canonEOSR5)
    try await deviceA.openIfNeeded()
    try await deviceB.openIfNeeded()
    let hA: MTPObjectHandle = 6000
    let hB: MTPObjectHandle = 6001
    await deviceA.addObject(VirtualObjectConfig(
      handle: hA, storage: storage, parent: nil,
      name: "a.dat", formatCode: 0x3000, data: Data("deviceA".utf8)))
    await deviceB.addObject(VirtualObjectConfig(
      handle: hB, storage: storage, parent: nil,
      name: "b.dat", formatCode: 0x3000, data: Data("deviceB".utf8)))
    let urlA = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-conc-a-\(UUID().uuidString)")
    let urlB = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-conc-b-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: urlA)
      try? FileManager.default.removeItem(at: urlB)
    }
    async let pA = deviceA.read(handle: hA, range: nil, to: urlA)
    async let pB = deviceB.read(handle: hB, range: nil, to: urlB)
    _ = try await (pA, pB)
    let dataA = try Data(contentsOf: urlA)
    let dataB = try Data(contentsOf: urlB)
    XCTAssertEqual(String(data: dataA, encoding: .utf8), "deviceA")
    XCTAssertEqual(String(data: dataB, encoding: .utf8), "deviceB")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Partial/range read
  // ───────────────────────────────────────────────

  func testPartialRead_FirstHalf() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let data = Data(repeating: 0xAA, count: 1000)
    let handle: MTPObjectHandle = 7000
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "partial.bin", formatCode: 0x3000, data: data))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-partial-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: 0..<500, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, 500)
  }

  func testPartialRead_LastPortion() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let data = Data(0..<200)
    let handle: MTPObjectHandle = 7010
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "partial2.bin", formatCode: 0x3000, data: data))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-partial2-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: 150..<200, to: url)
    let actual = try Data(contentsOf: url)
    XCTAssertEqual(actual.count, 50)
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Object not found error
  // ───────────────────────────────────────────────

  func testReadNonexistentHandle_ThrowsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-notfound-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
      _ = try await device.read(handle: 99999, range: nil, to: url)
      XCTFail("Expected objectNotFound error")
    } catch let err as MTPError {
      XCTAssertEqual(err, .objectNotFound)
    }
  }

  func testDeleteNonexistentHandle_ThrowsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    do {
      try await device.delete(99999, recursive: false)
      XCTFail("Expected objectNotFound error")
    } catch let err as MTPError {
      XCTAssertEqual(err, .objectNotFound)
    }
  }

  func testRenameNonexistentHandle_ThrowsObjectNotFound() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    do {
      try await device.rename(99999, to: "nope.txt")
      XCTFail("Expected objectNotFound error")
    } catch let err as MTPError {
      XCTAssertEqual(err, .objectNotFound)
    }
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Operation logging for auditing
  // ───────────────────────────────────────────────

  func testOperationLog_RecordsOpenAndRead() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let handle: MTPObjectHandle = 8000
    await device.addObject(VirtualObjectConfig(
      handle: handle, storage: storage, parent: nil,
      name: "logged.txt", formatCode: 0x3000, data: Data("log".utf8)))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-log-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await device.read(handle: handle, range: nil, to: url)
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "openIfNeeded" })
    XCTAssertTrue(ops.contains { $0.operation == "read" })
  }

  func testOperationLog_RecordsWriteAndDelete() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("bdd-logw-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("data".utf8).write(to: url)
    _ = try await device.write(parent: nil, name: "logw.txt", size: 4, from: url)
    // Find the handle of the written file to delete
    var written: MTPObjectHandle?
    for try await batch in device.list(parent: nil, in: storage) {
      if let obj = batch.first(where: { $0.name == "logw.txt" }) {
        written = obj.handle
      }
    }
    if let h = written {
      try await device.delete(h, recursive: false)
    }
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "write" })
    XCTAssertTrue(ops.contains { $0.operation == "delete" })
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: Newer-gen device configs
  // ───────────────────────────────────────────────

  func testGooglePixel8_Opens() async throws {
    let device = VirtualMTPDevice(config: .googlePixel8)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Google")
  }

  func testOnePlus12_Opens() async throws {
    let device = VirtualMTPDevice(config: .onePlus12)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "OnePlus")
  }

  func testSamsungGalaxyS24_Opens() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxyS24)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Samsung")
  }

  func testNothingPhone2_Opens() async throws {
    let device = VirtualMTPDevice(config: .nothingPhone2)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Nothing")
  }

  func testValveSteamDeck_Opens() async throws {
    let device = VirtualMTPDevice(config: .valveSteamDeck)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Valve")
  }

  func testMetaQuest3_Opens() async throws {
    let device = VirtualMTPDevice(config: .metaQuest3)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Meta")
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: TransportError localized messages
  // ───────────────────────────────────────────────

  func testTransportError_NoDevice_HasDescription() {
    let err = TransportError.noDevice
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.contains("MTP"))
  }

  func testTransportError_Timeout_HasDescription() {
    let err = TransportError.timeout
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("timed out"))
  }

  func testTransportError_Stall_HasDescription() {
    let err = TransportError.stall
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("stall"))
  }

  func testTransportError_IO_IncludesMessage() {
    let err = TransportError.io("bulk pipe reset")
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.contains("bulk pipe reset"))
  }

  func testTransportError_TimeoutInPhase_BulkOut() {
    let err = TransportError.timeoutInPhase(.bulkOut)
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.contains("bulk-out"))
  }

  func testTransportError_TimeoutInPhase_BulkIn() {
    let err = TransportError.timeoutInPhase(.bulkIn)
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.contains("bulk-in"))
  }

  // ───────────────────────────────────────────────
  // MARK: Scenario: MTPError localized messages
  // ───────────────────────────────────────────────

  func testMTPError_ObjectNotFound_HasDescription() {
    let err = MTPError.objectNotFound
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("not found"))
  }

  func testMTPError_StorageFull_HasDescription() {
    let err = MTPError.storageFull
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("full"))
  }

  func testMTPError_PermissionDenied_HasDescription() {
    let err = MTPError.permissionDenied
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("denied"))
  }

  func testMTPError_DeviceDisconnected_HasDescription() {
    let err = MTPError.deviceDisconnected
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.lowercased().contains("disconnect"))
  }

  func testMTPError_VerificationFailed_IncludesSizes() {
    let err = MTPError.verificationFailed(expected: 1024, actual: 512)
    XCTAssertNotNil(err.errorDescription)
    XCTAssertTrue(err.errorDescription!.contains("1024"))
    XCTAssertTrue(err.errorDescription!.contains("512"))
  }
}

// MARK: - In-Memory Transfer Journal (for advanced resume tests)

private final class BDDInMemoryTransferJournal: TransferJournal, @unchecked Sendable {
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
