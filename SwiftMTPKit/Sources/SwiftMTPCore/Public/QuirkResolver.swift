// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPQuirks

/// Single entry-point for resolving a device's complete policy from
/// fingerprint matching, flag resolution, and tuning building.
public struct QuirkResolver: Sendable {

  /// Resolve a complete `DevicePolicy` for a device fingerprint.
  ///
  /// - Parameters:
  ///   - fingerprint: USB fingerprint of the device.
  ///   - database: Loaded quirks database.
  ///   - capabilities: Probed capabilities (may be empty pre-session).
  ///   - learned: Previously learned tuning profile.
  ///   - overrides: User/environment overrides.
  /// - Returns: A fully resolved `DevicePolicy`.
  public static func resolve(
    fingerprint: MTPDeviceFingerprint,
    database: QuirkDatabase,
    capabilities: [String: Bool] = [:],
    learned: EffectiveTuning? = nil,
    overrides: [String: String]? = nil
  ) -> DevicePolicy {
    let vid = UInt16(fingerprint.vid, radix: 16) ?? 0
    let pid = UInt16(fingerprint.pid, radix: 16) ?? 0
    let ifaceClass = UInt8(fingerprint.interfaceTriple.class, radix: 16)
    let ifaceSubclass = UInt8(fingerprint.interfaceTriple.subclass, radix: 16)
    let ifaceProtocol = UInt8(fingerprint.interfaceTriple.protocol, radix: 16)
    let bcdDevice = fingerprint.bcdDevice.flatMap { UInt16($0, radix: 16) }

    let quirk = database.match(
      vid: vid, pid: pid,
      bcdDevice: bcdDevice,
      ifaceClass: ifaceClass,
      ifaceSubclass: ifaceSubclass,
      ifaceProtocol: ifaceProtocol
    )

    return EffectiveTuningBuilder.buildPolicy(
      capabilities: capabilities,
      learned: learned,
      quirk: quirk,
      overrides: overrides
    )
  }
}
