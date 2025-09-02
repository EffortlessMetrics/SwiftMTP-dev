import SwiftMTPCore
import SwiftMTPTransportLibUSB

@main struct CLI {
  static func main() async {
    try? await MTPDeviceManager.shared.startDiscovery()
    print("Waiting for MTP devices…")
    let attachedStream = await MTPDeviceManager.shared.deviceAttached
    for await d in attachedStream {
      print("Attached: \(d.manufacturer) \(d.model) [\(d.id.raw)]")

      // Open device and get parsed device info
      do {
        let transport = LibUSBTransportFactory.createTransport()
        let device = try await MTPDeviceManager.shared.openDevice(with: d, transport: transport)
        let info = try await device.info

        print("Device Info:")
        print("  Manufacturer: \(info.manufacturer)")
        print("  Model: \(info.model)")
        print("  Version: \(info.version)")
        if let serial = info.serialNumber {
          print("  Serial Number: \(serial)")
        }
        print("  Operations Supported: \(info.operationsSupported.count)")
        print("  Events Supported: \(info.eventsSupported.count)")

        print("Device info retrieved successfully!")

      } catch {
        print("Failed to get device info: \(error)")
      }
      break
    }
  }
}
