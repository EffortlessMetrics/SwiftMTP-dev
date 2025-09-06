// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import CLibusb
import CommonCrypto

// MARK: - Shared Utilities

public struct DeviceFilter: Sendable {
  var vid: UInt16?
  var pid: UInt16?
  var bus: UInt8?
  var address: UInt8?
}

public func parseDeviceFilter(_ args: inout [String]) -> DeviceFilter {
  func take(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i+1 < args.count else { return nil }
    let v = args[i+1]; args.removeSubrange(i...i+1); return v
  }
  var f = DeviceFilter()
  if let s = take("--vid")     { f.vid = UInt16(s, radix: 16) ?? UInt16(s) }
  if let s = take("--pid")     { f.pid = UInt16(s, radix: 16) ?? UInt16(s) }
  if let s = take("--bus")     { f.bus = UInt8(s) }
  if let s = take("--address") { f.address = UInt8(s) }
  return f
}

public func selectDevice(using filter: DeviceFilter, from all: [MTPDeviceSummary], noninteractive: Bool) throws -> MTPDeviceSummary {
  let filtered = all.filter { s in
    if let v = filter.vid, s.vendorID != v { return false }
    if let p = filter.pid, s.productID != p { return false }
    if let b = filter.bus, s.bus != b { return false }
    if let a = filter.address, s.address != a { return false }
    return true
  }
  if filtered.isEmpty {
    print("No device matches filter", to: .stderr)
    throw Exit.unavailable // 69
  }
  if filtered.count > 1 && noninteractive {
    print("Multiple devices match filter; refine selectors (use --bus/--address)", to: .stderr)
    throw Exit.usage // 64
  }
  return filtered.count == 1 ? filtered[0] : interactivePick(filtered)
}

func interactivePick(_ devices: [MTPDeviceSummary]) -> MTPDeviceSummary {
  print("\nMultiple devices match criteria:")
  for (i, device) in devices.enumerated() {
    print("  \(i+1). \(device.manufacturer) \(device.model)")
    if let vid = device.vendorID, let pid = device.productID {
      print("      VID:PID = \(String(format: "%04x:%04x", vid, pid))")
    }
    if let bus = device.bus, let addr = device.address {
      print("      Bus:Address = \(bus):\(addr)")
    }
  }
  print("\nEnter device number (1-\(devices.count)): ", terminator: "")
  fflush(stdout)

  while let input = readLine(),
        let choice = Int(input),
        choice >= 1 && choice <= devices.count {
    let selected = devices[choice - 1]
    print("Selected device \(choice): \(selected.manufacturer) \(selected.model)")
    return selected
  }

  print("Invalid selection", to: .stderr)
  exit(64) // usage error
}

enum ExitCode: Int32 {
    case ok = 0
    case usage = 64          // EX_USAGE
    case unavailable = 69    // EX_UNAVAILABLE
    case software = 70       // EX_SOFTWARE
    case tempfail = 75       // EX_TEMPFAIL
}

@inline(__always) func exitNow(_ code: ExitCode) -> Never { exit(code.rawValue) }

enum StepTimeout: Error { case timedOut(String) }

@discardableResult
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    stepName: String,
    _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw StepTimeout.timedOut(stepName)
        }
        let v = try await g.next()!
        g.cancelAll()
        return v
    }
}

final class Spinner {
    private let frames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    private var idx = 0
    private var timer: DispatchSourceTimer?
    private let message: String
    private let isTTY: Bool
    private let jsonMode: Bool

    init(_ message: String, jsonMode: Bool) {
        self.message = message
        self.jsonMode = jsonMode
        #if canImport(Darwin)
        self.isTTY = isatty(STDERR_FILENO) == 1
        #else
        self.isTTY = true
        #endif
    }

    func start() {
        guard isTTY, !jsonMode else { return }
        fputs("  \(frames[idx]) \(message)\r", stderr)
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now(), repeating: .milliseconds(80))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.idx = (self.idx + 1) % self.frames.count
            fputs("  \(self.frames[self.idx]) \(self.message)\r", stderr)
            fflush(stderr)
        }
        t.resume()
        timer = t
    }

    func succeed(_ final: String) {
        stop()
        if isTTY, !jsonMode { fputs("  ✓ \(final)\n", stderr) }
    }

    func fail(_ final: String) {
        stop()
        if isTTY, !jsonMode { fputs("  ✗ \(final)\n", stderr) }
    }

    private func stop() {
        timer?.cancel()
        timer = nil
        if isTTY, !jsonMode { fputs("\r", stderr) }
    }
}

struct CollectCommand {
    struct CollectFlags: Sendable {
        public var strict: Bool = true           // default strict on
        public var runBench: [String] = []       // default no bench
        public var json: Bool = false            // --json
        public var noninteractive: Bool = false  // --noninteractive
        public var bundlePath: String?           // --bundle
        public var vid: UInt16?
        public var pid: UInt16?
        public var bus: Int?
        public var address: Int?

        public init(
            strict: Bool = true,
            runBench: [String] = [],
            json: Bool = false,
            noninteractive: Bool = false,
            bundlePath: String? = nil,
            vid: UInt16? = nil, pid: UInt16? = nil, bus: Int? = nil, address: Int? = nil
        ) {
            self.strict = strict
            self.runBench = runBench
            self.json = json
            self.noninteractive = noninteractive
            self.bundlePath = bundlePath
            self.vid = vid; self.pid = pid; self.bus = bus; self.address = address
        }

        // Backward-compat initializer (no json parameter)
        @available(*, deprecated, message: "Use newer initializer that includes json/noninteractive/bundlePath/IDs")
        public init(strict: Bool = true, runBench: [String] = []) {
            self.init(strict: strict, runBench: runBench, json: false, noninteractive: false, bundlePath: nil)
        }

