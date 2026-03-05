// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPConcurrency

// MARK: - Atomic Progress Tracker

/// Thread-safe progress counter for transfer operations
final class AtomicProgressTracker: @unchecked Sendable {
  private let totalBytes = LockedValue<UInt64>(0)

  /// Add bytes to the total and return the new total
  @discardableResult
  func add(_ bytes: Int) -> UInt64 {
    totalBytes.withLock { total in
      total += UInt64(bytes)
      return total
    }
  }

  /// Get the current total bytes
  var total: UInt64 {
    totalBytes.read { $0 }
  }
}

/// Thread-safe container for capturing the remote handle assigned by SendObjectInfo.
/// Used to persist the handle to the journal even when SendObject subsequently fails.
public final class AtomicHandleBox: @unchecked Sendable {
  private let storage = LockedValue<UInt32?>(nil)

  public init() {}

  public func set(_ value: UInt32) {
    storage.withLock { $0 = value }
  }

  public var value: UInt32? {
    storage.read { $0 }
  }
}

// MARK: - Sendable Wrappers

/// Sendable wrapper for ByteSink that serializes access
final class SendableSinkAdapter: @unchecked Sendable {
  private let lockedSink: LockedValue<any ByteSink>

  init(_ sink: any ByteSink) {
    self.lockedSink = LockedValue(sink)
  }

  /// Thread-safe write operation
  public func consume(_ buf: UnsafeRawBufferPointer) -> Int {
    lockedSink.withLock { sink in
      do {
        try sink.write(buf)
        return buf.count
      } catch {
        return 0  // Error occurred, return 0 bytes consumed
      }
    }
  }

  /// Thread-safe close operation
  public func close() throws {
    try lockedSink.withLock { sink in try sink.close() }
  }
}

/// Sendable wrapper for ByteSource that serializes access
final class SendableSourceAdapter: @unchecked Sendable {
  private let lockedSource: LockedValue<any ByteSource>

  init(_ source: any ByteSource) {
    self.lockedSource = LockedValue(source)
  }

  /// Thread-safe read operation
  public func produce(_ buf: UnsafeMutableRawBufferPointer) -> Int {
    lockedSource.withLock { source in
      do {
        return try source.read(into: buf)
      } catch {
        return 0  // Error occurred, return 0 bytes produced
      }
    }
  }

  /// Thread-safe close operation
  public func close() throws {
    try lockedSource.withLock { source in try source.close() }
  }

  /// File size access (thread-safe since it's read-only)
  public var fileSize: UInt64? {
    lockedSource.read { $0.fileSize }
  }
}
