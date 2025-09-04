// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

struct LearnPromoteCommand {
    struct Flags {
        let fromPath: String?
        let toPath: String?
        let dryRun: Bool
        let apply: Bool
        let verbose: Bool
    }

    func run(flags: Flags) async throws {
        print("🧠 SwiftMTP Learn-Promote Tool")
        print("=============================")

        guard let fromPath = flags.fromPath else {
            throw MTPError.preconditionFailed("Must specify --from path to submission bundle")
        }

        let submissionURL = URL(fileURLWithPath: fromPath)

        // Validate submission bundle exists and is valid
        guard FileManager.default.fileExists(atPath: submissionURL.path) else {
            throw MTPError.preconditionFailed("Submission bundle not found: \(fromPath)")
        }

        // Load submission manifest
        let manifestURL = submissionURL.appendingPathComponent("submission.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(CollectCommand.SubmissionManifest.self, from: manifestData)

        // Load quirk suggestion
        let quirkURL = submissionURL.appendingPathComponent("quirk-suggestion.json")
        let quirkData = try Data(contentsOf: quirkURL)
        let quirkSuggestion = try JSONDecoder().decode(CollectCommand.QuirkSuggestion.self, from: quirkData)

        print("📦 Processing submission: \(manifest.device.vendor) \(manifest.device.model)")
        print("   VID:PID: \(manifest.device.vendorId):\(manifest.device.productId)")
        print("   Submitted: \(manifest.timestamp)")

        if flags.verbose {
            print("\n🔍 Quirk suggestion details:")
            print("   ID: \(quirkSuggestion.id)")
            print("   Status: \(quirkSuggestion.status)")
            print("   Confidence: \(quirkSuggestion.confidence)")
            print("   Overrides: \(quirkSuggestion.overrides.count) parameters")
            print("   Hooks: \(quirkSuggestion.hooks.count) configured")
            print("   Bench gates: Read ≥\(quirkSuggestion.benchGates.readMBps) MB/s, Write ≥\(quirkSuggestion.benchGates.writeMBps) MB/s")
        }

        // Load current quirks database
        let toPath = flags.toPath ?? "Specs/quirks.json"
        let quirksURL = URL(fileURLWithPath: toPath)

        var currentQuirks: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: quirksURL.path) {
            let quirksData = try Data(contentsOf: quirksURL)
            currentQuirks = try JSONSerialization.jsonObject(with: quirksData) as? [String: Any] ?? [:]
        }

        // Check if quirk already exists
        let vidPidKey = quirkSuggestion.match.vidPid
        if let existingQuirks = currentQuirks["quirks"] as? [[String: Any]] {
            for existingQuirk in existingQuirks {
                if let existingMatch = existingQuirk["match"] as? [String: Any],
                   let existingVidPid = existingMatch["vidPid"] as? String,
                   existingVidPid == vidPidKey {
                    print("⚠️  Warning: Quirk for \(vidPidKey) already exists in database")

                    if !flags.apply && !flags.dryRun {
                        print("   Use --apply to update existing quirk or --dry-run to preview")
                        return
                    }
                    break
                }
            }
        }

        // Generate new quirk entry
        let newQuirk: [String: Any] = [
            "schemaVersion": quirkSuggestion.schemaVersion,
            "id": quirkSuggestion.id,
            "match": [
                "vidPid": quirkSuggestion.match.vidPid
            ],
            "status": "experimental", // Start as experimental, can be promoted later
            "confidence": quirkSuggestion.confidence,
            "overrides": quirkSuggestion.overrides.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = pair.value.value
            },
            "hooks": quirkSuggestion.hooks.map { hook in
                var hookDict: [String: Any] = [
                    "phase": hook.phase,
                    "delayMs": hook.delayMs as Any
                ]
                if let backoff = hook.busyBackoff {
                    hookDict["busyBackoff"] = [
                        "retries": backoff.retries,
                        "baseMs": backoff.baseMs,
                        "jitterPct": backoff.jitterPct
                    ]
                }
                return hookDict
            },
            "benchGates": [
                "readMBps": quirkSuggestion.benchGates.readMBps,
                "writeMBps": quirkSuggestion.benchGates.writeMBps
            ],
            "provenance": [
                "submittedBy": quirkSuggestion.provenance.submittedBy as Any,
                "date": quirkSuggestion.provenance.date,
                "source": "learn-promote from \(fromPath)"
            ]
        ]

