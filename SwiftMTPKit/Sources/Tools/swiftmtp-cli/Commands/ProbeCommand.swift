// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI

@MainActor
struct ProbeCommand {
  static func runProbe(flags: CLIFlags) async {
    if flags.json {
      await runProbeJSON(flags: flags)
      return
    }
    log("🔍 Probing for MTP devices...")
    do {
      let device = try await openDevice(flags: flags)
      log("✅ Device found and opened!")

      try await device.openIfNeeded()
      let info = try await device.getDeviceInfo()
      let storages = try await device.storages()

      print("Device: \(info.manufacturer) \(info.model)")
      print("Operations: \(info.operationsSupported.count)")
      print("Events: \(info.eventsSupported.count)")
      print("Storage devices: \(storages.count)")

      for storage in storages {
        let usedBytes = storage.capacityBytes - storage.freeBytes
        let usedPercent = Double(usedBytes) / Double(storage.capacityBytes) * 100
        print(
          "  - \(storage.description): \(formatBytes(storage.capacityBytes)) total, \(formatBytes(storage.freeBytes)) free (\(String(format: "%.1f", usedPercent))% used)"
        )
      }
    } catch {
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .notSupported:
          log("❌ No MTP-capable device found.")
          exitNow(.unavailable)
        case .transport(let te):
          if case .noDevice = te {
            log("❌ No MTP device connected. Check USB connection and MTP mode.")
            exitNow(.unavailable)
          }
        default:
          break
        }
      }
      log("❌ Probe failed: \(error)")
      exitNow(.tempfail)
    }
  }

  static func runProbeJSON(flags: CLIFlags) async {
    do {
      let device = try await openDevice(flags: flags)
      try await device.openIfNeeded()

      // Prefer structured ProbeReceipt if available
      if let receipt = await device.probeReceipt {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt)
        print(String(data: data, encoding: .utf8) ?? "{}")
        return
      }

      // Fallback to ad-hoc output
      let info = try await device.info
      let storages = try await device.storages()
      let capabilities = await device.probedCapabilities
      let tuning = await device.effectiveTuning

      let output: [String: Any] = [
        "manufacturer": info.manufacturer,
        "model": info.model,
        "operations": info.operationsSupported.map { String(format: "0x%04X", $0) },
        "storages": storages.map { ["id": $0.id.raw, "description": $0.description] },
        "capabilities": capabilities,
        "effective": [
          "maxChunkBytes": tuning.maxChunkBytes,
          "ioTimeoutMs": tuning.ioTimeoutMs,
          "handshakeTimeoutMs": tuning.handshakeTimeoutMs,
          "inactivityTimeoutMs": tuning.inactivityTimeoutMs,
          "overallDeadlineMs": tuning.overallDeadlineMs,
          "stabilizeMs": tuning.stabilizeMs,
        ],
      ]
      printJSON(output, type: "probeResult")
    } catch {
      let errorOutput: [String: Any] = [
        "error": error.localizedDescription,
        "capabilities": [:],
        "effective": [:],
      ]
      printJSON(errorOutput, type: "probeResult")
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .notSupported:
          log("❌ No MTP-capable device found.")
          exitNow(.unavailable)
        case .transport(let te):
          if case .noDevice = te {
            log("❌ No MTP device connected. Check USB connection and MTP mode.")
            exitNow(.unavailable)
          }
        default:
          break
        }
      }
      log("❌ Probe failed: \(error)")
      exitNow(.tempfail)
    }
  }

  static func runUSBDump(flags: CLIFlags) async {
    do {
      if flags.json {
        let report = try USBDumper().collect()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8) ?? "{}")
      } else {
        print("🔍 Dumping USB device interfaces...")
        try await USBDumper().run()
        print("✅ USB dump complete")
      }
    } catch {
      if !flags.json {
        print("❌ USB dump failed: \(error)")
      }
      exitNow(.tempfail)
    }
  }

  static func runDiag(flags: CLIFlags) async {
    print("== Probe ==")
    await runProbe(flags: flags)
    print("\n== USB Dump ==")
    await runUSBDump(flags: flags)
    print("\n✅ Diagnostic complete")
  }
}
