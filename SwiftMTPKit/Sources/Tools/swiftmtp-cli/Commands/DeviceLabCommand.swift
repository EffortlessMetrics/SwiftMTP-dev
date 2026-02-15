// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@_spi(Dev) import SwiftMTPCore
import SwiftMTPTransportLibUSB

@MainActor
struct DeviceLabCommand {
  private enum ExpectedPolicy: String, Codable, Sendable {
    case fullExercise = "full-exercise"
    case probeNoCrash = "probe-no-crash"
    case readBestEffort = "read-best-effort"
    case blockerExpected = "blocker-expected"
    case generic = "generic"
  }

  private enum DeviceOutcome: String, Codable, Sendable {
    case passed
    case partial
    case blocked
    case failed
  }

  private struct ReadValidation: Codable, Sendable {
    var openSucceeded = false
    var deviceInfoSucceeded = false
    var storagesSucceeded = false
    var rootListingSucceeded = false
    var storageCount = 0
    var rootObjectCount: Int?
    var error: String?
  }

  private struct WriteSmoke: Codable, Sendable {
    var attempted = false
    var succeeded = false
    var skipped = false
    var reason: String?
    var bytesUploaded = 0
    var remoteFolder: String?
    var remoteFile: String?
    var warning: String?
    var error: String?
  }

  private struct ArtifactPaths: Codable, Sendable {
    var directory: String
    var reportJSON: String
    var harnessReportJSON: String?
    var probeReceiptJSON: String?
    var usbInterfaceJSON: String?
  }

  private struct DeviceResult: Codable, Sendable {
    let id: String
    let vidpid: String
    let bus: Int
    let address: Int
    let manufacturer: String
    let model: String
    let expectation: ExpectedPolicy
    var outcome: DeviceOutcome
    var read: ReadValidation
    var write: WriteSmoke
    var notes: [String]
    var error: String?
    var capabilityReport: DeviceLabReport?
    var probeReceipt: ProbeReceipt?
    let usbInterfaceDump: USBDumper.DumpDevice?
    var artifacts: ArtifactPaths
  }

  private struct ReportSummary: Codable, Sendable {
    let totalDevices: Int
    let passed: Int
    let partial: Int
    let blocked: Int
    let failed: Int
    let missingExpected: [String]
  }

  private struct ConnectedLabReport: Codable, Sendable {
    let schemaVersion: String
    let generatedAt: Date
    let outputPath: String
    let connectedDeviceCount: Int
    let summary: ReportSummary
    let devices: [DeviceResult]
  }

  private static let expectedPolicies: [String: ExpectedPolicy] = [
    "2717:ff40": .fullExercise,
    "2a70:f003": .probeNoCrash,
    "04e8:6860": .readBestEffort,
    "18d1:4ee1": .blockerExpected,
  ]

