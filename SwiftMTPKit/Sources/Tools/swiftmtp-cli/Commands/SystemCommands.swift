// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import SwiftMTPCLI

@MainActor
struct SystemCommands {
  static func runQuirks(flags: CLIFlags, args: [String]) async {
    guard let subcommand = args.first else {
      print("❌ Missing quirks subcommand.")
      print("   Usage: swiftmtp quirks <subcommand>")
      print("")
      print("   Subcommands:")
      print("     --explain                        Show how device config is computed")
      print("     matrix                           Display full device compatibility matrix")
      print("     lookup --vid 0xXXXX --pid 0xXXXX Look up a specific device")
      print("     stats                            Show governance summary statistics")
      print("")
      print("   Example: swiftmtp quirks lookup --vid 0x18d1 --pid 0x4ee1")
      exitNow(.usage)
    }
    if subcommand == "--explain" {
      await runQuirksExplain(flags: flags)
    } else if subcommand == "matrix" {
      await runQuirksMatrix(flags: flags)
    } else if subcommand == "lookup" {
      await runQuirksLookup(flags: flags, args: Array(args.dropFirst()))
    } else if subcommand == "stats" {
      await runQuirksStats(flags: flags)
    } else {
      print("❌ Unknown quirks subcommand: '\(subcommand)'")
      print("   Available: --explain, matrix, lookup, stats")
      print("   Example: swiftmtp quirks lookup --vid 0x18d1 --pid 0x4ee1")
      exitNow(.usage)
    }
  }

