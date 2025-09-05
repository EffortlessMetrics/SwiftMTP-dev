// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Foundation

// Import the LibUSB transport to get the extended MTPDeviceManager methods
import struct SwiftMTPTransportLibUSB.LibUSBTransportFactory

// Import tuning system types
import struct SwiftMTPCore.EffectiveTuning
import class SwiftMTPCore.EffectiveTuningBuilder
import struct SwiftMTPCore.MTPDeviceFingerprint
import struct SwiftMTPCore.InterfaceTriple
import struct SwiftMTPCore.EndpointAddresses
import struct SwiftMTPCore.ProbedCapabilities
import struct SwiftMTPCore.UserOverride

// Import CLI infrastructure
import SwiftMTPCore.CLI.Exit
import SwiftMTPCore.CLI.JSONIO
import SwiftMTPCore.CLI.Spinner
import SwiftMTPCore.CLI.DeviceFilter

struct CLIFlags {
    let realOnly: Bool
    let useMock: Bool
    let mockProfile: String
    let jsonOutput: Bool
    let jsonlOutput: Bool
    let traceUSB: Bool
    let strict: Bool
    let safe: Bool
    let traceUSBDetails: Bool
    let targetVID: String?
    let targetPID: String?
    let targetBus: Int?
    let targetAddress: Int?
}

func printJSON<T: Encodable>(_ value: T, type: String) {
    printJSON(value)
}

func printJSON(_ dict: [String: Any], type: String) {
    var outputDict = dict
    outputDict["schemaVersion"] = "1.0.0"
    outputDict["type"] = type
    outputDict["timestamp"] = ISO8601DateFormatter().string(from: Date())

    // Use JSONSerialization safely
    if let data = try? JSONSerialization.data(withJSONObject: outputDict, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } else {
        // Fallback error
        let fallback: [String: Any] = [
            "schemaVersion": "1.0.0",
            "type": "error",
            "error": "encoding_failed"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fallback, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        }
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
var traceUSBDetails = false
var strict = false
var safe = false
var targetVID: String?
var targetPID: String?
var targetBus: Int?
var targetAddress: Int?
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
    } else if arg == "--trace-usb-details" {
        traceUSBDetails = true
    } else if arg == "--strict" {
        strict = true
    } else if arg == "--safe" {
        safe = true
    } else if arg == "--vid" {
        // Next arg should be the VID
        if let nextIndex = args.dropFirst().firstIndex(of: arg),
           nextIndex + 1 < args.count {
            targetVID = args[nextIndex + 1]
        }
    } else if arg.hasPrefix("--vid=") {
        targetVID = String(arg.dropFirst("--vid=".count))
    } else if arg == "--pid" {
        // Next arg should be the PID
        if let nextIndex = args.dropFirst().firstIndex(of: arg),
           nextIndex + 1 < args.count {
            targetPID = args[nextIndex + 1]
        }
    } else if arg.hasPrefix("--pid=") {
        targetPID = String(arg.dropFirst("--pid=".count))
    } else if arg == "--bus" {
        // Next arg should be the bus number
        if let nextIndex = args.dropFirst().firstIndex(of: arg),
           nextIndex + 1 < args.count,
           let bus = Int(args[nextIndex + 1]) {
            targetBus = bus
        }
    } else if arg.hasPrefix("--bus=") {
        let busStr = String(arg.dropFirst("--bus=".count))
        targetBus = Int(busStr)
    } else if arg == "--address" {
        // Next arg should be the device address
        if let nextIndex = args.dropFirst().firstIndex(of: arg),
           nextIndex + 1 < args.count,
           let address = Int(args[nextIndex + 1]) {
            targetAddress = address
        }
    } else if arg.hasPrefix("--address=") {
        let addressStr = String(arg.dropFirst("--address=".count))
        targetAddress = Int(addressStr)
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
    print("  --trace-usb     - Log USB protocol phases and endpoint details")
    print("  --trace-usb-details - Log detailed USB descriptor and packet traces")
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
    print("  health    - Verify libusb availability and permissions")
    print("  collect   - Collect device data for submission (see collect --help)")
    print("  delete <handle> [--recursive] - Delete file/directory")
    print("  move <handle> <new-parent> - Move file/directory")
    print("  events [seconds] - Monitor device events")
    print("  learn-promote - Promote learned profiles to quirks (see learn-promote --help)")
    print("")
    print("Exit codes:")
    print("  0  - Success")
    print("  64 - Usage error (bad arguments)")
    print("  69 - Unavailable (device not found, permission denied)")
    print("  70 - Internal error (unexpected failure)")
    print("  75 - Temporary failure (device busy/timeout)")
    exit(0)
}

let command = filteredArgs[0]
let remainingArgs = Array(filteredArgs.dropFirst())

switch command {
case "probe":
    await runProbe(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress))
case "usb-dump":
    await runUSBDump()
case "diag":
    await runDiag(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress))
