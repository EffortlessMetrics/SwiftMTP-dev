// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI

/// Displays rich metadata for a single MTP object by handle.
@MainActor
struct InfoCommand {

  /// Run `swiftmtp info <handle>` — fetch and display all available properties.
  static func runObjectInfo(flags: CLIFlags, args: [String]) async {
    guard let handleStr = args.first, let handle = UInt32(handleStr) else {
      if flags.json {
        printJSON(["error": "Usage: swiftmtp info <object_handle>"], type: "objectInfoResult")
      } else {
        print("❌ Missing or invalid object handle.")
        print("   Usage: swiftmtp info <object_handle>")
        print("   Tip: Run 'swiftmtp ls <storage>' to find object handles.")
      }
      exitNow(.usage)
    }

    do {
      let device = try await openDevice(flags: flags)
      let obj = try await device.getInfo(handle: handle)

      if flags.json {
        printObjectInfoJSON(obj)
      } else {
        printObjectInfoText(obj)
      }
    } catch {
      if flags.json {
        printJSON(["error": error.localizedDescription], type: "objectInfoResult")
      } else {
        print("❌ Failed to get object info: \(actionableMessage(for: error))")
      }
      if let mtpError = error as? MTPError {
        switch mtpError {
        case .objectNotFound:
          exitNow(.usage)
        case .transport(let te):
          if case .noDevice = te { exitNow(.unavailable) }
        default:
          break
        }
      }
      exitNow(.tempfail)
    }
  }

  // MARK: - Text Output

  static func printObjectInfoText(_ obj: MTPObjectInfo) {
    let isDir = obj.formatCode == 0x3001
    let icon = isDir ? "📁" : "📄"

    print("\(icon) Object: \(obj.name) (handle: \(obj.handle))")
    print("  Format:    \(PTPObjectFormat.describe(obj.formatCode))")

    if let size = obj.sizeBytes {
      let numberFormatter = NumberFormatter()
      numberFormatter.numberStyle = .decimal
      let formatted = numberFormatter.string(from: NSNumber(value: size)) ?? "\(size)"
      print("  Size:      \(formatted) bytes (\(formatBytes(size)))")
    } else {
      print("  Size:      (unknown)")
    }

    if let modified = obj.modified {
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
      print("  Modified:  \(fmt.string(from: modified))")
    }

    print("  Storage:   0x\(String(format: "%08x", obj.storage.raw))")
    if let parent = obj.parent {
      print("  Parent:    handle \(parent)")
    } else {
      print("  Parent:    (root)")
    }

    // Group extended properties by category
    let coreProps: Set<UInt16> = [
      MTPObjectPropCode.storageID, MTPObjectPropCode.objectFormat,
      MTPObjectPropCode.objectSize, MTPObjectPropCode.objectFileName,
      MTPObjectPropCode.parentObject,
    ]

    let dateProps: Set<UInt16> = [
      MTPObjectPropCode.dateCreated, MTPObjectPropCode.dateModified,
      MTPObjectPropCode.dateAuthored, MTPObjectPropCode.dateAdded,
    ]

    let audioProps: Set<UInt16> = [
      MTPObjectPropCode.artist, MTPObjectPropCode.albumName,
      MTPObjectPropCode.albumArtist, MTPObjectPropCode.genre,
      MTPObjectPropCode.track, MTPObjectPropCode.duration,
      MTPObjectPropCode.rating, MTPObjectPropCode.sampleRate,
      MTPObjectPropCode.numberOfChannels, MTPObjectPropCode.audioBitRate,
      MTPObjectPropCode.audioBitDepth, MTPObjectPropCode.audioWAVECodec,
      MTPObjectPropCode.audioDuration, MTPObjectPropCode.audioBlockAlignment,
    ]

    let imageVideoProps: Set<UInt16> = [
      MTPObjectPropCode.width, MTPObjectPropCode.height,
      MTPObjectPropCode.dpi, MTPObjectPropCode.fourCCCodec,
      MTPObjectPropCode.videoBitRate,
    ]

    let extended = obj.properties.filter { !coreProps.contains($0.key) }

    if !extended.isEmpty {
      // Print date properties
      let dates = extended.filter { dateProps.contains($0.key) }
      if !dates.isEmpty {
        print("  --- Dates ---")
        for (code, value) in dates.sorted(by: { $0.key < $1.key }) {
          let label = MTPObjectPropCode.displayName(for: code)
          let padded = label + String(repeating: " ", count: max(0, 16 - label.count))
          print("  \(padded) \(value)")
        }
      }

      // Print audio metadata
      let audio = extended.filter { audioProps.contains($0.key) }
      if !audio.isEmpty {
        print("  --- Audio Metadata ---")
        for (code, value) in audio.sorted(by: { $0.key < $1.key }) {
          let label = MTPObjectPropCode.displayName(for: code)
          let padded = label + String(repeating: " ", count: max(0, 16 - label.count))
          print("  \(padded) \(value.isEmpty ? "(not available)" : value)")
        }
      }

      // Print image/video properties
      let imageVideo = extended.filter { imageVideoProps.contains($0.key) }
      if !imageVideo.isEmpty {
        print("  --- Image/Video ---")
        for (code, value) in imageVideo.sorted(by: { $0.key < $1.key }) {
          let label = MTPObjectPropCode.displayName(for: code)
          let padded = label + String(repeating: " ", count: max(0, 16 - label.count))
          print("  \(padded) \(value.isEmpty ? "(not available)" : value)")
        }
      }

      // Print remaining properties
      let shown = coreProps.union(dateProps).union(audioProps).union(imageVideoProps)
      let other = extended.filter { !shown.contains($0.key) }
      if !other.isEmpty {
        print("  --- Other Properties ---")
        for (code, value) in other.sorted(by: { $0.key < $1.key }) {
          let label = MTPObjectPropCode.displayName(for: code)
          let padded = label + String(repeating: " ", count: max(0, 16 - label.count))
          print("  \(padded) \(value.isEmpty ? "(not available)" : value)")
        }
      }
    }
  }

