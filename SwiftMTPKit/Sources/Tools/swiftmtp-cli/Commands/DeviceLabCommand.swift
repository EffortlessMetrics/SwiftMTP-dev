// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@_spi(Dev) import SwiftMTPCore
import SwiftMTPTransportLibUSB

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

  private enum FailureClass: String, Codable, Sendable {
    case enumeration = "class1-enumeration"
    case claim = "class2-claim"
    case handshake = "class3-handshake"
    case transfer = "class4-transfer"
    case storageGated = "storage_gated"
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

  private struct ReadSmoke: Codable, Sendable {
    var attempted = false
    var succeeded = false
    var skipped = false
    var reason: String?
    var objectHandle: MTPObjectHandle?
    var objectName: String?
    var objectSizeBytes: UInt64?
    var bytesDownloaded = 0
    var error: String?
  }

  private struct WriteSmoke: Codable, Sendable {
    var attempted = false
    var succeeded = false
    var skipped = false
    var reason: String?
    var strategyRung: String?
    var bytesUploaded = 0
    var remoteFolder: String?
    var remoteFile: String?
    var storageID: String?
    var parentHandle: MTPObjectHandle?
    var objectFormatCode: String?
    var declaredObjectSizeBytes: UInt64?
    var writeStrategy: String?
    var attemptedTargets: [String] = []
    var uploadedHandle: MTPObjectHandle?
    var deleteAttempted = false
    var deleteSucceeded = false
    var deleteError: String?
    var warning: String?
    var error: String?
  }

  private struct OperationReceipt: Codable, Sendable {
    let operation: String
    let attempted: Bool
    let succeeded: Bool
    let durationMs: Int?
    let details: String?
    let error: String?
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
    var failureClass: FailureClass?
    var read: ReadValidation
    var readSmoke: ReadSmoke
    var write: WriteSmoke
    var operations: [OperationReceipt]
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
    "2a70:f003": .fullExercise,
    "04e8:6860": .readBestEffort,
    "18d1:4ee1": .readBestEffort,
  ]
  private static let connectedLabSchemaVersion = "1.2.0"
  private static let openDeviceTimeoutMs = 45_000
  private static let operationTimeoutMs = 30_000
  private static let capabilityReportTimeoutMs = 10_000
  private static let readSmokeTimeoutMs = 30_000
  private static let writeSmokeTimeoutMs = 45_000
  private static let perDeviceWatchdogTimeoutMs = 240_000

  private enum DeviceLabTimeoutError: LocalizedError {
    case exceeded(stage: String, ms: Int)

    var errorDescription: String? {
      switch self {
      case .exceeded(let stage, let ms):
        return "operation '\(stage)' exceeded deadline (\(ms) ms)"
      }
    }
  }

  private actor DeadlineResolutionGate {
    private var resolved = false

    func claim() -> Bool {
      if resolved { return false }
      resolved = true
      return true
    }
  }

  static func run(flags: CLIFlags, args: [String]) async {
    guard let mode = args.first, mode == "connected" else {
      printUsage()
      exitNow(.usage)
    }

    do {
      let repoRoot = detectRepoRoot()
      let outputDir = try resolveOutputDirectory(args: Array(args.dropFirst()))
      let portableOutputPath = makePortablePath(outputDir, relativeTo: repoRoot)
      try FileManager.default.createDirectory(
        at: outputDir, withIntermediateDirectories: true, attributes: nil)

      let usbDump = try USBDumper().collect()
      let usbDumpURL = outputDir.appendingPathComponent("usb-dump.json")
      try writeJSON(usbDump, to: usbDumpURL)

      let requestedFilter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      let requestedHasExplicitFilter =
        requestedFilter.vid != nil || requestedFilter.pid != nil || requestedFilter.bus != nil
        || requestedFilter.address != nil

      let discovered: [MTPDeviceSummary]
      do {
        discovered = try await within(ms: operationTimeoutMs, stage: "connected-discovery") {
          try await LibUSBDiscovery.enumerateMTPDevices()
        }
      } catch {
        let summary = ReportSummary(
          totalDevices: 0,
          passed: 0,
          partial: 0,
          blocked: 0,
          failed: 0,
          missingExpected: requestedHasExplicitFilter ? [] : Array(expectedPolicies.keys).sorted()
        )
        let report = ConnectedLabReport(
          schemaVersion: connectedLabSchemaVersion,
          generatedAt: Date(),
          outputPath: portableOutputPath,
          connectedDeviceCount: 0,
          summary: summary,
          devices: []
        )
        let reportJSONURL = outputDir.appendingPathComponent("connected-lab.json")
        try? writeJSON(report, to: reportJSONURL)
        let reportMDURL = outputDir.appendingPathComponent("connected-lab.md")
        try? writeMarkdown(report: report, to: reportMDURL)
        if flags.json {
          printEncodedJSON(report)
        } else {
          print("Connected discovery failed: \(error)")
          print("Output: \(portableOutputPath)")
        }
        exitNow(.tempfail)
      }

      let filterResult = applyConnectedFilter(discovered: discovered, flags: flags)
      let filter = filterResult.filter
      let hasExplicitFilter = filterResult.hasExplicitFilter
      let connected = filterResult.devices
      if connected.isEmpty {
        let message: String
        if hasExplicitFilter {
          message = "No connected MTP devices matched the filter."
        } else {
          message = "No connected MTP devices found."
        }
        if flags.json {
          let emptySummary = ReportSummary(
            totalDevices: 0, passed: 0, partial: 0, blocked: 0, failed: 0,
            missingExpected: hasExplicitFilter ? [] : Array(expectedPolicies.keys).sorted())
          let emptyReport = ConnectedLabReport(
            schemaVersion: connectedLabSchemaVersion,
            generatedAt: Date(),
            outputPath: portableOutputPath,
            connectedDeviceCount: 0,
            summary: emptySummary,
            devices: []
          )
          printEncodedJSON(emptyReport)
        } else {
          print(message)
          if hasExplicitFilter {
            print("Filter: \(describeFilter(filter))")
          }
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
        let expectation = expectedPolicies[vidpid] ?? .generic
        let result: DeviceResult
        do {
          result = try await within(
            ms: perDeviceWatchdogTimeoutMs, stage: "per-device-\(vidpid)-watchdog"
          ) {
            await runPerDevice(
              summary: summary,
              expectation: expectation,
              flags: flags,
              usbDumpDevice: usbDevice,
              deviceDir: deviceDir
            )
          }
        } catch {
          result = makeTimedOutResult(
            summary: summary,
            expectation: expectation,
            usbDumpDevice: usbDevice,
            deviceDir: deviceDir,
            error: error
          )
        }

        // Persist per-device artifacts.
        let reportURL = deviceDir.appendingPathComponent("device-report.json")
        var resultMutable = result
        resultMutable.artifacts.reportJSON = reportURL.lastPathComponent
        try writeJSON(resultMutable, to: reportURL)

        if let receipt = resultMutable.probeReceipt {
          let receiptURL = deviceDir.appendingPathComponent("probe-receipt.json")
          resultMutable.artifacts.probeReceiptJSON = receiptURL.lastPathComponent
          try writeJSON(receipt, to: receiptURL)
          try writeJSON(resultMutable, to: reportURL)
        }

        if let capabilityReport = resultMutable.capabilityReport {
          let harnessURL = deviceDir.appendingPathComponent("harness-report.json")
          resultMutable.artifacts.harnessReportJSON = harnessURL.lastPathComponent
          try writeJSON(capabilityReport, to: harnessURL)
          try writeJSON(resultMutable, to: reportURL)
        }

        if let usbDevice {
          let usbURL = deviceDir.appendingPathComponent("usb-interface.json")
          resultMutable.artifacts.usbInterfaceJSON = usbURL.lastPathComponent
          try writeJSON(usbDevice, to: usbURL)
          try writeJSON(resultMutable, to: reportURL)
        }

        results.append(resultMutable)
      }

      let discoveredVIDPIDs = Set(results.map(\.vidpid))
      let missingExpected: [String]
      if hasExplicitFilter {
        missingExpected = []
      } else {
        missingExpected = expectedPolicies.keys.sorted()
          .filter { !discoveredVIDPIDs.contains($0) }
      }

      let summary = ReportSummary(
        totalDevices: results.count,
        passed: results.filter { $0.outcome == .passed }.count,
        partial: results.filter { $0.outcome == .partial }.count,
        blocked: results.filter { $0.outcome == .blocked }.count,
        failed: results.filter { $0.outcome == .failed }.count,
        missingExpected: missingExpected
      )

      let report = ConnectedLabReport(
        schemaVersion: connectedLabSchemaVersion,
        generatedAt: Date(),
        outputPath: portableOutputPath,
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
        print("Output: \(portableOutputPath)")
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
    let stageTraceURL = deviceDir.appendingPathComponent("stage-trace.log")
    let iso8601 = ISO8601DateFormatter()

    func trace(_ message: String) {
      let line = "[\(iso8601.string(from: Date()))] \(message)\n"
      let data = Data(line.utf8)
      if !FileManager.default.fileExists(atPath: stageTraceURL.path) {
        _ = FileManager.default.createFile(atPath: stageTraceURL.path, contents: data)
        return
      }
      guard let handle = try? FileHandle(forWritingTo: stageTraceURL) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    }

    var result = DeviceResult(
      id: summary.id.raw,
      vidpid: vidpid,
      bus: Int(summary.bus ?? 0),
      address: Int(summary.address ?? 0),
      manufacturer: summary.manufacturer,
      model: summary.model,
      expectation: expectation,
      outcome: .failed,
      failureClass: nil,
      read: ReadValidation(),
      readSmoke: ReadSmoke(),
      write: WriteSmoke(),
      operations: [],
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
      trace("open-device:start")
      let device = try await within(ms: openDeviceTimeoutMs, stage: "open-device") {
        try await openDevice(flags: perDeviceFlags)
      }
      trace("open-device:ok")

      func appendOperation(
        _ operation: String,
        attempted: Bool = true,
        succeeded: Bool,
        durationMs: Int? = nil,
        details: String? = nil,
        error: String? = nil
      ) {
        result.operations.append(
          OperationReceipt(
            operation: operation,
            attempted: attempted,
            succeeded: succeeded,
            durationMs: durationMs,
            details: details,
            error: error
          ))
      }

      do {
        trace("enumerate-and-claim-interface:start")
        let startedAt = DispatchTime.now()
        try await within(ms: operationTimeoutMs, stage: "enumerate-and-claim-interface") {
          try await device.openIfNeeded()
        }
        trace("enumerate-and-claim-interface:ok")
        result.read.openSucceeded = true
        appendOperation(
          "enumerate-and-claim-interface", succeeded: true, durationMs: elapsedMs(since: startedAt))
      } catch {
        trace("enumerate-and-claim-interface:fail error=\(error)")
        let message = "open failed: \(error)"
        result.read.error = message
        result.error = message
        appendOperation(
          "enumerate-and-claim-interface",
          succeeded: false,
          error: message
        )
        trace("close-after-open-failure:start")
        _ = try? await within(ms: 10_000, stage: "close-after-open-failure") {
          try await device.devClose()
          return ()
        }
        trace("close-after-open-failure:done")
        finalizeOutcome(&result)
        classifyFailure(&result)
        return result
      }

      do {
        trace("probe-receipt:start")
        result.probeReceipt = try await within(ms: operationTimeoutMs, stage: "probe-receipt") {
          await device.probeReceipt
        }
        trace("probe-receipt:ok")
      } catch {
        trace("probe-receipt:fail error=\(error)")
        result.notes.append("Probe receipt unavailable: \(error)")
      }
      do {
        trace("capability-harness:start")
        result.capabilityReport = try await within(ms: capabilityReportTimeoutMs, stage: "capability-harness") {
          try await DeviceLabHarness().collect(device: device)
        }
        trace("capability-harness:ok")
      } catch {
        trace("capability-harness:fail error=\(error)")
        result.notes.append("Capability harness unavailable: \(error)")
      }

      do {
        trace("open-session-and-get-device-info:start")
        let startedAt = DispatchTime.now()
        _ = try await within(ms: operationTimeoutMs, stage: "open-session-and-get-device-info") {
          try await device.info
        }
        trace("open-session-and-get-device-info:ok")
        result.read.deviceInfoSucceeded = true
        appendOperation(
          "open-session-and-get-device-info",
          succeeded: true,
          durationMs: elapsedMs(since: startedAt)
        )
      } catch {
        trace("open-session-and-get-device-info:fail error=\(error)")
        let message = "device info failed: \(error)"
        result.read.error = result.read.error ?? message
        result.error = result.error ?? message
        appendOperation(
          "open-session-and-get-device-info",
          succeeded: false,
          error: message
        )
      }

      var storages: [MTPStorageInfo] = []
      do {
        trace("storage-discovery:start")
        let startedAt = DispatchTime.now()
        storages = try await within(ms: operationTimeoutMs, stage: "storage-discovery") {
          try await device.storages()
        }
        trace("storage-discovery:ok count=\(storages.count)")
        result.read.storagesSucceeded = true
        result.read.storageCount = storages.count
        appendOperation(
          "storage-discovery",
          succeeded: true,
          durationMs: elapsedMs(since: startedAt),
          details: "storages=\(storages.count)"
        )
      } catch {
        trace("storage-discovery:fail error=\(error)")
        let message = "storage enumeration failed: \(error)"
        result.read.error = result.read.error ?? message
        result.error = result.error ?? message
        appendOperation(
          "storage-discovery",
          succeeded: false,
          error: message
        )
      }

      if let firstStorage = storages.first {
        do {
          trace("object-enumeration:start")
          let startedAt = DispatchTime.now()
          result.read.rootObjectCount = try await within(ms: operationTimeoutMs, stage: "object-enumeration") {
            try await sampleRootListing(device: device, storage: firstStorage.id)
          }
          trace("object-enumeration:ok count=\(result.read.rootObjectCount ?? 0)")
          result.read.rootListingSucceeded = true
          appendOperation(
            "object-enumeration",
            succeeded: true,
            durationMs: elapsedMs(since: startedAt),
            details: "rootObjects=\(result.read.rootObjectCount ?? 0)"
          )
        } catch {
          trace("object-enumeration:fail error=\(error)")
          let message = "root listing failed: \(error)"
          result.read.error = result.read.error ?? message
          result.error = result.error ?? message
          appendOperation(
            "object-enumeration",
            succeeded: false,
            error: message
          )
        }

        do {
          trace("read-download:start")
          let readSmokeStartedAt = DispatchTime.now()
          result.readSmoke = try await within(ms: readSmokeTimeoutMs, stage: "read-download") {
            await runReadSmoke(device: device, storage: firstStorage)
          }
          trace("read-download:ok attempted=\(result.readSmoke.attempted) succeeded=\(result.readSmoke.succeeded)")
          appendOperation(
            "read-download",
            attempted: result.readSmoke.attempted,
            succeeded: result.readSmoke.succeeded,
            durationMs: elapsedMs(since: readSmokeStartedAt),
            details: result.readSmoke.reason
              ?? result.readSmoke.objectName.map { "object=\($0)" },
            error: result.readSmoke.error
          )
        } catch {
          trace("read-download:fail error=\(error)")
          var timedReadSmoke = ReadSmoke()
          timedReadSmoke.attempted = true
          timedReadSmoke.reason = "read smoke stage did not complete"
          timedReadSmoke.error = "read smoke failed: \(error)"
          result.readSmoke = timedReadSmoke
          appendOperation(
            "read-download",
            attempted: true,
            succeeded: false,
            details: timedReadSmoke.reason,
            error: timedReadSmoke.error
          )
        }

        if expectation != .blockerExpected {
          do {
            trace("write-upload:start")
            let writeSmokeStartedAt = DispatchTime.now()
            result.write = try await within(ms: writeSmokeTimeoutMs, stage: "write-upload") {
              await runWriteSmoke(device: device, storage: firstStorage)
            }
            trace("write-upload:ok attempted=\(result.write.attempted) succeeded=\(result.write.succeeded)")
            appendOperation(
              "write-upload",
              attempted: result.write.attempted,
              succeeded: result.write.succeeded,
              durationMs: elapsedMs(since: writeSmokeStartedAt),
              details: result.write.reason
                ?? result.write.remoteFolder.map { "folder=\($0)" },
              error: result.write.error
            )
            appendOperation(
              "delete-uploaded-object",
              attempted: result.write.deleteAttempted,
              succeeded: result.write.deleteSucceeded,
              details: result.write.deleteAttempted ? result.write.remoteFile : "not-attempted",
              error: result.write.deleteError
            )
          } catch {
            trace("write-upload:fail error=\(error)")
            var timedWriteSmoke = WriteSmoke()
            timedWriteSmoke.attempted = true
            timedWriteSmoke.reason = "write smoke stage did not complete"
            timedWriteSmoke.strategyRung = "timed-timeout"
            timedWriteSmoke.error = "write smoke failed: \(error)"
            result.write = timedWriteSmoke
            appendOperation(
              "write-upload",
              attempted: result.write.attempted,
              succeeded: false,
              details: result.write.reason,
              error: result.write.error
            )
            appendOperation(
              "delete-uploaded-object",
              attempted: false,
              succeeded: false,
              details: "skipped because write stage did not complete"
            )
          }
        } else {
          result.notes.append("Policy: blocker diagnostics only; write smoke skipped.")
          appendOperation(
            "write-upload",
            attempted: false,
            succeeded: false,
            details: "skipped due to blocker-expected policy"
          )
          appendOperation(
            "delete-uploaded-object",
            attempted: false,
            succeeded: false,
            details: "skipped because write stage did not run"
          )
        }
      } else {
        result.notes.append(
          "Device returned zero storages. On Android this often means the phone is locked or file access is not yet approved."
        )
        result.notes.append(
          "Unlock the phone, accept the USB file-access prompt, then unplug/replug and rerun."
        )
        appendOperation(
          "object-enumeration",
          attempted: false,
          succeeded: false,
          details: "no storage exposed"
        )
        appendOperation(
          "read-download",
          attempted: false,
          succeeded: false,
          details: "no storage exposed"
        )
        appendOperation(
          "write-upload",
          attempted: false,
          succeeded: false,
          details: "no storage exposed"
        )
        appendOperation(
          "delete-uploaded-object",
          attempted: false,
          succeeded: false,
          details: "no uploaded object"
        )
      }

      trace("device-close:start")
      _ = try? await within(ms: 10_000, stage: "device-close") {
        try await device.devClose()
        return ()
      }
      trace("device-close:done")
    } catch {
      trace("open-device:fail error=\(error)")
      result.error = "openDevice failed: \(error)"
      result.operations.append(
        OperationReceipt(
          operation: "open-device",
          attempted: true,
          succeeded: false,
          durationMs: nil,
          details: nil,
          error: result.error
        ))
    }

    finalizeOutcome(&result)
    classifyFailure(&result)
    return result
  }

  private static func makeTimedOutResult(
    summary: MTPDeviceSummary,
    expectation: ExpectedPolicy,
    usbDumpDevice: USBDumper.DumpDevice?,
    deviceDir: URL,
    error: Error
  ) -> DeviceResult {
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
      failureClass: nil,
      read: ReadValidation(),
      readSmoke: ReadSmoke(),
      write: WriteSmoke(),
      operations: [],
      notes: ["Per-device watchdog timeout emitted a partial report."],
      error: "device-lab watchdog timeout: \(error)",
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
    result.operations.append(
      OperationReceipt(
        operation: "per-device-watchdog",
        attempted: true,
        succeeded: false,
        durationMs: nil,
        details: nil,
        error: result.error
      )
    )
    finalizeOutcome(&result)
    classifyFailure(&result)
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

  private static func runReadSmoke(device: any MTPDevice, storage: MTPStorageInfo) async
    -> ReadSmoke
  {
    var smoke = ReadSmoke()
    smoke.attempted = true

    let rootItems: [MTPObjectInfo]
    do {
      rootItems = try await listObjects(device: device, parent: nil, storage: storage.id, limit: 256)
    } catch {
      smoke.skipped = true
      smoke.reason = "root listing unavailable for read smoke"
      smoke.error = "list failed: \(error)"
      return smoke
    }

    guard
      let candidate = rootItems.first(where: {
        // Pick a bounded regular file to keep read smoke deterministic.
        $0.formatCode != 0x3001 && ($0.sizeBytes ?? 0) > 0 && ($0.sizeBytes ?? 0) <= 8 * 1024 * 1024
      })
    else {
      smoke.skipped = true
      smoke.reason = "no root file <= 8 MiB available for read smoke"
      return smoke
    }

    smoke.objectHandle = candidate.handle
    smoke.objectName = candidate.name
    smoke.objectSizeBytes = candidate.sizeBytes

    let fm = FileManager.default
    let tempURL = fm.temporaryDirectory.appendingPathComponent(
      "swiftmtp-read-smoke-\(UUID().uuidString.prefix(8)).bin")
    defer { try? fm.removeItem(at: tempURL) }

    do {
      _ = try await device.read(handle: candidate.handle, range: nil, to: tempURL)
      if let attrs = try? fm.attributesOfItem(atPath: tempURL.path),
        let downloaded = attrs[.size] as? NSNumber
      {
        smoke.bytesDownloaded = downloaded.intValue
      } else {
        smoke.bytesDownloaded = Int(candidate.sizeBytes ?? 0)
      }
      smoke.succeeded = true
      return smoke
    } catch {
      smoke.error = "read failed (\(candidate.name)): \(error)"
      return smoke
    }
  }

  /// Finds writable parent folders in preference order.
  private static func findWritableParents(
    device: any MTPDevice,
    storage: MTPStorageID
  ) async -> [(MTPObjectHandle, String)] {
    let preferredFolders = ["Download", "Downloads", "DCIM", "Camera", "Pictures", "Documents"]
    let rootItems: [MTPObjectInfo]
    do {
      rootItems = try await listObjects(device: device, parent: nil, storage: storage, limit: 512)
    } catch {
      return []
    }

    var ordered: [(MTPObjectHandle, String)] = []
    var seen = Set<MTPObjectHandle>()

    for folderName in preferredFolders {
      if let existing = rootItems.first(where: {
        $0.formatCode == 0x3001 && $0.name.lowercased() == folderName.lowercased()
      }) {
        if seen.insert(existing.handle).inserted {
          ordered.append((existing.handle, existing.name))
        }
      }
    }

    // Keep remaining folders as low-priority fallbacks.
    for folder in rootItems where folder.formatCode == 0x3001 {
      if seen.insert(folder.handle).inserted {
        ordered.append((folder.handle, folder.name))
      }
    }

    return ordered
  }

  private static func ensureSwiftMTPFolder(
    device: any MTPDevice,
    storage: MTPStorageID
  ) async throws -> MTPObjectHandle {
    let rootItems = try await listObjects(device: device, parent: nil, storage: storage, limit: 512)
    if let existing = rootItems.first(where: {
      $0.formatCode == 0x3001 && $0.name.lowercased() == "swiftmtp"
    }) {
      return existing.handle
    }
    return try await device.createFolder(parent: nil, name: "SwiftMTP", storage: storage)
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

    let writableParents = await findWritableParents(device: device, storage: storage.id)
    var attempts: [String] = []
    var lastFailure: WriteSmoke?
    // Keep target climb bounded so one device cannot stall an entire bring-up cycle.
    let maxRetryableTargetAttempts = 6

    for (parentHandle, parentName) in writableParents {
      attempts.append(parentName)
      var attempt = await writeToParent(
        device: device, storage: storage, parentHandle: parentHandle, parentName: parentName)
      attempt.attemptedTargets = attempts
      if attempt.succeeded {
        return attempt
      }
      lastFailure = attempt
      // Keep climbing the ladder for known retryable write failures.
      if looksLikeRetryableWriteFailure(attempt.error) {
        if attempts.count >= maxRetryableTargetAttempts {
          attempt.reason = appendWarning(
            attempt.reason,
            "retryable target attempt budget exhausted (\(maxRetryableTargetAttempts)); proceeding to SwiftMTP fallback rung")
          lastFailure = attempt
          break
        }
        continue
      }
      return attempt
    }

    // Last rung: create/use SwiftMTP folder in root and retry once.
    do {
      let swiftMTPHandle = try await ensureSwiftMTPFolder(device: device, storage: storage.id)
      attempts.append("SwiftMTP")
      var attempt = await writeToParent(
        device: device, storage: storage, parentHandle: swiftMTPHandle, parentName: "SwiftMTP")
      attempt.attemptedTargets = attempts
      if attempt.succeeded {
        return attempt
      }
      lastFailure = attempt
    } catch {
      smoke.attemptedTargets = attempts + ["SwiftMTP"]
      smoke.error = "failed to create/access SwiftMTP folder: \(error)"
      smoke.skipped = true
      smoke.reason = "no writable target accepted upload"
      return smoke
    }

    if var failure = lastFailure {
      failure.attemptedTargets = attempts
      failure.skipped = true
      if failure.reason == nil {
        failure.reason = "all writable parent targets rejected upload"
      }
      return failure
    }

    smoke.attemptedTargets = attempts
    smoke.skipped = true
    smoke.reason = "no writable parent folders discovered in root"
    return smoke
  }

  private static func writeToParent(
    device: any MTPDevice, storage: MTPStorageInfo, parentHandle: MTPObjectHandle,
    parentName: String
  ) async -> WriteSmoke {
    var smoke = WriteSmoke()
    smoke.attempted = true
    smoke.remoteFolder = parentName
    smoke.storageID = String(format: "0x%08x", storage.id.raw)
    smoke.parentHandle = parentHandle

    let fm = FileManager.default
    let fileName = "swiftmtp-smoke-\(UUID().uuidString.prefix(8)).txt"
    let payloadSize = 16 * 1024
    smoke.bytesUploaded = payloadSize
    smoke.remoteFile = fileName
    smoke.declaredObjectSizeBytes = UInt64(payloadSize)
    smoke.objectFormatCode = String(format: "0x%04x", inferredFormatCode(for: fileName))
    smoke.writeStrategy = await device.devicePolicy?.fallbacks.write.rawValue
    smoke.strategyRung = "primary-target"

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
      let writeError = "write to \(parentName) failed: \(error)"
      smoke.error = writeError

      // Timeout-class write errors may still result in an uploaded object.
      if looksLikeTimeoutFailure(writeError) {
        if let uploaded = try? await findUploadedObject(
          device: device,
          storage: storage.id,
          parent: parentHandle,
          name: fileName
        ) {
          smoke.succeeded = true
          smoke.uploadedHandle = uploaded.handle
          smoke.strategyRung = "timeout-verify-existing"
          smoke.warning = appendWarning(
            smoke.warning, "write returned timeout but object exists on device")
          smoke.warning = appendWarning(smoke.warning, "original write error: \(writeError)")
          smoke.error = nil
        }
      }

      if !smoke.succeeded {
        smoke.skipped = true
        smoke.strategyRung = "target-ladder"
        smoke.reason = "SendObject rejected by device (\(error)); attempting fallback target"
        return smoke
      }
    }

    // Verify and cleanup
    if smoke.uploadedHandle == nil {
      do {
        if let uploaded = try await findUploadedObject(
          device: device, storage: storage.id, parent: parentHandle, name: fileName)
        {
          smoke.uploadedHandle = uploaded.handle
        } else {
          smoke.warning = appendWarning(
            smoke.warning, "uploaded file not visible for delete verification")
        }
      } catch {
        smoke.warning = appendWarning(smoke.warning, "cleanup verification failed: \(error)")
      }
    }

    if let uploadedHandle = smoke.uploadedHandle {
      smoke.deleteAttempted = true
      do {
        try await device.delete(uploadedHandle, recursive: false)
        smoke.deleteSucceeded = true
      } catch {
        smoke.deleteError = "delete failed: \(error)"
      }
    }

    return smoke
  }

  private static func findUploadedObject(
    device: any MTPDevice,
    storage: MTPStorageID,
    parent: MTPObjectHandle,
    name: String
  ) async throws -> MTPObjectInfo? {
    let maxScanObjects = 4096
    var scanned = 0
    let stream = device.list(parent: parent, in: storage)
    for try await batch in stream {
      if let uploaded = batch.first(where: { $0.name == name }) {
        return uploaded
      }
      scanned += batch.count
      if scanned >= maxScanObjects { break }
    }
    return nil
  }

  static func looksLikeTimeoutFailure(_ message: String?) -> Bool {
    guard let lowered = message?.lowercased() else { return false }
    return lowered.contains("timeout") || lowered.contains("timed out")
  }

  static func looksLikeRetryableWriteFailure(_ message: String?) -> Bool {
    guard let lowered = message?.lowercased() else { return false }
    return lowered.contains("0x201d")
      || lowered.contains("0x2008")
      || lowered.contains("invalidparameter")
      || lowered.contains("invalidstorageid")
      || lowered.contains("parameternotsupported")
      || lowered.contains("timeout")
      || lowered.contains("timed out")
      || lowered.contains("busy")
      || lowered.contains("temporar")
      || lowered.contains("io(")
      || lowered.contains("transport(")
  }

  private static func inferredFormatCode(for filename: String) -> UInt16 {
    let lower = filename.lowercased()
    if lower.hasSuffix(".txt") { return 0x3004 }  // Text
    if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return 0x3801 }
    if lower.hasSuffix(".png") { return 0x380B }
    return 0x3000  // Undefined non-association
  }

  private static func finalizeOutcome(_ result: inout DeviceResult) {
    let readOK =
      result.read.openSucceeded
      && result.read.deviceInfoSucceeded
      && result.read.storagesSucceeded
      && result.read.rootListingSucceeded
    let readSmokeOK = result.readSmoke.succeeded || result.readSmoke.skipped
    let writeUploadOK = result.write.succeeded || result.write.skipped
    let deleteOK = !result.write.deleteAttempted || result.write.deleteSucceeded

    switch result.expectation {
    case .fullExercise:
      if readOK && result.readSmoke.succeeded && result.write.succeeded && deleteOK {
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
      if readOK && readSmokeOK {
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
      if readOK && readSmokeOK && writeUploadOK {
        result.outcome = .passed
      } else if result.read.openSucceeded {
        result.outcome = .partial
      } else {
        result.outcome = .failed
      }
    }
  }

  private static func classifyFailure(_ result: inout DeviceResult) {
    guard result.outcome != .passed else {
      result.failureClass = nil
      return
    }

    let combinedErrors =
      [
        result.error,
        result.read.error,
        result.readSmoke.error,
        result.write.error,
        result.write.deleteError,
      ]
      .compactMap { $0 } + result.operations.compactMap(\.error)
    let combined = combinedErrors.joined(separator: " ").lowercased()
    let hasTransferErrors =
      result.readSmoke.error != nil || result.write.error != nil || result.write.deleteError != nil

    result.failureClass = classifyFailureClass(
      openSucceeded: result.read.openSucceeded,
      deviceInfoSucceeded: result.read.deviceInfoSucceeded,
      storagesSucceeded: result.read.storagesSucceeded,
      storageCount: result.read.storageCount,
      rootListingSucceeded: result.read.rootListingSucceeded,
      hasTransferErrors: hasTransferErrors,
      combinedErrorText: combined
    )
  }

  private static func classifyFailureClass(
    openSucceeded: Bool,
    deviceInfoSucceeded: Bool,
    storagesSucceeded: Bool,
    storageCount: Int,
    rootListingSucceeded: Bool,
    hasTransferErrors: Bool,
    combinedErrorText: String
  ) -> FailureClass? {
    if !openSucceeded {
      if combinedErrorText.contains("no mtp") || combinedErrorText.contains("no device")
        || combinedErrorText.contains("no interface") || combinedErrorText.contains("no candidate")
      {
        return .enumeration
      }
      if combinedErrorText.contains("access denied") || combinedErrorText.contains("busy")
        || combinedErrorText.contains("claim restrictions")
        || combinedErrorText.contains("claim failed")
      {
        return .claim
      }
      return .handshake
    }

    if deviceInfoSucceeded && storagesSucceeded && storageCount == 0 {
      return .storageGated
    }

    if !deviceInfoSucceeded || !storagesSucceeded || !rootListingSucceeded {
      return .handshake
    }

    if hasTransferErrors {
      return .transfer
    }

    return nil
  }

  static func classifyFailureClassForState(
    openSucceeded: Bool,
    deviceInfoSucceeded: Bool,
    storagesSucceeded: Bool,
    storageCount: Int,
    rootListingSucceeded: Bool,
    hasTransferErrors: Bool,
    combinedErrorText: String
  ) -> String? {
    classifyFailureClass(
      openSucceeded: openSucceeded,
      deviceInfoSucceeded: deviceInfoSucceeded,
      storagesSucceeded: storagesSucceeded,
      storageCount: storageCount,
      rootListingSucceeded: rootListingSucceeded,
      hasTransferErrors: hasTransferErrors,
      combinedErrorText: combinedErrorText.lowercased()
    )?.rawValue
  }

  private static func elapsedMs(since start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
  }

  /// Execute an operation with a wall-clock timeout and fail the stage deterministically.
  /// Uses detached racing tasks so timeout completion does not block on non-cooperative operations.
  private static func within<T: Sendable>(
    ms: Int,
    stage: String,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let gate = DeadlineResolutionGate()
    let timeoutMs = max(ms, 1)
    return try await withCheckedThrowingContinuation { continuation in
      Task.detached {
        do {
          let value = try await operation()
          if await gate.claim() {
            continuation.resume(returning: value)
          }
        } catch {
          if await gate.claim() {
            continuation.resume(throwing: error)
          }
        }
      }

      Task.detached {
        try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
        if await gate.claim() {
          continuation.resume(throwing: DeviceLabTimeoutError.exceeded(stage: stage, ms: timeoutMs))
        }
      }
    }
  }

  static func testWithinTimeoutProbe(timeoutMs: Int, sleepMs: Int) async -> String {
    do {
      _ = try await within(ms: timeoutMs, stage: "test-timeout-probe") {
        try await Task.sleep(nanoseconds: UInt64(max(sleepMs, 1)) * 1_000_000)
        return "completed"
      }
      return "completed"
    } catch {
      return String(describing: error)
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

  private static func makePortablePath(_ url: URL, relativeTo root: URL) -> String {
    let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
    let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = normalizedRoot.path
    let outputPath = normalizedURL.path
    if outputPath == rootPath { return "." }
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    if outputPath.hasPrefix(prefix) {
      return String(outputPath.dropFirst(prefix.count))
    }
    return normalizedURL.lastPathComponent
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
    lines.append(
      "| VID:PID | Device | Expected | Outcome | Failure Class | Read | Read Smoke | Write | Delete | Notes |"
    )
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for device in report.devices {
      let readState =
        device.read.openSucceeded && device.read.deviceInfoSucceeded
          && device.read.storagesSucceeded && device.read.rootListingSucceeded ? "ok" : "partial"
      let readSmokeState: String = {
        if !device.readSmoke.attempted { return "skipped" }
        if device.readSmoke.skipped { return "skipped" }
        return device.readSmoke.succeeded ? "ok" : "failed"
      }()
      let writeState: String = {
        if !device.write.attempted { return "skipped" }
        if device.write.skipped { return "skipped" }
        return device.write.succeeded ? "ok" : "failed"
      }()
      let deleteState: String = {
        if !device.write.deleteAttempted { return "skipped" }
        return device.write.deleteSucceeded ? "ok" : "failed"
      }()
      let noteText =
        (
          device.notes
            + [device.error, device.readSmoke.error, device.write.warning, device.write.error, device.write.deleteError]
              .compactMap { $0 }
        )
        .joined(separator: "; ")
      lines.append(
        "| \(device.vidpid) | \(device.manufacturer) \(device.model) | \(device.expectation.rawValue) | \(device.outcome.rawValue) | \(device.failureClass?.rawValue ?? "-") | \(readState) | \(readSmokeState) | \(writeState) | \(deleteState) | \(noteText.isEmpty ? "-" : noteText) |"
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

  private static func matchesFilter(_ summary: MTPDeviceSummary, filter: DeviceFilter) -> Bool {
    if let vid = filter.vid, summary.vendorID != vid { return false }
    if let pid = filter.pid, summary.productID != pid { return false }
    if let bus = filter.bus {
      guard let deviceBus = summary.bus, bus == Int(deviceBus) else { return false }
    }
    if let address = filter.address {
      guard let deviceAddress = summary.address, address == Int(deviceAddress) else { return false }
    }
    return true
  }

  static func applyConnectedFilter(discovered: [MTPDeviceSummary], flags: CLIFlags)
    -> (devices: [MTPDeviceSummary], filter: DeviceFilter, hasExplicitFilter: Bool)
  {
    let filter = DeviceFilter(
      vid: parseUSBIdentifier(flags.targetVID),
      pid: parseUSBIdentifier(flags.targetPID),
      bus: flags.targetBus,
      address: flags.targetAddress
    )
    let hasExplicitFilter =
      filter.vid != nil || filter.pid != nil || filter.bus != nil || filter.address != nil
    let devices = discovered.filter { matchesFilter($0, filter: filter) }
    return (devices, filter, hasExplicitFilter)
  }

  private static func describeFilter(_ filter: DeviceFilter) -> String {
    var parts: [String] = []
    if let vid = filter.vid { parts.append(String(format: "vid=%04x", vid)) }
    if let pid = filter.pid { parts.append(String(format: "pid=%04x", pid)) }
    if let bus = filter.bus { parts.append("bus=\(bus)") }
    if let address = filter.address { parts.append("address=\(address)") }
    return parts.isEmpty ? "(none)" : parts.joined(separator: ", ")
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
