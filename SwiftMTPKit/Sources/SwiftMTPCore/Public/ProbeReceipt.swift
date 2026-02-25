// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPQuirks

/// Structured diagnostic record of everything that happened during
/// device probing, session establishment, and capability negotiation.
public struct ProbeReceipt: Sendable, Codable {
  /// When the probe started.
  public let timestamp: Date

  /// Basic device identification.
  public let deviceSummary: ReceiptDeviceSummary

  /// Device fingerprint used for quirk matching.
  public let fingerprint: MTPDeviceFingerprint

  /// Interface probe results (from Phase 1 probe ladder).
  public var interfaceProbe: InterfaceProbeResult?

  /// Session establishment outcome.
  public var sessionEstablishment: SessionProbeResult?

  /// Probed device capabilities.
  public var capabilities: [String: Bool] = [:]

  /// Which fallback strategy won for each operation type.
  public var fallbackResults: [String: String] = [:]

  /// Summary of the resolved policy.
  public var resolvedPolicy: PolicySummary?

  /// Total time from start to end of probe in milliseconds.
  public var totalProbeTimeMs: Int = 0

  public init(
    timestamp: Date = Date(),
    deviceSummary: ReceiptDeviceSummary,
    fingerprint: MTPDeviceFingerprint
  ) {
    self.timestamp = timestamp
    self.deviceSummary = deviceSummary
    self.fingerprint = fingerprint
  }
}

/// Lightweight device info for the receipt (avoids duplicating full MTPDeviceSummary).
public struct ReceiptDeviceSummary: Sendable, Codable {
  public let id: String
  public let manufacturer: String
  public let model: String
  public let vendorID: String?
  public let productID: String?

  public init(from summary: MTPDeviceSummary) {
    self.id = summary.id.raw
    self.manufacturer = summary.manufacturer
    self.model = summary.model
    self.vendorID = summary.vendorID.map { String(format: "0x%04x", $0) }
    self.productID = summary.productID.map { String(format: "0x%04x", $0) }
  }
}

/// Result of the interface probe ladder.
public struct InterfaceProbeResult: Sendable, Codable {
  /// How many candidates were evaluated.
  public var candidatesEvaluated: Int = 0
  /// Which interface number was selected.
  public var selectedInterface: Int?
  /// Score of the selected interface.
  public var selectedScore: Int?
  /// Class/subclass/protocol of selected interface.
  public var selectedClass: String?
  /// Whether device-info was cached from probe.
  public var deviceInfoCached: Bool = false
  /// Individual attempt results.
  public var attempts: [InterfaceAttemptResult] = []
  /// Reason for selecting this interface.
  public var selectionReason: String?
  /// Interfaces that were skipped and why.
  public var skippedAlternatives: [SkippedInterface] = []

  public init() {}
}

/// Record of a skipped interface candidate for diagnostics.
public struct SkippedInterface: Sendable, Codable {
  public let interfaceNumber: Int
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  public let score: Int
  public let reason: String

  public init(
    interfaceNumber: Int, interfaceClass: UInt8, interfaceSubclass: UInt8, interfaceProtocol: UInt8,
    score: Int, reason: String
  ) {
    self.interfaceNumber = interfaceNumber
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.score = score
    self.reason = reason
  }
}

/// Per-interface attempt result for diagnostics.
public struct InterfaceAttemptResult: Sendable, Codable {
  public let interfaceNumber: Int
  public let score: Int
  public let succeeded: Bool
  public let durationMs: Int
  public let error: String?

  public init(
    interfaceNumber: Int, score: Int, succeeded: Bool, durationMs: Int, error: String? = nil
  ) {
    self.interfaceNumber = interfaceNumber
    self.score = score
    self.succeeded = succeeded
    self.durationMs = durationMs
    self.error = error
  }
}

/// Session establishment outcome.
public struct SessionProbeResult: Sendable, Codable {
  public var succeeded: Bool = false
  public var requiredRetry: Bool = false
  public var durationMs: Int = 0
  public var error: String?
  public var firstFailure: String?
  public var recoveryAction: String?
  public var resetAttempted: Bool = false
  public var resetError: String?

  public init() {}
}

/// Summary of the resolved policy for diagnostic output.
public struct PolicySummary: Sendable, Codable {
  public let maxChunkBytes: Int
  public let ioTimeoutMs: Int
  public let handshakeTimeoutMs: Int
  public let resetOnOpen: Bool
  public let disableEventPump: Bool
  public let enumerationStrategy: String
  public let readStrategy: String
  public let writeStrategy: String

  public init(from policy: DevicePolicy) {
    self.maxChunkBytes = policy.tuning.maxChunkBytes
    self.ioTimeoutMs = policy.tuning.ioTimeoutMs
    self.handshakeTimeoutMs = policy.tuning.handshakeTimeoutMs
    self.resetOnOpen = policy.flags.resetOnOpen
    self.disableEventPump = policy.flags.disableEventPump
    self.enumerationStrategy = policy.fallbacks.enumeration.rawValue
    self.readStrategy = policy.fallbacks.read.rawValue
    self.writeStrategy = policy.fallbacks.write.rawValue
  }
}
