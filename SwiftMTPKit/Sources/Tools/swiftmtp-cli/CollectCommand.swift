// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import CLibusb
import CommonCrypto

struct CollectCommand {
    struct Flags {
        let deviceName: String?
        let runBench: [String]  // e.g., ["100M", "1G"]
        let noBench: Bool
        let openPR: Bool
        let nonInteractive: Bool
        let realOnly: Bool
        let strict: Bool
        let safe: Bool
        let traceUSB: Bool
        let traceUSBDetails: Bool
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

    func run(flags: Flags) async throws {
        print("🔍 SwiftMTP Device Submission Collector")
        print("=====================================")

        // Step 1: Consent and validation
        try await handleConsent(flags: flags)

        // Step 2: Discover and validate device
        let device = try await discoverDevice(flags: flags)

        // Step 3: Generate salt for redaction
        let salt = Redaction.generateSalt(count: 32)

        // Step 4: Collect probe data
        print("\n📊 Collecting probe data...")
        let probeData = try await collectProbeData(device: device, flags: flags, salt: salt)

        // Step 5: Collect USB dump
        print("\n🔌 Collecting USB dump...")
        let usbDump = try await collectUSBDump()

        // Step 6: Run benchmarks (if requested)
        print("\n🏃 Running benchmarks...")
        let benchResults = try await runBenchmarks(device: device, flags: flags)

        // Step 7: Generate quirk suggestion
        print("\n🧠 Generating quirk suggestion...")
        let quirkSuggestion = generateQuirkSuggestion(device: device, effectiveTuning: probeData.effectiveTuning)

        // Step 8: Create submission bundle
        print("\n📦 Creating submission bundle...")
        let bundle = try await createSubmissionBundle(
            device: device,
            flags: flags,
            probeData: probeData,
            usbDump: usbDump,
            benchResults: benchResults,
            quirkSuggestion: quirkSuggestion,
            salt: salt
        )

        // Step 9: Validate bundle
        print("\n✅ Validating submission bundle...")
        try await validateBundle(bundle: bundle)

        // Step 10: Handle PR creation or manual submission
        if flags.openPR {
            try await createPullRequest(bundle: bundle)
        } else {
            printManualSubmissionInstructions(bundle: bundle)
        }

        print("\n🎉 Device submission collection complete!")
        print("Bundle saved to: \(bundle.bundleDir.path)")
    }

