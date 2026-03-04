// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Persistent per-device tuning data keyed by VID:PID.
///
/// Stored at `~/.swiftmtp/device-tuning.json`.  On device connection the
/// tuning record is loaded and used as the starting chunk size for
/// ``AdaptiveChunkTuner``.  After a session the record is updated.
public struct DeviceTuningRecord: Sendable, Codable, Equatable {
  /// USB Vendor ID (hex, e.g. "2717").
  public var vid: String
  /// USB Product ID (hex, e.g. "ff10").
  public var pid: String
  /// Best chunk size found so far (bytes).
  public var optimalChunkSize: Int
  /// Peak throughput ever observed (bytes/s).
  public var maxObservedThroughput: Double
  /// Cumulative error count across sessions.
  public var errorCount: Int
  /// ISO-8601 timestamp of the last tuning session.
  public var lastTunedDate: String

  public init(
    vid: String,
    pid: String,
    optimalChunkSize: Int,
    maxObservedThroughput: Double,
    errorCount: Int,
    lastTunedDate: String
  ) {
    self.vid = vid
    self.pid = pid
    self.optimalChunkSize = optimalChunkSize
    self.maxObservedThroughput = maxObservedThroughput
    self.errorCount = errorCount
    self.lastTunedDate = lastTunedDate
  }

  /// Composite key used in the JSON dictionary.
  public var key: String { "\(vid):\(pid)" }
}

/// Reads and writes `~/.swiftmtp/device-tuning.json`.
public final class DeviceTuningStore: @unchecked Sendable {
  private let fileURL: URL
  private let queue = DispatchQueue(label: "com.swiftmtp.device-tuning-store")

  /// Creates a store backed by the given file URL.
  /// - Parameter fileURL: Explicit path.  Defaults to `~/.swiftmtp/device-tuning.json`.
  public init(fileURL: URL? = nil) {
    self.fileURL =
      fileURL
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".swiftmtp")
        .appendingPathComponent("device-tuning.json")
  }

  // MARK: - Read

  /// Load all records from disk.
  public func loadAll() -> [String: DeviceTuningRecord] {
    queue.sync { _loadAll() }
  }

  /// Load the record for a specific VID:PID.
  public func load(vid: String, pid: String) -> DeviceTuningRecord? {
    loadAll()["\(vid):\(pid)"]
  }

  // MARK: - Write

  /// Save or update a record for a device.
  public func save(_ record: DeviceTuningRecord) {
    queue.sync {
      var all = _loadAll()
      all[record.key] = record
      _saveAll(all)
    }
  }

  /// Update tuning from an ``AdaptiveChunkTuner/Snapshot``.
  public func update(vid: String, pid: String, from snapshot: AdaptiveChunkTuner.Snapshot) {
    let iso = ISO8601DateFormatter()
    let existing = load(vid: vid, pid: pid)
    let record = DeviceTuningRecord(
      vid: vid,
      pid: pid,
      optimalChunkSize: snapshot.currentChunkSize,
      maxObservedThroughput: max(snapshot.maxObservedThroughput,
                                 existing?.maxObservedThroughput ?? 0),
      errorCount: (existing?.errorCount ?? 0) + snapshot.errorCount,
      lastTunedDate: iso.string(from: Date())
    )
    save(record)
  }

  // MARK: - Private

  private func _loadAll() -> [String: DeviceTuningRecord] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode([String: DeviceTuningRecord].self, from: data)
    } catch {
      return [:]
    }
  }

  private func _saveAll(_ records: [String: DeviceTuningRecord]) {
    do {
      let dir = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Non-fatal: tuning data is advisory.
      if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
        print("Warning: Failed to save device-tuning.json: \(error)")
      }
    }
  }
}
