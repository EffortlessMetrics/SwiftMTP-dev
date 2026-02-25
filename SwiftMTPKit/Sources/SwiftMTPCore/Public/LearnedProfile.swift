// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Learned performance profile for a specific device fingerprint.
/// Captures successful configurations and adapts over time.
public struct LearnedProfile: Sendable, Codable {
  /// Unique fingerprint identifying the device + environment
  public let fingerprint: MTPDeviceFingerprint

  /// Short hash of the device fingerprint for quick comparison
  public let fingerprintHash: String

  /// When this profile was created
  public let created: Date

  /// When this profile was last updated
  public let lastUpdated: Date

  /// Number of successful sessions that contributed to this profile
  public let sampleCount: Int

  /// Learned optimal chunk size (bytes)
  public let optimalChunkSize: Int?

  /// Learned typical handshake time (milliseconds)
  public let avgHandshakeMs: Int?

  /// Learned I/O timeout (milliseconds)
  public let optimalIoTimeoutMs: Int?

  /// Learned inactivity timeout (milliseconds)
  public let optimalInactivityTimeoutMs: Int?

  /// P95 throughput for reads (MB/s)
  public let p95ReadThroughputMBps: Double?

  /// P95 throughput for writes (MB/s)
  public let p95WriteThroughputMBps: Double?

  /// Success rate (0.0-1.0)
  public let successRate: Double

  /// Host environment fingerprint (OS version, USB stack info)
  public let hostEnvironment: String

  /// Creates a new learned profile
  public init(
    fingerprint: MTPDeviceFingerprint,
    fingerprintHash: String? = nil,
    created: Date = Date(),
    lastUpdated: Date = Date(),
    sampleCount: Int = 1,
    optimalChunkSize: Int? = nil,
    avgHandshakeMs: Int? = nil,
    optimalIoTimeoutMs: Int? = nil,
    optimalInactivityTimeoutMs: Int? = nil,
    p95ReadThroughputMBps: Double? = nil,
    p95WriteThroughputMBps: Double? = nil,
    successRate: Double = 1.0,
    hostEnvironment: String = ProcessInfo.processInfo.operatingSystemVersionString
  ) {
    self.fingerprint = fingerprint
    self.fingerprintHash = fingerprintHash ?? fingerprint.hashString
    self.created = created
    self.lastUpdated = lastUpdated
    self.sampleCount = sampleCount
    self.optimalChunkSize = optimalChunkSize
    self.avgHandshakeMs = avgHandshakeMs
    self.optimalIoTimeoutMs = optimalIoTimeoutMs
    self.optimalInactivityTimeoutMs = optimalInactivityTimeoutMs
    self.p95ReadThroughputMBps = p95ReadThroughputMBps
    self.p95WriteThroughputMBps = p95WriteThroughputMBps
    self.successRate = successRate
    self.hostEnvironment = hostEnvironment
  }

  /// Merges this profile with new session data
  public func merged(with sessionData: SessionData) -> LearnedProfile {
    let newSampleCount = sampleCount + 1
    let alpha = 1.0 / Double(newSampleCount)  // Learning rate

    return LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprintHash,
      created: created,
      lastUpdated: Date(),
      sampleCount: newSampleCount,
      optimalChunkSize: sessionData.actualChunkSize ?? optimalChunkSize,
      avgHandshakeMs: weightedAverage(
        current: avgHandshakeMs, new: sessionData.handshakeTimeMs, alpha: alpha),
      optimalIoTimeoutMs: sessionData.effectiveIoTimeoutMs ?? optimalIoTimeoutMs,
      optimalInactivityTimeoutMs: sessionData.effectiveInactivityTimeoutMs
        ?? optimalInactivityTimeoutMs,
      p95ReadThroughputMBps: sessionData.readThroughputMBps.flatMap {
        weightedAverage(current: p95ReadThroughputMBps, new: $0, alpha: alpha)
      },
      p95WriteThroughputMBps: sessionData.writeThroughputMBps.flatMap {
        weightedAverage(current: p95WriteThroughputMBps, new: $0, alpha: alpha)
      },
      successRate: weightedAverage(
        current: successRate, new: sessionData.wasSuccessful ? 1.0 : 0.0, alpha: alpha)
        ?? successRate,
      hostEnvironment: hostEnvironment
    )
  }

  private func weightedAverage(current: Int?, new: Int?, alpha: Double) -> Int? {
    guard let new = new else { return current }
    guard let current = current else { return new }
    return Int(Double(current) * (1 - alpha) + Double(new) * alpha)
  }

  private func weightedAverage(current: Double?, new: Double?, alpha: Double) -> Double? {
    guard let newValue = new else { return current }
    guard let currentValue = current else { return newValue }
    return currentValue * (1 - alpha) + newValue * alpha
  }
}

