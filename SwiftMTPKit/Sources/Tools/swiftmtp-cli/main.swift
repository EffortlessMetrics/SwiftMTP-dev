// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Foundation

// BuildInfo is auto-generated in the same target

// Import the LibUSB transport to get the extended MTPDeviceManager methods
import struct SwiftMTPTransportLibUSB.LibUSBTransportFactory

// Import tuning system types
import struct SwiftMTPCore.EffectiveTuning
import struct SwiftMTPCore.EffectiveTuningBuilder
import struct SwiftMTPCore.MTPDeviceFingerprint
import struct SwiftMTPCore.InterfaceTriple
import struct SwiftMTPCore.EndpointAddresses
import struct SwiftMTPCore.ProbedCapabilities
import struct SwiftMTPCore.UserOverride

// Import exit code enum
import enum SwiftMTPCore.ExitCode

struct CLIFlags: Sendable {
    let realOnly: Bool
    let useMock: Bool
    let mockProfile: String
    let json: Bool
    let jsonlOutput: Bool
    let traceUSB: Bool
    let strict: Bool
    let safe: Bool
    let traceUSBDetails: Bool
    let targetVID: String?
    let targetPID: String?
    let targetBus: Int?
    let targetAddress: Int?

    // Back-compat property
    @available(*, deprecated, message: "Use json instead")
    var jsonOutput: Bool { json }
}

struct JSONEnvelope<T: Encodable>: Encodable {
    let schemaVersion: String
    let type: String
    let timestamp: String
    let data: T
}

struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ value: Encodable) {
        encode = { try value.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

@MainActor
func openDevice(flags: CLIFlags) async throws -> any MTPDevice {
    if flags.useMock {
        throw MTPError.notSupported("Mock transport not available")
    }

    let devices = try await MTPDeviceManager.shared.currentRealDevices()
    let filter = DeviceFilter(
        vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
        pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
        bus: flags.targetBus,
        address: flags.targetAddress
    )
    let selection = selectDevice(devices, filter: filter, noninteractive: false)
    let selectedDevice: MTPDeviceSummary
    switch selection {
    case .selected(let device):
        selectedDevice = device
    case .none:
        throw MTPError.notSupported("No device matches filter")
    case .multiple:
        throw MTPError.notSupported("Multiple devices match filter")
    }

    let db = (try? QuirkDatabase.load())
    let matchedQuirk = db?.match(
        vid: selectedDevice.vendorID ?? 0,
        pid: selectedDevice.productID ?? 0,
        bcdDevice: nil,
        ifaceClass: 0x06,
        ifaceSubclass: 0x01,
        ifaceProtocol: 0x01
    )

    let effectiveTuning = EffectiveTuningBuilder.build(
        capabilities: ["partialRead": true, "partialWrite": true],
        learned: nil,
        quirk: matchedQuirk,
        overrides: nil
    )

    var finalTuning = effectiveTuning
    let (userOverrides, _) = UserOverride.fromEnvironment(ProcessInfo.processInfo.environment)
    if let maxChunk = userOverrides.maxChunkBytes { finalTuning.maxChunkBytes = maxChunk }
    if let ioTimeout = userOverrides.ioTimeoutMs { finalTuning.ioTimeoutMs = ioTimeout }
    if let handshakeTimeout = userOverrides.handshakeTimeoutMs { finalTuning.handshakeTimeoutMs = handshakeTimeout }
    if let inactivityTimeout = userOverrides.inactivityTimeoutMs { finalTuning.inactivityTimeoutMs = inactivityTimeout }
    if let overallDeadline = userOverrides.overallDeadlineMs { finalTuning.overallDeadlineMs = overallDeadline }

    var config = SwiftMTPConfig()
    config.apply(finalTuning)

    return try await MTPDeviceManager.shared.openDevice(with: selectedDevice, transport: LibUSBTransportFactory.createTransport(), config: config)
}

@MainActor
struct SwiftMTPCLI {
    var realOnly = false
    var useMock = false
    var mockProfile = "default"
    var json = false
    var jsonlOutput = false
    var traceUSB = false
    var traceUSBDetails = false
    var strict = false
    var safe = false
    var targetVID: String?
    var targetPID: String?
    var targetBus: Int?
    var targetAddress: Int?
    var filteredArgs = [String]()

    mutating func parseArgs() {
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "--real-only" {
                realOnly = true
            } else if arg == "--mock" {
                useMock = true
            } else if arg.hasPrefix("--mock-profile=") {
                mockProfile = String(arg.dropFirst("--mock-profile=".count))
                useMock = true
            } else if arg == "--json" {
                json = true
            } else if arg == "--jsonl" {
                jsonlOutput = true
            } else if arg == "--trace-usb" {
                traceUSB = true
            } else if arg == "--trace-usb-details" {
                traceUSBDetails = true
            } else if arg == "--strict" {
                strict = true
            } else if arg == "--safe" {
                safe = true
            } else if arg == "--vid" {
                if i + 1 < args.count {
                    targetVID = args[i + 1]
                    i += 1
                }
            } else if arg.hasPrefix("--vid=") {
                targetVID = String(arg.dropFirst("--vid=".count))
            } else if arg == "--pid" {
                if i + 1 < args.count {
                    targetPID = args[i + 1]
                    i += 1
                }
            } else if arg.hasPrefix("--pid=") {
                targetPID = String(arg.dropFirst("--pid=".count))
            } else if arg == "--bus" {
                if i + 1 < args.count, let bus = Int(args[i + 1]) {
                    targetBus = bus
                    i += 1
                }
            } else if arg.hasPrefix("--bus=") {
                targetBus = Int(arg.dropFirst("--bus=".count))
            } else if arg == "--address" {
                if i + 1 < args.count, let address = Int(args[i + 1]) {
                    targetAddress = address
                    i += 1
                }
            } else if arg.hasPrefix("--address=") {
                targetAddress = Int(arg.dropFirst("--address=".count))
            } else {
                filteredArgs.append(arg)
            }
            i += 1
        }
    }

    func run() async {
        var mutableSelf = self
        mutableSelf.parseArgs()

        if mutableSelf.filteredArgs.isEmpty {
            printHelp()
            exitNow(.ok)
        }

        let command = mutableSelf.filteredArgs[0]
        let remainingArgs = Array(mutableSelf.filteredArgs.dropFirst())
        let flags = CLIFlags(
            realOnly: mutableSelf.realOnly,
            useMock: mutableSelf.useMock,
            mockProfile: mutableSelf.mockProfile,
            json: mutableSelf.json,
            jsonlOutput: mutableSelf.jsonlOutput,
            traceUSB: mutableSelf.traceUSB,
            strict: mutableSelf.strict,
            safe: mutableSelf.safe,
            traceUSBDetails: mutableSelf.traceUSBDetails,
            targetVID: mutableSelf.targetVID,
            targetPID: mutableSelf.targetPID,
            targetBus: mutableSelf.targetBus,
            targetAddress: mutableSelf.targetAddress
        )

        switch command {
        case "storybook":
            await StorybookCommand.run()
        case "probe":
            await runProbe(flags: flags)
        case "usb-dump":
            await runUSBDump()
        case "diag":
            await runDiag(flags: flags)
        case "storages":
            await runStorages(flags: flags)
        case "ls":
            await runList(flags: flags, args: remainingArgs)
        case "pull":
            await runPull(flags: flags, args: remainingArgs)
        case "push":
            await runPush(flags: flags, args: remainingArgs)
        case "bench":
            await runBench(flags: flags, args: remainingArgs)
        case "profile":
            var iter = 3
            if let idx = remainingArgs.firstIndex(of: "--iterations"), idx + 1 < remainingArgs.count {
                iter = Int(remainingArgs[idx+1]) ?? 3
            }
            await ProfileCommand.run(flags: flags, iterations: iter)
        case "mirror":
            await runMirror(flags: flags, args: remainingArgs)
        case "quirks":
            await runQuirks(flags: flags, args: remainingArgs)
        case "health":
            await runHealth()
        case "delete":
            let filter = DeviceFilter(
                vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                bus: flags.targetBus, 
                address: flags.targetAddress
            )
            var cmdArgs = remainingArgs
            let exitCode = await runDeleteCommand(args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter, strict: flags.strict, safe: flags.safe)
            exitNow(exitCode)
        case "move":
            let filter = DeviceFilter(
                vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                bus: flags.targetBus, 
                address: flags.targetAddress
            )
            var cmdArgs = remainingArgs
            let exitCode = await runMoveCommand(args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter, strict: flags.strict, safe: flags.safe)
            exitNow(exitCode)
        case "events":
            let filter = DeviceFilter(
                vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) }, 
                bus: flags.targetBus, 
                address: flags.targetAddress
            )
            var cmdArgs = remainingArgs
            let exitCode = await runEventsCommand(args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter, strict: flags.strict, safe: flags.safe)
            exitNow(exitCode)
        case "collect":
            if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
                printCollectHelp()
                exitNow(.ok)
            }
            await runCollect(flags: flags)
        case "submit":
            guard let bundlePath = remainingArgs.first else {
                print("❌ Usage: submit <bundle-path> [--gh]")
                exitNow(.usage)
            }
            let gh = remainingArgs.contains("--gh")
            let exitCode = await SubmitCommand.run(bundlePath: bundlePath, gh: gh)
            exitNow(exitCode)
        case "learn-promote":
            if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
                LearnPromoteCommand.printHelp()
                exitNow(.ok)
            }
            await runLearnPromote()
        case "bdd":
            await runBDD(flags: flags)
        case "snapshot":
            await runSnapshot(flags: flags, args: remainingArgs)
        case "version":
            await runVersion(flags: flags, args: remainingArgs)
        default:
            print("Unknown command: \(command)")
            exitNow(.usage)
        }
    }

    func printHelp() {
        print("SwiftMTP CLI Help...")
    }

    func runVersion(flags: CLIFlags, args: [String]) async {
        let versionData = [
            "version": BuildInfo.version,
            "git": BuildInfo.git,
            "builtAt": BuildInfo.builtAt,
            "schemaVersion": BuildInfo.schemaVersion
        ]
        
        if flags.json {
            printJSON(versionData, type: "version")
        } else {
            print("SwiftMTP \(BuildInfo.version) (\(BuildInfo.git))")
        }
    }

    func printJSON(_ value: Any, type: String) {
        var envelope: [String: Any] = [
            "schemaVersion": "1.0.0",
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            if let dict = value as? [String: Any] {
                for (k, v) in dict { envelope[k] = v }
            } else if let encodable = value as? Encodable {
                let jsonData = try JSONEncoder().encode(AnyEncodable(encodable))
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    for (k, v) in dict { envelope[k] = v }
                } else {
                    envelope["data"] = try JSONSerialization.jsonObject(with: jsonData)
                }
            } else {
                envelope["data"] = value
            }
            
            let outputData = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
            print(String(data: outputData, encoding: .utf8) ?? "{}")
        } catch {
            print("{\"error\": \"json_encoding_failed\", \"type\": \"\(type)\"}")
        }
    }

    func runProbe(flags: CLIFlags) async {
        if flags.json {
            await runProbeJSON(flags: flags)
            return
        }
        do {
            let device = try await openDevice(flags: flags)
            try await device.openIfNeeded()
            let info = try await device.getDeviceInfo()
            print("Device: \(info.manufacturer) \(info.model)")
        } catch {
            if let mtpError = error as? MTPError {
                switch mtpError {
                case .notSupported:
                    exitNow(.unavailable)
                default:
                    break
                }
            }
            print("Probe failed: \(error)")
            exitNow(.tempfail)
        }
    }

    func runProbeJSON(flags: CLIFlags) async {
        do {
            let device = try await openDevice(flags: flags)
            try await device.openIfNeeded()
            let info = try await device.getDeviceInfo()
            let storages = try await device.storages()
            
            let output: [String: Any] = [
                "manufacturer": info.manufacturer,
                "model": info.model,
                "operations": info.operationsSupported.map { String(format: "0x%04X", $0) },
                "storages": storages.map { ["id": $0.id.raw, "description": $0.description] },
                "capabilities": ["partialRead": true, "partialWrite": true],
                "effective": ["maxChunkBytes": 1048576, "ioTimeoutMs": 10000]
            ]
            printJSON(output, type: "probeResult")
        } catch {
            let errorOutput: [String: Any] = [
                "error": error.localizedDescription,
                "capabilities": [:],
                "effective": [:]
            ]
            printJSON(errorOutput, type: "probeResult")
            if let mtpError = error as? MTPError, case .notSupported = mtpError {
                exitNow(.unavailable)
            }
            exitNow(.tempfail)
        }
    }

    func runUSBDump() async {
        do {
            try await USBDumper().run()
        } catch {
            print("USB Dump failed: \(error)")
            exitNow(.tempfail)
        }
    }

    func runDiag(flags: CLIFlags) async {
        await runProbe(flags: flags)
        await runUSBDump()
    }

    func runStorages(flags: CLIFlags) async {
        do {
            let device = try await openDevice(flags: flags)
            let storages = try await device.storages()
            
            if flags.json {
                let storageInfos = storages.map { [
                    "id": String($0.id.raw),
                    "description": $0.description,
                    "capacityBytes": $0.capacityBytes,
                    "freeBytes": $0.freeBytes
                ] }
                printJSON(["storages": storageInfos], type: "storagesResult")
            } else {
                for s in storages { print("Storage: \(s.description)") }
            }
        } catch {
            if flags.json {
                printJSON(["error": error.localizedDescription], type: "storagesResult")
            } else {
                print("Storages failed: \(error)")
            }
            if let mtpError = error as? MTPError, case .notSupported = mtpError {
                exitNow(.unavailable)
            }
            exitNow(.tempfail)
        }
    }

    func runList(flags: CLIFlags, args: [String]) async {
        guard let handleStr = args.first, let handle = UInt32(handleStr) else { 
            if flags.json {
                printJSON(["error": "Usage: ls <storage_handle>"], type: "listResult")
            }
            exitNow(.usage)
        }
        do {
            let device = try await openDevice(flags: flags)
            let stream = device.list(parent: nil as MTPObjectHandle?, in: MTPStorageID(raw: handle))
            
            var items: [[String: Any]] = []
            for try await batch in stream {
                for item in batch {
                    if flags.json {
                        items.append([
                            "handle": item.handle,
                            "name": item.name,
                            "sizeBytes": item.sizeBytes ?? 0,
                            "formatCode": item.formatCode,
                            "isDirectory": item.formatCode == 0x3001
                        ])
                    } else {
                        print("- \(item.name)")
                    }
                }
            }
            if flags.json {
                printJSON(["items": items], type: "listResult")
            }
        } catch {
            if flags.json {
                printJSON(["error": error.localizedDescription], type: "listResult")
            } else {
                print("List failed: \(error)")
            }
            if let mtpError = error as? MTPError, case .notSupported = mtpError {
                exitNow(.unavailable)
            }
            exitNow(.tempfail)
        }
    }

    func runPull(flags: CLIFlags, args: [String]) async {
        guard args.count >= 2, let handle = UInt32(args[0]) else { return }
        do {
            let device = try await openDevice(flags: flags)
            let progress = try await device.read(handle: handle, range: nil, to: URL(fileURLWithPath: args[1]))
            while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
        } catch {
            print("Pull failed: \(error)")
            exitNow(.tempfail)
        }
    }

    func runPush(flags: CLIFlags, args: [String]) async {
        guard args.count >= 2 else { return }
        let handle = UInt32(args[1], radix: 16) ?? UInt32(args[1]) ?? 0
        do {
            let device = try await openDevice(flags: flags)
            let srcURL = URL(fileURLWithPath: args[0])
            let attrs = try FileManager.default.attributesOfItem(atPath: args[0])
            let size = attrs[.size] as? UInt64 ?? 0
            let progress = try await device.write(parent: handle == 0 ? nil : handle, name: srcURL.lastPathComponent, size: size, from: srcURL)
            while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
        } catch {
            print("Push failed: \(error)")
            exitNow(.tempfail)
        }
    }

    func runBench(flags: CLIFlags, args: [String]) async {
        print("Bench...")
    }

    func runMirror(flags: CLIFlags, args: [String]) async {
        print("Mirror...")
    }

    func runQuirks(flags: CLIFlags, args: [String]) async {
        guard let subcommand = args.first else {
            print("❌ Usage: quirks --explain")
            exitNow(.usage)
        }
        if subcommand == "--explain" { await runQuirksExplain(flags: flags) }
    }

    func runQuirksExplain(flags: CLIFlags) async {
        if flags.json {
            let mockExplain: [String: Any] = [
                "mode": flags.safe ? "safe" : (flags.strict ? "strict" : "normal"),
                "layers": [["source": "defaults", "description": "Built-in conservative defaults"]],
                "effective": [
                    "maxChunkBytes": 1048576,
                    "ioTimeoutMs": 10000
                ],
                "appliedQuirks": [],
                "capabilities": [:],
                "hooks": []
            ]
            printJSON(mockExplain, type: "quirksExplain")
        } else {
            print("🔧 Device Configuration Explain")
            print("Mode: \(flags.safe ? "safe" : (flags.strict ? "strict" : "normal"))")
        }
    }

    func runHealth() async {
        do {
            let devices = try await MTPDeviceManager.shared.currentRealDevices()
            print("Found \(devices.count) devices")
        } catch {
            print("Health check failed: \(error)")
            exitNow(.unavailable)
        }
    }

    func runCollect(flags: CLIFlags) async {
        let collectFlags = CollectCommand.CollectFlags(
            strict: flags.strict,
            runBench: [],
            json: flags.json,
            noninteractive: false,
            bundlePath: nil
        )
        let exitCode = await CollectCommand.run(flags: collectFlags)
        exitNow(exitCode)
    }

    func runLearnPromote() async {
        print("Learn-Promote...")
    }

    func runSnapshot(flags: CLIFlags, args: [String]) async {
        print("Snapshot...")
    }

    func runBDD(flags: CLIFlags) async {
        print("BDD...")
    }

    func printCollectHelp() {
        print("Collect Help...")
    }
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func exitNow(_ code: ExitCode) -> Never {
    Darwin.exit(Int32(code.rawValue))
}

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes), unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 { value /= 1024; unitIndex += 1 }
    return String(format: "%.1f %@", value, units[unitIndex])
}

// Global actor entry point
await SwiftMTPCLI().run()
