// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPStore
import SwiftMTPCLI
import Foundation

@MainActor
struct SwiftMTPCLI {
  var realOnly = false
  var useMock = false
  var mockProfile = "default"
  var json = false
  var jsonlOutput = false
  var traceUSB = false
  var traceUSBDetails = false
  var strict = false
  var safe = false
  var targetVID: String?
  var targetPID: String?
  var targetBus: Int?
  var targetAddress: Int?
  var filteredArgs = [String]()

  mutating func parseArgs() {
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
      let arg = args[i]
      if arg == "--real-only" {
        realOnly = true
      } else if arg == "--mock" {
        useMock = true
      } else if arg.hasPrefix("--mock-profile=") {
        mockProfile = String(arg.dropFirst("--mock-profile=".count))
        useMock = true
      } else if arg == "--json" {
        json = true
      } else if arg == "--jsonl" {
        jsonlOutput = true
      } else if arg == "--trace-usb" {
        traceUSB = true
      } else if arg == "--trace-usb-details" {
        traceUSBDetails = true
      } else if arg == "--strict" {
        strict = true
      } else if arg == "--safe" {
        safe = true
      } else if arg == "--vid" {
        if i + 1 < args.count {
          targetVID = args[i + 1]
          i += 1
        }
      } else if arg.hasPrefix("--vid=") {
        targetVID = String(arg.dropFirst("--vid=".count))
      } else if arg == "--pid" {
        if i + 1 < args.count {
          targetPID = args[i + 1]
          i += 1
        }
      } else if arg.hasPrefix("--pid=") {
        targetPID = String(arg.dropFirst("--pid=".count))
      } else if arg == "--bus" {
        if i + 1 < args.count, let bus = Int(args[i + 1]) {
          targetBus = bus
          i += 1
        }
      } else if arg.hasPrefix("--bus=") {
        targetBus = Int(arg.dropFirst("--bus=".count))
      } else if arg == "--address" {
        if i + 1 < args.count, let address = Int(args[i + 1]) {
          targetAddress = address
          i += 1
        }
      } else if arg.hasPrefix("--address=") {
        targetAddress = Int(arg.dropFirst("--address=".count))
      } else {
        filteredArgs.append(arg)
      }
      i += 1
    }
  }

  func run() async {
    var mutableSelf = self
    mutableSelf.parseArgs()

    // Initialize persistence
    await MTPDeviceManager.shared.setPersistence(SwiftMTPStoreAdapter())

    if mutableSelf.filteredArgs.isEmpty {
      printHelp()
      exitNow(.ok)
    }

    let command = mutableSelf.filteredArgs[0]
    let remainingArgs = Array(mutableSelf.filteredArgs.dropFirst())
    let flags = CLIFlags(
      realOnly: mutableSelf.realOnly,
      useMock: mutableSelf.useMock,
      mockProfile: mutableSelf.mockProfile,
      json: mutableSelf.json,
      jsonlOutput: mutableSelf.jsonlOutput,
      traceUSB: mutableSelf.traceUSB,
      strict: mutableSelf.strict,
      safe: mutableSelf.safe,
      traceUSBDetails: mutableSelf.traceUSBDetails,
      targetVID: mutableSelf.targetVID,
      targetPID: mutableSelf.targetPID,
      targetBus: mutableSelf.targetBus,
      targetAddress: mutableSelf.targetAddress
    )

    switch command {
    case "storybook":
      await StorybookCommand.run()
    case "probe":
      await ProbeCommand.runProbe(flags: flags)
    case "usb-dump":
      await ProbeCommand.runUSBDump(flags: flags)
    case "device-lab":
      await DeviceLabCommand.run(flags: flags, args: remainingArgs)
    case "diag":
      await ProbeCommand.runDiag(flags: flags)
    case "storages":
      await StorageListCommands.runStorages(flags: flags)
    case "ls":
      await StorageListCommands.runList(flags: flags, args: remainingArgs)
    case "pull":
      await TransferCommands.runPull(flags: flags, args: remainingArgs)
    case "push":
      await TransferCommands.runPush(flags: flags, args: remainingArgs)
    case "bench":
      await TransferCommands.runBench(flags: flags, args: remainingArgs)
    case "profile":
      if remainingArgs.contains("--collect") {
        await ProfileCommand.runCollect(flags: flags)
      } else {
        var iter = 3
        if let idx = remainingArgs.firstIndex(of: "--iterations"), idx + 1 < remainingArgs.count {
          iter = Int(remainingArgs[idx + 1]) ?? 3
        }
        await ProfileCommand.run(flags: flags, iterations: iter)
      }
    case "mirror":
      await TransferCommands.runMirror(flags: flags, args: remainingArgs)
    case "quirks":
      await SystemCommands.runQuirks(flags: flags, args: remainingArgs)
    case "health":
      await SystemCommands.runHealth()
    case "delete":
      let filter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      var cmdArgs = remainingArgs
      let exitCode = await runDeleteCommand(
        args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter,
        strict: flags.strict, safe: flags.safe)
      exitNow(exitCode)
    case "move":
      let filter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      var cmdArgs = remainingArgs
      let exitCode = await runMoveCommand(
        args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter,
        strict: flags.strict, safe: flags.safe)
      exitNow(exitCode)
    case "cp", "copy":
      let filter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      var cmdArgs = remainingArgs
      let exitCode = await runCopyCommand(
        args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter,
        strict: flags.strict, safe: flags.safe)
      exitNow(exitCode)
    case "edit":
      let filter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      var cmdArgs = remainingArgs
      let exitCode = await runEditCommand(
        args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter,
        strict: flags.strict, safe: flags.safe)
      exitNow(exitCode)
    case "events":
      let filter = DeviceFilter(
        vid: parseUSBIdentifier(flags.targetVID),
        pid: parseUSBIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
      )
      var cmdArgs = remainingArgs
      let exitCode = await runEventsCommand(
        args: &cmdArgs, json: flags.json, noninteractive: true, filter: filter,
        strict: flags.strict, safe: flags.safe)
      exitNow(exitCode)
    case "collect":
      if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
        CollectCLICommand.printHelp()
        exitNow(.ok)
      }
      await CollectCLICommand.run(args: remainingArgs, flags: flags)
    case "info":
      await SystemCommands.runInfo(flags: flags)
    case "add-device":
      AddDeviceCommand.run(flags: flags, args: remainingArgs)
    case "wizard":
      await WizardCommand.run(flags: flags, args: remainingArgs)
    case "submit":
      guard let bundlePath = remainingArgs.first else {
        print("❌ Missing required argument: <bundle-path>")
        print("   Usage: swiftmtp submit <bundle-path> [--gh]")
        print("   Example: swiftmtp submit ./my-device-bundle --gh")
        print("   Tip: Run 'swiftmtp collect' first to create a submission bundle.")
        exitNow(.usage)
      }
      let gh = remainingArgs.contains("--gh")
      let exitCode = await SubmitCommand.run(bundlePath: bundlePath, gh: gh)
      exitNow(exitCode)
    case "learn-promote":
      guard MTPFeatureFlags.shared.isEnabled(.learnPromote) else {
        print("❌ Experimental 'learn-promote' feature is disabled.")
        print("   Enable with SWIFTMTP_FEATURE_LEARN_PROMOTE=1")
        exitNow(.unavailable)
      }
      if remainingArgs.contains("--help") || remainingArgs.contains("-h") {
        LearnPromoteCommand.printHelp()
        exitNow(.ok)
      }
      await LearnPromoteCommand.runCLI(args: remainingArgs)
    case "bdd":
      await BDDCommand.run(flags: flags)
    case "snapshot":
      await SnapshotCommand.run(flags: flags, args: remainingArgs)
    case "version":
      await SystemCommands.runVersion(flags: flags, args: remainingArgs)
    default:
      print("❌ Unknown command: '\(command)'")
      if let suggestion = suggestCommand(command) {
        print("   Did you mean '\(suggestion)'?")
      }
      print("   Run 'swiftmtp --help' to see available commands.")
      exitNow(.usage)
    }
  }

  /// Known commands for "did you mean?" suggestions.
  private static let knownCommands = [
    "probe", "usb-dump", "device-lab", "diag", "storages", "ls", "pull", "push",
    "bench", "mirror", "quirks", "info", "health", "collect", "submit",
    "add-device", "wizard", "delete", "move", "cp", "copy", "edit", "events",
    "learn-promote", "bdd", "snapshot", "version", "storybook", "profile",
  ]

  /// Suggest the closest known command for a typo using simple edit-distance heuristics.
  private func suggestCommand(_ input: String) -> String? {
    let lowered = input.lowercased()
    // Prefix match first (e.g. "prob" -> "probe")
    let prefixMatches = Self.knownCommands.filter { $0.hasPrefix(lowered) }
    if prefixMatches.count == 1 { return prefixMatches[0] }
    // Substring match (e.g. "irror" -> "mirror")
    let substringMatches = Self.knownCommands.filter {
      $0.contains(lowered) || lowered.contains($0)
    }
    if substringMatches.count == 1 { return substringMatches[0] }
    // Levenshtein distance ≤ 2
    for cmd in Self.knownCommands {
      if levenshtein(lowered, cmd) <= 2 { return cmd }
    }
    return nil
  }

  /// Minimal Levenshtein distance for short strings.
  private func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var dp = Array(0...b.count)
    for i in 1...a.count {
      var prev = dp[0]
      dp[0] = i
      for j in 1...b.count {
        let tmp = dp[j]
        dp[j] = a[i - 1] == b[j - 1] ? prev : min(prev, dp[j], dp[j - 1]) + 1
        prev = tmp
      }
    }
    return dp[b.count]
  }

  func printHelp() {
    print("SwiftMTP CLI — MTP device management for macOS")
    print("")
    print("Usage: swiftmtp [flags] <command> [arguments]")
    print("")
    print("Device Discovery:")
    print("  probe             Detect and display MTP device info")
    print("  usb-dump          Dump raw USB interface descriptors")
    print("  diag              Run probe + usb-dump diagnostics")
    print("  health            Quick USB/MTP connectivity check")
    print("")
    print("File Operations:")
    print("  ls <storage>      List files in a storage")
    print("  storages          List available storage volumes")
    print("  pull <h> <dest>   Download a file by handle")
    print("  push <src> <dst>  Upload a file to a folder")
    print("  delete <handle>   Delete an object on the device")
    print("  move <h> <parent> Move an object to a new parent")
    print("  cp <h> <storage>  Copy an object (server-side)")
    print("  mirror <dest>     Mirror device contents locally")
    print("    --photos-only            Only mirror image files")
    print("    --format ext[,ext...]    Only mirror specified formats")
    print("    --exclude-format ext[,ext...] Exclude specified formats")
    print("  snapshot          Capture full device content snapshot")
    print("")
    print("Edit Extensions (Android):")
    print("  edit begin <h>    Begin in-place editing of an object")
    print("  edit end <h>      Commit in-place edits for an object")
    print("  edit truncate <h> <size>  Truncate a file to given size")
    print("")
    print("Performance:")
    print("  bench <size>      Benchmark transfer speed")
    print("  profile           Profile device transfer characteristics")
    print("")
    print("Device Database:")
    print("  quirks            Query/explain device quirk profiles")
    print("  info              Show quirks database summary")
    print("  add-device        Generate a new device quirk template")
    print("  learn-promote     Promote a learned profile to quirks DB")
    print("")
    print("Device Contribution:")
    print("  collect           Collect device evidence for submission")
    print("  submit <bundle>   Submit a device profile bundle")
    print("  wizard            Interactive guided device setup")
    print("  device-lab        Automated device testing matrix")
    print("")
    print("Other:")
    print("  events [secs]     Monitor MTP device events")
    print("  bdd               Run BDD scenario tests on a device")
    print("  storybook         Run demo storybook scenarios")
    print("  version           Show version and build info")
    print("")
    print("Global Flags:")
    print("  --json            Output results as JSON")
    print("  --vid <hex>       Filter by USB Vendor ID  (e.g. 0x18d1)")
    print("  --pid <hex>       Filter by USB Product ID (e.g. 0x4ee1)")
    print("  --bus <n>         Filter by USB bus number")
    print("  --address <n>     Filter by USB device address")
    print("  --mock            Use simulated demo device")
    print("  --safe            Enable safe mode (extra checks)")
    print("  --strict          Enable strict mode (fail on warnings)")
    print("  --trace-usb       Enable USB trace logging")
    print("")
    print("Examples:")
    print("  swiftmtp probe")
    print("  swiftmtp ls 65537")
    print("  swiftmtp pull 42 ./photo.jpg")
    print("  swiftmtp push ./file.txt Download")
    print("  swiftmtp quirks lookup --vid 0x18d1 --pid 0x4ee1")
    print("  swiftmtp bench 10M --repeat 3 --out results.csv")
  }
}

// Global actor entry point
await SwiftMTPCLI().run()
