// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for post-write size verification (`verifyAfterWrite` / `MTPError.verificationFailed`).
final class VerificationModeTests: XCTestCase {

  // MARK: - Helpers

  /// Returns a VirtualMTPDevice that contains one object at `handle` whose reported
  /// `sizeBytes` is `reportedSize` (which may differ from the actual data length).
  private func makeDevice(handle: MTPObjectHandle, reportedSize: UInt64) -> VirtualMTPDevice {
    let config = VirtualDeviceConfig.emptyDevice
    let storage = config.storages[0].id
    let obj = VirtualObjectConfig(
      handle: handle,
      storage: storage,
      parent: nil,
      name: "test.bin",
      sizeBytes: reportedSize,
      data: Data(repeating: 0xAA, count: Int(min(reportedSize, 256)))
    )
    return VirtualMTPDevice(config: config.withObject(obj))
  }

  // MARK: - Tests

  func testVerifySucceedsWhenSizesMatch() async throws {
    let handle: MTPObjectHandle = 10
    let expectedSize: UInt64 = 1024
    let device = makeDevice(handle: handle, reportedSize: expectedSize)

    // Should not throw when the remote size matches.
    try await postWriteVerify(device: device, handle: handle, expectedSize: expectedSize)
  }

  func testVerifyThrowsWhenSizesMismatch() async throws {
    let handle: MTPObjectHandle = 20
    let expectedSize: UInt64 = 1024
    let actualSize: UInt64 = 512  // device reports a shorter file (partial write simulation)
    let device = makeDevice(handle: handle, reportedSize: actualSize)

    do {
      try await postWriteVerify(device: device, handle: handle, expectedSize: expectedSize)
      XCTFail("Expected verificationFailed to be thrown")
    } catch let error as MTPError {
      guard case .verificationFailed(let expected, let actual) = error else {
        XCTFail("Wrong error type: \(error)")
        return
      }
      XCTAssertEqual(expected, expectedSize)
      XCTAssertEqual(actual, actualSize)
    }
  }

  func testVerifySkippedWhenHandleNotFound() async throws {
    // If the device doesn't have the handle, postWriteVerify should return silently.
    let config = VirtualDeviceConfig.emptyDevice
    let device = VirtualMTPDevice(config: config)

    // Should not throw — getInfo returns nil and verification is skipped.
    try await postWriteVerify(device: device, handle: 999, expectedSize: 100)
  }

  func testVerificationFailedErrorDescription() {
    let error = MTPError.verificationFailed(expected: 2048, actual: 1024)
    let desc = error.localizedDescription
    XCTAssertTrue(desc.contains("2048") || desc.contains("verify") || desc.contains("verif"),
                  "Error description should mention size values or verification: \(desc)")
  }

  func testVerificationFailedActionableDescription() {
    let error = MTPError.verificationFailed(expected: 100, actual: 50)
    XCTAssertTrue(error.actionableDescription.contains("verification") ||
                  error.actionableDescription.contains("size"),
                  "Actionable description missing expected content: \(error.actionableDescription)")
  }

  func testVerificationFailedIsEquatable() {
    let a = MTPError.verificationFailed(expected: 100, actual: 50)
    let b = MTPError.verificationFailed(expected: 100, actual: 50)
    let c = MTPError.verificationFailed(expected: 200, actual: 50)
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }
}
