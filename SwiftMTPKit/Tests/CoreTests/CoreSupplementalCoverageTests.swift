// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

final class CoreSupplementalCoverageTests: XCTestCase {
  private func makeEventContainer(code: UInt16, param: UInt32?) -> Data {
    var bytes: [UInt8] = []
    let length: UInt32 = param == nil ? 12 : 16
    bytes.append(contentsOf: withUnsafeBytes(of: length.littleEndian, Array.init))
    bytes.append(contentsOf: withUnsafeBytes(of: UInt16(4).littleEndian, Array.init))
    bytes.append(contentsOf: withUnsafeBytes(of: code.littleEndian, Array.init))
    bytes.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian, Array.init))
    if let param {
      bytes.append(contentsOf: withUnsafeBytes(of: param.littleEndian, Array.init))
    }
    return Data(bytes)
  }

  func testMTPExtensionOpcodesAndPTPOpAliases() {
    XCTAssertEqual(MTPOp.getObjectPropList.rawValue, 0x9805)
    XCTAssertEqual(MTPOp.getPartialObject64.rawValue, 0x95C4)
    XCTAssertEqual(MTPOp.sendPartialObject.rawValue, 0x95C1)
    XCTAssertEqual(MTPOp.getObjectPropDesc.rawValue, 0x9802)
    XCTAssertEqual(MTPOp.getObjectPropValue.rawValue, 0x9803)
    XCTAssertEqual(MTPOp.setObjectPropValue.rawValue, 0x9804)
    XCTAssertEqual(MTPOp.getObjectReferences.rawValue, 0x9810)
    XCTAssertEqual(MTPOp.setObjectReferences.rawValue, 0x9811)

    XCTAssertEqual(PTPOp.getPartialObject64Value, MTPOp.getPartialObject64.rawValue)
    XCTAssertEqual(PTPOp.sendPartialObjectValue, MTPOp.sendPartialObject.rawValue)
    XCTAssertEqual(PTPOp.getObjectPropListValue, MTPOp.getObjectPropList.rawValue)
  }

  func testMTPEventFromRawParsesKnownCodes() {
    if case .objectAdded(let handle)? = MTPEvent.fromRaw(
      makeEventContainer(code: 0x4002, param: 777))
    {
      XCTAssertEqual(handle, 777)
    } else {
      XCTFail("Expected objectAdded event")
    }

    if case .objectRemoved(let handle)? = MTPEvent.fromRaw(
      makeEventContainer(code: 0x4003, param: 888))
    {
      XCTAssertEqual(handle, 888)
    } else {
      XCTFail("Expected objectRemoved event")
    }

    if case .storageInfoChanged(let storage)? = MTPEvent.fromRaw(
      makeEventContainer(code: 0x400C, param: 0x10001))
    {
      XCTAssertEqual(storage.raw, 0x10001)
    } else {
      XCTFail("Expected storageInfoChanged event")
    }

    // Unknown codes now return .unknown(code:params:) instead of nil
    if case .unknown(let code, _)? = MTPEvent.fromRaw(makeEventContainer(code: 0x4999, param: 1)) {
      XCTAssertEqual(code, 0x4999)
    } else {
      XCTFail("Expected .unknown for code 0x4999")
    }
    XCTAssertNil(MTPEvent.fromRaw(Data([0x01, 0x02])))
    XCTAssertNil(MTPEvent.fromRaw(makeEventContainer(code: 0x4002, param: nil)))
  }

  func testSpinnerAndExitCodeConstants() async throws {
    XCTAssertEqual(ExitCode.ok.rawValue, 0)
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
    XCTAssertEqual(ExitCode.software.rawValue, 70)
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)

    let disabled = Spinner(enabled: false)
    disabled.start("disabled")
    disabled.stopAndClear("done")

    let enabled = Spinner(enabled: true)
    enabled.start("enabled")
    try await Task.sleep(for: .milliseconds(30))
    enabled.stopAndClear("done")
  }
}
