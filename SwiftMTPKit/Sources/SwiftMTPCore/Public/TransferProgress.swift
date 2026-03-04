// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Reports transfer progress for CLI and UI consumers.
public actor TransferProgressReporter {

  /// A single progress update emitted during a transfer.
  public struct Update: Sendable {
    public let filename: String
    public let bytesTransferred: UInt64
    public let totalBytes: UInt64
    public let filesCompleted: Int
    public let totalFiles: Int
    public let bytesPerSecond: Double
    public let estimatedTimeRemaining: TimeInterval?

    public init(
      filename: String,
      bytesTransferred: UInt64,
      totalBytes: UInt64,
      filesCompleted: Int,
      totalFiles: Int,
      bytesPerSecond: Double,
      estimatedTimeRemaining: TimeInterval?
    ) {
      self.filename = filename
      self.bytesTransferred = bytesTransferred
      self.totalBytes = totalBytes
      self.filesCompleted = filesCompleted
      self.totalFiles = totalFiles
      self.bytesPerSecond = bytesPerSecond
      self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    /// Fraction complete in 0…1.
    public var fractionComplete: Double {
      guard totalBytes > 0 else { return 0 }
      return Double(bytesTransferred) / Double(totalBytes)
    }
  }

  private var handler: (@Sendable (Update) -> Void)?

  public init() {}

  /// Register a handler that receives every progress update.
  public func onUpdate(_ handler: @Sendable @escaping (Update) -> Void) {
    self.handler = handler
  }

  /// Emit a progress update to the registered handler.
  public func report(_ update: Update) {
    handler?(update)
  }
}
