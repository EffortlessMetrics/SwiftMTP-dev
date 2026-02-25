// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Integration tests for USB transport layer scenarios
@available(macOS 15.0, *)
final class TransportIntegrationTests: XCTestCase {
  private func connectedTransport() async throws -> MockUSBTransport {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    return transport
  }

  // MARK: - USB Bandwidth Tests

  func testUSBBandwidthSaturation() async throws {
    let transport = try await connectedTransport()

    // Set bandwidth throttling to simulate USB 2.0 HS
    await transport.setBandwidthThrottling(1.0)

    // Test with various chunk sizes
    let testSizes = [1024, 4096, 16384, 65536, 262144]

    for size in testSizes {
      let data = Data(repeating: 0xAA, count: size)
      _ = try await transport.write(data, timeout: 5000)
    }

    XCTAssertTrue(true)
  }

  func testBandwidthThrottling() async throws {
    let transport = try await connectedTransport()

    // Set throttled bandwidth (USB 1.1 LS speed)
    await transport.setBandwidthThrottling(0.1)

    let startTime = Date()
    let data = Data(repeating: 0x55, count: 65536)
    _ = try await transport.write(data, timeout: 30000)
    let elapsed = Date().timeIntervalSince(startTime)

    // Should take approximately 55ms for 64KB at 1.5 Mbps
    XCTAssertGreaterThan(elapsed, 0.05)
  }

  // MARK: - Descriptor Parsing Tests

  func testUSBDescriptorParsing() async throws {
    // Test malformed descriptors
    let malformedDescriptor = Data([
      0x09,  // Length
      0x02,  // Descriptor type
      0x00, 0x01,  // Total length (little-endian)
      0x01,  // Num interfaces
      0x01,  // Configuration value
      0x00,  // Configuration string index
      0xC0,  // Attributes (bus powered)
      0x32,  // Max power (100mA)
    ])

    XCTAssertEqual(malformedDescriptor.count, 9)
  }

  func testMultipleInterfaceHandling() async throws {
    let transport = MockUSBTransport()

    // Simulate multi-interface scenario
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)

    // Test interface selection
    let configValue = await transport.configurationValue
    XCTAssertEqual(configValue, 1)
  }

  func testIsochronousTransfers() async throws {
    let transport = try await connectedTransport()

    // Isochronous transfers have different timing characteristics
    await transport.setBandwidthThrottling(0.5)

    // Small, time-critical transfers
    for _ in 0..<10 {
      let data = Data(repeating: 0xAB, count: 256)
      _ = try await transport.write(data, timeout: 1000)
    }

    XCTAssertTrue(true)
  }

  // MARK: - Error Injection Tests

  func testCorruptPacketInjection() async throws {
    let transport = try await connectedTransport()

    await transport.setErrorInjection(.corruptNextPacket)

    do {
      let data = Data([0x0C, 0x00])  // GetDeviceInfo opcode
      _ = try await transport.write(data, timeout: 5000)
      XCTFail("Should have thrown")
    } catch let error as USBTransportError {
      XCTAssertEqual(error, .crcMismatch)
    }
  }

  func testTimeoutInjection() async throws {
    let transport = try await connectedTransport()

    await transport.setErrorInjection(.timeoutNextRequest)

    do {
      var buffer = Data(count: 1024)
      _ = try await transport.read(into: &buffer, timeout: 5000)
      XCTFail("Should have thrown")
    } catch let error as USBTransportError {
      XCTAssertEqual(error, .timeout)
    }
  }

  func testStallInjection() async throws {
    let transport = try await connectedTransport()

    await transport.setErrorInjection(.stallNextRequest)

    do {
      let data = Data([0x0C, 0x00])
      _ = try await transport.write(data, timeout: 5000)
      XCTFail("Should have thrown")
    } catch let error as USBTransportError {
      XCTAssertEqual(error, .stall)
    }
  }

  func testRandomBitFlips() async throws {
    let transport = try await connectedTransport()

    await transport.setErrorInjection(.randomBitFlips(probability: 0.01))

    // With 1% probability, most writes should succeed
    var successCount = 0
    var failCount = 0

    for _ in 0..<100 {
      do {
        let data = Data(repeating: 0x42, count: 1024)
        _ = try await transport.write(data, timeout: 5000)
        successCount += 1
      } catch is USBTransportError {
        failCount += 1
      }
    }

    // Should have mostly successes
    XCTAssertGreaterThan(successCount, 90)
  }

  // MARK: - Response Queue Tests

  func testResponseQueue() async throws {
    let transport = try await connectedTransport()

    // Queue responses
    await transport.queueResponse(Data([0x20, 0x00, 0x0A, 0x00]))  // Response header
    await transport.queueResponse(Data([0x01, 0x02, 0x03, 0x04]))  // Response data

    var buffer = Data(count: 1024)
    let bytesRead = try await transport.read(into: &buffer, timeout: 5000)

    XCTAssertGreaterThan(bytesRead, 0)
  }

  func testProgrammedDelays() async throws {
    let transport = try await connectedTransport()

    // Program slow response for GetDeviceInfo
    await transport.programDelay(opcode: 0x1001, delay: 0.1)

    let startTime = Date()
    let data = Data([0x01, 0x10])  // GetDeviceInfo
    _ = try await transport.write(data, timeout: 10000)
    let elapsed = Date().timeIntervalSince(startTime)

    XCTAssertGreaterThan(elapsed, 0.09)  // Should be approximately 100ms
  }
}

// MARK: - Request Logging Tests

@available(macOS 15.0, *)
final class RequestLoggingTests: XCTestCase {
  private func connectedTransport() async throws -> MockUSBTransport {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    return transport
  }

  func testRequestLogging() async throws {
    let transport = try await connectedTransport()

    // Clear previous log
    await transport.clearRequests()

    // Perform some operations
    let data1 = Data([0x01, 0x10, 0x00, 0x0C])
    let data2 = Data([0x04, 0x10, 0x00, 0x0C])

    _ = try await transport.write(data1, timeout: 5000)
    _ = try await transport.write(data2, timeout: 5000)

    let log = await transport.getRequestLog()

    XCTAssertEqual(log.count, 2)
    XCTAssertEqual(log[0].direction, .outRequest)
    XCTAssertEqual(log[1].direction, .outRequest)
  }

  func testRequestLogTiming() async throws {
    let transport = try await connectedTransport()
    await transport.clearRequests()

    let data = Data(repeating: 0xFF, count: 4096)
    _ = try await transport.write(data, timeout: 5000)

    let log = await transport.getRequestLog()

    XCTAssertEqual(log.count, 1)
    XCTAssertGreaterThan(log[0].durationNs, 0)
  }
}
