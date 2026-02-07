// DeleteMoveEventsCommands.swift
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

@MainActor
func runDeleteCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: SwiftMTPCore.DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
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
    // Construct CLIFlags for openDevice
    let flags = CLIFlags(
        realOnly: true, useMock: false, mockProfile: "", 
        json: json, jsonlOutput: false, traceUSB: false, 
        strict: strict, safe: safe, traceUSBDetails: false, 
        targetVID: filter.vid.map { String(format: "%04x", $0) }, 
        targetPID: filter.pid.map { String(format: "%04x", $0) }, 
        targetBus: filter.bus, 
        targetAddress: filter.address
    )
    
    let device = try await openDevice(flags: flags)
    try await device.openIfNeeded()

    try await device.delete(handle, recursive: recursive)
    if !json && isTTY { spinner.succeed("Deleted") }
    return .ok

  } catch {
    if !json && isTTY { spinner.fail() }
    
    if let mtpError = error as? MTPError, case .notSupported = mtpError {
        if json {
            printJSONErrorAndExit("No device matched the provided filter.", code: .unavailable)
        } else {
            fputs("No device matched the provided filter.\n", stderr)
            return .unavailable
        }
    }
    
    if json {
      printJSONErrorAndExit(error.localizedDescription, code: .software)
    } else {
      fputs("❌ delete failed: \(error)\n", stderr)
      return .software
    }
  }
}

@MainActor
func runMoveCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: SwiftMTPCore.DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
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
    let flags = CLIFlags(
        realOnly: true, useMock: false, mockProfile: "", 
        json: json, jsonlOutput: false, traceUSB: false, 
        strict: strict, safe: safe, traceUSBDetails: false, 
        targetVID: filter.vid.map { String(format: "%04x", $0) }, 
        targetPID: filter.pid.map { String(format: "%04x", $0) }, 
        targetBus: filter.bus, 
        targetAddress: filter.address
    )
    
    let device = try await openDevice(flags: flags)
    try await device.openIfNeeded()

    try await device.move(handle, to: parent)
    if !json && isTTY { spinner.succeed("Moved") }
    return .ok

  } catch {
    if !json && isTTY { spinner.fail() }
    
    if let mtpError = error as? MTPError, case .notSupported = mtpError {
        if json {
            printJSONErrorAndExit("No device matched the provided filter.", code: .unavailable)
        } else {
            fputs("No device matched the provided filter.\n", stderr)
            return .unavailable
        }
    }
    
    if json {
      printJSONErrorAndExit(error.localizedDescription, code: .software)
    } else {
      fputs("❌ move failed: \(error)\n", stderr)
      return .software
    }
  }
}

@MainActor
func runEventsCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: SwiftMTPCore.DeviceFilter, strict: Bool, safe: Bool) async -> ExitCode {
  let seconds = (args.first.flatMap { Int($0) }) ?? 30

  // Check if we're in a TTY for spinner
  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Listening for events (\(seconds)s)…", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let flags = CLIFlags(
        realOnly: true, useMock: false, mockProfile: "", 
        json: json, jsonlOutput: false, traceUSB: false, 
        strict: strict, safe: safe, traceUSBDetails: false, 
        targetVID: filter.vid.map { String(format: "%04x", $0) }, 
        targetPID: filter.pid.map { String(format: "%04x", $0) }, 
        targetBus: filter.bus, 
        targetAddress: filter.address
    )
    
    let device = try await openDevice(flags: flags)
    try await device.openIfNeeded()

    if !json && isTTY { spinner.succeed("Connected") }

    // Stream events for the requested duration.
    let deadline = DispatchTime.now().uptimeNanoseconds
                 + UInt64(seconds) * 1_000_000_000

    var out: [EventOut] = []
    let iso = ISO8601DateFormatter()

    // Your DeviceActor exposes an AsyncStream<MTPEvent>
    for await ev in device.events {
      let code: UInt16
      let params: [UInt32]
      
      switch ev {
      case .objectAdded(let handle):
          code = 0x4002
          params = [handle]
      case .objectRemoved(let handle):
          code = 0x4003
          params = [handle]
      case .storageInfoChanged(let storageId):
          code = 0x400C
          params = [storageId.raw]
      }
      
      let e = EventOut(
        ts: iso.string(from: Date()),
        code: code,
        params: params
      )
      if json {
        out.append(e)
      } else {
        print(String(format: "0x%04X  params=%@", e.code, "\(e.params)"))
      }
      if DispatchTime.now().uptimeNanoseconds >= deadline { break }
    }

    if !json && isTTY { spinner.succeed("Complete") }
    if json { printJSON(out, type: "events") }
    return .ok

  } catch {
    if !json && isTTY { spinner.fail() }
    
    if let mtpError = error as? MTPError, case .notSupported = mtpError {
        if json {
            printJSONErrorAndExit("No device matched the provided filter.", code: .unavailable)
        } else {
            fputs("No device matched the provided filter.\n", stderr)
            return .unavailable
        }
    }
    
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