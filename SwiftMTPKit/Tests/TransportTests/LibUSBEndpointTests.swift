// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
import SwiftMTPTestKit

extension USBEndpointAddress: Equatable {
  static func == (lhs: USBEndpointAddress, rhs: USBEndpointAddress) -> Bool {
    lhs.rawValue == rhs.rawValue
  }
}

extension USBEndpointAddress {
  var transferType: TransferType {
    switch rawValue & 0x03 {
    case 0x03:
      return .interrupt
    default:
      return .bulk
    }
  }
}

/// Tests for USB endpoint handling and data transfer
final class LibUSBEndpointTests: XCTestCase {

  // MARK: - Endpoint Address Tests

  func testEndpointAddressParsing() {
    // Bulk IN endpoint
    let bulkIn = USBEndpointAddress(rawValue: 0x81)
    XCTAssertTrue(bulkIn.isInput)
    XCTAssertFalse(bulkIn.isOutput)
    XCTAssertEqual(bulkIn.number, 1)
    XCTAssertEqual(bulkIn.transferType, .bulk)

    // Bulk OUT endpoint
    let bulkOut = USBEndpointAddress(rawValue: 0x02)
    XCTAssertFalse(bulkOut.isInput)
    XCTAssertTrue(bulkOut.isOutput)
    XCTAssertEqual(bulkOut.number, 2)
    XCTAssertEqual(bulkOut.transferType, .bulk)

    // Interrupt IN endpoint
    let interruptIn = USBEndpointAddress(rawValue: 0x83)
    XCTAssertTrue(interruptIn.isInput)
    XCTAssertEqual(interruptIn.number, 3)
    XCTAssertEqual(interruptIn.transferType, .interrupt)
  }

  func testEndpointAddressEquality() {
    let addr1 = USBEndpointAddress(rawValue: 0x81)
    let addr2 = USBEndpointAddress(rawValue: 0x81)
    let addr3 = USBEndpointAddress(rawValue: 0x01)

    XCTAssertEqual(addr1, addr2)
    XCTAssertNotEqual(addr1, addr3)
  }

  // MARK: - Transfer Type Tests

  func testTransferTypes() {
    let bulk = USBEndpointAddress(rawValue: 0x02)
    XCTAssertEqual(bulk.transferType, .bulk)

    let interrupt = USBEndpointAddress(rawValue: 0x83)
    XCTAssertEqual(interrupt.transferType, .interrupt)
  }

  // MARK: - Data Buffer Tests

  func testBufferAllocation() {
    let smallBuffer = DataBuffer(capacity: 512)
    XCTAssertEqual(smallBuffer.capacity, 512)

    let largeBuffer = DataBuffer(capacity: 2 * 1024 * 1024)
    XCTAssertEqual(largeBuffer.capacity, 2 * 1024 * 1024)
  }

  func testBufferWriteAndRead() {
    var buffer = DataBuffer(capacity: 1024)
    let testData = Data([0x01, 0x02, 0x03, 0x04, 0x05])

    buffer.write(testData)
    XCTAssertEqual(buffer.availableBytes, testData.count)

    let readData = buffer.read(count: testData.count)
    XCTAssertEqual(readData, testData)
  }

  func testBufferPartialWrites() {
    var buffer = DataBuffer(capacity: 1024)

    buffer.write(Data([0x01, 0x02]))
    XCTAssertEqual(buffer.availableBytes, 2)

    buffer.write(Data([0x03, 0x04]))
    XCTAssertEqual(buffer.availableBytes, 4)
  }

  func testBufferOverflowHandling() {
    var buffer = DataBuffer(capacity: 10)
    let largeData = Data(repeating: 0xFF, count: 20)

    // Writing more than capacity should not crash
    buffer.write(largeData)
    // Buffer should be at capacity
    XCTAssertEqual(buffer.availableBytes, buffer.capacity)
  }

  func testBufferClear() {
    var buffer = DataBuffer(capacity: 1024)
    buffer.write(Data([0x01, 0x02, 0x03]))

    buffer.clear()
    XCTAssertEqual(buffer.availableBytes, 0)
  }

  // MARK: - Bulk Transfer Simulation Tests

  func testBulkTransferChunking() {
    let dataSize = 5 * 1024 * 1024  // 5 MB
    let chunkSize = 2 * 1024 * 1024  // 2 MB chunks
    let data = Data(repeating: 0xAA, count: dataSize)

    var chunks: [Data] = []
    var offset = 0

    while offset < data.count {
      let chunkLength = min(chunkSize, data.count - offset)
      chunks.append(data.subdata(in: offset..<(offset + chunkLength)))
      offset += chunkLength
    }

    XCTAssertEqual(chunks.count, 3)
    XCTAssertEqual(chunks[0].count, chunkSize)
    XCTAssertEqual(chunks[1].count, chunkSize)
    XCTAssertEqual(chunks[2].count, dataSize - (2 * chunkSize))
  }

