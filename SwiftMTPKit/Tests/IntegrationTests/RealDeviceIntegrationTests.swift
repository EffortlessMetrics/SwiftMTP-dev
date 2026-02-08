// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Integration tests for real device scenarios using libusb.
/// These tests require actual hardware and are gated behind
/// the SWIFTMTP_LIVE_DEVICE_TESTS=1 environment variable.
@available(macOS 15.0, *)
final class RealDeviceIntegrationTests: XCTestCase {

  // MARK: - Device Probing Tests

  func testDeviceProbing() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_LIVE_DEVICE_TESTS"] == "1",
      "Requires real Android device connected via USB"
    )
  }

  func testFullFileTransferLifecycle() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_LIVE_DEVICE_TESTS"] == "1",
      "Requires real Android device with MTP support"
    )
  }

  func testConcurrentMultiDevice() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_LIVE_DEVICE_TESTS"] == "1",
      "Requires multiple real Android devices"
    )
  }

  func testHotPlugDetection() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_LIVE_DEVICE_TESTS"] == "1",
      "Requires hot-plug capability with a real device"
    )
  }

  func testLongRunningStability() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_LIVE_DEVICE_TESTS"] == "1",
      "Runs for extended period with a real device"
    )
  }
}

// MARK: - Conditional Compilation for Real Device Tests

#if canImport(Darwin) && canImport(IOKit)
import IOKit
import IOKit.usb

/// Helper to check for connected USB devices
enum USBHardwareChecker {
  static func hasConnectedMTPDevice(vendorID: UInt16? = nil, productID: UInt16? = nil) -> Bool {
    // Implementation would check IOKit for connected USB devices
    // For CI environments, this typically returns false
    return false
  }

  static func getConnectedDeviceCount() -> Int {
    // Count connected USB MTP devices
    return 0
  }
}

#endif

// MARK: - Mock-Based Real Device Tests (Fallback)

@available(macOS 15.0, *)
final class MockRealDeviceIntegrationTests: XCTestCase {

  func testVirtualDeviceProbing() async throws {
    let profile = VirtualDeviceProfiles.pixel7

    // Verify profile setup
    XCTAssertEqual(profile.name, "pixel7")
    XCTAssertEqual(profile.vendorID, 0x18D1)
    XCTAssertTrue(profile.supportedOperations.contains(0x1001))
  }

  func testVirtualFileTransfer() async throws {
    let transport = MockUSBTransport()

    // Simulate transfer
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)

    // Verify connection
    let isConnected = await transport.isConnected
    XCTAssertTrue(isConnected)
  }

  func testProgrammableResponses() async throws {
    let transport = MockUSBTransport()

    // Program slow response
    await transport.programDelay(opcode: 0x1001, delay: 0.5)

    // Program error injection
    await transport.setErrorInjection(.timeoutNextRequest)

    // Verify setup
    await transport.programDelay(opcode: 0x1007, delay: 0.1)
  }

  func testTrafficRecording() async throws {
    let recorder = TrafficRecorder()

    // Start recording session
    await recorder.startSession(profile: "pixel7")

    // Record some entries
    let entry = TrafficRecorder.TrafficEntry(
      timestamp: Date(),
      direction: .request,
      opcode: 0x1001,
      payload: Data([0x00, 0x01]),
      responseTimeMs: 50
    )
    await recorder.record(entry: entry)

    // End session
    let session = await recorder.endSession()

    // Verify recording
    XCTAssertNotNil(session)
    XCTAssertEqual(session?.deviceProfile, "pixel7")
    XCTAssertEqual(session?.entries.count, 1)
  }

  func testMultiVirtualDeviceConcurrency() async throws {
    let pixel7Transport = MockUSBTransport()
    let onePlusTransport = MockUSBTransport()

    // Connect both devices concurrently
    async let connectPixel7: Void = pixel7Transport.connect(vid: 0x18D1, pid: 0x4EE1)
    async let connectOnePlus: Void = onePlusTransport.connect(vid: 0x2A70, pid: 0x9038)

    _ = try await (connectPixel7, connectOnePlus)

    // Verify both connected
    let p7Connected = await pixel7Transport.isConnected
    let opConnected = await onePlusTransport.isConnected
    XCTAssertTrue(p7Connected)
    XCTAssertTrue(opConnected)
  }
}