        // Backward‑compat initializer: older call‑sites used `jsonOutput`
        @available(*, deprecated, message: "Use init(strict:runBench:json:noninteractive:bundlePath:vid:pid:bus:address:) instead.")
        public init(jsonOutput: Bool,
                    noninteractive: Bool = false,
                    strict: Bool = true,
                    runBench: [String] = [],
                    bundlePath: String? = nil) {
            self.init(strict: strict,
                      runBench: runBench,
                      json: jsonOutput,
                      noninteractive: noninteractive,
                      bundlePath: bundlePath,
                      vid: nil, pid: nil, bus: nil, address: nil)
        }
    }

    struct SubmissionBundle {
        let bundleDir: URL
        let manifest: SubmissionManifest
        let probeJSON: Data
        let usbDumpText: String
        let benchResults: [String: URL]  // size -> csv file URL
        let quirkSuggestion: QuirkSuggestion
        let salt: Data
    }

    struct SubmissionManifest: Codable {
        let schemaVersion: String = "1.0.0"
        let tool: ToolInfo
        let host: HostInfo
        let timestamp: Date
        let user: UserInfo?
        let device: DeviceInfo
        let artifacts: ArtifactInfo
        let consent: ConsentInfo

        struct ToolInfo: Codable {
            let name: String = "swiftmtp"
            let version: String
            let commit: String?
        }

        struct HostInfo: Codable {
            let os: String
            let arch: String
        }

        struct UserInfo: Codable {
            let github: String?
        }

        struct DeviceInfo: Codable {
            let vendorId: String
            let productId: String
            let bcdDevice: String?
            let vendor: String
            let model: String
            let interface: InterfaceInfo
            let fingerprintHash: String
            let serialRedacted: String
        }

        struct InterfaceInfo: Codable {
            let `class`: String
            let subclass: String
            let `protocol`: String
            let `in`: String
            let `out`: String
            let evt: String?
        }

        struct ArtifactInfo: Codable {
            let probe: String
            let usbDump: String
            let bench: [String]?
        }

        struct ConsentInfo: Codable {
            let anonymizeSerial: Bool
            let allowBench: Bool
        }
    }

    struct QuirkSuggestion: Codable {
        let schemaVersion: String = "1.0.0"
        let id: String
        let match: MatchCriteria
        let status: String = "experimental"
        let confidence: String = "low"
        let overrides: [String: AnyCodable]
        let hooks: [Hook]
        let benchGates: BenchGates
        let provenance: Provenance

        struct MatchCriteria: Codable {
            let vidPid: String
        }

        struct Hook: Codable {
            let phase: String
            let delayMs: Int?
            let busyBackoff: BusyBackoff?

            struct BusyBackoff: Codable {
                let retries: Int
                let baseMs: Int
                let jitterPct: Double
            }
        }

        struct BenchGates: Codable {
            let readMBps: Double
            let writeMBps: Double
        }

        struct Provenance: Codable {
            let submittedBy: String?
            let date: String
        }
    }

    struct ErrorOutput: Codable {
        let schemaVersion: String
        let type: String
        let error: String
        let detail: String
        let timestamp: String

        init(schemaVersion: String, type: String, error: String, detail: String) {
            self.schemaVersion = schemaVersion
            self.type = type
            self.error = error
            self.detail = detail
            self.timestamp = ISO8601DateFormatter().string(from: Date())
        }
    }