  static func run(flags: CLIFlags, args: [String]) async {
    guard let mode = args.first, mode == "connected" else {
      printUsage()
      exitNow(.usage)
    }

    do {
      let outputDir = try resolveOutputDirectory(args: Array(args.dropFirst()))
      try FileManager.default.createDirectory(
        at: outputDir, withIntermediateDirectories: true, attributes: nil)

      let usbDump = try USBDumper().collect()
      let usbDumpURL = outputDir.appendingPathComponent("usb-dump.json")
      try writeJSON(usbDump, to: usbDumpURL)

      let connected = try await LibUSBDiscovery.enumerateMTPDevices()
      if connected.isEmpty {
        if flags.json {
          let emptySummary = ReportSummary(
            totalDevices: 0, passed: 0, partial: 0, blocked: 0, failed: 0,
            missingExpected: Array(expectedPolicies.keys).sorted())
          let emptyReport = ConnectedLabReport(
            schemaVersion: "1.0.0",
            generatedAt: Date(),
            outputPath: outputDir.path,
            connectedDeviceCount: 0,
            summary: emptySummary,
            devices: []
          )
          printEncodedJSON(emptyReport)
        } else {
          print("No connected MTP devices found.")
        }
        exitNow(.unavailable)
      }

      let devicesRoot = outputDir.appendingPathComponent("devices")
      try FileManager.default.createDirectory(
        at: devicesRoot, withIntermediateDirectories: true, attributes: nil)

      var results: [DeviceResult] = []
      for summary in connected.sorted(by: { deviceSortOrder($0, $1) }) {
        let vidpid = formatVIDPID(summary)
        let slug =
          "\(vidpid.replacingOccurrences(of: ":", with: "-"))-b\(summary.bus ?? 0)-a\(summary.address ?? 0)"
        let deviceDir = devicesRoot.appendingPathComponent(slug)
        try FileManager.default.createDirectory(
          at: deviceDir, withIntermediateDirectories: true, attributes: nil)

        let usbDevice = findUSBDumpDevice(for: summary, in: usbDump.devices)
        var result = await runPerDevice(
          summary: summary, expectation: expectedPolicies[vidpid] ?? .generic, flags: flags,
          usbDumpDevice: usbDevice, deviceDir: deviceDir)

        // Persist per-device artifacts.
        let reportURL = deviceDir.appendingPathComponent("device-report.json")
        result.artifacts.reportJSON = reportURL.lastPathComponent
        try writeJSON(result, to: reportURL)

        if let receipt = result.probeReceipt {
          let receiptURL = deviceDir.appendingPathComponent("probe-receipt.json")
          result.artifacts.probeReceiptJSON = receiptURL.lastPathComponent
          try writeJSON(receipt, to: receiptURL)
          try writeJSON(result, to: reportURL)
        }

        if let capabilityReport = result.capabilityReport {
          let harnessURL = deviceDir.appendingPathComponent("harness-report.json")
          result.artifacts.harnessReportJSON = harnessURL.lastPathComponent
          try writeJSON(capabilityReport, to: harnessURL)
          try writeJSON(result, to: reportURL)
        }

        if let usbDevice {
          let usbURL = deviceDir.appendingPathComponent("usb-interface.json")
          result.artifacts.usbInterfaceJSON = usbURL.lastPathComponent
          try writeJSON(usbDevice, to: usbURL)
          try writeJSON(result, to: reportURL)
        }

        results.append(result)
      }

      let discoveredVIDPIDs = Set(results.map(\.vidpid))
      let missingExpected = expectedPolicies.keys.sorted()
        .filter { !discoveredVIDPIDs.contains($0) }

      let summary = ReportSummary(
        totalDevices: results.count,
        passed: results.filter { $0.outcome == .passed }.count,
        partial: results.filter { $0.outcome == .partial }.count,
        blocked: results.filter { $0.outcome == .blocked }.count,
        failed: results.filter { $0.outcome == .failed }.count,
        missingExpected: missingExpected
      )

      let report = ConnectedLabReport(
        schemaVersion: "1.0.0",
        generatedAt: Date(),
        outputPath: outputDir.path,
        connectedDeviceCount: connected.count,
        summary: summary,
        devices: results
      )

      let reportJSONURL = outputDir.appendingPathComponent("connected-lab.json")
      try writeJSON(report, to: reportJSONURL)
      let reportMDURL = outputDir.appendingPathComponent("connected-lab.md")
      try writeMarkdown(report: report, to: reportMDURL)

      if flags.json {
        printEncodedJSON(report)
      } else {
        print("Connected device lab complete.")
        print("Output: \(outputDir.path)")
        print(
          "Devices: \(summary.totalDevices)  passed=\(summary.passed) partial=\(summary.partial) blocked=\(summary.blocked) failed=\(summary.failed)"
        )
        if !missingExpected.isEmpty {
          print("Missing expected VID:PID: \(missingExpected.joined(separator: ", "))")
        }
      }
    } catch {
      print("❌ device-lab failed: \(error)")
      exitNow(.tempfail)
    }
  }

