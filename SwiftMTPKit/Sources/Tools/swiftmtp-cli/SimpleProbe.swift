import Foundation
import SwiftMTPTransportLibUSB

@main
struct SimpleProbe {
    static func main() async {
        print("🔌 Simple MTP Device Probe")
        print("Initializing libusb context...")

        // Create an async stream for device events
        let (attachedStream, _) = AsyncStream<MTPDeviceSummary>.makeStream()

        // Start USB device discovery
        USBDeviceWatcher.start(
            onAttach: { deviceSummary in
                print("🎉 Device attached!")
                print("   Manufacturer: \(deviceSummary.manufacturer)")
                print("   Model: \(deviceSummary.model)")
                print("   ID: \(deviceSummary.id.raw)")
                print("   Device appears to have MTP interface (class 0x06)")
            },
            onDetach: { deviceId in
                print("📤 Device detached: \(deviceId.raw)")
            }
        )

        print("✅ Device discovery started successfully")
        print("Waiting for MTP devices… (you may need to change USB mode on your device)")
        print("Make sure your device is in 'File Transfer' mode, not 'Charging only'")
        print("Press Ctrl+C to exit")

        // Wait for device attachment
        for await d in attachedStream {
            print("🔄 Attempting basic transport connection...")

            // Try basic transport connection
            do {
                let transport = LibUSBTransportFactory.createTransport()
                let link = try await transport.open(d)
                print("✅ Successfully opened USB transport connection")
                print("   Transport link established")

                // Close the link
                await link.close()
                print("✅ Transport connection closed successfully")
                print("✅ Basic device detection working!")

            } catch {
                print("⚠️  Transport connection failed: \(error)")
                print("   This is expected if device is not in MTP mode")
                print("   Try: unlock phone → Settings → Connected devices → USB → 'File Transfer'")
            }

            print("Waiting for more devices... (Ctrl+C to exit)")
        }
    }
}
