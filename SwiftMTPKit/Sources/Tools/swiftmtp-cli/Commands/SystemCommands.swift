// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

@MainActor
struct SystemCommands {
  static func runQuirks(flags: CLIFlags, args: [String]) async {
    guard let subcommand = args.first else {
      print("❌ Usage: quirks --explain")
      exitNow(.usage)
    }
    if subcommand == "--explain" { await runQuirksExplain(flags: flags) }
  }

  static func runQuirksExplain(flags: CLIFlags) async {
    let defaults = SwiftMTPQuirks.EffectiveTuning.defaults()
    var effective = defaults
    var capabilities: [String: Bool] = [:]

    do {
      let device = try await openDevice(flags: flags)
      try await device.openIfNeeded()
      effective = await device.effectiveTuning
      capabilities = await device.probedCapabilities
    } catch {
      // Fallback to defaults if device cannot be opened
    }

    if flags.json {
      let mockExplain: [String: Any] = [
        "mode": flags.safe ? "safe" : (flags.strict ? "strict" : "normal"),
        "layers": [
          ["source": "defaults", "description": "Built-in conservative defaults"],
          ["source": "quirks.json", "description": "Static device-specific fixes"],
        ],
        "effective": [
          "maxChunkBytes": effective.maxChunkBytes,
          "ioTimeoutMs": effective.ioTimeoutMs,
          "handshakeTimeoutMs": effective.handshakeTimeoutMs,
          "inactivityTimeoutMs": effective.inactivityTimeoutMs,
          "overallDeadlineMs": effective.overallDeadlineMs,
          "stabilizeMs": effective.stabilizeMs,
        ],
        "appliedQuirks": [],
        "capabilities": capabilities,
        "hooks": effective.hooks.map { $0.phase.rawValue },
      ]
      printJSON(mockExplain, type: "quirksExplain")
      return
    }

    print("🔧 Device Configuration Explain")
    print("==============================")
    print("Mode: \(flags.safe ? "safe" : (flags.strict ? "strict" : "normal"))")

    print("\nLayers:")
    print(
      "  1. defaults           -> chunk=\(formatBytes(UInt64(defaults.maxChunkBytes))), timeout=\(defaults.ioTimeoutMs)ms"
    )

    do {
      let db = try QuirkDatabase.load()
      print("  2. quirks.json        -> loaded \(db.entries.count) entries")
    } catch {
      print("  2. quirks.json        -> FAILED TO LOAD")
    }

    print("\nEffective Configuration:")
    print("  Transfer:")
    print("    Chunk Size: \(formatBytes(UInt64(effective.maxChunkBytes)))")
    print("    I/O Timeout: \(effective.ioTimeoutMs)ms")
    print("    Handshake Timeout: \(effective.handshakeTimeoutMs)ms")
    print("    Stabilize Delay: \(effective.stabilizeMs)ms")
    print("")
  }

  static func runHealth() async {
    print("🏥 SwiftMTP Health Check")
    do {
      let devices = try await LibUSBDiscovery.enumerateMTPDevices()
      print("✅ Found \(devices.count) MTP device(s)")
    } catch {
      print("❌ Health check failed: \(error)")
      exitNow(.unavailable)
    }
  }

  static func runVersion(flags: CLIFlags, args: [String]) async {
    let versionData = [
      "version": BuildInfo.version,
      "git": BuildInfo.git,
      "builtAt": BuildInfo.builtAt,
      "schemaVersion": BuildInfo.schemaVersion,
    ]

    if flags.json {
      printJSON(versionData, type: "version")
    } else {
      print("SwiftMTP \(BuildInfo.version) (\(BuildInfo.git))")
    }
  }
}