  static func runQuirksLookup(flags: CLIFlags, args: [String]) async {
    // Parse --vid and --pid from args
    var vidStr: String? = nil
    var pidStr: String? = nil
    var i = 0
    while i < args.count {
      switch args[i] {
      case "--vid":
        if i + 1 < args.count {
          vidStr = args[i + 1]
          i += 1
        }
      case "--pid":
        if i + 1 < args.count {
          pidStr = args[i + 1]
          i += 1
        }
      default: break
      }
      i += 1
    }
    guard let vidRaw = vidStr, let pidRaw = pidStr else {
      print("❌ Missing --vid and/or --pid arguments.")
      print("   Usage: swiftmtp quirks lookup --vid 0xXXXX --pid 0xXXXX")
      print("   Example: swiftmtp quirks lookup --vid 0x18d1 --pid 0x4ee1")
      print("   Tip: Run 'system_profiler SPUSBDataType' to find your device's VID/PID.")
      exitNow(.usage)
    }
    // Normalize to lowercase 0xXXXX format and parse to UInt16
    let vidHex =
      vidRaw.lowercased().hasPrefix("0x") ? String(vidRaw.dropFirst(2)) : vidRaw.lowercased()
    let pidHex =
      pidRaw.lowercased().hasPrefix("0x") ? String(pidRaw.dropFirst(2)) : pidRaw.lowercased()
    guard let vidVal = UInt16(vidHex, radix: 16), let pidVal = UInt16(pidHex, radix: 16) else {
      print("❌ Invalid VID/PID format: '\(vidRaw)'/'\(pidRaw)'")
      print("   Use hex values like 0x18d1 or 18d1 (with or without 0x prefix).")
      exitNow(.usage)
    }
    let vidFormatted = String(format: "0x%04x", vidVal)
    let pidFormatted = String(format: "0x%04x", pidVal)

    do {
      let db = try QuirkDatabase.load()
      let match = db.entries.first { $0.vid == vidVal && $0.pid == pidVal }
      if let q = match {
        if flags.json {
          printJSON(
            [
              "found": true,
              "id": q.id,
              "vid": vidFormatted,
              "pid": pidFormatted,
              "status": q.status?.rawValue ?? "proposed",
              "supportsGetObjectPropList": q.resolvedFlags().supportsGetObjectPropList,
              "requiresKernelDetach": q.resolvedFlags().requiresKernelDetach,
            ], type: "quirksLookup")
        } else {
          let rf = q.resolvedFlags()
          print("✅ Device found in quirk database")
          print("   ID:               \(q.id)")
          print("   VID:PID:          \(vidFormatted):\(pidFormatted)")
          print("   Status:           \(q.status?.rawValue ?? "proposed")")
          print(
            "   GetObjectPropList:\(rf.supportsGetObjectPropList ? " ✅ fast-path" : " — fallback only")"
          )
          print("   Kernel detach:    \(rf.requiresKernelDetach ? "yes (Android)" : "no")")
          if let cls = q.ifaceClass {
            let label =
              cls == 0x06
              ? "PTP (0x06)" : cls == 0xff ? "Android/vendor (0xff)" : String(format: "0x%02x", cls)
            print("   Interface class:  \(label)")
          }
          if let ioMs = q.ioTimeoutMs {
            print("   I/O timeout:      \(ioMs) ms")
          }
        }
      } else {
        if flags.json {
          printJSON(
            [
              "found": false,
              "vid": vidFormatted,
              "pid": pidFormatted,
              "message": "Device not in quirk database. It may still work via PTP class heuristic.",
              "submitURL": "Docs/DeviceSubmission.md",
            ], type: "quirksLookup")
        } else {
          print(
            "⚠️  Device \(vidFormatted):\(pidFormatted) not found in quirk database (\(db.entries.count) entries)"
          )
          print("   PTP cameras (class 0x06) will work via automatic heuristic.")
          print("   Android devices may need a quirk entry for best results.")
          print("   To contribute: see Docs/DeviceSubmission.md or run `swiftmtp add-device`")
        }
      }
    } catch {
      print("❌ Failed to load quirks database: \(error)")
      print("   Ensure quirks.json is present in SwiftMTPQuirks/Resources/.")
      exitNow(.unavailable)
    }
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

  static func runQuirksMatrix(flags: CLIFlags) async {
    do {
      let db = try QuirkDatabase.load()
      let tested = db.testedDevices()
      let research = db.researchEntries()
      if flags.json {
        let rows = db.entries.map { e -> [String: Any] in
          var row: [String: Any] = [
            "id": e.id,
            "vidpid": String(format: "0x%04x:0x%04x", e.vid, e.pid),
            "status": e.status?.rawValue ?? "proposed",
            "confidence": e.confidence ?? "unknown",
            "governanceLevel": QuirkGovernanceLevel.classify(e).rawValue,
          ]
          if let d = e.lastVerifiedDate { row["lastVerifiedDate"] = d }
          if let by = e.lastVerifiedBy { row["lastVerifiedBy"] = by }
          if let ev = e.evidenceRequired { row["evidenceRequired"] = ev }
          return row
        }
        printJSON(["matrix": rows, "tested": tested.count, "research": research.count], type: "quirksMatrix")
        return
      }
      print("\(db.entries.count) quirk entries (\(tested.count) tested, \(research.count) research-based)")
      print("")
      print("| Device | VID:PID | Status | Governance | Last Verified | Confidence |")
      print("| --- | --- | --- | --- | --- | --- |")
      for e in db.entries {
        let vidpid = String(format: "0x%04x:0x%04x", e.vid, e.pid)
        let status = e.status?.rawValue ?? "proposed"
        let govLevel = QuirkGovernanceLevel.classify(e)
        let govTag: String
        switch govLevel {
        case .promoted:   govTag = "✅ tested"
        case .research:   govTag = "🔬 research"
        case .community:  govTag = "👥 community"
        case .deprecated: govTag = "⚠️  deprecated"
        }
        let date = e.lastVerifiedDate ?? "—"
        let confidence = e.confidence ?? "—"
        print("| \(e.id) | \(vidpid) | \(status) | \(govTag) | \(date) | \(confidence) |")
      }
    } catch {
      print("❌ Failed to load quirks database: \(error)")
      print("   Ensure quirks.json is present in SwiftMTPQuirks/Resources/.")
      exitNow(.unavailable)
    }
  }

  static func runQuirksStats(flags: CLIFlags) async {
    do {
      let db = try QuirkDatabase.load()
      let summary = db.governanceSummary()
      let validation = db.validateGovernance()
      let tested = db.testedDevices()
      let stats = db.coverageStats()

      if flags.json {
        var info: [String: Any] = [
          "totalEntries": stats.totalEntries,
          "uniqueVIDs": stats.uniqueVIDs,
          "governance": Dictionary(uniqueKeysWithValues: summary.map { ($0.key.rawValue, $0.value) }),
          "governanceValid": validation.isValid,
          "status": stats.statusCounts,
          "flagUsage": stats.flagUsage,
          "categories": stats.categoryCounts,
          "validation": [
            "withEvidence": stats.withEvidence,
            "withoutEvidence": stats.withoutEvidence,
          ],
          "testing": [
            "tested": stats.testedCount,
            "untested": stats.untestedCount,
          ],
          "confidence": stats.confidenceCounts,
          "topVIDs": stats.topVIDs.map { ["vid": $0.formatted, "count": $0.count] },
          "unusedFlags": stats.unusedFlags,
        ]
        if !validation.isValid {
          info["violations"] = validation.violations
        }
        info["testedDeviceIds"] = tested.map(\.id)
        printJSON(info, type: "quirksStats")
        return
      }

      print("📊 Quirks Governance Summary")
      print("============================")
      print("   Total entries:  \(stats.totalEntries)")
      print("   Unique VIDs:    \(stats.uniqueVIDs)")
      print("")
      print("   By governance level:")
      for level in QuirkGovernanceLevel.allCases {
        let count = summary[level] ?? 0
        let icon: String
        switch level {
        case .promoted:   icon = "✅"
        case .research:   icon = "🔬"
        case .community:  icon = "👥"
        case .deprecated: icon = "⚠️ "
        }
        let label = level.rawValue + String(repeating: " ", count: max(0, 12 - level.rawValue.count))
        print("     \(icon) \(label) \(count)")
      }

      // Status breakdown
      print("")
      print("   By status:")
      for (status, count) in stats.statusCounts.sorted(by: { $0.key < $1.key }) {
        let padded = status + String(repeating: " ", count: max(0, 14 - status.count))
        print("     \(padded) \(count)")
      }

      // Flag usage (top 10)
      let topFlags = stats.flagUsage.sorted { $0.value > $1.value }.prefix(10)
      if !topFlags.isEmpty {
        print("")
        print("   Top flag usage (non-default):")
        for (name, count) in topFlags {
          let padded = name + String(repeating: " ", count: max(0, 38 - name.count))
          print("     \(padded) \(count)")
        }
      }

      // Unused flags
      if !stats.unusedFlags.isEmpty {
        print("")
        print("   Unused flags (\(stats.unusedFlags.count)):")
        for name in stats.unusedFlags.prefix(flags.verbose ? stats.unusedFlags.count : 5) {
          print("     ⚪ \(name)")
        }
        if !flags.verbose && stats.unusedFlags.count > 5 {
          print("     ... and \(stats.unusedFlags.count - 5) more (use --verbose)")
        }
      }

      // Validation status
      print("")
      print("   Validation:")
      print("     With evidence:    \(stats.withEvidence)")
      print("     Without evidence: \(stats.withoutEvidence)")

      // Testing status
      print("")
      print("   Device testing:")
      print("     Tested:   \(stats.testedCount)")
      print("     Untested: \(stats.untestedCount)")

      // Confidence breakdown
      print("")
      print("   By confidence:")
      for (conf, count) in stats.confidenceCounts.sorted(by: { $0.key < $1.key }) {
        let padded = conf + String(repeating: " ", count: max(0, 14 - conf.count))
        print("     \(padded) \(count)")
      }

      // Top categories
      let topCats = stats.topCategories(10)
      if !topCats.isEmpty {
        print("")
        print("   Top categories:")
        for (cat, count) in topCats {
          let padded = cat + String(repeating: " ", count: max(0, 20 - cat.count))
          print("     \(padded) \(count)")
        }
      }

      // Top VIDs
      if !stats.topVIDs.isEmpty {
        print("")
        print("   Top VIDs:")
        for entry in stats.topVIDs.prefix(10) {
          let padded = entry.formatted + String(repeating: " ", count: max(0, 10 - entry.formatted.count))
          print("     \(padded) \(entry.count) entries")
        }
      }

      if flags.verbose {
        // Full category breakdown
        let allCats = stats.categoryCounts.sorted { $0.value > $1.value }
        if allCats.count > 10 {
          print("")
          print("   All categories (\(allCats.count)):")
          for (cat, count) in allCats {
            let padded = cat + String(repeating: " ", count: max(0, 20 - cat.count))
            print("     \(padded) \(count)")
          }
        }
      }

      if !tested.isEmpty {
        print("")
        print("   Tested devices:")
        for entry in tested {
          let vidpid = String(format: "0x%04x:0x%04x", entry.vid, entry.pid)
          print("     ✅ \(entry.id) (\(vidpid))")
        }
      }

      if !validation.isValid {
        print("")
        print("   ⚠️  Governance violations:")
        for v in validation.violations {
          print("     - \(v)")
        }
      } else {
        print("")
        print("   ✅ All governance invariants satisfied")
      }
    } catch {
      print("❌ Failed to load quirks database: \(error)")
      exitNow(.unavailable)
    }
  }

  static func runHealth() async {
    print("🏥 SwiftMTP Health Check")
    do {
      let devices = try await LibUSBDiscovery.enumerateMTPDevices()
      if devices.isEmpty {
        print("⚠️  No MTP devices found. Connect a device via USB and enable MTP/File Transfer mode.")
      } else {
        print("✅ Found \(devices.count) MTP device(s)")
      }
    } catch {
      print("❌ Health check failed: \(actionableMessage(for: error))")
      print("   Tip: Check that no other app (Android File Transfer, adb) is holding the USB device.")
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

  static func runInfo(flags: CLIFlags) async {
    do {
      let qdb = try QuirkDatabase.load()
      let entries = qdb.entries
      let vids = Set(entries.map { String(format: "0x%04x", $0.vid) })
      let byStatus = Dictionary(grouping: entries) { $0.status?.rawValue ?? "unknown" }
      let proplistCount = entries.filter { $0.resolvedFlags().supportsGetObjectPropList }.count
      let kernelDetachCount = entries.filter { $0.resolvedFlags().requiresKernelDetach }.count
      let tested = qdb.testedDevices().count
      let research = qdb.researchEntries().count

      if flags.json {
        let info: [String: Any] = [
          "totalEntries": entries.count,
          "uniqueVIDs": vids.count,
          "byStatus": byStatus.mapValues { $0.count },
          "supportsGetObjectPropList": proplistCount,
          "requiresKernelDetach": kernelDetachCount,
          "testedDevices": tested,
          "researchEntries": research,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]),
          let str = String(data: data, encoding: .utf8)
        {
          print(str)
        }
      } else {
        print("📦 SwiftMTP Device Database")
        print("")
        print("   Entries:          \(entries.count) (\(tested) tested, \(research) research-based)")
        print("   Unique VIDs:      \(vids.count)")
        print("   Proplist-capable: \(proplistCount)")
        print("   Kernel-detach:    \(kernelDetachCount)")
        print("")
        print("   By status:")
        for (status, items) in byStatus.sorted(by: { $0.key < $1.key }) {
          let padded = status + String(repeating: " ", count: max(0, 14 - status.count))
          print("     \(padded) \(items.count)")
        }
        print("")
        print("   Run 'swiftmtp quirks' for the full list.")
      }
    } catch {
      print("❌ Could not load quirks database: \(error)")
      exitNow(.unavailable)
    }
  }
}
