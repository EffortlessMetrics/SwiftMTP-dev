// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Resolved device policy combining tuning, behavioral flags, fallback
/// selections, and provenance metadata. This is the single "truth" object
/// that device actors consult for all behavioral decisions.
public struct DevicePolicy: Sendable {

  /// Numeric tuning parameters (chunk sizes, timeouts).
  public let tuning: EffectiveTuning

  /// Typed behavioral flags.
  public var flags: QuirkFlags

  /// Which enumeration/read/write strategies were selected.
  public var fallbacks: FallbackSelections

  /// Where each setting came from.
  public let sources: PolicySources

  public init(
    tuning: EffectiveTuning,
    flags: QuirkFlags,
    fallbacks: FallbackSelections = FallbackSelections(),
    sources: PolicySources = PolicySources()
  ) {
    self.tuning = tuning
    self.flags = flags
    self.fallbacks = fallbacks
    self.sources = sources
  }
}

/// Tracks provenance for each resolved setting.
public struct PolicySources: Sendable {

  public enum Source: String, Sendable {
    case defaults
    case learned
    case quirk
    case probe
    case userOverride
  }

  /// Which layer determined each key setting.
  public var chunkSizeSource: Source = .defaults
  public var ioTimeoutSource: Source = .defaults
  public var flagsSource: Source = .defaults
  public var fallbackSource: Source = .defaults

  public init() {}
}
