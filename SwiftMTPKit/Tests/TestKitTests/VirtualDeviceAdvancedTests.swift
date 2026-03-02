// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

// MARK: - Virtual Device All Storage Types

final class VirtualDeviceAllStorageTypesTests: XCTestCase {

  func testDeviceWithInternalAndSDCardStorages() async throws {
    let sdCard = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card",
      capacityBytes: 256 * 1024 * 1024 * 1024, freeBytes: 200 * 1024 * 1024 * 1024)
    let config = VirtualDeviceConfig.pixel7.withStorage(sdCard)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 2)
    XCTAssertTrue(storages.contains { $0.description == "Internal shared storage" })
    XCTAssertTrue(storages.contains { $0.description == "SD Card" })
  }

  func testDeviceWithReadOnlyStorage() async throws {
    let roStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0003_0001), description: "ROM",
      capacityBytes: 1024 * 1024, freeBytes: 0, isReadOnly: true)
    let config = VirtualDeviceConfig.emptyDevice.withStorage(roStorage)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    let rom = try XCTUnwrap(storages.first { $0.description == "ROM" })
    XCTAssertTrue(rom.isReadOnly)
    XCTAssertEqual(rom.freeBytes, 0)
  }

  func testDeviceWithThreeStorages() async throws {
    let sd = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card")
    let external = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0003_0001), description: "External USB")
    let config = VirtualDeviceConfig.pixel7.withStorage(sd).withStorage(external)
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 3)
  }

  func testCameraPresetHasMemoryCardStorage() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)
    XCTAssertEqual(storages[0].description, "Memory Card")
  }
}

// MARK: - Virtual Device Filesystem Operations

final class VirtualDeviceFilesystemTests: XCTestCase {

  func testCreateNestedFoldersAndFiles() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let photos = try await device.createFolder(parent: nil, name: "Photos", storage: sid)
    let vacation = try await device.createFolder(parent: photos, name: "Vacation", storage: sid)

    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "beach.jpg", content: Data(repeating: 0xAA, count: 512))
    _ = try await device.write(parent: vacation, name: "beach.jpg", size: 512, from: src)

    var children: [MTPObjectInfo] = []
    for try await batch in device.list(parent: vacation, in: sid) {
      children.append(contentsOf: batch)
    }
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0].name, "beach.jpg")
  }

  func testDeleteFolderRecursivelyRemovesChildren() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    let parent = try await device.createFolder(parent: nil, name: "Parent", storage: sid)
    let child = try await device.createFolder(parent: parent, name: "Child", storage: sid)
    let src = try TestUtilities.createTempFile(
      directory: tempDir, filename: "f.txt", content: Data("hello".utf8))
    _ = try await device.write(parent: child, name: "f.txt", size: 5, from: src)

    try await device.delete(parent, recursive: true)

    // Both child folder and file should be gone
    do {
      _ = try await device.getInfo(handle: child)
      XCTFail("Expected objectNotFound for child after recursive delete")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testRenamePreservesParentAndStorage() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let folder = try await device.createFolder(parent: nil, name: "OldName", storage: sid)
    try await device.rename(folder, to: "NewName")

    let info = try await device.getInfo(handle: folder)
    XCTAssertEqual(info.name, "NewName")
    XCTAssertEqual(info.storage.raw, sid.raw)
    XCTAssertNil(info.parent)
  }

  func testMoveChangesParent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let folderA = try await device.createFolder(parent: nil, name: "A", storage: sid)
    let folderB = try await device.createFolder(parent: nil, name: "B", storage: sid)
    let file = try await device.createFolder(parent: folderA, name: "file", storage: sid)

    try await device.move(file, to: folderB)

    let info = try await device.getInfo(handle: file)
    XCTAssertEqual(info.parent, folderB)
  }

  func testDeleteNonRecursiveOnFolderWithChildren() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let parent = try await device.createFolder(parent: nil, name: "Dir", storage: sid)
    _ = try await device.createFolder(parent: parent, name: "Sub", storage: sid)

    // Non-recursive delete only removes the parent, orphaning children
    try await device.delete(parent, recursive: false)
    do {
      _ = try await device.getInfo(handle: parent)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }
}

// MARK: - Virtual Device Concurrent Access