  private static func runPerDevice(
    summary: MTPDeviceSummary,
    expectation: ExpectedPolicy,
    flags: CLIFlags,
    usbDumpDevice: USBDumper.DumpDevice?,
    deviceDir: URL
  ) async -> DeviceResult {
    let vidpid = formatVIDPID(summary)
    var result = DeviceResult(
      id: summary.id.raw,
      vidpid: vidpid,
      bus: Int(summary.bus ?? 0),
      address: Int(summary.address ?? 0),
      manufacturer: summary.manufacturer,
      model: summary.model,
      expectation: expectation,
      outcome: .failed,
      read: ReadValidation(),
      write: WriteSmoke(),
      notes: [],
      error: nil,
      capabilityReport: nil,
      probeReceipt: nil,
      usbInterfaceDump: usbDumpDevice,
      artifacts: ArtifactPaths(
        directory: deviceDir.lastPathComponent,
        reportJSON: "device-report.json",
        harnessReportJSON: nil,
        probeReceiptJSON: nil,
        usbInterfaceJSON: nil
      )
    )

    let perDeviceFlags = CLIFlags(
      realOnly: true,
      useMock: false,
      mockProfile: flags.mockProfile,
      json: flags.json,
      jsonlOutput: flags.jsonlOutput,
      traceUSB: flags.traceUSB,
      strict: flags.strict,
      safe: flags.safe,
      traceUSBDetails: flags.traceUSBDetails,
      targetVID: summary.vendorID.map { String(format: "0x%04x", $0) },
      targetPID: summary.productID.map { String(format: "0x%04x", $0) },
      targetBus: summary.bus.map(Int.init),
      targetAddress: summary.address.map(Int.init)
    )

    do {
      let device = try await openDevice(flags: perDeviceFlags)

      do {
        try await device.openIfNeeded()
        result.read.openSucceeded = true
      } catch {
        let message = "open failed: \(error)"
        result.read.error = message
        result.error = message
        try? await device.devClose()
        finalizeOutcome(&result)
        return result
      }

      result.probeReceipt = await device.probeReceipt
      result.capabilityReport = try? await DeviceLabHarness().collect(device: device)

      do {
        _ = try await device.info
        result.read.deviceInfoSucceeded = true
      } catch {
        let message = "device info failed: \(error)"
        result.read.error = result.read.error ?? message
        result.error = result.error ?? message
      }

      var storages: [MTPStorageInfo] = []
      do {
        storages = try await device.storages()
        result.read.storagesSucceeded = true
        result.read.storageCount = storages.count
      } catch {
        let message = "storage enumeration failed: \(error)"
        result.read.error = result.read.error ?? message
        result.error = result.error ?? message
      }

      if let firstStorage = storages.first {
        do {
          result.read.rootObjectCount = try await sampleRootListing(
            device: device, storage: firstStorage.id)
          result.read.rootListingSucceeded = true
        } catch {
          let message = "root listing failed: \(error)"
          result.read.error = result.read.error ?? message
          result.error = result.error ?? message
        }

        if expectation != .blockerExpected {
          result.write = await runWriteSmoke(device: device, storage: firstStorage)
        } else {
          result.notes.append("Policy: blocker diagnostics only; write smoke skipped.")
        }
      } else {
        result.notes.append("No storage exposed by device.")
      }

      try? await device.devClose()
    } catch {
      result.error = "openDevice failed: \(error)"
    }

    finalizeOutcome(&result)
    return result
  }

  private static func sampleRootListing(device: any MTPDevice, storage: MTPStorageID) async throws
    -> Int
  {
    var count = 0
    let stream = device.list(parent: nil, in: storage)
    for try await batch in stream {
      count += batch.count
      if count >= 200 { break }
    }
    return count
  }

  private static func listObjects(
    device: any MTPDevice,
    parent: MTPObjectHandle?,
    storage: MTPStorageID,
    limit: Int
  ) async throws -> [MTPObjectInfo] {
    var items: [MTPObjectInfo] = []
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream {
      items.append(contentsOf: batch)
      if items.count >= limit { break }
    }
    return items
  }

  /// Finds an existing writable folder in root (Download, Downloads, Documents).
  /// Returns (handle, name) or nil if none found.
  private static func findWritableParent(device: any MTPDevice, storage: MTPStorageID) async -> (
    MTPObjectHandle, String
  )? {
    let preferredFolders = ["Download", "Downloads", "Documents"]
    let rootItems: [MTPObjectInfo]
    do {
      rootItems = try await listObjects(device: device, parent: nil, storage: storage, limit: 256)
    } catch {
      return nil
    }

    for folderName in preferredFolders {
      if let existing = rootItems.first(where: {
        $0.formatCode == 0x3001 && $0.name.lowercased() == folderName.lowercased()
      }) {
        return (existing.handle, existing.name)
      }
    }
    return nil
  }

  private static func runWriteSmoke(device: any MTPDevice, storage: MTPStorageInfo) async
    -> WriteSmoke
  {
    var smoke = WriteSmoke()
    smoke.attempted = true

    guard !storage.isReadOnly else {
      smoke.skipped = true
      smoke.reason = "storage is read-only"
      return smoke
    }

    // Find existing writable parent instead of creating folders
    if let (parentHandle, parentName) = await findWritableParent(
      device: device, storage: storage.id)
    {
      smoke.remoteFolder = parentName
      return await writeToParent(
        device: device, storage: storage, parentHandle: parentHandle, parentName: parentName)
    }

    // No existing folder found - skip write smoke instead of creating folders
    smoke.skipped = true
    smoke.reason =
      "no writable parent found (Download/Downloads/Documents not present); folder creation skipped"
    return smoke
  }

