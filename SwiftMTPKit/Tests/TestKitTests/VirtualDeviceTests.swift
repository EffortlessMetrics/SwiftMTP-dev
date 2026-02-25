// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class VirtualDeviceTests: XCTestCase {
  func testDeviceCreation() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let info = try await device.info
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
  }

  func testStorageEnumeration() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)
  }

  func testListObjects() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard let storage = storages.first else {
      XCTFail("No storages found")
      return
    }

    var allObjects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storage.id)
    for try await batch in stream {
      allObjects.append(contentsOf: batch)
    }
    // pixel7 preset has objects in root
    XCTAssertFalse(allObjects.isEmpty)
  }

  func testOperationRecording() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    _ = try await device.storages()
    let ops = await device.operations
    XCTAssertTrue(ops.contains(where: { $0.operation == "storages" }))
  }

  func testEmptyDevice() async throws {
    let config = VirtualDeviceConfig.emptyDevice
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1, "Empty device has one storage but no objects")

    // Verify no objects in the storage
    var allObjects: [MTPObjectInfo] = []
    let stream = device.list(parent: nil, in: storages[0].id)
    for try await batch in stream {
      allObjects.append(contentsOf: batch)
    }
    XCTAssertTrue(allObjects.isEmpty)
  }
}
