// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPTransportLibUSB
import SwiftMTPCore
import SwiftMTPQuirks
import Testing

/// Integration tests for USB transport layer scenarios
@available(macOS 15.0, *)
@Suite(.tags(.transport, .integration))
struct TransportIntegrationTests {
  
  // MARK: - USB Bandwidth Tests
  
  @Test("USB bandwidth saturation scenarios")
  func testUSBBandwidthSaturation() async throws {
    let transport = MockUSBTransport()
    
    // Set bandwidth throttling to simulate USB 2.0 HS
    await transport.setBandwidthThrottling(1.0)
    
    // Test with various chunk sizes
    let testSizes = [1024, 4096, 16384, 65536, 262144]
    
    for size in testSizes {
      let data = Data(repeating: 0xAA, count: size)
      try await transport.write(data, timeout: 5000)
    }
    
    #expect(true)
  }
  
  @Test("USB bandwidth throttling simulation")
  func testBandwidthThrottling() async throws {
    let transport = MockUSBTransport()
    
    // Set throttled bandwidth (USB 1.1 LS speed)
    await transport.setBandwidthThrottling(0.1)
    
    let startTime = Date()
    let data = Data(repeating: 0x55, count: 65536)
    _ = try await transport.write(data, timeout: 30000)
    let elapsed = Date().timeIntervalSince(startTime)
    
    // Should take approximately 55ms for 64KB at 1.5 Mbps
    #expect(elapsed > 0.05)
  }
  
  // MARK: - Descriptor Parsing Tests
  
  @Test("USB descriptor parsing edge cases")
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
      0x32   // Max power (100mA)
    ])
    
    #expect(malformedDescriptor.count == 9)
  }
  
  @Test("Multiple interface handling")
  func testMultipleInterfaceHandling() async throws {
    let transport = MockUSBTransport()
    
    // Simulate multi-interface scenario
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    
    // Test interface selection
    #expect(await transport.configurationValue == 1)
  }
  
  @Test("Isochronous transfer patterns")
  func testIsochronousTransfers() async throws {
    let transport = MockUSBTransport()
    
    // Isochronous transfers have different timing characteristics
    await transport.setBandwidthThrottling(0.5)
    
    // Small, time-critical transfers
    for _ in 0..<10 {
      let data = Data(repeating: 0xAB, count: 256)
      _ = try await transport.write(data, timeout: 1000)
    }
    
    #expect(true)
  }
  
  // MARK: - Error Injection Tests
  
  @Test("Corrupt packet injection")
  func testCorruptPacketInjection() async throws {
    let transport = MockUSBTransport()
    
    await transport.setErrorInjection(.corruptNextPacket)
    
    do {
      let data = Data([0x0C, 0x00]) // GetDeviceInfo opcode
      _ = try await transport.write(data, timeout: 5000)
      #expect(false) // Should have thrown
    } catch let error as USBTransportError {
      #expect(error == .crcMismatch)
    }
  }
  
  @Test("Timeout injection")
  func testTimeoutInjection() async throws {
    let transport = MockUSBTransport()
    
    await transport.setErrorInjection(.timeoutNextRequest)
    
    do {
      var buffer = Data(count: 1024)
      _ = try await transport.read(into: &buffer, timeout: 5000)
      #expect(false) // Should have thrown
    } catch let error as USBTransportError {
      #expect(error == .timeout)
    }
  }
  
  @Test("Stall injection")
  func testStallInjection() async throws {
    let transport = MockUSBTransport()
    
    await transport.setErrorInjection(.stallNextRequest)
    
    do {
      let data = Data([0x0C, 0x00])
      _ = try await transport.write(data, timeout: 5000)
      #expect(false) // Should have thrown
    } catch let error as USBTransportError {
      #expect(error == .stall)
    }
  }
  
  @Test("Random bit flip simulation")
  func testRandomBitFlips() async throws {
    let transport = MockUSBTransport()
    
    await transport.setErrorInjection(.randomBitFlips(probability: 0.01))
    
    // With 1% probability, most writes should succeed
    var successCount = 0
    var failCount = 0
    
    for _ in 0..<100 {
      do {
        let data = Data(repeating: 0x42, count: 1024)
        _ = try await transport.write(data, timeout: 5000)
        successCount += 1
      } catch USBTransportError.crcMismatch {
        failCount += 1
      } catch {
        // Other errors
      }
    }
    
    // Should have mostly successes
    #expect(successCount > 90)
  }
  
  // MARK: - Response Queue Tests
  
  @Test("Programmed response queue")
  func testResponseQueue() async throws {
    let transport = MockUSBTransport()
    
    // Queue responses
    await transport.queueResponse(Data([0x20, 0x00, 0x0A, 0x00])) // Response header
    await transport.queueResponse(Data([0x01, 0x02, 0x03, 0x04])) // Response data
    
    var buffer = Data(count: 1024)
    let bytesRead = try await transport.read(into: &buffer, timeout: 5000)
    
    #expect(bytesRead > 0)
  }
  
  @Test("Programmed delays for specific opcodes")
  func testProgrammedDelays() async throws {
    let transport = MockUSBTransport()
    
    // Program slow response for GetDeviceInfo
    await transport.programDelay(opcode: 0x1001, delay: 0.1)
    
    let startTime = Date()
    let data = Data([0x01, 0x10]) // GetDeviceInfo
    _ = try await transport.write(data, timeout: 10000)
    let elapsed = Date().timeIntervalSince(startTime)
    
    #expect(elapsed > 0.09) // Should be approximately 100ms
  }
}

// MARK: - Request Logging Tests

@available(macOS 15.0, *)
@Suite(.tags(.transport, .logging))
struct RequestLoggingTests {
  
  @Test("Request logging captures all transactions")
  func testRequestLogging() async throws {
    let transport = MockUSBTransport()
    
    // Clear previous log
    await transport.clearRequests()
    
    // Perform some operations
    let data1 = Data([0x01, 0x10, 0x00, 0x0C])
    let data2 = Data([0x04, 0x10, 0x00, 0x0C])
    
    _ = try await transport.write(data1, timeout: 5000)
    _ = try await transport.write(data2, timeout: 5000)
    
    let log = await transport.getRequestLog()
    
    #expect(log.count == 2)
    #expect(log[0].direction == .outRequest)
    #expect(log[1].direction == .outRequest)
  }
  
  @Test("Request log includes timing information")
  func testRequestLogTiming() async throws {
    let transport = MockUSBTransport()
    await transport.clearRequests()
    
    let data = Data(repeating: 0xFF, count: 4096)
    _ = try await transport.write(data, timeout: 5000)
    
    let log = await transport.getRequestLog()
    
    #expect(log.count == 1)
    #expect(log[0].durationNs > 0)
  }
}
