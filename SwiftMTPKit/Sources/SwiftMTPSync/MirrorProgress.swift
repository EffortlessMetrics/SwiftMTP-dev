// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Tracks file-level and byte-level progress during mirror/sync operations.
public actor MirrorProgress {

  /// A snapshot of the current mirror progress state.
  public struct Snapshot: Sendable {
    public let totalFiles: Int
    public let filesCompleted: Int
    public let filesSkipped: Int
    public let filesFailed: Int
    public let currentFileName: String?
    public let totalBytes: UInt64
    public let bytesTransferred: UInt64
    public let bytesPerSecond: Double
    public let estimatedTimeRemaining: TimeInterval?

    /// Fraction of files complete in 0…1.
    public var fileFraction: Double {
      guard totalFiles > 0 else { return 0 }
      return Double(filesCompleted + filesSkipped + filesFailed) / Double(totalFiles)
    }

    /// Fraction of bytes complete in 0…1.
    public var byteFraction: Double {
      guard totalBytes > 0 else { return 0 }
      return Double(bytesTransferred) / Double(totalBytes)
    }
  }

  private var totalFiles: Int = 0
  private var filesCompleted: Int = 0
  private var filesSkipped: Int = 0
  private var filesFailed: Int = 0
  private var currentFileName: String?
  private var totalBytes: UInt64 = 0
  private var bytesTransferred: UInt64 = 0
  private var startTime: Date?
  private var handler: (@Sendable (Snapshot) -> Void)?

  public init() {}

  /// Register a handler that receives progress snapshots.
  public func onUpdate(_ handler: @Sendable @escaping (Snapshot) -> Void) {
    self.handler = handler
  }

  /// Set the total work to be done before the mirror loop begins.
  public func setTotal(files: Int, bytes: UInt64) {
    totalFiles = files
    totalBytes = bytes
    startTime = Date()
    emit()
  }

  /// Signal that a file download is starting.
  public func beginFile(name: String, size: UInt64) {
    currentFileName = name
    emit()
  }

  /// Signal that a file download completed successfully.
  public func completeFile(size: UInt64) {
    filesCompleted += 1
    bytesTransferred += size
    currentFileName = nil
    emit()
  }

  /// Signal that a file was skipped (filter or already up-to-date).
  public func skipFile() {
    filesSkipped += 1
    currentFileName = nil
    emit()
  }

  /// Signal that a file download failed.
  public func failFile() {
    filesFailed += 1
    currentFileName = nil
    emit()
  }

  /// Return the current progress snapshot.
  public func snapshot() -> Snapshot {
    makeSnapshot()
  }

  // MARK: - Private

  private func makeSnapshot() -> Snapshot {
    let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
    let bps = elapsed > 0 ? Double(bytesTransferred) / elapsed : 0
    let remaining: TimeInterval?
    if bps > 0, totalBytes > bytesTransferred {
      remaining = Double(totalBytes - bytesTransferred) / bps
    } else {
      remaining = nil
    }
    return Snapshot(
      totalFiles: totalFiles,
      filesCompleted: filesCompleted,
      filesSkipped: filesSkipped,
      filesFailed: filesFailed,
      currentFileName: currentFileName,
      totalBytes: totalBytes,
      bytesTransferred: bytesTransferred,
      bytesPerSecond: bps,
      estimatedTimeRemaining: remaining
    )
  }

  private func emit() {
    handler?(makeSnapshot())
  }
}
