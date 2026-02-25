// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@preconcurrency import FileProvider
import SwiftMTPCore

/// Bridges index change notifications to File Provider's `signalEnumerator` API.
///
/// When the crawler updates the live index, it reports which parent directories changed.
/// This class converts those parent handles to `NSFileProviderItemIdentifier` values
/// and calls `NSFileProviderManager.signalEnumerator(for:)` to tell Finder to re-enumerate.
@available(macOS 11.0, *)
public final class ChangeSignaler: Sendable {
  private let domainIdentifier: NSFileProviderDomainIdentifier

  public init(domainIdentifier: NSFileProviderDomainIdentifier) {
    self.domainIdentifier = domainIdentifier
  }

  /// Signal that specific parent directories have changed.
  /// - Parameters:
  ///   - deviceId: The device whose content changed.
  ///   - storageId: The storage containing the changed directories.
  ///   - parentHandles: Set of parent handles that changed. `nil` means the storage root.
  public func signalParents(
    deviceId: String, storageId: UInt32, parentHandles: Set<MTPObjectHandle?>
  ) {
    let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "")
    guard let manager = NSFileProviderManager(for: domain) else { return }

    for parentHandle in parentHandles {
      let identifier: NSFileProviderItemIdentifier
      if let ph = parentHandle {
        identifier = NSFileProviderItemIdentifier("\(deviceId):\(storageId):\(ph)")
      } else {
        // Storage root
        identifier = NSFileProviderItemIdentifier("\(deviceId):\(storageId)")
      }
      manager.signalEnumerator(for: identifier) { error in
        if let error = error {
          // Log but don't propagate — signaling is best-effort
          _ = error
        }
      }
    }
  }

  /// Signal the working set (used on device attach/reconnect).
  public func signalWorkingSet() {
    let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "")
    guard let manager = NSFileProviderManager(for: domain) else { return }
    manager.signalEnumerator(for: .workingSet) { _ in }
  }
}