/// Device fingerprint for uniquely identifying a device configuration
public struct MTPDeviceFingerprint: Sendable, Hashable, Codable {
  /// USB Vendor ID
  public let vid: String

  /// USB Product ID
  public let pid: String

  /// USB Device release number
  public let bcdDevice: String?

  /// Interface class/subclass/protocol triple
  public let interfaceTriple: InterfaceTriple

  /// Endpoint addresses
  public let endpointAddresses: EndpointAddresses

  /// Device info strings hash
  public let deviceInfoHash: String?

  /// Creates a device fingerprint
  public init(
    vid: String,
    pid: String,
    bcdDevice: String? = nil,
    interfaceTriple: InterfaceTriple,
    endpointAddresses: EndpointAddresses,
    deviceInfoHash: String? = nil
  ) {
    self.vid = vid
    self.pid = pid
    self.bcdDevice = bcdDevice
    self.interfaceTriple = interfaceTriple
    self.endpointAddresses = endpointAddresses
    self.deviceInfoHash = deviceInfoHash
  }

  /// Creates a fingerprint from USB device descriptor data
  public static func fromUSB(
    vid: UInt16,
    pid: UInt16,
    bcdDevice: UInt16? = nil,
    interfaceClass: UInt8,
    interfaceSubclass: UInt8,
    interfaceProtocol: UInt8,
    epIn: UInt8,
    epOut: UInt8,
    epEvt: UInt8? = nil,
    deviceInfoStrings: [String]? = nil
  ) -> MTPDeviceFingerprint {
    let deviceInfoHash = deviceInfoStrings.map { strings in
      let combined = strings.joined(separator: "|")
      return String(combined.hashValue)
    }

    return MTPDeviceFingerprint(
      vid: String(format: "%04x", vid),
      pid: String(format: "%04x", pid),
      bcdDevice: bcdDevice.map { String(format: "%04x", $0) },
      interfaceTriple: InterfaceTriple(
        class: String(format: "%02x", interfaceClass),
        subclass: String(format: "%02x", interfaceSubclass),
        protocol: String(format: "%02x", interfaceProtocol)
      ),
      endpointAddresses: EndpointAddresses(
        input: String(format: "%02x", epIn),
        output: String(format: "%02x", epOut),
        event: epEvt.map { String(format: "%02x", $0) }
      ),
      deviceInfoHash: deviceInfoHash
    )
  }

  public var hashString: String {
    let components = [
      vid, pid,
      bcdDevice ?? "0000",
      interfaceTriple.class, interfaceTriple.subclass, interfaceTriple.protocol,
      endpointAddresses.input, endpointAddresses.output,
      endpointAddresses.event ?? "00",
      deviceInfoHash ?? "none",
    ]
    return components.joined(separator: "-")
  }
}

/// USB interface descriptor triple
public struct InterfaceTriple: Sendable, Hashable, Codable {
  public let `class`: String
  public let subclass: String
  public let `protocol`: String
}

