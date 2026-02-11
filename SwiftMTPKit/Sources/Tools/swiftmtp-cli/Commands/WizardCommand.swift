// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

/// Interactive wizard that guides contributors through device snapshot + submission.
@MainActor
struct WizardCommand {

  static func printHelp() {
    print("Usage: swiftmtp wizard [options]")
    print("")
    print("Interactive guide for contributing a new device profile.")
    print("Walks you through: detect device, collect evidence, submit.")
    print("")
    print("Options:")
    print("  --timeout <sec>   Device detection timeout (default: 60)")
    print("  --safe            Enable safe mode (extra privacy redaction)")
    print("  --help, -h        Show this help")
  }

  static func run(flags: CLIFlags, args: [String]) async {
    if args.contains("--help") || args.contains("-h") {
      printHelp()
      return
    }

    var timeoutSec = 60
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
       let t = Int(args[idx + 1]) {
      timeoutSec = t
    }

    print("")
    print("=== SwiftMTP Device Wizard ===")
    print("")

    // Step 1: Detect or wait for device
    print("Step 1: Looking for MTP devices...")
    print("   Connect your Android device via USB and enable MTP file transfer.")
    print("")

    var devices: [MTPDeviceSummary] = []
    let deadline = Date().addingTimeInterval(Double(timeoutSec))

    while Date() < deadline {
      do {
        devices = try await LibUSBDiscovery.enumerateMTPDevices()
        if !devices.isEmpty { break }
      } catch {
        // Ignore transient errors during polling
      }
      print("   Waiting for device... (\(max(0, Int(deadline.timeIntervalSinceNow)))s remaining)")
      try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    guard !devices.isEmpty else {
      print("")
      print("No MTP device detected within \(timeoutSec)s.")
      print("Make sure your device is connected and set to MTP/File Transfer mode.")
      return
    }

    // Step 2: Select device
    let selected: MTPDeviceSummary
    if devices.count == 1 {
      selected = devices[0]
      let id = String(format: "%04x:%04x", selected.vendorID ?? 0, selected.productID ?? 0)
      print("   Found: \(selected.manufacturer) \(selected.model) [\(id)]")
    } else {
      print("   Found \(devices.count) devices:")
      for (i, dev) in devices.enumerated() {
        let id = String(format: "%04x:%04x", dev.vendorID ?? 0, dev.productID ?? 0)
        let busAddr = String(format: "%d:%d", dev.bus ?? 0, dev.address ?? 0)
        print("   \(i + 1). \(dev.manufacturer) \(dev.model) [\(id)] @ \(busAddr)")
      }
      print("")
      print("   Enter device number (1-\(devices.count)): ", terminator: "")
      if let line = readLine(), let choice = Int(line), choice >= 1, choice <= devices.count {
        selected = devices[choice - 1]
      } else {
        print("Invalid selection. Using first device.")
        selected = devices[0]
      }
    }
    print("")

    // Step 3: Check known status
    print("Step 2: Checking device database...")
    do {
      let qdb = try QuirkDatabase.load()
      if let match = qdb.match(vid: selected.vendorID ?? 0, pid: selected.productID ?? 0,
                                bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil) {
        print("   Known device: \(match.id) (status: \(match.status ?? "unknown"))")
      } else {
        print("   New device! Not in the quirks database yet.")
      }
    } catch {
      print("   Could not load quirks database: \(error)")
    }
    print("")

    // Step 4: Privacy notice
    print("Step 3: Privacy notice")
    print("   The wizard will collect:")
    print("   - Device info (manufacturer, model, MTP capabilities)")
    print("   - USB interface descriptors")
    print("   - Storage info (capacity, type)")
    print("")
    print("   It will NOT collect:")
    print("   - File names or contents")
    print("   - Serial numbers (redacted)")
    print("   - Personal data")
    print("")
    print("   Continue? [Y/n] ", terminator: "")
    if let answer = readLine()?.lowercased(), answer == "n" || answer == "no" {
      print("Aborted.")
      return
    }
    print("")

    // Step 5: Collect bundle
    print("Step 4: Collecting device evidence...")
    let collectFlags = CollectCommand.CollectFlags(
      strict: true,
      safe: flags.safe || true, // wizard always uses safe mode
      runBench: [],
      json: false,
      noninteractive: true,
      bundlePath: nil,
      vid: selected.vendorID,
      pid: selected.productID,
      bus: selected.bus.map { Int($0) },
      address: selected.address.map { Int($0) }
    )

    let bundleURL: URL
    do {
      let result = try await CollectCommand.collectBundle(flags: collectFlags)
      bundleURL = result.bundleURL
      print("   Bundle created: \(bundleURL.path)")
    } catch {
      print("   Collection failed: \(error)")
      return
    }
    print("")

    // Step 6: Zip bundle
    let zipURL = bundleURL.deletingLastPathComponent()
      .appendingPathComponent(bundleURL.lastPathComponent + ".zip")
    let zipProcess = Process()
    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zipProcess.arguments = ["-r", "-j", zipURL.path, bundleURL.path]
    zipProcess.standardOutput = FileHandle.nullDevice
    zipProcess.standardError = FileHandle.nullDevice
    do {
      try zipProcess.run()
      zipProcess.waitUntilExit()
      if zipProcess.terminationStatus == 0 {
        print("   Zipped: \(zipURL.lastPathComponent)")
      }
    } catch {
      // zip not available, that's fine
    }
    print("")

    // Step 7: Present actions
    print("Step 5: What would you like to do?")
    print("")
    print("   1. Submit via GitHub PR (requires gh CLI)")
    print("   2. Open bundle in Finder")
    print("   3. Print path and exit")
    print("")
    print("   Enter choice (1-3): ", terminator: "")

    let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "3"

    switch choice {
    case "1":
      let ghBundlePath = zipProcess.terminationStatus == 0 ? zipURL.path : bundleURL.path
      let exitCode = await SubmitCommand.run(bundlePath: ghBundlePath, gh: true)
      if exitCode != .ok {
        print("   Submission encountered an issue (exit code: \(exitCode)).")
        print("   You can manually submit the bundle at: \(bundleURL.path)")
      }
    case "2":
      let openProcess = Process()
      openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      openProcess.arguments = ["-R", bundleURL.path]
      try? openProcess.run()
      openProcess.waitUntilExit()
    default:
      print("")
      print("Bundle path: \(bundleURL.path)")
      if zipProcess.terminationStatus == 0 {
        print("Zip path:    \(zipURL.path)")
      }
    }

    print("")
    print("Done! Thank you for contributing to SwiftMTP.")
  }
}