  // MARK: - JSON Output

  static func printObjectInfoJSON(_ obj: MTPObjectInfo) {
    var info: [String: Any] = [
      "handle": obj.handle,
      "name": obj.name,
      "formatCode": obj.formatCode,
      "formatDescription": PTPObjectFormat.describe(obj.formatCode),
      "isDirectory": obj.formatCode == 0x3001,
      "storageId": obj.storage.raw,
    ]
    if let size = obj.sizeBytes {
      info["sizeBytes"] = size
      info["sizeFormatted"] = formatBytes(size)
    }
    if let modified = obj.modified {
      info["modified"] = ISO8601DateFormatter().string(from: modified)
    }
    if let parent = obj.parent {
      info["parentHandle"] = parent
    }
    if !obj.properties.isEmpty {
      var props: [[String: Any]] = []
      for (code, value) in obj.properties.sorted(by: { $0.key < $1.key }) {
        props.append([
          "code": String(format: "0x%04X", code),
          "name": MTPObjectPropCode.displayName(for: code),
          "value": value,
        ])
      }
      info["properties"] = props
    }
    printJSON(info, type: "objectInfoResult")
  }

  // MARK: - Detail Line (for ls --detail)

  /// Format a single-line detail summary for use in `ls --detail` output.
  static func formatDetailLine(_ obj: MTPObjectInfo) -> String {
    let isDir = obj.formatCode == 0x3001
    let icon = isDir ? "📁" : "📄"
    let format = PTPObjectFormat.describe(obj.formatCode)
    let size: String
    if let s = obj.sizeBytes {
      size = formatBytes(s)
    } else {
      size = "-"
    }
    let modified: String
    if let m = obj.modified {
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyy-MM-dd HH:mm"
      modified = fmt.string(from: m)
    } else {
      modified = "-"
    }
    return "\(icon) \(obj.name) (handle: \(obj.handle))  \(format)  \(size)  \(modified)"
  }
}
