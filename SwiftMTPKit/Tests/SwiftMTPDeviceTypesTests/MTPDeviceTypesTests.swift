// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPDeviceTypes

final class MTPDeviceTypesTests: XCTestCase {
  func testFingerprintFormatting() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "usb:1:2"),
      manufacturer: "Vendor",
      model: "Model",
      vendorID: 0x04e8,
      productID: 0x6860
    )

    XCTAssertEqual(summary.fingerprint, "04e8:6860")
  }

  func testUnknownEventPreservesCodeAndParams() {
    var data = Data()
    let words: [UInt32] = [16, 4 | (0xC001 << 16), 0, 1]
    for word in words {
      data.append(contentsOf: withUnsafeBytes(of: word.littleEndian) { Array($0) })
    }

    guard case let .unknown(code, params)? = MTPEvent.fromRaw(data) else {
      return XCTFail("Expected unknown event")
    }

    XCTAssertEqual(code, 0xC001)
    XCTAssertEqual(params, [1])
  }
}