final class VirtualDeviceConcurrentAccessTests: XCTestCase {

  func testConcurrentWriteAndReadDoNotInterfere() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id
    let tempDir = try TestUtilities.createTempDirectory()
    defer { try? TestUtilities.cleanupTempDirectory(tempDir) }

    // Create files concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          let data = Data(repeating: UInt8(i), count: 128)
          let src = try TestUtilities.createTempFile(
            directory: tempDir, filename: "write\(i).bin", content: data)
          _ = try await device.write(
            parent: nil, name: "file\(i).bin", size: 128, from: src)
        }
      }
      try await group.waitForAll()
    }

    // Verify all files exist
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      items.append(contentsOf: batch)
    }
    XCTAssertEqual(items.count, 10)
  }

  func testConcurrentFolderCreationAndDeletion() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let handles = try await withThrowingTaskGroup(of: MTPObjectHandle.self) { group in
      for i in 0..<15 {
        group.addTask {
          try await device.createFolder(parent: nil, name: "dir\(i)", storage: sid)
        }
      }
      var result: [MTPObjectHandle] = []
      for try await h in group { result.append(h) }
      return result
    }

    // Delete half concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      for h in handles.prefix(7) {
        group.addTask { try await device.delete(h, recursive: false) }
      }
      try await group.waitForAll()
    }

    var remaining: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      remaining.append(contentsOf: batch)
    }
    XCTAssertEqual(remaining.count, 8)
  }

  func testConcurrentOperationRecording() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<20 {
        group.addTask {
          _ = try await device.createFolder(parent: nil, name: "op\(i)", storage: sid)
        }
      }
      try? await group.waitForAll()
    }

    let ops = await device.operations
    // 1 storages + 20 createFolder
    XCTAssertEqual(ops.count, 21)
  }
}

// MARK: - Virtual Device Storage Capacity Tracking

final class VirtualDeviceStorageCapacityTests: XCTestCase {

  func testStorageCapacityReflectsConfig() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Test",
      capacityBytes: 100_000, freeBytes: 50_000)
    let config = VirtualDeviceConfig.emptyDevice
    var modConfig = config
    modConfig.storages = [storage]
    let device = VirtualMTPDevice(config: modConfig)

    let storages = try await device.storages()
    XCTAssertEqual(storages[0].capacityBytes, 100_000)
    XCTAssertEqual(storages[0].freeBytes, 50_000)
  }

  func testZeroCapacityStorage() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Empty",
      capacityBytes: 0, freeBytes: 0)
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = [storage]
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages[0].capacityBytes, 0)
    XCTAssertEqual(storages[0].freeBytes, 0)
  }

  func testLargeCapacityStorage() async throws {
    let oneTerabyte: UInt64 = 1024 * 1024 * 1024 * 1024
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "1TB",
      capacityBytes: oneTerabyte, freeBytes: oneTerabyte / 2)
    var config = VirtualDeviceConfig.emptyDevice
    config.storages = [storage]
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages[0].capacityBytes, oneTerabyte)
  }
}

// MARK: - Virtual Device Custom Object Properties

final class VirtualDeviceObjectPropertiesTests: XCTestCase {

  func testObjectWithExplicitSizeBytes() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 100, storage: sid, parent: nil, name: "sized.dat",
      sizeBytes: 999, formatCode: 0x3000)
    await device.addObject(obj)

    let info = try await device.getInfo(handle: 100)
    XCTAssertEqual(info.sizeBytes, 999)
    XCTAssertEqual(info.name, "sized.dat")
  }

  func testObjectSizeInferredFromData() {
    let data = Data(repeating: 0x42, count: 256)
    let obj = VirtualObjectConfig(
      handle: 1, storage: MTPStorageID(raw: 1), name: "data.bin", data: data)
    XCTAssertEqual(obj.sizeBytes, 256)
  }

  func testFolderObjectHasAssociationFormatCode() {
    let folder = VirtualObjectConfig(
      handle: 1, storage: MTPStorageID(raw: 1), name: "Dir", formatCode: 0x3001)
    XCTAssertTrue(folder.isFolder)

    let file = VirtualObjectConfig(
      handle: 2, storage: MTPStorageID(raw: 1), name: "f.txt", formatCode: 0x3000)
    XCTAssertFalse(file.isFolder)
  }

  func testObjectInfoContainsCorrectHandle() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 77, storage: sid, parent: nil, name: "test.png",
      formatCode: 0x3801)
    await device.addObject(obj)

    let info = try await device.getInfo(handle: 77)
    XCTAssertEqual(info.handle, 77)
    XCTAssertEqual(info.formatCode, 0x3801)
  }

  func testObjectToObjectInfoPreservesParent() {
    let obj = VirtualObjectConfig(
      handle: 5, storage: MTPStorageID(raw: 1), parent: 3, name: "child.txt")
    let info = obj.toObjectInfo()
    XCTAssertEqual(info.parent, 3)
    XCTAssertEqual(info.storage.raw, 1)
  }
}