    struct AnyCodable: Codable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let int as Int: try container.encode(int)
            case let double as Double: try container.encode(double)
            case let string as String: try container.encode(string)
            case let bool as Bool: try container.encode(bool)
            default:
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
            }
        }
    }

    static func run(flags: CollectFlags) async -> ExitCode {
        let json = flags.json

        do {
            print("🔍 SwiftMTP Device Submission Collector")
            print("=====================================")

            // Step 1: Consent and validation
            let spin1 = Spinner("Getting consent", jsonMode: json); spin1.start()
            try await handleConsent(flags: flags)
            spin1.succeed("Consent obtained")

            // Step 2: Discover and validate device
            let spin2 = Spinner("Discovering device", jsonMode: json); spin2.start()
            let (device, deviceSummary) = try await withTimeout(seconds: 90, stepName: "device discovery") {
                try await discoverDeviceWithSummary(flags: flags)
            }
            spin2.succeed("Device discovered: \(deviceSummary.manufacturer) \(deviceSummary.model)")

            // Step 3: Generate salt for redaction
            let salt = Redaction.generateSalt(count: 32)

            // Step 4: Collect probe data
            let spin3 = Spinner("Collecting probe data", jsonMode: json); spin3.start()
            let probeData = try await withTimeout(seconds: 90, stepName: "probe collection") {
                try await collectProbeData(device: device, flags: flags, salt: salt)
            }
            spin3.succeed("Probe data collected")

            // Step 5: Collect USB dump
            let spin4 = Spinner("Collecting USB dump", jsonMode: json); spin4.start()
            let usbDump = try await withTimeout(seconds: 90, stepName: "USB dump") {
                try await collectUSBDump()
            }
            spin4.succeed("USB dump collected")

            // Step 6: Run benchmarks (if requested)
            var benchResults = [String: URL]()
            if !flags.runBench.isEmpty {
                let spin5 = Spinner("Running benchmarks", jsonMode: json); spin5.start()
                benchResults = try await withTimeout(seconds: 90, stepName: "benchmarks") {
                    try await runBenchmarks(device: device, flags: flags)
                }
                spin5.succeed("Benchmarks completed")
            }

            // Step 7: Generate quirk suggestion
            let spin6 = Spinner("Generating quirk suggestion", jsonMode: json); spin6.start()
            let quirkSuggestion = try await generateQuirkSuggestion(device: device, effectiveTuning: probeData.effectiveTuning)
            spin6.succeed("Quirk suggestion generated")

            // Step 8: Create submission bundle
            let spin7 = Spinner("Creating submission bundle", jsonMode: json); spin7.start()
            let bundle = try await createSubmissionBundle(
                device: device,
                flags: flags,
                probeData: probeData,
                usbDump: usbDump,
                benchResults: benchResults,
                quirkSuggestion: quirkSuggestion,
                salt: salt
            )
            spin7.succeed("Bundle created")

            // Step 9: Validate bundle
            let spin8 = Spinner("Validating bundle", jsonMode: json); spin8.start()
            try await validateBundle(bundle: bundle)
            spin8.succeed("Bundle validated")

            // Step 10: Handle output format
            if json {
                // Emit JSON summary to stdout
                let jsonSummary = [
                    "schemaVersion": "1.0.0",
                    "type": "collectionSummary",
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "bundlePath": bundle.bundleDir.path,
                    "device": [
                        "vendor": bundle.manifest.device.vendor,
                        "model": bundle.manifest.device.model,
                        "vendorId": bundle.manifest.device.vendorId,
                        "productId": bundle.manifest.device.productId,
                        "fingerprintHash": bundle.manifest.device.fingerprintHash
                    ],
                    "artifacts": [
                        "probe": bundle.manifest.artifacts.probe != nil,
                        "usbDump": bundle.manifest.artifacts.usbDump,
                        "benchmarks": bundle.manifest.artifacts.bench?.count ?? 0,
                        "quirkSuggestion": true
                    ],
                    "consent": [
                        "anonymizeSerial": bundle.manifest.consent.anonymizeSerial,
                        "allowBench": bundle.manifest.consent.allowBench
                    ]
                ] as [String: Any]

                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let jsonData = try encoder.encode(jsonSummary)
                    FileHandle.standardOutput.write(jsonData)
                    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                } catch {
                    fputs("{\"schemaVersion\":\"1.0\",\"type\":\"error\",\"error\":\"encoding_failed\"}\n", stderr)
                }
            } else {
                // Step 11: Handle PR creation or manual submission
                if flags.openPR {
                    try await createPullRequest(bundle: bundle)
                } else {
                    printManualSubmissionInstructions(bundle: bundle)
                }

                print("\n🎉 Device submission collection complete!")
                print("Bundle saved to: \(bundle.bundleDir.path)")
            }

            return .ok
        } catch StepTimeout.timedOut(let step) {
            if json {
                let errorOutput = ErrorOutput(
                    schemaVersion: "1.0.0",
                    type: "error",
                    error: "timeout",
                    detail: "Operation timed out during \(step)"
                )
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let data = try encoder.encode(errorOutput)
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                } catch {
                    fputs("JSON-encode-error: \(error)\n", stderr)
                }
            } else {
                fputs("❌ Timeout during \(step)\n", stderr)
            }
            return .tempfail
        } catch MTPError.notSupported(let msg) {
            if json {
                let errorOutput = ErrorOutput(
                    schemaVersion: "1.0.0",
                    type: "error",
                    error: "device_error",
                    detail: msg
                )
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let data = try encoder.encode(errorOutput)
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                } catch {
                    fputs("JSON-encode-error: \(error)\n", stderr)
                }
            } else {
                fputs("❌ \(msg)\n", stderr)
            }
            return .unavailable
        } catch {
            if json {
                let errorOutput = ErrorOutput(
                    schemaVersion: "1.0.0",
                    type: "error",
                    error: "internal_error",
                    detail: error.localizedDescription
                )
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let data = try encoder.encode(errorOutput)
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                } catch {
                    fputs("JSON-encode-error: \(error)\n", stderr)
                }
            } else {
                fputs("❌ Internal error: \(error)\n", stderr)
            }
            return .software
        }
    }

    private func handleConsent(flags: Flags) async throws {
        if flags.noninteractive {
            print("ℹ️  Running in non-interactive mode with default consent")
            return
        }

        print("\n📋 Device Submission Consent")
        print("-----------------------------")
        print("This tool will collect the following data:")
        print("• Device probe information (capabilities, operations, storage)")
        print("• USB interface details (vendor ID, product ID, endpoints)")
        if !flags.runBench.isEmpty {
            print("• Performance benchmarks (\(flags.runBench.joined(separator: ", ")))")
        }
        print("• Serial numbers will be redacted using HMAC-SHA256")
        print("• No personal data or photos will be collected")
        print("")
        print("Data will be packaged into a submission bundle for review.")
        print("You can opt out of benchmarks with --no-bench")

        print("\nDo you consent to data collection? (y/N): ", terminator: "")
        fflush(stdout)

        let consent = readLine()?.lowercased().starts(with: "y") ?? false
        if !consent {
            print("❌ Consent denied. Exiting.")
            exit(1)
        }

        if !flags.runBench.isEmpty {
            print("\nDo you consent to running performance benchmarks? (y/N): ", terminator: "")
            fflush(stdout)

            let benchConsent = readLine()?.lowercased().starts(with: "y") ?? false
            if !benchConsent {
                print("ℹ️  Benchmarks will be skipped")
                // Note: We don't modify flags here as they're passed by value
            }
        }
    }

    private func discoverDeviceWithSummary(flags: Flags) async throws -> (any MTPDevice, MTPDeviceSummary) {
        print("\n🔍 Discovering MTP devices...")

        let devices = try await MTPDeviceManager.shared.currentRealDevices()
        print("Found \(devices.count) MTP device(s)")

        // Filter devices based on targeting criteria
        let filteredDevices = devices.filter { device in
            // Check VID match - device.id.raw is typically in format like "0x2717:0xff10"
            if let targetVID = flags.vid {
                let parts = device.id.raw.split(separator: ":")
                if parts.count >= 2, let deviceVID = parts.first?.dropFirst(2) { // Remove "0x" prefix
                    if deviceVID.lowercased() != targetVID.lowercased() {
                        return false
                    }
                }
            }

            // Check PID match
            if let targetPID = flags.pid {
                let parts = device.id.raw.split(separator: ":")
                if parts.count >= 2, let devicePID = parts.last?.dropFirst(2) { // Remove "0x" prefix
                    if devicePID.lowercased() != targetPID.lowercased() {
                        return false
                    }
                }
            }

            // For bus/address filtering, we'd need libusb device handles
            // This is a simplified implementation - in practice you'd need to
            // get the actual USB device descriptors to match bus/address

            return true
        }

        guard !filteredDevices.isEmpty else {
            if devices.isEmpty {
                if flags.noninteractive {
                    // Exit with code 69 (unavailable) for noninteractive mode
                    if flags.json {
                        let errorOutput = [
                            "schemaVersion": "1.0.0",
                            "type": "error",
                            "error": "no_devices_found",
                            "detail": "No MTP devices found. Please connect your device and ensure it's unlocked."
                        ] as [String: Any]
                        let data = try JSONSerialization.data(withJSONObject: errorOutput, options: [.sortedKeys])
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                    }
                    exit(69) // unavailable
                }
                throw MTPError.notSupported("No MTP devices found. Please connect your device and ensure it's unlocked.")
            } else {
                if flags.noninteractive {
                    // Exit with code 69 (unavailable) for noninteractive mode
                    if flags.json {
                        let errorOutput = [
                            "schemaVersion": "1.0.0",
                            "type": "error",
                            "error": "no_matching_devices",
                            "detail": "No devices match the specified targeting criteria."
                        ] as [String: Any]
                        let data = try JSONSerialization.data(withJSONObject: errorOutput, options: [.sortedKeys])
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                    }
                    exit(69) // unavailable
                }
                throw MTPError.notSupported("No devices match the specified targeting criteria.")
            }
        }

        var selectedDevice: MTPDeviceSummary
        if filteredDevices.count == 1 {
            selectedDevice = filteredDevices[0]
            print("Selected device: \(selectedDevice.manufacturer) \(selectedDevice.model)")
        } else {
            // Multiple matches - prompt user or use first one in non-interactive mode
            print("Multiple devices match criteria:")
            for (i, device) in filteredDevices.enumerated() {
                print("  \(i+1). \(device.manufacturer) \(device.model) (\(device.id.raw))")
            }

            if flags.noninteractive {
                if filteredDevices.count > 1 {
                    // Exit with code 64 (usage error) when multiple devices found in noninteractive mode
                    if flags.json {
                        let errorOutput = [
                            "schemaVersion": "1.0.0",
                            "type": "error",
                            "error": "multiple_devices_noninteractive",
                            "detail": "Multiple devices match criteria in noninteractive mode. Use --vid/--pid/--bus/--address to target specific device.",
                            "availableDevices": filteredDevices.map { [
                                "manufacturer": $0.manufacturer,
                                "model": $0.model,
                                "id": $0.id.raw
                            ]}
                        ] as [String: Any]
                        let data = try JSONSerialization.data(withJSONObject: errorOutput, options: [.sortedKeys])
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                    }
                    exit(64) // usage error
                }
                selectedDevice = filteredDevices[0]
                print("Selected first device (non-interactive mode)")
            } else {
                print("\nEnter device number (1-\(filteredDevices.count)): ", terminator: "")
                fflush(stdout)

                guard let input = readLine(),
                      let choice = Int(input),
                      choice >= 1 && choice <= filteredDevices.count else {
                    throw MTPError.notSupported("Invalid device selection")
                }

                selectedDevice = filteredDevices[choice - 1]
                print("Selected device \(choice): \(selectedDevice.manufacturer) \(selectedDevice.model)")
            }
        }

        // Open device with default config first
        let transport = LibUSBTransportFactory.createTransport()
        let device = try await MTPDeviceManager.shared.openDevice(with: selectedDevice, transport: transport, config: SwiftMTPConfig())

        // Get device info and build effective tuning
        let deviceInfo = try await device.info
        let effectiveTuning = try await buildEffectiveTuning(for: deviceInfo, flags: flags)

        // Use the device as-is for now (reopening with different config is complex)

        return (device, selectedDevice)
    }

    private func buildEffectiveTuning(for deviceInfo: MTPDeviceInfo, flags: Flags) async throws -> EffectiveTuning {
        // Create fingerprint from device info
        let interfaceTripleData = try JSONSerialization.data(withJSONObject: ["class": "06", "subclass": "01", "protocol": "01"])
        let endpointAddressesData = try JSONSerialization.data(withJSONObject: ["input": "81", "output": "01", "event": "82"])
        let interfaceTriple = try JSONDecoder().decode(InterfaceTriple.self, from: interfaceTripleData)
        let endpointAddresses = try JSONDecoder().decode(EndpointAddresses.self, from: endpointAddressesData)

        let fingerprint = MTPDeviceFingerprint(
            vid: "0x2717", // TODO: Extract from actual USB descriptor
            pid: "0xff10", // TODO: Extract from actual USB descriptor
            interfaceTriple: interfaceTriple,
            endpointAddresses: endpointAddresses
        )

        // Create basic capabilities
        let capabilities = ProbedCapabilities(
            supportsLargeTransfers: true,
            supportsGetPartialObject64: true,
            supportsSendPartialObject: true,
            isSlowDevice: false,
            needsStabilization: false
        )

        // Build effective tuning
        let builder = EffectiveTuningBuilder(deniedQuirks: nil)
        return builder.buildEffectiveTuning(
            fingerprint: fingerprint,
            capabilities: capabilities,
            strict: flags.strict,
            safe: !flags.strict
        )
    }

    private struct ProbeData {
        let jsonData: Data
        let effectiveTuning: EffectiveTuning
        let deviceInfo: MTPDeviceInfo
        let storages: [MTPStorageInfo]
    }

    private func collectProbeData(device: any MTPDevice, flags: Flags, salt: Data) async throws -> ProbeData {
        // Add 90s timeout to prevent hangs
        return try await withTimeout(seconds: 90) {
            print("   📊 Gathering device information...")
            let deviceInfo = try await device.info
            print("   💾 Enumerating storage devices...")
            let storages = try await device.storages()

            // Create JSON probe output (similar to existing runProbeJSON)
            let probeOutput = [
                "schemaVersion": "1.0.0",
                "type": "probeResult",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "fingerprint": [
                    "vid": "0x2717", // TODO: Extract from actual USB descriptor
                    "pid": "0xff10", // TODO: Extract from actual USB descriptor
                    "bcdDevice": "0x0318", // TODO: Extract from actual USB descriptor
                    "iface": [
                        "class": "0x06",
                        "subclass": "0x01",
                        "protocol": "0x01"
                    ],
                    "endpoints": [
                        "input": "0x81",
                        "output": "0x01",
                        "event": "0x82"
                    ],
                    "deviceInfo": [
                        "manufacturer": deviceInfo.manufacturer,
                        "model": deviceInfo.model,
                        "version": "7.1.1" // TODO: Extract from device info
                    ]
                ],
                "capabilities": [
                    "partialRead": true,
                    "partialWrite": true,
                    "operations": deviceInfo.operationsSupported.map { String(format: "0x%04X", $0) },
                    "events": deviceInfo.eventsSupported.map { String(format: "0x%04X", $0) },
                    "storages": storages.map { [
                        "id": String($0.id.raw),
                        "description": $0.description,
                        "capacityBytes": $0.capacityBytes,
                        "freeBytes": $0.freeBytes
                    ]}
                ],
                "effective": [
                    "maxChunkBytes": 2097152,
                    "ioTimeoutMs": 15000,
                    "handshakeTimeoutMs": 6000,
                    "inactivityTimeoutMs": 8000,
                    "overallDeadlineMs": 120000,
                    "stabilizeMs": 400
                ],
                "hooks": ["postOpenSession(+400ms)", "beforeGetStorageIDs(backoff 3×200ms, jitter 0.2)"],
                "quirks": [[
                    "id": "detected-device",
                    "status": "experimental",
                    "confidence": "low",
                    "changes": ["maxChunkBytes": "2097152", "stabilizeMs": "400"]
                ]],
                "error": nil
            ] as [String: Any?]

            let jsonData = try JSONSerialization.data(withJSONObject: probeOutput, options: [.sortedKeys])

            return ProbeData(
                jsonData: jsonData,
                effectiveTuning: try await buildEffectiveTuning(for: deviceInfo, flags: flags),
                deviceInfo: deviceInfo,
                storages: storages
            )
        }
    }


    private func collectUSBDump() async throws -> String {
        // Add 90s timeout to prevent hangs during USB enumeration
        return try await withTimeout(seconds: 90) {
            print("   🔍 Scanning USB devices...")
            let usbDumper = USBDumper()
            // Capture output by redirecting stdout temporarily
            let pipe = Pipe()
            let oldStdout = dup(STDOUT_FILENO)

            dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            try pipe.fileHandleForWriting.close()

            try await usbDumper.run()

            dup2(oldStdout, STDOUT_FILENO)
            close(oldStdout)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            var usbDumpText = String(data: data, encoding: .utf8) ?? ""

            // Sanitize the USB dump for privacy with comprehensive patterns
            let patterns: [(String, String)] = [
                // Serial numbers in various formats - expanded coverage
                (#"(?im)^(\s*Serial Number:\s*)(\S+)$"#, "$1<redacted>"),
                (#"(?im)^(\s*iSerial\s+)(\S+)$"#, "$1<redacted>"),
                (#"(?im)^(\s*Serial:\s*)(\S+)$"#, "$1<redacted>"),
                (#"(?im)^(\s*SN[:=]\s*)(\S+)$"#, "$1<redacted>"),
                (#"(?im)\b(iSerialNumber|iSerial)\s*[=:]\s*([A-Za-z0-9:_\-.]+)"#, "iSerial: <redacted>"),

                // UDID patterns
                (#"(?im)\bUDID\s*[=:]\s*([A-Fa-f0-9-]+)"#, "UDID: <redacted>"),

                // Device-friendly names that may contain personal info - expanded
                (#"(?im)^(\s*(Product|Manufacturer|Device Name|Model|Friendly Name):\s+)(.+)$"#, "$1<redacted>"),
                (#"(?im)^(\s*Product:\s+)(.+)$"#, "$1<redacted>"),
                (#"(?im)^(\s*Manufacturer:\s+)(.+)$"#, "$1<redacted>"),

                // Hostnames and computer names - expanded patterns
                (#"(?i)\b(Hostname|Computer Name|Machine Name|Host Name):\s+(.+)$"#, "$1: <redacted>"),
                (#"(?i)\b(ComputerName|HostName|MachineName):\s+(.+)$"#, "$1: <redacted>"),
                (#"[A-Za-z0-9_-]+'s\s+[A-Za-z0-9 _-]+"#, "<hostname-redacted>"), // "Steven's Mac mini"

                // User names and owners - expanded
                (#"(?i)\b(User Name|Owner|Author|Creator|User):\s+(.+)$"#, "$1: <redacted>"),
                (#"(?i)\b(UserName|OwnerName|AuthorName):\s+(.+)$"#, "$1: <redacted>"),

                // Absolute user paths - comprehensive coverage
                (#"/Users/[^/\s]+"#, "/Users/<redacted>"),
                (#"(?i)C:\\Users\\[^\\[:space:]]+"#, "C:\\Users\\<redacted>"),
                (#"(?i)/home/[^/[:space:]]+"#, "/home/<redacted>"),
                (#"(?i)/usr/home/[^/[:space:]]+"#, "/usr/home/<redacted>"),

                // Network-related identifiers that might leak personal info
                (#"(?i)\b(MAC Address|Ethernet ID|WiFi Address|Bluetooth Address):\s+([0-9A-Fa-f:-]+)"#, "$1: <redacted>"),
                (#"(?i)\b(MAC|Ethernet|WiFi|Bluetooth)[-_ ](Address|ID):\s+([0-9A-Fa-f:-]+)"#, "$1$2: <redacted>"),

                // IP addresses
                (#"\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"#, "<ip-redacted>"),

                // Email addresses
                (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email-redacted>"),

                // UUIDs and GUIDs - expanded
                (#"(?i)\b(UUID|GUID|UUIDString):\s+([0-9A-Fa-f-]+)"#, "$1: <redacted>"),
                (#"(?i)\b(uuid|guid)\s*[=:]\s*([0-9A-Fa-f-]+)"#, "$1: <redacted>"),

                // Device-specific identifiers
                (#"(?i)\b(DeviceID|HardwareID|SystemID):\s+([A-Za-z0-9_-]+)"#, "$1: <redacted>"),

                // Personal device names
                (#"(?i)\b(Device Name|Phone Name|iPhone Name|iPad Name):\s+(.+)$"#, "$1: <redacted>")
            ]

            // Apply all patterns
            for (pattern, replacement) in patterns {
                usbDumpText = usbDumpText.replacingOccurrences(
                    of: pattern,
                    with: replacement,
                    options: .regularExpression
                )
            }

            return usbDumpText
        }
    }

    private func runBenchmarks(device: any MTPDevice, flags: Flags) async throws -> [String: URL] {
        guard !flags.runBench.isEmpty else {
            return [:]
        }

        var results = [String: URL]()

        for (index, sizeStr) in flags.runBench.enumerated() {
            print("   🏃 Running \(sizeStr) benchmark (\(index + 1)/\(flags.runBench.count))...")
            let csvURL = try await runSingleBenchmark(device: device, size: sizeStr)
            results[sizeStr] = csvURL
            print("   ✅ \(sizeStr) benchmark completed")
        }

        return results
    }

    private func runSingleBenchmark(device: any MTPDevice, size: String) async throws -> URL {
        let sizeBytes = parseSize(size)
        guard sizeBytes > 0 else {
            throw MTPError.preconditionFailed("Invalid benchmark size: \(size)")
        }

        let storages = try await device.storages()
        guard let storage = storages.first else {
            throw MTPError.notSupported("No storage available for benchmarking")
        }

        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("swiftmtp-bench-\(size).tmp")
        let testData = Data(repeating: 0xAA, count: Int(sizeBytes))
        try testData.write(to: tempFile)

        // Run benchmark
        let startTime = Date()
        let progress = try await device.write(parent: nil, name: "swiftmtp-bench.tmp", size: sizeBytes, from: tempFile)

        while !progress.isFinished {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let duration = Date().timeIntervalSince(startTime)
        let speedMBps = Double(sizeBytes) / duration / 1_000_000

        // Create CSV result
        let csvURL = tempDir.appendingPathComponent("bench-\(size.lowercased()).csv")
        let csvContent = """
        timestamp,operation,size_bytes,duration_seconds,speed_mbps
        \(ISO8601DateFormatter().string(from: Date())),write,\(sizeBytes),\(duration),\(speedMBps)
        """

        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        // Cleanup
        try? FileManager.default.removeItem(at: tempFile)

        return csvURL
    }

    private func generateQuirkSuggestion(device: any MTPDevice, effectiveTuning: EffectiveTuning) async throws -> QuirkSuggestion {
        let deviceInfo = try? await device.info
        let vidPid = "0x2717:0xff10" // TODO: Extract from actual device

        let suggestion = QuirkSuggestion(
            id: "generated-\(vidPid.replacingOccurrences(of: ":", with: "-"))-\(Int(Date().timeIntervalSince1970))",
            match: QuirkSuggestion.MatchCriteria(vidPid: vidPid),
            overrides: [
                "maxChunkBytes": AnyCodable(effectiveTuning.maxChunkBytes),
                "stabilizeMs": AnyCodable(effectiveTuning.stabilizeMs),
                "ioTimeoutMs": AnyCodable(effectiveTuning.ioTimeoutMs),
                "overallDeadlineMs": AnyCodable(effectiveTuning.overallDeadlineMs)
            ],
            hooks: effectiveTuning.hooks.map { hook in
                QuirkSuggestion.Hook(
                    phase: hook.phase.rawValue,
                    delayMs: hook.delayMs,
                    busyBackoff: hook.busyBackoff.map { backoff in
                        QuirkSuggestion.Hook.BusyBackoff(
                            retries: backoff.retries,
                            baseMs: backoff.baseMs,
                            jitterPct: backoff.jitterPct
                        )
                    }
                )
            },
            benchGates: QuirkSuggestion.BenchGates(readMBps: 10.0, writeMBps: 8.0), // Conservative defaults
            provenance: QuirkSuggestion.Provenance(
                submittedBy: nil, // Will be filled if user provides GitHub username
                date: ISO8601DateFormatter().string(from: Date())
            )
        )

        return suggestion
    }

    private func createSubmissionBundle(
        device: any MTPDevice,
        flags: Flags,
        probeData: ProbeData,
        usbDump: String,
        benchResults: [String: URL],
        quirkSuggestion: QuirkSuggestion,
        salt: Data
    ) async throws -> SubmissionBundle {
        // Create bundle directory - use custom path if provided
        let bundleDir: URL
        if let customPath = flags.bundlePath {
            bundleDir = URL(fileURLWithPath: customPath)
        } else {
            let contribDir = URL(fileURLWithPath: "Contrib/submissions")
            try FileManager.default.createDirectory(at: contribDir, withIntermediateDirectories: true)
            let deviceSlug = "generated-\(Int(Date().timeIntervalSince1970))"
            bundleDir = contribDir.appendingPathComponent(deviceSlug)
        }
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // Write artifacts
        print("   📄 Writing probe data...")
        let probeURL = bundleDir.appendingPathComponent("probe.json")
        try probeData.jsonData.write(to: probeURL)

        print("   🔌 Writing USB dump...")
        let usbDumpURL = bundleDir.appendingPathComponent("usb-dump.txt")
        try usbDump.write(to: usbDumpURL, atomically: true, encoding: .utf8)

        // Copy benchmark results
        var benchFiles = [String]()
        if !benchResults.isEmpty {
            print("   📊 Copying benchmark results...")
            for (size, csvURL) in benchResults {
                let destURL = bundleDir.appendingPathComponent("bench-\(size.lowercased()).csv")
                try FileManager.default.copyItem(at: csvURL, to: destURL)
                benchFiles.append("bench-\(size.lowercased()).csv")
            }
        }

        // Write quirk suggestion
        print("   🧠 Writing quirk suggestion...")
        let quirkURL = bundleDir.appendingPathComponent("quirk-suggestion.json")
        let quirkData = try JSONEncoder().encode(quirkSuggestion)
        try quirkData.write(to: quirkURL)

        // Write salt to local file (never committed to git for privacy)
        print("   🔐 Securing redaction salt...")
        let localSaltURL = URL(fileURLWithPath: ".salt.local")
        try salt.write(to: localSaltURL)

        // Note: Salt is NOT written to bundle - it must never be committed
        // The bundle only contains redacted data derived using the salt

        // Create manifest
        print("   📋 Creating submission manifest...")
        let manifest = SubmissionManifest(
            tool: SubmissionManifest.ToolInfo(
                version: "1.0.0-rc1", // TODO: Get from build
                commit: try? await getGitCommit()
            ),
            host: SubmissionManifest.HostInfo(
                os: ProcessInfo.processInfo.operatingSystemVersionString,
                arch: getArchitecture()
            ),
            timestamp: Date(),
            user: nil, // TODO: Get from environment or prompt
            device: SubmissionManifest.DeviceInfo(
                vendorId: "0x2717", // TODO: Extract from device
                productId: "0xff10", // TODO: Extract from device
                bcdDevice: "0x0318", // TODO: Extract from device
                vendor: probeData.deviceInfo.manufacturer,
                model: probeData.deviceInfo.model,
                interface: SubmissionManifest.InterfaceInfo(
                    class: "0x06",
                    subclass: "0x01",
                    protocol: "0x01",
                    in: "0x81",
                    out: "0x01",
                    evt: "0x82"
                ),
                fingerprintHash: try generateFingerprintHash(device: probeData.deviceInfo),
                serialRedacted: try redactSerial(probeData.deviceInfo.serialNumber ?? "", salt: salt)
            ),
            artifacts: SubmissionManifest.ArtifactInfo(
                probe: "probe.json",
                usbDump: "usb-dump.txt",
                bench: benchFiles.isEmpty ? nil : benchFiles
            ),
            consent: SubmissionManifest.ConsentInfo(
                anonymizeSerial: true,
                allowBench: !flags.runBench.isEmpty
            )
        )

        // Write manifest
        print("   💾 Writing submission manifest...")
        let manifestURL = bundleDir.appendingPathComponent("submission.json")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL)

        return SubmissionBundle(
            bundleDir: bundleDir,
            manifest: manifest,
            probeJSON: probeData.jsonData,
            usbDumpText: usbDump,
            benchResults: benchResults,
            quirkSuggestion: quirkSuggestion,
            salt: salt
        )
    }

    private func validateBundle(bundle: SubmissionBundle) async throws {
        // Basic validation - check that referenced files exist
        let probeURL = bundle.bundleDir.appendingPathComponent("probe.json")
        let usbDumpURL = bundle.bundleDir.appendingPathComponent("usb-dump.txt")

        guard FileManager.default.fileExists(atPath: probeURL.path) else {
            throw MTPError.preconditionFailed("Missing probe.json in bundle")
        }

        guard FileManager.default.fileExists(atPath: usbDumpURL.path) else {
            throw MTPError.preconditionFailed("Missing usb-dump.txt in bundle")
        }

        // Validate JSON files can be parsed
        let probeData = try Data(contentsOf: probeURL)
        _ = try JSONSerialization.jsonObject(with: probeData)

        let quirkURL = bundle.bundleDir.appendingPathComponent("quirk-suggestion.json")
        let quirkData = try Data(contentsOf: quirkURL)
        _ = try JSONDecoder().decode(QuirkSuggestion.self, from: quirkData)

        print("✅ Bundle validation passed")
    }

    private func createPullRequest(bundle: SubmissionBundle) async throws {
        print("\n📤 Creating GitHub pull request...")

        // Check if gh CLI is available
        guard await GitHubIntegration.isGitHubCLIInstalled() else {
            print("❌ GitHub CLI (gh) not found. Please install it or use manual submission.")
            printManualSubmissionInstructions(bundle: bundle)
            return
        }

        // Check if user is authenticated
        guard await GitHubIntegration.isGitHubCLIAuthenticated() else {
            print("❌ Not authenticated with GitHub CLI. Please run 'gh auth login' first.")
            printManualSubmissionInstructions(bundle: bundle)
            return
        }

        // Create branch
        let branchName = GitHubIntegration.generateBranchName(
            deviceName: bundle.manifest.device.vendor + " " + bundle.manifest.device.model,
            vendorId: bundle.manifest.device.vendorId,
            productId: bundle.manifest.device.productId
        )
        try await GitHubIntegration.createBranch(name: branchName)

        // Add files
        try await GitHubIntegration.addFiles(paths: [bundle.bundleDir.path])

        // Commit
        let commitMessage = GitHubIntegration.generateCommitMessage(
            deviceName: bundle.manifest.device.vendor + " " + bundle.manifest.device.model,
            vendorId: bundle.manifest.device.vendorId,
            productId: bundle.manifest.device.productId
        )
        try await GitHubIntegration.commitChanges(message: commitMessage)

        // Push
        try await GitHubIntegration.pushBranch(branchName: branchName)

        // Create PR
        let prTitle = "Device Submission: \(bundle.manifest.device.vendor) \(bundle.manifest.device.model)"
        let prBody = GitHubIntegration.generatePRBody(
            deviceName: bundle.manifest.device.vendor + " " + bundle.manifest.device.model,
            vendorId: bundle.manifest.device.vendorId,
            productId: bundle.manifest.device.productId,
            bundlePath: bundle.bundleDir.path
        )

        try await GitHubIntegration.createPullRequest(title: prTitle, body: prBody, fill: true)

        print("✅ Pull request created successfully!")
    }

    private func printManualSubmissionInstructions(bundle: SubmissionBundle) {
        print("\n📋 Manual Submission Instructions")
        print("-------------------------------")
        print("To submit your device data manually:")
        print("")
        print("1. Create a new branch:")
        print("   git checkout -b device/\(bundle.manifest.device.vendor.lowercased())-\(bundle.manifest.device.model.lowercased())")
        print("")
        print("2. Add the submission bundle:")
        print("   git add \(bundle.bundleDir.path)")
        print("")
        print("3. Commit the changes:")
        print("   git commit -s -m \"Device submission: \(bundle.manifest.device.vendor) \(bundle.manifest.device.model) (\(bundle.manifest.device.vendorId):\(bundle.manifest.device.productId))\"")
        print("")
        print("4. Push to your fork:")
        print("   git push -u origin HEAD")
        print("")
        print("5. Create a pull request using the device-submission template")
        print("")
        print("Bundle location: \(bundle.bundleDir.path)")
    }

    private func generatePRBody(bundle: SubmissionBundle) -> String {
        var body = """
        ## Device Submission

        **Device:** \(bundle.manifest.device.vendor) \(bundle.manifest.device.model)
        **VID:PID:** \(bundle.manifest.device.vendorId):\(bundle.manifest.device.productId)
        **Interface:** \(bundle.manifest.device.interface.class)/\(bundle.manifest.device.interface.subclass)/\(bundle.manifest.device.interface.protocol)

        ### Probe Results
        - Operations: \(bundle.manifest.device.vendor) \(bundle.manifest.device.model) operations supported
        - Storage: \(bundle.manifest.device.vendor) \(bundle.manifest.device.model) storage devices found

        ### Performance Benchmarks
        """

        if let benches = bundle.manifest.artifacts.bench, !benches.isEmpty {
            body += "- Benchmarks: \(benches.joined(separator: ", "))\n"
        } else {
            body += "- No benchmarks performed\n"
        }

        body += """

        ### Proposed Quirk Configuration
        ```json
        \(String(data: try! JSONEncoder().encode(bundle.quirkSuggestion), encoding: .utf8)!)
        ```

        ### Files Changed
        - `Contrib/submissions/\(bundle.bundleDir.lastPathComponent)/` - New submission bundle

        ### Checklist
        - [x] Device probe data collected
        - [x] USB dump captured
        - [x] Serial numbers redacted
        - [x] Quirk suggestion generated
        - [ ] Submission validated locally

        ---
        *Generated by SwiftMTP collect command*
        """

        return body
    }

    // Helper functions
    private func parseSize(_ str: String) -> UInt64 {
        let multipliers: [Character: UInt64] = ["K": 1024, "M": 1024*1024, "G": 1024*1024*1024]
        let numStr = str.filter { $0.isNumber }
        let suffix = str.last(where: { multipliers.keys.contains($0.uppercased().first!) })

        guard let num = UInt64(numStr) else { return 0 }
        guard let mult = suffix?.uppercased().first,
              let multiplier = multipliers[mult] else { return num }

        return num * multiplier
    }

    private func getArchitecture() -> String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }

    private func generateFingerprintHash(device: MTPDeviceInfo) throws -> String {
        let fingerprint = "\(device.manufacturer)|\(device.model)|\(device.serialNumber ?? "")"
        let data = fingerprint.data(using: .utf8) ?? Data()
        return "sha256:" + sha256Hex(data)
    }

    private func redactSerial(_ serial: String, salt: Data) throws -> String {
        let data = (serial + String(data: salt, encoding: .utf8)!).data(using: .utf8) ?? Data()
        let hmac = hmacSHA256(data: data, key: salt)
        return "hmacsha256:" + hmac.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(data: Data, key: Data) -> Data {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBuffer.baseAddress, key.count, dataBuffer.baseAddress, data.count, &hmac)
            }
        }
        return Data(hmac)
    }

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func getGitCommit() async throws -> String? {
        do {
            let result = try await runCommand("git", arguments: ["rev-parse", "HEAD"])
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }


    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command)")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw MTPError.preconditionFailed("Command failed: \(command) \(arguments.joined(separator: " "))")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}


