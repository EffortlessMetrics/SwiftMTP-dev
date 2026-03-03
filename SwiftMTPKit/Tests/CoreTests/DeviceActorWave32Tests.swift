// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
import SwiftMTPQuirks

// MARK: - DeviceActor Wave-32 Deep Tests

/// Deep tests for DeviceActor state machine, reconciliation, prop list operations,
/// transfer flow, session management, and concurrent operation serialisation.
final class DeviceActorWave32Tests: XCTestCase {

  // MARK: - State Machine Transitions

  /// Verify canonical happy-path lifecycle: disconnected → connecting → connected →
  /// transferring → disconnecting → disconnected.
  func testStateMachine_happyPathLifecycle() {
    var state: DeviceState = .disconnected
    XCTAssertTrue(state.isDisconnected)

    state = .connecting
    XCTAssertFalse(state.isDisconnected)
    XCTAssertFalse(state.isTransferring)

    state = .connected
    XCTAssertFalse(state.isDisconnected)
    XCTAssertFalse(state.isTransferring)

    state = .transferring
    XCTAssertTrue(state.isTransferring)
    XCTAssertFalse(state.isDisconnected)

    // Back to connected after transfer completes
    state = .connected
    XCTAssertFalse(state.isTransferring)

    state = .disconnecting
    XCTAssertFalse(state.isDisconnected)

    state = .disconnected
    XCTAssertTrue(state.isDisconnected)
  }

  /// Invalid transitions that go from disconnected straight to transferring should
  /// still be representable (the enum is pure value type) but the flags reflect
  /// the current case, not the previous one.
  func testStateMachine_invalidTransitionFlags() {
    var state: DeviceState = .disconnected
    // Jump directly to transferring (logically invalid but structurally allowed)
    state = .transferring
    XCTAssertTrue(state.isTransferring)
    XCTAssertFalse(state.isDisconnected)
  }

  /// Error states preserve the associated MTPError variant.
  func testStateMachine_errorStatesPreserveAssociatedError() {
    let timeout = DeviceState.error(.timeout)
    let busy = DeviceState.error(.busy)
    let protocol2003 = DeviceState.error(.protocolError(code: 0x2003, message: "SessionNotOpen"))

    XCTAssertNotEqual(timeout, busy)
    XCTAssertNotEqual(timeout, protocol2003)
    XCTAssertNotEqual(busy, protocol2003)

    // Same error → equal
    XCTAssertEqual(timeout, DeviceState.error(.timeout))
  }

  /// Recovering from error → connecting → connected is valid.
  func testStateMachine_errorRecoveryPath() {
    var state: DeviceState = .connected
    state = .error(.timeout)
    XCTAssertFalse(state.isDisconnected)
    XCTAssertFalse(state.isTransferring)

    state = .connecting
    state = .connected
    XCTAssertEqual(state, .connected)
  }

  /// Rapid connect/disconnect cycles preserve final state.
  func testStateMachine_rapidCycles() {
    var state: DeviceState = .disconnected
    for _ in 0..<50 {
      state = .connecting
      state = .connected
      state = .transferring
      state = .connected
      state = .disconnecting
      state = .disconnected
    }
    XCTAssertTrue(state.isDisconnected)
  }

  // MARK: - Session Management via VirtualMTPDevice

  /// openSession → storages → list → closeSession lifecycle using VirtualMTPDevice.
  func testSessionLifecycle_virtualDevice() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    // Open session
    try await device.openIfNeeded()

    // Verify device info
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertNotNil(info.serialNumber)

    // Enumerate storages
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Pixel 7 config must have at least one storage")
    let storage = storages[0]
    XCTAssertEqual(storage.id.raw, 0x0001_0001)
    XCTAssertGreaterThan(storage.capacityBytes, 0)

    // Close session
    try await device.devClose()