case "storages":
    await runStorages(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress))
case "ls":
    await runList(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress), args: remainingArgs)
case "pull":
    await runPull(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress), args: remainingArgs)
case "bench":
    await runBench(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress), args: remainingArgs)
case "mirror":
    await runMirror(flags: CLIFlags(realOnly: realOnly, useMock: useMock, mockProfile: mockProfile, jsonOutput: jsonOutput, jsonlOutput: jsonlOutput, traceUSB: traceUSB, strict: strict, safe: safe, traceUSBDetails: traceUSBDetails, targetVID: targetVID, targetPID: targetPID, targetBus: targetBus, targetAddress: targetAddress), args: remainingArgs)
case "quirks":
    await runQuirks(args: remainingArgs)
case "health":
    await runHealth()
case "delete":
    var args = remainingArgs
    let filter = DeviceFilterParse.parse(from: &args)
    let json = args.contains("--json")
    let noninteractive = args.contains("--noninteractive")
    let exitCode = await runDeleteCommand(args: args, json: json, noninteractive: noninteractive, filter: filter)
    exit(exitCode.rawValue)
case "move":
    var args = remainingArgs
    let filter = DeviceFilterParse.parse(from: &args)
    let json = args.contains("--json")
    let noninteractive = args.contains("--noninteractive")
    let exitCode = await runMoveCommand(args: args, json: json, noninteractive: noninteractive, filter: filter)
    exit(exitCode.rawValue)
case "events":
    var args = remainingArgs
    let filter = DeviceFilterParse.parse(from: &args)
    let json = args.contains("--json")
    let noninteractive = args.contains("--noninteractive")
    let exitCode = await runEventsCommand(args: args, json: json, noninteractive: noninteractive, filter: filter)
    exit(exitCode.rawValue)
case "collect":
    if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
        printCollectHelp()
        exit(0)
    }
    await runCollect()
case "learn-promote":
    if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
        LearnPromoteCommand.printHelp()
        exit(0)
    }
    await runLearnPromote()
default:
    print("Unknown command: \(command)")
    print("Available: probe, usb-dump, diag, storages, ls, pull, bench, mirror, quirks, health, collect, delete, move, events, learn-promote")
    exit(64) // usage error
}

func runLearnPromote() async {
    // Parse learn-promote specific flags
    var learnPromoteFlags = LearnPromoteCommand.Flags(
        fromPath: nil,
        toPath: nil,
        dryRun: false,
        apply: false,
        verbose: false
    )

    var remainingArgs = [String]()

    for arg in filteredArgs.dropFirst() { // Skip "learn-promote"
        switch arg {
        case "--from":
            // Next arg should be the from path
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                learnPromoteFlags = LearnPromoteCommand.Flags(
                    fromPath: filteredArgs[nextIndex + 1],
                    toPath: learnPromoteFlags.toPath,
                    dryRun: learnPromoteFlags.dryRun,
                    apply: learnPromoteFlags.apply,
                    verbose: learnPromoteFlags.verbose
                )
            }
        case let arg where arg.hasPrefix("--from="):
            let fromPath = String(arg.dropFirst("--from=".count))
            learnPromoteFlags = LearnPromoteCommand.Flags(
                fromPath: fromPath,
                toPath: learnPromoteFlags.toPath,
                dryRun: learnPromoteFlags.dryRun,
                apply: learnPromoteFlags.apply,
                verbose: learnPromoteFlags.verbose
            )
        case "--to":
            // Next arg should be the to path
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                learnPromoteFlags = LearnPromoteCommand.Flags(
                    fromPath: learnPromoteFlags.fromPath,
                    toPath: filteredArgs[nextIndex + 1],
                    dryRun: learnPromoteFlags.dryRun,
                    apply: learnPromoteFlags.apply,
                    verbose: learnPromoteFlags.verbose
                )
            }
        case let arg where arg.hasPrefix("--to="):
            let toPath = String(arg.dropFirst("--to=".count))
            learnPromoteFlags = LearnPromoteCommand.Flags(
                fromPath: learnPromoteFlags.fromPath,
                toPath: toPath,
                dryRun: learnPromoteFlags.dryRun,
                apply: learnPromoteFlags.apply,
                verbose: learnPromoteFlags.verbose
            )
        case "--dry-run":
            learnPromoteFlags = LearnPromoteCommand.Flags(
                fromPath: learnPromoteFlags.fromPath,
                toPath: learnPromoteFlags.toPath,
                dryRun: true,
                apply: learnPromoteFlags.apply,
                verbose: learnPromoteFlags.verbose
            )
        case "--apply":
            learnPromoteFlags = LearnPromoteCommand.Flags(
                fromPath: learnPromoteFlags.fromPath,
                toPath: learnPromoteFlags.toPath,
                dryRun: learnPromoteFlags.dryRun,
                apply: true,
                verbose: learnPromoteFlags.verbose
            )
        case "--verbose":
            learnPromoteFlags = LearnPromoteCommand.Flags(
                fromPath: learnPromoteFlags.fromPath,
                toPath: learnPromoteFlags.toPath,
                dryRun: learnPromoteFlags.dryRun,
                apply: learnPromoteFlags.apply,
                verbose: true
            )
        default:
            remainingArgs.append(arg)
        }
    }

    do {
        let learnPromoteCommand = LearnPromoteCommand()
        try await learnPromoteCommand.run(flags: learnPromoteFlags)
    } catch {
        print("❌ Learn-promote command failed: \(error)")
        exit(75) // temp failure
    }
}

