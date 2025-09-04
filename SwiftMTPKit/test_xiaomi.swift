#!/usr/bin/env swift
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// Simple test script for Xiaomi Mi Note 2 MTP communication
import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB

@main struct TestXiaomi {
    static func main() async {
        print("🔬 Testing Xiaomi Mi Note 2 MTP Communication")
        print("=============================================")

        do {
            print("📡 Starting device discovery...")

            // Start device discovery
            try await MTPDeviceManager.shared.startDiscovery()

            let attachedStream = await MTPDeviceManager.shared.deviceAttached
            var iterator = attachedStream.makeAsyncIterator()

            print("⏳ Waiting for Xiaomi device (timeout: 30s)...")

            // Wait for device with timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                throw NSError(domain: "TestTimeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Device discovery timeout"])
            }

            let deviceTask = Task {
                if let deviceSummary = await iterator.next() {
                    return deviceSummary
                } else {
                    throw NSError(domain: "NoDevice", code: -2, userInfo: [NSLocalizedDescriptionKey: "No device found"])
                }
            }

            let deviceSummary = try await deviceTask.value
            timeoutTask.cancel()

            print("✅ Device found!")
            print("   Manufacturer: \(deviceSummary.manufacturer)")
            print("   Model: \(deviceSummary.model)")
            print("   ID: \(deviceSummary.id.raw)")

            print("\n🔌 Opening transport connection...")

            // Open device
            let transport = LibUSBTransportFactory.createTransport()
            let config = SwiftMTPConfig() // Use default config
            let device = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport, config: config)

            print("✅ Transport connection established!")

            print("\n📱 Getting device information...")

            // Get device info
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

            print("\n💾 Getting storage information...")

            // Get storage info
            let storages = try await device.storages()
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
                let objects = await listObjects(device: device, storage: firstStorage.id, parent: nil, maxCount: 10)
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
