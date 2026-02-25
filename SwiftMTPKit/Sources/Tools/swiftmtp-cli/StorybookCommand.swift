// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import MTPEndianCodec
import SwiftMTPTransportLibUSB
import SwiftMTPObservability
import Foundation

struct StorybookCommand {
  static func run() async {
    print("📖 SwiftMTP Storybook (CLI Edition)")
    print("===================================")

    let profile = FeatureFlags.shared.mockProfile
    print("Current Profile: \(profile)")

    // Setup Mock Environment
    FeatureFlags.shared.useMockTransport = true

    let mockData: MockDeviceData
    switch profile.lowercased() {
    case "s21", "galaxy": mockData = MockDeviceData.androidGalaxyS21
    case "oneplus", "oneplus3t": mockData = MockDeviceData.androidOnePlus3T
    case "iphone", "ios": mockData = MockDeviceData.iosDevice
    case "canon", "camera": mockData = MockDeviceData.canonCamera
    default: mockData = MockDeviceData.androidPixel7
    }

    let transport = MockTransport(deviceData: mockData)
    let summary = MTPDeviceSummary(
      id: mockData.deviceSummary.id,
      manufacturer: mockData.deviceSummary.manufacturer,
      model: mockData.deviceSummary.model,
      vendorID: mockData.deviceSummary.vendorID,
      productID: mockData.deviceSummary.productID
    )

    print("")
    print("[Story 1: Device Discovery]")
    print("Found device: \(summary.manufacturer) \(summary.model) (ID: \(summary.id.raw))")

    print("")
    print("[Story 2: Connection]")
    do {
      let device = try await MTPDeviceManager.shared.openDevice(with: summary, transport: transport)
      let info = try await device.info
      print("✅ Connected!")
      print("   Serial: \(info.serialNumber ?? "N/A")")

      // 3. Storage Enumeration
      print("")
      print("[Story 3: Storage Enumeration]")
      let storages = try await device.storages()
      for storage in storages {
        print("   💾 \(storage.description) - \(formatBytes(storage.freeBytes)) free")
      }

      // 4. Events Story
      print("")
      print("[Story 4: Event Notifications]")
      print("   Listening for device events...")

      let eventTask = Task {
        for await event in device.events {
          switch event {
          case .objectAdded(let handle):
            print("   🔔 EVENT: New object added! (Handle: \(handle))")
          case .objectRemoved(let handle):
            print("   🔔 EVENT: Object removed! (Handle: \(handle))")
          case .storageInfoChanged(let storageID):
            print("   🔔 EVENT: Storage info changed! (ID: \(storageID.raw))")
          case .storageAdded(let storageID):
            print("   🔔 EVENT: Storage added (ID: \(storageID.raw))")
          case .storageRemoved(let storageID):
            print("   🔔 EVENT: Storage removed (ID: \(storageID.raw))")
          case .objectInfoChanged(let handle):
            print("   🔔 EVENT: Object info changed (Handle: \(handle))")
          case .deviceInfoChanged:
            print("   🔔 EVENT: Device info changed")
          case .unknown(let code, let params):
            print(
              "   🔔 EVENT: Unknown event code=\(String(format: "0x%04X", code)) params=\(params)")
          }
        }
      }

      // Simulate an event after a short delay
      try await Task.sleep(nanoseconds: 500_000_000)
      if let actor = device as? MTPDeviceActor {
        if let mockLink = try await actor.getMTPLink() as? MockMTPLink {
          print("   (Simulating hardware event: ObjectAdded 0xDEADBEEF)")
          let rawEvent = makeRawEvent(code: 0x4002, params: [0xDEADBEEF])
          mockLink.simulateEvent(rawEvent)
        }
      }

      try await Task.sleep(nanoseconds: 200_000_000)
      eventTask.cancel()

      // 5. Performance Story
      print("")
      print("[Story 5: Performance Monitoring]")
      var ewma = ThroughputEWMA()
      print("   Simulating 50.0 MB transfer...")
      for i in 1...50 {
        let startTime = Date()
        try await Task.sleep(nanoseconds: 10_000_000)
        let dt = Date().timeIntervalSince(startTime)
        let _ = ewma.update(bytes: 1024 * 1024, dt: dt)
        if i % 10 == 0 {
          print(
            "   Progress: \(i*2)% - Rate: \(String(format: "%.1f", ewma.megabytesPerSecond)) MB/s")
        }
      }
      print(
        "   ✅ Simulation complete. Final Rate: \(String(format: "%.1f", ewma.megabytesPerSecond)) MB/s"
      )

      // 6. Error Handling Story
      print("")
      print("[Story 6: Error Handling]")
      print("   Attempting connection to failing hardware...")
      let failingTransport = MockTransport(deviceData: MockDeviceData.failureTimeout)
      do {
        _ = try await MTPDeviceManager.shared.openDevice(with: summary, transport: failingTransport)
      } catch {
        print("   ✅ Caught expected error: \(error)")
      }

      print("")
      print("✨ Storybook completed successfully!")

    } catch {
      print("❌ Storybook failed: \(error)")
    }
  }

  static func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
      value /= 1024
      unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
  }

  /// Helper to construct raw PTP event packet
  static func makeRawEvent(code: UInt16, params: [UInt32]) -> Data {
    var enc = MTPDataEncoder()
    enc.append(UInt32(12 + UInt32(params.count) * 4))  // length
    enc.append(UInt16(4))  // Type 4 = Event
    enc.append(code)
    enc.append(UInt32(0))  // Transaction ID (usually 0 for events)
    for p in params { enc.append(p) }
    return enc.encodedData
  }
}
