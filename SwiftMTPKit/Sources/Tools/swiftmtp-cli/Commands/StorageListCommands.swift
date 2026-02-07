// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

@MainActor
struct StorageListCommands {
    static func runStorages(flags: CLIFlags) async {
        do {
            let device = try await openDevice(flags: flags)
            let storages = try await device.storages()
            
            if flags.json {
                let storageInfos = storages.map { [
                    "id": String($0.id.raw),
                    "description": $0.description,
                    "capacityBytes": $0.capacityBytes,
                    "freeBytes": $0.freeBytes
                ] }
                printJSON(["storages": storageInfos], type: "storagesResult")
            } else {
                print("Found \(storages.count) storage device(s):")
                for s in storages { print("  - \(s.description) (ID: \(s.id.raw))") }
            }
        } catch {
            if flags.json {
                printJSON(["error": error.localizedDescription], type: "storagesResult")
            } else {
                print("❌ Storages failed: \(error)")
            }
            if let mtpError = error as? MTPError, case .notSupported = mtpError {
                exitNow(.unavailable)
            }
            exitNow(.tempfail)
        }
    }

    static func runList(flags: CLIFlags, args: [String]) async {
        guard let handleStr = args.first, let handle = UInt32(handleStr) else { 
            if flags.json {
                printJSON(["error": "Usage: ls <storage_handle>"], type: "listResult")
            } else {
                print("❌ Usage: ls <storage_handle>")
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
                        items.append([
                            "handle": item.handle,
                            "name": item.name,
                            "sizeBytes": item.sizeBytes ?? 0,
                            "formatCode": item.formatCode,
                            "isDirectory": item.formatCode == 0x3001
                        ])
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
                print("❌ List failed: \(error)")
            }
            if let mtpError = error as? MTPError, case .notSupported = mtpError {
                exitNow(.unavailable)
            }
            exitNow(.tempfail)
        }
    }
}
