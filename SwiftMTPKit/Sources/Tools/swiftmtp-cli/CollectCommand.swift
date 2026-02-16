// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

// Import ExitCode and exitNow from SwiftMTPCore
import enum SwiftMTPCore.ExitCode
import func SwiftMTPCore.exitNow

// Import CLI utilities
func printJSONErrorAndExit(_ error: any Error) -> Never {
  printJSONErrorAndExit("\(error)")
}

func printJSONErrorAndExit(_ error: any Error, flags: CollectCommand.CollectFlags) -> Never {
  let mode: String
  if flags.safe {
    mode = "safe"
  } else if flags.strict {
    mode = "strict"
  } else {
    mode = "normal"
  }

  // Extract candidates from CollectError if available
  var details: [String: String] = [:]
  if let collectError = error as? CollectCommand.CollectError {
    switch collectError {
    case .noDeviceMatched(let candidates):
      details["availableDevices"] = candidates.isEmpty ? "none" : "\(candidates.count)"
      if !candidates.isEmpty {
        // Add first few candidates as examples
        let examples = candidates.prefix(3).map { "\($0.vid):\($0.pid)@\($0.bus):\($0.address)" }
        details["examples"] = examples.joined(separator: ", ")
      }
    case .ambiguousSelection(let count, let candidates):
      details["matchingDevices"] = "\(count)"
      let examples = candidates.prefix(3).map { "\($0.vid):\($0.pid)@\($0.bus):\($0.address)" }
      details["examples"] = examples.joined(separator: ", ")
    case .redactionCheckFailed(let issues):
      details["redactionIssues"] = issues.joined(separator: ", ")
    case .invalidBenchSize(let size):
      details["invalidBenchSize"] = size
    case .timeout:
      break
    }
  }

  printJSONErrorAndExit("\(error)", details: details.isEmpty ? nil : details, mode: mode)
}

// Spinner & JSON/Exit helpers are expected from your CLI shared utilities:
// - Spinner (aka CLISpinner) with init(message:enabled:) / start / succeed / fail
// - printJSON(_:)
// - printJSONErrorAndExit(_:)
// - Exit.software(), Exit.usage(), Exit.unavailable()

public enum CollectCommand {

  // MARK: - Back-compat type aliases
  public typealias Flags = CollectFlags

  // MARK: - Flags structure for back-compatibility
  public struct CollectFlags: Sendable {
    public var strict: Bool = true           // default strict on
    public var safe: Bool = false            // --safe
    public var runBench: [String] = []       // default no bench
    public var json: Bool = false            // --json
    public var noninteractive: Bool = false  // --noninteractive
    public var bundlePath: String?           // --bundle
    public var deviceName: String?           // --device-name
    public var openPR: Bool = false          // --open-pr
    public var vid: UInt16?
    public var pid: UInt16?
    public var bus: Int?
    public var address: Int?

    public init(
      strict: Bool = true,
      safe: Bool = false,
      runBench: [String] = [],
      json: Bool = false,
      noninteractive: Bool = false,
      bundlePath: String? = nil,
      deviceName: String? = nil,
      openPR: Bool = false,
      vid: UInt16? = nil, pid: UInt16? = nil, bus: Int? = nil, address: Int? = nil
    ) {
      self.strict = strict
      self.safe = safe
      self.runBench = runBench
      self.json = json
      self.noninteractive = noninteractive
      self.bundlePath = bundlePath
      self.deviceName = deviceName
      self.openPR = openPR
      self.vid = vid; self.pid = pid; self.bus = bus; self.address = address
    }

