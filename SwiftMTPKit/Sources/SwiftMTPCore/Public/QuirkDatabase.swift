// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Database of device quirks loaded from configuration
public final class QuirkDatabase: Sendable {
    private let quirks: [QuirkRule]
    private let schemaVersion: String

    public init(from url: URL) throws {
        // TODO: Implement proper JSON parsing when QuirkRule becomes Codable again
        // For now, create empty database
        self.quirks = []
        self.schemaVersion = "1.0.0"
    }

    public init(with quirks: [QuirkRule], schemaVersion: String = "1.0.0") {
        self.quirks = quirks
        self.schemaVersion = schemaVersion
    }

    /// Finds the best matching quirk for a device fingerprint
    public func match(for fingerprint: MTPDeviceFingerprint) -> QuirkRule? {
        // Find quirks that match the device
        let candidates = quirks.filter { quirk in
            matches(quirk.match, fingerprint: fingerprint)
        }

        // Return the most specific match (most criteria matched)
        return candidates.max { a, b in
            specificity(of: a.match) < specificity(of: b.match)
        }
    }

    /// Gets all quirks (for debugging/analysis)
    public func allQuirks() -> [QuirkRule] {
        quirks
    }

    /// Gets quirks by status
    public func quirks(withStatus status: String) -> [QuirkRule] {
        quirks.filter { $0.status == status }
    }

    /// Validates schema version compatibility
    public func validateSchemaVersion() throws {
        let supportedVersions = ["1.0.0"]
        guard supportedVersions.contains(schemaVersion) else {
            throw QuirkDatabaseError.unsupportedSchemaVersion(schemaVersion, supportedVersions)
        }
    }

    /// Gets the current schema version
    public func getSchemaVersion() -> String {
        schemaVersion
    }

    private func matches(_ match: DeviceMatch, fingerprint: MTPDeviceFingerprint) -> Bool {
        // Check VID/PID
        if let vid = match.vid, vid != fingerprint.vid { return false }
        if let pid = match.pid, pid != fingerprint.pid { return false }

        // Check interface
        if let iface = match.iface {
            if let cls = iface.class, cls != fingerprint.interfaceTriple.class { return false }
            if let sub = iface.subclass, sub != fingerprint.interfaceTriple.subclass { return false }
            if let proto = iface.protocol, proto != fingerprint.interfaceTriple.protocol { return false }
        }

        // Check endpoints
        if let endpoints = match.endpoints {
            if let input = endpoints.input, input != fingerprint.endpointAddresses.input { return false }
            if let output = endpoints.output, output != fingerprint.endpointAddresses.output { return false }
            if let event = endpoints.event, event != fingerprint.endpointAddresses.event { return false }
        }

        // Check device info regex (if provided)
        if match.deviceInfoRegex != nil {
            // This would need device info strings - for now, skip if specified
            // In a full implementation, this would be checked against device info
        }

        return true
    }

    private func specificity(of match: DeviceMatch) -> Int {
        var score = 0
        if match.vid != nil { score += 10 }
        if match.pid != nil { score += 10 }
        if match.iface?.class != nil { score += 5 }
        if match.iface?.subclass != nil { score += 3 }
        if match.iface?.protocol != nil { score += 2 }
        if match.endpoints?.input != nil { score += 2 }
        if match.endpoints?.output != nil { score += 2 }
        if match.endpoints?.event != nil { score += 1 }
        if match.deviceInfoRegex != nil { score += 5 }
        return score
    }

}

/// Builds effective tuning by applying all layers in merge order
public final class EffectiveTuningBuilder {
    private let quirkDB: QuirkDatabase?
    private let learnedProfiles: LearnedProfileManager?
    private let userOverrides: UserOverride?

    public init(
        quirkDB: QuirkDatabase? = nil,
        learnedProfiles: LearnedProfileManager? = nil,
        userOverrides: UserOverride? = nil
    ) {
        self.quirkDB = quirkDB
        self.learnedProfiles = learnedProfiles
        self.userOverrides = userOverrides
    }

    /// Builds effective tuning for a device fingerprint and capabilities
    public func buildEffectiveTuning(
        fingerprint: MTPDeviceFingerprint,
        capabilities: ProbedCapabilities,
        strict: Bool = false,
        safe: Bool = false
    ) -> EffectiveTuning {
        var tuning = EffectiveTuning.defaults

        // Apply safe mode (overrides everything with conservative settings)
        if safe {
            tuning.maxChunkBytes = 131_072  // 128KB
            tuning.ioTimeoutMs = 30_000     // 30s
            tuning.handshakeTimeoutMs = 15_000
            tuning.inactivityTimeoutMs = 20_000
            tuning.overallDeadlineMs = 300_000 // 5min
            tuning.supportsGetPartialObject64 = false
            tuning.supportsSendPartialObject = false
            return tuning
        }

        // Layer 1: Apply capability probe results
        tuning.apply(capabilities)

        // Layer 2: Apply learned profile (skip in strict mode)
        if !strict, let learned = learnedProfiles?.profile(for: fingerprint) {
            tuning.apply(learned)
        }

        // Layer 3: Apply static quirk (skip in strict mode)
        if !strict, let quirk = quirkDB?.match(for: fingerprint) {
            tuning.apply(quirk)
        }

        // Layer 4: Apply user overrides (always applied)
        if let overrides = userOverrides {
            tuning.apply(overrides)
        }

        return tuning
    }

    /// Describes the layers applied for a specific configuration
    public func describeLayers(
        fingerprint: MTPDeviceFingerprint,
        capabilities: ProbedCapabilities,
        strict: Bool = false,
        safe: Bool = false
    ) -> String {
        var layers = ["baseline defaults -> \(EffectiveTuning.defaults.describe().components(separatedBy: "\n").last ?? "")"]

        layers.append("capability probe -> largeTransfers=\(capabilities.supportsLargeTransfers), slow=\(capabilities.isSlowDevice)")

        if !strict {
            if let learned = learnedProfiles?.profile(for: fingerprint) {
                layers.append("learned profile -> chunk=\(learned.optimalChunkSize.map { "\($0)" } ?? "none"), success=\(String(format: "%.1f%%", learned.successRate * 100))")
            } else {
                layers.append("learned profile -> (none)")
            }

            if let quirk = quirkDB?.match(for: fingerprint) {
                layers.append("quirk \(quirk.id) -> status=\(quirk.status), confidence=\(quirk.confidence)")
            } else {
                layers.append("static quirk -> (none)")
            }
        } else {
            layers.append("learned profile -> (skipped in strict mode)")
            layers.append("static quirk -> (skipped in strict mode)")
        }

        if userOverrides != nil {
            layers.append("user overrides -> (present)")
        } else {
            layers.append("user overrides -> (none)")
        }

        let effective = buildEffectiveTuning(fingerprint: fingerprint, capabilities: capabilities, strict: strict, safe: safe)
        layers.append("effective config -> \(effective.maxChunkBytes) bytes, \(effective.ioTimeoutMs)ms timeout")

        return layers.joined(separator: "\n  ")
    }
}

/// Errors that can occur when working with quirk databases
public enum QuirkDatabaseError: Error {
    case unsupportedSchemaVersion(String, [String])
    case invalidQuirkFormat(String)
    case duplicateQuirkId(String)
}
