// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Renders transfer progress to the terminal.
public struct ProgressRenderer: Sendable {

  // MARK: - Progress bar

  /// Render a progress bar: `[████████░░░░] 45%  2.3 MB/s  ETA 0:32`
  public static func renderProgressBar(
    completed: UInt64,
    total: UInt64,
    bytesPerSecond: Double,
    eta: TimeInterval?,
    barWidth: Int = 20
  ) -> String {
    let fraction: Double
    if total > 0 {
      fraction = min(Double(completed) / Double(total), 1.0)
    } else {
      fraction = 0
    }
    let filledCount = Int(fraction * Double(barWidth))
    let emptyCount = barWidth - filledCount
    let filled = String(repeating: "█", count: filledCount)
    let empty = String(repeating: "░", count: emptyCount)
    let pct = Int(fraction * 100)

    var line = "[\(filled)\(empty)] \(pct)%  \(formatBytes(UInt64(bytesPerSecond)))/s"
    if let eta {
      line += "  ETA \(formatDuration(eta))"
    }
    return line
  }

  // MARK: - File counter

  /// Render file counter: `[3/17] photo_001.jpg`
  public static func renderFileProgress(
    current: Int,
    total: Int,
    filename: String
  ) -> String {
    "[\(current)/\(total)] \(filename)"
  }

  // MARK: - Byte formatting

  /// Format bytes into human-readable form: `1.2 MB`, `456 KB`, etc.
  public static func formatBytes(_ bytes: UInt64) -> String {
    let gb: UInt64 = 1_000_000_000
    let mb: UInt64 = 1_000_000
    let kb: UInt64 = 1_000

    if bytes >= gb {
      return String(format: "%.1f GB", Double(bytes) / Double(gb))
    } else if bytes >= mb {
      return String(format: "%.1f MB", Double(bytes) / Double(mb))
    } else if bytes >= kb {
      return String(format: "%.1f KB", Double(bytes) / Double(kb))
    } else {
      return "\(bytes) B"
    }
  }

  // MARK: - Duration formatting

  /// Format seconds into `m:ss` or `h:mm:ss`.
  public static func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds.rounded(.up))
    guard totalSeconds >= 0 else { return "0:00" }

    let h = totalSeconds / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60

    if h > 0 {
      return String(format: "%d:%02d:%02d", h, m, s)
    } else {
      return String(format: "%d:%02d", m, s)
    }
  }
}