    // Backward-compat initializer (no json parameter)
    @available(*, deprecated, message: "Use newer initializer that includes json/noninteractive/bundlePath/IDs")
    public init(strict: Bool = true, runBench: [String] = []) {
      self.init(
        strict: strict,
        runBench: runBench,
        json: false,
        noninteractive: false,
        bundlePath: nil,
        deviceName: nil,
        openPR: false
      )
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
                deviceName: nil,
                openPR: false,
                vid: nil, pid: nil, bus: nil, address: nil)
    }
  }

  // MARK: - Bundle collection (reusable by WizardCommand)

  /// Collect a device evidence bundle without calling exitNow().
  /// Returns the bundle URL and optional CI output.
  public static func collectBundle(flags: Flags) async throws -> (bundleURL: URL, summary: MTPDeviceSummary) {
    let summary = try await selectDeviceOrExit(flags: flags)
    let (device, config) = try await openDevice(summary: summary, strict: flags.strict)
    let bundleURL = try prepareBundlePath(flags: flags, summary: summary)
    try await collectArtifacts(
      flags: flags,
      summary: summary,
      device: device,
      config: config,
      bundleURL: bundleURL
    )

    return (bundleURL, summary)
  }

  // MARK: - Public entry point used by main.swift
  public static func run(flags: Flags) async -> ExitCode {
    let jsonMode = flags.json
    var spinner = Spinner("Collecting device evidence…", enabled: !jsonMode)

    do {
      spinner.start("Preparing bundle and collecting artifacts…")
      let result = try await collectBundle(flags: flags)
      let bundleURL = result.bundleURL
      let summary = result.summary
      spinner.succeed("Bundle ready: \(bundleURL.path)")

      // Record submission in persistence
      Task {
        let persistence = await MTPDeviceManager.shared.persistence
        try? await persistence.submissions.recordSubmission(
          id: bundleURL.lastPathComponent,
          deviceId: summary.id,
          path: bundleURL.path
        )
      }

      if flags.openPR {
        spinner.start("Opening GitHub PR…")
        let submitExit = await SubmitCommand.run(bundlePath: bundleURL.path, gh: true)
        guard submitExit == .ok else {
          spinner.fail("Submission failed")
          return submitExit
        }
        spinner.succeed("GitHub PR opened")
      }

      // Emit JSON summary for CI if requested
      if jsonMode {
        let mode: String
        if flags.safe {
          mode = "safe"
        } else if flags.strict {
          mode = "strict"
        } else {
          mode = "normal"
        }

        let out = CollectionOutput(
          schemaVersion: "1.0.0",
          timestamp: ISO8601DateFormatter().string(from: Date()),
          bundlePath: bundleURL.path,
          deviceVID: summary.vendorID ?? 0, devicePID: summary.productID ?? 0,
          bus: Int(summary.bus ?? 0), address: Int(summary.address ?? 0),
          mode: mode
        )
        printJSON(out)
      }

      return .ok

    } catch {
      if jsonMode { printJSONErrorAndExit(error, flags: flags) }
      
      if let collectError = error as? CollectError {
        switch collectError {
        case .noDeviceMatched:
          fputs("❌ collect failed: \(error)\n", stderr)
          return .unavailable
        case .ambiguousSelection:
          fputs("❌ collect failed: \(error)\n", stderr)
          return .usage
        case .timeout:
          fputs("❌ collect failed: \(error)\n", stderr)
          return .tempfail
        case .redactionCheckFailed:
          fputs("❌ collect failed: \(error)\n", stderr)
          return .software
        case .invalidBenchSize:
          fputs("❌ collect failed: \(error)\n", stderr)
          return .usage
        }
      }
      
      fputs("❌ collect failed: \(error)\n", stderr)
      return .software
    }
  }

  // MARK: - Device selection (no internal helpers)
  private static func selectDeviceOrExit(flags: Flags) async throws -> MTPDeviceSummary {
    let devs = try await enumerateRealMTPDevices()
    let filter = DeviceFilter(vid: flags.vid, pid: flags.pid, bus: flags.bus, address: flags.address)
    let outcome = selectDevice(devs, filter: filter, noninteractive: flags.noninteractive)

    let candidates = devs.map { DeviceCandidate(from: $0) }

    switch outcome {
    case .none:
      // 69 = unavailable
      if flags.json {
        printJSONErrorAndExit(CollectError.noDeviceMatched(candidates: candidates), flags: flags)
      } else {
        fputs("No devices matched the provided filter.\n", stderr)
        if !devs.isEmpty {
          fputs("Available devices:\n", stderr)
          for (i, candidate) in candidates.enumerated() {
            fputs("  \(i+1). \(candidate.vid):\(candidate.pid) @ \(candidate.bus):\(candidate.address) - \(candidate.manufacturer) \(candidate.model)\n", stderr)
          }
        }
        exitNow(.unavailable)
      }
      // never returns
    case .selected(let selected):
      return selected
    case .multiple(let matches):
      // If interactive, you could prompt; for noninteractive we must exit(64).
      if flags.noninteractive {
        if flags.json {
          printJSONErrorAndExit(CollectError.ambiguousSelection(count: matches.count, candidates: candidates), flags: flags)
        } else {
          fputs("Multiple devices matched the filter; refine selection.\n", stderr)
          fputs("Matching devices:\n", stderr)
          for (i, device) in matches.enumerated() {
            let candidate = DeviceCandidate(from: device)
            fputs("  \(i+1). \(candidate.vid):\(candidate.pid) @ \(candidate.bus):\(candidate.address) - \(candidate.manufacturer) \(candidate.model)\n", stderr)
          }
          exitNow(.usage)
        }
      }
      // Simple interactive choose-first fallback
      return matches[0]
    }
  }

  // Discover available MTP devices via LibUSBTransport's discovery layer.
  private static func enumerateRealMTPDevices() async throws -> [MTPDeviceSummary] {
    // This uses the public LibUSBTransport discovery bridge you already wired.
    let list = try await LibUSBDiscovery.enumerateMTPDevices()
    return list
  }

  // MARK: - Open device
  private static func openDevice(summary: MTPDeviceSummary, strict: Bool) async throws
  -> (any MTPDevice, SwiftMTPConfig) {
    let transport = LibUSBTransportFactory.createTransport()
    let config = SwiftMTPConfig()
    // Strict mode is conceptual; your DeviceActor applies conservative tuning when strict=true
    // Apply tuning/quirks at open time using your existing actor method:
    let device = try await MTPDeviceManager.shared.openDevice(with: summary,
                                                              transport: transport,
                                                              config: config)
    try await device.openIfNeeded() // compat shim you added
    return (device, config)
  }

  private static let stepTimeoutMs = 90_000

  private static func collectArtifacts(
    flags: Flags,
    summary: MTPDeviceSummary,
    device: any MTPDevice,
    config: SwiftMTPConfig,
    bundleURL: URL
  ) async throws {
    let probe = try await within(ms: stepTimeoutMs) {
      try await collectProbeJSON(device: device, summary: summary)
    }
    try writeJSONFile(probe, to: bundleURL.appendingPathComponent("probe.json"))

    let rawDump = try await within(ms: stepTimeoutMs) {
      try await generateSimpleUSBDump(summary: summary)
    }
    let sanitized = sanitizeDump(rawDump)
    try validateDebugSanitization(sanitized, strict: flags.strict)
    try sanitized.write(
      to: bundleURL.appendingPathComponent("usb-dump.txt"),
      atomically: true,
      encoding: .utf8
    )

    var benchResults: [BenchResult] = []
    if !flags.runBench.isEmpty {
      benchResults = try await runBenches(device: device, sizes: flags.runBench)
      for result in benchResults {
        try result.csv.write(
          to: bundleURL.appendingPathComponent("bench-\(result.name).csv"),
          atomically: true,
          encoding: .utf8
        )
      }
    }

    let salt = Redaction.generateSalt()
    try (salt.hexString() + "\n").write(
      to: bundleURL.appendingPathComponent(".salt"),
      atomically: true,
      encoding: .utf8
    )

    let tuning = await device.effectiveTuning
    let manifest = buildSubmissionManifest(
      summary: summary,
      probe: probe,
      benchResults: benchResults,
      salt: salt
    )
    try writeJSONFile(manifest, to: bundleURL.appendingPathComponent("submission.json"))

    let quirkSuggestion = buildQuirkSuggestion(
      summary: summary,
      tuning: tuning,
      config: config,
      benchResults: benchResults,
      submittedBy: manifest.user?.github
    )
    try writeJSONFile(quirkSuggestion, to: bundleURL.appendingPathComponent("quirk-suggestion.json"))
  }

  // MARK: - Probe capture
  private struct ProbeJSON: Codable, Sendable {
    var schemaVersion = "1.0.0"
    var type = "probe"
    var timestamp: String
    var fingerprint: MTPDeviceFingerprint
    var capabilities: [String: Bool]
    var vendorID: UInt16
    var productID: UInt16
    var bus: Int
    var address: Int
    var deviceInfo: DeviceInfoJSON
    var storageCount: Int
  }

  private struct DeviceInfoJSON: Codable, Sendable {
    var manufacturer: String
    var model: String
    var version: String
    var serial: String?
  }

  private static func collectProbeJSON(device: any MTPDevice,
                                       summary: MTPDeviceSummary) async throws -> ProbeJSON {
    let info = try await device.getDeviceInfo()
    let storages = try await device.storages()
    let receipt = await device.probeReceipt
    let capabilities = await device.probedCapabilities
    let fp = receipt?.fingerprint ?? fallbackFingerprint(for: summary)
    return .init(
      timestamp: ISO8601DateFormatter().string(from: Date()),
      fingerprint: fp,
      capabilities: capabilities,
      vendorID: summary.vendorID ?? 0, productID: summary.productID ?? 0,
      bus: Int(summary.bus ?? 0), address: Int(summary.address ?? 0),
      deviceInfo: .init(manufacturer: info.manufacturer,
                        model: info.model,
                        version: info.version,
                        serial: info.serialNumber),
      storageCount: storages.count
    )
  }

  private static func fallbackFingerprint(for summary: MTPDeviceSummary) -> MTPDeviceFingerprint {
    MTPDeviceFingerprint.fromUSB(
      vid: summary.vendorID ?? 0,
      pid: summary.productID ?? 0,
      interfaceClass: 0x06,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      epIn: 0x81,
      epOut: 0x01,
      epEvt: 0x82
    )
  }

  // MARK: - USB dump (simple, sanitized)
  private static func generateSimpleUSBDump(summary: MTPDeviceSummary) async throws -> String {
    // We rely only on information embedded in the summary to avoid internal helpers.
    var text = "Device \(String(format: "%04x:%04x", summary.vendorID ?? 0, summary.productID ?? 0))\n"
    text += "  bus=\(summary.bus ?? 0) address=\(summary.address ?? 0)\n"
    // If your summary exposes interface/endpoint info, include it here similarly.
    return text
  }

  private static func sanitizeDump(_ s: String) -> String {
    // Comprehensive privacy sanitization for USB dumps and device information
    var t = s

    // User paths (macOS, Linux, Windows)
    t = t.replacingOccurrences(of: #"/Users/[^/\n]+"#, with: "/Users/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"/home/[^/\n]+"#, with: "/home/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"/var/[^/\n]+"#, with: "/var/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"/etc/[^/\n]+"#, with: "/etc/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"([A-Za-z]:\\Users\\)[^\\]+"#, with: "$1<redacted>", options: .regularExpression)

    // Host/computer names
    t = t.replacingOccurrences(of: #"(?i)(Host\s*Name|Hostname|Computer\s*Name)\s*:\s*.*"#, with: "$1: <redacted>", options: .regularExpression)

    // Emails
    t = t.replacingOccurrences(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "<redacted-email>", options: [.regularExpression, .caseInsensitive])

    // IP addresses (IPv4 and IPv6)
    t = t.replacingOccurrences(of: #"\b(\d{1,3}\.){3}\d{1,3}\b"#, with: "<redacted-ipv4>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"\b([0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}\b"#, with: "<redacted-ipv6>", options: [.regularExpression, .caseInsensitive])

    // MAC addresses
    t = t.replacingOccurrences(of: #"\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#, with: "<redacted-mac>", options: [.regularExpression, .caseInsensitive])

    // Serial numbers and device IDs
    t = t.replacingOccurrences(of: #"(?i)(UDID|Serial\s*(?:Number)?|iSerial)\b[:\s]+(\S+)"#, with: "$1: <redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"\b([0-9a-f]{16,64})\b(?=.*\b(udid|serial|device|sn|id)\b)"#, with: "<redacted-hex>", options: [.regularExpression, .caseInsensitive])

    // Possessive device names (e.g., "Steven's iPhone" → "iPhone")
    t = t.replacingOccurrences(of: #"\b[\p{L}\p{N}._%+-]+'s\s+"#, with: "", options: [.regularExpression, .caseInsensitive])

    // Legacy patterns for backward compatibility
    t = t.replacingOccurrences(of: #"Serial\s+Number:\s+[^\s]+"#, with: "Serial Number: <redacted>", options: .regularExpression)
    t = t.replacingOccurrences(of: #"\b[A-Za-z0-9._-]+\.local\b"#, with: "<redacted>.local", options: .regularExpression)

    return t
  }

  private static func validateDebugSanitization(_ dump: String, strict: Bool) throws {
    let issues = redactionIssuesDetected(in: dump)
    guard !issues.isEmpty else { return }
    if strict {
      throw CollectError.redactionCheckFailed(issues)
    } else {
      log("⚠️  Potentially sensitive artifacts detected: \(issues.joined(separator: ", ")).")
    }
  }

  private static func redactionIssuesDetected(in dump: String) -> [String] {
    let checks: [(String, String)] = [
      ("serial", #"(?im)^\s*(Serial|Serial Number|iSerial)\s*[:=]\s*(?!<redacted>)\S+"#),
      ("hex-serial", #"(?im)\b[0-9A-Fa-f]{16,64}\b(?=.*\b(serial|device|sn|id)\b)"#),
      ("user-path", #"/Users/(?!<redacted>)[^/\n]+"#),
      ("home-path", #"/home/(?!<redacted>)[^/\n]+"#),
      ("hostname", #"(?im)^(Host Name|Hostname|Computer Name)\s*:\s*(?!<redacted>)\S+"#),
      ("email", #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#),
      ("ipv4", #"\b(\d{1,3}\.){3}\d{1,3}\b"#),
      ("mac", #"\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#)
    ]

    return checks.compactMap { label, pattern in
      dump.range(of: pattern, options: .regularExpression) == nil ? nil : label
    }
  }

  // MARK: - Bench
  private struct BenchResult: Sendable {
    let name: String
    let csv: String
    let readMBps: Double
    let writeMBps: Double
  }

  private static func runBenches(device: any MTPDevice, sizes: [String]) async throws -> [BenchResult] {
    var results: [BenchResult] = []
    results.reserveCapacity(sizes.count)

    for requested in sizes {
      let sizeLabel = try normalizeBenchSizeLabel(requested)
      let sizeBytes = parseSize(sizeLabel)
      guard sizeBytes > 0 else { throw CollectError.invalidBenchSize(requested) }

      let bench = try await within(ms: benchTimeoutMs(for: sizeBytes)) {
        try await runSingleBench(device: device, sizeLabel: sizeLabel, sizeBytes: sizeBytes)
      }
      results.append(bench)
    }

    return results
  }

  private static func normalizeBenchSizeLabel(_ requested: String) throws -> String {
    let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard normalized.range(of: #"^\d+[KMG]$"#, options: .regularExpression) != nil else {
      throw CollectError.invalidBenchSize(requested)
    }
    return normalized
  }

  private static func benchTimeoutMs(for sizeBytes: UInt64) -> Int {
    let sizeMB = max(1.0, Double(sizeBytes) / 1_000_000.0)
    let estimatedSeconds = Int(sizeMB / 3.0) + 120
    return max(estimatedSeconds * 1_000, 240_000)
  }

  private static func runSingleBench(
    device: any MTPDevice,
    sizeLabel: String,
    sizeBytes: UInt64
  ) async throws -> BenchResult {
    let (storageID, parentHandle) = try await resolveCollectBenchTarget(device: device)
    let randomSuffix = String(UInt32.random(in: 0...UInt32.max), radix: 16, uppercase: false)
    let benchFilename = "swiftmtp-bench-\(randomSuffix).tmp"
    let uploadURL = try createTempPayloadFile(name: benchFilename, sizeBytes: sizeBytes)
    let downloadURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("swiftmtp-bench-read-\(randomSuffix).tmp")

    defer {
      try? FileManager.default.removeItem(at: uploadURL)
      try? FileManager.default.removeItem(at: downloadURL)
    }

    var uploadedHandle: MTPObjectHandle?
    do {
      let writeStart = Date()
      let writeProgress = try await device.write(
        parent: parentHandle == 0xFFFFFFFF ? nil : parentHandle,
        name: benchFilename,
        size: sizeBytes,
        from: uploadURL
      )
      try await waitForTransfer(writeProgress)
      let writeDuration = max(Date().timeIntervalSince(writeStart), 0.001)
      let writeMBps = Double(sizeBytes) / writeDuration / 1_000_000

      let listParent = parentHandle == 0xFFFFFFFF ? nil : parentHandle
      uploadedHandle = try await findObjectHandle(
        device: device,
        storage: storageID,
        parent: listParent,
        name: benchFilename
      )

      let readStart = Date()
      let readProgress = try await device.read(handle: uploadedHandle!, range: nil, to: downloadURL)
      try await waitForTransfer(readProgress)
      let readDuration = max(Date().timeIntervalSince(readStart), 0.001)
      let readMBps = Double(sizeBytes) / readDuration / 1_000_000

      let iso = ISO8601DateFormatter()
      var rows = ["timestamp,operation,size_bytes,duration_seconds,speed_mbps"]
      rows.append(
        "\(iso.string(from: writeStart)),write,\(sizeBytes),\(String(format: "%.6f", writeDuration)),\(String(format: "%.3f", writeMBps))"
      )
      rows.append(
        "\(iso.string(from: readStart)),read,\(sizeBytes),\(String(format: "%.6f", readDuration)),\(String(format: "%.3f", readMBps))"
      )
      let csv = rows.joined(separator: "\n") + "\n"

      if let handle = uploadedHandle {
        try? await device.delete(handle, recursive: false)
      }

      return BenchResult(
        name: sizeLabel,
        csv: csv,
        readMBps: readMBps,
        writeMBps: writeMBps
      )
    } catch {
      if let handle = uploadedHandle {
        try? await device.delete(handle, recursive: false)
      }
      throw error
    }
  }

  private static func waitForTransfer(_ progress: Progress) async throws {
    while !progress.isFinished {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private static func createTempPayloadFile(name: String, sizeBytes: UInt64) throws -> URL {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    let testData = Data(repeating: 0xAA, count: Int(min(sizeBytes, 1024 * 1024)))
    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: tempURL)
    var written: UInt64 = 0
    while written < sizeBytes {
      let toWrite = min(UInt64(testData.count), sizeBytes - written)
      try fileHandle.write(contentsOf: testData.prefix(Int(toWrite)))
      written += toWrite
    }
    try fileHandle.close()
    return tempURL
  }

  private static func resolveCollectBenchTarget(
    device: any MTPDevice
  ) async throws -> (MTPStorageID, MTPObjectHandle) {
    let storages = try await device.storages()
    guard let targetStorage = storages.first(where: { !$0.isReadOnly }) ?? storages.first else {
      throw MTPError.preconditionFailed("No storage available")
    }

    let rootStream = device.list(parent: nil, in: targetStorage.id)
    var rootItems: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootItems.append(contentsOf: batch)
    }

    let folders = rootItems.filter { $0.formatCode == 0x3001 }
    let preferredNames = ["Download", "Downloads", "DCIM"]
    var safeFolder: MTPObjectInfo? = nil
    for name in preferredNames {
      if let match = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
        safeFolder = match
        break
      }
    }
    if safeFolder == nil {
      safeFolder = folders.first
    }
    guard let parent = safeFolder else { return (targetStorage.id, 0xFFFFFFFF) }

    let childStream = device.list(parent: parent.handle, in: targetStorage.id)
    var children: [MTPObjectInfo] = []
    for try await batch in childStream {
      children.append(contentsOf: batch)
    }

    if let benchFolder = children.first(where: {
      $0.name == "SwiftMTPBench" && $0.formatCode == 0x3001
    }) {
      return (targetStorage.id, benchFolder.handle)
    }

    let newHandle = try await device.createFolder(
      parent: parent.handle,
      name: "SwiftMTPBench",
      storage: targetStorage.id
    )
    return (targetStorage.id, newHandle)
  }

  private static func findObjectHandle(
    device: any MTPDevice,
    storage: MTPStorageID,
    parent: MTPObjectHandle?,
    name: String
  ) async throws -> MTPObjectHandle {
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream {
      if let match = batch.first(where: { $0.name == name }) {
        return match.handle
      }
    }
    throw MTPError.objectNotFound
  }

  private static func buildSubmissionManifest(
    summary: MTPDeviceSummary,
    probe: ProbeJSON,
    benchResults: [BenchResult],
    salt: Data
  ) -> SubmissionManifest {
    let serialSource = probe.deviceInfo.serial ?? summary.usbSerial ?? "unknown"
    let serialRedacted = Redaction.redactSerial(serialSource, salt: salt)
    let submitter = submitterUser()

    let interface = SubmissionManifest.InterfaceInfo(
      class: toHexByte(probe.fingerprint.interfaceTriple.class),
      subclass: toHexByte(probe.fingerprint.interfaceTriple.subclass),
      protocol: toHexByte(probe.fingerprint.interfaceTriple.protocol),
      in: toHexByte(probe.fingerprint.endpointAddresses.input),
      out: toHexByte(probe.fingerprint.endpointAddresses.output),
      evt: probe.fingerprint.endpointAddresses.event.map { toHexByte($0) }
    )

    let benchFiles = benchResults.map { "bench-\($0.name).csv" }

    return SubmissionManifest(
      tool: .init(
        version: normalizedBuildVersion(BuildInfo.version),
        commit: normalizedCommitHash(BuildInfo.git)
      ),
      host: .init(
        os: ProcessInfo.processInfo.operatingSystemVersionString,
        arch: hostArch()
      ),
      timestamp: ISO8601DateFormatter().string(from: Date()),
      user: submitter.map { .init(github: $0) },
      device: .init(
        vendorId: String(format: "0x%04x", summary.vendorID ?? 0),
        productId: String(format: "0x%04x", summary.productID ?? 0),
        bcdDevice: probe.fingerprint.bcdDevice.map { toHexWord($0) },
        vendor: summary.manufacturer,
        model: summary.model,
        interface: interface,
        fingerprintHash: sha256FingerprintHash(for: probe.fingerprint),
        serialRedacted: serialRedacted
      ),
      artifacts: .init(
        probe: "probe.json",
        usbDump: "usb-dump.txt",
        bench: benchFiles.isEmpty ? nil : benchFiles
      ),
      consent: .init(anonymizeSerial: true, allowBench: !benchResults.isEmpty)
    )
  }

  private static func buildQuirkSuggestion(
    summary: MTPDeviceSummary,
    tuning: EffectiveTuning,
    config: SwiftMTPConfig,
    benchResults: [BenchResult],
    submittedBy: String?
  ) -> QuirkSuggestion {
    var overrides: [String: AnyCodable] = [
      "maxChunkBytes": AnyCodable(tuning.maxChunkBytes),
      "ioTimeoutMs": AnyCodable(tuning.ioTimeoutMs),
      "handshakeTimeoutMs": AnyCodable(tuning.handshakeTimeoutMs),
      "inactivityTimeoutMs": AnyCodable(tuning.inactivityTimeoutMs),
      "overallDeadlineMs": AnyCodable(tuning.overallDeadlineMs),
      "stabilizeMs": AnyCodable(tuning.stabilizeMs),
      "postClaimStabilizeMs": AnyCodable(tuning.postClaimStabilizeMs),
      "postProbeStabilizeMs": AnyCodable(tuning.postProbeStabilizeMs),
      "resetOnOpen": AnyCodable(tuning.resetOnOpen),
      "disableEventPump": AnyCodable(tuning.disableEventPump)
    ]
    overrides["resumeEnabled"] = AnyCodable(config.resumeEnabled)

    let hooks: [QuirkSuggestion.Hook] = tuning.hooks.map { hook in
      .init(
        phase: hook.phase.rawValue,
        delayMs: hook.delayMs,
        busyBackoff: hook.busyBackoff.map {
          .init(retries: $0.retries, baseMs: $0.baseMs, jitterPct: $0.jitterPct)
        }
      )
    }

    let readGate = benchResults.isEmpty
      ? 0
      : benchResults.map(\.readMBps).reduce(0, +) / Double(benchResults.count)
    let writeGate = benchResults.isEmpty
      ? 0
      : benchResults.map(\.writeMBps).reduce(0, +) / Double(benchResults.count)

    return QuirkSuggestion(
      id: quirkIdentifier(for: summary),
      match: .init(
        vidPid: String(format: "0x%04X:0x%04X", summary.vendorID ?? 0, summary.productID ?? 0)
      ),
      status: "experimental",
      confidence: benchResults.isEmpty ? "low" : "medium",
      overrides: overrides,
      hooks: hooks,
      benchGates: .init(
        readMBps: round(readGate * 100) / 100,
        writeMBps: round(writeGate * 100) / 100
      ),
      provenance: .init(
        submittedBy: submittedBy,
        date: utcDateStamp()
      )
    )
  }

  private static func quirkIdentifier(for summary: MTPDeviceSummary) -> String {
    let base = slugify("\(summary.manufacturer)-\(summary.model)")
    let pid = String(format: "%04x", summary.productID ?? 0)
    return "\(base)-\(pid)"
  }

  private static func sha256FingerprintHash(for fingerprint: MTPDeviceFingerprint) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(fingerprint)) ?? Data(fingerprint.hashString.utf8)
    let digest = SHA256.hash(data: data)
    return "sha256:" + digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private static func normalizedBuildVersion(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.range(of: #"^\d+\.\d+\.\d+.*$"#, options: .regularExpression) != nil {
      return trimmed
    }
    if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
      let dropped = String(trimmed.dropFirst())
      if dropped.range(of: #"^\d+\.\d+\.\d+.*$"#, options: .regularExpression) != nil {
        return dropped
      }
    }
    return "0.0.0"
  }

  private static func normalizedCommitHash(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard trimmed.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression) != nil else {
      return nil
    }
    return trimmed
  }

  private static func submitterUser() -> String? {
    let env = ProcessInfo.processInfo.environment
    return env["GITHUB_USER"] ?? env["GITHUB_ACTOR"] ?? env["USER"]
  }

  private static func hostArch() -> String {
#if arch(arm64)
    return "arm64"
#elseif arch(x86_64)
    return "x86_64"
#elseif arch(i386)
    return "i386"
#else
    return "unknown"
#endif
  }

  private static func toHexByte(_ raw: String) -> String {
    let cleaned = raw.lowercased().hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
    guard let value = UInt64(cleaned, radix: 16) else { return "0x00" }
    return String(format: "0x%02llx", value)
  }

  private static func toHexWord(_ raw: String) -> String {
    let cleaned = raw.lowercased().hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
    guard let value = UInt64(cleaned, radix: 16) else { return "0x0000" }
    return String(format: "0x%04llx", value)
  }

  private static func utcDateStamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private static func slugify(_ value: String) -> String {
    let lower = value.lowercased()
    let slug = lower
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? "device" : slug
  }

  // MARK: - Common utilities

  private static func writeJSONFile<T: Encodable>(_ value: T, to url: URL) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try enc.encode(value)
    try data.write(to: url, options: .atomic)
  }

  private static func prepareBundlePath(flags: Flags, summary: MTPDeviceSummary) throws -> URL {
    let fm = FileManager.default
    let base: URL
    if let b = flags.bundlePath {
      base = URL(fileURLWithPath: b, isDirectory: true)
    } else {
      let root = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
      let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
      let namePrefix: String
      if let customName = flags.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
         !customName.isEmpty {
        namePrefix = slugify(customName)
      } else {
        namePrefix = String(format: "device-%04x-%04x", summary.vendorID ?? 0, summary.productID ?? 0)
      }
      let name = "\(namePrefix)-\(stamp)"
      base = root.appendingPathComponent("Contrib/submissions/\(name)", isDirectory: true)
    }
    try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base
  }

  /// Execute `op` with a wall-clock deadline (ms). Cancels the task on timeout.
  private static func within<T: Sendable>(ms: Int, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await op() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        throw CollectError.timeout(ms)
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  // MARK: - Models

  enum CollectError: LocalizedError {
    case noDeviceMatched(candidates: [CollectCommand.DeviceCandidate])
    case ambiguousSelection(count: Int, candidates: [CollectCommand.DeviceCandidate])
    case timeout(Int)
    case redactionCheckFailed([String])
    case invalidBenchSize(String)

    var errorDescription: String? {
      switch self {
      case .noDeviceMatched: return "No device matched the provided filter."
      case .ambiguousSelection(let n, _): return "Multiple devices matched the filter (\(n))."
      case .timeout(let ms): return "Step exceeded deadline (\(ms) ms)."
      case .redactionCheckFailed(let issues):
        return "Debug-artifact redaction check failed: \(issues.joined(separator: ", "))."
      case .invalidBenchSize(let size):
        return "Invalid benchmark size '\(size)'. Expected values like 100M, 500M, or 1G."
      }
    }
  }

  struct DeviceCandidate: Codable, Sendable {
    let vid: String
    let pid: String
    let bus: Int
    let address: Int
    let manufacturer: String
    let model: String

    init(from summary: MTPDeviceSummary) {
      self.vid = String(format: "%04x", summary.vendorID ?? 0)
      self.pid = String(format: "%04x", summary.productID ?? 0)
      self.bus = Int(summary.bus ?? 0)
      self.address = Int(summary.address ?? 0)
      self.manufacturer = summary.manufacturer
      self.model = summary.model
    }
  }

  private struct CollectionOutput: Codable, Sendable {
    let schemaVersion: String
    let timestamp: String
    let bundlePath: String
    let deviceVID: UInt16
    let devicePID: UInt16
    let bus: Int
    let address: Int
    let mode: String
  }

  // MARK: - Public types for external consumption (e.g., LearnPromoteCommand)

  public struct SubmissionManifest: Codable {
    var schemaVersion: String = "1.0.0"
    let tool: ToolInfo
    let host: HostInfo
    let timestamp: String
    let user: UserInfo?
    let device: DeviceInfo
    let artifacts: ArtifactInfo
    let consent: ConsentInfo

    public struct ToolInfo: Codable {
      var name: String = "swiftmtp"
      let version: String
      let commit: String?
    }

    public struct HostInfo: Codable {
      let os: String
      let arch: String
    }

    public struct UserInfo: Codable {
      let github: String?
    }

    public struct DeviceInfo: Codable {
      let vendorId: String
      let productId: String
      let bcdDevice: String?
      let vendor: String
      let model: String
      let interface: InterfaceInfo
      let fingerprintHash: String
      let serialRedacted: String
    }

    public struct InterfaceInfo: Codable {
      let `class`: String
      let subclass: String
      let `protocol`: String
      let `in`: String
      let `out`: String
      let evt: String?
    }

    public struct ArtifactInfo: Codable {
      let probe: String
      let usbDump: String
      let bench: [String]?
    }

    public struct ConsentInfo: Codable {
      let anonymizeSerial: Bool
      let allowBench: Bool
    }
  }

  public struct QuirkSuggestion: Codable {
    var schemaVersion: String = "1.0.0"
    let id: String
    let match: MatchCriteria
    var status: String = "experimental"
    var confidence: String = "low"
    let overrides: [String: AnyCodable]
    let hooks: [Hook]
    let benchGates: BenchGates
    let provenance: Provenance

    public struct MatchCriteria: Codable {
      let vidPid: String
    }

    public struct Hook: Codable {
      let phase: String
      let delayMs: Int?
      let busyBackoff: BusyBackoff?

      public struct BusyBackoff: Codable {
        let retries: Int
        let baseMs: Int
        let jitterPct: Double
      }
    }

    public struct BenchGates: Codable {
      let readMBps: Double
      let writeMBps: Double
    }

    public struct Provenance: Codable {
      let submittedBy: String?
      let date: String
    }
  }

  public struct AnyCodable: Codable {
    let value: Any

    public init(_ value: Any) {
      self.value = value
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
}
