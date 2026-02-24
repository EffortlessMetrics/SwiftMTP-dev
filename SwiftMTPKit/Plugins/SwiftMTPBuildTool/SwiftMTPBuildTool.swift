// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import PackagePlugin

@main
struct SwiftMTPBuildTool: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    // Use the URL-based API (Path.appending(_:) is deprecated in Swift Package Plugin API v2)
    let pkgURL = context.package.directoryURL
    let quirksURL = pkgURL.deletingLastPathComponent().appendingPathComponent(
      "Specs/quirks.json", isDirectory: false)
    let outputURL = pkgURL.deletingLastPathComponent().appendingPathComponent(
      "Docs/SwiftMTP.docc/Devices", isDirectory: true)

    let quirksPath = quirksURL.path
    let outputPath = outputURL.path

    // Delegate to the `swiftmtp-docs` SPM executable target for hands-off doc generation.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "swift", "run", "--package-path", pkgURL.path,
      "swiftmtp-docs", quirksPath, outputPath,
    ]

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      print("❌ Documentation generation failed with exit code \(process.terminationStatus)")
      throw NSError(domain: "SwiftMTPBuildTool", code: Int(process.terminationStatus))
    }

    print("✅ Device documentation regenerated successfully.")
  }
}
