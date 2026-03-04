// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Strategy for resolving conflicts when a file has been modified on both
/// the device and the local side since the last sync.
public enum ConflictResolutionStrategy: String, Sendable, CaseIterable {
  /// Compare modification dates; keep the newer version.
  case newerWins = "newer-wins"
  /// Always prefer the local copy.
  case localWins = "local-wins"
  /// Always prefer the device copy.
  case deviceWins = "device-wins"
  /// Keep both versions, renaming the losing side with a "-device" or "-local" suffix.
  case keepBoth = "keep-both"
  /// Skip conflicting files and log them without transferring.
  case skip = "skip"
  /// Emit a conflict event for the UI to present a choice (async callback).
  case ask = "ask"
}

/// Describes a detected conflict between local and device versions of a file.
public struct MTPConflictInfo: Sendable {
  /// Path key identifying the object on the device.
  public let pathKey: String
  /// MTP object handle on the device.
  public let handle: UInt32
  /// Size of the device-side version (bytes).
  public let deviceSize: UInt64?
  /// Modification time of the device-side version.
  public let deviceMtime: Date?
  /// Size of the local version (bytes).
  public let localSize: UInt64?
  /// Modification time of the local version.
  public let localMtime: Date?

  public init(
    pathKey: String, handle: UInt32,
    deviceSize: UInt64?, deviceMtime: Date?,
    localSize: UInt64?, localMtime: Date?
  ) {
    self.pathKey = pathKey
    self.handle = handle
    self.deviceSize = deviceSize
    self.deviceMtime = deviceMtime
    self.localSize = localSize
    self.localMtime = localMtime
  }
}

/// Outcome of a single conflict resolution.
public enum ConflictOutcome: String, Sendable {
  case keptLocal = "kept-local"
  case keptDevice = "kept-device"
  case keptBoth = "kept-both"
  case skipped = "skipped"
  case pending = "pending"
}

/// Record of how a conflict was resolved, suitable for journal logging.
public struct ConflictResolutionRecord: Sendable {
  public let pathKey: String
  public let strategy: ConflictResolutionStrategy
  public let outcome: ConflictOutcome
  public let timestamp: Date

  public init(
    pathKey: String, strategy: ConflictResolutionStrategy,
    outcome: ConflictOutcome, timestamp: Date = Date()
  ) {
    self.pathKey = pathKey
    self.strategy = strategy
    self.outcome = outcome
    self.timestamp = timestamp
  }
}

/// Callback type for the `.ask` strategy. The UI supplies a resolution for each conflict.
public typealias ConflictResolver = @Sendable (MTPConflictInfo) async -> ConflictOutcome
