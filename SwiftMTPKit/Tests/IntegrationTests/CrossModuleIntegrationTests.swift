// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
@testable import SwiftMTPIndex

// MARK: - Mock TransferJournal

/// In-memory transfer journal for integration tests.
private actor MockTransferJournal: TransferJournal {
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
    guard var record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: committed, supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: record.state, updatedAt: Date())
  }

  func fail(id: String, error: Error) async throws {
    guard var record = entries[id] else { return }
    entries[id] = TransferRecord(
      id: record.id, deviceId: record.deviceId, kind: record.kind,
      handle: record.handle, parentHandle: record.parentHandle,
      name: record.name, totalBytes: record.totalBytes,
      committedBytes: record.committedBytes, supportsPartial: record.supportsPartial,
      localTempURL: record.localTempURL, finalURL: record.finalURL,
      state: "failed", updatedAt: Date())
  }

  func complete(id: String) async throws {
    guard var record = entries[id] else { return }
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

// MARK: - 1. Core → Transport: Mock transport roundtrip

/// Tests that VirtualMTPLink correctly handles MTP protocol operations
/// bridging SwiftMTPCore types through the transport layer.
final class CoreTransportIntegrationTests: XCTestCase {

  func testVirtualLinkGetDeviceInfoRoundtrip() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertTrue(info.operationsSupported.contains(0x1001))

    try await link.closeSession()
  }

  func testVirtualLinkStorageEnumeration() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty)

    let storageInfo = try await link.getStorageInfo(id: storageIDs[0])
    XCTAssertEqual(storageInfo.description, "Internal shared storage")
    XCTAssertGreaterThan(storageInfo.capacityBytes, 0)
  }

  func testVirtualLinkObjectHandlesAndInfos() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    let handles = try await link.getObjectHandles(storage: storageIDs[0], parent: nil)
    XCTAssertFalse(handles.isEmpty, "Root should have DCIM folder")

    let infos = try await link.getObjectInfos(handles)
    XCTAssertEqual(infos.count, handles.count)
    XCTAssertTrue(infos.contains(where: { $0.name == "DCIM" }))
  }

  func testVirtualLinkCommandExecution() async throws {
    let link = VirtualMTPLink(config: .samsungGalaxy)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let command = PTPContainer(type: 1, code: 0x1001, txid: 42)
    let result = try await link.executeCommand(command)
    XCTAssertEqual(result.code, 0x2001, "OK response expected")
    XCTAssertEqual(result.txid, 42)
  }
}

// MARK: - 2. Core → Index: Device enumeration → index population

/// Tests that device enumeration via VirtualMTPDevice feeds into the
/// Snapshotter index and produces valid snapshot generations.
final class CoreIndexIntegrationTests: XCTestCase {

  private func makeTempDBPath() -> String {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-test-\(UUID().uuidString).db")
    return tmp.path
  }

  func testDeviceEnumerationPopulatesIndex() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)

    XCTAssertGreaterThan(gen, 0)

    let latestGen = try snapshotter.latestGeneration(for: deviceId)
    XCTAssertEqual(latestGen, gen)
  }

  func testMultipleSnapshotsCreateDistinctGenerations() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Small delay to ensure different timestamp
    try await Task.sleep(nanoseconds: 1_100_000_000)

    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    XCTAssertNotEqual(gen1, gen2)
    XCTAssertEqual(try snapshotter.latestGeneration(for: deviceId), gen2)
    XCTAssertEqual(try snapshotter.previousGeneration(for: deviceId, before: gen2), gen1)
  }

  func testEmptyDeviceSnapshotSucceeds() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    XCTAssertGreaterThan(gen, 0)
  }
}

// MARK: - 3. Index → Sync: Index snapshot → diff

/// Tests that snapshots can be diffed to detect added, removed, and modified objects.
final class IndexDiffIntegrationTests: XCTestCase {

  private func makeTempDBPath() -> String {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-test-\(UUID().uuidString).db")
    return tmp.path
  }

