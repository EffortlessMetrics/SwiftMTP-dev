// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider

/// In-memory store for File Provider sync anchors and pending change queues.
///
/// Maps a `deviceId+storageId` composite key to an epoch-based 8-byte anchor and
/// queues of pending added/deleted item identifiers.  Changes are fed by MTP device
/// events (via `MTPFileProviderExtension.handleDeviceEvent`) and consumed by
/// `DomainEnumerator.enumerateChanges(for:from:)`.
///
/// Thread-safe via an internal `NSLock`.
public final class SyncAnchorStore: @unchecked Sendable {
  /// Maximum items returned in a single `consumeChanges` call.
  public static let maxBatchSize = 200

  private struct Slot {
    var anchor: Data
    var pendingAdded: [NSFileProviderItemIdentifier]
    var pendingDeleted: [NSFileProviderItemIdentifier]
  }

  private var slots: [String: Slot] = [:]
  private let lock = NSLock()

  public init() {}

  // MARK: - Public API

  /// Returns the current epoch-based 8-byte anchor for the given key.
  /// If no anchor has been recorded yet a fresh timestamp is returned.
  public func currentAnchor(for key: String) -> Data {
    lock.lock()
    defer { lock.unlock() }
    return slots[key]?.anchor ?? makeTimestampAnchor()
  }

  /// Queues `added` and `deleted` identifiers for `key` and bumps the anchor.
  public func recordChange(
    added: [NSFileProviderItemIdentifier],
    deleted: [NSFileProviderItemIdentifier],
    for key: String
  ) {
    lock.lock()
    defer { lock.unlock() }
    var slot =
      slots[key]
      ?? Slot(anchor: makeTimestampAnchor(), pendingAdded: [], pendingDeleted: [])
    slot.anchor = makeTimestampAnchor()
    slot.pendingAdded.append(contentsOf: added)
    slot.pendingDeleted.append(contentsOf: deleted)
    slots[key] = slot
  }

  /// Dequeues up to `maxBatchSize` pending items regardless of the given anchor.
  /// Returns `hasMore: true` when the queue still contains items after this batch.
  public func consumeChanges(
    from anchor: Data,
    for key: String
  ) -> (
    added: [NSFileProviderItemIdentifier], deleted: [NSFileProviderItemIdentifier], hasMore: Bool
  ) {
    lock.lock()
    defer { lock.unlock() }
    guard var slot = slots[key] else { return ([], [], false) }

    let batchAdded = Array(slot.pendingAdded.prefix(Self.maxBatchSize))
    slot.pendingAdded = Array(slot.pendingAdded.dropFirst(batchAdded.count))

    let remaining = Self.maxBatchSize - batchAdded.count
    let batchDeleted = Array(slot.pendingDeleted.prefix(remaining))
    slot.pendingDeleted = Array(slot.pendingDeleted.dropFirst(batchDeleted.count))

    let hasMore = !slot.pendingAdded.isEmpty || !slot.pendingDeleted.isEmpty
    slots[key] = slot
    return (batchAdded, batchDeleted, hasMore)
  }

  // MARK: - Private

  private func makeTimestampAnchor() -> Data {
    var ts = Int64(Date().timeIntervalSince1970 * 1_000)
    return Data(bytes: &ts, count: 8)
  }
}