// MARK: - Virtual Device Path Resolution

final class VirtualDevicePathResolutionTests: XCTestCase {

  func testRootObjectsHaveNilParent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.getInfo(handle: 1) // DCIM
    XCTAssertNil(info.parent)
  }

  func testChildObjectReferencesCorrectParent() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let cameraInfo = try await device.getInfo(handle: 2) // Camera folder
    XCTAssertEqual(cameraInfo.parent, 1) // parent is DCIM
  }

  func testListRootReturnsOnlyTopLevelObjects() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let sid = MTPStorageID(raw: 0x0001_0001)

    var rootItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      rootItems.append(contentsOf: batch)
    }
    XCTAssertEqual(rootItems.count, 1) // Only DCIM at root
    XCTAssertEqual(rootItems[0].name, "DCIM")
  }

  func testListSubfolderReturnsOnlyDirectChildren() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let sid = MTPStorageID(raw: 0x0001_0001)

    var dcimChildren: [MTPObjectInfo] = []
    for try await batch in device.list(parent: 1, in: sid) {
      dcimChildren.append(contentsOf: batch)
    }
    XCTAssertEqual(dcimChildren.count, 1) // Only Camera subfolder
    XCTAssertEqual(dcimChildren[0].name, "Camera")
  }

  func testListEmptyFolderReturnsNothing() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    let folder = try await device.createFolder(parent: nil, name: "Empty", storage: sid)
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: folder, in: sid) {
      items.append(contentsOf: batch)
    }
    XCTAssertTrue(items.isEmpty)
  }

  func testObjectsInDifferentStoragesAreIsolated() async throws {
    let sd = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card")
    let config = VirtualDeviceConfig.emptyDevice.withStorage(sd)
    let device = VirtualMTPDevice(config: config)
    let storages = try await device.storages()

    let h1 = try await device.createFolder(
      parent: nil, name: "OnInternal", storage: storages[0].id)
    let h2 = try await device.createFolder(
      parent: nil, name: "OnSD", storage: storages[1].id)

    var internalItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storages[0].id) {
      internalItems.append(contentsOf: batch)
    }
    XCTAssertEqual(internalItems.count, 1)
    XCTAssertEqual(internalItems[0].handle, h1)

    var sdItems: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storages[1].id) {
      sdItems.append(contentsOf: batch)
    }
    XCTAssertEqual(sdItems.count, 1)
    XCTAssertEqual(sdItems[0].handle, h2)
  }
}

// MARK: - Virtual Device Event Generation

final class VirtualDeviceEventGenerationTests: XCTestCase {

