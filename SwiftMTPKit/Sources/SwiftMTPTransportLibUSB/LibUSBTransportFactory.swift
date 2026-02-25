// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

public struct LibUSBTransportFactory: TransportFactory {
  public static func createTransport() -> MTPTransport {
    if FeatureFlags.shared.useMockTransport {
      let profile = FeatureFlags.shared.mockProfile
      let data: MockDeviceData
      switch profile.lowercased() {
      case "s21", "galaxy": data = MockDeviceData.androidGalaxyS21
      case "oneplus", "oneplus3t": data = MockDeviceData.androidOnePlus3T
      case "iphone", "ios": data = MockDeviceData.iosDevice
      case "canon", "camera": data = MockDeviceData.canonCamera
      default: data = MockDeviceData.androidPixel7
      }
      return MockTransport(deviceData: data)
    }
    return LibUSBTransport()
  }
}
