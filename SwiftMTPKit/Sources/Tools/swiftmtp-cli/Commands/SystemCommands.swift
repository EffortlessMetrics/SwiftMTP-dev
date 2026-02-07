// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
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
        if flags.json {
            let mockExplain: [String: Any] = [
                "mode": flags.safe ? "safe" : (flags.strict ? "strict" : "normal"),
                "layers": [
                    ["source": "defaults", "description": "Built-in conservative defaults"],
                    ["source": "quirks.json", "description": "Static device-specific fixes"]
                ],
                "effective": [
                    "maxChunkBytes": 1048576,
                    "ioTimeoutMs": 10000,
                    "handshakeTimeoutMs": 6000
                ],
                "appliedQuirks": [],
                "capabilities": ["partialRead": true, "partialWrite": true],
                "hooks": []
            ]
            printJSON(mockExplain, type: "quirksExplain")
            return
        }

        print("🔧 Device Configuration Explain")
        print("==============================")
        print("Mode: \(flags.safe ? "safe" : (flags.strict ? "strict" : "normal"))")
        let defaults = EffectiveTuning.defaults()
        print("\nLayers:")
        print("  1. defaults           -> chunk=\(formatBytes(UInt64(defaults.maxChunkBytes))), timeout=\(defaults.ioTimeoutMs)ms")
        do {
            let db = try QuirkDatabase.load()
            print("  2. quirks.json        -> loaded \(db.entries.count) entries")
        } catch {
            print("  2. quirks.json        -> FAILED TO LOAD")
        }
        print("\nEffective Configuration:")
        print("  Transfer:")
        print("    Chunk Size: \(formatBytes(UInt64(defaults.maxChunkBytes)))")
        print("    I/O Timeout: \(defaults.ioTimeoutMs)ms")
        print("    Handshake Timeout: \(defaults.handshakeTimeoutMs)ms")
        print("")
    }

    static func runHealth() async {
        print("🏥 SwiftMTP Health Check")
        do {
            let devices = try await MTPDeviceManager.shared.currentRealDevices()
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
            "schemaVersion": BuildInfo.schemaVersion
        ]
        
        if flags.json {
            printJSON(versionData, type: "version")
        } else {
            print("SwiftMTP \(BuildInfo.version) (\(BuildInfo.git))")
        }
    }
}