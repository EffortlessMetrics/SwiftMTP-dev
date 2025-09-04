// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Foundation

@main struct SwiftMTPCLI {
    static func main() async {
        let args = CommandLine.arguments

        if args.count < 2 {
            print("SwiftMTP CLI - Basic MTP device testing")
            print("Usage: swift run swiftmtp <command>")
            print("")
            print("Commands:")
            print("  probe     - Test device connection and get info")
            print("  usb-dump  - Show USB interface details")
            print("  diag      - Run diagnostic tests")
            return
        }

        let command = args[1]

        switch command {
        case "probe":
            await runProbe()
        case "usb-dump":
            await runUSBDump()
        case "diag":
            await runDiag()
        default:
            print("Unknown command: \(command)")
            print("Available: probe, usb-dump, diag")
        }
    }

    static func runProbe() async {
        print("🔍 Probing for MTP devices...")

        do {
            // Get device manager and start discovery
            try await MTPDeviceManager.shared.startDiscovery()

            let attachedStream = await MTPDeviceManager.shared.deviceAttached
            var iterator = attachedStream.makeAsyncIterator()

            print("Waiting for device attachment... (Ctrl+C to cancel)")

            if let deviceSummary = await iterator.next() {
                print("✅ Device found!")
                print("   Manufacturer: \(deviceSummary.manufacturer)")
                print("   Model: \(deviceSummary.model)")
                print("   ID: \(deviceSummary.id.raw)")

                // Try to open the device
                let transport = LibUSBTransportFactory.createTransport()
                let config = SwiftMTPConfig() // Use default config
                let device = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport, config: config)

                let info = try await device.info
                print("✅ Device opened successfully!")
                print("   Device Info: \(info.manufacturer) \(info.model)")
                print("   Operations: \(info.operationsSupported.count)")
                print("   Events: \(info.eventsSupported.count)")

                // Get storage info
                let storages = try await device.storages()
                print("   Storage devices: \(storages.count)")

                for storage in storages {
                    let usedBytes = storage.capacityBytes - storage.freeBytes
                    let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
                    print("     - \(storage.description): \(formatBytes(storage.capacityBytes)) total, \(formatBytes(storage.freeBytes)) free (\(String(format: "%.1f", usedPercent))% used)")
                }

            } else {
                print("❌ No device found within timeout")
            }

        } catch {
            print("❌ Probe failed: \(error)")
        }
    }

    static func runUSBDump() async {
        print("🔍 Dumping USB device interfaces...")
        do {
            try await USBDumper().run()
            print("✅ USB dump complete")
        } catch {
            print("❌ USB dump failed: \(error)")
        }
    }

    static func runDiag() async {
        print("== Probe ==")
        await runProbe()

        print("\n== USB Dump ==")
        await runUSBDump()

        print("\n== OK ==")
        print("✅ Diagnostic complete")
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
}
