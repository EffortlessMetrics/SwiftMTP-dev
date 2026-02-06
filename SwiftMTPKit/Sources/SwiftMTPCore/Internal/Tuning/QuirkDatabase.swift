// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public struct QuirkHook: Codable, Sendable {
  public enum Phase: String, Codable, Sendable { 
    case postOpenUSB, postClaimInterface, postOpenSession, 
         beforeGetDeviceInfo, beforeGetStorageIDs, beforeGetObjectHandles,
         beforeTransfer, afterTransfer, onDeviceBusy, onDetach 
  }
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

  // Internal decoding helpers
  private enum CodingKeys: String, CodingKey {
    case id, match, tuning, hooks, ops, status, confidence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
    hooks = try container.decodeIfPresent([QuirkHook].self, forKey: .hooks)
    operations = try container.decodeIfPresent([String: Bool].self, forKey: .ops)

    // Decode 'match' object
    let match = try container.decode(RawMatch.self, forKey: .match)
    vid = try parseHex(match.vid)
    pid = try parseHex(match.pid)
    bcdDevice = try match.bcdDevice.map { try parseHex($0) }
    ifaceClass = try match.iface?.`class`.map { try parseHex($0) }
    ifaceSubclass = try match.iface?.subclass.map { try parseHex($0) }
    ifaceProtocol = try match.iface?.`protocol`.map { try parseHex($0) }

    // Decode 'tuning' object
    if let tuning = try container.decodeIfPresent(RawTuning.self, forKey: .tuning) {
      maxChunkBytes = tuning.maxChunkBytes
      ioTimeoutMs = tuning.ioTimeoutMs
      handshakeTimeoutMs = tuning.handshakeTimeoutMs
      inactivityTimeoutMs = tuning.inactivityTimeoutMs
      overallDeadlineMs = tuning.overallDeadlineMs
      stabilizeMs = tuning.stabilizeMs
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(status, forKey: .status)
    try container.encodeIfPresent(confidence, forKey: .confidence)
    try container.encodeIfPresent(hooks, forKey: .hooks)
    try container.encodeIfPresent(operations, forKey: .ops)
    
    // We don't necessarily need to implement symmetric encoding for now 
    // since we mostly read the quirks.json, but for completeness:
    // (Skipping full symmetric encoding to keep it simple unless needed)
  }
}

private struct RawMatch: Codable {
  let vid: String
  let pid: String
  let bcdDevice: String?
  let iface: RawIface?
  struct RawIface: Codable {
    let `class`: String?
    let subclass: String?
    let `protocol`: String?
  }
}

private struct RawTuning: Codable {
  let maxChunkBytes: Int?
  let handshakeTimeoutMs: Int?
  let ioTimeoutMs: Int?
  let inactivityTimeoutMs: Int?
  let overallDeadlineMs: Int?
  let stabilizeMs: Int?
}

private func parseHex<T: FixedWidthInteger>(_ str: String) throws -> T {
  let clean = str.hasPrefix("0x") ? String(str.dropFirst(2)) : str
  guard let val = T(clean, radix: 16) else {
    throw NSError(domain: "QuirkParsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid hex string: \(str)"])
  }
  return val
}

public struct QuirkDatabase: Codable, Sendable {
  public var schemaVersion: String
  public var entries: [DeviceQuirk]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, version, entries
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
    entries = try container.decode([DeviceQuirk].self, forKey: .entries)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(entries, forKey: .entries)
  }

  public static func load(pathEnv: String? = ProcessInfo.processInfo.environment["SWIFTMTP_QUIRKS_PATH"]) throws -> QuirkDatabase {
    let fm = FileManager.default
    let candidates: [URL] = [
      pathEnv.flatMap { URL(fileURLWithPath: $0) },
      URL(fileURLWithPath: "Specs/quirks.json"),
      URL(fileURLWithPath: "../Specs/quirks.json"),
      URL(fileURLWithPath: "SwiftMTPKit/Specs/quirks.json"),
    ].compactMap { $0 }
    guard let url = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
      throw NSError(domain: "QuirkDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "quirks.json not found"])
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(QuirkDatabase.self, from: data)
  }

  /// Returns the most specific match (VID/PID/bcdDevice/iface triplet outranks wildcards).
  public func match(vid: UInt16, pid: UInt16, bcdDevice: UInt16?, ifaceClass: UInt8?, ifaceSubclass: UInt8?, ifaceProtocol: UInt8?) -> DeviceQuirk? {
    func score(_ q: DeviceQuirk) -> Int {
      var s = 0
      if q.vid == vid { s += 4 } else { return -1 } // Must match VID
      if q.pid == pid { s += 4 } else { return -1 } // Must match PID
      
      if let b = q.bcdDevice {
        if let bb = bcdDevice, b == bb { s += 3 } else { return -1 }
      }
      
      if let c = q.ifaceClass {
        if let cc = ifaceClass, c == cc { s += 2 } else { return -1 }
      }
      
      if let sc = q.ifaceSubclass {
        if let scc = ifaceSubclass, sc == scc { s += 2 } else { return -1 }
      }
      
      if let pr = q.ifaceProtocol {
        if let prr = ifaceProtocol, pr == prr { s += 2 } else { return -1 }
      }
      
      return s
    }
    
    let scored = entries.map { (entry: $0, score: score($0)) }
    let valid = scored.filter { $0.score >= 0 }
    return valid.max(by: { $0.score < $1.score })?.entry
  }
}