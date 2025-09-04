// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Effective tuning configuration after applying all layers in merge order.
/// Merge order: defaults → capability probe → learned profile → static quirk → user override
public struct EffectiveTuning: Sendable {
    // Core timing parameters
    public var maxChunkBytes: Int
    public var ioTimeoutMs: Int
    public var handshakeTimeoutMs: Int
    public var inactivityTimeoutMs: Int
    public var overallDeadlineMs: Int
    public var stabilizeMs: Int
    public var eventPumpDelayMs: Int

    // Operation capabilities
    public var supportsGetPartialObject64: Bool
    public var supportsSendPartialObject: Bool
    public var preferGetObjectPropList: Bool
    public var disableWriteResume: Bool

    // Phase-specific hooks
    public var hooks: [Hook]

    /// Creates default tuning configuration
    public static var defaults: EffectiveTuning {
        EffectiveTuning(
            maxChunkBytes: 1_048_576,        // 1MB conservative default
            ioTimeoutMs: 10_000,             // 10s
            handshakeTimeoutMs: 6_000,       // 6s
            inactivityTimeoutMs: 8_000,      // 8s
            overallDeadlineMs: 60_000,       // 60s
            stabilizeMs: 0,                  // No delay
            eventPumpDelayMs: 0,             // No delay
            supportsGetPartialObject64: false,
            supportsSendPartialObject: false,
            preferGetObjectPropList: true,
            disableWriteResume: false,
            hooks: []
        )
    }

    /// Applies capability probe results
    public mutating func apply(_ caps: ProbedCapabilities) {
        // Adjust chunk size based on device capabilities
        if caps.supportsLargeTransfers {
            maxChunkBytes = min(maxChunkBytes * 2, 16_777_216) // Up to 16MB
        }

        // Update operation support
        supportsGetPartialObject64 = caps.supportsGetPartialObject64
        supportsSendPartialObject = caps.supportsSendPartialObject

        // Adjust timeouts based on device responsiveness
        if caps.isSlowDevice {
            ioTimeoutMs = max(ioTimeoutMs, 15_000)
            handshakeTimeoutMs = max(handshakeTimeoutMs, 10_000)
        }

        // Add hooks based on capability patterns
        if caps.needsStabilization {
            hooks.append(Hook(phase: .postOpenSession, delayMs: 500))
        }
    }

    /// Applies learned profile data
    public mutating func apply(_ learned: LearnedProfile) {
        // Apply learned optimal values if they exist and are reasonable
        if let chunk = learned.optimalChunkSize, chunk > 0 {
            maxChunkBytes = min(max(maxChunkBytes, chunk), 16_777_216)
        }

        if let handshake = learned.avgHandshakeMs, handshake > 0 {
            handshakeTimeoutMs = max(handshake * 3, handshakeTimeoutMs) // 3x the typical time
        }

        if let io = learned.optimalIoTimeoutMs, io > 0 {
            ioTimeoutMs = io
        }

        if let inactivity = learned.optimalInactivityTimeoutMs, inactivity > 0 {
            inactivityTimeoutMs = inactivity
        }

        // Only apply if learned profile has good success rate (>80%)
        guard learned.successRate > 0.8 else { return }

        // Apply throughput-based adjustments
        if let readMBps = learned.p95ReadThroughputMBps, readMBps > 10 {
            // High-throughput device - can use larger chunks
            maxChunkBytes = min(maxChunkBytes * 2, 16_777_216)
        }
    }

    /// Applies static quirk configuration
    public mutating func apply(_ quirk: QuirkRule) {
        // Apply tuning overrides
        if let chunk = quirk.tuning.maxChunkBytes {
            maxChunkBytes = chunk
        }
        if let io = quirk.tuning.ioTimeoutMs {
            ioTimeoutMs = io
        }
        if let handshake = quirk.tuning.handshakeTimeoutMs {
            handshakeTimeoutMs = handshake
        }
        if let inactivity = quirk.tuning.inactivityTimeoutMs {
            inactivityTimeoutMs = inactivity
        }
        if let overall = quirk.tuning.overallDeadlineMs {
            overallDeadlineMs = overall
        }
        if let stabilize = quirk.tuning.stabilizeMs {
            stabilizeMs = stabilize
        }
        if let event = quirk.tuning.eventPumpDelayMs {
            eventPumpDelayMs = event
        }

        // Apply operation overrides
        if let partial64 = quirk.ops.supportsGetPartialObject64 {
            supportsGetPartialObject64 = partial64
        }
        if let partialSend = quirk.ops.supportsSendPartialObject {
            supportsSendPartialObject = partialSend
        }
        if let preferList = quirk.ops.preferGetObjectPropList {
            preferGetObjectPropList = preferList
        }
        if let disableResume = quirk.ops.disableWriteResume {
            disableWriteResume = disableResume
        }

        // Apply hooks
        hooks.append(contentsOf: quirk.hooks)
    }

