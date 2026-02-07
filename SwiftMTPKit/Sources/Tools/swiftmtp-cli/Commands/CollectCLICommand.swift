// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

@MainActor
struct CollectCLICommand {
    static func run(args: [String], flags: CLIFlags) async {
        var collectFlags = CollectCommand.CollectFlags(
            strict: flags.strict,
            runBench: [],
            json: flags.json,
            noninteractive: false,
            bundlePath: nil,
            vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
            pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
            bus: flags.targetBus,
            address: flags.targetAddress
        )
        
        // Basic arg parsing for collect-specific options
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--run-bench" && i + 1 < args.count {
                collectFlags.runBench = args[i+1].split(separator: ",").map { String($0) }
                i += 1
            } else if arg.hasPrefix("--run-bench=") {
                collectFlags.runBench = String(arg.dropFirst("--run-bench=".count)).split(separator: ",").map { String($0) }
            } else if arg == "--noninteractive" {
                collectFlags.noninteractive = true
            } else if arg == "--bundle" && i + 1 < args.count {
                collectFlags.bundlePath = args[i+1]
                i += 1
            } else if arg.hasPrefix("--bundle=") {
                collectFlags.bundlePath = String(arg.dropFirst("--bundle=".count))
            }
            i += 1
        }
        
        let exitCode = await CollectCommand.run(flags: collectFlags)
        exitNow(exitCode)
    }
    
    static func printHelp() {
        print("SwiftMTP Device Submission Collector")
        print("Usage: swift run swiftmtp collect [flags]")
        print("")
        print("Flags:")
        print("  --run-bench <sizes>  - Run benchmarks with sizes (e.g., '100M,1G')")
        print("  --noninteractive     - Skip consent prompts")
        print("  --bundle <path>      - Custom output location for submission bundle")
    }
}
