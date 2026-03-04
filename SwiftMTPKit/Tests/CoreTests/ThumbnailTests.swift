// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

final class ThumbnailTests: XCTestCase {

  private func makeDeviceWithObject() -> (VirtualMTPDevice, MTPObjectHandle) {
    var config = VirtualDeviceConfig.emptyDevice
    let storage = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 42,
        storage: storage,
        parent: nil,
        name: "photo.jpg",
        data: Data("fake-jpeg".utf8)
      )
    )
    return (VirtualMTPDevice(config: config), 42)
  }

  // MARK: - VirtualMTPDevice thumbnail retrieval

  func testGetThumbnailReturnsStubJPEG() async throws {
    let (device, handle) = makeDeviceWithObject()

    let data = try await device.getThumbnail(handle: handle)
    XCTAssertGreaterThan(data.count, 0)
    // Verify JPEG SOI marker
    XCTAssertEqual(data[0], 0xFF)
    XCTAssertEqual(data[1], 0xD8)
    // Verify JPEG EOI marker at end
    XCTAssertEqual(data[data.count - 2], 0xFF)
    XCTAssertEqual(data[data.count - 1], 0xD9)
  }

  func testGetThumbnailWithInvalidHandleThrows() async {
    let (device, _) = makeDeviceWithObject()
    do {
      _ = try await device.getThumbnail(handle: 0xDEAD)
      XCTFail("Expected objectNotFound error")
    } catch {
      guard let mtpError = error as? MTPError else {
        XCTFail("Expected MTPError, got \(type(of: error))")
        return
      }
      XCTAssertEqual(mtpError, .objectNotFound)
    }
  }

  func testGetThumbnailWithHandle0Throws() async {
    let (device, _) = makeDeviceWithObject()
    do {
      _ = try await device.getThumbnail(handle: 0)
      XCTFail("Expected error for handle 0")
    } catch {
      XCTAssertTrue(error is MTPError)
    }
  }

  func testThumbnailDataHasReasonableSize() async throws {
    let (device, handle) = makeDeviceWithObject()

    let data = try await device.getThumbnail(handle: handle)
    XCTAssertGreaterThanOrEqual(data.count, 4)
    XCTAssertLessThan(data.count, 1_000_000, "Stub thumbnail should be small")
  }
}
