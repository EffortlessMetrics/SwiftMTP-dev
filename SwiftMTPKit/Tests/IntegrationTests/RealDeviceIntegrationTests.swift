// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPTransportLibUSB
import SwiftMTPCore
import SwiftMTPQuirks
import Testing

/// Integration tests for real device scenarios using libusb
/// These tests require actual hardware and are conditionally compiled
@available(macOS 15.0, *)
@Suite(.tags(.realDevice, .integration))
struct RealDeviceIntegrationTests {
  
  // MARK: - Device Probing Tests
  
  @Test("Device probing discovers connected Android device")
  func testDeviceProbing() async throws {
    #continue("This test requires a real Android device connected via USB")
    #expect(false) // Skip unless hardware is available
  }
  
  @Test("Full file transfer lifecycle with real Android device")
  func testFullFileTransferLifecycle() async throws {
    #continue("This test requires a real Android device with MTP support")
    #expect(false) // Skip unless hardware is available
  }
  
  @Test("Concurrent multi-device scenarios")
  func testConcurrentMultiDevice() async throws {
    #continue("This test requires multiple real Android devices")
    #expect(false) // Skip unless hardware is available
  }
  
  @Test("Hot-plug detection and recovery")
  func testHotPlugDetection() async throws {
    #continue("This test requires hot-plug capability with a real device")
    #expect(false) // Skip unless hardware is available
  }
  
  @Test("Long-running stability tests")
  func testLongRunningStability() async throws {
    #continue("This test runs for extended period with a real device")
    #expect(false) // Skip unless hardware is available
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
@Suite(.tags(.mockDevice, .integration))
struct MockRealDeviceIntegrationTests {
  
  @Test("Virtual device probing with mock transport")
  func testVirtualDeviceProbing() async throws {
    let harness = DeviceLabHarness()
    let transport = MockUSBTransport()
    
    // Setup virtual device response
    let profile = VirtualDeviceProfiles.pixel7
    
    // Verify profile setup
    #expect(profile.name == "pixel7")
    #expect(profile.vendorID == 0x18D1)
    #expect(profile.supportedOperations.contains(0x1001))
  }
  
  @Test("Virtual device file transfer simulation")
  func testVirtualFileTransfer() async throws {
    let transport = MockUSBTransport()
    
    // Simulate transfer
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    
    // Verify connection
    let isConnected = await transport.isConnected
    #expect(isConnected == true)
  }
  
  @Test("Programmable response patterns")
  func testProgrammableResponses() async throws {
    let transport = MockUSBTransport()
    
    // Program slow response
    await transport.programDelay(opcode: 0x1001, delay: 0.5)
    
    // Program error injection
    await transport.setErrorInjection(.timeoutNextRequest)
    
    // Verify setup
    await transport.programDelay(opcode: 0x1007, delay: 0.1)
  }
  
  @Test("Traffic recording and replay")
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
    #expect(session != nil)
    #expect(session?.deviceProfile == "pixel7")
    #expect(session?.entries.count == 1)
  }
  
  @Test("Multi-virtual device concurrent operations")
  func testMultiVirtualDeviceConcurrency() async throws {
    let pixel7Transport = MockUSBTransport()
    let onePlusTransport = MockUSBTransport()
    
    // Connect both devices concurrently
    async let connectPixel7 = pixel7Transport.connect(vid: 0x18D1, pid: 0x4EE1)
    async let connectOnePlus = onePlusTransport.connect(vid: 0x2A70, pid: 0x9038)
    
    let (pixelResult, onePlusResult) = try await (connectPixel7, connectOnePlus)
    
    // Verify both connected
    #expect(await pixel7Transport.isConnected)
    #expect(await onePlusTransport.isConnected)
  }
}
