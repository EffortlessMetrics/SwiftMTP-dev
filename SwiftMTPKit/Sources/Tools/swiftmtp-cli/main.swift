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
    case "wizard":
      await WizardCommand.run(flags: flags, args: remainingArgs)
    case "submit":
      guard let bundlePath = remainingArgs.first else {
        print("❌ Usage: submit <bundle-path> [--gh]")
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
      print("Unknown command: \(command)")
      exitNow(.usage)
    }
  }

  func printHelp() {
    print("SwiftMTP CLI - Modular Refactor")
    print("Usage: swift run swiftmtp [flags] <command>")
    print("")
    print(
      "Commands: probe, usb-dump, device-lab, diag, storages, ls, pull, push, bench, mirror, quirks, health, collect, submit, wizard, delete, move, events, learn-promote, bdd, snapshot, version"
    )
  }
}

// Global actor entry point
await SwiftMTPCLI().run()
