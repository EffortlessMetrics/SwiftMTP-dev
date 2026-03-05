// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import SwiftMTPCLI

@MainActor
struct ProbeCommand {

  /// Troubleshooting hints shown when no devices are found.
  static let noDeviceHints: [String] = [
    "Check the USB cable — try a different cable or port.",
    "On the device, enable MTP / File Transfer mode (not charging-only).",
    "Unlock the device screen and accept any 'Trust This Computer' or USB permission prompts.",
    "On macOS, check System Settings > Privacy & Security > Files and Folders for USB access.",
    "Quit other apps that may claim the device (Android File Transfer, adb, Samsung Smart Switch).",
    "Try disconnecting and reconnecting the device.",
    "Use --timeout <sec> to increase the detection window for slow devices.",
  ]

  /// Formats elapsed duration in human-readable form.
  static func formatDuration(_ interval: TimeInterval) -> String {
    if interval < 1.0 {
      return String(format: "%.0fms", interval * 1000)
    }
    return String(format: "%.2fs", interval)
  }

  static func runProbe(flags: CLIFlags) async {
    if flags.json {
      await runProbeJSON(flags: flags)
      return
    }
    let overallStart = Date()
    log("🔍 Probing for MTP devices (timeout: \(flags.probeTimeoutSeconds)s)...")
    do {
      // Phase 1: USB enumeration
      let enumStart = Date()
      let listings = try await LibUSBDiscovery.enumerateMTPDevices()
      let enumElapsed = Date().timeIntervalSince(enumStart)

      if flags.verbose {
        log("  ↳ USB enumeration: \(formatDuration(enumElapsed)) — found \(listings.count) candidate(s)")
      }

      var selectedVID: UInt16? = nil
      var selectedPID: UInt16? = nil
      var selectedSerial: String? = nil
      var selectedManufacturer: String? = nil
      if let first = listings.first {
        selectedVID = first.vendorID
        selectedPID = first.productID
        selectedSerial = first.usbSerial
        selectedManufacturer = first.manufacturer
      }

      // Phase 2: Device open
      let openStart = Date()
      let device = try await openDevice(flags: flags)
      let openElapsed = Date().timeIntervalSince(openStart)
      log("✅ Device found and opened!")

      if flags.verbose {
        log("  ↳ Device open: \(formatDuration(openElapsed))")
      }

      // Phase 3: MTP handshake
      let handshakeStart = Date()
      try await device.openIfNeeded()
      let info = try await device.getDeviceInfo()
      let storages = try await device.storages()
      let handshakeElapsed = Date().timeIntervalSince(handshakeStart)

      if flags.verbose {
        log("  ↳ MTP handshake: \(formatDuration(handshakeElapsed))")
      }

      // USB descriptor details
      if let vid = selectedVID, let pid = selectedPID {
        let vidpid = String(format: "0x%04x:0x%04x", vid, pid)
        print("USB ID:  \(vidpid)")
        if let mfr = selectedManufacturer, !mfr.isEmpty {
          print("USB Mfr: \(mfr)")
        }
        if let serial = selectedSerial, !serial.isEmpty {
          print("Serial:  \(serial)")
        }
        if let db = try? QuirkDatabase.load(),
          let q = db.entries.first(where: { $0.vid == vid && $0.pid == pid })
        {
          print("Quirk:   \(q.id) [\(q.status?.rawValue ?? "proposed")]")
          if let proplist = q.flags?.supportsGetObjectPropList {
            print("         GetObjectPropList: \(proplist ? "✅ fast-path" : "— fallback only")")
          }
        } else {
          let vidStr = String(format: "0x%04x", vid)
          let pidStr = String(format: "0x%04x", pid)
          print("Quirk:   ⚠️  not in database — connected via heuristic defaults")
          print(
            "         Contribute a profile: swiftmtp add-device --vid \(vidStr) --pid \(pidStr) --class android|ptp --name \"<brand model>\""
          )
          print("         See Docs/DeviceSubmission.md")
        }
      }
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

      // Timing summary
      let overallElapsed = Date().timeIntervalSince(overallStart)
      print("Probe completed in \(formatDuration(overallElapsed))")
    } catch {
      if isNoDeviceError(error) {
        printNoDeviceMessage(verbose: flags.verbose)
        exitNow(.unavailable)
      }
      displayError("Probe failed", error: error, flags: flags)
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
        "hint": actionableMessage(for: error),
        "capabilities": [:],
        "effective": [:],
      ]
      printJSON(errorOutput, type: "probeResult")
      if isNoDeviceError(error) {
        exitNow(.unavailable)
      }
      displayError("Probe failed", error: error, flags: flags)
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
        displayError("USB dump failed", error: error, flags: flags)
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

  // MARK: - Helpers

  /// Returns true if the error indicates no MTP device was found.
  static func isNoDeviceError(_ error: Error) -> Bool {
    if let mtpError = error as? MTPError {
      switch mtpError {
      case .notSupported:
        return true
      case .transport(let te):
        if case .noDevice = te { return true }
      default:
        break
      }
    }
    return false
  }

  /// Prints a user-friendly message when no devices are found.
  static func printNoDeviceMessage(verbose: Bool) {
    log("❌ No MTP device found.")
    log("")
    log("Troubleshooting:")
    for (i, hint) in noDeviceHints.enumerated() {
      log("  \(i + 1). \(hint)")
    }
    if verbose {
      log("")
      log("Run 'swiftmtp usb-dump' to see all connected USB devices.")
      log("Run 'swiftmtp diag' for a full diagnostic report.")
    }
  }
}
