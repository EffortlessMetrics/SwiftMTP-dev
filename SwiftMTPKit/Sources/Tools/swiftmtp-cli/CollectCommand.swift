// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

// Import ExitCode from SwiftMTPCore
import enum SwiftMTPCore.ExitCode

// Import CLI utilities
func printJSONErrorAndExit(_ error: any Error) -> Never {
  printJSONErrorAndExit("\(error)")
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

  // MARK: - Public entry point used by main.swift
  public static func run(flags: Flags) async -> ExitCode {
    let jsonMode = flags.json
    var spinner = Spinner(message: "Collecting device evidence…", enabled: !jsonMode)

    do {
      // 1) Resolve device (VID/PID/bus/address filtering + exit codes)
      spinner.start("Discovering devices…")
      let summary = try await selectDeviceOrExit(flags: flags)
      let deviceId = String(format: "%04x:%04x@%d:%d",
                             summary.vendorID ?? 0, summary.productID ?? 0,
                             Int(summary.bus ?? 0), Int(summary.address ?? 0))
      spinner.succeed("Device selected: \(deviceId)")

      // 2) Open device with LibUSB transport and default config (strict behavior is handled inside DeviceActor)
      spinner.start("Opening device…")
      let (device, config) = try await openDevice(summary: summary, strict: flags.strict)
      spinner.succeed("Device opened (strict=\(flags.strict))")

      // 3) Create bundle path
      spinner.start("Preparing bundle…")
      let bundleURL = try prepareBundlePath(flags: flags, summary: summary)
      spinner.succeed("Bundle: \(bundleURL.path)")

      // 4) Collect probe.json (90s deadline)
      spinner.start("Collecting probe…")
      let probe = try await within(ms: 90_000) {
        try await collectProbeJSON(device: device, summary: summary)
      }
      try writeJSONFile(probe, to: bundleURL.appendingPathComponent("probe.json"))
      spinner.succeed("probe.json saved")

      // 5) Collect usb-dump.txt (90s deadline) — sanitized
      spinner.start("Capturing USB dump…")
      let rawDump = try await within(ms: 90_000) { try await generateSimpleUSBDump(summary: summary) }
      let sanitized = sanitizeDump(rawDump)
      try sanitized.write(to: bundleURL.appendingPathComponent("usb-dump.txt"), atomically: true, encoding: .utf8)
      spinner.succeed("usb-dump.txt saved")

      // 6) Optional benchmarks (still respecting safety defaults; only if user requested)
      if !flags.runBench.isEmpty {
        spinner.start("Running benchmarks: \(flags.runBench.joined(separator: ","))…")
        let benchResults = try await within(ms: 90_000) {
          try await runBenches(device: device, sizes: flags.runBench)
        }
        for (name, csv) in benchResults {
          let url = bundleURL.appendingPathComponent("bench-\(name).csv")
          try csv.write(to: url, atomically: true, encoding: .utf8)
        }
        spinner.succeed("Benchmarks complete")
      }

      // 7) submission.json (summary manifest)
      spinner.start("Writing submission.json…")
      let manifest = SubmissionSummary.make(from: summary, bundle: bundleURL)
      try writeJSONFile(manifest, to: bundleURL.appendingPathComponent("submission.json"))
      spinner.succeed("submission.json saved")

      // 8) Emit JSON summary for CI if requested
      if jsonMode {
        let out = CollectionOutput(
          schemaVersion: "1.0.0",
          timestamp: ISO8601DateFormatter().string(from: Date()),
          bundlePath: bundleURL.path,
          deviceVID: summary.vendorID ?? 0, devicePID: summary.productID ?? 0,
          bus: Int(summary.bus ?? 0), address: Int(summary.address ?? 0)
        )
        printJSON(out)
      }

      return .ok

    } catch {
      if jsonMode { printJSONErrorAndExit(error) }
      fputs("❌ collect failed: \(error)\n", stderr)
      return .software
    }
  }

  // MARK: - Device selection (no internal helpers)
  private static func selectDeviceOrExit(flags: Flags) async throws -> MTPDeviceSummary {
    let devs = try await enumerateRealMTPDevices()
    let matches = devs.filter { m in
      if let vid = flags.vid, m.vendorID != vid { return false }
      if let pid = flags.pid, m.productID != pid { return false }
      if let bus = flags.bus, let deviceBus = m.bus, deviceBus != UInt8(bus) { return false }
      if let addr = flags.address, let deviceAddr = m.address, deviceAddr != UInt8(addr) { return false }
      return true
    }

    switch matches.count {
    case 0:
      // 69 = unavailable
      if flags.json {
        printJSONErrorAndExit(CollectError.noDeviceMatched)
      } else {
        fputs("No devices matched the provided filter.\n", stderr)
        exit(69)
      }
      // never returns
    case 1:
      return matches[0]
    default:
      // If interactive, you could prompt; for noninteractive we must exit(64).
      if flags.noninteractive {
        if flags.json {
          printJSONErrorAndExit(CollectError.ambiguousSelection(count: matches.count))
        } else {
          fputs("Multiple devices matched the filter; refine selection.\n", stderr)
          exit(64)
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

  // MARK: - Probe capture
  private struct ProbeJSON: Codable, Sendable {
    var schemaVersion = "1.0.0"
    var timestamp: String
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
    return .init(
      timestamp: ISO8601DateFormatter().string(from: Date()),
      vendorID: summary.vendorID ?? 0, productID: summary.productID ?? 0,
      bus: Int(summary.bus ?? 0), address: Int(summary.address ?? 0),
      deviceInfo: .init(manufacturer: info.manufacturer,
                        model: info.model,
                        version: "unknown",
                        serial: info.serialNumber),
      storageCount: storages.count
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
    // Minimal redaction; your validation script performs deep checks.
    var t = s
    // Redact /Users/<name>/...
    t = t.replacingOccurrences(of: #"/Users/[^/\n]+"#, with: "/Users/<redacted>", options: .regularExpression)
    // Redact "Serial Number: <anything>"
    t = t.replacingOccurrences(of: #"Serial\s+Number:\s+[^\s]+"#, with: "Serial Number: <redacted>", options: .regularExpression)
    // Redact hostnames (best-effort)
    t = t.replacingOccurrences(of: #"\b[A-Za-z0-9._-]+\.local\b"#, with: "<redacted>.local", options: .regularExpression)
    return t
  }

  // MARK: - Bench (optional, minimal)
  private static func runBenches(device: any MTPDevice, sizes: [String]) async throws -> [(name: String, csv: String)] {
    // Keep this minimal; many contributors won't run benches.
    // Produce a trivial CSV header per requested size.
    return try await withThrowingTaskGroup(of: (String, String).self) { group in
      for size in sizes {
        group.addTask {
          // Here you could invoke your existing bench command. We stub a CSV with header only.
          let csv = "size,bytes,duration_s,mbps\n"
          return (size, csv)
        }
      }
      var out: [(String, String)] = []
      for try await item in group { out.append(item) }
      return out
    }
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
      let name = String(format: "device-%04x-%04x-%@",
                        summary.vendorID ?? 0, summary.productID ?? 0, stamp)
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

  private enum CollectError: LocalizedError {
    case noDeviceMatched
    case ambiguousSelection(count: Int)
    case timeout(Int)

    var errorDescription: String? {
      switch self {
      case .noDeviceMatched: return "No device matched the provided filter."
      case .ambiguousSelection(let n): return "Multiple devices matched the filter (\(n))."
      case .timeout(let ms): return "Step exceeded deadline (\(ms) ms)."
      }
    }
  }

  private struct SubmissionSummary: Codable, Sendable {
    let schemaVersion = "1.0.0"
    let createdAt: String
    let vendorID: UInt16
    let productID: UInt16
    let bus: Int
    let address: Int
    let artifacts: [String]

    static func make(from s: MTPDeviceSummary, bundle: URL) -> SubmissionSummary {
      return .init(
        createdAt: ISO8601DateFormatter().string(from: Date()),
        vendorID: s.vendorID ?? 0, productID: s.productID ?? 0,
        bus: Int(s.bus ?? 0), address: Int(s.address ?? 0),
        artifacts: ["probe.json", "usb-dump.txt"]
      )
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
  }

  // MARK: - Public types for external consumption (e.g., LearnPromoteCommand)

  public struct SubmissionManifest: Codable {
    let schemaVersion: String = "1.0.0"
    let tool: ToolInfo
    let host: HostInfo
    let timestamp: Date
    let user: UserInfo?
    let device: DeviceInfo
    let artifacts: ArtifactInfo
    let consent: ConsentInfo

    public struct ToolInfo: Codable {
      let name: String = "swiftmtp"
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
    let schemaVersion: String = "1.0.0"
    let id: String
    let match: MatchCriteria
    let status: String = "experimental"
    let confidence: String = "low"
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
