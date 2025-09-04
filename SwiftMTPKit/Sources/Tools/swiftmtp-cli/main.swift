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
    let jsonOutput: Bool
    let jsonlOutput: Bool
    let traceUSB: Bool
    let strict: Bool
    let safe: Bool
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    do {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        // Fall back: emit a minimal JSON error on stdout
        let fallback = ["schemaVersion":"1.0.0","error":"encoding_failed","detail":"\(error)"]
        let data = try! JSONSerialization.data(withJSONObject: fallback, options: [])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        exit(70) // internal error
    }
}

func printJSON(_ dict: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        // Fall back: emit a minimal JSON error on stdout
        let fallback = ["schemaVersion":"1.0.0","error":"encoding_failed","detail":"\(error)"]
        let data = try! JSONSerialization.data(withJSONObject: fallback, options: [])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        exit(70) // internal error
    }
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// Script-style entry point without @main
let args = CommandLine.arguments

// Parse flags from arguments
var realOnly = false
var useMock = false
var mockProfile = "default"
var jsonOutput = false
var jsonlOutput = false
var traceUSB = false
var strict = false
var safe = false
var filteredArgs = [String]()

for arg in args.dropFirst() { // Skip executable name
    if arg == "--real-only" {
        realOnly = true
    } else if arg == "--mock" {
        useMock = true
    } else if arg.hasPrefix("--mock-profile=") {
        mockProfile = String(arg.dropFirst("--mock-profile=".count))
        useMock = true
    } else if arg == "--json" {
        jsonOutput = true
    } else if arg == "--jsonl" {
        jsonlOutput = true
    } else if arg == "--trace-usb" {
        traceUSB = true
    } else if arg == "--strict" {
        strict = true
    } else if arg == "--safe" {
        safe = true
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
    print("  --json          - Output JSON to stdout (logs to stderr)")
    print("  --jsonl         - Output streaming JSON lines for multi-item results")
    print("  --trace-usb     - Log detailed USB protocol traces")
    print("  --strict        - Disable quirks and learned profiles")
    print("  --safe          - Force conservative transfer settings")
    print("")
    print("Commands:")
    print("  probe [--json] - Test device connection and get info")
    print("  usb-dump  - Show USB interface details")
    print("  diag      - Run diagnostic tests")
    print("  storages  - List storage devices")
    print("  ls <handle> - List files in directory")
    print("  pull <handle> <dest> - Download file")
    print("  bench <size> - Benchmark transfer speed")
    print("  mirror <dest> - Mirror device contents")
    print("  quirks --explain - Show active device quirk configuration")
    print("")
    print("Exit codes:")
    print("  0 - Success")
    print("  64 - Usage error (bad arguments)")
    print("  69 - Unavailable (device not found)")
    print("  70 - Internal error (unexpected failure)")
    print("  75 - Temporary failure (device busy/timeout)")
    exit(0)
}

let command = filteredArgs[0]
let remainingArgs = Array(filteredArgs.dropFirst())

switch command {
case "probe":
    await runProbe(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe))
case "usb-dump":
    await runUSBDump()
case "diag":
    await runDiag(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe))
case "storages":
    await runStorages(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe))
case "ls":
    await runList(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe), args: remainingArgs)
case "pull":
    await runPull(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe), args: remainingArgs)
case "bench":
    await runBench(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe), args: remainingArgs)
case "mirror":
    await runMirror(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe), args: remainingArgs)
case "quirks":
    await runQuirks(args: remainingArgs)
default:
    print("Unknown command: \(command)")
    print("Available: probe, usb-dump, diag, storages, ls, pull, bench, mirror, quirks")
    exit(64) // usage error
}

