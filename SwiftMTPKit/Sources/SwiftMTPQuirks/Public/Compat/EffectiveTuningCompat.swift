// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import SwiftMTPCore

/// Back-compat façade for older call-sites referencing `EffectiveTuningBuilder`.
public struct EffectiveTuningBuilder {
  private let deniedQuirks: String?

  public init(deniedQuirks: String?) {
    self.deniedQuirks = deniedQuirks
  }

  public func buildEffectiveTuning(
    fingerprint: MTPDeviceFingerprint,
    capabilities: ProbedCapabilities,
    strict: Bool,
    safe: Bool
  ) -> EffectiveTuning {
    // Delegate to the current static API
    return SwiftMTPCore.EffectiveTuningBuilder.build(
      capabilities: [
        "partialRead": capabilities.partialRead,
        "partialWrite": capabilities.partialWrite
      ],
      learned: nil as EffectiveTuning?,
      quirk: nil as DeviceQuirk?,
      overrides: nil as [String: String]?
    )
  }
}