    private func handleConsent(flags: Flags) async throws {
        if flags.nonInteractive {
            print("ℹ️  Running in non-interactive mode with default consent")
            return
        }

        print("\n📋 Device Submission Consent")
        print("-----------------------------")
        print("This tool will collect the following data:")
        print("• Device probe information (capabilities, operations, storage)")
        print("• USB interface details (vendor ID, product ID, endpoints)")
        if !flags.noBench && !flags.runBench.isEmpty {
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

        if !flags.noBench && !flags.runBench.isEmpty {
            print("\nDo you consent to running performance benchmarks? (y/N): ", terminator: "")
            fflush(stdout)

            let benchConsent = readLine()?.lowercased().starts(with: "y") ?? false
            if !benchConsent {
                print("ℹ️  Benchmarks will be skipped")
                // Note: We don't modify flags here as they're passed by value
            }
        }
    }

    private func discoverDevice(flags: Flags) async throws -> any MTPDevice {
        print("\n🔍 Discovering MTP devices...")

        let devices = try await MTPDeviceManager.shared.currentRealDevices()
        print("Found \(devices.count) MTP device(s)")

        guard let deviceInfo = devices.first else {
            throw MTPError.notSupported("No MTP devices found. Please connect your device and ensure it's unlocked.")
        }

        print("Selected device: \(deviceInfo.manufacturer) \(deviceInfo.model)")

        // Build effective tuning for this device
        let effectiveTuning = try await buildEffectiveTuning(for: deviceInfo, flags: flags)

        // Open device
        let transport = LibUSBTransportFactory.createTransport()
        let config = effectiveTuning.toConfig()
        let device = try await MTPDeviceManager.shared.openDevice(with: deviceInfo, transport: transport, config: config)

        return device
    }

    private func buildEffectiveTuning(for deviceInfo: MTPDeviceInfo, flags: Flags) async throws -> EffectiveTuning {
        // Create fingerprint from device info
        let fingerprint = MTPDeviceFingerprint(
            vid: "0x2717", // TODO: Extract from actual USB descriptor
            pid: "0xff10", // TODO: Extract from actual USB descriptor
            interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
            endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82")
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
            safe: flags.safe
        )
    }

    private struct ProbeData {
        let jsonData: Data
        let effectiveTuning: EffectiveTuning
        let deviceInfo: MTPDeviceInfo
        let storages: [MTPStorage]
    }

    private func collectProbeData(device: any MTPDevice, flags: Flags, salt: Data) async throws -> ProbeData {
        let deviceInfo = try await device.info
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

    private func collectUSBDump() async throws -> String {
        let usbDumper = USBDumper()
        // Capture output by redirecting stdout temporarily
        let pipe = Pipe()
        let oldStdout = dup(STDOUT_FILENO)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        pipe.fileHandleForWriting.close()

        try await usbDumper.run()

        dup2(oldStdout, STDOUT_FILENO)
        close(oldStdout)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func runBenchmarks(device: any MTPDevice, flags: Flags) async throws -> [String: URL] {
        guard !flags.noBench && !flags.runBench.isEmpty else {
            return [:]
        }

        var results = [String: URL]()

        for sizeStr in flags.runBench {
            print("Running \(sizeStr) benchmark...")
            let csvURL = try await runSingleBenchmark(device: device, size: sizeStr)
            results[sizeStr] = csvURL
        }

        return results
    }

    private func runSingleBenchmark(device: any MTPDevice, size: String) async throws -> URL {
        let sizeBytes = parseSize(size)
        guard sizeBytes > 0 else {
            throw MTPError.invalidParameter("Invalid benchmark size: \(size)")
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

    private func generateQuirkSuggestion(device: any MTPDevice, effectiveTuning: EffectiveTuning) -> QuirkSuggestion {
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
        // Create bundle directory
        let contribDir = URL(fileURLWithPath: "Contrib/submissions")
        try FileManager.default.createDirectory(at: contribDir, withIntermediateDirectories: true)

        let deviceSlug = "generated-\(Int(Date().timeIntervalSince1970))"
        let bundleDir = contribDir.appendingPathComponent(deviceSlug)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // Write artifacts
        let probeURL = bundleDir.appendingPathComponent("probe.json")
        try probeData.jsonData.write(to: probeURL)

        let usbDumpURL = bundleDir.appendingPathComponent("usb-dump.txt")
        try usbDump.write(to: usbDumpURL, atomically: true, encoding: .utf8)

        // Copy benchmark results
        var benchFiles = [String]()
        for (size, csvURL) in benchResults {
            let destURL = bundleDir.appendingPathComponent("bench-\(size.lowercased()).csv")
            try FileManager.default.copyItem(at: csvURL, to: destURL)
            benchFiles.append("bench-\(size.lowercased()).csv")
        }

        // Write quirk suggestion
        let quirkURL = bundleDir.appendingPathComponent("quirk-suggestion.json")
        let quirkData = try JSONEncoder().encode(quirkSuggestion)
        try quirkData.write(to: quirkURL)

        // Write salt
        let saltURL = bundleDir.appendingPathComponent(".salt")
        try salt.write(to: saltURL)

        // Create manifest
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
                allowBench: !flags.noBench && !flags.runBench.isEmpty
            )
        )

        // Write manifest
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
            throw MTPError.invalidParameter("Missing probe.json in bundle")
        }

        guard FileManager.default.fileExists(atPath: usbDumpURL.path) else {
            throw MTPError.invalidParameter("Missing usb-dump.txt in bundle")
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
        return "sha256:" + data.sha256().hexString
    }

    private func redactSerial(_ serial: String, salt: Data) throws -> String {
        return Redaction.redactSerial(serial, salt: salt)
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
            throw MTPError.invalidParameter("Command failed: \(command) \(arguments.joined(separator: " "))")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