  private static func writeToParent(
    device: any MTPDevice, storage: MTPStorageInfo, parentHandle: MTPObjectHandle,
    parentName: String
  ) async -> WriteSmoke {
    var smoke = WriteSmoke()
    smoke.attempted = true
    smoke.remoteFolder = parentName

    let fm = FileManager.default
    let fileName = "swiftmtp-smoke-\(UUID().uuidString.prefix(8)).txt"
    let payloadSize = 16 * 1024
    smoke.bytesUploaded = payloadSize
    smoke.remoteFile = fileName

    let tempURL = fm.temporaryDirectory.appendingPathComponent(fileName)
    let payload = Data(repeating: 0x5A, count: payloadSize)
    do {
      try payload.write(to: tempURL, options: .atomic)
    } catch {
      smoke.error = "temp file creation failed: \(error)"
      return smoke
    }
    defer { try? fm.removeItem(at: tempURL) }

    do {
      _ = try await device.write(
        parent: parentHandle, name: fileName, size: UInt64(payloadSize), from: tempURL)
      smoke.succeeded = true
    } catch {
      smoke.error = "write to \(parentName) failed: \(error)"
      smoke.skipped = true
      smoke.reason = "SendObject rejected by device (\(error)); write smoke skipped"
      return smoke
    }

    // Verify and cleanup
    do {
      let children = try await listObjects(
        device: device, parent: parentHandle, storage: storage.id, limit: 128)
      if let uploaded = children.first(where: { $0.name == fileName }) {
        try? await device.delete(uploaded.handle, recursive: false)
      }
    } catch {
      smoke.warning = appendWarning(smoke.warning, "cleanup verification failed: \(error)")
    }

    return smoke
  }

  private static func finalizeOutcome(_ result: inout DeviceResult) {
    let readOK =
      result.read.openSucceeded
      && result.read.deviceInfoSucceeded
      && result.read.storagesSucceeded
      && result.read.rootListingSucceeded

    switch result.expectation {
    case .fullExercise:
      if readOK && result.write.succeeded {
        result.outcome = .passed
      } else if result.read.openSucceeded {
        result.outcome = .partial
      } else {
        result.outcome = .failed
      }
    case .probeNoCrash:
      if result.read.openSucceeded {
        result.outcome = .passed
      } else if result.error != nil {
        result.outcome = .partial
        result.notes.append("No fatal trap observed; interface probe remained non-crashing.")
      } else {
        result.outcome = .failed
      }
    case .readBestEffort:
      if readOK {
        result.outcome = .passed
      } else if result.read.openSucceeded {
        result.outcome = .partial
      } else {
        result.outcome = .failed
      }
    case .blockerExpected:
      if result.error != nil || !result.read.openSucceeded {
        result.outcome = .blocked
        result.notes.append("Expected blocker observed; diagnostics captured without crash.")
      } else {
        result.outcome = .partial
        result.notes.append("Device opened unexpectedly; blocker was not reproduced.")
      }
    case .generic:
      if readOK {
        result.outcome = .passed
      } else if result.read.openSucceeded {
        result.outcome = .partial
      } else {
        result.outcome = .failed
      }
    }
  }

  private static func resolveOutputDirectory(args: [String]) throws -> URL {
    var output: String?
    var index = 0
    while index < args.count {
      let arg = args[index]
      if arg == "--out" {
        guard index + 1 < args.count else {
          throw MTPError.preconditionFailed("missing value for --out")
        }
        output = args[index + 1]
        index += 2
        continue
      } else if arg.hasPrefix("--out=") {
        output = String(arg.dropFirst("--out=".count))
      } else {
        throw MTPError.preconditionFailed("unknown argument: \(arg)")
      }
      index += 1
    }

    if let output {
      return URL(fileURLWithPath: output, isDirectory: true)
    }

    let root = detectRepoRoot()
    return
      root
      .appendingPathComponent("Docs", isDirectory: true)
      .appendingPathComponent("benchmarks", isDirectory: true)
      .appendingPathComponent("connected-lab", isDirectory: true)
      .appendingPathComponent(pathTimestamp(), isDirectory: true)
  }