  func testDiffDetectsAddedObjects() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    // First snapshot
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Add a new root-level object (Snapshotter only lists root objects)
    let newObj = VirtualObjectConfig(
      handle: 100,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "new_photo.jpg",
      sizeBytes: 1_000_000,
      formatCode: 0x3801,
      data: Data(repeating: 0xAA, count: 256))
    await device.addObject(newObj)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second snapshot
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Compute diff
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

    XCTAssertGreaterThan(diff.added.count, 0, "Diff should detect the newly added object")
    XCTAssertTrue(diff.added.contains(where: { $0.pathKey.contains("new_photo.jpg") }))
  }

  func testDiffDetectsRemovedObjects() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    // First snapshot with all objects
    let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Remove a root-level object (handle 1 = DCIM folder; Snapshotter only lists root objects)
    await device.removeObject(handle: 1)

    try await Task.sleep(nanoseconds: 1_100_000_000)

    // Second snapshot
    let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)

    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)
    XCTAssertGreaterThan(diff.removed.count, 0, "Diff should detect the removed object")
  }

  func testDiffFromNilOldGenTreatsAllAsAdded() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let snapshotter = try Snapshotter(dbPath: dbPath)
    let diffEngine = try DiffEngine(dbPath: dbPath)

    let gen = try await snapshotter.capture(device: device, deviceId: deviceId)
    let diff = try await diffEngine.diff(deviceId: deviceId, oldGen: nil, newGen: gen)

    // All objects should appear as added when comparing against nil
    XCTAssertGreaterThan(diff.added.count, 0)
    XCTAssertEqual(diff.removed.count, 0)
  }
}

// MARK: - 4. Quirks → Core: Device matching → tuning application

/// Tests the full flow from device fingerprint through quirk resolution
/// to policy/tuning application.
final class QuirksCoreIntegrationTests: XCTestCase {

  func testQuirkDatabaseMatchAndPolicyBuilding() {
    let quirk = DeviceQuirk(
      id: "test-device-001",
      vid: 0x2717, pid: 0xFF10,
      maxChunkBytes: 512 * 1024,
      ioTimeoutMs: 12000,
      flags: QuirkFlags())

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x2717, pid: 0xFF10,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 12000)
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk)
  }

  func testUnmatchedDeviceGetsDefaults() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0xDEAD, pid: 0xBEEF,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(policy.tuning.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, defaults.ioTimeoutMs)
    XCTAssertTrue(policy.flags.requiresKernelDetach, "Default flags require kernel detach")
  }

  func testCameraClassHeuristicAppliedViaQuirkResolver() {
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x32B4,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
  }

  func testQuirkFlagsOverrideDefaults() {
    var customFlags = QuirkFlags()
    customFlags.supportsPartialRead64 = false
    customFlags.disableEventPump = true
    customFlags.writeToSubfolderOnly = true
    customFlags.preferredWriteFolder = "Download"

    let quirk = DeviceQuirk(
      id: "custom-flags-device",
      vid: 0x1234, pid: 0x5678,
      flags: customFlags)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234, pid: 0x5678,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    XCTAssertFalse(policy.flags.supportsPartialRead64)
    XCTAssertTrue(policy.flags.disableEventPump)
    XCTAssertTrue(policy.flags.writeToSubfolderOnly)
    XCTAssertEqual(policy.flags.preferredWriteFolder, "Download")
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }
}

// MARK: - 5. End-to-end file transfer simulation

/// Tests full file read/write lifecycle using VirtualMTPDevice.
final class EndToEndFileTransferTests: XCTestCase {

  func testWriteAndReadBackFile() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-e2e-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Write a file to the device
    let sourceURL = tmpDir.appendingPathComponent("upload.txt")
    let testData = Data("Hello, MTP World! 🌍".utf8)
    try testData.write(to: sourceURL)

    let writeProgress = try await device.write(
      parent: 1, name: "upload.txt", size: UInt64(testData.count), from: sourceURL)
    XCTAssertEqual(writeProgress.completedUnitCount, Int64(testData.count))

    // Find the written object by listing
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    var foundHandle: MTPObjectHandle?
    let stream = device.list(parent: 1, in: storages[0].id)
    for try await batch in stream {
      if let obj = batch.first(where: { $0.name == "upload.txt" }) {
        foundHandle = obj.handle
      }
    }
    XCTAssertNotNil(foundHandle, "Written file should be discoverable")