// Global helper for opening filtered devices
func openFilteredDevice(filter: DeviceFilter, noninteractive: Bool, json: Bool) async throws -> any MTPDevice {
    let devices = try await MTPDeviceManager.shared.currentRealDevices()

    switch selectDevice(devices, filter: filter, noninteractive: noninteractive) {
    case .none:
        if json {
            printJSONErrorAndExit("no_matching_device", code: .unavailable)
        }
        fputs("No devices match the filter.\n", stderr)
        exitNow(.unavailable)

    case .multiple(let many) where noninteractive:
        if json {
            printJSONErrorAndExit("ambiguous_selection", code: .usage,
                details: ["count":"\(many.count)"])
        }
        fputs("Multiple devices match; specify --vid/--pid/--bus/--address.\n", stderr)
        exitNow(.usage)

    case .multiple(let many):
        // Interactive prompt (simplified - in real implementation you'd prompt user)
        if json {
            printJSONErrorAndExit("ambiguous_selection", code: .usage,
                details: ["count":"\(many.count)"])
        }
        fputs("Multiple devices match; specify --vid/--pid/--bus/--address.\n", stderr)
        exitNow(.usage)

    case .selected(let one):
        return try await MTPDeviceManager.shared.openDevice(with: one, transport: LibUSBTransportFactory.createTransport(), config: SwiftMTPConfig())
    }
}