    /// Applies user overrides
    public mutating func apply(_ override: UserOverride) {
        // User overrides take precedence over everything
        if let chunk = override.maxChunkBytes {
            maxChunkBytes = chunk
        }
        if let io = override.ioTimeoutMs {
            ioTimeoutMs = io
        }
        if let handshake = override.handshakeTimeoutMs {
            handshakeTimeoutMs = handshake
        }
        if let inactivity = override.inactivityTimeoutMs {
            inactivityTimeoutMs = inactivity
        }
        if let overall = override.overallDeadlineMs {
            overallDeadlineMs = overall
        }
        if let stabilize = override.stabilizeMs {
            stabilizeMs = stabilize
        }
    }

    /// Converts to SwiftMTPConfig for use with existing code
    public func toConfig() -> SwiftMTPConfig {
        var config = SwiftMTPConfig()
        config.transferChunkBytes = maxChunkBytes
        config.ioTimeoutMs = ioTimeoutMs
        config.handshakeTimeoutMs = handshakeTimeoutMs
        config.inactivityTimeoutMs = inactivityTimeoutMs
        config.overallDeadlineMs = overallDeadlineMs
        config.stabilizeMs = stabilizeMs
        config.resumeEnabled = !disableWriteResume
        return config
    }

    /// Gets all hooks for a specific phase
    public func hooksForPhase(_ phase: Hook.Phase) -> [Hook] {
        hooks.filter { $0.phase == phase }
    }

    /// Describes the effective configuration for debugging
    public func describe() -> String {
        """
        Effective Configuration:
          Chunk Size: \(formatBytes(maxChunkBytes))
          I/O Timeout: \(ioTimeoutMs)ms
          Handshake Timeout: \(handshakeTimeoutMs)ms
          Inactivity Timeout: \(inactivityTimeoutMs)ms
          Overall Deadline: \(overallDeadlineMs)ms
          Stabilization: \(stabilizeMs)ms
          Partial Read: \(supportsGetPartialObject64)
          Partial Write: \(supportsSendPartialObject)
          Hooks: \(hooks.count) configured
        """
    }

    private func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

/// Capabilities discovered through device probing
public struct ProbedCapabilities: Sendable {
    public let supportsLargeTransfers: Bool
    public let supportsGetPartialObject64: Bool
    public let supportsSendPartialObject: Bool
    public let isSlowDevice: Bool
    public let needsStabilization: Bool

    public init(
        supportsLargeTransfers: Bool = false,
        supportsGetPartialObject64: Bool = false,
        supportsSendPartialObject: Bool = false,
        isSlowDevice: Bool = false,
        needsStabilization: Bool = false
    ) {
        self.supportsLargeTransfers = supportsLargeTransfers
        self.supportsGetPartialObject64 = supportsGetPartialObject64
        self.supportsSendPartialObject = supportsSendPartialObject
        self.isSlowDevice = isSlowDevice
        self.needsStabilization = needsStabilization
    }
}

/// Static quirk rule loaded from configuration
public struct QuirkRule: Sendable {
    public let id: String
    public let match: DeviceMatch
    public let tuning: TuningConfig
    public let hooks: [Hook]
    public let ops: OperationConfig
    public let confidence: String
    public let status: String

    public init(
        id: String,
        match: DeviceMatch,
        tuning: TuningConfig,
        hooks: [Hook] = [],
        ops: OperationConfig,
        confidence: String,
        status: String
    ) {
        self.id = id
        self.match = match
        self.tuning = tuning
        self.hooks = hooks
        self.ops = ops
        self.confidence = confidence
        self.status = status
    }
}

/// Device matching criteria for quirks
public struct DeviceMatch: Sendable, Codable {
    public let vid: String?
    public let pid: String?
    public let deviceInfoRegex: String?
    public let iface: InterfaceMatch?
    public let endpoints: EndpointMatch?

    public init(
        vid: String? = nil,
        pid: String? = nil,
        deviceInfoRegex: String? = nil,
        iface: InterfaceMatch? = nil,
        endpoints: EndpointMatch? = nil
    ) {
        self.vid = vid
        self.pid = pid
        self.deviceInfoRegex = deviceInfoRegex
        self.iface = iface
        self.endpoints = endpoints
    }
}

/// Interface matching criteria
public struct InterfaceMatch: Sendable, Codable {
    public let `class`: String?
    public let subclass: String?
    public let `protocol`: String?

    public init(class: String? = nil, subclass: String? = nil, protocol: String? = nil) {
        self.`class` = `class`
        self.subclass = subclass
        self.`protocol` = `protocol`
    }
}

/// Endpoint matching criteria
public struct EndpointMatch: Sendable, Codable {
    public let input: String?
    public let output: String?
    public let event: String?

    public init(input: String? = nil, output: String? = nil, event: String? = nil) {
        self.input = input
        self.output = output
        self.event = event
    }
}

/// Tuning configuration values
public struct TuningConfig: Sendable, Codable {
    public let maxChunkBytes: Int?
    public let ioTimeoutMs: Int?
    public let handshakeTimeoutMs: Int?
    public let inactivityTimeoutMs: Int?
    public let overallDeadlineMs: Int?
    public let stabilizeMs: Int?
    public let eventPumpDelayMs: Int?

