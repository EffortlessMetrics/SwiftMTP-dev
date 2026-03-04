// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for Android MTP edit extensions: BeginEditObject (0x95C4),
/// EndEditObject (0x95C5), and TruncateObject (0x95C3).
final class EditExtensionTests: XCTestCase {

  // MARK: - VirtualMTPLink (link-level)

  func testBeginEditObject_validHandle_succeeds() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    // Handle 3 is a photo in .pixel7 config
    try await link.beginEditObject(handle: 3)
  }

  func testEndEditObject_validHandle_succeeds() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    try await link.endEditObject(handle: 3)
  }

  func testTruncateObject_validHandle_succeeds() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    try await link.truncateObject(handle: 3, offset: 1024)
  }

  func testBeginEditObject_nonExistent_throws() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    do {
      try await link.beginEditObject(handle: 9999)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // VirtualMTPLink throws TransportError.io for unknown handles
    }
  }

  func testEndEditObject_nonExistent_throws() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    do {
      try await link.endEditObject(handle: 9999)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // Expected
    }
  }

  func testTruncateObject_nonExistent_throws() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    do {
      try await link.truncateObject(handle: 9999, offset: 0)
      XCTFail("Expected error for non-existent handle")
    } catch {
      // Expected
    }
  }

  func testEndEditObject_withoutBeginEdit_succeeds() async throws {
    // At link level, endEdit is a standalone command — no state tracking
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    try await link.endEditObject(handle: 3)
  }

  func testDoubleBeginEdit_succeeds() async throws {
    // At link level, consecutive beginEdit calls are accepted
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    try await link.beginEditObject(handle: 3)
    try await link.beginEditObject(handle: 3)
  }

  func testTruncateObject_zeroOffset_succeeds() async throws {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    try await link.truncateObject(handle: 3, offset: 0)
  }

  func testTruncateObject_largeOffset_succeeds() async throws {
    // Verify 64-bit offset handling (split into lo/hi in the protocol)
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    let largeOffset: UInt64 = 0x1_0000_0001  // exceeds 32-bit range
    try await link.truncateObject(handle: 3, offset: largeOffset)
  }

  // MARK: - DeviceActor (handle-0 guards)

  func testBeginEdit_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.beginEdit(handle: 0)
      XCTFail("Expected preconditionFailed for handle 0")
    } catch let error as MTPError {
      switch error {
      case .preconditionFailed:
        break  // expected
      default:
        XCTFail("Unexpected MTPError: \(error)")
      }
    }
  }

  func testEndEdit_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.endEdit(handle: 0)
      XCTFail("Expected preconditionFailed for handle 0")
    } catch let error as MTPError {
      switch error {
      case .preconditionFailed:
        break  // expected
      default:
        XCTFail("Unexpected MTPError: \(error)")
      }
    }
  }

  func testTruncateFile_zeroHandle_throwsPreconditionFailed() async throws {
    let actor = makeActor()
    do {
      try await actor.truncateFile(handle: 0, size: 1024)
      XCTFail("Expected preconditionFailed for handle 0")
    } catch let error as MTPError {
      switch error {
      case .preconditionFailed:
        break  // expected
      default:
        XCTFail("Unexpected MTPError: \(error)")
      }
    }
  }

  func testBeginEdit_validHandle_succeeds() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
  }

  func testEndEdit_validHandle_succeeds() async throws {
    let actor = makeActor()
    try await actor.endEdit(handle: 3)
  }

  func testTruncateFile_validHandle_succeeds() async throws {
    let actor = makeActor()
    try await actor.truncateFile(handle: 3, size: 512)
  }

  // MARK: - Workflows

  func testBeginEdit_truncate_endEdit_workflow() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.truncateFile(handle: 3, size: 2048)
    try await actor.endEdit(handle: 3)
  }

  func testBeginEdit_endEdit_workflow() async throws {
    let actor = makeActor()
    try await actor.beginEdit(handle: 3)
    try await actor.endEdit(handle: 3)
  }

  // MARK: - MTPOp enum values

  func testMTPOp_editExtensionValues() {
    XCTAssertEqual(MTPOp.beginEditObject.rawValue, 0x95C4)
    XCTAssertEqual(MTPOp.endEditObject.rawValue, 0x95C5)
    XCTAssertEqual(MTPOp.truncateObject.rawValue, 0x95C3)
  }

  // MARK: - Helpers

  private func makeActor() -> MTPDeviceActor {
    let config = VirtualDeviceConfig.pixel7
    let link = VirtualMTPLink(config: config)
    let transport = StubTransport(link: link)
    return MTPDeviceActor(
      id: config.deviceId, summary: config.summary, transport: transport,
      config: .init())
  }
}

/// Minimal transport stub that returns a pre-built link.
private final class StubTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}
