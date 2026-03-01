// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.
//
// Hands-off DocC device page generator.
// Usage: swift run swiftmtp-docs <quirks.json> [output_dir]
// Default output_dir: Docs/SwiftMTP.docc/Devices/

import Foundation

// MARK: - Data Models

struct QuirksFile: Codable {
  let version: Int
  let entries: [QuirkEntry]
}

struct QuirkEntry: Codable {
  let id: String
  let match: MatchCriteria
  let tuning: TuningParameters?
  let ops: OperationSupport?
  let benchGates: BenchmarkGates?
  let notes: [String]?
  let provenance: Provenance?
  let status: Status
  let evidenceRequired: [String]?
  let lastVerifiedDate: String?
  let lastVerifiedBy: String?
  let category: String?
  let flags: Flags?
  let confidence: String?
  let hooks: [Hook]?
  let governance: Governance?
  let deviceName: String?
  let label: String?
  let name: String?
  let transport: Transport?
  let behaviorLimitations: [String]?
  let warnings: [String]?
  let probeLadder: [String]?

  enum Status: String, Codable {
    case experimental, stable, deprecated
    case proposed, verified, promoted

    init(from decoder: Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(String.self)
      self = Status(rawValue: raw) ?? .proposed
    }
  }

  struct Flags: Codable {
    // Accept any keys
    init(from decoder: Decoder) throws {
      _ = try decoder.container(keyedBy: DynamicCodingKeys.self)
    }
    func encode(to encoder: Encoder) throws {}
    private struct DynamicCodingKeys: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init?(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { return nil }
    }
  }

  struct Hook: Codable {
    let phase: String?
    let action: String?
    init(from decoder: Decoder) throws {
      if let container = try? decoder.container(keyedBy: CodingKeys.self) {
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        action = try container.decodeIfPresent(String.self, forKey: .action)
      } else {
        phase = nil
        action = nil
      }
    }
    enum CodingKeys: String, CodingKey { case phase, action }
  }

  struct Governance: Codable {
    init(from decoder: Decoder) throws {
      _ = try decoder.container(keyedBy: DynamicCodingKeys.self)
    }
    func encode(to encoder: Encoder) throws {}
    private struct DynamicCodingKeys: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init?(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { return nil }
    }
  }

  struct Transport: Codable {
    init(from decoder: Decoder) throws {
      _ = try decoder.container(keyedBy: DynamicCodingKeys.self)
    }
    func encode(to encoder: Encoder) throws {}
    private struct DynamicCodingKeys: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init?(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { return nil }
    }
  }
}

struct MatchCriteria: Codable {
  let vid: String?
  let pid: String?
  let deviceInfoRegex: String?
  let iface: InterfaceDescriptor?
  let endpoints: EndpointAddresses?
  let interfaceClass: String?
  let interfaceSubclass: String?
  let interfaceProtocol: String?
}

struct InterfaceDescriptor: Codable {
  let `class`: String?
  let subclass: String?
  let `protocol`: String?
}

struct EndpointAddresses: Codable {
  let input: String?
  let output: String?
  let event: String?

  enum CodingKeys: String, CodingKey {
    case input = "in"
    case output = "out"
    case event = "evt"
  }
}

struct TuningParameters: Codable {
  let maxChunkBytes: Int?
  let handshakeTimeoutMs: Int?
  let ioTimeoutMs: Int?
  let inactivityTimeoutMs: Int?
  let overallDeadlineMs: Int?
  let stabilizeMs: Int?
  let eventPumpDelayMs: Int?
  let chunkSize: Int?
  let timeoutMs: Int?
  let maxRetries: Int?
  let resetOnOpen: Bool?
  let maxPayload: Int?
  let windowSize: Int?
  let maxPacketSize: Int?
  let requiresKernelDetach: Bool?
  let postClaimStabilizeMs: Int?
  let alternateInterfaceSelection: Int?
  let skipPTPReset: Bool?
  let forceConfigurationNumber: Int?
  let forceAltSetting: Int?
  let disableEventPump: Bool?
  let postProbeStabilizeMs: Int?
}

