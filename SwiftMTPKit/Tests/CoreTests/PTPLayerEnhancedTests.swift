// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Enhanced PTPLayer tests with async operations using VirtualMTPLink
final class PTPLayerEnhancedTests: XCTestCase {

  // MARK: - PTPLayer.getDeviceInfo

  func testGetDeviceInfoSuccess() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)

    let deviceInfo = try await PTPLayer.getDeviceInfo(on: link)

    XCTAssertEqual(deviceInfo.manufacturer, config.info.manufacturer)
    XCTAssertTrue(deviceInfo.operationsSupported.contains(0x1001))
  }

  func testGetDeviceInfoFromVirtualDevice() async throws {
    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId,
      manufacturer: "TestManufacturer",
      model: "TestModel",
      vendorID: 0x1234,
      productID: 0x5678
    )
    let info = MTPDeviceInfo(
      manufacturer: "TestManufacturer",
      model: "TestModel",
      version: "1.0",
      serialNumber: "12345",
      operationsSupported: Set([0x1001, 0x1002, 0x1003, 0x1004]),
      eventsSupported: Set([0x4002])
    )
    let config = VirtualDeviceConfig(
      deviceId: deviceId,
      summary: summary,
      info: info
    )
    let link = VirtualMTPLink(config: config)

    let deviceInfo = try await PTPLayer.getDeviceInfo(on: link)

    XCTAssertEqual(deviceInfo.manufacturer, "TestManufacturer")
    XCTAssertEqual(deviceInfo.model, "TestModel")
  }

  // MARK: - PTPLayer.openSession

  func testOpenSessionSuccess() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)

    try await PTPLayer.openSession(id: 1, on: link)
    // Session opened successfully
  }

  func testOpenSessionWithDifferentIDs() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)

    // Open multiple sessions (only last one matters in simple mock)
    try await PTPLayer.openSession(id: 42, on: link)
    try await PTPLayer.openSession(id: 100, on: link)
  }

  // MARK: - PTPLayer.closeSession

  func testCloseSessionSuccess() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)

    try await PTPLayer.openSession(id: 1, on: link)
    try await PTPLayer.closeSession(on: link)
  }

  // MARK: - PTPLayer.getStorageIDs

  func testGetStorageIDsWithStorages() async throws {
    let storage1 = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001),
      description: "Storage 1",
      capacityBytes: 16_000_000_000
    )
    let storage2 = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00020001),
      description: "Storage 2",
      capacityBytes: 32_000_000_000
    )

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "Test", model: "Test", vendorID: 0x1234, productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "Test", model: "Test", version: "1.0", serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1002, 0x1004]), eventsSupported: [])
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage1, storage2])
    let link = VirtualMTPLink(config: config)

    let storageIDs = try await PTPLayer.getStorageIDs(on: link)

    XCTAssertEqual(storageIDs.count, 2)
  }

  func testGetStorageIDsEmptyDevice() async throws {
    let config = VirtualDeviceConfig.emptyDevice
    let link = VirtualMTPLink(config: config)

    let storageIDs = try await PTPLayer.getStorageIDs(on: link)

    // Empty device has at least one storage
    XCTAssertFalse(storageIDs.isEmpty)
  }

  // MARK: - PTPLayer.getStorageInfo

  func testGetStorageInfoSuccess() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001),
      description: "Internal Storage",
      capacityBytes: 16_000_000_000,
      freeBytes: 8_000_000_000
    )

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "Test", model: "Test", vendorID: 0x1234, productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "Test", model: "Test", version: "1.0", serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1005]), eventsSupported: [])
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage])
    let link = VirtualMTPLink(config: config)

    let storageID = MTPStorageID(raw: 0x00010001)
    let storageInfo = try await PTPLayer.getStorageInfo(id: storageID, on: link)

    XCTAssertEqual(storageInfo.id.raw, 0x00010001)
    XCTAssertEqual(storageInfo.description, "Internal Storage")
    XCTAssertEqual(storageInfo.capacityBytes, 16_000_000_000)
  }

  // MARK: - PTPLayer.getObjectHandles

  func testGetObjectHandlesWithObjects() async throws {
    let obj1 = VirtualObjectConfig(
      handle: 0x00010001, storage: MTPStorageID(raw: 0x00010001), parent: nil, name: "file1.txt")
    let obj2 = VirtualObjectConfig(
      handle: 0x00010002, storage: MTPStorageID(raw: 0x00010001), parent: nil, name: "file2.txt")
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001), description: "Internal", capacityBytes: 16_000_000_000)

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "Test", model: "Test", vendorID: 0x1234, productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "Test", model: "Test", version: "1.0", serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1007]), eventsSupported: [])
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage], objects: [obj1, obj2])
    let link = VirtualMTPLink(config: config)

    let storageID = MTPStorageID(raw: 0x00010001)
    let handles = try await PTPLayer.getObjectHandles(storage: storageID, parent: nil, on: link)

    XCTAssertEqual(handles.count, 2)
  }

  func testGetObjectHandlesWithParentFilter() async throws {
    let parentObj = VirtualObjectConfig(
      handle: 0x00000001, storage: MTPStorageID(raw: 0x00010001), parent: nil, name: "folder",
      formatCode: 0x3001)
    let childObj = VirtualObjectConfig(
      handle: 0x00010002, storage: MTPStorageID(raw: 0x00010001), parent: 0x00000001,
      name: "child.txt")
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001), description: "Internal", capacityBytes: 16_000_000_000)

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "Test", model: "Test", vendorID: 0x1234, productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "Test", model: "Test", version: "1.0", serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1007]), eventsSupported: [])
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage],
      objects: [parentObj, childObj])
    let link = VirtualMTPLink(config: config)

    let storageID = MTPStorageID(raw: 0x00010001)
    let handles = try await PTPLayer.getObjectHandles(
      storage: storageID, parent: 0x00000001, on: link)

    // Should only return the child object
    XCTAssertEqual(handles.count, 1)
    XCTAssertEqual(handles[0], 0x00010002)
  }

  // MARK: - PTPLayer.supportsOperation Edge Cases

  func testSupportsOperationWithAllOperations() {
    // Create a device with many operations supported
    let operations = Set([
      PTPOp.getDeviceInfo.rawValue,
      PTPOp.openSession.rawValue,
      PTPOp.closeSession.rawValue,
      PTPOp.getStorageIDs.rawValue,
      PTPOp.getStorageInfo.rawValue,
      PTPOp.getObjectHandles.rawValue,
      PTPOp.getObject.rawValue,
      PTPOp.sendObject.rawValue,
      PTPOp.deleteObject.rawValue,
    ])

    let deviceInfo = MTPDeviceInfo(
      manufacturer: "Test",
      model: "TestDevice",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: operations,
      eventsSupported: []
    )

    // Test all supported operations
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getDeviceInfo.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.openSession.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.closeSession.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getStorageIDs.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getStorageInfo.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(
      PTPLayer.supportsOperation(PTPOp.getObjectHandles.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.getObject.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.sendObject.rawValue, deviceInfo: deviceInfo))
    XCTAssertTrue(PTPLayer.supportsOperation(PTPOp.deleteObject.rawValue, deviceInfo: deviceInfo))
  }

  func testSupportsOperationVendorSpecific() {
    let deviceInfo = MTPDeviceInfo(
      manufacturer: "Test",
      model: "TestDevice",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1002]),
      eventsSupported: []
    )

    // Vendor-specific operations should return false if not in the set
    XCTAssertFalse(PTPLayer.supportsOperation(0x9801, deviceInfo: deviceInfo))
    XCTAssertFalse(PTPLayer.supportsOperation(0x9001, deviceInfo: deviceInfo))
    XCTAssertFalse(PTPLayer.supportsOperation(0xFFFF, deviceInfo: deviceInfo))
  }

  func testSupportsOperationWithEmptySet() {
    let deviceInfo = MTPDeviceInfo(
      manufacturer: "Test",
      model: "TestDevice",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: [],
      eventsSupported: []
    )

    XCTAssertFalse(PTPLayer.supportsOperation(0x1001, deviceInfo: deviceInfo))
    XCTAssertFalse(PTPLayer.supportsOperation(0x1002, deviceInfo: deviceInfo))
  }

  // MARK: - Session Management Flow

  func testFullSessionLifecycle() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001), description: "Internal", capacityBytes: 16_000_000_000)

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "TestManufacturer", model: "TestModel", vendorID: 0x1234,
      productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "TestManufacturer",
      model: "TestModel",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1002, 0x1003, 0x1004]),
      eventsSupported: []
    )
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage])
    let link = VirtualMTPLink(config: config)

    // Open session
    try await PTPLayer.openSession(id: 42, on: link)

    // Get device info during session
    let deviceInfo = try await PTPLayer.getDeviceInfo(on: link)
    XCTAssertEqual(deviceInfo.manufacturer, "TestManufacturer")

    // Get storage IDs
    let storageIDs = try await PTPLayer.getStorageIDs(on: link)
    XCTAssertFalse(storageIDs.isEmpty)

    // Close session
    try await PTPLayer.closeSession(on: link)
  }

  // MARK: - Concurrent Operations

  func testConcurrentPTPOperations() async throws {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x00010001), description: "Internal", capacityBytes: 16_000_000_000)

    let deviceId = MTPDeviceID(raw: "test:001@1:1")
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: "TestManufacturer", model: "TestModel", vendorID: 0x1234,
      productID: 0x5678)
    let info = MTPDeviceInfo(
      manufacturer: "TestManufacturer",
      model: "TestModel",
      version: "1.0",
      serialNumber: nil,
      operationsSupported: Set([0x1001, 0x1002, 0x1004]),
      eventsSupported: []
    )
    let config = VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info, storages: [storage])
    let link = VirtualMTPLink(config: config)

    // Run multiple operations concurrently
    async let deviceInfoTask = PTPLayer.getDeviceInfo(on: link)
    async let storageIDsTask = PTPLayer.getStorageIDs(on: link)

    let deviceInfo = try await deviceInfoTask
    let storageIDs = try await storageIDsTask

    XCTAssertEqual(deviceInfo.manufacturer, "TestManufacturer")
    XCTAssertFalse(storageIDs.isEmpty)
  }
}
