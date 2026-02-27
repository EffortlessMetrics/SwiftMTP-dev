// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public struct EffectiveTuning: Sendable {
  public var maxChunkBytes: Int
  public var ioTimeoutMs: Int
  public var handshakeTimeoutMs: Int
  public var inactivityTimeoutMs: Int
  public var overallDeadlineMs: Int
  public var stabilizeMs: Int
  public var postClaimStabilizeMs: Int
  public var postProbeStabilizeMs: Int
  public var resetOnOpen: Bool
  public var disableEventPump: Bool
  public var operations: [String: Bool]
  public var hooks: [QuirkHook]

  public init(
    maxChunkBytes: Int,
    ioTimeoutMs: Int,
    handshakeTimeoutMs: Int,
    inactivityTimeoutMs: Int,
    overallDeadlineMs: Int,
    stabilizeMs: Int,
    postClaimStabilizeMs: Int,
    postProbeStabilizeMs: Int,
    resetOnOpen: Bool,
    disableEventPump: Bool,
    operations: [String: Bool],
    hooks: [QuirkHook]
  ) {
    self.maxChunkBytes = maxChunkBytes
    self.ioTimeoutMs = ioTimeoutMs
    self.handshakeTimeoutMs = handshakeTimeoutMs
    self.inactivityTimeoutMs = inactivityTimeoutMs
    self.overallDeadlineMs = overallDeadlineMs
    self.stabilizeMs = stabilizeMs
    self.postClaimStabilizeMs = postClaimStabilizeMs
    self.postProbeStabilizeMs = postProbeStabilizeMs
    self.resetOnOpen = resetOnOpen
    self.disableEventPump = disableEventPump
    self.operations = operations
    self.hooks = hooks
  }

  public static func defaults() -> EffectiveTuning {
    .init(
      maxChunkBytes: 1 << 20,  // 1 MiB
      ioTimeoutMs: 8000,
      handshakeTimeoutMs: 6000,
      inactivityTimeoutMs: 8000,
      overallDeadlineMs: 60000,
      stabilizeMs: 0,
      postClaimStabilizeMs: 250,
      postProbeStabilizeMs: 0,
      resetOnOpen: false,
      disableEventPump: false,
      operations: [:],
      hooks: []
    )
  }
}

public struct EffectiveTuningBuilder: Sendable {
  public static func build(
    capabilities: [String: Bool],
    learned: EffectiveTuning?,
    quirk: DeviceQuirk?,
    overrides: [String: String]?
  ) -> EffectiveTuning {
    var eff = EffectiveTuning.defaults()

    // (2) capability probe layer
    for (k, v) in capabilities { eff.operations[k] = v }

    // (3) learned profile layer (clamped)
    if var l = learned {
      clamp(&l)
      eff = merge(base: eff, top: l)
    }

    // (4) static quirk
    if let q = quirk {
      if let v = q.maxChunkBytes { eff.maxChunkBytes = v }
      if let v = q.ioTimeoutMs { eff.ioTimeoutMs = v }
      if let v = q.handshakeTimeoutMs { eff.handshakeTimeoutMs = v }
      if let v = q.inactivityTimeoutMs { eff.inactivityTimeoutMs = v }
      if let v = q.overallDeadlineMs { eff.overallDeadlineMs = v }
      if let v = q.stabilizeMs { eff.stabilizeMs = v }
      if let v = q.postClaimStabilizeMs { eff.postClaimStabilizeMs = v }
      if let v = q.postProbeStabilizeMs { eff.postProbeStabilizeMs = v }
      if let v = q.resetOnOpen { eff.resetOnOpen = v }
      if let v = q.disableEventPump { eff.disableEventPump = v }
      if let ops = q.operations { for (k, v) in ops { eff.operations[k] = v } }
      if let h = q.hooks { eff.hooks.append(contentsOf: h) }
    }

    // (5) user overrides env (highest precedence)
    if let o = overrides {
      if let s = o["maxChunkBytes"], let v = Int(s) { eff.maxChunkBytes = v }
      if let s = o["ioTimeoutMs"], let v = Int(s) { eff.ioTimeoutMs = v }
      if let s = o["handshakeTimeoutMs"], let v = Int(s) { eff.handshakeTimeoutMs = v }
      if let s = o["inactivityTimeoutMs"], let v = Int(s) { eff.inactivityTimeoutMs = v }
      if let s = o["overallDeadlineMs"], let v = Int(s) { eff.overallDeadlineMs = v }
      if let s = o["stabilizeMs"], let v = Int(s) { eff.stabilizeMs = v }
    }

    clamp(&eff)
    return eff
  }

