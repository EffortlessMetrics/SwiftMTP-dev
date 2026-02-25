// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Stable identity for an MTP device that persists across reconnections.
///
/// The `domainId` (UUID) serves as the File Provider domain identifier and
/// the `deviceId` key in the live index, replacing the ephemeral bus:addr ID.
public struct StableDeviceIdentity: Sendable, Codable, Equatable {
  /// Stable UUID used as the File Provider domain identifier and live index deviceId.
  public let domainId: String
  /// Human-readable display name (e.g. "Samsung Galaxy S21").
  public let displayName: String
  /// When this identity was first created.
  public let createdAt: Date
  /// When this device was last seen.
  public let lastSeenAt: Date

  public init(domainId: String, displayName: String, createdAt: Date, lastSeenAt: Date) {
    self.domainId = domainId
    self.displayName = displayName
    self.createdAt = createdAt
    self.lastSeenAt = lastSeenAt
  }
}

/// Signals collected from a device at attach time, used to resolve its stable identity.
public struct DeviceIdentitySignals: Sendable {
  public let vendorId: UInt16?
  public let productId: UInt16?
  /// USB iSerialNumber descriptor (most reliable signal).
  public let usbSerial: String?
  /// MTP serial from GetDeviceInfo (available after opening the device).
  public let mtpSerial: String?
  public let manufacturer: String?
  public let model: String?

  public init(
    vendorId: UInt16?, productId: UInt16?, usbSerial: String?, mtpSerial: String?,
    manufacturer: String?, model: String?
  ) {
    self.vendorId = vendorId
    self.productId = productId
    self.usbSerial = usbSerial
    self.mtpSerial = mtpSerial
    self.manufacturer = manufacturer
    self.model = model
  }

  /// Derive a stable identity key using the best available signal.
  ///
  /// Priority ladder:
  /// 1. USB serial (unique per physical device)
  /// 2. MTP serial (unique per device, but only available after opening)
  /// 3. Type hash (VID:PID:manufacturer:model — collides for identical models)
  public func identityKey() -> String {
    if let serial = usbSerial, !serial.isEmpty {
      return "usb:\(serial)"
    }
    if let serial = mtpSerial, !serial.isEmpty {
      return "mtp:\(serial)"
    }
    let vid = vendorId.map { String(format: "%04x", $0) } ?? "0000"
    let pid = productId.map { String(format: "%04x", $0) } ?? "0000"
    let mfr = manufacturer ?? "unknown"
    let mdl = model ?? "unknown"
    return "type:\(vid):\(pid):\(mfr):\(mdl)"
  }

  /// Build a display name from available signals.
  public func displayName() -> String {
    let mfr = manufacturer ?? "Unknown"
    let mdl = model ?? "Device"
    return "\(mfr) \(mdl)"
  }
}

/// Persistent store for device identity mappings.
///
/// Implementations store the mapping from identity keys to stable domain IDs,
/// allowing the same physical device to be recognized across reconnections.
public protocol DeviceIdentityStore: Sendable {
  /// Resolve (or create) a stable identity for the given signals.
  ///
  /// If an identity with the same `identityKey` already exists, returns it
  /// (with `lastSeenAt` updated). Otherwise creates a new identity with a fresh UUID.
  func resolveIdentity(signals: DeviceIdentitySignals) async throws -> StableDeviceIdentity

  /// Look up an existing identity by domain ID.
  func identity(for domainId: String) async throws -> StableDeviceIdentity?

  /// Update the MTP serial for an existing identity (called after device open).
  ///
  /// If the identity was created from a type hash and an MTP serial is now available,
  /// the identity key is upgraded so future lookups use the serial.
  func updateMTPSerial(domainId: String, mtpSerial: String) async throws

  /// List all known device identities.
  func allIdentities() async throws -> [StableDeviceIdentity]

  /// Remove an identity (e.g., after extended absence cleanup).
  func removeIdentity(domainId: String) async throws
}