  private static func detectRepoRoot() -> URL {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)

    var candidates: [URL] = [
      cwd,
      cwd.deletingLastPathComponent(),
      cwd.deletingLastPathComponent().deletingLastPathComponent(),
    ]

    var sourcePath = URL(fileURLWithPath: #filePath)
    for _ in 0..<10 {
      sourcePath.deleteLastPathComponent()
      candidates.append(sourcePath)
    }

    for candidate in candidates {
      let packagePath = candidate.appendingPathComponent("SwiftMTPKit/Package.swift").path
      let docsPath = candidate.appendingPathComponent("Docs").path
      if fm.fileExists(atPath: packagePath), fm.fileExists(atPath: docsPath) {
        return candidate
      }
    }

    return cwd
  }

  private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  private static func printEncodedJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(value),
      let text = String(data: data, encoding: .utf8)
    {
      print(text)
    } else {
      print("{}")
    }
  }

  private static func writeMarkdown(report: ConnectedLabReport, to url: URL) throws {
    var lines: [String] = []
    lines.append("# Connected Device Lab Report")
    lines.append("")
    lines.append("- Generated: \(ISO8601DateFormatter().string(from: report.generatedAt))")
    lines.append("- Output: `\(report.outputPath)`")
    lines.append(
      "- Devices: \(report.summary.totalDevices) (passed: \(report.summary.passed), partial: \(report.summary.partial), blocked: \(report.summary.blocked), failed: \(report.summary.failed))"
    )
    if !report.summary.missingExpected.isEmpty {
      lines.append(
        "- Missing expected VID:PID: \(report.summary.missingExpected.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("| VID:PID | Device | Expected | Outcome | Read | Write | Notes |")
    lines.append("|---|---|---|---|---|---|---|")
    for device in report.devices {
      let readState =
        device.read.openSucceeded && device.read.deviceInfoSucceeded
          && device.read.storagesSucceeded && device.read.rootListingSucceeded ? "ok" : "partial"
      let writeState: String = {
        if !device.write.attempted { return "skipped" }
        return device.write.succeeded ? "ok" : "failed"
      }()
      let noteText =
        (device.notes + [device.error, device.write.warning, device.write.error].compactMap { $0 })
        .joined(separator: "; ")
      lines.append(
        "| \(device.vidpid) | \(device.manufacturer) \(device.model) | \(device.expectation.rawValue) | \(device.outcome.rawValue) | \(readState) | \(writeState) | \(noteText.isEmpty ? "-" : noteText) |"
      )
    }
    lines.append("")
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
  }

  private static func formatVIDPID(_ summary: MTPDeviceSummary) -> String {
    String(format: "%04x:%04x", summary.vendorID ?? 0, summary.productID ?? 0)
  }

  private static func findUSBDumpDevice(
    for summary: MTPDeviceSummary, in devices: [USBDumper.DumpDevice]
  ) -> USBDumper.DumpDevice? {
    let vid = String(format: "%04x", summary.vendorID ?? 0)
    let pid = String(format: "%04x", summary.productID ?? 0)
    let bus = Int(summary.bus ?? 0)
    let address = Int(summary.address ?? 0)

    return devices.first {
      $0.vendorID.caseInsensitiveCompare(vid) == .orderedSame
        && $0.productID.caseInsensitiveCompare(pid) == .orderedSame && $0.bus == bus
        && $0.address == address
    }
      ?? devices.first {
        $0.vendorID.caseInsensitiveCompare(vid) == .orderedSame
          && $0.productID.caseInsensitiveCompare(pid) == .orderedSame
      }
  }

  private static func deviceSortOrder(_ lhs: MTPDeviceSummary, _ rhs: MTPDeviceSummary) -> Bool {
    let left = formatVIDPID(lhs)
    let right = formatVIDPID(rhs)
    if left == right {
      if lhs.bus == rhs.bus {
        return (lhs.address ?? 0) < (rhs.address ?? 0)
      }
      return (lhs.bus ?? 0) < (rhs.bus ?? 0)
    }
    return left < right
  }

  private static func appendWarning(_ existing: String?, _ addition: String) -> String {
    guard let existing, !existing.isEmpty else { return addition }
    return "\(existing); \(addition)"
  }

  private static func pathTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private static func printUsage() {
    print("Usage: swift run swiftmtp device-lab connected [--out <path>] [--json]")
  }
}
