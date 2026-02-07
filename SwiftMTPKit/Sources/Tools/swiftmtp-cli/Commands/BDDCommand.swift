// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

@MainActor
struct BDDCommand {
    static func run(flags: CLIFlags) async {
        print("🚀 Initializing BDD Test Runner...")
        do {
            let device = try await openDevice(flags: flags)
            try await device.openIfNeeded()
            
            // Assuming MTPDeviceActor exposes getMTPLinkIfAvailable
            if let actor = device as? MTPDeviceActor, 
               let link = await actor.getMTPLinkIfAvailable() {
                let context = BDDContext(link: link)
                let scenarios: [BDDScenario] = [
                    DiscoveryScenario(),
                    ListingScenario(),
                    UploadScenario()
                ]
                
                var passed = 0
                var failed = 0
                
                for scenario in scenarios {
                    print("\n🏃 Scenario: \(scenario.name)")
                    do {
                        try await scenario.execute(context: context)
                        print("✅ Scenario passed")
                        passed += 1
                    } catch {
                        print("❌ Scenario failed: \(error)")
                        failed += 1
                    }
                }
                
                print("\nBDD Summary:")
                print("   Total: \(scenarios.count)")
                print("   Passed: \(passed)")
                print("   Failed: \(failed)")
                
                if failed > 0 {
                    exitNow(.software)
                }
            } else {
                print("❌ BDD requires a device implementation that exposes its MTP link")
                exitNow(.unavailable)
            }
        } catch {
            print("\n❌ BDD runner failed: \(error)")
            exitNow(.tempfail)
        }
    }
}