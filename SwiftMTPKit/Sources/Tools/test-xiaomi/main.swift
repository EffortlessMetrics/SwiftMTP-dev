// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// Test program for Xiaomi Mi Note 2 MTP communication
import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import CLibusb

@main struct TestXiaomi {
    static func main() async {
        print("🔬 Testing Xiaomi Mi Note 2 MTP Communication")
        print("=============================================")

        do {
            print("🔍 Scanning for Xiaomi device (VID:PID 2717:ff10)...")

            // Initialize libusb directly
            var ctx: OpaquePointer?
            let rc = libusb_init(&ctx)
            guard rc == 0, let ctx = ctx else {
                throw NSError(domain: "LibUSB", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize libusb"])
            }
            defer { libusb_exit(ctx) }

            // Get device list
            var list: UnsafeMutablePointer<OpaquePointer?>?
            let cnt = libusb_get_device_list(ctx, &list)
            guard cnt > 0, let list = list else {
                throw NSError(domain: "LibUSB", code: -1, userInfo: [NSLocalizedDescriptionKey: "No USB devices found"])
            }
            defer { libusb_free_device_list(list, 1) }

            // Find Xiaomi device and get its info
            var foundDevice = false
            var deviceVID: UInt16 = 0
            var devicePID: UInt16 = 0
            var deviceBus: UInt8 = 0
            var deviceAddr: UInt8 = 0

            for i in 0..<Int(cnt) {
                if let dev = list[i] {
                    var desc = libusb_device_descriptor()
                    if libusb_get_device_descriptor(dev, &desc) == 0 {
                        if desc.idVendor == 0x2717 && desc.idProduct == 0xff10 {
                            deviceVID = desc.idVendor
                            devicePID = desc.idProduct
                            deviceBus = libusb_get_bus_number(dev)
                            deviceAddr = libusb_get_device_address(dev)
                            foundDevice = true
                            break
                        }
                    }
                }
            }

            guard foundDevice else {
                throw NSError(domain: "Device", code: -1, userInfo: [NSLocalizedDescriptionKey: "Xiaomi Mi Note 2 not found"])
            }

            print("✅ Xiaomi Mi Note 2 found!")

            print("\n🔌 Opening USB transport connection...")

            // Create device summary manually
            let deviceSummary = MTPDeviceSummary(
                id: MTPDeviceID(raw: String(format: "%04x:%04x", deviceVID, devicePID)),
                manufacturer: "Xiaomi",
                model: "Mi Note 2"
            )

            print("   Device: \(deviceSummary.manufacturer) \(deviceSummary.model)")
            print("   Location: Bus \(deviceBus), Address \(deviceAddr)")
            print("   VID:PID = \(String(format:"%04x", deviceVID)):\(String(format:"%04x", devicePID))")

            // Open device
            let transport = LibUSBTransportFactory.createTransport()
            let config = SwiftMTPConfig() // Use default config
            let mtpDevice = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport, config: config)

            print("✅ Transport connection established!")

            print("\n📱 Getting device information...")

            // Get device info
            let info = try await mtpDevice.info
            print("✅ Device Info Retrieved:")
            print("   Manufacturer: \(info.manufacturer)")
            print("   Model: \(info.model)")
            print("   Version: \(info.version)")
            if let serial = info.serialNumber {
                print("   Serial Number: \(serial)")
            }
            print("   Operations Supported: \(info.operationsSupported.count)")
            print("   Events Supported: \(info.eventsSupported.count)")

            print("\n💾 Getting storage information...")

            // Get storage info
            let storages = try await mtpDevice.storages()
            print("✅ Storage Devices: \(storages.count)")

            for storage in storages {
                let usedBytes = storage.capacityBytes - storage.freeBytes
                let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
                print("   📁 \(storage.description)")
                print("      Capacity: \(formatBytes(storage.capacityBytes))")
                print("      Free: \(formatBytes(storage.freeBytes))")
                print("      Used: \(formatBytes(usedBytes)) (\(String(format: "%.1f", usedPercent))%)")
                print("      Read-only: \(storage.isReadOnly ? "Yes" : "No")")
            }

            if let firstStorage = storages.first {
                print("\n📂 Listing files from root (first 10)...")

                // List some files
                let objects = await listObjects(device: mtpDevice, storage: firstStorage.id, parent: nil, maxCount: 10)
                print("✅ Found \(objects.count) objects:")

                for object in objects {
                    if let size = object.sizeBytes {
                        print("   📄 \(object.name) (\(formatBytes(size)))")
                    } else {
                        print("   📁 \(object.name)/")
                    }
                }
            }

            print("\n🎉 MTP Communication Test: SUCCESS!")
            print("   Xiaomi Mi Note 2 is responding correctly to MTP commands")
            print("   Device is ready for file transfer operations")

        } catch {
            print("❌ Test failed: \(error)")
            if let nsError = error as? NSError {
                print("   Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            exit(1)
        }
    }

    static func listObjects(device: any MTPDevice, storage: MTPStorageID, parent: MTPObjectHandle?, maxCount: Int) async -> [MTPObjectInfo] {
        do {
            let stream = device.list(parent: parent, in: storage)
            var objects: [MTPObjectInfo] = []
            var count = 0

            for try await batch in stream {
                for object in batch {
                    objects.append(object)
                    count += 1
                    if count >= maxCount {
                        return objects
                    }
                }
            }

            return objects
        } catch {
            print("Error listing objects: \(error)")
            return []
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
}