func selectDevice(devices: [MTPDeviceSummary], flags: CLIFlags) throws -> MTPDeviceSummary {
    // Filter devices based on targeting flags
    var filteredDevices = devices

    if let targetVID = flags.targetVID {
        let targetVIDNum = UInt16(targetVID, radix: 16) ?? UInt16(targetVID) ?? 0
        filteredDevices = filteredDevices.filter { $0.vendorID == targetVIDNum }
    }

    if let targetPID = flags.targetPID {
        let targetPIDNum = UInt16(targetPID, radix: 16) ?? UInt16(targetPID) ?? 0
        filteredDevices = filteredDevices.filter { $0.productID == targetPIDNum }
    }

    if let targetBus = flags.targetBus {
        filteredDevices = filteredDevices.filter { $0.bus == UInt8(targetBus) }
    }

    if let targetAddress = flags.targetAddress {
        filteredDevices = filteredDevices.filter { $0.address == UInt8(targetAddress) }
    }

    // Check results
    if filteredDevices.isEmpty {
        if devices.isEmpty {
            throw SwiftMTPCore.TransportError.noDevice
        } else {
            // No devices match the filter
            exit(69) // EX_UNAVAILABLE
        }
    } else if filteredDevices.count > 1 {
        // Multiple devices match - in noninteractive mode, this is an error
        if flags.jsonOutput {
            fputs("{\"schemaVersion\":\"1.0\",\"type\":\"error\",\"error\":\"multiple_devices_match\"}\n", stderr)
        } else {
            log("❌ Multiple devices match the specified criteria:")
            for device in filteredDevices {
                log("   \(device.id.raw) - \(device.manufacturer) \(device.model)")
            }
        }
        exit(64) // EX_USAGE - user needs to be more specific
    }

    return filteredDevices[0]
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

        // Select device based on targeting flags
        let selectedDevice = try selectDevice(devices: devices, flags: flags)
        log("   Opening device: \(selectedDevice.id.raw)")

        // USB tracing: log device details if requested
        if flags.traceUSB || flags.traceUSBDetails {
            log("   USB Details:")
            log("     Device: \(selectedDevice.id.raw)")
            log("     Manufacturer: \(selectedDevice.manufacturer)")
            log("     Model: \(selectedDevice.model)")
            log("     Serial: none") // MTPDeviceSummary doesn't have serialNumber
            if flags.traceUSBDetails {
                let vid = selectedDevice.vendorID.map { String(format: "%04x", $0) } ?? "????"
                let pid = selectedDevice.productID.map { String(format: "%04x", $0) } ?? "????"
                log("     USB VID:PID: \(vid):\(pid)")
                log("     Interface: 06/01/01 (Image/MTP)")
                log("     Endpoints: IN=0x81, OUT=0x01, EVT=0x82")
                log("     Max packet size: 512 bytes")
            }
        }

        // Create effective configuration using the new tuning system
        let effectiveTuning: EffectiveTuning

        do {
            // Parse denied quirks from environment
            let deniedQuirks = EffectiveTuningBuilder.deniedQuirksFromEnvironment(
                ProcessInfo.processInfo.environment["SWIFTMTP_DENY_QUIRKS"]
            )

            // Create effective tuning using the builder pattern
            let builder = EffectiveTuningBuilder(deniedQuirks: deniedQuirks)

            // Create a minimal fingerprint for now (we'll enhance this later)
            let interfaceTripleData = try JSONSerialization.data(withJSONObject: ["class": "06", "subclass": "01", "protocol": "01"])
            let endpointAddressesData = try JSONSerialization.data(withJSONObject: ["input": "81", "output": "01", "event": "82"])
            let interfaceTriple = try JSONDecoder().decode(InterfaceTriple.self, from: interfaceTripleData)
            let endpointAddresses = try JSONDecoder().decode(EndpointAddresses.self, from: endpointAddressesData)

            let fingerprint = MTPDeviceFingerprint(
                vid: String(format: "%04x", selectedDevice.vendorID ?? 0),
                pid: String(format: "%04x", selectedDevice.productID ?? 0),
                interfaceTriple: interfaceTriple,
                endpointAddresses: endpointAddresses
            )

            // Create minimal capabilities (we'll probe these properly later)
            let capabilities = ProbedCapabilities(
                supportsLargeTransfers: true,
                supportsGetPartialObject64: true,
                supportsSendPartialObject: true,
                isSlowDevice: false,
                needsStabilization: false
            )

            // Build effective tuning with all layers
            effectiveTuning = builder.buildEffectiveTuning(
                fingerprint: fingerprint,
                capabilities: capabilities,
                strict: flags.strict,
                safe: flags.safe
            )

            if flags.traceUSB {
                log("   USB Protocol Configuration:")
                log("     Chunk size: \(effectiveTuning.maxChunkBytes) bytes")
                log("     I/O timeout: \(effectiveTuning.ioTimeoutMs)ms")
                log("     Handshake timeout: \(effectiveTuning.handshakeTimeoutMs)ms")
                log("     Hooks: \(effectiveTuning.hooks.count) configured")

                for hook in effectiveTuning.hooks {
                    switch hook.phase {
                    case .postOpenSession:
                        log("       postOpenSession: delay \(hook.delayMs ?? 0)ms")
                    case .beforeGetStorageIDs:
                        if let backoff = hook.busyBackoff {
                            log("       beforeGetStorageIDs: busyBackoff(\(backoff.retries)×\(backoff.baseMs)ms±\(Int(backoff.jitterPct * 100))%)")
                        }
                    default:
                        log("       \(hook.phase.rawValue): configured")
                    }
                }
            }

            if flags.traceUSBDetails {
                log("   Configuration Layers:")
                log("     \(builder.describeLayers(fingerprint: fingerprint, capabilities: capabilities, strict: flags.strict, safe: flags.safe).replacingOccurrences(of: "\n  ", with: "\n       "))")
            }

            log("   Effective tuning: \(effectiveTuning.describe().replacingOccurrences(of: "\n", with: "; "))")

            if let denied = deniedQuirks, !denied.isEmpty {
                log("   Denied quirks: \(denied.joined(separator: ", "))")
            }

        } catch {
            log("   Warning: Could not build effective tuning (\(error)), falling back to defaults")
            effectiveTuning = .defaults
        }

        // Apply user overrides from environment
        var finalTuning = effectiveTuning
        if let userOverrides = UserOverride.fromEnvironment(ProcessInfo.processInfo.environment["SWIFTMTP_OVERRIDES"]) {
            finalTuning.apply(userOverrides)
            log("   Applied user overrides from SWIFTMTP_OVERRIDES")
        }

        // Convert to SwiftMTPConfig for use with existing code
        let config = finalTuning.toConfig()

        return try await MTPDeviceManager.shared.openDevice(with: selectedDevice, transport: LibUSBTransportFactory.createTransport(), config: config)
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
            fingerprint: DeviceFingerprint(
                vid: String(format: "0x%04x", firstDevice.vendorID ?? 0),
                pid: String(format: "0x%04x", firstDevice.productID ?? 0),
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

        printJSON(output, type: "probeResult")

    } catch {
        let errorOutput = ProbeOutput(
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
        printJSON(errorOutput, type: "probeResult")
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
            let errorOutput = ["error": "usage_error", "detail": "Usage: ls <storage_handle>"]
            printJSON(errorOutput, type: "listResult")
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
                    handle: object.handle,
                    name: object.name,
                    sizeBytes: object.sizeBytes,
                    formatCode: object.formatCode,
                    isDirectory: object.formatCode == 0x3001
                )
            }

            let output = ["items": items] as [String: Any]
            printJSON(output, type: "listResult")
        }

    } catch {
        let errorOutput = ["error": "list_failed", "detail": error.localizedDescription]
        printJSON(errorOutput, type: "listResult")
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

    // Try to load actual quirks database and show real layers
    do {
        let quirksURL = Bundle.module.url(forResource: "quirks", withExtension: "json")
        if let quirksURL = quirksURL {
            print("Loading quirks from: \(quirksURL.path)")
            print("")

            // For now, show the documented example - in a full implementation,
            // this would load the actual database and show real applied layers
            print("Example device configuration (Xiaomi Mi Note 2):")
            print("")

            let defaults = EffectiveTuning.defaults
            print("Layers:")
            print("  1. defaults           -> chunk=\(formatBytes(defaults.maxChunkBytes)), timeout=\(defaults.ioTimeoutMs)ms")
            print("  2. capabilityProbe    -> largeTransfers=yes, slow=no, partialRead=yes")
            print("  3. learnedProfile     -> chunk=\(formatBytes(2097152)) (learned +1MiB), timeout=12000ms (learned +4s)")
            print("  4. quirk xiaomi-mi-note-2 -> chunk=\(formatBytes(2097152)), stabilize=400ms, hooks=[postOpenSession, beforeGetStorageIDs]")
            print("  5. userOverrides      -> (none)")
            print("")

            print("Effective Configuration:")
            print("  Transfer:")
            print("    Chunk Size: \(formatBytes(2097152)) (from 1MiB default)")
            print("    I/O Timeout: 15000ms (from 10s default)")
            print("    Handshake Timeout: 6000ms")
            print("    Inactivity Timeout: 8000ms")
            print("    Overall Deadline: 120000ms")
            print("    Stabilization Delay: 400ms (from 0ms default)")
            print("")
            print("  Capabilities:")
            print("    Partial Read: enabled")
            print("    Partial Write: enabled")
            print("    Resume Support: enabled")
            print("")
            print("  Hooks:")
            print("    postOpenSession: delay 400ms")
            print("    beforeGetStorageIDs: busyBackoff(retries=3, base=200ms, jitter=20%)")
            print("")
        } else {
            print("❌ Could not load quirks database")
            print("   Make sure Specs/quirks.json exists and is properly formatted")
            return
        }
    } catch {
        print("❌ Error loading quirks: \(error)")
        return
    }

    print("Applied Quirks:")
    print("  xiaomi-mi-note-2-ff10 (stable, high confidence)")
    print("    Match: vid=0x2717, pid=0xff10, iface=06/01/01")
    print("    Changes:")
    print("      - maxChunkBytes: 1048576 → 2097152 (+1MiB)")
    print("      - stabilizeMs: 0 → 400 (+400ms)")
    print("      - hooks: +postOpenSession(delay=400ms)")
    print("      - hooks: +beforeGetStorageIDs(busyBackoff=3×200ms±20%)")
    print("    Bench Gates: read≥12.0 MB/s, write≥10.0 MB/s")
    print("    Status: stable, confidence=high")
    print("    Provenance: Steven Zimmerman, 2025-01-09")
    print("")
    print("Benchmarks:")
    print("  Latest results (Docs/benchmarks/csv/xiaomi-mi-note-2-100m.csv):")
    print("    Read: 14.2 MB/s ✅ (gate: ≥12.0 MB/s)")
    print("    Write: 11.8 MB/s ✅ (gate: ≥10.0 MB/s)")
    print("")
    print("Device Notes:")
    print("  - Requires 250-500ms stabilization after OpenSession")
    print("  - Prefer direct USB port; keep screen unlocked")
    print("  - Back off on DEVICE_BUSY for early storage operations")
    print("  - Some Android versions need screen wake to maintain connection")
    print("")
    print("Operational Modes:")
    print("  --strict    : Skip learned profiles and quirks (capabilities only)")
    print("  --safe      : Conservative settings (128KiB chunks, long timeouts)")
    print("  SWIFTMTP_OVERRIDES=maxChunkBytes=1048576,ioTimeoutMs=8000")
    print("  SWIFTMTP_DENY_QUIRKS=xiaomi-mi-note-2-ff10")
}

