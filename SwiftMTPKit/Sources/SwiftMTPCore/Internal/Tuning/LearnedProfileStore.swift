// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public struct LearnedProfile: Codable, Sendable {
  public var key: String             // e.g., "2717:ff10:06-01-01" (vid:pid:iface triplet)
  public var lastSeen: Date
  public var firstSeen: Date
  public var samples: Int
  public var maxChunkBytes: Int
  public var ioTimeoutMs: Int
  public var handshakeTimeoutMs: Int
  public var inactivityTimeoutMs: Int
  public var overallDeadlineMs: Int
}

public enum LearnedStore {
  static func baseDir() -> URL {
    #if os(macOS)
    let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return u.appendingPathComponent("SwiftMTP/learned", isDirectory: true)
    #else
    let home = URL(fileURLWithPath: NSHomeDirectory())
    return home.appendingPathComponent(".config/swiftmtp/learned", isDirectory: true)
    #endif
  }

  public static func load(key: String) -> LearnedProfile? {
    let path = baseDir().appendingPathComponent("\(key).json")
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    guard let data = try? Data(contentsOf: path) else { return nil }
    guard let p = try? JSONDecoder().decode(LearnedProfile.self, from: data) else { return nil }
    // TTL 90 days
    if Date().timeIntervalSince(p.lastSeen) > 90*24*3600 { return nil }
    return p
  }

  public static func save(_ p: LearnedProfile) {
    let dir = baseDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("\(p.key).json")
    if let data = try? JSONEncoder().encode(p) { try? data.write(to: path, options: .atomic) }
  }

  /// Simple EMA smoothing on successful observation; clamp to safe bounds
  public static func update(key: String, obs: EffectiveTuning) {
    var cur = load(key: key) ?? LearnedProfile(
      key: key, lastSeen: Date(), firstSeen: Date(), samples: 0,
      maxChunkBytes: obs.maxChunkBytes, ioTimeoutMs: obs.ioTimeoutMs,
      handshakeTimeoutMs: obs.handshakeTimeoutMs, inactivityTimeoutMs: obs.inactivityTimeoutMs,
      overallDeadlineMs: obs.overallDeadlineMs
    )
    let alpha = 0.2
    func ema(_ old: Int, _ new: Int) -> Int { Int(Double(old)*(1-alpha) + Double(new)*alpha) }
    cur.maxChunkBytes      = ema(cur.maxChunkBytes, obs.maxChunkBytes)
    cur.ioTimeoutMs        = ema(cur.ioTimeoutMs, obs.ioTimeoutMs)
    cur.handshakeTimeoutMs = ema(cur.handshakeTimeoutMs, obs.handshakeTimeoutMs)
    cur.inactivityTimeoutMs = ema(cur.inactivityTimeoutMs, obs.inactivityTimeoutMs)
    cur.overallDeadlineMs  = ema(cur.overallDeadlineMs, obs.overallDeadlineMs)
    cur.samples += 1
    cur.lastSeen = Date()
    save(cur)
  }
}
