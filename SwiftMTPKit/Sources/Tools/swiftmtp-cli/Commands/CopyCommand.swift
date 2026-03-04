// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import SwiftMTPCLI

@MainActor
func runCopyCommand(
  args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter,
  strict: Bool, safe: Bool
) async -> ExitCode {
  guard args.count >= 2,
    let handle = UInt32(args.removeFirst(), radix: 0),
    let storageRaw = UInt32(args.removeFirst(), radix: 0)
  else {
    if json { printJSONErrorAndExit("missing_args", code: .usage) }
    fputs("❌ Missing required arguments for copy.\n", stderr)
    fputs("   Usage: swiftmtp cp <handle> <dest-storage> [--parent <handle>]\n", stderr)
    fputs("   Tip: Run 'swiftmtp ls <storage>' to find object handles.\n", stderr)
    return .usage
  }

  var parentHandle: MTPObjectHandle?
  if let idx = args.firstIndex(of: "--parent"), idx + 1 < args.count {
    parentHandle = UInt32(args[idx + 1], radix: 0)
    args.removeSubrange(idx...idx + 1)
  }

  let isTTY = isatty(STDOUT_FILENO) != 0
  var spinner = Spinner("Copying …", enabled: !json && isTTY)
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

    let newHandle = try await device.copyObject(
      handle: handle,
      toStorage: MTPStorageID(raw: storageRaw),
      parentFolder: parentHandle
    )
    if !json && isTTY { spinner.succeed("Copied") }
    if json {
      printJSON(["handle": handle, "newHandle": newHandle], type: "copy")
    } else {
      print("Copied object \(handle) → new handle \(newHandle)")
    }
    return .ok

  } catch {
    if !json && isTTY { spinner.fail() }

    if let mtpError = error as? MTPError {
      switch mtpError {
      case .notSupported:
        guard json else {
          fputs("❌ No MTP device found. Check USB connection and MTP/File Transfer mode.\n", stderr)
          return .unavailable
        }
        printJSONErrorAndExit("No MTP device found.", code: .unavailable)
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
      fputs("❌ Copy failed: \(actionableMessage(for: error))\n", stderr)
      return .software
    }
    printJSONErrorAndExit(error.localizedDescription, code: .software)
  }
}
