// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class VirtualDeviceConfigTests: XCTestCase {

  // MARK: - Preset Verification

  func testPixel7ConfigProperties() {
    let config = VirtualDeviceConfig.pixel7
    XCTAssertEqual(config.info.manufacturer, "Google")
    XCTAssertEqual(config.info.model, "Pixel 7")
    XCTAssertEqual(config.storages.count, 1)
    XCTAssertFalse(config.objects.isEmpty)
    XCTAssertTrue(config.objects.contains { $0.name == "DCIM" })
  }

  func testSamsungGalaxyConfig() {
    let config = VirtualDeviceConfig.samsungGalaxy
    XCTAssertEqual(config.info.manufacturer, "Samsung")
    XCTAssertEqual(config.storages.count, 1)
    XCTAssertFalse(config.objects.isEmpty)
  }

  func testCanonEOSR5Config() {
    let config = VirtualDeviceConfig.canonEOSR5
    XCTAssertEqual(config.info.manufacturer, "Canon")
    XCTAssertEqual(config.info.model, "EOS R5")
    XCTAssertTrue(config.objects.contains { $0.name == "DCIM" })
  }

  func testEmptyDeviceConfig() {
    let config = VirtualDeviceConfig.emptyDevice
    XCTAssertEqual(config.info.manufacturer, "Virtual")
    XCTAssertEqual(config.storages.count, 1)
    XCTAssertTrue(config.objects.isEmpty)
  }

  func testMultiplePresetConfigs() {
    let configs: [(String, VirtualDeviceConfig)] = [
      ("pixel7", .pixel7),
      ("samsungGalaxy", .samsungGalaxy),
      ("canonEOSR5", .canonEOSR5),
      ("nikonZ6", .nikonZ6),
      ("motorolaMotoG", .motorolaMotoG),
      ("sonyXperiaZ", .sonyXperiaZ),
      ("onePlus9", .onePlus9),
    ]
    var manufacturers = Set<String>()
    for (label, config) in configs {
      XCTAssertFalse(config.storages.isEmpty, "\(label) has no storages")
      XCTAssertFalse(config.objects.isEmpty, "\(label) has no objects")
      manufacturers.insert(config.info.manufacturer)
    }
    XCTAssertGreaterThanOrEqual(manufacturers.count, 5)
  }

  // MARK: - Builder Methods

  func testWithStorageBuilder() {
    let base = VirtualDeviceConfig.emptyDevice
    let extraStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "SD Card",
      capacityBytes: 256 * 1024 * 1024 * 1024,
      freeBytes: 200 * 1024 * 1024 * 1024
    )
    let config = base.withStorage(extraStorage)
    XCTAssertEqual(config.storages.count, 2)
    XCTAssertEqual(config.storages[1].description, "SD Card")
    // Original should be unmodified
    XCTAssertEqual(base.storages.count, 1)
  }

  func testWithObjectBuilder() {
    let base = VirtualDeviceConfig.emptyDevice
    let storageId = base.storages[0].id
    let obj = VirtualObjectConfig(
      handle: 100, storage: storageId, parent: nil,
      name: "test.txt", data: Data("test".utf8))
    let config = base.withObject(obj)
    XCTAssertEqual(config.objects.count, 1)
    XCTAssertEqual(config.objects[0].name, "test.txt")
    XCTAssertEqual(config.objects[0].sizeBytes, 4)
    // Original should be unmodified
    XCTAssertTrue(base.objects.isEmpty)
  }

  func testWithLatencyBuilder() {
    let base = VirtualDeviceConfig.emptyDevice
    let config = base.withLatency(.getDeviceInfo, duration: .milliseconds(50))
    XCTAssertEqual(config.latencyPerOp[.getDeviceInfo], .milliseconds(50))
    XCTAssertTrue(base.latencyPerOp.isEmpty)
  }

  // MARK: - Object/Storage Config Types

  func testVirtualObjectConfigIsFolder() {
    let storageId = MTPStorageID(raw: 1)
    let folder = VirtualObjectConfig(
      handle: 1, storage: storageId, parent: nil, name: "Folder", formatCode: 0x3001)
    let file = VirtualObjectConfig(
      handle: 2, storage: storageId, parent: nil, name: "file.txt", formatCode: 0x3000)
    XCTAssertTrue(folder.isFolder)
    XCTAssertFalse(file.isFolder)
  }

  func testVirtualObjectConfigToObjectInfo() {
    let storageId = MTPStorageID(raw: 0x0001_0001)
    let obj = VirtualObjectConfig(
      handle: 42, storage: storageId, parent: 10, name: "photo.jpg",
      sizeBytes: 1024, formatCode: 0x3801)
    let info = obj.toObjectInfo()
    XCTAssertEqual(info.handle, 42)
    XCTAssertEqual(info.storage.raw, 0x0001_0001)
    XCTAssertEqual(info.parent, 10)
    XCTAssertEqual(info.name, "photo.jpg")
    XCTAssertEqual(info.sizeBytes, 1024)
    XCTAssertEqual(info.formatCode, 0x3801)
  }

  func testVirtualObjectConfigSizeFromData() {
    let storageId = MTPStorageID(raw: 1)
    let obj = VirtualObjectConfig(
      handle: 1, storage: storageId, parent: nil, name: "data.bin",
      data: Data(repeating: 0xAB, count: 256))
    XCTAssertEqual(obj.sizeBytes, 256)
  }

  func testVirtualStorageConfigToStorageInfo() {
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Test Storage",
      capacityBytes: 100,
      freeBytes: 50,
      isReadOnly: true
    )
    let info = storage.toStorageInfo()
    XCTAssertEqual(info.id.raw, 0x0001_0001)
    XCTAssertEqual(info.description, "Test Storage")
    XCTAssertEqual(info.capacityBytes, 100)
    XCTAssertEqual(info.freeBytes, 50)
    XCTAssertTrue(info.isReadOnly)
  }
}
