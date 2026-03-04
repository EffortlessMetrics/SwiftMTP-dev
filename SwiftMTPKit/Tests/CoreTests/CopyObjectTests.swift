// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

final class CopyObjectTests: XCTestCase {

  // MARK: - VirtualMTPDevice

  func testCopyObject_duplicatesObject() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    // Handle 3 is a photo in .pixel7 config
    let storages = try await device.storages()
    let storage = storages[0].id

    let newHandle = try await device.copyObject(
      handle: 3, toStorage: storage, parentFolder: nil)
    XCTAssertNotEqual(newHandle, 3, "New handle must differ from the source")

    let info = try await device.getInfo(handle: newHandle)
    let original = try await device.getInfo(handle: 3)
    XCTAssertEqual(info.name, original.name, "Copy should keep the original name")
  }

  func testCopyObject_nonExistentThrows() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id

    do {
      _ = try await device.copyObject(handle: 9999, toStorage: storage, parentFolder: nil)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  func testCopyObject_preservesOriginal() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    let storages = try await device.storages()
    let storage = storages[0].id

    let originalInfo = try await device.getInfo(handle: 3)
    _ = try await device.copyObject(handle: 3, toStorage: storage, parentFolder: nil)

    // Original should still exist and be unchanged
    let afterCopy = try await device.getInfo(handle: 3)
    XCTAssertEqual(afterCopy.name, originalInfo.name)
    XCTAssertEqual(afterCopy.handle, originalInfo.handle)
  }

  // MARK: - DeviceActor (zero-handle guard)

  func testCopyObject_zeroHandleThrows() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    let transport = StubTransport(link: link)
    let actor = MTPDeviceActor(
      id: config.deviceId, summary: config.summary, transport: transport,
      config: .init())

    do {
      _ = try await actor.copyObject(
        handle: 0, toStorage: MTPStorageID(raw: 0x00010001), parentFolder: nil)
      XCTFail("Expected preconditionFailed for handle 0")
    } catch let error as MTPError {
      switch error {
      case .preconditionFailed:
        break  // expected
      default:
        XCTFail("Unexpected error: \(error)")
      }
    }
  }

  // MARK: - PTPOp enum

  func testPTPOp_copyObjectValue() {
    XCTAssertEqual(PTPOp.copyObject.rawValue, 0x101A)
  }
}

// MARK: - Helpers

/// Minimal transport stub that returns a pre-built link.
private final class StubTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}
