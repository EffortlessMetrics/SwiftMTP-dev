// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Foundation

// Import the LibUSB transport to get the extended MTPDeviceManager methods
import struct SwiftMTPTransportLibUSB.LibUSBTransportFactory

struct CLIFlags {
    let realOnly: Bool
    let useMock: Bool
    let mockProfile: String
}

// Script-style entry point without @main
let args = CommandLine.arguments

// Parse flags from arguments
var realOnly = false
var useMock = false
var mockProfile = "default"
var filteredArgs = [String]()

for arg in args.dropFirst() { // Skip executable name
    if arg == "--real-only" {
        realOnly = true
    } else if arg == "--mock" {
        useMock = true
    } else if arg.hasPrefix("--mock-profile=") {
        mockProfile = String(arg.dropFirst("--mock-profile=".count))
        useMock = true
    } else {
        filteredArgs.append(arg)
    }
}

if filteredArgs.isEmpty {
    print("SwiftMTP CLI - Basic MTP device testing")
    print("Usage: swift run swiftmtp [flags] <command>")
    print("")
    print("Flags:")
    print("  --real-only     - Only use real devices, no mock fallback")
    print("  --mock          - Force use mock device")
    print("  --mock-profile=<name> - Specify mock profile (default: default)")
    print("")
    print("Commands:")
    print("  probe     - Test device connection and get info")
    print("  usb-dump  - Show USB interface details")
    print("  diag      - Run diagnostic tests")
    print("  storages  - List storage devices")
    print("  ls <handle> - List files in directory")
    print("  pull <handle> <dest> - Download file")
    print("  bench <size> - Benchmark transfer speed")
    print("  mirror <dest> - Mirror device contents")
    exit(0)
}

let command = filteredArgs[0]
let remainingArgs = Array(filteredArgs.dropFirst())

switch command {
case "probe":
    await runProbe(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile))
case "usb-dump":
    await runUSBDump()
case "diag":
    await runDiag(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile))
case "storages":
    await runStorages(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile))
case "ls":
    await runList(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile), args: remainingArgs)
case "pull":
    await runPull(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile), args: remainingArgs)
case "bench":
    await runBench(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile), args: remainingArgs)
case "mirror":
    await runMirror(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile), args: remainingArgs)
default:
    print("Unknown command: \(command)")
    print("Available: probe, usb-dump, diag, storages, ls, pull, bench, mirror")
}

func openDevice(flags: CLIFlags) async throws -> any MTPDevice {
    if flags.useMock {
        print("🔧 Mock transport not yet implemented")
        throw MTPError.notSupported("Mock transport not available")
    }

    print("🔌 Using LibUSBTransport (real device)")
    do {
        return try await MTPDeviceManager.shared.openFirstRealDevice()
    } catch {
        if flags.realOnly {
            print("❌ Real device required but failed: \(error)")
            throw error
        }
        print("⚠️  Real device failed, mock fallback not available: \(error)")
        throw error
    }
}

func runProbe(flags: CLIFlags) async {
    print("🔍 Probing for MTP devices...")

    do {
        let device = try await openDevice(flags: flags)

        print("✅ Device found and opened!")
        let info = try await device.info
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

    } catch {
        print("❌ Probe failed: \(error)")
        print("   Error type: \(type(of: error))")
        if let nsError = error as? NSError {
            print("   Error domain: \(nsError.domain), code: \(nsError.code)")
        }
    }
}

func runUSBDump() async {
        print("🔍 Dumping USB device interfaces...")
        do {
            try await USBDumper().run()
            print("✅ USB dump complete")
        } catch {
            print("❌ USB dump failed: \(error)")
        }
    }

func runDiag(flags: CLIFlags) async {
        print("== Probe ==")
        await runProbe(flags: flags)

        print("\n== USB Dump ==")
        await runUSBDump()

        print("\n== OK ==")
        print("✅ Diagnostic complete")
    }

func runStorages(flags: CLIFlags) async {
    print("📁 Getting storage devices...")

    do {
        let device = try await openDevice(flags: flags)
        let storages = try await device.storages()

        print("Found \(storages.count) storage device(s):")
        for (i, storage) in storages.enumerated() {
            let usedBytes = storage.capacityBytes - storage.freeBytes
            let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
            print("  \(i+1). \(storage.description)")
            print("     Capacity: \(formatBytes(storage.capacityBytes))")
            print("     Free: \(formatBytes(storage.freeBytes))")
            print("     Used: \(String(format: "%.1f", usedPercent))%")
            print("     Handle: \(storage.id.raw)")
        }
    } catch {
        print("❌ Failed to get storages: \(error)")
    }
}