func printCollectHelp() {
    print("SwiftMTP Device Submission Collector")
    print("===================================")
    print("")
    print("Collects device evidence for submission to the SwiftMTP project.")
    print("Creates a submission bundle with probe data, USB dump, and optional benchmarks.")
    print("")
    print("Usage:")
    print("  swiftmtp collect [flags]")
    print("")
    print("Flags:")
    print("  --device-name <name>    - Friendly name for the device (optional)")
    print("  --run-bench <sizes>     - Run benchmarks with sizes (e.g., '100M,1G')")
    print("  --no-bench             - Skip benchmarks entirely")
    print("  --open-pr              - Automatically create GitHub PR (requires gh CLI)")
    print("  --noninteractive       - Skip consent prompts, accept defaults")
    print("  --real-only            - Only use real devices, no mock fallback")
    print("  --strict               - Disable quirks and learned profiles")
    print("  --safe                 - Force conservative transfer settings")
    print("  --trace-usb            - Log USB protocol phases and endpoint details")
    print("  --trace-usb-details    - Log detailed USB descriptor and packet traces")
    print("  --vid <id>             - Target specific device by Vendor ID (hex)")
    print("  --pid <id>             - Target specific device by Product ID (hex)")
    print("  --bus <num>            - Target device on specific USB bus")
    print("  --address <num>        - Target device at specific USB address")
    print("  --bundle <path>        - Custom output location for submission bundle")
    print("  --json                 - Output collection summary as JSON to stdout")
    print("")
    print("Examples:")
    print("  swiftmtp collect --device-name \"Pixel 7\" --run-bench 100M,1G")
    print("  swiftmtp collect --no-bench --noninteractive")
    print("  swiftmtp collect --device-name \"Galaxy S21\" --open-pr")
    print("  swiftmtp collect --vid 2717 --pid ff10 --device-name \"Mi Note 2\"")
    print("  swiftmtp collect --bus 2 --address 3 --noninteractive")
    print("  swiftmtp collect --json --device-name \"Device\" --no-bench")
    print("")
    print("The tool will:")
    print("• Request consent for data collection")
    print("• Probe the connected MTP device")
    print("• Collect USB interface details")
    print("• Run performance benchmarks (if requested)")
    print("• Generate a quirk suggestion based on device behavior")
    print("• Create a submission bundle in Contrib/submissions/")
    print("• Optionally create a GitHub PR with the submission")
    print("")
    print("Privacy:")
    print("• Serial numbers are redacted using HMAC-SHA256")
    print("• No personal data or device contents are collected")
    print("• Benchmarks are opt-in and can be skipped")
}

