// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - MTP Object Property Codes

/// Commonly used MTP object property codes (MTP spec § 3.7).
public enum MTPObjectPropCode {
  public static let storageID: UInt16 = 0xDC01
  public static let objectFormat: UInt16 = 0xDC02
  public static let objectSize: UInt16 = 0xDC04
  public static let objectFileName: UInt16 = 0xDC07
  public static let dateCreated: UInt16 = 0xDC08
  public static let dateModified: UInt16 = 0xDC09
  public static let keywords: UInt16 = 0xDC0A
  public static let parentObject: UInt16 = 0xDC0B
  public static let persistentUniqueObjectIdentifier: UInt16 = 0xDC41
  public static let name: UInt16 = 0xDC44
  public static let displayName: UInt16 = 0xDC48
}

// MARK: - MTP Date String Helpers

/// Encode/decode MTP date strings (ISO 8601 compact format `YYYYMMDDTHHmmSS`).
public enum MTPDateString {
  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd'T'HHmmss"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }()

  public static func encode(_ date: Date) -> String {
    dateFormatter.string(from: date)
  }

  public static func decode(_ string: String) -> Date? {
    // Strip trailing timezone suffix (e.g. ".0Z", "+0000") before parsing
    let stripped = String(string.prefix(15))
    return dateFormatter.date(from: stripped)
  }
}

// MARK: - PTPLayer

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
  public static func getStorageInfo(id: MTPStorageID, on link: MTPLink) async throws
    -> MTPStorageInfo
  {
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

  // MARK: - MTP Object Property Helpers

  /// Read the `DateModified` (0xDC09) property for an object and parse it.
  ///
  /// Returns `nil` if the property is not supported or the response is empty.
  public static func getObjectModificationDate(
    handle: MTPObjectHandle, on link: MTPLink
  ) async throws -> Date? {
    let data = try await link.getObjectPropValue(
      handle: handle, property: MTPObjectPropCode.dateModified)
    var offset = 0
    guard let s = PTPString.parse(from: data, at: &offset), !s.isEmpty else { return nil }
    return MTPDateString.decode(s)
  }

  /// Write the `DateModified` (0xDC09) property for an object.
  public static func setObjectModificationDate(
    handle: MTPObjectHandle, date: Date, on link: MTPLink
  ) async throws {
    let encoded = PTPString.encode(MTPDateString.encode(date))
    try await link.setObjectPropValue(
      handle: handle, property: MTPObjectPropCode.dateModified, value: encoded)
  }

  /// Read the `ObjectFileName` (0xDC07) property for an object.
  public static func getObjectFileName(
    handle: MTPObjectHandle, on link: MTPLink
  ) async throws -> String? {
    let data = try await link.getObjectPropValue(
      handle: handle, property: MTPObjectPropCode.objectFileName)
    var offset = 0
    return PTPString.parse(from: data, at: &offset)
  }
}