    // Read it back
    let downloadURL = tmpDir.appendingPathComponent("download.txt")
    let readProgress = try await device.read(handle: foundHandle!, range: nil, to: downloadURL)
    XCTAssertGreaterThan(readProgress.completedUnitCount, 0)

    let readBack = try Data(contentsOf: downloadURL)
    XCTAssertEqual(readBack, testData, "Read data should match written data")
  }

  func testReadNonExistentObjectThrows() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-e2e-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let url = tmpDir.appendingPathComponent("output.dat")
    do {
      _ = try await device.read(handle: 99999, range: nil, to: url)
      XCTFail("Should throw objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testCreateFolderAndWriteIntoIt() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-e2e-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let storages = try await device.storages()
    let storageId = storages[0].id

    // Create a folder
    let folderHandle = try await device.createFolder(
      parent: nil, name: "TestFolder", storage: storageId)
    XCTAssertGreaterThan(folderHandle, 0)

    // Write a file into the folder
    let sourceURL = tmpDir.appendingPathComponent("file.bin")
    let data = Data(repeating: 0x42, count: 1024)
    try data.write(to: sourceURL)

    let progress = try await device.write(
      parent: folderHandle, name: "file.bin", size: UInt64(data.count), from: sourceURL)
    XCTAssertEqual(progress.completedUnitCount, Int64(data.count))

    // Verify the file is listed under the folder
    var foundFile = false
    let stream = device.list(parent: folderHandle, in: storageId)
    for try await batch in stream {
      if batch.contains(where: { $0.name == "file.bin" }) {
        foundFile = true
      }
    }
    XCTAssertTrue(foundFile, "File should be listed under the created folder")
  }

  func testDeleteAndRenameOperations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Rename
    try await device.rename(3, to: "renamed_photo.jpg")
    let info = try await device.getInfo(handle: 3)
    XCTAssertEqual(info.name, "renamed_photo.jpg")

    // Delete
    try await device.delete(3, recursive: false)
    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Should throw after deletion")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testOperationLogRecordsActions() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    await device.clearOperations()

    _ = try await device.storages()
    _ = try await device.getInfo(handle: 1)

    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "storages" }))
    XCTAssertTrue(ops.contains(where: { $0.operation == "getInfo" }))
  }
}

// MARK: - 6. Error propagation across module boundaries

/// Tests that errors from the transport layer propagate correctly through
/// the device and core layers.
final class ErrorPropagationIntegrationTests: XCTestCase {

  func testFaultInjectingLinkPropagatesTimeout() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Should have thrown timeout")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }

    // Second call should succeed (fault was one-shot)
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
  }

  func testFaultInjectingLinkBusyRetryPattern() async throws {
    let innerLink = VirtualMTPLink(config: .samsungGalaxy)
    let schedule = FaultSchedule([
      ScheduledFault.busyForRetries(3)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    // First 3 executeCommand calls should fail with busy
    for i in 0..<3 {
      let command = PTPContainer(type: 1, code: 0x1001, txid: UInt32(i))
      do {
        _ = try await faultyLink.executeCommand(command)
        XCTFail("Call \(i) should have thrown busy")
      } catch let error as TransportError {
        XCTAssertEqual(error, .busy)
      }
    }

    // 4th call should succeed
    let command = PTPContainer(type: 1, code: 0x1001, txid: 99)
    let result = try await faultyLink.executeCommand(command)
    XCTAssertEqual(result.code, 0x2001)
  }

  func testFaultInjectingLinkDisconnectError() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .disconnected)
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Should have thrown noDevice")
    } catch let error as TransportError {
      XCTAssertEqual(error, .noDevice)
    }
  }

  func testVirtualDeviceObjectNotFoundError() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      _ = try await device.getInfo(handle: 42)
      XCTFail("Should throw objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testMultipleFaultsInSequence() async throws {
    let innerLink = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(0), error: .timeout),
      ScheduledFault(trigger: .atCallIndex(1), error: .busy),
    ])
    let faultyLink = FaultInjectingLink(wrapping: innerLink, schedule: schedule)

    // First call: timeout
    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected timeout")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }

    // Second call: busy
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected busy")
    } catch let error as TransportError {
      XCTAssertEqual(error, .busy)
    }

    // Third call: succeeds
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }
}

