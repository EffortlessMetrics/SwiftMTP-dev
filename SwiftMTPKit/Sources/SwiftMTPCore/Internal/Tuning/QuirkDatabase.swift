// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public struct QuirkHook: Codable, Sendable {
  public enum Phase: String, Codable, Sendable { case postOpenUSB, postClaimInterface, postOpenSession, beforeGetStorageIDs, beforeTransfer, onDetach }
  public var phase: Phase
  public var delayMs: Int?
  public struct BusyBackoff: Codable, Sendable { var retries: Int; var baseMs: Int; var jitterPct: Double }
  public var busyBackoff: BusyBackoff?
}

public struct DeviceQuirk: Codable, Sendable {
  public var id: String                     // e.g. "xiaomi-mi-note-2-ff10"
  public var vid: UInt16
  public var pid: UInt16
  public var bcdDevice: UInt16?
  public var ifaceClass: UInt8?
  public var ifaceSubclass: UInt8?
  public var ifaceProtocol: UInt8?
  public var maxChunkBytes: Int?
  public var ioTimeoutMs: Int?
  public var handshakeTimeoutMs: Int?
  public var inactivityTimeoutMs: Int?
  public var overallDeadlineMs: Int?
  public var stabilizeMs: Int?
  public var operations: [String: Bool]?    // e.g. {"partialRead": true}
  public var hooks: [QuirkHook]?
  public var status: String?                // "stable" | "experimental" | ...
  public var confidence: String?            // "low" | "medium" | "high"
}

public struct QuirkDatabase: Codable, Sendable {
  public var schemaVersion: String
  public var entries: [DeviceQuirk]

  public static func load(pathEnv: String? = ProcessInfo.processInfo.environment["SWIFTMTP_QUIRKS_PATH"]) throws -> QuirkDatabase {
    let fm = FileManager.default
    let candidates: [URL] = [
      pathEnv.flatMap { URL(fileURLWithPath: $0) },
      URL(fileURLWithPath: "Specs/quirks.json"),
      URL(fileURLWithPath: "../Specs/quirks.json"),
    ].compactMap { $0 }
    guard let url = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
      throw NSError(domain: "QuirkDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "quirks.json not found"])
    }
    let data = try Data(contentsOf: url)
    do {
        return try JSONDecoder().decode(QuirkDatabase.self, from: data)
    } catch {
        // Fallback for Storybook/Dev: don't crash if schema mismatch
        return QuirkDatabase(schemaVersion: "1.0.0", entries: [])
    }
  }

  /// Returns the most specific match (VID/PID/bcdDevice/iface triplet outranks wildcards).
  public func match(vid: UInt16, pid: UInt16, bcdDevice: UInt16?, ifaceClass: UInt8?, ifaceSubclass: UInt8?, ifaceProtocol: UInt8?) -> DeviceQuirk? {
    func score(_ q: DeviceQuirk) -> Int {
      var s = 0
      if q.vid == vid { s += 4 }
      if q.pid == pid { s += 4 }
      if let b = q.bcdDevice, let bb = bcdDevice, b == bb { s += 3 }
      if let c = q.ifaceClass, let cc = ifaceClass, c == cc { s += 2 }
      if let sc = q.ifaceSubclass, let scc = ifaceSubclass, sc == scc { s += 2 }
      if let pr = q.ifaceProtocol, let prr = ifaceProtocol, pr == prr { s += 2 }
      return s
    }
    return entries.max(by: { score($0) < score($1) })
  }
}
