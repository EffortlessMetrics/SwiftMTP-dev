// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPQuirks

// Script-style entry point for learning promotion
let args = CommandLine.arguments

if args.count < 3 {
  print("Usage: learn-promote <learned-profiles.json> <quirks.json> [fingerprint]")
  print("Analyzes learned profiles and suggests quirk updates")
  exit(1)
}

let learnedProfilesPath = args[1]
let quirksPath = args[2]
let targetFingerprint = args.count > 3 ? args[3] : nil

do {
  // Load learned profiles
  let learnedData = try Data(contentsOf: URL(fileURLWithPath: learnedProfilesPath))
  let profiles = try JSONDecoder().decode([String: LearnedProfile].self, from: learnedData)

  // Load current quirks
  let quirkDB = try QuirkDatabase.load(pathEnv: quirksPath)

  // Filter profiles if specific fingerprint requested
  let profilesToAnalyze =
    targetFingerprint.map { fp in
      profiles.filter { $0.key.contains(fp) }
    } ?? profiles

  print("🔍 Analyzing \(profilesToAnalyze.count) learned profile(s)")
  print("")

  for (key, profile) in profilesToAnalyze {
    print("Profile: \(key)")
    print("  Samples: \(profile.sampleCount)")
    print("  Success Rate: \(String(format: "%.1f%%", profile.successRate * 100))")
    print("  Last Updated: \(profile.lastUpdated.ISO8601Format())")

    if profile.successRate > 0.8 && profile.sampleCount >= 3 {
      // Resolve USB identifiers from fingerprint hex strings
      let vid = UInt16(profile.fingerprint.vid, radix: 16) ?? 0
      let pid = UInt16(profile.fingerprint.pid, radix: 16) ?? 0
      let bcdDevice = profile.fingerprint.bcdDevice.flatMap { UInt16($0, radix: 16) }
      let ifaceClass = UInt8(profile.fingerprint.interfaceTriple.class, radix: 16)
      let ifaceSubclass = UInt8(profile.fingerprint.interfaceTriple.subclass, radix: 16)
      let ifaceProtocol = UInt8(profile.fingerprint.interfaceTriple.protocol, radix: 16)

      if let existingQuirk = quirkDB.match(
        vid: vid, pid: pid, bcdDevice: bcdDevice,
        ifaceClass: ifaceClass, ifaceSubclass: ifaceSubclass, ifaceProtocol: ifaceProtocol
      ) {
        print("  Existing Quirk: \(existingQuirk.id) (\(existingQuirk.status ?? "unknown"))")

        // Compare learned values with quirk values
        var suggestions = [String]()

        if let learnedChunk = profile.optimalChunkSize {
          let quirkChunk = existingQuirk.maxChunkBytes ?? 1_048_576
          if abs(learnedChunk - quirkChunk) > quirkChunk / 4 {  // 25% difference
            suggestions.append("maxChunkBytes: \(quirkChunk) -> \(learnedChunk)")
          }
        }

        if let learnedIO = profile.optimalIoTimeoutMs {
          let quirkIO = existingQuirk.ioTimeoutMs ?? 8000
          if abs(learnedIO - quirkIO) > quirkIO / 4 {
            suggestions.append("ioTimeoutMs: \(quirkIO) -> \(learnedIO)")
          }
        }

        if !suggestions.isEmpty {
          print("  📈 Suggestions:")
          suggestions.forEach { print("    - \($0)") }
        } else {
          print("  ✅ No significant differences from current quirk")
        }

      } else {
        print(
          "  🆕 No existing quirk for VID:\(profile.fingerprint.vid) PID:\(profile.fingerprint.pid) — consider creating one"
        )
        print("  📝 Suggested values:")
        if let chunk = profile.optimalChunkSize {
          print("    maxChunkBytes: \(chunk)")
        }
        if let io = profile.optimalIoTimeoutMs {
          print("    ioTimeoutMs: \(io)")
        }
        if let readMBps = profile.p95ReadThroughputMBps {
          print("    readMBpsMin: \(readMBps)")
        }
      }
    } else {
      print("  ⏳ Not enough data (need ≥3 samples, ≥80% success)")
    }

    print("")
  }

  // Generate potential PR content
  if !profilesToAnalyze.isEmpty {
    print("📋 To create a PR with these changes:")
    print("1. Update Specs/quirks.json with suggested values")
    print("2. Update provenance date and commit hash")
    print("3. Run validation: ./scripts/validate-quirks.sh")
    print("4. Test with: swift run swiftmtp probe --json")
  }

} catch {
  print("❌ Error: \(error)")
  exit(1)
}
