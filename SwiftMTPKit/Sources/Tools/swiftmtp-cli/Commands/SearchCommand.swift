// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPCLI

/// Searches the FTS5 live index for files by filename or path.
@MainActor
struct SearchCommand {

  static func run(flags: CLIFlags, args: [String]) async {
    var query: String?
    var searchPath = false
    var limit = 50
    var deviceId: String?

    // Parse command-specific args
    var i = 0
    while i < args.count {
      let arg = args[i]
      switch arg {
      case "--path":
        searchPath = true
      case "--limit":
        if i + 1 < args.count, let n = Int(args[i + 1]), n > 0 {
          limit = n
          i += 1
        }
      case "--device":
        if i + 1 < args.count {
          deviceId = args[i + 1]
          i += 1
        }
      case "--help", "-h":
        printSearchHelp()
        exitNow(.ok)
      default:
        if arg.hasPrefix("--limit=") {
          if let n = Int(arg.dropFirst("--limit=".count)), n > 0 { limit = n }
        } else if arg.hasPrefix("--device=") {
          deviceId = String(arg.dropFirst("--device=".count))
        } else if query == nil {
          query = arg
        }
      }
      i += 1
    }

    guard let searchQuery = query, !searchQuery.isEmpty else {
      if flags.json {
        printJSON(["error": "Missing search query"], type: "searchResult")
      } else {
        print("❌ Missing search query.")
        print("   Usage: swiftmtp search <query> [--path] [--device <id>] [--limit <n>]")
        print("   Example: swiftmtp search \"vacation*\"")
      }
      exitNow(.usage)
    }

    do {
      let index = try SQLiteLiveIndex.appGroupIndex(readOnly: true)

      let effectiveDeviceId = deviceId ?? "default"
      let results: [IndexedObject]
      if searchPath {
        results = try await index.searchByPath(
          deviceId: effectiveDeviceId, query: searchQuery, limit: limit)
      } else {
        results = try await index.searchByFilename(
          deviceId: effectiveDeviceId, query: searchQuery, limit: limit)
      }

      if flags.json {
        printSearchJSON(results, query: searchQuery, searchPath: searchPath)
      } else {
        printSearchTable(results, query: searchQuery, searchPath: searchPath)
      }
    } catch {
      if flags.json {
        printJSON(["error": error.localizedDescription], type: "searchResult")
      } else {
        displayError("Search failed", error: error, flags: flags)
      }
      exitNow(.tempfail)
    }
  }

  // MARK: - Text Output

  private static func printSearchTable(
    _ results: [IndexedObject], query: String, searchPath: Bool
  ) {
    let mode = searchPath ? "path" : "filename"
    if results.isEmpty {
      print("🔍 No results for \(mode) search: \"\(query)\"")
      return
    }

    print("🔍 \(results.count) result(s) for \(mode) search: \"\(query)\"")
    print("")

    // Column headers
    let header = String(
      format: "  %-10s  %-30s  %-35s  %10s  %s",
      "HANDLE", "FILENAME", "PATH", "SIZE", "MODIFIED")
    print(header)
    print("  " + String(repeating: "─", count: 95))

    let dateFmt = DateFormatter()
    dateFmt.dateFormat = "yyyy-MM-dd HH:mm"

    for obj in results {
      let handle = String(obj.handle)
      let name = String(obj.name.prefix(30))
      let path = String(obj.pathKey.prefix(35))
      let size: String
      if let s = obj.sizeBytes {
        size = formatBytes(s)
      } else {
        size = "-"
      }
      let modified: String
      if let m = obj.mtime {
        modified = dateFmt.string(from: m)
      } else {
        modified = "-"
      }
      let icon = obj.isDirectory ? "📁" : "📄"
      let line = String(
        format: "  %-10s  %@%-29s  %-35s  %10s  %@",
        handle, icon, name, path, size, modified)
      print(line)
    }
  }

  // MARK: - JSON Output

  private static func printSearchJSON(
    _ results: [IndexedObject], query: String, searchPath: Bool
  ) {
    let items: [[String: Any]] = results.map { obj in
      var item: [String: Any] = [
        "handle": obj.handle,
        "name": obj.name,
        "path": obj.pathKey,
        "formatCode": obj.formatCode,
        "isDirectory": obj.isDirectory,
        "storageId": obj.storageId,
        "deviceId": obj.deviceId,
      ]
      if let s = obj.sizeBytes { item["sizeBytes"] = s }
      if let m = obj.mtime { item["modified"] = ISO8601DateFormatter().string(from: m) }
      return item
    }
    let payload: [String: Any] = [
      "query": query,
      "mode": searchPath ? "path" : "filename",
      "count": results.count,
      "results": items,
    ]
    printJSON(payload, type: "searchResult")
  }

  // MARK: - Help

  static func printSearchHelp() {
    print("swiftmtp search — Full-text search over the device file index")
    print("")
    print("Usage: swiftmtp search <query> [options]")
    print("")
    print("Arguments:")
    print("  <query>            Search term (supports prefix matching with trailing *)")
    print("")
    print("Options:")
    print("  --path             Search by path instead of filename")
    print("  --device <id>      Scope search to a specific device ID")
    print("  --limit <n>        Maximum number of results (default: 50)")
    print("  --json             Output results as JSON")
    print("")
    print("Examples:")
    print("  swiftmtp search photo")
    print("  swiftmtp search \"IMG_20*\" --limit 10")
    print("  swiftmtp search DCIM --path")
    print("  swiftmtp search vacation --json")
  }
}