    public init(
        maxChunkBytes: Int? = nil,
        ioTimeoutMs: Int? = nil,
        handshakeTimeoutMs: Int? = nil,
        inactivityTimeoutMs: Int? = nil,
        overallDeadlineMs: Int? = nil,
        stabilizeMs: Int? = nil,
        eventPumpDelayMs: Int? = nil
    ) {
        self.maxChunkBytes = maxChunkBytes
        self.ioTimeoutMs = ioTimeoutMs
        self.handshakeTimeoutMs = handshakeTimeoutMs
        self.inactivityTimeoutMs = inactivityTimeoutMs
        self.overallDeadlineMs = overallDeadlineMs
        self.stabilizeMs = stabilizeMs
        self.eventPumpDelayMs = eventPumpDelayMs
    }
}

/// Operation capability configuration
public struct OperationConfig: Sendable, Codable {
    public let supportsGetPartialObject64: Bool?
    public let supportsSendPartialObject: Bool?
    public let preferGetObjectPropList: Bool?
    public let disableWriteResume: Bool?

    public init(
        supportsGetPartialObject64: Bool? = nil,
        supportsSendPartialObject: Bool? = nil,
        preferGetObjectPropList: Bool? = nil,
        disableWriteResume: Bool? = nil
    ) {
        self.supportsGetPartialObject64 = supportsGetPartialObject64
        self.supportsSendPartialObject = supportsSendPartialObject
        self.preferGetObjectPropList = preferGetObjectPropList
        self.disableWriteResume = disableWriteResume
    }
}

/// User-specified overrides (highest precedence)
public struct UserOverride: Sendable {
    public let maxChunkBytes: Int?
    public let ioTimeoutMs: Int?
    public let handshakeTimeoutMs: Int?
    public let inactivityTimeoutMs: Int?
    public let overallDeadlineMs: Int?
    public let stabilizeMs: Int?

    public init(
        maxChunkBytes: Int? = nil,
        ioTimeoutMs: Int? = nil,
        handshakeTimeoutMs: Int? = nil,
        inactivityTimeoutMs: Int? = nil,
        overallDeadlineMs: Int? = nil,
        stabilizeMs: Int? = nil
    ) {
        self.maxChunkBytes = maxChunkBytes
        self.ioTimeoutMs = ioTimeoutMs
        self.handshakeTimeoutMs = handshakeTimeoutMs
        self.inactivityTimeoutMs = inactivityTimeoutMs
        self.overallDeadlineMs = overallDeadlineMs
        self.stabilizeMs = stabilizeMs
    }

    /// Parses overrides from environment variable format: "key1=value1,key2=value2"
    public static func fromEnvironment(_ envValue: String?) -> UserOverride? {
        guard let envValue = envValue else { return nil }

        var overrides = [String: String]()
        for pair in envValue.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                overrides[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        return UserOverride(
            maxChunkBytes: overrides["maxChunkBytes"].flatMap(Int.init),
            ioTimeoutMs: overrides["ioTimeoutMs"].flatMap(Int.init),
            handshakeTimeoutMs: overrides["handshakeTimeoutMs"].flatMap(Int.init),
            inactivityTimeoutMs: overrides["inactivityTimeoutMs"].flatMap(Int.init),
            overallDeadlineMs: overrides["overallDeadlineMs"].flatMap(Int.init),
            stabilizeMs: overrides["stabilizeMs"].flatMap(Int.init)
        )
    }
}

/// Phase-specific hook for timing and retry logic
public struct Hook: Sendable {
    public enum Phase: String, Sendable {
        case postOpenUSB
        case postClaimInterface
        case postOpenSession
        case beforeGetDeviceInfo
        case beforeGetStorageIDs
        case beforeTransfer
        case afterTransfer
        case onDeviceBusy
    }

    public let phase: Phase
    public let delayMs: Int?
    public let busyBackoff: MTPBusyBackoff?

    public init(phase: Phase, delayMs: Int? = nil, busyBackoff: MTPBusyBackoff? = nil) {
        self.phase = phase
        self.delayMs = delayMs
        self.busyBackoff = busyBackoff
    }
}

/// Backoff strategy for DEVICE_BUSY responses
public struct MTPBusyBackoff: Sendable {
    public let retries: Int
    public let baseMs: Int
    public let jitterPct: Double

    public init(retries: Int, baseMs: Int, jitterPct: Double) {
        self.retries = retries
        self.baseMs = baseMs
        self.jitterPct = jitterPct
    }

    /// Calculates the delay for a specific retry attempt
    public func delayForAttempt(_ attempt: Int) -> Int {
        let exponential = baseMs * (1 << min(attempt, 10)) // Cap at 2^10 multiplier
        let jitter = Int(Double(exponential) * jitterPct * Double.random(in: -1.0...1.0))
        return max(exponential + jitter, 100) // Minimum 100ms
    }
}