struct OperationSupport: Codable {
  let supportsGetPartialObject64: Bool?
  let supportsSendPartialObject: Bool?
  let preferGetObjectPropList: Bool?
  let disableWriteResume: Bool?
  let supportsGetObjectPropList: Bool?
  let supportsGetPartialObject: Bool?
  let getPartialObject: Bool?
  let sendPartialObject: Bool?
  let useAndroidExtensions: Bool?
  let openSession: Bool?
  let getDeviceInfo: Bool?
  let getStorageIDs: Bool?
  let getObjectHandles: Bool?
  let getObject: Bool?
  let sendObject: Bool?
  let skipGetObjectPropValue: Bool?
  let getObjectPropList: Bool?
  let deleteObject: Bool?
  let supportsEvents: Bool?
}

struct BenchmarkGates: Codable {
  let readMBpsMin: Double?
  let writeMBpsMin: Double?
}

struct Provenance: Codable {
  let author: String?
  let date: String?
  let commit: String?
  let artifacts: Artifacts?
  let source: String?
  let notes: String?
  let confidence: String?
  let addedDate: String?
  let sourceRef: String?
  let origin: String?
  let deviceName: String?
  let libmtpFlags: String?
}

struct Artifacts: Codable {
  let probe: String?
  let usbDump: String?
  let bench100M: String?
  let bench1G: String?
  let mirrorLog: String?
}

// MARK: - DocC Generation

func generateDocCPage(for entry: QuirkEntry) -> String {
  let vendor = extractVendor(from: entry.id)
  let model = extractModel(from: entry.id)

  var content = """
    # \(vendor) \(model)

    @Metadata {
        @DisplayName: "\(vendor) \(model)"
        @PageKind: article
        @Available: iOS 15.0, macOS 12.0
    }

    Device-specific configuration for \(vendor) \(model) MTP implementation.

    ## Identity

    | Property | Value |
    |----------|-------|
    | Vendor ID | \(entry.match.vid ?? "Unknown") |
    | Product ID | \(entry.match.pid ?? "Unknown") |
    | Device Info Pattern | `\(entry.match.deviceInfoRegex ?? "None")` |
    | Status | \(entry.status.rawValue.capitalized) |

    """

  if let iface = entry.match.iface {
    content += """

      ## Interface

      | Property | Value |
      |----------|-------|
      | Class | \(iface.class ?? "Unknown") |
      | Subclass | \(iface.subclass ?? "Unknown") |
      | Protocol | \(iface.`protocol` ?? "Unknown") |
      """
  }

  if let endpoints = entry.match.endpoints {
    content += """

      ## Endpoints

      | Property | Value |
      |----------|-------|
      | Input Endpoint | \(endpoints.input ?? "Unknown") |
      | Output Endpoint | \(endpoints.output ?? "Unknown") |
      | Event Endpoint | \(endpoints.event ?? "Unknown") |
      """
  }

  if let tuning = entry.tuning {
    content += """

      ## Tuning Parameters

      | Parameter | Value | Unit |
      |-----------|-------|------|
      | Maximum Chunk Size | \(tuning.maxChunkBytes.map { formatBytes($0) } ?? "default") | bytes |
      | Handshake Timeout | \(tuning.handshakeTimeoutMs.map(String.init) ?? "default") | ms |
      | I/O Timeout | \(tuning.ioTimeoutMs.map(String.init) ?? "default") | ms |
      | Inactivity Timeout | \(tuning.inactivityTimeoutMs.map(String.init) ?? "default") | ms |
      | Overall Deadline | \(tuning.overallDeadlineMs.map(String.init) ?? "default") | ms |
      """

    if let stabilize = tuning.stabilizeMs, stabilize > 0 {
      content += "| Stabilization Delay | \(stabilize) | ms |\n"
    }

    if let eventDelay = tuning.eventPumpDelayMs, eventDelay > 0 {
      content += "| Event Pump Delay | \(eventDelay) | ms |\n"
    }
  }

  if let ops = entry.ops {
    content += """

      ## Operation Support

      | Operation | Supported |
      |-----------|-----------|
      """

    if let partial64 = ops.supportsGetPartialObject64 {
      content += "| 64-bit Partial Object Retrieval | \(partial64 ? "Yes" : "No") |\n"
    }

    if let sendPartial = ops.supportsSendPartialObject {
      content += "| Partial Object Sending | \(sendPartial ? "Yes" : "No") |\n"
    }

    if let preferPropList = ops.preferGetObjectPropList {
      content += "| Prefer Object Property List | \(preferPropList ? "Yes" : "No") |\n"
    }

    if let disableResume = ops.disableWriteResume {
      content += "| Write Resume Disabled | \(disableResume ? "Yes" : "No") |\n"
    }
  }

  if let gates = entry.benchGates {
    content += """

      ## Performance Gates

      | Operation | Minimum Throughput |
      |-----------|-------------------|
      """

    if let readMin = gates.readMBpsMin {
      content += "| Read | \(readMin) MB/s |\n"
    }

    if let writeMin = gates.writeMBpsMin {
      content += "| Write | \(writeMin) MB/s |\n"
    }
  }

  if let notes = entry.notes, !notes.isEmpty {
    content += """

      ## Notes

      \(notes.map { "- \($0)" }.joined(separator: "\n"))
      """
  }

  if let provenance = entry.provenance {
    content += """

      ## Provenance

      - **Author**: \(provenance.author ?? "Unknown")
      - **Date**: \(provenance.date ?? "Unknown")
      - **Commit**: \(provenance.commit ?? "Unknown")

      ### Evidence Artifacts

      """

    if let artifacts = provenance.artifacts {
      if let probe = artifacts.probe {
        content += "- [Device Probe](\(probe))\n"
      }
      if let usbDump = artifacts.usbDump {
        content += "- [USB Dump](\(usbDump))\n"
      }
      if let bench100M = artifacts.bench100M {
        content += "- [100MB Benchmark](\(bench100M))\n"
      }
      if let bench1G = artifacts.bench1G {
        content += "- [1GB Benchmark](\(bench1G))\n"
      }
      if let mirrorLog = artifacts.mirrorLog {
        content += "- [Mirror Log](\(mirrorLog))\n"
      }
    }
  }

  return content
}

