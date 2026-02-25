// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import CLibusb
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

final class PTPUSBHelpersCoverageTests: XCTestCase {
  func testPTPHeaderEncodeDecodeRoundTrip() {
    let header = PTPHeader(length: 24, type: 1, code: 0x1001, txid: 42)
    var bytes = [UInt8](repeating: 0, count: PTPHeader.size)
    bytes.withUnsafeMutableBytes { raw in
      header.encode(into: raw.baseAddress!)
    }
    let decoded = bytes.withUnsafeBytes { raw in
      PTPHeader.decode(from: raw.baseAddress!)
    }
    XCTAssertEqual(decoded.length, 24)
    XCTAssertEqual(decoded.type, 1)
    XCTAssertEqual(decoded.code, 0x1001)
    XCTAssertEqual(decoded.txid, 42)
  }

  func testPTPHeaderDecodeFromMisalignedPointer() {
    let header = PTPHeader(length: 28, type: 2, code: 0x1009, txid: 77)
    var encoded = [UInt8](repeating: 0, count: PTPHeader.size)
    encoded.withUnsafeMutableBytes { raw in
      header.encode(into: raw.baseAddress!)
    }

    var padded = [UInt8](repeating: 0, count: encoded.count + 1)
    padded.replaceSubrange(1..<(encoded.count + 1), with: encoded)
    let decoded = padded.withUnsafeBytes { raw in
      PTPHeader.decode(from: raw.baseAddress!.advanced(by: 1))
    }

    XCTAssertEqual(decoded.length, 28)
    XCTAssertEqual(decoded.type, 2)
    XCTAssertEqual(decoded.code, 0x1009)
    XCTAssertEqual(decoded.txid, 77)
  }

  func testMakePTPCommandEncodesHeaderAndParams() {
    let command = makePTPCommand(opcode: 0x1002, txid: 99, params: [1, 2, 3])
    XCTAssertEqual(command.count, PTPHeader.size + 12)

    let header = command.withUnsafeBytes { raw in
      PTPHeader.decode(from: raw.baseAddress!)
    }
    XCTAssertEqual(header.length, UInt32(command.count))
    XCTAssertEqual(header.type, PTPContainer.Kind.command.rawValue)
    XCTAssertEqual(header.code, 0x1002)
    XCTAssertEqual(header.txid, 99)

    var reader = PTPReader(data: Data(command[PTPHeader.size...]))
    let params = (0..<3).compactMap { _ in reader.u32() }
    XCTAssertEqual(params, [1, 2, 3])
  }

  func testMakePTPDataContainerEncodesHeader() {
    let dataContainer = makePTPDataContainer(length: 4096, code: 0x1009, txid: 7)
    XCTAssertEqual(dataContainer.count, PTPHeader.size)

    let header = dataContainer.withUnsafeBytes { raw in
      PTPHeader.decode(from: raw.baseAddress!)
    }
    XCTAssertEqual(header.length, 4096)
    XCTAssertEqual(header.type, PTPContainer.Kind.data.rawValue)
    XCTAssertEqual(header.code, 0x1009)
    XCTAssertEqual(header.txid, 7)
  }

  func testMapLibusbAndCheckHelpers() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_TIMEOUT.rawValue)), .timeout)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_BUSY.rawValue)), .busy)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_ACCESS.rawValue)), .accessDenied)
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_NO_DEVICE.rawValue)), .noDevice)

    if case .io(let message) = mapLibusb(-999) {
      XCTAssertTrue(message.contains("-999"))
    } else {
      XCTFail("Expected io mapping")
    }

    XCTAssertNoThrow(try check(0))
    do {
      try check(Int32(LIBUSB_ERROR_TIMEOUT.rawValue))
      XCTFail("Expected timeout transport error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .transport(.timeout))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLibUSBTransportFactoryUsesFeatureFlags() {
    let flags = FeatureFlags.shared
    let original = flags.useMockTransport
    defer { flags.useMockTransport = original }

    flags.useMockTransport = true
    let mocked = LibUSBTransportFactory.createTransport()
    XCTAssertTrue(mocked is MockTransport)

    flags.useMockTransport = false
    let real = LibUSBTransportFactory.createTransport()
    XCTAssertTrue(real is LibUSBTransport)
  }

  func testLibUSBContextSingletonPointer() {
    let first = LibUSBContext.shared.contextPointer
    let second = LibUSBContext.shared.contextPointer
    XCTAssertEqual(first, second)
  }

  func testMapLibusbPipeReturnsStall() {
    XCTAssertEqual(mapLibusb(Int32(LIBUSB_ERROR_PIPE.rawValue)), .stall)
  }

  func testTransportErrorStallCaseExists() {
    let stall = TransportError.stall
    XCTAssertEqual(stall, TransportError.stall)
    XCTAssertNotEqual(stall, TransportError.timeout)
    XCTAssertNotNil(stall.errorDescription)
  }

  func testTransportPhaseDescriptions() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }
}
