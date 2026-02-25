// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI

struct SubmitCommand {
  static func run(bundlePath: String, gh: Bool) async -> ExitCode {
    print("🚀 Preparing device submission...")

    let bundleURL = URL(fileURLWithPath: bundlePath)
    let manifestURL = bundleURL.appendingPathComponent("submission.json")

    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      print("❌ Invalid bundle: submission.json missing at \(manifestURL.path)")
      return .usage
    }

    do {
      let data = try Data(contentsOf: manifestURL)
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

      let vid = String(format: "%04x", json?["vendorID"] as? UInt16 ?? 0)
      let pid = String(format: "%04x", json?["productID"] as? UInt16 ?? 0)

      // Try to find device name from probe.json
      let probeURL = bundleURL.appendingPathComponent("probe.json")
      var deviceName = "Unknown Device"
      if let probeData = try? Data(contentsOf: probeURL),
        let probeJson = try? JSONSerialization.jsonObject(with: probeData) as? [String: Any],
        let deviceInfo = probeJson["deviceInfo"] as? [String: Any]
      {
        let manufacturer = deviceInfo["manufacturer"] as? String ?? ""
        let model = deviceInfo["model"] as? String ?? ""
        deviceName = "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces)
      }

      if gh {
        guard await GitHubIntegration.isGitHubCLIInstalled() else {
          print("❌ GitHub CLI (gh) is not installed. Please install it or use manual submission.")
          return .unavailable
        }

        guard await GitHubIntegration.isGitHubCLIAuthenticated() else {
          print("❌ GitHub CLI is not authenticated. Run 'gh auth login'.")
          return .unavailable
        }

        let branchName = GitHubIntegration.generateBranchName(
          deviceName: deviceName, vendorId: vid, productId: pid)
        print("🌿 Creating branch: \(branchName)")
        try await GitHubIntegration.createBranch(name: branchName)

        print("📁 Staging files...")
        try await GitHubIntegration.addFiles(paths: [bundlePath])

        let commitMsg = GitHubIntegration.generateCommitMessage(
          deviceName: deviceName, vendorId: vid, productId: pid)
        print("💾 Committing: \(commitMsg)")
        try await GitHubIntegration.commitChanges(message: commitMsg)

        print("📤 Pushing to remote...")
        try await GitHubIntegration.pushBranch(branchName: branchName)

        print("📝 Creating Pull Request...")
        let prTitle = "Device submission: \(deviceName)"
        let prBody = GitHubIntegration.generatePRBody(
          deviceName: deviceName, vendorId: vid, productId: pid, bundlePath: bundlePath)
        try await GitHubIntegration.createPullRequest(title: prTitle, body: prBody)

        print("✅ Submission successful! PR created.")
      } else {
        print("✅ Bundle is valid for submission.")
        print("👉 To submit, please zip \(bundlePath) and attach it to a GitHub issue")
        print("   or run with --gh if you have the GitHub CLI installed.")
      }

      return .ok
    } catch {
      print("❌ Submission failed: \(error)")
      return .software
    }
  }
}
