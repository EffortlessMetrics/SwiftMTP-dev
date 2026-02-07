// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Pure PTP-standard operations that work on any PTP device (cameras, DAPs)
/// without requiring an MTP session. These can be called pre-session.
public enum PTPLayer {

  /// Send GetDeviceInfo (0x1001) — sessionless, works on any PTP device.
  public static func getDeviceInfo(on link: MTPLink) async throws -> MTPDeviceInfo {
    try await link.getDeviceInfo()
  }

  /// Open a PTP session with the given ID.
  public static func openSession(id: UInt32, on link: MTPLink) async throws {
    try await link.openSession(id: id)
  }

  /// Close the current PTP session.
  public static func closeSession(on link: MTPLink) async throws {
    try await link.closeSession()
  }

  /// Get list of storage IDs.
  public static func getStorageIDs(on link: MTPLink) async throws -> [MTPStorageID] {
    try await link.getStorageIDs()
  }

  /// Get storage info for a specific storage.
  public static func getStorageInfo(id: MTPStorageID, on link: MTPLink) async throws -> MTPStorageInfo {
    try await link.getStorageInfo(id: id)
  }

  /// Get object handles in a storage/parent.
  public static func getObjectHandles(
    storage: MTPStorageID, parent: MTPObjectHandle?,
    on link: MTPLink
  ) async throws -> [MTPObjectHandle] {
    try await link.getObjectHandles(storage: storage, parent: parent)
  }

  /// Check if a link's device supports a specific PTP/MTP operation code.
  public static func supportsOperation(_ opcode: UInt16, deviceInfo: MTPDeviceInfo) -> Bool {
    deviceInfo.operationsSupported.contains(opcode)
  }
}
