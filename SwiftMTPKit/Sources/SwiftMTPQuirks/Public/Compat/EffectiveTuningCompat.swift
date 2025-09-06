// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import SwiftMTPCore

/// Back-compat façade for older call-sites referencing `EffectiveTuningBuilder`.
public struct EffectiveTuningBuilder {
  public static func build(
    capabilities: [String: Bool],
    learned: EffectiveTuning?,
    quirk: DeviceQuirk?,
    overrides: [String: String]?
  ) -> EffectiveTuning {
    SwiftMTPCore.EffectiveTuningBuilder.build(
      capabilities: capabilities,
      learned: learned,
      quirk: quirk,
      overrides: overrides
    )
  }
}