func runList(flags: CLIFlags, args: [String]) async {
    guard let handleStr = args.first, let handle = UInt32(handleStr) else {
        print("❌ Usage: ls <storage_handle>")
        print("   Get storage handle from 'storages' command")
        return
    }

    print("📂 Listing files in storage \(handle)...")

    do {
        let device = try await openDevice(flags: flags)
        let storageID = MTPStorageID(raw: handle)

        var objects: [MTPObjectInfo] = []
        let stream = device.list(parent: nil, in: storageID)
        for try await batch in stream {
            objects.append(contentsOf: batch)
        }

        if objects.isEmpty {
            print("   (empty storage)")
        } else {
            for object in objects {
                let type = object.formatCode == 0x3001 ? "📁" : "📄"  // Directory format code
                let size = object.sizeBytes.map { formatBytes($0) } ?? ""
                print("\(type) \(object.name) (handle: \(object.handle)) \(size)")
            }
        }
        print("\nTotal: \(objects.count) items")
    } catch {
        print("❌ Failed to list directory: \(error)")
    }
}

func runPull(flags: CLIFlags, args: [String]) async {
    guard args.count >= 2,
          let handle = UInt32(args[0]) else {
        print("❌ Usage: pull <handle> <destination>")
        return
    }

    let destPath = args[1]
    let destURL = URL(fileURLWithPath: destPath)
    print("⬇️  Downloading object \(handle) to \(destPath)...")

    do {
        let device = try await openDevice(flags: flags)
        let progress = try await device.read(handle: handle, range: nil, to: destURL)

        // Wait for completion (simple polling approach)
        while !progress.isFinished {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let fileSize = try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? UInt64 ?? 0
        print("✅ Downloaded \(formatBytes(fileSize ?? 0)) to \(destPath)")
    } catch {
        print("❌ Failed to download: \(error)")
    }
}

func runBench(flags: CLIFlags, args: [String]) async {
    guard let sizeStr = args.first else {
        print("❌ Usage: bench <size> (e.g., 100M, 1G)")
        return
    }

    let sizeBytes = parseSize(sizeStr)
    guard sizeBytes > 0 else {
        print("❌ Invalid size format: \(sizeStr)")
        return
    }

    print("🏃 Benchmarking with \(formatBytes(sizeBytes))...")

    do {
        let device = try await openDevice(flags: flags)
        let storages = try await device.storages()
        guard let storage = storages.first else {
            print("❌ No storage available")
            return
        }

        // Create temporary file with test data
        let tempURL = URL(fileURLWithPath: "/tmp/swiftmtp-bench.tmp")
        let testData = Data(repeating: 0xAA, count: Int(sizeBytes))
        try testData.write(to: tempURL)

        let startTime = Date()
        let progress = try await device.write(parent: nil, name: "swiftmtp-bench.tmp", size: sizeBytes, from: tempURL)

        // Wait for completion (simple polling approach)
        while !progress.isFinished {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let duration = Date().timeIntervalSince(startTime)
        let speedMBps = Double(sizeBytes) / duration / 1_000_000
        print(String(format: "✅ Upload: %.2f MB/s (%.2f seconds)", speedMBps, duration))

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

    } catch {
        print("❌ Benchmark failed: \(error)")
    }
}

func runMirror(flags: CLIFlags, args: [String]) async {
    guard let destPath = args.first else {
        print("❌ Usage: mirror <destination>")
        return
    }

    print("🔄 Mirroring device to \(destPath)...")

    do {
        let device = try await openDevice(flags: flags)
        // This would require implementing the mirror logic
        // For now, just list the root directory
        let storages = try await device.storages()
        guard let storage = storages.first else {
            print("❌ No storage available")
            return
        }

        var objects: [MTPObjectInfo] = []
        let stream = device.list(parent: nil, in: storage.id)
        for try await batch in stream {
            objects.append(contentsOf: batch)
        }
        print("Found \(objects.count) items in root directory")

    } catch {
        print("❌ Mirror failed: \(error)")
    }
}

func parseSize(_ str: String) -> UInt64 {
    let multipliers: [Character: UInt64] = ["K": 1024, "M": 1024*1024, "G": 1024*1024*1024]
    let numStr = str.filter { $0.isNumber }
    let suffix = str.last(where: { multipliers.keys.contains($0.uppercased().first!) })

    guard let num = UInt64(numStr) else { return 0 }
    guard let mult = suffix?.uppercased().first,
          let multiplier = multipliers[mult] else { return num }

    return num * multiplier
}

func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