func extractVendor(from id: String) -> String {
  let components = id.split(separator: "-")
  return components.first?.capitalized ?? "Unknown"
}

func extractModel(from id: String) -> String {
  let components = id.split(separator: "-").dropFirst()
  return components.joined(separator: " ").capitalized
}

func formatBytes(_ bytes: Int) -> String {
  let formatter = ByteCountFormatter()
  formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
  formatter.countStyle = .file
  return formatter.string(fromByteCount: Int64(bytes))
}

// MARK: - Main

func main() {
  let args = CommandLine.arguments

  guard args.count >= 2 else {
    print("Usage: \(args[0]) <quirks.json> [output_dir]")
    exit(1)
  }

  let quirksPath = args[1]
  let outputDir = args.count > 2 ? args[2] : "./Docs/SwiftMTP.docc/Devices"

  do {
    let quirksURL = URL(fileURLWithPath: quirksPath)
    let quirksData = try Data(contentsOf: quirksURL)
    let quirks = try JSONDecoder().decode(QuirksFile.self, from: quirksData)

    let outputURL = URL(fileURLWithPath: outputDir)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    for entry in quirks.entries {
      let filename = "\(entry.id).md"
      let fileURL = outputURL.appendingPathComponent(filename)
      let content = generateDocCPage(for: entry)

      try content.write(to: fileURL, atomically: true, encoding: .utf8)
      print("Generated: \(filename)")
    }

    print("✅ Generated \(quirks.entries.count) device documentation pages")

  } catch {
    print("❌ Error: \(error)")
    exit(1)
  }
}

main()