  private static func merge(base: EffectiveTuning, top: EffectiveTuning) -> EffectiveTuning {
    var out = base
    out.maxChunkBytes = top.maxChunkBytes
    out.ioTimeoutMs = top.ioTimeoutMs
    out.handshakeTimeoutMs = top.handshakeTimeoutMs
    out.inactivityTimeoutMs = top.inactivityTimeoutMs
    out.overallDeadlineMs = top.overallDeadlineMs
    out.stabilizeMs = top.stabilizeMs
    out.postClaimStabilizeMs = top.postClaimStabilizeMs
    out.postProbeStabilizeMs = top.postProbeStabilizeMs
    out.resetOnOpen = top.resetOnOpen
    out.disableEventPump = top.disableEventPump
    for (k, v) in top.operations { out.operations[k] = v }
    out.hooks.append(contentsOf: top.hooks)
    return out
  }

  /// Build a full `DevicePolicy` combining tuning, typed flags, and provenance.
  ///
  /// When `quirk` is nil but `ifaceClass` is `0x06` (PTP/Still-Image-Capture),
  /// class-based heuristic defaults are applied so unrecognised cameras still work.
  public static func buildPolicy(
    capabilities: [String: Bool],
    learned: EffectiveTuning?,
    quirk: DeviceQuirk?,
    overrides: [String: String]?,
    ifaceClass: UInt8? = nil
  ) -> DevicePolicy {
    let tuning = build(
      capabilities: capabilities,
      learned: learned,
      quirk: quirk,
      overrides: overrides
    )
    let flags: QuirkFlags
    if let q = quirk {
      flags = q.resolvedFlags()
    } else if ifaceClass == 0x06 {
      flags = QuirkFlags.ptpCameraDefaults()
    } else {
      flags = QuirkFlags()
    }
    var sources = PolicySources()
    if overrides?.isEmpty == false {
      sources.chunkSizeSource = .userOverride
      sources.ioTimeoutSource = .userOverride
    } else if quirk != nil {
      sources.chunkSizeSource = .quirk
      sources.ioTimeoutSource = .quirk
      sources.flagsSource = .quirk
    } else if ifaceClass == 0x06 {
      sources.flagsSource = .defaults  // class heuristic
    } else if learned != nil {
      sources.chunkSizeSource = .learned
      sources.ioTimeoutSource = .learned
    }
    return DevicePolicy(tuning: tuning, flags: flags, sources: sources)
  }

  private static func clamp(_ t: inout EffectiveTuning) {
    t.maxChunkBytes = min(max(t.maxChunkBytes, 128 * 1024), 16 * 1024 * 1024)
    t.ioTimeoutMs = min(max(t.ioTimeoutMs, 1000), 60000)
    t.handshakeTimeoutMs = min(max(t.handshakeTimeoutMs, 1000), 60000)
    t.inactivityTimeoutMs = min(max(t.inactivityTimeoutMs, 1000), 60000)
    t.overallDeadlineMs = min(max(t.overallDeadlineMs, 5000), 300000)
    t.stabilizeMs = min(max(t.stabilizeMs, 0), 5000)
    t.postClaimStabilizeMs = min(max(t.postClaimStabilizeMs, 0), 5000)
    t.postProbeStabilizeMs = min(max(t.postProbeStabilizeMs, 0), 5000)
  }
}