/// USB endpoint addresses
public struct EndpointAddresses: Sendable, Hashable, Codable {
  public let input: String
  public let output: String
  public let event: String?
}

/// Data captured from a successful device session
public struct SessionData: Sendable {
  /// Actual chunk size used
  public let actualChunkSize: Int?

  /// Time spent in handshake phase
  public let handshakeTimeMs: Int?

  /// Effective I/O timeout used
  public let effectiveIoTimeoutMs: Int?

  /// Effective inactivity timeout used
  public let effectiveInactivityTimeoutMs: Int?

  /// Read throughput achieved
  public let readThroughputMBps: Double?

  /// Write throughput achieved
  public let writeThroughputMBps: Double?

  /// Whether the session was successful
  public let wasSuccessful: Bool

  public init(
    actualChunkSize: Int? = nil,
    handshakeTimeMs: Int? = nil,
    effectiveIoTimeoutMs: Int? = nil,
    effectiveInactivityTimeoutMs: Int? = nil,
    readThroughputMBps: Double? = nil,
    writeThroughputMBps: Double? = nil,
    wasSuccessful: Bool = true
  ) {
    self.actualChunkSize = actualChunkSize
    self.handshakeTimeMs = handshakeTimeMs
    self.effectiveIoTimeoutMs = effectiveIoTimeoutMs
    self.effectiveInactivityTimeoutMs = effectiveInactivityTimeoutMs
    self.readThroughputMBps = readThroughputMBps
    self.writeThroughputMBps = writeThroughputMBps
    self.wasSuccessful = wasSuccessful
  }
}

/// Manages learned profiles with persistence and TTL
public final class LearnedProfileManager {
  private let storageURL: URL
  private let maxProfiles: Int
  private let ttlDays: Int
  private let inactivityDays: Int

  private var profiles: [String: LearnedProfile] = [:]
  private let queue = DispatchQueue(label: "com.swiftmtp.learned-profiles")

  public init(storageURL: URL, maxProfiles: Int = 1000, ttlDays: Int = 90, inactivityDays: Int = 30)
  {
    self.storageURL = storageURL
    self.maxProfiles = maxProfiles
    self.ttlDays = ttlDays
    self.inactivityDays = inactivityDays
    loadProfiles()
    cleanupExpired()
  }

  /// Gets the learned profile for a device fingerprint
  public func profile(for fingerprint: MTPDeviceFingerprint) -> LearnedProfile? {
    queue.sync {
      profiles[fingerprint.hashString]
    }
  }

  /// Updates or creates a learned profile with new session data
  public func updateProfile(for fingerprint: MTPDeviceFingerprint, with sessionData: SessionData) {
    queue.sync {
      let key = fingerprint.hashString
      let existing = profiles[key]
      let updated =
        existing?.merged(with: sessionData)
        ?? LearnedProfile(
          fingerprint: fingerprint,
          fingerprintHash: fingerprint.hashString,
          created: Date(),
          lastUpdated: Date(),
          sampleCount: 1,
          optimalChunkSize: sessionData.actualChunkSize,
          avgHandshakeMs: sessionData.handshakeTimeMs,
          optimalIoTimeoutMs: sessionData.effectiveIoTimeoutMs,
          optimalInactivityTimeoutMs: sessionData.effectiveInactivityTimeoutMs,
          p95ReadThroughputMBps: sessionData.readThroughputMBps,
          p95WriteThroughputMBps: sessionData.writeThroughputMBps
        )

      profiles[key] = updated

      // Enforce limits
      if profiles.count > maxProfiles {
        evictOldProfiles()
      }

      saveProfiles()
    }
  }

  /// Checks if a profile should be expired due to fingerprint changes
  public func shouldExpireProfile(_ profile: LearnedProfile, newFingerprint: MTPDeviceFingerprint)
    -> Bool
  {
    // Expire if bcdDevice changed (firmware update)
    if profile.fingerprint.bcdDevice != newFingerprint.bcdDevice {
      return true
    }

    // Expire if fingerprint hash changed (significant device change)
    if profile.fingerprintHash != newFingerprint.hashString {
      return true
    }

    return false
  }