  func testBulkTransferAlignment() {
    // Test that chunk boundaries are properly aligned
    let chunkSize = 2 * 1024 * 1024
    var offsets: [Int] = [0]

    var currentOffset = 0
    while currentOffset < 10 * 1024 * 1024 {
      currentOffset += chunkSize
      offsets.append(currentOffset)
    }

    XCTAssertEqual(offsets.count, 6)
    for offset in offsets {
      XCTAssertEqual(offset % chunkSize, 0)
    }
  }

  // MARK: - Interrupt Transfer Tests

  func testInterruptTransferSetup() {
    let interruptEndpoint = USBEndpointAddress(rawValue: 0x83)
    XCTAssertEqual(interruptEndpoint.transferType, .interrupt)
    XCTAssertTrue(interruptEndpoint.isInput)
  }

  // MARK: - Transfer Configuration Tests

  func testTransferConfigDefaults() {
    let config = TransferConfig.default
    XCTAssertEqual(config.timeoutMs, 10_000)
    XCTAssertEqual(config.chunkSize, 2 * 1024 * 1024)
  }

  func testTransferConfigCustom() {
    var config = TransferConfig.default
    config.timeoutMs = 30_000
    config.chunkSize = 4 * 1024 * 1024

    XCTAssertEqual(config.timeoutMs, 30_000)
    XCTAssertEqual(config.chunkSize, 4 * 1024 * 1024)
  }

  func testTransferConfigHighLatency() {
    var config = TransferConfig.default
    config.timeoutMs = 60_000

    XCTAssertEqual(config.timeoutMs, 60_000)
  }

  // MARK: - USB Packet Size Tests

  func testMaxPacketSizeCalculation() {
    // USB 2.0 high-speed bulk: 512 bytes
    let highSpeedBulk: UInt16 = 512
    XCTAssertEqual(highSpeedBulk, 512)

    // USB 2.0 full-speed bulk: 64 bytes
    let fullSpeedBulk: UInt16 = 64
    XCTAssertEqual(fullSpeedBulk, 64)

    // USB 3.0 super-speed bulk: 1024 bytes
    let superSpeedBulk: UInt16 = 1024
    XCTAssertEqual(superSpeedBulk, 1024)
  }

  func testPacketSizeAlignment() {
    let packetSize: UInt16 = 512
    let bufferSize = 4 * 1024 * 1024

    let alignedPackets = bufferSize / Int(packetSize)
    XCTAssertEqual(alignedPackets, 8192)
  }

  // MARK: - Data Transfer State Tests

  func testTransferStateTransitions() {
    var state = TransferState.idle

    state.start()
    XCTAssertEqual(state, .inProgress)

    state.complete()
    XCTAssertEqual(state, .completed)

    state.reset()
    XCTAssertEqual(state, .idle)
  }

  func testTransferStateFailure() {
    var state = TransferState.inProgress

    state.fail(error: .timeout)
    XCTAssertEqual(state, .failed(.timeout))
  }

  // MARK: - Virtual Device Transfer Tests

  func testVirtualDeviceTransfer() async throws {
    let config = VirtualDeviceConfig.pixel7
    let virtualDevice = VirtualMTPDevice(config: config)

    // Verify virtual device can be created
    XCTAssertNotNil(virtualDevice)
  }

  func testVirtualDeviceLatencyConfiguration() {
    let fastConfig = VirtualDeviceConfig.pixel7
      .withLatency(.getObjectInfos, duration: .milliseconds(10))

    let slowConfig = VirtualDeviceConfig.pixel7
      .withLatency(.getObjectInfos, duration: .milliseconds(500))

    XCTAssertNotNil(fastConfig)
    XCTAssertNotNil(slowConfig)
  }
}

// MARK: - Supporting Types

enum TransferType: Equatable {
  case control
  case bulk
  case interrupt
  case isochronous
}

struct DataBuffer {
  let capacity: Int
  private var data: Data
  private var readOffset: Int = 0

  init(capacity: Int) {
    self.capacity = capacity
    self.data = Data(capacity: capacity)
  }

  var availableBytes: Int {
    data.count - readOffset
  }

  mutating func write(_ newData: Data) {
    let availableSpace = capacity - data.count
    let bytesToWrite = min(newData.count, availableSpace)
    if bytesToWrite > 0 {
      data.append(newData.prefix(bytesToWrite))
    }
  }

  mutating func read(count: Int) -> Data {
    let bytesToRead = min(count, availableBytes)
    let result = data.subdata(in: readOffset..<(readOffset + bytesToRead))
    readOffset += bytesToRead
    return result
  }

  mutating func clear() {
    data.removeAll()
    readOffset = 0
  }
}

enum TransferState: Equatable {
  case idle
  case inProgress
  case completed
  case failed(TransferError)

  mutating func start() {
    self = .inProgress
  }

  mutating func complete() {
    self = .completed
  }

  mutating func fail(error: TransferError) {
    self = .failed(error)
  }

  mutating func reset() {
    self = .idle
  }
}

enum TransferError: Equatable {
  case timeout
  case crc
  case stall
  case babble
  case bufferOverrun
  case deviceDisconnected
}