  func testStorageAddedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0002_0001)

    let expectation = XCTestExpectation(description: "storageAdded event")
    let task = Task {
      for await event in await device.events {
        if case .storageAdded(let id) = event, id.raw == sid.raw {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.storageAdded(sid))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testStorageRemovedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let sid = MTPStorageID(raw: 0x0001_0001)

    let expectation = XCTestExpectation(description: "storageRemoved event")
    let task = Task {
      for await event in await device.events {
        if case .storageRemoved(let id) = event, id.raw == sid.raw {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.storageRemoved(sid))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testObjectInfoChangedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "objectInfoChanged event")
    let task = Task {
      for await event in await device.events {
        if case .objectInfoChanged(let handle) = event, handle == 55 {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.objectInfoChanged(55))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testDeviceInfoChangedEvent() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "deviceInfoChanged event")
    let task = Task {
      for await event in await device.events {
        if case .deviceInfoChanged = event {
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.deviceInfoChanged)
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testUnknownEventCode() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "unknown event")
    let task = Task {
      for await event in await device.events {
        if case .unknown(let code, let params) = event {
          XCTAssertEqual(code, 0xFFFF)
          XCTAssertEqual(params, [42])
          expectation.fulfill()
          break
        }
      }
    }

    try await Task.sleep(for: .milliseconds(50))
    await device.injectEvent(.unknown(code: 0xFFFF, params: [42]))
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }

  func testEventStreamFinishesAfterDevClose() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    let expectation = XCTestExpectation(description: "stream finishes")
    let task = Task {
      for await _ in await device.events {
        // consume
      }
      expectation.fulfill()
    }

    try await Task.sleep(for: .milliseconds(50))
    try await device.devClose()
    await fulfillment(of: [expectation], timeout: 2.0)
    task.cancel()
  }
}

// MARK: - Virtual Device Mock Transfer Latency

final class VirtualDeviceMockLatencyTests: XCTestCase {

  func testLatencyConfigAppliedToLink() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withLatency(.getDeviceInfo, duration: .milliseconds(100))
    let link = VirtualMTPLink(config: config)

    let start = ContinuousClock.now
    _ = try await link.getDeviceInfo()
    let elapsed = ContinuousClock.now - start

    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(80))
  }

  func testNoLatencyByDefault() async throws {
    let link = VirtualMTPLink(config: .emptyDevice)

    let start = ContinuousClock.now
    _ = try await link.getDeviceInfo()
    let elapsed = ContinuousClock.now - start

    XCTAssertLessThan(elapsed, .milliseconds(50))
  }

  func testMultipleOperationsWithDifferentLatencies() async throws {
    let config = VirtualDeviceConfig.emptyDevice
      .withLatency(.getDeviceInfo, duration: .milliseconds(50))
      .withLatency(.getStorageIDs, duration: .milliseconds(100))
    let link = VirtualMTPLink(config: config)

    let start1 = ContinuousClock.now
    _ = try await link.getDeviceInfo()
    let elapsed1 = ContinuousClock.now - start1

    let start2 = ContinuousClock.now
    _ = try await link.getStorageIDs()
    let elapsed2 = ContinuousClock.now - start2

    XCTAssertGreaterThanOrEqual(elapsed1, .milliseconds(30))
    XCTAssertGreaterThanOrEqual(elapsed2, .milliseconds(70))
  }
}

// MARK: - Virtual Device Tree Traversal

final class VirtualDeviceTreeTraversalTests: XCTestCase {

  private func makeTreeDevice() async throws -> (VirtualMTPDevice, MTPStorageID) {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    // Build tree: root -> A -> B -> C
    //                  -> D
    let a = try await device.createFolder(parent: nil, name: "A", storage: sid)
    let b = try await device.createFolder(parent: a, name: "B", storage: sid)
    _ = try await device.createFolder(parent: b, name: "C", storage: sid)
    _ = try await device.createFolder(parent: nil, name: "D", storage: sid)

    return (device, sid)
  }

  func testBFSTraversalVisitsAllNodes() async throws {
    let (device, sid) = try await makeTreeDevice()

    // BFS: visit level by level
    var visited: [String] = []
    var queue: [MTPObjectHandle?] = [nil] // start from root

    while !queue.isEmpty {
      let parent = queue.removeFirst()
      var children: [MTPObjectInfo] = []
      for try await batch in device.list(parent: parent, in: sid) {
        children.append(contentsOf: batch)
      }
      for child in children {
        visited.append(child.name)
        queue.append(child.handle)
      }
    }

    XCTAssertEqual(visited.count, 4)
    // BFS: A and D at root level first, then B, then C
    XCTAssertTrue(visited.prefix(2).contains("A"))
    XCTAssertTrue(visited.prefix(2).contains("D"))
    XCTAssertTrue(visited.contains("B"))
    XCTAssertTrue(visited.contains("C"))
  }

