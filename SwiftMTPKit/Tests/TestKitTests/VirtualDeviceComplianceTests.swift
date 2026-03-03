// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

// MARK: - VirtualMTPDevice MTP Protocol Compliance

final class VirtualDeviceComplianceTests: XCTestCase {

  // MARK: - Response Codes & Transaction IDs

  func testDeviceInfoReturnsCorrectManufacturerAndModel() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertEqual(info.version, "1.0")
    XCTAssertEqual(info.serialNumber, "VIRTUAL001")
  }

  func testDeviceInfoMatchesSummary() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let info = try await device.info
    XCTAssertEqual(info.manufacturer, config.summary.manufacturer)
    XCTAssertEqual(info.model, config.summary.model)
  }

  func testOperationsSupported() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.info
    XCTAssertTrue(info.operationsSupported.contains(0x1001), "GetDeviceInfo should be supported")
    XCTAssertTrue(info.operationsSupported.contains(0x1007), "GetObjectHandles should be supported")
  }

  func testEventsSupported() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.info
    XCTAssertTrue(info.eventsSupported.contains(0x4002), "ObjectAdded event should be supported")
    XCTAssertTrue(info.eventsSupported.contains(0x4003), "ObjectRemoved event should be supported")
  }

  // MARK: - Storage Enumeration Accuracy

  func testStorageEnumerationReturnsAllConfiguredStorages() async throws {
    let base = VirtualDeviceConfig.emptyDevice
    let extra = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card",
      capacityBytes: 256 * 1024 * 1024 * 1024, freeBytes: 200 * 1024 * 1024 * 1024)
    let config = base.withStorage(extra)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    let descriptions = Set(storages.map(\.description))
    XCTAssertTrue(descriptions.contains("Internal storage"))
    XCTAssertTrue(descriptions.contains("SD Card"))
  }

  func testStorageCapacityAndFreeSpace() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = try XCTUnwrap(storages.first)
    XCTAssertEqual(storage.capacityBytes, 128 * 1024 * 1024 * 1024)
    XCTAssertEqual(storage.freeBytes, 64 * 1024 * 1024 * 1024)
    XCTAssertFalse(storage.isReadOnly)
  }

  func testStorageOperationIsRecorded() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    _ = try await device.storages()
    let ops = await device.operations
    XCTAssertEqual(ops.filter { $0.operation == "storages" }.count, 1)
  }

  // MARK: - Object Handle Allocation & Deallocation

  func testHandleAllocationIsMonotonicallyIncreasing() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    var handles: [MTPObjectHandle] = []
    for i in 0..<5 {
      let h = try await device.createFolder(parent: nil, name: "dir\(i)", storage: sid)
      handles.append(h)
    }
    for i in 1..<handles.count {
      XCTAssertGreaterThan(handles[i], handles[i - 1], "Handles should increase monotonically")
    }
  }

  func testDeletedHandleIsNoLongerAccessible() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let handle = try await device.createFolder(parent: nil, name: "ToDelete", storage: sid)
    try await device.delete(handle, recursive: false)

    do {
      _ = try await device.getInfo(handle: handle)
      XCTFail("Expected objectNotFound after deletion")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testAddObjectAndRemoveObjectAtRuntime() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 500, storage: sid, parent: nil, name: "injected.txt",
      data: Data("injected".utf8))
    await device.addObject(obj)

    let info = try await device.getInfo(handle: 500)
    XCTAssertEqual(info.name, "injected.txt")

    await device.removeObject(handle: 500)
    do {
      _ = try await device.getInfo(handle: 500)
      XCTFail("Expected objectNotFound after removal")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testAddObjectUpdatesNextHandle() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    await device.addObject(
      VirtualObjectConfig(
        handle: 1000, storage: sid, parent: nil, name: "high.txt"))

    let newHandle = try await device.createFolder(parent: nil, name: "after", storage: sid)
    XCTAssertGreaterThan(newHandle, 1000, "New handle should be > manually added handle")
  }

  // MARK: - File Content Round-Trip

  func testWriteReadVerifyBinaryContent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    var content = Data(count: 2048)
    for i in 0..<content.count { content[i] = UInt8(i % 256) }

    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "binary.bin", content: content)
    _ = try await device.write(
      parent: nil, name: "binary.bin", size: UInt64(content.count), from: src)

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      items.append(contentsOf: batch)
    }
    let file = try XCTUnwrap(items.first { $0.name == "binary.bin" })
    XCTAssertEqual(file.sizeBytes, UInt64(content.count))

    let dest = tempDir.appendingPathComponent("downloaded.bin")
    _ = try await device.read(handle: file.handle, range: nil, to: dest)
    XCTAssertEqual(try Data(contentsOf: dest), content)
  }

  func testWriteToNonRootParent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let folder = try await device.createFolder(parent: nil, name: "SubDir", storage: sid)
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "child.txt", content: Data("child".utf8))
    _ = try await device.write(parent: folder, name: "child.txt", size: 5, from: src)

    var children: [MTPObjectInfo] = []
    for try await batch in device.list(parent: folder, in: sid) {
      children.append(contentsOf: batch)
    }
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0].name, "child.txt")
  }

  // MARK: - Event Generation

  func testObjectAddedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive objectAdded event")
    let task = Task {
      for await event in await device.events {
        if case .objectAdded(let handle) = event, handle == 42 {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.objectAdded(42))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testObjectRemovedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive objectRemoved event")
    let task = Task {
      for await event in await device.events {
        if case .objectRemoved(let handle) = event, handle == 99 {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.objectRemoved(99))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testStorageInfoChangedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive storageInfoChanged event")
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let task = Task {
      for await event in await device.events {
        if case .storageInfoChanged(let sid) = event, sid.raw == storageId.raw {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.storageInfoChanged(storageId))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testMultipleEventsInSequence() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "Receive 3 events")
    expectation.expectedFulfillmentCount = 3
    let task = Task {
      var count = 0
      for await _ in await device.events {
        count += 1
        expectation.fulfill()
        if count >= 3 { break }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.objectAdded(1))
    await device.injectEvent(.objectRemoved(2))
    await device.injectEvent(.deviceInfoChanged)
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  // MARK: - Concurrent Access Safety

  func testConcurrentFolderCreation() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let handles = try await withThrowingTaskGroup(of: MTPObjectHandle.self) { group in
      for i in 0..<20 {
        group.addTask {
          try await device.createFolder(parent: nil, name: "concurrent\(i)", storage: sid)
        }
      }
      var result: [MTPObjectHandle] = []
      for try await handle in group {
        result.append(handle)
      }
      return result
    }

    XCTAssertEqual(Set(handles).count, 20, "All 20 handles should be unique")
  }

  func testConcurrentReadsDoNotCorrupt() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    // Handle 3 is the sample photo in pixel7 preset
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let dest = tempDir.appendingPathComponent("read\(i).jpg")
          _ = try await device.read(handle: 3, range: nil, to: dest)
          let data = try Data(contentsOf: dest)
          XCTAssertEqual(data.count, 4_500_000)
        }
      }
      try await group.waitForAll()
    }
  }

  // MARK: - Operation Log & Clear

  func testClearOperationsResetsLog() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    _ = try await device.storages()
    let opsBefore = await device.operations
    XCTAssertFalse(opsBefore.isEmpty)

    await device.clearOperations()
    let opsAfter = await device.operations
    XCTAssertTrue(opsAfter.isEmpty)
  }

  func testOpenIfNeededRecordsOperation() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.openIfNeeded()
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "openIfNeeded" })
  }

  func testDevCloseRecordsAndFinishesEvents() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.devClose()
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "devClose" })
  }

  // MARK: - Dev SPI Methods

  func testDevGetDeviceInfoUncached() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Google")
    let ops = await device.operations
    XCTAssertTrue(ops.contains { $0.operation == "devGetDeviceInfoUncached" })
  }

  func testDevGetStorageIDsUncached() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let ids = try await device.devGetStorageIDsUncached()
    XCTAssertFalse(ids.isEmpty)
    XCTAssertEqual(ids[0].raw, 0x0001_0001)
  }

  func testDevGetRootHandlesUncached() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let handles = try await device.devGetRootHandlesUncached(
      storage: MTPStorageID(raw: 0x0001_0001))
    XCTAssertTrue(handles.contains(1), "DCIM folder handle should be in root handles")
  }

  func testDevGetObjectInfoUncachedThrowsForMissingHandle() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    do {
      _ = try await device.devGetObjectInfoUncached(handle: 9999)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }
}

