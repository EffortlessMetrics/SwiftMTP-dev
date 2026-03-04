// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI

@MainActor
struct StorageListCommands {
  static func runStorages(flags: CLIFlags) async {
    do {
      let device = try await openDevice(flags: flags)
      let storages = try await device.storages()

      if flags.json {
        let storageInfos = storages.map {
          [
            "id": String($0.id.raw),
            "description": $0.description,
            "capacityBytes": $0.capacityBytes,
            "freeBytes": $0.freeBytes,
          ]
        }
        printJSON(["storages": storageInfos], type: "storagesResult")
      } else {
        print("Found \(storages.count) storage device(s):")
        for s in storages { print("  - \(s.description) (ID: \(s.id.raw))") }
      }
    } catch {
      if flags.json {
        printJSON(["error": error.localizedDescription], type: "storagesResult")
      } else {
        print("❌ Failed to list storages: \(actionableMessage(for: error))")
      }
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .notSupported:
          exitNow(.unavailable)
        case .transport(let te):
          if case .noDevice = te { exitNow(.unavailable) }
        default:
          break
        }
      }
      exitNow(.tempfail)
    }
  }

  static func runList(flags: CLIFlags, args: [String], detail: Bool = false) async {
    let filteredArgs = args.filter { $0 != "--detail" }
    guard let handleStr = filteredArgs.first, let handle = UInt32(handleStr) else {
      if flags.json {
        printJSON(["error": "Usage: ls <storage_handle>"], type: "listResult")
      } else {
        print("❌ Missing or invalid storage handle.")
        print("   Usage: swiftmtp ls <storage_handle> [--detail]")
        print("   Tip: Run 'swiftmtp storages' to find available storage IDs.")
      }
      exitNow(.usage)
    }
    do {
      let device = try await openDevice(flags: flags)
      let stream = device.list(parent: nil as MTPObjectHandle?, in: MTPStorageID(raw: handle))

      var items: [[String: Any]] = []
      for try await batch in stream {
        for item in batch {
          if flags.json {
            var entry: [String: Any] = [
              "handle": item.handle,
              "name": item.name,
              "sizeBytes": item.sizeBytes ?? 0,
              "formatCode": item.formatCode,
              "formatDescription": PTPObjectFormat.describe(item.formatCode),
              "isDirectory": item.formatCode == 0x3001,
            ]
            if detail {
              if let modified = item.modified {
                entry["modified"] = ISO8601DateFormatter().string(from: modified)
              }
              entry["storageId"] = item.storage.raw
              if let parent = item.parent {
                entry["parentHandle"] = parent
              }
              if !item.properties.isEmpty {
                var props: [[String: Any]] = []
                for (code, value) in item.properties.sorted(by: { $0.key < $1.key }) {
                  props.append([
                    "code": String(format: "0x%04X", code),
                    "name": MTPObjectPropCode.displayName(for: code),
                    "value": value,
                  ])
                }
                entry["properties"] = props
              }
            }
            items.append(entry)
          } else if detail {
            print(InfoCommand.formatDetailLine(item))
          } else {
            let type = item.formatCode == 0x3001 ? "📁" : "📄"
            print("\(type) \(item.name) (handle: \(item.handle))")
          }
        }
      }
      if flags.json {
        printJSON(["items": items], type: "listResult")
      }
    } catch {
      if flags.json {
        printJSON(["error": error.localizedDescription], type: "listResult")
      } else {
        print("❌ Failed to list objects: \(actionableMessage(for: error))")
      }
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .notSupported:
          exitNow(.unavailable)
        case .transport(let te):
          if case .noDevice = te { exitNow(.unavailable) }
        default:
          break
        }
      }
      exitNow(.tempfail)
    }
  }
}