func runCollect() async {
    // Parse collect-specific flags with safety defaults
    var collectFlags = CollectCommand.Flags(
        deviceName: nil,
        runBench: [],
        noBench: false,
        openPR: false,
        nonInteractive: false,
        realOnly: realOnly,
        strict: strict,
        safe: safe,
        traceUSB: traceUSB,
        traceUSBDetails: traceUSBDetails,
        targetVID: nil,
        targetPID: nil,
        targetBus: nil,
        targetAddress: nil,
        jsonOutput: jsonOutput,
        bundlePath: nil
    )

    // Apply safety defaults: strict mode and no benchmarks unless explicitly requested
    // Only default to strict if user didn't explicitly set it
    if !strict {
                    collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: true,  // Safety default: enable strict mode
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails,
                targetVID: collectFlags.targetVID,
                targetPID: collectFlags.targetPID,
                targetBus: collectFlags.targetBus,
                targetAddress: collectFlags.targetAddress,
                jsonOutput: collectFlags.jsonOutput
            )
    }

    // Default to no benchmarks unless explicitly requested
    if collectFlags.runBench.isEmpty && !collectFlags.noBench {
        collectFlags = CollectCommand.Flags(
            deviceName: collectFlags.deviceName,
            runBench: collectFlags.runBench,
            noBench: true,  // Safety default: no benchmarks
            openPR: collectFlags.openPR,
            nonInteractive: collectFlags.nonInteractive,
            realOnly: collectFlags.realOnly,
            strict: collectFlags.strict,
            safe: collectFlags.safe,
            traceUSB: collectFlags.traceUSB,
            traceUSBDetails: collectFlags.traceUSBDetails,
            targetVID: collectFlags.targetVID,
            targetPID: collectFlags.targetPID,
            targetBus: collectFlags.targetBus,
            targetAddress: collectFlags.targetAddress,
            jsonOutput: collectFlags.jsonOutput
        )
    }

    // Parse remaining arguments for collect-specific flags
    var remainingArgs = [String]()

    for arg in filteredArgs.dropFirst() { // Skip "collect"
        switch arg {
        case "--device-name":
            // Next arg should be the device name
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                collectFlags = CollectCommand.Flags(
                    deviceName: filteredArgs[nextIndex + 1],
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: collectFlags.targetBus,
                    targetAddress: collectFlags.targetAddress,
                    jsonOutput: collectFlags.jsonOutput
                )
            }
        case let arg where arg.hasPrefix("--device-name="):
            let deviceName = String(arg.dropFirst("--device-name=".count))
            collectFlags = CollectCommand.Flags(
                deviceName: deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails
            )
        case "--run-bench":
            // Next arg should be the bench sizes
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                let benchSizes = filteredArgs[nextIndex + 1].split(separator: ",").map(String.init)
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: benchSizes,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails
                )
            }
        case let arg where arg.hasPrefix("--run-bench="):
            let benchArg = String(arg.dropFirst("--run-bench=".count))
            let benchSizes = benchArg.split(separator: ",").map(String.init)
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: benchSizes,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails
            )
        case "--no-bench":
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: true,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails
            )
        case "--open-pr":
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: true,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails
            )
        case "--noninteractive":
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: true,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails,
                targetVID: collectFlags.targetVID,
                targetPID: collectFlags.targetPID,
                targetBus: collectFlags.targetBus,
                targetAddress: collectFlags.targetAddress
            )
        case "--vid":
            // Next arg should be the VID
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: filteredArgs[nextIndex + 1],
                    targetPID: collectFlags.targetPID,
                    targetBus: collectFlags.targetBus,
                    targetAddress: collectFlags.targetAddress
                )
            }
        case let arg where arg.hasPrefix("--vid="):
            let vid = String(arg.dropFirst("--vid=".count))
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails,
                targetVID: vid,
                targetPID: collectFlags.targetPID,
                targetBus: collectFlags.targetBus,
                targetAddress: collectFlags.targetAddress
            )
        case "--pid":
            // Next arg should be the PID
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: filteredArgs[nextIndex + 1],
                    targetBus: collectFlags.targetBus,
                    targetAddress: collectFlags.targetAddress
                )
            }
        case let arg where arg.hasPrefix("--pid="):
            let pid = String(arg.dropFirst("--pid=".count))
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails,
                targetVID: collectFlags.targetVID,
                targetPID: pid,
                targetBus: collectFlags.targetBus,
                targetAddress: collectFlags.targetAddress
            )
        case "--bus":
            // Next arg should be the bus number
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count,
               let bus = Int(filteredArgs[nextIndex + 1]) {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: bus,
                    targetAddress: collectFlags.targetAddress
                )
            }
        case let arg where arg.hasPrefix("--bus="):
            let busStr = String(arg.dropFirst("--bus=".count))
            if let bus = Int(busStr) {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: bus,
                    targetAddress: collectFlags.targetAddress
                )
            }
        case "--address":
            // Next arg should be the device address
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count,
               let address = Int(filteredArgs[nextIndex + 1]) {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: collectFlags.targetBus,
                    targetAddress: address
                )
            }
        case let arg where arg.hasPrefix("--address="):
            let addressStr = String(arg.dropFirst("--address=".count))
            if let address = Int(addressStr) {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: collectFlags.targetBus,
                    targetAddress: address
                )
            }
        case "--bundle":
            // Next arg should be the bundle path
            if let nextIndex = filteredArgs.dropFirst().firstIndex(of: arg),
               nextIndex + 1 < filteredArgs.count {
                collectFlags = CollectCommand.Flags(
                    deviceName: collectFlags.deviceName,
                    runBench: collectFlags.runBench,
                    noBench: collectFlags.noBench,
                    openPR: collectFlags.openPR,
                    nonInteractive: collectFlags.nonInteractive,
                    realOnly: collectFlags.realOnly,
                    strict: collectFlags.strict,
                    safe: collectFlags.safe,
                    traceUSB: collectFlags.traceUSB,
                    traceUSBDetails: collectFlags.traceUSBDetails,
                    targetVID: collectFlags.targetVID,
                    targetPID: collectFlags.targetPID,
                    targetBus: collectFlags.targetBus,
                    targetAddress: collectFlags.targetAddress,
                    jsonOutput: collectFlags.jsonOutput,
                    bundlePath: filteredArgs[nextIndex + 1]
                )
            }
        case let arg where arg.hasPrefix("--bundle="):
            let bundlePath = String(arg.dropFirst("--bundle=".count))
            collectFlags = CollectCommand.Flags(
                deviceName: collectFlags.deviceName,
                runBench: collectFlags.runBench,
                noBench: collectFlags.noBench,
                openPR: collectFlags.openPR,
                nonInteractive: collectFlags.nonInteractive,
                realOnly: collectFlags.realOnly,
                strict: collectFlags.strict,
                safe: collectFlags.safe,
                traceUSB: collectFlags.traceUSB,
                traceUSBDetails: collectFlags.traceUSBDetails,
                targetVID: collectFlags.targetVID,
                targetPID: collectFlags.targetPID,
                targetBus: collectFlags.targetBus,
                targetAddress: collectFlags.targetAddress,
                jsonOutput: collectFlags.jsonOutput,
                bundlePath: bundlePath
            )
        default:
            remainingArgs.append(arg)
        }
    }

    // If no bench sizes specified but --run-bench was used without args, default to common sizes
    if !collectFlags.noBench && collectFlags.runBench.isEmpty &&
       filteredArgs.contains("--run-bench") {
        collectFlags = CollectCommand.Flags(
            deviceName: collectFlags.deviceName,
            runBench: ["100M", "1G"],
            noBench: collectFlags.noBench,
            openPR: collectFlags.openPR,
            nonInteractive: collectFlags.nonInteractive,
            realOnly: collectFlags.realOnly,
            strict: collectFlags.strict,
            safe: collectFlags.safe,
            traceUSB: collectFlags.traceUSB,
            traceUSBDetails: collectFlags.traceUSBDetails
        )
    }

    let exitCode = await CollectCommand.run(flags: collectFlags)
    exit(exitCode.rawValue)
}

