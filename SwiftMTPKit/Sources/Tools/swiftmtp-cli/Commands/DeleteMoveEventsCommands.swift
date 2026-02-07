// DeleteMoveEventsCommands.swift
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks


// DELETE
func runDeleteCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
  guard args.count >= 1, let handle = UInt32(args.removeFirst(), radix: 0) else {
    if json { printJSONErrorAndExit("missing_handle", code: .usage) }
    fputs("usage: swiftmtp delete <handle> [--recursive]\n", stderr); return .usage
  }
  let recursive = args.contains("--recursive")

  // Check if we're in a TTY for spinner
  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Deleting …", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let opened = try await openFilteredDevice(
      filter: filter,
      noninteractive: noninteractive,
      strict: strict,
      safe: safe
    )

    try await opened.device.delete(handle, recursive: recursive)
    if !json && isTTY { spinner.succeed("Deleted") }
    return .ok

  } catch let DeviceOpenError.noneMatched(available) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "No device matched the provided filter.",
        code: .unavailable,
        details: [
          "availableDevices": "\(available.count)",
          "examples": available.prefix(3).map { "\(String(format: "%04x", $0.vendorID ?? 0)):\(String(format: "%04x", $0.productID ?? 0))@\($0.bus ?? 0):\($0.address ?? 0)" }.joined(separator: ", ")
        ]
      )
    } else {
      fputs("No device matched the provided filter.\n", stderr)
      return .unavailable
    }

  } catch let DeviceOpenError.ambiguous(matches) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "Multiple devices match the filter; refine with --bus/--address.",
        code: .usage,
        details: [
           "matches": matches.map { "\(String(format: "%04x", $0.vendorID ?? 0)):\(String(format: "%04x", $0.productID ?? 0))@\($0.bus ?? 0):\($0.address ?? 0)" }.joined(separator: ", ")
        ]
      )
    } else {
      fputs("Multiple devices match; refine with --bus/--address.\n", stderr)
      return .usage
    }

  } catch {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(error.localizedDescription, code: .software)
    } else {
      fputs("❌ delete failed: \(error)\n", stderr)
      return .software
    }
  }
}

// MOVE
func runMoveCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
  guard args.count >= 2,
        let handle = UInt32(args.removeFirst(), radix: 0),
        let parent = UInt32(args.removeFirst(), radix: 0) else {
    if json { printJSONErrorAndExit("missing_args", code: .usage) }
    fputs("usage: swiftmtp move <handle> <new-parent-handle>\n", stderr); return .usage
  }

  // Check if we're in a TTY for spinner
  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Moving …", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let opened = try await openFilteredDevice(
      filter: filter,
      noninteractive: noninteractive,
      strict: strict,
      safe: safe
    )

    try await opened.device.move(handle, to: parent)
    if !json && isTTY { spinner.succeed("Moved") }
    return .ok

  } catch let DeviceOpenError.noneMatched(available) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "No device matched the provided filter.",
        code: .unavailable,
        details: [
          "availableDevices": "\(available.count)"
        ]
      )
    } else {
      fputs("No device matched the provided filter.\n", stderr)
      return .unavailable
    }

  } catch let DeviceOpenError.ambiguous(matches) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "Multiple devices match the filter; refine with --bus/--address.",
        code: .usage,
        details: [
           "matches": matches.map { "\(String(format: "%04x", $0.vendorID ?? 0)):\(String(format: "%04x", $0.productID ?? 0))@\($0.bus ?? 0):\($0.address ?? 0)" }.joined(separator: ", ")
        ]
      )
    } else {
      fputs("Multiple devices match; refine with --bus/--address.\n", stderr)
      return .usage
    }

  } catch {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(error.localizedDescription, code: .software)
    } else {
      fputs("❌ move failed: \(error)\n", stderr)
      return .software
    }
  }
}

// EVENTS (prints lines or JSONL)
func runEventsCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
  let seconds = (args.first.flatMap { Int($0) }) ?? 30

  // Check if we're in a TTY for spinner
  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Listening for events (\(seconds)s)…", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let opened = try await openFilteredDevice(
      filter: filter,
      noninteractive: noninteractive,
      strict: strict,
      safe: safe
    )

    if !json && isTTY { spinner.succeed("Connected") }

    // Stream events for the requested duration.
    let deadline = DispatchTime.now().uptimeNanoseconds
                 + UInt64(seconds) * 1_000_000_000

    var out: [EventOut] = []
    let iso = ISO8601DateFormatter()

    // Your DeviceActor exposes an AsyncStream<MTPEvent>
    for await ev in opened.device.events {
      let e = EventOut(
        ts: iso.string(from: Date()),
        code: ev.code,            // UInt16 on your MTPEvent
        params: ev.parameters     // [UInt32] on your MTPEvent
      )
      if json {
        out.append(e)
      } else {
        print(String(format: "0x%04X  params=%@", e.code, "\(e.params)"))
      }
      if DispatchTime.now().uptimeNanoseconds >= deadline { break }
    }

    if !json && isTTY { spinner.succeed("Complete") }
    if json { printJSON(out) }
    return .ok

  } catch let DeviceOpenError.noneMatched(available) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "No device matched the provided filter.",
        code: .unavailable,
        details: [
          "availableDevices": "\(available.count)"
        ]
      )
    } else {
      fputs("No device matched the provided filter.\n", stderr)
      return .unavailable
    }

  } catch let DeviceOpenError.ambiguous(matches) {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(
        "Multiple devices match the filter; refine with --bus/--address.",
        code: .usage,
        details: [
           "matches": matches.map { "\(String(format: "%04x", $0.vendorID ?? 0)):\(String(format: "%04x", $0.productID ?? 0))@\($0.bus ?? 0):\($0.address ?? 0)" }.joined(separator: ", ")
        ]
      )
    } else {
      fputs("Multiple devices match; refine with --bus/--address.\n", stderr)
      return .usage
    }

  } catch {
    if !json && isTTY { spinner.fail() }
    if json {
      printJSONErrorAndExit(error.localizedDescription, code: .software)
    } else {
      fputs("events failed: \(error)\n", stderr)
      return .software
    }
  }
}

// Helper struct for JSON output
private struct EventOut: Codable {
  let ts: String
  let code: UInt16
  let params: [UInt32]
}