// MARK: - 7. Device discovery → quirk matching → session setup flow

/// Tests the end-to-end flow from device summary through fingerprint creation,
/// quirk resolution, and session initialization.
final class DeviceDiscoveryQuirkSessionTests: XCTestCase {

  func testFullDiscoveryToSessionFlow() async throws {
    // Simulate device discovery via VirtualMTPDevice
    let device = VirtualMTPDevice(config: .pixel7)
    let summary = await device.summary

    // Build fingerprint from summary (simulating what LibUSBDiscovery would do)
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: summary.vendorID ?? 0,
      pid: summary.productID ?? 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      epIn: 0x81,
      epOut: 0x02)

    // Resolve quirks
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertNotNil(policy.tuning)

    // Open session on device
    try await device.openIfNeeded()
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")

    // Enumerate storages
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    // List root objects
    let rootStream = device.list(parent: nil, in: storages[0].id)
    var rootObjects: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootObjects.append(contentsOf: batch)
    }
    XCTAssertTrue(rootObjects.contains(where: { $0.name == "DCIM" }))
  }

  func testCameraDeviceDiscoveryWithHeuristic() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let summary = await device.summary

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: summary.vendorID ?? 0,
      pid: summary.productID ?? 0,
      interfaceClass: 0x06,  // PTP/Still Image Capture
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      epIn: 0x81,
      epOut: 0x02)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    // Camera class heuristic should enable proplist
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertFalse(policy.flags.requiresKernelDetach)

    // Device should be usable
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Canon")

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
    XCTAssertEqual(storages[0].description, "Memory Card")
  }

  func testMultipleDevicePresetsResolveDistinctPolicies() {
    let presets: [(VirtualDeviceConfig, UInt8)] = [
      (.pixel7, 0xFF),
      (.samsungGalaxy, 0xFF),
      (.canonEOSR5, 0x06),
      (.nikonZ6, 0x06),
    ]

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])

    for (config, ifaceClass) in presets {
      let fingerprint = MTPDeviceFingerprint.fromUSB(
        vid: config.summary.vendorID ?? 0,
        pid: config.summary.productID ?? 0,
        interfaceClass: ifaceClass,
        interfaceSubclass: 0x01,
        interfaceProtocol: 0x01,
        epIn: 0x81,
        epOut: 0x02)

      let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
      XCTAssertNotNil(policy.tuning)

      if ifaceClass == 0x06 {
        XCTAssertTrue(
          policy.flags.supportsGetObjectPropList,
          "\(config.summary.model) with PTP class should enable proplist")
      }
    }
  }
}

// MARK: - 8. Transfer journal → resume flow

/// Tests the transfer journal lifecycle: begin, progress, fail, resume, complete.
final class TransferJournalResumeFlowTests: XCTestCase {

