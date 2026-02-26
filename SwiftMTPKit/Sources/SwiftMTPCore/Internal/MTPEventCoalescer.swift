// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Coalesces burst MTP events within a configurable window.
///
/// When a device generates many events in rapid succession (e.g., a bulk file copy),
/// forwarding every individual event would thrash the cache. This utility returns
/// `true` only for the first event in each window, suppressing the rest.
public final class MTPEventCoalescer: @unchecked Sendable {
  /// A typed MTP device event suitable for push-based change notification.
  public enum Event: Sendable {
    case addObject(deviceId: String, storageId: UInt32, objectHandle: UInt32, parentHandle: UInt32?)
    case deleteObject(deviceId: String, storageId: UInt32, objectHandle: UInt32)
    case storageAdded(deviceId: String, storageId: UInt32)
    case storageRemoved(deviceId: String, storageId: UInt32)
  }

  public let window: TimeInterval
  private var lastEmitTime: Date = .distantPast
  private let lock = NSLock()

  public init(window: TimeInterval = 0.05) {
    self.window = window
  }

  /// Returns `true` if the event should be forwarded (not coalesced).
  ///
  /// Thread-safe; may be called from any context.
  public func shouldForward() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let now = Date()
    if now.timeIntervalSince(lastEmitTime) >= window {
      lastEmitTime = now
      return true
    }
    return false
  }
}
