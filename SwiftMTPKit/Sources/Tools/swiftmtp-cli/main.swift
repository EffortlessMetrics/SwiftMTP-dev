import SwiftMTPCore
import SwiftMTPTransportLibUSB

@main struct CLI {
  static func main() async {
    print("Starting MTP device discovery...")
    print("Initializing libusb context...")

    do {
      try await MTPDeviceManager.shared.startDiscovery()
      print("✅ Device discovery started successfully")
      print("Waiting for MTP devices… (you may need to change USB mode on your device)")
      print("Make sure your device is in 'File Transfer' mode, not 'Charging only'")
    } catch {
      print("❌ Failed to start device discovery: \(error)")
      return
    }

    let attachedStream = await MTPDeviceManager.shared.deviceAttached
    print("✅ Listening for device attach events...")

    for await d in attachedStream {
      print("🎉 Device attached!")
      print("   Manufacturer: \(d.manufacturer)")
      print("   Model: \(d.model)")
      print("   ID: \(d.id.raw)")

      // Open device and get parsed device info
      do {
        print("🔌 Opening transport connection...")
        let transport = LibUSBTransportFactory.createTransport()
        let device = try await MTPDeviceManager.shared.openDevice(with: d, transport: transport)

        print("📱 Getting device info...")
        let info = try await device.info

        print("✅ Device Info Retrieved:")
        print("   Manufacturer: \(info.manufacturer)")
        print("   Model: \(info.model)")
        print("   Version: \(info.version)")
        if let serial = info.serialNumber {
          print("   Serial Number: \(serial)")
        }
        print("   Operations Supported: \(info.operationsSupported.count)")
        print("   Events Supported: \(info.eventsSupported.count)")

      } catch {
        print("❌ Failed to get device info: \(error)")
        print("   This might be because:")
        print("   - Device is in charging-only mode")
        print("   - Device is locked/screen off")
        print("   - Permission issues with libusb")
      }
      break
    }
  }
}