  func testJournalBeginProgressComplete() async throws {
    let journal = MockTransferJournal()
    let deviceId = MTPDeviceID(raw: "test:device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.dat")
    let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("final.dat")

    let id = try await journal.beginRead(
      device: deviceId, handle: 42, name: "photo.jpg",
      size: 4_500_000, supportsPartial: true,
      tempURL: tmpURL, finalURL: finalURL, etag: (size: 4_500_000, mtime: nil))

    // Simulate progress updates
    try await journal.updateProgress(id: id, committed: 1_000_000)
    try await journal.updateProgress(id: id, committed: 3_000_000)

    var entry = await journal.entries[id]
    XCTAssertEqual(entry?.committedBytes, 3_000_000)
    XCTAssertEqual(entry?.state, "active")

    // Complete
    try await journal.complete(id: id)
    entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "completed")
    XCTAssertEqual(entry?.committedBytes, 4_500_000)
  }

  func testJournalFailAndResumeFlow() async throws {
    let journal = MockTransferJournal()
    let deviceId = MTPDeviceID(raw: "test:device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.dat")

    // Begin a write transfer
    let id = try await journal.beginWrite(
      device: deviceId, parent: 1, name: "video.mp4",
      size: 10_000_000, supportsPartial: true,
      tempURL: tmpURL, sourceURL: nil)

    // Partial progress then failure
    try await journal.updateProgress(id: id, committed: 5_000_000)
    try await journal.fail(id: id, error: TransportError.timeout)

    let entry = await journal.entries[id]
    XCTAssertEqual(entry?.state, "failed")
    XCTAssertEqual(entry?.committedBytes, 5_000_000)
  }

  func testJournalLoadResumables() async throws {
    let journal = MockTransferJournal()
    let deviceId = MTPDeviceID(raw: "test:device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.dat")

    // Start two transfers for same device
    let id1 = try await journal.beginRead(
      device: deviceId, handle: 10, name: "a.jpg",
      size: 1000, supportsPartial: true,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))
    let id2 = try await journal.beginRead(
      device: deviceId, handle: 20, name: "b.jpg",
      size: 2000, supportsPartial: false,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    // Complete one, leave the other active
    try await journal.complete(id: id1)

    let resumables = try await journal.loadResumables(for: deviceId)
    XCTAssertEqual(resumables.count, 1)
    XCTAssertEqual(resumables[0].name, "b.jpg")
  }

  func testJournalClearStaleTemps() async throws {
    let journal = MockTransferJournal()
    let deviceId = MTPDeviceID(raw: "test:device")
    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.dat")

    _ = try await journal.beginRead(
      device: deviceId, handle: 1, name: "old.jpg",
      size: 100, supportsPartial: false,
      tempURL: tmpURL, finalURL: nil, etag: (size: nil, mtime: nil))

    // Clear temps older than 0 seconds (clears everything)
    try await journal.clearStaleTemps(olderThan: 0)

    let count = await journal.entries.count
    XCTAssertEqual(count, 0)
  }

  func testJournalIntegrationWithVirtualDevice() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let deviceId = await device.id
    let journal = MockTransferJournal()
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-journal-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Begin a journal entry for a read
    let tempURL = tmpDir.appendingPathComponent("temp_photo.jpg")
    let finalURL = tmpDir.appendingPathComponent("photo.jpg")

    let journalId = try await journal.beginRead(
      device: deviceId, handle: 3, name: "IMG_20250101_120000.jpg",
      size: 4_500_000, supportsPartial: true,
      tempURL: tempURL, finalURL: finalURL,
      etag: (size: 4_500_000, mtime: nil))

    // Perform the actual read
    let progress = try await device.read(handle: 3, range: nil, to: tempURL)
    try await journal.updateProgress(
      id: journalId, committed: UInt64(progress.completedUnitCount))
    try await journal.complete(id: journalId)

    let entry = await journal.entries[journalId]
    XCTAssertEqual(entry?.state, "completed")
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
  }
}

// MARK: - Event stream integration

/// Tests that MTP event injection and consumption works across module boundaries.
final class EventStreamIntegrationTests: XCTestCase {

  func testEventInjectionAndConsumption() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Start consuming events
    let eventTask = Task<[MTPEvent], Never> {
      var collected: [MTPEvent] = []
      for await event in await device.events {
        collected.append(event)
        if collected.count >= 3 { break }
      }
      return collected
    }

    // Give the consumer a moment to start
    try await Task.sleep(nanoseconds: 50_000_000)

    // Inject events
    await device.injectEvent(.objectAdded(100))
    await device.injectEvent(.storageInfoChanged(MTPStorageID(raw: 0x0001_0001)))
    await device.injectEvent(.objectRemoved(100))

    let events = await eventTask.value
    XCTAssertEqual(events.count, 3)

    if case .objectAdded(let handle) = events[0] {
      XCTAssertEqual(handle, 100)
    } else {
      XCTFail("First event should be objectAdded")
    }

    if case .storageInfoChanged(let sid) = events[1] {
      XCTAssertEqual(sid.raw, 0x0001_0001)
    } else {
      XCTFail("Second event should be storageInfoChanged")
    }

    if case .objectRemoved(let handle) = events[2] {
      XCTAssertEqual(handle, 100)
    } else {
      XCTFail("Third event should be objectRemoved")
    }
  }
}