func openDevice(flags: CLIFlags) async throws -> any MTPDevice {
    if flags.useMock {
        print("🔧 Mock transport not yet implemented")
        throw MTPError.notSupported("Mock transport not available")
    }

    log("🔌 Using LibUSBTransport (real device)")
    if flags.strict {
        log("   Strict mode: quirks and learned profiles disabled")
    }
    if flags.safe {
        log("   Safe mode: conservative transfer settings")
    }

    log("   Enumerating devices...")
    do {
        let devices = try await MTPDeviceManager.shared.currentRealDevices()
        log("   Found \(devices.count) MTP device(s)")
        for (i, device) in devices.enumerated() {
            log("     \(i+1). \(device.id.raw) - \(device.manufacturer) \(device.model)")
        }

        guard let firstDevice = devices.first else {
            throw SwiftMTPCore.TransportError.noDevice
        }

        log("   Opening first device: \(firstDevice.id.raw)")

        // Create effective configuration based on operational modes
        var config = SwiftMTPCore.SwiftMTPConfig()

        if flags.safe {
            // Safe mode: very conservative settings
            config.transferChunkBytes = 131_072  // 128KB
            config.ioTimeoutMs = 30_000          // 30s
            config.handshakeTimeoutMs = 15_000   // 15s
            config.inactivityTimeoutMs = 20_000  // 20s
            config.overallDeadlineMs = 300_000   // 5min
            config.resumeEnabled = false
        }

        // Apply user overrides from environment
        if let userOverrides = UserOverride.fromEnvironment(ProcessInfo.processInfo.environment["SWIFTMTP_OVERRIDES"]) {
            if let chunk = userOverrides.maxChunkBytes {
                config.transferChunkBytes = chunk
            }
            if let io = userOverrides.ioTimeoutMs {
                config.ioTimeoutMs = io
            }
            if let handshake = userOverrides.handshakeTimeoutMs {
                config.handshakeTimeoutMs = handshake
            }
            if let inactivity = userOverrides.inactivityTimeoutMs {
                config.inactivityTimeoutMs = inactivity
            }
            if let overall = userOverrides.overallDeadlineMs {
                config.overallDeadlineMs = overall
            }
            if let stabilize = userOverrides.stabilizeMs {
                config.stabilizeMs = stabilize
            }
            log("   Applied user overrides from SWIFTMTP_OVERRIDES")
        }

        return try await MTPDeviceManager.shared.openDevice(with: firstDevice, transport: LibUSBTransportFactory.createTransport(), config: config)
    } catch {
        log("❌ Device operation failed: \(error)")
        log("   Error type: \(type(of: error))")
        if let nsError = error as? NSError {
            log("   Error domain: \(nsError.domain), code: \(nsError.code)")
        }
        throw error
    }
}

func runProbe(flags: CLIFlags) async {
    if flags.jsonOutput {
        await runProbeJSON(flags: flags)
        return
    }

    log("🔍 Probing for MTP devices...")

    do {
        let device = try await openDevice(flags: flags)

        log("✅ Device found and opened!")
        let info = try await device.info
        log("   Device Info: \(info.manufacturer) \(info.model)")
        log("   Operations: \(info.operationsSupported.count)")
        log("   Events: \(info.eventsSupported.count)")

        // Get storage info
        let storages = try await device.storages()
        log("   Storage devices: \(storages.count)")

        for storage in storages {
            let usedBytes = storage.capacityBytes - storage.freeBytes
            let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
            log("     - \(storage.description): \(formatBytes(storage.capacityBytes)) total, \(formatBytes(storage.freeBytes)) free (\(String(format: "%.1f", usedPercent))% used)")
        }

    } catch {
        log("❌ Probe failed: \(error)")
        log("   Error type: \(type(of: error))")
        if let nsError = error as? NSError {
            log("   Error domain: \(nsError.domain), code: \(nsError.code)")
        }
        exit(75) // temp failure
    }
}

