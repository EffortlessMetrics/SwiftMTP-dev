// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public struct DeviceFingerprint: Sendable, Codable, Equatable {
  public let vid: UInt16
  public let pid: UInt16
  public let bcdDevice: UInt16?
  public let ifaceClass: UInt8?
  public let ifaceSubClass: UInt8?
  public let ifaceProtocol: UInt8?

  public init(vid: UInt16, pid: UInt16, bcdDevice: UInt16?,
              ifaceClass: UInt8?, ifaceSubClass: UInt8?, ifaceProtocol: UInt8?) {
    self.vid = vid; self.pid = pid; self.bcdDevice = bcdDevice
    self.ifaceClass = ifaceClass; self.ifaceSubClass = ifaceSubClass; self.ifaceProtocol = ifaceProtocol
  }
}

public enum QuirkDatabaseError: Error { case invalidJSON, schemaMismatch }

public struct QuirkEntry: Sendable, Codable, Equatable {
  public let id: String
  public let status: String
  public let confidence: String
  public let overrides: EffectiveTuningOverrides
}

public struct EffectiveTuningOverrides: Sendable, Codable, Equatable {
  public let maxChunkBytes: Int?
  public let ioTimeoutMs: Int?
  public let stabilizeMs: Int?
}

public final class QuirkDatabase: @unchecked Sendable {
  public let entries: [QuirkEntry]
  public let schemaVersion: String

  public init(data: Data) throws {
    // Decode your JSON format; throw QuirkDatabaseError.invalidJSON on failure
    let decoder = JSONDecoder()
    let rawDatabase = try decoder.decode(RawQuirkDatabase.self, from: data)

    self.schemaVersion = rawDatabase.schemaVersion
    self.entries = rawDatabase.devices.map { device in
      QuirkEntry(
        id: device.id,
        status: device.status ?? "stable",
        confidence: device.confidence ?? "medium",
        overrides: EffectiveTuningOverrides(
          maxChunkBytes: device.maxChunkBytes,
          ioTimeoutMs: device.ioTimeoutMs,
          stabilizeMs: device.stabilizeMs
        )
      )
    }
  }

  public static func load() throws -> QuirkDatabase {
    return try loadDefault()
  }

  public static func loadDefault(in bundle: Bundle? = nil) throws -> QuirkDatabase {
    let targetBundle = bundle ?? Bundle.module
    
    if let url = targetBundle.url(forResource: "quirks", withExtension: "json") {
        let data = try Data(contentsOf: url)
        return try QuirkDatabase(data: data)
    }
    
    // Fallback: Check current directory (for CLI development/test)
    let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let localURL = cwdURL.appendingPathComponent("Specs/quirks.json")
    if FileManager.default.fileExists(atPath: localURL.path) {
        let data = try Data(contentsOf: localURL)
        return try QuirkDatabase(data: data)
    }
    
    // Fallback for package root execution
    let parentSpecsURL = cwdURL.appendingPathComponent("../Specs/quirks.json")
    if FileManager.default.fileExists(atPath: parentSpecsURL.path) {
        let data = try Data(contentsOf: parentSpecsURL)
        return try QuirkDatabase(data: data)
    }

    throw NSError(domain: "QuirkDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "quirks.json not found in \(targetBundle.bundlePath) or local paths"])
  }

  /// Returns the best quirk for a device fingerprint, or nil if none matches.
  public func bestMatch(for fp: DeviceFingerprint) -> QuirkEntry? {
    // Use existing scoring logic from internal implementation
    return entries.max { lhs, rhs in
      score(for: lhs, fingerprint: fp) < score(for: rhs, fingerprint: fp)
    }
  }

  private func score(for entry: QuirkEntry, fingerprint fp: DeviceFingerprint) -> Int {
    // This would need to be implemented based on your existing scoring logic
    // For now, return a basic score based on available fields
    return 1 // Placeholder - implement proper scoring
  }
}

// Private helper types for JSON decoding
private struct RawQuirkDatabase: Codable {
  let schemaVersion: String
  let devices: [RawDeviceQuirk]
}

private struct RawDeviceQuirk: Codable {
  let id: String
  let vid: UInt16
  let pid: UInt16
  let bcdDevice: UInt16?
  let ifaceClass: UInt8?
  let ifaceSubclass: UInt8?
  let ifaceProtocol: UInt8?
  let maxChunkBytes: Int?
  let ioTimeoutMs: Int?
  let stabilizeMs: Int?
  let status: String?
  let confidence: String?
}