  func testDFSTraversalVisitsAllNodes() async throws {
    let (device, sid) = try await makeTreeDevice()

    // DFS: visit depth-first
    var visited: [String] = []

    func dfs(parent: MTPObjectHandle?) async throws {
      var children: [MTPObjectInfo] = []
      for try await batch in device.list(parent: parent, in: sid) {
        children.append(contentsOf: batch)
      }
      for child in children {
        visited.append(child.name)
        try await dfs(parent: child.handle)
      }
    }

    try await dfs(parent: nil)
    XCTAssertEqual(visited.count, 4)
    XCTAssertTrue(visited.contains("A"))
    XCTAssertTrue(visited.contains("B"))
    XCTAssertTrue(visited.contains("C"))
    XCTAssertTrue(visited.contains("D"))
  }

  func testTreeDepthMeasurement() async throws {
    let (device, sid) = try await makeTreeDevice()

    func depth(parent: MTPObjectHandle?) async throws -> Int {
      var children: [MTPObjectInfo] = []
      for try await batch in device.list(parent: parent, in: sid) {
        children.append(contentsOf: batch)
      }
      if children.isEmpty { return 0 }
      var maxChildDepth = 0
      for child in children {
        let d = try await depth(parent: child.handle)
        maxChildDepth = max(maxChildDepth, d)
      }
      return 1 + maxChildDepth
    }

    let d = try await depth(parent: nil)
    XCTAssertEqual(d, 3) // root -> A -> B -> C
  }

  func testLeafNodeCount() async throws {
    let (device, sid) = try await makeTreeDevice()

    func countLeaves(parent: MTPObjectHandle?) async throws -> Int {
      var children: [MTPObjectInfo] = []
      for try await batch in device.list(parent: parent, in: sid) {
        children.append(contentsOf: batch)
      }
      if children.isEmpty { return 1 }
      var total = 0
      for child in children {
        total += try await countLeaves(parent: child.handle)
      }
      return total
    }

    // root has children, so not a leaf. Leaves are C and D.
    let a = try await device.getInfo(handle: 1) // A
    let _ = a
    // Count leaves starting from root
    let leaves = try await countLeaves(parent: nil)
    XCTAssertEqual(leaves, 2) // C and D are leaves
  }

  func testEmptyTreeHasNoChildren() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let storages = try await device.storages()
    let sid = storages[0].id

    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: sid) {
      items.append(contentsOf: batch)
    }
    XCTAssertTrue(items.isEmpty)
  }
}

// MARK: - Virtual Device Dev SPI Advanced

final class VirtualDeviceDevSPIAdvancedTests: XCTestCase {

  func testDevGetRootHandlesForMultipleStorages() async throws {
    let sd = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001), description: "SD Card")
    let sdObj = VirtualObjectConfig(
      handle: 100, storage: sd.id, parent: nil, name: "SDROOT", formatCode: 0x3001)
    let config = VirtualDeviceConfig.pixel7.withStorage(sd).withObject(sdObj)
    let device = VirtualMTPDevice(config: config)

    let internalHandles = try await device.devGetRootHandlesUncached(
      storage: MTPStorageID(raw: 0x0001_0001))
    XCTAssertTrue(internalHandles.contains(1)) // DCIM

    let sdHandles = try await device.devGetRootHandlesUncached(
      storage: MTPStorageID(raw: 0x0002_0001))
    XCTAssertTrue(sdHandles.contains(100)) // SDROOT
    XCTAssertFalse(sdHandles.contains(1))
  }

  func testDevGetObjectInfoUncachedReturnsCorrectData() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let info = try await device.devGetObjectInfoUncached(handle: 3) // sample photo
    XCTAssertEqual(info.name, "IMG_20250101_120000.jpg")
    XCTAssertEqual(info.formatCode, 0x3801)
  }

  func testProbedCapabilitiesDefaultEmpty() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let caps = await device.probedCapabilities
    XCTAssertTrue(caps.isEmpty)
  }

  func testEffectiveTuningReturnsDefaults() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let tuning = await device.effectiveTuning
    XCTAssertNotNil(tuning)
  }

  func testDevicePolicyDefaultsNil() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let policy = await device.devicePolicy
    XCTAssertNil(policy)
  }

  func testProbeReceiptDefaultsNil() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    let receipt = await device.probeReceipt
    XCTAssertNil(receipt)
  }
}