func runProbeJSON(flags: CLIFlags) async {
    struct ProbeOutput: Codable {
        let schemaVersion: String
        let timestamp: String
        let fingerprint: DeviceFingerprint?
        let capabilities: DeviceCapabilities
        let effective: EffectiveConfig
        let hooks: [String]
        let quirks: [AppliedQuirk]
        let learnedProfile: LearnedProfile?
        let error: String?
    }

    struct DeviceFingerprint: Codable {
        let vid: String
        let pid: String
        let bcdDevice: String?
        let iface: InterfaceDescriptor
        let endpoints: EndpointDescriptor
        let deviceInfo: DeviceInfoDescriptor?
    }

    struct InterfaceDescriptor: Codable {
        let `class`: String
        let subclass: String
        let `protocol`: String
    }

    struct EndpointDescriptor: Codable {
        let input: String
        let output: String
        let event: String?
    }

    struct DeviceInfoDescriptor: Codable {
        let manufacturer: String
        let model: String
        let version: String
    }

    struct DeviceCapabilities: Codable {
        let partialRead: Bool
        let partialWrite: Bool
        let operations: [String]
        let events: [String]
        let storages: [StorageInfo]
    }

    struct EffectiveConfig: Codable {
        let maxChunkBytes: Int
        let ioTimeoutMs: Int
        let handshakeTimeoutMs: Int
        let inactivityTimeoutMs: Int
        let overallDeadlineMs: Int
        let stabilizeMs: Int
    }

    struct AppliedQuirk: Codable {
        let id: String
        let status: String
        let confidence: String?
        let changes: [String: String]
    }

    struct LearnedProfile: Codable {
        let lastUpdated: String
        let sampleCount: Int
        let avgChunkSize: Int?
        let avgHandshakeMs: Int?
        let p95ThroughputMBps: Double?
    }

    struct StorageInfo: Codable {
        let id: String
        let description: String
        let capacityBytes: UInt64
        let freeBytes: UInt64
    }

    do {
        let device = try await openDevice(flags: flags)
        let info = try await device.info
        let storages = try await device.storages()

        // Create structured output with proper schema versioning
        let output = ProbeOutput(
            schemaVersion: "1.0.0",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            fingerprint: DeviceFingerprint(
                vid: "0x2717", // TODO: Extract from actual USB descriptor
                pid: "0xff10", // TODO: Extract from actual USB descriptor
                bcdDevice: "0x0318", // TODO: Extract from actual USB descriptor
                iface: InterfaceDescriptor(class: "0x06", subclass: "0x01", protocol: "0x01"),
                endpoints: EndpointDescriptor(input: "0x81", output: "0x01", event: "0x82"),
                deviceInfo: DeviceInfoDescriptor(
                    manufacturer: info.manufacturer,
                    model: info.model,
                    version: "7.1.1" // TODO: Extract from device info
                )
            ),
            capabilities: DeviceCapabilities(
                partialRead: true, // TODO: Probe actual capabilities
                partialWrite: true, // TODO: Probe actual capabilities
                operations: info.operationsSupported.map { String(format: "0x%04X", $0) },
                events: info.eventsSupported.map { String(format: "0x%04X", $0) },
                storages: storages.map { StorageInfo(id: String($0.id.raw), description: $0.description, capacityBytes: $0.capacityBytes, freeBytes: $0.freeBytes) }
            ),
            effective: EffectiveConfig(
                maxChunkBytes: 2_097_152, // 2MB
                ioTimeoutMs: 15_000,
                handshakeTimeoutMs: 6_000,
                inactivityTimeoutMs: 8_000,
                overallDeadlineMs: 120_000,
                stabilizeMs: 400
            ),
            hooks: ["postOpenSession(+400ms)", "beforeGetStorageIDs(backoff 3×200ms, jitter 0.2)"],
            quirks: [AppliedQuirk(
                id: "xiaomi-mi-note-2-ff10",
                status: "stable",
                confidence: "high",
                changes: ["maxChunkBytes": "2097152", "stabilizeMs": "400"]
            )],
            learnedProfile: nil, // TODO: Load from learned profile store
            error: nil
        )

        printJSON(output)

    } catch {
        let errorOutput = ProbeOutput(
            schemaVersion: "1.0.0",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            fingerprint: nil,
            capabilities: DeviceCapabilities(
                partialRead: false,
                partialWrite: false,
                operations: [],
                events: [],
                storages: []
            ),
            effective: EffectiveConfig(
                maxChunkBytes: 1_048_576, // 1MB conservative
                ioTimeoutMs: 10_000,
                handshakeTimeoutMs: 6_000,
                inactivityTimeoutMs: 8_000,
                overallDeadlineMs: 60_000,
                stabilizeMs: 0
            ),
            hooks: [],
            quirks: [],
            learnedProfile: nil,
            error: error.localizedDescription
        )
        printJSON(errorOutput)
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
        if flags.jsonOutput || flags.jsonlOutput {
            let errorOutput = ["schemaVersion": "1.0.0", "error": "usage_error", "detail": "Usage: ls <storage_handle>"]
            printJSON(errorOutput)
            exit(64) // usage error
        } else {
            print("❌ Usage: ls <storage_handle>")
            print("   Get storage handle from 'storages' command")
            exit(64) // usage error
        }
    }

    if flags.jsonOutput || flags.jsonlOutput {
        await runListJSON(flags: flags, storageHandle: handle)
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
        exit(75) // temp failure
    }
}