        // Update quirks database
        var updatedQuirks = currentQuirks
        if var existingQuirks = updatedQuirks["quirks"] as? [[String: Any]] {
            // Remove existing quirk for this VID:PID if present
            existingQuirks = existingQuirks.filter { quirk in
                if let match = quirk["match"] as? [String: Any],
                   let vidPid = match["vidPid"] as? String {
                    return vidPid != vidPidKey
                }
                return true
            }
            existingQuirks.append(newQuirk)
            updatedQuirks["quirks"] = existingQuirks
        } else {
            updatedQuirks["quirks"] = [newQuirk]
        }

        // Update metadata
        var metadata = updatedQuirks["metadata"] as? [String: Any] ?? [:]
        let currentDate = ISO8601DateFormatter().string(from: Date())
        metadata["lastUpdated"] = currentDate
        metadata["lastPromotion"] = [
            "date": currentDate,
            "from": fromPath,
            "device": "\(manifest.device.vendor) \(manifest.device.model)",
            "vidPid": vidPidKey
        ] as [String: Any]
        updatedQuirks["metadata"] = metadata

        if flags.dryRun {
            print("\n🔍 Dry run - proposed changes:")
            print("Would add/update quirk for \(vidPidKey)")

            let jsonData = try JSONSerialization.data(withJSONObject: newQuirk, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("\nNew quirk entry:")
                print(jsonString)
            }

            let fullJsonData = try JSONSerialization.data(withJSONObject: updatedQuirks, options: [.prettyPrinted, .sortedKeys])
            if let fullJsonString = String(data: fullJsonData, encoding: .utf8) {
                print("\nFull updated database:")
                print(fullJsonString)
            }
        } else if flags.apply {
            print("\n💾 Applying changes to \(toPath)...")

            let jsonData = try JSONSerialization.data(withJSONObject: updatedQuirks, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: quirksURL)

            print("✅ Successfully promoted quirk for \(vidPidKey)")
            print("   Device: \(manifest.device.vendor) \(manifest.device.model)")
            print("   Status: experimental (can be promoted to stable after testing)")
            print("   File: \(toPath)")
        } else {
            print("\n📋 Preview mode - use --apply to commit changes or --dry-run for full preview")

            let jsonData = try JSONSerialization.data(withJSONObject: newQuirk, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("\nProposed quirk entry:")
                print(jsonString)
            }
        }

        print("\n🎉 Learn-promote operation complete!")
    }

    static func printHelp() {
        print("SwiftMTP Learn-Promote Tool")
        print("===========================")
        print("")
        print("Promotes a learned device profile from a submission bundle into the main quirks database.")
        print("")
        print("Usage:")
        print("  swift run swiftmtp learn-promote [flags]")
        print("")
        print("Flags:")
        print("  --from <path>      - Path to submission bundle directory (required)")
        print("  --to <path>        - Path to quirks database (default: Specs/quirks.json)")
        print("  --dry-run          - Show what would be changed without modifying files")
        print("  --apply            - Apply the changes to the database")
        print("  --verbose          - Show detailed information")
        print("")
        print("Examples:")
        print("  swift run swiftmtp learn-promote --from Contrib/submissions/bundle-123 --dry-run")
        print("  swift run swiftmtp learn-promote --from Contrib/submissions/bundle-123 --apply")
        print("  swift run swiftmtp learn-promote --from Contrib/submissions/bundle-123 --to custom-quirks.json --apply")
        print("")
        print("Workflow:")
        print("1. Validate the submission bundle with validate-submission.sh")
        print("2. Review the quirk suggestion manually")
        print("3. Use --dry-run to preview the promotion")
        print("4. Use --apply to commit the changes")
        print("5. Test the new quirk with real devices")
        print("6. Promote status from 'experimental' to 'stable' after validation")
    }
}
