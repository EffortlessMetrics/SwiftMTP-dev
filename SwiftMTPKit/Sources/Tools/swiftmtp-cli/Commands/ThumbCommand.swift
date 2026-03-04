// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPCLI

@MainActor
struct ThumbCommand {
  static func run(flags: CLIFlags, args: [String]) async {
    guard let handleStr = args.first, let handle = UInt32(handleStr) else {
      print("❌ Missing required argument: <handle>")
      print("   Usage: swiftmtp thumb <handle> [--output <path>]")
      print("   Example: swiftmtp thumb 42 --output thumb.jpg")
      print("   Tip: Run 'swiftmtp ls <storage>' to find object handles.")
      exitNow(.usage)
    }

    var outputPath: String? = nil
    if let idx = args.firstIndex(of: "--output"), idx + 1 < args.count {
      outputPath = args[idx + 1]
    } else if let idx = args.firstIndex(of: "-o"), idx + 1 < args.count {
      outputPath = args[idx + 1]
    }

    do {
      let device = try await openDevice(flags: flags)
      let data = try await device.getThumbnail(handle: handle)

      if let outputPath {
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url)
        print("✅ Thumbnail saved to \(outputPath) (\(formatBytes(UInt64(data.count))))")
      } else {
        // Display thumbnail info
        let info = try await device.getInfo(handle: handle)
        print("📷 Thumbnail for \(info.name) (handle \(handle))")
        print("   Size: \(formatBytes(UInt64(data.count)))")
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
          print("   Format: JPEG")
        } else if data.count >= 8, data[0] == 0x89, data[1] == 0x50 {
          print("   Format: PNG")
        } else {
          print("   Format: Unknown")
        }
      }
    } catch {
      log("❌ Failed to get thumbnail: \(actionableMessage(for: error))")
      if let mtpError = error as? MTPError, case .transport(let te) = mtpError, case .noDevice = te
      {
        exitNow(.unavailable)
      }
      exitNow(.tempfail)
    }
  }
}
