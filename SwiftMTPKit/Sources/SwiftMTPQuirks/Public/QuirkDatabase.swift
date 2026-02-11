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
  public struct BusyBackoff: Codable, Sendable { 
    public var retries: Int
    public var baseMs: Int
    public var jitterPct: Double 
    
    public init(retries: Int, baseMs: Int, jitterPct: Double) {
        self.retries = retries
        self.baseMs = baseMs
        self.jitterPct = jitterPct
    }
  }
  public var busyBackoff: BusyBackoff?
  
  public init(phase: Phase, delayMs: Int? = nil, busyBackoff: BusyBackoff? = nil) {
    self.phase = phase
    self.delayMs = delayMs
    self.busyBackoff = busyBackoff
  }
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
  public var postClaimStabilizeMs: Int?
  public var resetOnOpen: Bool?
  public var disableEventPump: Bool?
  public var operations: [String: Bool]?    // e.g. {"partialRead": true}
  public var hooks: [QuirkHook]?
  public var flags: QuirkFlags?             // Typed behavioral flags
  public var status: String?                // "stable" | "experimental" | ...
  public var confidence: String?            // "low" | "medium" | "high"

  public init(
    id: String,
    vid: UInt16,
    pid: UInt16,
    bcdDevice: UInt16? = nil,
    ifaceClass: UInt8? = nil,
    ifaceSubclass: UInt8? = nil,
    ifaceProtocol: UInt8? = nil,
    maxChunkBytes: Int? = nil,
    ioTimeoutMs: Int? = nil,
    handshakeTimeoutMs: Int? = nil,
    inactivityTimeoutMs: Int? = nil,
    overallDeadlineMs: Int? = nil,
    stabilizeMs: Int? = nil,
    postClaimStabilizeMs: Int? = nil,
    resetOnOpen: Bool? = nil,
    disableEventPump: Bool? = nil,
    operations: [String: Bool]? = nil,
    hooks: [QuirkHook]? = nil,
    flags: QuirkFlags? = nil,
    status: String? = nil,
    confidence: String? = nil
  ) {
    self.id = id
    self.vid = vid
    self.pid = pid
    self.bcdDevice = bcdDevice
    self.ifaceClass = ifaceClass
    self.ifaceSubclass = ifaceSubclass
    self.ifaceProtocol = ifaceProtocol
    self.maxChunkBytes = maxChunkBytes
    self.ioTimeoutMs = ioTimeoutMs
    self.handshakeTimeoutMs = handshakeTimeoutMs
    self.inactivityTimeoutMs = inactivityTimeoutMs
    self.overallDeadlineMs = overallDeadlineMs
    self.stabilizeMs = stabilizeMs
    self.postClaimStabilizeMs = postClaimStabilizeMs
    self.resetOnOpen = resetOnOpen
    self.disableEventPump = disableEventPump
    self.operations = operations
    self.hooks = hooks
    self.flags = flags
    self.status = status
    self.confidence = confidence
  }

  /// Resolve typed QuirkFlags, synthesizing from `operations` map if
  /// the entry uses the legacy `ops` format instead of typed `flags`.
  public func resolvedFlags() -> QuirkFlags {
    if let f = flags { return f }
    var f = QuirkFlags()
    // Translate legacy ops → typed flags
    if let ops = operations {
      if let v = ops["supportsGetPartialObject64"] { f.supportsPartialRead64 = v }
      if let v = ops["supportsSendPartialObject"]  { f.supportsPartialWrite = v }
      if let v = ops["preferGetObjectPropList"]     { f.prefersPropListEnumeration = v }
    }
    if let v = resetOnOpen     { f.resetOnOpen = v }
    if let v = disableEventPump { f.disableEventPump = v }
    if let s = stabilizeMs, s > 0 { f.requireStabilization = true }
    return f
  }

  private enum CodingKeys: String, CodingKey {
    case id, match, tuning, hooks, ops, flags, status, confidence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
    hooks = try container.decodeIfPresent([QuirkHook].self, forKey: .hooks)
    operations = try container.decodeIfPresent([String: Bool].self, forKey: .ops)
    flags = try container.decodeIfPresent(QuirkFlags.self, forKey: .flags)

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
      postClaimStabilizeMs = tuning.postClaimStabilizeMs
      resetOnOpen = tuning.resetOnOpen
      disableEventPump = tuning.disableEventPump
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(status, forKey: .status)
    try container.encodeIfPresent(confidence, forKey: .confidence)
    try container.encodeIfPresent(hooks, forKey: .hooks)
    try container.encodeIfPresent(operations, forKey: .ops)
    
    // Reverse mapping for 'match' and 'tuning' would go here if needed
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
  let postClaimStabilizeMs: Int?
  let resetOnOpen: Bool?
  let disableEventPump: Bool?
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

  public init(schemaVersion: String, entries: [DeviceQuirk]) {
    self.schemaVersion = schemaVersion
    self.entries = entries
  }

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