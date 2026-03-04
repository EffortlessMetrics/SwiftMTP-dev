// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import SwiftMTPCLI

/// Dispatches `swiftmtp edit <subcommand>` to the appropriate handler.
@MainActor
func runEditCommand(
  args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter,
  strict: Bool, safe: Bool
) async -> ExitCode {
  guard let subcommand = args.first else {
    if json { printJSONErrorAndExit("missing_subcommand", code: .usage) }
    fputs("❌ Missing edit subcommand.\n", stderr)
    fputs("   Usage: swiftmtp edit <begin|end|truncate> <handle> [args]\n", stderr)
    fputs("   These commands expose Android MTP edit extensions for debugging.\n", stderr)
    return .usage
  }
  args.removeFirst()

  switch subcommand {
  case "begin":
    return await runEditBegin(
      args: &args, json: json, filter: filter, strict: strict, safe: safe)
  case "end":
    return await runEditEnd(
      args: &args, json: json, filter: filter, strict: strict, safe: safe)
  case "truncate":
    return await runEditTruncate(
      args: &args, json: json, filter: filter, strict: strict, safe: safe)
  default:
    if json { printJSONErrorAndExit("unknown_subcommand", code: .usage) }
    fputs("❌ Unknown edit subcommand: '\(subcommand)'\n", stderr)
    fputs("   Available: begin, end, truncate\n", stderr)
    return .usage
  }
}

// MARK: - edit begin

@MainActor
private func runEditBegin(
  args: inout [String], json: Bool, filter: DeviceFilter,
  strict: Bool, safe: Bool
) async -> ExitCode {
  guard let handle = args.first.flatMap({ UInt32($0, radix: 0) }) else {
    if json { printJSONErrorAndExit("missing_handle", code: .usage) }
    fputs("❌ Missing required argument: <handle>\n", stderr)
    fputs("   Usage: swiftmtp edit begin <handle>\n", stderr)
    return .usage
  }

  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("BeginEdit …", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let device = try await openEditDevice(json: json, filter: filter, strict: strict, safe: safe)
    try await device.beginEdit(handle: handle)
    if !json && isTTY { spinner.succeed("BeginEdit OK") }
    if json {
      printJSON(["handle": handle, "action": "beginEdit"] as [String: Any], type: "edit")
    } else {
      print("BeginEdit succeeded for handle \(handle)")
    }
    return .ok
  } catch {
    if !json && isTTY { spinner.fail() }
    return handleEditError(error, operation: "BeginEdit", json: json)
  }
}

// MARK: - edit end

@MainActor
private func runEditEnd(
  args: inout [String], json: Bool, filter: DeviceFilter,
  strict: Bool, safe: Bool
) async -> ExitCode {
  guard let handle = args.first.flatMap({ UInt32($0, radix: 0) }) else {
    if json { printJSONErrorAndExit("missing_handle", code: .usage) }
    fputs("❌ Missing required argument: <handle>\n", stderr)
    fputs("   Usage: swiftmtp edit end <handle>\n", stderr)
    return .usage
  }

  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("EndEdit …", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let device = try await openEditDevice(json: json, filter: filter, strict: strict, safe: safe)
    try await device.endEdit(handle: handle)
    if !json && isTTY { spinner.succeed("EndEdit OK") }
    if json {
      printJSON(["handle": handle, "action": "endEdit"] as [String: Any], type: "edit")
    } else {
      print("EndEdit succeeded for handle \(handle)")
    }
    return .ok
  } catch {
    if !json && isTTY { spinner.fail() }
    return handleEditError(error, operation: "EndEdit", json: json)
  }
}

// MARK: - edit truncate

@MainActor
private func runEditTruncate(
  args: inout [String], json: Bool, filter: DeviceFilter,
  strict: Bool, safe: Bool
) async -> ExitCode {
  guard args.count >= 2,
    let handle = UInt32(args[0], radix: 0),
    let size = UInt64(args[1])
  else {
    if json { printJSONErrorAndExit("missing_args", code: .usage) }
    fputs("❌ Missing required arguments.\n", stderr)
    fputs("   Usage: swiftmtp edit truncate <handle> <size>\n", stderr)
    return .usage
  }

  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Truncate …", enabled: !json && isTTY)
  if !json && isTTY { spinner.start() }

  do {
    let device = try await openEditDevice(json: json, filter: filter, strict: strict, safe: safe)
    try await device.truncateFile(handle: handle, size: size)
    if !json && isTTY { spinner.succeed("Truncate OK") }
    if json {
      printJSON(
        ["handle": handle, "size": size, "action": "truncate"] as [String: Any], type: "edit")
    } else {
      print("Truncate succeeded for handle \(handle) → \(size) bytes")
    }
    return .ok
  } catch {
    if !json && isTTY { spinner.fail() }
    return handleEditError(error, operation: "Truncate", json: json)
  }
}

// MARK: - Helpers

/// Open a device and downcast to MTPDeviceActor (required for edit extensions).
@MainActor
private func openEditDevice(
  json: Bool, filter: DeviceFilter, strict: Bool, safe: Bool
) async throws -> MTPDeviceActor {
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

  guard let actor = device as? MTPDeviceActor else {
    throw MTPError.notSupported(
      "Edit extensions require MTPDeviceActor (Android MTP extension)")
  }
  return actor
}

@MainActor
private func handleEditError(_ error: Error, operation: String, json: Bool) -> ExitCode {
  if let mtpError = error as? MTPError {
    switch mtpError {
    case .notSupported:
      guard json else {
        fputs(
          "❌ \(operation) not supported. Device may not support Android edit extensions.\n",
          stderr)
        return .unavailable
      }
      printJSONErrorAndExit("\(operation) not supported.", code: .unavailable)
    case .transport(let te) where te == .noDevice:
      guard json else {
        fputs("❌ No MTP device found. Check USB connection and MTP/File Transfer mode.\n", stderr)
        return .unavailable
      }
      printJSONErrorAndExit("No MTP device found.", code: .unavailable)
    default:
      break
    }
  }

  guard json else {
    fputs("❌ \(operation) failed: \(actionableMessage(for: error))\n", stderr)
    return .software
  }
  printJSONErrorAndExit(error.localizedDescription, code: .software)
}