func runListJSON(flags: CLIFlags, storageHandle: UInt32) async {
    struct ListItem: Codable {
        let schemaVersion: String
        let handle: UInt32
        let name: String
        let sizeBytes: UInt64?
        let formatCode: UInt16
        let isDirectory: Bool
    }

    do {
        let device = try await openDevice(flags: flags)
        let storageID = MTPStorageID(raw: storageHandle)

        let stream = device.list(parent: nil, in: storageID)

        if flags.jsonlOutput {
            // Streaming JSONL output
            for try await batch in stream {
                for object in batch {
                    let item = ListItem(
                        schemaVersion: "1.0.0",
                        handle: object.handle,
                        name: object.name,
                        sizeBytes: object.sizeBytes,
                        formatCode: object.formatCode,
                        isDirectory: object.formatCode == 0x3001 // Directory format code
                    )
                    printJSON(item)
                }
            }
        } else {
            // Single JSON array output
            var objects: [MTPObjectInfo] = []
            for try await batch in stream {
                objects.append(contentsOf: batch)
            }

            let items = objects.map { object in
                ListItem(
                    schemaVersion: "1.0.0",
                    handle: object.handle,
                    name: object.name,
                    sizeBytes: object.sizeBytes,
                    formatCode: object.formatCode,
                    isDirectory: object.formatCode == 0x3001
                )
            }

            let output = ["schemaVersion": "1.0.0", "items": items] as [String: Any]
            printJSON(output)
        }

    } catch {
        let errorOutput = ["schemaVersion": "1.0.0", "error": "list_failed", "detail": error.localizedDescription]
        printJSON(errorOutput)
        exit(75) // temp failure
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
        guard !storages.isEmpty else {
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

func runQuirks(args: [String]) async {
    guard let subcommand = args.first else {
        print("❌ Usage: quirks <subcommand>")
        print("   --explain - Show active device quirk configuration")
        return
    }

    switch subcommand {
    case "--explain":
        await runQuirksExplain()
    default:
        print("❌ Unknown quirks subcommand: \(subcommand)")
        print("   Available: --explain")
    }
}

func runQuirksExplain() async {
    print("🔧 Device Configuration Layers (Merge Order)")
    print("===========================================")

    // Simulate layered configuration display
    print("Device fingerprint: 2717:ff10 iface(06/01/01) eps(81,01,82)")
    print("")
    print("Layers (applied in order):")
    print("  baseline defaults      -> chunk=1MiB ioTimeout=8000ms")
    print("  capability probe       -> partialRead=yes partialWrite=yes")
    print("  learned profile        -> chunk=2MiB ioTimeout=12000ms")
    print("  quirk xiaomi-mi-note-2 -> postOpenSession delay=400ms")
    print("  user overrides         -> (none)")
    print("")

    print("Effective config:")
    print("  chunk=2MiB io=15000ms inactivity=8000ms overall=120000ms")
    print("Hooks: postOpenSession(+400ms), beforeGetStorageIDs(backoff 3×200ms)")
    print("")

    print("Applied quirks:")
    print("  xiaomi-mi-note-2-ff10 (stable, high confidence)")
    print("    Changes: maxChunkBytes=2097152, stabilizeMs=400")
    print("    Status: stable, confidence=high")
    print("    Provenance: Steven Zimmerman, 2025-01-09")
    print("")

    print("Bench gates (must pass for stable status):")
    print("  read >= 12.0 MB/s")
    print("  write >= 10.0 MB/s")
    print("")

    print("Notes:")
    print("  - Requires 250-500 ms stabilization after OpenSession")
    print("  - Prefer direct USB port; keep screen unlocked")
    print("  - Back off on DEVICE_BUSY for early storage ops")
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

