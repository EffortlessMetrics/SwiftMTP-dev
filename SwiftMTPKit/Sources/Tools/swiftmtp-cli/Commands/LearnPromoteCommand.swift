// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPCLI

@MainActor
struct LearnPromoteCommand {
  struct Flags: Sendable {
    let fromPath: String?
    let toPath: String?
    let dryRun: Bool
    let apply: Bool
    let verbose: Bool
  }

  static func runCLI(args: [String]) async {
    // Parse learn-promote specific flags
    var learnPromoteFlags = Flags(
      fromPath: nil,
      toPath: nil,
      dryRun: false,
      apply: false,
      verbose: false
    )

    var i = 0
    while i < args.count {
      let arg = args[i]
      if arg == "--from" && i + 1 < args.count {
        learnPromoteFlags = Flags(
          fromPath: args[i + 1], toPath: learnPromoteFlags.toPath, dryRun: learnPromoteFlags.dryRun,
          apply: learnPromoteFlags.apply, verbose: learnPromoteFlags.verbose)
        i += 1
      } else if arg.hasPrefix("--from=") {
        learnPromoteFlags = Flags(
          fromPath: String(arg.dropFirst("--from=".count)), toPath: learnPromoteFlags.toPath,
          dryRun: learnPromoteFlags.dryRun, apply: learnPromoteFlags.apply,
          verbose: learnPromoteFlags.verbose)
      } else if arg == "--to" && i + 1 < args.count {
        learnPromoteFlags = Flags(
          fromPath: learnPromoteFlags.fromPath, toPath: args[i + 1],
          dryRun: learnPromoteFlags.dryRun, apply: learnPromoteFlags.apply,
          verbose: learnPromoteFlags.verbose)
        i += 1
      } else if arg.hasPrefix("--to=") {
        learnPromoteFlags = Flags(
          fromPath: learnPromoteFlags.fromPath, toPath: String(arg.dropFirst("--to=".count)),
          dryRun: learnPromoteFlags.dryRun, apply: learnPromoteFlags.apply,
          verbose: learnPromoteFlags.verbose)
      } else if arg == "--dry-run" {
        learnPromoteFlags = Flags(
          fromPath: learnPromoteFlags.fromPath, toPath: learnPromoteFlags.toPath, dryRun: true,
          apply: learnPromoteFlags.apply, verbose: learnPromoteFlags.verbose)
      } else if arg == "--apply" {
        learnPromoteFlags = Flags(
          fromPath: learnPromoteFlags.fromPath, toPath: learnPromoteFlags.toPath,
          dryRun: learnPromoteFlags.dryRun, apply: true, verbose: learnPromoteFlags.verbose)
      } else if arg == "--verbose" {
        learnPromoteFlags = Flags(
          fromPath: learnPromoteFlags.fromPath, toPath: learnPromoteFlags.toPath,
          dryRun: learnPromoteFlags.dryRun, apply: learnPromoteFlags.apply, verbose: true)
      }
      i += 1
    }

    do {
      let cmd = LearnPromoteCommand()
      try await cmd.run(flags: learnPromoteFlags)
    } catch {
      print("❌ Learn-promote failed: \(error)")
      exitNow(.tempfail)
    }
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

    // Validate submission bundle structure
    guard
      FileManager.default.fileExists(
        atPath: submissionURL.appendingPathComponent("submission.json").path)
    else {
      throw MTPError.preconditionFailed("Missing submission.json in bundle")
    }
    guard
      FileManager.default.fileExists(
        atPath: submissionURL.appendingPathComponent("probe.json").path)
    else {
      throw MTPError.preconditionFailed("Missing probe.json in bundle")
    }
    guard
      FileManager.default.fileExists(
        atPath: submissionURL.appendingPathComponent("quirk-suggestion.json").path)
    else {
      throw MTPError.preconditionFailed("Missing quirk-suggestion.json in bundle")
    }

    // Load submission manifest
    let manifestURL = submissionURL.appendingPathComponent("submission.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder()
      .decode(CollectCommand.SubmissionManifest.self, from: manifestData)

    // Validate manifest structure
    guard manifest.device.fingerprintHash.hasPrefix("sha256:") else {
      throw MTPError.preconditionFailed("Invalid fingerprint hash format")
    }
    guard manifest.consent.anonymizeSerial else {
      throw MTPError.preconditionFailed("Serial numbers must be anonymized for promotion")
    }

    // Load quirk suggestion
    let quirkURL = submissionURL.appendingPathComponent("quirk-suggestion.json")
    let quirkData = try Data(contentsOf: quirkURL)
    let quirkSuggestion = try JSONDecoder()
      .decode(CollectCommand.QuirkSuggestion.self, from: quirkData)

    // Validate quirk suggestion structure
    guard quirkSuggestion.match.vidPid.contains(":") else {
      throw MTPError.preconditionFailed("Invalid VID:PID format in quirk suggestion")
    }
    guard quirkSuggestion.status == "experimental" else {
      throw MTPError.preconditionFailed("Only experimental quirks can be promoted")
    }
    guard
      quirkSuggestion.confidence == "low" || quirkSuggestion.confidence == "medium"
        || quirkSuggestion.confidence == "high"
    else {
      throw MTPError.preconditionFailed("Invalid confidence level: \(quirkSuggestion.confidence)")
    }

    // Validate bench gates if present
    if let benchFiles = manifest.artifacts.bench, !benchFiles.isEmpty {
      guard quirkSuggestion.benchGates.readMBps > 0 && quirkSuggestion.benchGates.writeMBps > 0
      else {
        throw MTPError.preconditionFailed(
          "Bench gates must be positive values when benchmarks are present")
      }

      // Require bench gates satisfied for --apply (safety rail)
      if flags.apply {
        // Check if benchmark files exist and contain data
        for benchFile in benchFiles {
          let benchURL = submissionURL.appendingPathComponent(benchFile)
          if !FileManager.default.fileExists(atPath: benchURL.path) {
            throw MTPError.preconditionFailed("Benchmark file missing: \(benchFile)")
          }

          // Basic validation that file has data
          let benchData = try String(contentsOf: benchURL, encoding: .utf8)
          let lines = benchData.split(separator: "\n")
          if lines.count < 2 {  // Header + at least one data row
            throw MTPError.preconditionFailed("Benchmark file has no data: \(benchFile)")
          }
        }

        print("✅ Benchmark evidence validated for promotion")
      }
    } else if flags.apply {
      // No benchmarks present - require explicit override for safety
      let maintainerOverride = ProcessInfo.processInfo.environment["MAINTAINER_OVERRIDE"]
      if maintainerOverride != "true" {
        throw MTPError.preconditionFailed(
          "Cannot promote without benchmark evidence. Set MAINTAINER_OVERRIDE=true to override.")
      }
      print("⚠️  Promoting without benchmark evidence (MAINTAINER_OVERRIDE set)")
    }

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
      print(
        "   Bench gates: Read ≥\(quirkSuggestion.benchGates.readMBps) MB/s, Write ≥\(quirkSuggestion.benchGates.writeMBps) MB/s"
      )
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
          existingVidPid == vidPidKey
        {
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
      "status": "experimental",  // Start as experimental, can be promoted later
      "confidence": quirkSuggestion.confidence,
      "overrides": quirkSuggestion.overrides.reduce(into: [String: Any]()) { result, pair in
        result[pair.key] = pair.value.value
      },
      "hooks": quirkSuggestion.hooks.map { hook in
        var hookDict: [String: Any] = [
          "phase": hook.phase,
          "delayMs": hook.delayMs as Any,
        ]
        if let backoff = hook.busyBackoff {
          hookDict["busyBackoff"] = [
            "retries": backoff.retries,
            "baseMs": backoff.baseMs,
            "jitterPct": backoff.jitterPct,
          ]
        }
        return hookDict
      },
      "benchGates": [
        "readMBps": quirkSuggestion.benchGates.readMBps,
        "writeMBps": quirkSuggestion.benchGates.writeMBps,
      ],
      "provenance": [
        "submittedBy": quirkSuggestion.provenance.submittedBy as Any,
        "date": quirkSuggestion.provenance.date,
        "source": "learn-promote from \(fromPath)",
      ],
    ]

    // Update quirks database
    var updatedQuirks = currentQuirks
    if var existingQuirks = updatedQuirks["quirks"] as? [[String: Any]] {
      // Remove existing quirk for this VID:PID if present
      existingQuirks = existingQuirks.filter { quirk in
        if let match = quirk["match"] as? [String: Any],
          let vidPid = match["vidPid"] as? String
        {
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
    metadata["lastPromotion"] =
      [
        "date": currentDate,
        "from": fromPath,
        "device": "\(manifest.device.vendor) \(manifest.device.model)",
        "vidPid": vidPidKey,
      ] as [String: Any]
    updatedQuirks["metadata"] = metadata

    if flags.dryRun {
      print("\n🔍 Dry run - proposed changes:")
      print("Would add/update quirk for \(vidPidKey)")

      let jsonData = try JSONSerialization.data(
        withJSONObject: newQuirk, options: [.prettyPrinted, .sortedKeys])
      if let jsonString = String(data: jsonData, encoding: .utf8) {
        print("\nNew quirk entry:")
        print(jsonString)
      }

      let fullJsonData = try JSONSerialization.data(
        withJSONObject: updatedQuirks, options: [.prettyPrinted, .sortedKeys])
      if let fullJsonString = String(data: fullJsonData, encoding: .utf8) {
        print("\nFull updated database:")
        print(fullJsonString)
      }
    } else if flags.apply {
      print("\n💾 Applying changes to \(toPath)...")

      let jsonData = try JSONSerialization.data(
        withJSONObject: updatedQuirks, options: [.prettyPrinted, .sortedKeys])
      try jsonData.write(to: quirksURL)

      print("✅ Successfully promoted quirk for \(vidPidKey)")
      print("   Device: \(manifest.device.vendor) \(manifest.device.model)")
      print("   Status: experimental (can be promoted to stable after testing)")
      print("   File: \(toPath)")

      // Automatic DocC regeneration (safety rail)
      print("\n📚 Regenerating device documentation...")
      try await regenerateDeviceDocs()

      print("✅ Device documentation updated")
    } else {
      print("\n📋 Preview mode - use --apply to commit changes or --dry-run for full preview")

      let jsonData = try JSONSerialization.data(
        withJSONObject: newQuirk, options: [.prettyPrinted, .sortedKeys])
      if let jsonString = String(data: jsonData, encoding: .utf8) {
        print("\nProposed quirk entry:")
        print(jsonString)
      }
    }

    print("\n🎉 Learn-promote operation complete!")
  }

  private func regenerateDeviceDocs() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "bash", "-c",
      "cd SwiftMTPKit/Sources/Tools && chmod +x docc-generator && ./docc-generator ../../../Specs/quirks.json ../../../Docs/SwiftMTP.docc/Devices",
    ]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw MTPError.internalError(
        "DocC regeneration failed with exit code \(process.terminationStatus)")
    }

    // Verify no uncommitted changes
    let gitProcess = Process()
    gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    gitProcess.arguments = ["git", "diff", "--exit-code", "Docs/SwiftMTP.docc/Devices"]

    do {
      try gitProcess.run()
      gitProcess.waitUntilExit()
      if gitProcess.terminationStatus != 0 {
        throw MTPError.internalError(
          "DocC pages out of date after regeneration. Run docc-generator manually.")
      }
    } catch {
      // If git diff fails, the docs are likely out of date
      throw MTPError.internalError("Failed to verify DocC regeneration: \(error)")
    }
  }

  static func printHelp() {
    print("SwiftMTP Learn-Promote Tool")
    print("===========================")
    print("")
    print(
      "Promotes a learned device profile from a submission bundle into the main quirks database.")
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
    print(
      "  swift run swiftmtp learn-promote --from Contrib/submissions/bundle-123 --to custom-quirks.json --apply"
    )
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
