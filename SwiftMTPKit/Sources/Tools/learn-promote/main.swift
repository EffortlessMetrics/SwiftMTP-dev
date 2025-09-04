// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

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
    // TODO: Load learned profiles when LearnedProfile becomes Codable again
    // For now, use empty profiles
    let profiles: [String: LearnedProfile] = [:]

    // Load current quirks
    let quirksURL = URL(fileURLWithPath: quirksPath)
    let quirkDB = try QuirkDatabase(from: quirksURL)

    // Filter profiles if specific fingerprint requested
    let profilesToAnalyze = targetFingerprint.map { fp in
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
            // Check if there's an existing quirk
            if let existingQuirk = quirkDB.match(for: profile.fingerprint) {
                print("  Existing Quirk: \(existingQuirk.id) (\(existingQuirk.status))")

                // Compare learned values with quirk values
                var suggestions = [String]()

                if let learnedChunk = profile.optimalChunkSize,
                   let quirkChunk = existingQuirk.tuning.maxChunkBytes,
                   abs(learnedChunk - quirkChunk) > quirkChunk / 4 { // 25% difference
                    suggestions.append("maxChunkBytes: \(quirkChunk) -> \(learnedChunk)")
                }

                if let learnedIO = profile.optimalIoTimeoutMs,
                   let quirkIO = existingQuirk.tuning.ioTimeoutMs,
                   abs(learnedIO - quirkIO) > quirkIO / 4 {
                    suggestions.append("ioTimeoutMs: \(quirkIO) -> \(learnedIO)")
                }

                if !suggestions.isEmpty {
                    print("  📈 Suggestions:")
                    suggestions.forEach { print("    - \($0)") }
                } else {
                    print("  ✅ No significant differences from current quirk")
                }

            } else {
                print("  🆕 No existing quirk - consider creating one")
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
