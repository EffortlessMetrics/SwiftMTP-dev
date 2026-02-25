// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SwiftMTPCore

final class MutationTests: XCTestCase {
  // Valid DeviceInfo dataset captured from OnePlus 3T
  let validDeviceInfoData = Data([
    0x64, 0x00, 0x06, 0x00, 0x00, 0x00, 0x64, 0x00, 0x11, 0x4d, 0x69, 0x63, 0x72, 0x6f, 0x73, 0x6f,
    0x66, 0x74, 0x20, 0x44, 0x65, 0x76, 0x69, 0x63, 0x65, 0x00, 0x00, 0x00, 0x08, 0x4f, 0x6e, 0x65,
    0x50, 0x6c, 0x75, 0x73, 0x00, 0x0e, 0x4f, 0x4e, 0x45, 0x50, 0x4c, 0x55, 0x53, 0x20, 0x41, 0x33,
    0x30, 0x31, 0x30, 0x00, 0x04, 0x31, 0x2e, 0x30, 0x00,
  ])  // Simplified example

  func testDeviceInfoMutation() {
    for _ in 1...500 {
      let mutated = MTPFuzzer.mutate(validDeviceInfoData)
      _ = PTPDeviceInfo.parse(from: mutated)
      // Expect no crash
    }
  }

  func testDeviceInfoTruncation() {
    for i in 0..<validDeviceInfoData.count {
      let truncated = validDeviceInfoData.prefix(i)
      _ = PTPDeviceInfo.parse(from: truncated)
      // Expect no crash
    }
  }

  func testStringMutation() {
    let validStringData = PTPString.encode("Hello World")
    for _ in 1...500 {
      let mutated = MTPFuzzer.mutate(validStringData)
      var off = 0
      _ = PTPString.parse(from: mutated, at: &off)
      // Expect no crash
    }
  }
}
