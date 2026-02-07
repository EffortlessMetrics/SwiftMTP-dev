// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPCore
import OSLog

/// Bridges device attach/detach events to File Provider domain lifecycle.
///
/// Runs in the host app process:
/// - Attach → register domain → signal working set
/// - Detach → signal offline (keep domain registered for cached content)
/// - Reconnect → signal online → trigger delta crawl
/// - Extended absence (24h) → unregister domain
@available(macOS 11.0, *)
public actor MTPDeviceService {
    private let fpManager: MTPFileProviderManager
    private let log = Logger(subsystem: "SwiftMTP", category: "DeviceService")

    /// Tracks when each device was last seen, for extended-absence cleanup.
    private var lastSeen: [MTPDeviceID: Date] = [:]

    /// How long before an unseen device's domain gets unregistered.
    public var extendedAbsenceThreshold: TimeInterval = 24 * 3600 // 24 hours

    public init(fpManager: MTPFileProviderManager = .shared) {
        self.fpManager = fpManager
    }

    /// Handle device attachment.
    public func deviceAttached(_ summary: MTPDeviceSummary) async {
        lastSeen[summary.id] = Date()

        do {
            try await fpManager.registerDomain(for: summary)
            fpManager.signalOnline(for: summary)
            log.info("Device attached: \(summary.manufacturer) \(summary.model)")
        } catch {
            log.error("Failed to register domain on attach: \(error.localizedDescription)")
        }
    }

    /// Handle device detachment.
    public func deviceDetached(_ deviceId: MTPDeviceID, fingerprint: String) {
        // Keep domain registered — cached content is still available
        fpManager.signalOffline(for: fingerprint)
        log.info("Device detached: \(deviceId.raw)")
    }

    /// Handle device reconnection.
    public func deviceReconnected(_ summary: MTPDeviceSummary) async {
        lastSeen[summary.id] = Date()
        fpManager.signalOnline(for: summary)
        log.info("Device reconnected: \(summary.manufacturer) \(summary.model)")
    }

    /// Clean up domains for devices not seen within the threshold.
    public func cleanupAbsentDevices(knownDevices: [MTPDeviceSummary]) async {
        let now = Date()
        for (deviceId, lastSeenDate) in lastSeen {
            if now.timeIntervalSince(lastSeenDate) > extendedAbsenceThreshold {
                // Find matching summary to unregister
                if let summary = knownDevices.first(where: { $0.id == deviceId }) {
                    try? await fpManager.unregisterDomain(for: summary)
                    lastSeen.removeValue(forKey: deviceId)
                    log.info("Unregistered domain for absent device: \(deviceId.raw)")
                }
            }
        }
    }
}