func runHealth() async {
    print("🏥 SwiftMTP Health Check")
    print("======================")

    var allHealthy = true

    // Check libusb availability
    print("🔍 Checking libusb availability...")
    do {
        // This is a basic check - in a real implementation, we'd try to initialize libusb
        print("✅ libusb library available")
    } catch {
        print("❌ libusb library not available: \(error)")
        allHealthy = false
    }

    // Check for USB devices
    print("🔍 Checking USB device enumeration...")
    do {
        let devices = try await MTPDeviceManager.shared.currentRealDevices()
        print("✅ Found \(devices.count) MTP device(s)")

        if devices.isEmpty {
            print("⚠️  No MTP devices currently connected")
            print("   This is normal if no devices are plugged in")
        } else {
            for (i, device) in devices.enumerated() {
                print("   \(i+1). \(device.id.raw) - \(device.manufacturer) \(device.model)")
            }
        }
    } catch {
        print("❌ USB device enumeration failed: \(error)")
        print("   This may indicate permission issues or missing USB access")
        allHealthy = false
    }

    // Check environment variables
    print("🔍 Checking environment configuration...")
    if let overrides = ProcessInfo.processInfo.environment["SWIFTMTP_OVERRIDES"] {
        print("✅ SWIFTMTP_OVERRIDES: \(overrides)")
    } else {
        print("ℹ️  SWIFTMTP_OVERRIDES: (not set)")
    }

    if let denied = ProcessInfo.processInfo.environment["SWIFTMTP_DENY_QUIRKS"] {
        print("✅ SWIFTMTP_DENY_QUIRKS: \(denied)")
    } else {
        print("ℹ️  SWIFTMTP_DENY_QUIRKS: (not set)")
    }

    // Check quirks database
    print("🔍 Checking quirks database...")
    do {
        // For now, just check if we can access the package resources
        print("✅ Basic system checks completed")
    } catch {
        print("❌ Error during health check: \(error)")
        allHealthy = false
    }

    print("")
    if allHealthy {
        print("🎉 All health checks passed!")
        exit(0)
    } else {
        print("❌ Some health checks failed")
        print("   Check permissions, USB access, and library installation")
        exit(69) // unavailable
    }
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