    // Operations recorded
    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "openIfNeeded" }))
    XCTAssertTrue(ops.contains(where: { $0.operation == "storages" }))
    XCTAssertTrue(ops.contains(where: { $0.operation == "devClose" }))
  }

  // MARK: - GetDeviceInfo Response Parsing

  /// Verify that the virtual device info includes expected operations and events.
  func testGetDeviceInfo_operationsAndEvents() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let info = try await device.info
    // Pixel 7 config supports GetPartialObject (0x101B)
    XCTAssertTrue(info.operationsSupported.contains(PTPOp.getPartialObject.rawValue))
    // Pixel 7 config supports events
    XCTAssertFalse(info.eventsSupported.isEmpty)
    XCTAssertTrue(info.eventsSupported.contains(0x4002))  // ObjectAdded
    XCTAssertTrue(info.eventsSupported.contains(0x4003))  // ObjectRemoved
  }

  /// Samsung Galaxy config advertises GetObjectPropList (0x9805).
  func testGetDeviceInfo_samsungSupportsGetObjectPropList() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    let info = try await device.info
    XCTAssertTrue(
      info.operationsSupported.contains(MTPOp.getObjectPropList.rawValue),
      "Samsung Galaxy config should advertise 0x9805")
  }

  // MARK: - GetStorageIDs and GetStorageInfo

  /// Pixel 7 has exactly one storage; verify its metadata.
  func testGetStorageIDs_singleStorage() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Internal shared storage")
    XCTAssertFalse(storages[0].isReadOnly)
  }

  /// A device with multiple storages returns all of them.
  func testGetStorageIDs_multipleStorages() async throws {
    let extraStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 32 * 1024 * 1024 * 1024,
      freeBytes: 16 * 1024 * 1024 * 1024)
    let config = VirtualDeviceConfig.pixel7.withStorage(extraStorage)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    let descriptions = Set(storages.map(\.description))
    XCTAssertTrue(descriptions.contains("Internal shared storage"))
    XCTAssertTrue(descriptions.contains("SD Card"))
  }

  /// Empty device still returns its one empty storage.
  func testGetStorageIDs_emptyDevice() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Internal storage")
  }

  // MARK: - GetObjectHandles

  /// Root listing of pixel7 returns DCIM folder.
  func testGetObjectHandles_rootListing() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    var allObjects: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storage) {
      allObjects.append(contentsOf: batch)
    }
    XCTAssertEqual(allObjects.count, 1, "Root should have only DCIM folder")
    XCTAssertEqual(allObjects[0].name, "DCIM")
  }

  /// DCIM folder contains Camera subfolder.
  func testGetObjectHandles_subfolder() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    // DCIM is handle 1
    var children: [MTPObjectInfo] = []
    for try await batch in device.list(parent: 1, in: storage) {
      children.append(contentsOf: batch)
    }
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0].name, "Camera")
  }

  /// Camera folder contains the sample photo.
  func testGetObjectHandles_fileInSubfolder() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    // Camera is handle 2
    var files: [MTPObjectInfo] = []
    for try await batch in device.list(parent: 2, in: storage) {
      files.append(contentsOf: batch)
    }
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(files[0].name, "IMG_20250101_120000.jpg")
    XCTAssertEqual(files[0].sizeBytes, 4_500_000)
  }

  /// Listing children of a non-existent parent returns empty.
  func testGetObjectHandles_nonExistentParent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    var results: [MTPObjectInfo] = []
    for try await batch in device.list(parent: 9999, in: storage) {
      results.append(contentsOf: batch)
    }
    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - PropList Parsing

  /// parsePropListDataset correctly decodes a multi-object dataset.
  func testParsePropListDataset_multipleObjects() async throws {
    let actor = makeActor()
    let data = buildPropListDataset(objects: [
      PropListEntry(handle: 1, storageID: 0x00010001, parent: 0, name: "alpha.txt", size: 100),
      PropListEntry(handle: 2, storageID: 0x00010001, parent: 0, name: "beta.jpg", size: 2048),
      PropListEntry(handle: 3, storageID: 0x00010001, parent: 1, name: "gamma.png", size: 4096),
    ])

    let infos = try actor.parsePropListDataset(data)
    XCTAssertEqual(infos.count, 3)

    let byHandle = Dictionary(uniqueKeysWithValues: infos.map { ($0.handle, $0) })
    XCTAssertEqual(byHandle[1]?.name, "alpha.txt")
    XCTAssertEqual(byHandle[1]?.sizeBytes, 100)
    XCTAssertEqual(byHandle[2]?.name, "beta.jpg")
    XCTAssertEqual(byHandle[2]?.sizeBytes, 2048)
    XCTAssertEqual(byHandle[3]?.name, "gamma.png")
    XCTAssertEqual(byHandle[3]?.parent, 1)
  }

  /// Empty dataset (count = 0) returns empty array without error.
  func testParsePropListDataset_emptyDataset() async throws {
    let actor = makeActor()
    var data = Data()
    appendU32(&data, 0)  // count = 0
    let infos = try actor.parsePropListDataset(data)
    XCTAssertTrue(infos.isEmpty)
  }

  /// Single-object dataset with date modified.
  func testParsePropListDataset_dateModified() async throws {
    let actor = makeActor()
    let data = buildPropListDataset(objects: [
      PropListEntry(
        handle: 10, storageID: 0x00010001, parent: 0, name: "dated.txt",
        size: 512, dateModified: "20250601T150000")
    ])
    let infos = try actor.parsePropListDataset(data)
    XCTAssertEqual(infos.count, 1)
    XCTAssertNotNil(infos[0].modified)
  }

  /// Prop list with large object sizes (> 4 GB via uint64).
  func testParsePropListDataset_largeObjectSize() async throws {
    let actor = makeActor()
    let data = buildPropListDataset(objects: [
      PropListEntry(
        handle: 50, storageID: 0x00010001, parent: 0, name: "bigfile.iso",
        size: 8_000_000_000)
    ])
    let infos = try actor.parsePropListDataset(data)
    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos[0].sizeBytes, 8_000_000_000)
  }

  /// Root parent (0xFFFFFFFF) is normalised to nil.
  func testParsePropListDataset_rootParentNormalisedToNil() async throws {
    let actor = makeActor()
    let data = buildPropListDataset(objects: [
      PropListEntry(
        handle: 7, storageID: 0x00010001, parent: 0xFFFFFFFF, name: "root-child.txt", size: 10)
    ])
    let infos = try actor.parsePropListDataset(data)
    XCTAssertEqual(infos.count, 1)
    XCTAssertNil(infos[0].parent, "0xFFFFFFFF parent should normalise to nil")
  }

  // MARK: - GetObjectPropValue via VirtualMTPLink

  /// VirtualMTPLink returns correct objectFileName property.
  func testGetObjectPropValue_fileName() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let data = try await link.getObjectPropValue(
      handle: 3, property: MTPObjectPropCode.objectFileName)
    // PTPString encoded — at minimum should contain the filename bytes
    XCTAssertGreaterThan(data.count, 0)
  }

  /// VirtualMTPLink returns correct objectSize property.
  func testGetObjectPropValue_objectSize() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let data = try await link.getObjectPropValue(
      handle: 3, property: MTPObjectPropCode.objectSize)
    XCTAssertEqual(data.count, 8)  // UInt64
  }

  /// VirtualMTPLink returns correct storageID property.
  func testGetObjectPropValue_storageID() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let data = try await link.getObjectPropValue(
      handle: 3, property: MTPObjectPropCode.storageID)
    XCTAssertEqual(data.count, 4)  // UInt32
  }

  /// Unsupported property code throws notSupported.
  func testGetObjectPropValue_unsupportedProperty() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    do {
      _ = try await link.getObjectPropValue(handle: 3, property: 0xFFFF)
      XCTFail("Expected MTPError.notSupported")
    } catch let error as MTPError {
      if case .notSupported = error { /* expected */
      } else {
        XCTFail("Expected notSupported, got \(error)")
      }
    }
  }

  /// getObjectPropsSupported returns baseline property codes.
  func testGetObjectPropsSupported_baselineProps() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let props = try await link.getObjectPropsSupported(format: 0x3000)
    XCTAssertTrue(props.contains(MTPObjectPropCode.objectFileName))
    XCTAssertTrue(props.contains(MTPObjectPropCode.objectSize))
    XCTAssertTrue(props.contains(MTPObjectPropCode.storageID))
    XCTAssertTrue(props.contains(MTPObjectPropCode.parentObject))
    XCTAssertTrue(props.contains(MTPObjectPropCode.dateCreated))
    XCTAssertTrue(props.contains(MTPObjectPropCode.dateModified))
  }

  // MARK: - Reconciliation

  /// reconcilePartialWrites deletes a partial object and fails the journal entry.
  func testReconcilePartials_deletesPartialObject() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let journal = StubTransferJournal()

    // Add a partial write record whose remote handle exists on the device
    // but actual size < expected
    let partialHandle: MTPObjectHandle = 3  // IMG — sizeBytes = 4_500_000
    journal.resumables = [
      TransferRecord(
        id: "r1", deviceId: config.deviceId, kind: "write",
        handle: nil, parentHandle: 2, name: "partial.jpg",
        totalBytes: 10_000_000,  // expected
        committedBytes: 2_000_000,
        supportsPartial: false,
        localTempURL: URL(fileURLWithPath: "/tmp/partial.part"),
        finalURL: nil, state: "active", updatedAt: Date(),
        remoteHandle: partialHandle)
    ]

    await reconcilePartialWrites(journal: journal, device: device)

    // The partial object should have been deleted
    let ops = await device.operations
    let deleteOps = ops.filter { $0.operation == "delete" }
    XCTAssertEqual(deleteOps.count, 1)

    // The journal entry should have been failed
    XCTAssertEqual(journal.failedIDs.count, 1)
    XCTAssertEqual(journal.failedIDs.first, "r1")
  }

  /// reconcilePartialWrites skips records with no remoteHandle.
  func testReconcilePartials_skipsNoRemoteHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let journal = StubTransferJournal()
    journal.resumables = [
      TransferRecord(
        id: "r2", deviceId: VirtualDeviceConfig.pixel7.deviceId, kind: "write",
        handle: nil, parentHandle: nil, name: "no-remote.jpg",
        totalBytes: 5000, committedBytes: 0,
        supportsPartial: false,
        localTempURL: URL(fileURLWithPath: "/tmp/no-remote.part"),
        finalURL: nil, state: "active", updatedAt: Date(),
        remoteHandle: nil)
    ]

    await reconcilePartialWrites(journal: journal, device: device)

    let ops = await device.operations
    let deleteOps = ops.filter { $0.operation == "delete" }
    XCTAssertTrue(deleteOps.isEmpty, "No delete should occur for records without remoteHandle")
  }

  /// reconcilePartialWrites leaves complete objects untouched.
  func testReconcilePartials_leavesCompleteObject() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let journal = StubTransferJournal()

    // handle 3 has sizeBytes 4_500_000 — mark expected as same
    journal.resumables = [
      TransferRecord(
        id: "r3", deviceId: VirtualDeviceConfig.pixel7.deviceId, kind: "write",
        handle: nil, parentHandle: 2, name: "complete.jpg",
        totalBytes: 4_500_000, committedBytes: 4_500_000,
        supportsPartial: false,
        localTempURL: URL(fileURLWithPath: "/tmp/complete.part"),
        finalURL: nil, state: "active", updatedAt: Date(),
        remoteHandle: 3)
    ]

    await reconcilePartialWrites(journal: journal, device: device)

    let ops = await device.operations
    let deleteOps = ops.filter { $0.operation == "delete" }
    XCTAssertTrue(deleteOps.isEmpty, "Complete objects should not be deleted")
    XCTAssertTrue(journal.failedIDs.isEmpty, "Journal should not be failed for complete objects")
  }

  // MARK: - Transfer Flow

  /// VirtualMTPDevice write creates the expected object with correct metadata.
  func testTransferFlow_writeCreatesObject() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wave32-test.txt")
    let testData = Data("hello wave32".utf8)
    try testData.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let progress = try await device.write(
      parent: 1, name: "wave32-test.txt",
      size: UInt64(testData.count), from: tempURL)

    XCTAssertEqual(progress.completedUnitCount, Int64(testData.count))
    XCTAssertEqual(progress.totalUnitCount, Int64(testData.count))

    // Verify the object was created in the device
    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "write" }))
  }

  /// VirtualMTPDevice read downloads expected data.
  func testTransferFlow_readDownloadsData() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "wave32-read-\(UUID().uuidString).jpg")
    defer { try? FileManager.default.removeItem(at: destURL) }

    // Handle 3 = IMG_20250101_120000.jpg (4.5 MB of 0xFF)
    let progress = try await device.read(handle: 3, range: nil, to: destURL)
    XCTAssertEqual(progress.completedUnitCount, 4_500_000)

    let downloaded = try Data(contentsOf: destURL)
    XCTAssertEqual(downloaded.count, 4_500_000)
  }

  /// Reading a non-existent handle throws objectNotFound.
  func testTransferFlow_readNonExistentThrows() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing.bin")
    do {
      _ = try await device.read(handle: 9999, range: nil, to: destURL)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - Concurrent Operation Serialisation (withTransaction)

  /// Multiple concurrent callers are serialised by withTransaction.
  func testWithTransaction_serialisesOperations() async throws {
    let actor = makeActor()
    let orderBox = OrderBox()

    // Launch three concurrent transactions
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<3 {
        group.addTask {
          try? await actor.withTransaction {
            await orderBox.append(i)
            // Small sleep to ensure interleaving would be visible without serialisation
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            await orderBox.append(i + 100)
          }
        }
      }
    }

    let order = await orderBox.values
    // Each transaction's pair (i, i+100) must be adjacent — never interleaved
    XCTAssertEqual(order.count, 6)
    var idx = 0
    while idx < order.count {
      let start = order[idx]
      let end = order[idx + 1]
      XCTAssertEqual(end, start + 100, "Transaction pair should be adjacent: \(start) → \(end)")
      idx += 2
    }
  }

  /// Single transaction completes normally.
  func testWithTransaction_singleTransaction() async throws {
    let actor = makeActor()
    let result = try await actor.withTransaction { 42 }
    XCTAssertEqual(result, 42)
  }

  /// Transaction that throws still releases the lock.
  func testWithTransaction_throwingReleasesLock() async throws {
    let actor = makeActor()
    do {
      _ = try await actor.withTransaction {
        throw MTPError.timeout
      }
      XCTFail("Should have thrown")
    } catch {
      // expected
    }
    // A subsequent transaction should succeed (lock was released)
    let result = try await actor.withTransaction { "recovered" }
    XCTAssertEqual(result, "recovered")
  }

  // MARK: - MTPDeviceActor via VirtualMTPLink

  /// MTPDeviceActor constructed with VirtualMTPLink can retrieve device info.
  func testDeviceActor_getDeviceInfoViaLink() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
  }

  /// MTPDeviceActor link can get storage IDs.
  func testDeviceActor_getStorageIDsViaLink() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    try await link.openSession(id: 1)
    let ids = try await link.getStorageIDs()
    XCTAssertEqual(ids.count, 1)
    XCTAssertEqual(ids[0].raw, 0x0001_0001)
  }

  /// MTPDeviceActor link can get object handles with filters.
  func testDeviceActor_getObjectHandlesViaLink() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    // Root: only DCIM
    let rootHandles = try await link.getObjectHandles(storage: storage, parent: nil)
    XCTAssertEqual(rootHandles.count, 1)
    XCTAssertEqual(rootHandles[0], 1)  // DCIM handle

    // DCIM children: Camera
    let dcimHandles = try await link.getObjectHandles(storage: storage, parent: 1)
    XCTAssertEqual(dcimHandles.count, 1)

    // Camera children: photo
    let cameraHandles = try await link.getObjectHandles(storage: storage, parent: 2)
    XCTAssertEqual(cameraHandles.count, 1)
    XCTAssertEqual(cameraHandles[0], 3)
  }

  /// StorageInfo from link matches config.
  func testDeviceActor_getStorageInfoViaLink() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    let info = try await link.getStorageInfo(id: MTPStorageID(raw: 0x0001_0001))
    XCTAssertEqual(info.description, "Internal shared storage")
    XCTAssertEqual(info.capacityBytes, 128 * 1024 * 1024 * 1024)
    XCTAssertFalse(info.isReadOnly)
  }

  /// Requesting storage info for unknown storage throws.
  func testDeviceActor_getStorageInfoUnknownThrows() async throws {
    let link = VirtualMTPLink(config: .pixel7)
    do {
      _ = try await link.getStorageInfo(id: MTPStorageID(raw: 0xDEAD))
      XCTFail("Expected error for unknown storage")
    } catch {
      // Expected: TransportError.io
    }
  }

  // MARK: - Fault Injection: openSession timeout

  /// When openSession faults with timeout, VirtualMTPLink throws.
  func testFaultInjection_openSessionTimeout() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .openSession)])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected timeout error")
    } catch let error as TransportError {
      XCTAssertEqual(error, .timeout)
    }
  }

  /// After a transient fault, the link succeeds on retry.
  func testFaultInjection_retryAfterTransientFault() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageIDs)])
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: schedule)

    // First call faults
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout on first call")
    } catch {
      // expected
    }

    // Second call succeeds (fault was repeatCount: 1)
    let ids = try await link.getStorageIDs()
    XCTAssertEqual(ids.count, 1)
  }

  // MARK: - Delete and Rename

  /// Delete an object via VirtualMTPDevice.
  func testDelete_removesObject() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    // Delete the photo (handle 3)
    try await device.delete(3, recursive: false)

    // Verify it's gone
    do {
      _ = try await device.getInfo(handle: 3)
      XCTFail("Object should have been deleted")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  /// Delete non-existent handle throws objectNotFound.
  func testDelete_nonExistentThrows() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    do {
      try await device.delete(9999, recursive: false)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  /// Rename changes the object's name.
  func testRename_changesName() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.rename(3, to: "renamed.jpg")
    let info = try await device.getInfo(handle: 3)
    XCTAssertEqual(info.name, "renamed.jpg")
  }

  // MARK: - CreateFolder

  /// createFolder creates a new folder object.
  func testCreateFolder_createsNewObject() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storage = MTPStorageID(raw: 0x0001_0001)

    let handle = try await device.createFolder(parent: 1, name: "NewFolder", storage: storage)
    XCTAssertGreaterThan(handle, 3)  // handles 1,2,3 taken

    let info = try await device.getInfo(handle: handle)
    XCTAssertEqual(info.name, "NewFolder")
  }

  // MARK: - MTPEvent Parsing

  /// MTPEvent.fromRaw correctly parses ObjectAdded event.
  func testMTPEvent_objectAdded() {
    var data = Data()
    appendU32(&data, 16)  // length
    appendU16(&data, 4)  // type = event
    appendU16(&data, 0x4002)  // ObjectAdded
    appendU32(&data, 1)  // txid
    appendU32(&data, 42)  // handle

    let event = MTPEvent.fromRaw(data)
    if case .objectAdded(let handle) = event {
      XCTAssertEqual(handle, 42)
    } else {
      XCTFail("Expected objectAdded, got \(String(describing: event))")
    }
  }

  /// MTPEvent.fromRaw correctly parses ObjectRemoved event.
  func testMTPEvent_objectRemoved() {
    var data = Data()
    appendU32(&data, 16)
    appendU16(&data, 4)
    appendU16(&data, 0x4003)  // ObjectRemoved
    appendU32(&data, 1)
    appendU32(&data, 99)

    let event = MTPEvent.fromRaw(data)
    if case .objectRemoved(let handle) = event {
      XCTAssertEqual(handle, 99)
    } else {
      XCTFail("Expected objectRemoved")
    }
  }

  /// MTPEvent.fromRaw returns unknown for unrecognised codes.
  func testMTPEvent_unknownCode() {
    var data = Data()
    appendU32(&data, 16)
    appendU16(&data, 4)
    appendU16(&data, 0xFFFF)  // Unknown
    appendU32(&data, 1)
    appendU32(&data, 7)

    let event = MTPEvent.fromRaw(data)
    if case .unknown(let code, let params) = event {
      XCTAssertEqual(code, 0xFFFF)
      XCTAssertEqual(params, [7])
    } else {
      XCTFail("Expected unknown event")
    }
  }

  /// MTPEvent.fromRaw returns nil for too-short data.
  func testMTPEvent_tooShortReturnsNil() {
    let data = Data([0x00, 0x01, 0x02])
    XCTAssertNil(MTPEvent.fromRaw(data))
  }

  // MARK: - Helpers

  private func makeActor() -> MTPDeviceActor {
    let transport = Wave32InjectedTransport(link: VirtualMTPLink(config: .pixel7))
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "wave32-test"), manufacturer: "Test", model: "Wave32",
      vendorID: 0x0000, productID: 0x0000)
    return MTPDeviceActor(id: summary.id, summary: summary, transport: transport)
  }

  private func appendU16(_ data: inout Data, _ v: UInt16) {
    withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
  }

  private func appendU32(_ data: inout Data, _ v: UInt32) {
    withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
  }

  private func appendU64(_ data: inout Data, _ v: UInt64) {
    withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
  }

  private func appendStr(_ data: inout Data, _ s: String) {
    data.append(PTPString.encode(s))
  }

  private struct PropListEntry {
    let handle: UInt32
    let storageID: UInt32
    let parent: UInt32
    let name: String
    let size: UInt64
    var dateModified: String? = nil
  }

  private func buildPropListDataset(objects: [PropListEntry]) -> Data {
    let tuplesPerObject = 4
    let extraTuples = objects.filter { $0.dateModified != nil }.count
    let totalTuples = UInt32(objects.count * tuplesPerObject + extraTuples)

    var data = Data()
    appendU32(&data, totalTuples)

    for obj in objects {
      // storageID
      appendU32(&data, obj.handle)
      appendU16(&data, 0xDC01)  // storageID prop
      appendU16(&data, 0x0006)  // UINT32
      appendU32(&data, obj.storageID)
      // objectSize
      appendU32(&data, obj.handle)
      appendU16(&data, 0xDC04)  // objectSize prop
      appendU16(&data, 0x0008)  // UINT64
      appendU64(&data, obj.size)
      // objectFileName
      appendU32(&data, obj.handle)
      appendU16(&data, 0xDC07)  // objectFileName prop
      appendU16(&data, 0xFFFF)  // STRING
      appendStr(&data, obj.name)
      // parentObject
      appendU32(&data, obj.handle)
      appendU16(&data, 0xDC0B)  // parentObject prop
      appendU16(&data, 0x0006)  // UINT32
      appendU32(&data, obj.parent)
      // dateModified (optional)
      if let dateStr = obj.dateModified {
        appendU32(&data, obj.handle)
        appendU16(&data, 0xDC09)  // dateModified prop
        appendU16(&data, 0xFFFF)  // STRING
        appendStr(&data, dateStr)
      }
    }
    return data
  }
}