  /// Gets the learned profile for a device fingerprint, handling expiration
  public func profile(for fingerprint: MTPDeviceFingerprint, shouldUpdate: Bool = false)
    -> LearnedProfile?
  {
    queue.sync {
      let key = fingerprint.hashString
      guard let existing = profiles[key] else { return nil }

      // Check if profile should be expired due to fingerprint changes
      if shouldExpireProfile(existing, newFingerprint: fingerprint) {
        profiles.removeValue(forKey: key)
        saveProfiles()
        return nil
      }

      // If shouldUpdate is true, update the lastUpdated timestamp
      if shouldUpdate {
        var updated = existing
        updated = LearnedProfile(
          fingerprint: existing.fingerprint,
          fingerprintHash: existing.fingerprintHash,
          created: existing.created,
          lastUpdated: Date(),
          sampleCount: existing.sampleCount,
          optimalChunkSize: existing.optimalChunkSize,
          avgHandshakeMs: existing.avgHandshakeMs,
          optimalIoTimeoutMs: existing.optimalIoTimeoutMs,
          optimalInactivityTimeoutMs: existing.optimalInactivityTimeoutMs,
          p95ReadThroughputMBps: existing.p95ReadThroughputMBps,
          p95WriteThroughputMBps: existing.p95WriteThroughputMBps,
          successRate: existing.successRate,
          hostEnvironment: existing.hostEnvironment
        )
        profiles[key] = updated
        saveProfiles()
      }

      return existing
    }
  }

  /// Removes expired profiles based on TTL and inactivity
  public func cleanupExpired() {
    queue.sync {
      let now = Date()
      let ttlCutoff = now.addingTimeInterval(TimeInterval(-ttlDays * 24 * 60 * 60))
      let inactivityCutoff = now.addingTimeInterval(TimeInterval(-inactivityDays * 24 * 60 * 60))

      profiles = profiles.filter { _, profile in
        // Keep if created within TTL period
        profile.created > ttlCutoff
          // And accessed within inactivity period
          && profile.lastUpdated > inactivityCutoff
      }
      saveProfiles()
    }
  }

  /// Expires profiles that match old fingerprint but have changed bcdDevice
  public func expireProfilesForOldFirmware(
    oldFingerprint: MTPDeviceFingerprint, newBcdDevice: String?
  ) {
    queue.sync {
      profiles = profiles.filter { key, profile in
        // Keep profiles that don't match the old fingerprint
        if profile.fingerprint.hashString != oldFingerprint.hashString {
          return true
        }

        // Or if bcdDevice hasn't changed
        if profile.fingerprint.bcdDevice == newBcdDevice {
          return true
        }

        // Otherwise expire this profile
        return false
      }
      saveProfiles()
    }
  }

  private func loadProfiles() {
    do {
      let data = try Data(contentsOf: storageURL)
      let decoder = JSONDecoder()
      let container = try decoder.decode([String: LearnedProfile].self, from: data)
      profiles = container
    } catch {
      // If file doesn't exist or is corrupted, start with empty profiles
      profiles = [:]
    }
  }

  private func saveProfiles() {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(profiles)
      try data.write(to: storageURL)
    } catch {
      // Log error but don't crash - learned profiles are not critical
      if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
        print("Warning: Failed to save learned profiles: \(error)")
      }
    }
  }

  private func evictOldProfiles() {
    // Keep the most recently updated profiles
    let sorted = profiles.sorted { $0.value.lastUpdated > $1.value.lastUpdated }
    let prefix = Array(sorted.prefix(maxProfiles))
    profiles = Dictionary(uniqueKeysWithValues: prefix)
  }
}
