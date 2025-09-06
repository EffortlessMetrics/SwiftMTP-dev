// DeleteMoveEventsCommands.swift
import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB

// Placeholder - this should be implemented to use DeviceFilter selection
func openFilteredDevice(filter: DeviceFilter, noninteractive: Bool, json: Bool) async throws -> any MTPDevice {
  // Implementation needed - use MTPDeviceManager.shared to discover devices
  // and select using DeviceFilter logic
  fatalError("openFilteredDevice not implemented")
}

// DELETE
func runDeleteCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter) async -> ExitCode {
  guard args.count >= 1, let handle = UInt32(args.removeFirst(), radix: 0) else {
    if json { printJSONErrorAndExit("missing_handle", code: .usage) }
    fputs("usage: swiftmtp delete <handle> [--recursive]\n", stderr); return .usage
  }
  let recursive = args.contains("--recursive")
  let spinner = Spinner("Deleting …", enabled: !json); spinner.start()
  do {
    let device = try await openFilteredDevice(filter: filter, noninteractive: noninteractive, json: json)
    try await device.delete(handle, recursive: recursive)
    spinner.succeed("Deleted")
    return .ok
  } catch {
    spinner.fail("Delete failed")
    if json { printJSONErrorAndExit("delete_failed") }
    fputs("❌ delete failed: \(error)\n", stderr)
    return .software
  }
}

// MOVE
func runMoveCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter) async -> ExitCode {
  guard args.count >= 2,
        let handle = UInt32(args.removeFirst(), radix: 0),
        let parent = UInt32(args.removeFirst(), radix: 0) else {
    if json { printJSONErrorAndExit("missing_args", code: .usage) }
    fputs("usage: swiftmtp move <handle> <new-parent-handle>\n", stderr); return .usage
  }
  let spinner = Spinner("Moving …", enabled: !json); spinner.start()
  do {
    let device = try await openFilteredDevice(filter: filter, noninteractive: noninteractive, json: json)
    try await device.move(handle, to: parent)
    spinner.succeed("Moved")
    return .ok
  } catch {
    spinner.fail("Move failed")
    if json { printJSONErrorAndExit("move_failed") }
    fputs("❌ move failed: \(error)\n", stderr)
    return .software
  }
}

// EVENTS (prints lines or JSONL)
func runEventsCommand(args: inout [String], json: Bool, noninteractive: Bool, filter: DeviceFilter) async -> ExitCode {
  let seconds = (args.first.flatMap { Int($0) }) ?? 30
  var spinner = Spinner("Subscribing to events …", enabled: !json); spinner.start()
  do {
    let device = try await openFilteredDevice(filter: filter, noninteractive: noninteractive, json: json)
    spinner.succeed("Listening …")
    let stream = device.events
    let deadline = Date().addingTimeInterval(TimeInterval(seconds))
    for await ev in stream {
      if json {
        struct J: Codable { let schemaVersion = "1.0"; let type = "event"; let t = ISO8601DateFormatter().string(from: Date()); let event: String }
        printJSON(J(event: "\(ev)"))
      } else {
        print("• \(ev)")
      }
      if Date() >= deadline { break }
    }
    return .ok
  } catch {
    spinner.stopAndClear("")
    if json { printJSONErrorAndExit("events_failed", code: .software, details: ["error":"\(error)"]) }
    fputs("❌ events failed: \(error)\n", stderr)
    return .software
  }
}