// MARK: - FaultInjectingLink Specific Fault Types & Schedule Accuracy

final class FaultInjectingLinkComplianceTests: XCTestCase {

  private func makeLink(
    config: VirtualDeviceConfig = .emptyDevice,
    schedule: FaultSchedule = FaultSchedule()
  ) -> FaultInjectingLink {
    FaultInjectingLink(wrapping: VirtualMTPLink(config: config), schedule: schedule)
  }

  // MARK: - Specific Fault Types

  func testTimeoutFaultOnOpenUSB() async throws {
    let link = makeLink(schedule: FaultSchedule([.timeoutOnce(on: .openUSB)]))
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    // Second call succeeds
    try await link.openUSBIfNeeded()
  }

  func testBusyFaultOnOpenSession() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .busy, repeatCount: 2)
    ])
    let link = makeLink(schedule: schedule)

    for _ in 0..<2 {
      do {
        try await link.openSession(id: 1)
        XCTFail("Expected busy fault")
      } catch {
        XCTAssertTrue("\(error)".contains("busy"))
      }
    }
    try await link.openSession(id: 1)
  }

  func testAccessDeniedFaultOnMoveObject() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    let sid = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(handle: 10, storage: sid, parent: nil, name: "f.txt"))
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.moveObject), error: .accessDenied)
    ])
    let link = FaultInjectingLink(wrapping: VirtualMTPLink(config: config), schedule: schedule)

    do {
      try await link.moveObject(handle: 10, to: sid, parent: nil)
      XCTFail("Expected accessDenied")
    } catch {
      XCTAssertTrue("\(error)".lowercased().contains("access"))
    }
  }

  func testIOFaultOnExecuteCommand() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .io("USB pipe broken"))
    ])
    let link = makeLink(schedule: schedule)

    do {
      _ = try await link.executeCommand(PTPContainer(type: 1, code: 0x1001, txid: 1))
      XCTFail("Expected IO fault")
    } catch {
      XCTAssertTrue("\(error)".contains("USB pipe broken"))
    }
  }

  func testDisconnectedFaultOnCloseSession() async throws {
    let link = makeLink(
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.closeSession), error: .disconnected)
      ]))

    do {
      try await link.closeSession()
      XCTFail("Expected disconnected fault")
    } catch {
      let desc = "\(error)".lowercased()
      XCTAssertTrue(desc.contains("no") || desc.contains("device"))
    }
  }

  // MARK: - Fault Schedule Accuracy (by call index)

  func testFaultFiresOnlyAtSpecificCallIndex() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(1), error: .timeout)
    ])
    let link = makeLink(schedule: schedule)

    // Call 0: getDeviceInfo (no fault)
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")

    // Call 1: getStorageIDs (fault fires)
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout at call index 1")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }

    // Call 2: getStorageIDs again (no fault)
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - Fault Statistics / Schedule State

  func testDynamicFaultAdditionDuringOperation() async throws {
    let schedule = FaultSchedule()
    let link = makeLink(schedule: schedule)

    // No faults initially — succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")

    // Add fault dynamically
    link.scheduleFault(.timeoutOnce(on: .getStorageIDs))

    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected dynamically scheduled timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }

    // Fault consumed — succeeds again
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testScheduleClearRemovesAllPendingFaults() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout, repeatCount: 0),
      ScheduledFault(trigger: .onOperation(.getStorageIDs), error: .busy, repeatCount: 0),
    ])
    let link = makeLink(schedule: schedule)

    // Verify faults are active
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected fault")
    } catch {}

    // Clear all
    schedule.clear()

    // Both should now succeed
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testFaultOnGetObjectInfosThroughLink() async throws {
    let link = makeLink(schedule: FaultSchedule([.timeoutOnce(on: .getObjectInfos)]))

    do {
      _ = try await link.getObjectInfos([1, 2, 3])
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
    // Second call succeeds (empty result for empty device is fine)
    let infos = try await link.getObjectInfos([])
    XCTAssertTrue(infos.isEmpty)
  }

  func testFaultOnExecuteStreamingCommand() async throws {
    let link = makeLink(
      schedule: FaultSchedule([
        .timeoutOnce(on: .executeStreamingCommand)
      ]))

    do {
      _ = try await link.executeStreamingCommand(
        PTPContainer(type: 1, code: 0x100C, txid: 1),
        dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue("\(error)".contains("timeout"))
    }
  }

  func testMultipleFaultTypesOnSameOperation() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .timeout),
      ScheduledFault(trigger: .onOperation(.getDeviceInfo), error: .busy),
    ])
    let link = makeLink(schedule: schedule)

    // First call: timeout
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout")
    } catch { XCTAssertTrue("\(error)".contains("timeout")) }

    // Second call: busy
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected busy")
    } catch { XCTAssertTrue("\(error)".contains("busy")) }

    // Third call: succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Virtual")
  }
}
