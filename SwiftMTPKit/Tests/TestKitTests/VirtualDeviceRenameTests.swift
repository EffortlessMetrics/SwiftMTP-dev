// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPTestKit
import SwiftMTPCore

final class VirtualDeviceRenameTests: XCTestCase {
  func testRenameObject() async throws {
    var config = VirtualDeviceConfig.emptyDevice
    let storageId = config.storages[0].id
    let handle: MTPObjectHandle = 7777
    config = config.withObject(
      VirtualObjectConfig(
        handle: handle,
        storage: storageId,
        parent: nil,
        name: "original.txt",
        data: Data()
      )
    )
    let device = VirtualMTPDevice(config: config)
    try await device.rename(handle, to: "renamed.txt")

    var allObjects: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storageId) {
      allObjects.append(contentsOf: batch)
    }

    XCTAssertTrue(allObjects.contains { $0.name == "renamed.txt" })
    XCTAssertFalse(allObjects.contains { $0.name == "original.txt" })
  }
}