// MARK: - Test Helpers

/// Thread-safe ordered value collector for concurrency tests.
private actor OrderBox {
  var values: [Int] = []
  func append(_ v: Int) { values.append(v) }
}

/// Minimal MTPTransport that returns a pre-built MTPLink.
private final class Wave32InjectedTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}

/// Stub TransferJournal for reconciliation tests.
private final class StubTransferJournal: TransferJournal, @unchecked Sendable {
  var resumables: [TransferRecord] = []
  var failedIDs: [String] = []
  private let lock = NSLock()

  func beginRead(
    device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?,
    supportsPartial: Bool, tempURL: URL, finalURL: URL?,
    etag: (size: UInt64?, mtime: Date?)
  ) async throws -> String { UUID().uuidString }

  func beginWrite(
    device: MTPDeviceID, parent: UInt32, name: String, size: UInt64,
    supportsPartial: Bool, tempURL: URL, sourceURL: URL?
  ) async throws -> String { UUID().uuidString }

  func updateProgress(id: String, committed: UInt64) async throws {}

  func fail(id: String, error: Error) async throws {
    lock.withLock { failedIDs.append(id) }
  }

  func complete(id: String) async throws {}

  func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] {
    return resumables
  }

  func clearStaleTemps(olderThan: TimeInterval) async throws {}
}
