// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import PackagePlugin
import Foundation

@main
struct SwiftMTPBuildTool: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let quirksPath = context.package.directory.appending("..", "Specs", "quirks.json")
        let outputDir = context.package.directory.appending("..", "Docs", "SwiftMTP.docc", "Devices")
        let scriptPath = context.package.directory.appending("Sources", "Tools", "docc-generator")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-c", "chmod +x \(scriptPath.string) && \(scriptPath.string) \(quirksPath.string) \(outputDir.string)"]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            print("❌ Documentation generation failed with exit code \(process.terminationStatus)")
            throw NSError(domain: "SwiftMTPBuildTool", code: Int(process.terminationStatus))
        }
        
        print("✅ Device documentation regenerated successfully.")
    }
}