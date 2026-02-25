// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

// MARK: - Partial Write Reconciliation

/// Reconcile partial write objects on a device.
///
/// For each resumable write record that has a known `remoteHandle`, this function checks
/// whether the object still exists on the device and is smaller than the expected size
/// (i.e., a partial created by a previous SendObjectInfo that was followed by a failed
/// or interrupted SendObject). Partial objects are deleted to prevent accumulation.
///
/// This is called automatically from `MTPDeviceActor.openIfNeeded()` after the session
/// is established, and can be called directly in tests using any `MTPDevice` conformer.
func reconcilePartialWrites(journal: any TransferJournal, device: any MTPDevice) async {
  guard let records = try? await journal.loadResumables(for: device.id) else { return }
  let writeRecords = records.filter { $0.kind == "write" && $0.remoteHandle != nil }
  for record in writeRecords {
    guard let handle = record.remoteHandle else { continue }
    guard let info = try? await device.getInfo(handle: handle) else {
      // Object not found — nothing to clean up.
      continue
    }
    guard let expected = record.totalBytes, let actual = info.sizeBytes, actual < expected else {
      // Object is complete (size matches or exceeds expected) — leave it alone.
      continue
    }
    Logger(subsystem: "SwiftMTP", category: "reconcile")
      .info(
        "Deleting partial object handle=\(handle) name=\(record.name) actual=\(actual) expected=\(expected)"
      )
    try? await device.delete(handle, recursive: false)
  }
}

// MARK: - MTPDeviceActor Extension

extension MTPDeviceActor {
  /// Reconcile any partial write objects left on the device from interrupted transfers.
  /// Called automatically from `openIfNeeded()` after the session is established.
  func reconcilePartials() async {
    guard let journal = transferJournal else { return }
    await reconcilePartialWrites(journal: journal, device: self)
  }
}
