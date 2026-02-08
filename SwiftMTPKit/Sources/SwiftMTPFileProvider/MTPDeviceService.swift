// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPCore
import OSLog

/// Bridges device attach/detach events to File Provider domain lifecycle.
///
/// Runs in the host app process:
/// - Attach → resolve identity → register domain → signal working set
/// - Detach → signal offline (keep domain registered for cached content)
/// - Reconnect → signal online → trigger delta crawl
/// - Extended absence (24h) → unregister domain
@available(macOS 11.0, *)
public actor MTPDeviceService {
    private let fpManager: MTPFileProviderManager
    private let log = Logger(subsystem: "SwiftMTP", category: "DeviceService")

    /// Tracks when each domainId was last seen, for extended-absence cleanup.
    private var lastSeen: [String: Date] = [:]

    /// How long before an unseen device's domain gets unregistered.
    public var extendedAbsenceThreshold: TimeInterval = 24 * 3600 // 24 hours

    public init(fpManager: MTPFileProviderManager = .shared) {
        self.fpManager = fpManager
    }

    /// Handle device attachment with stable identity.
    public func deviceAttached(identity: StableDeviceIdentity) async {
        lastSeen[identity.domainId] = Date()

        do {
            try await fpManager.registerDomain(identity: identity)
            fpManager.signalOnline(domainId: identity.domainId)
            log.info("Device attached: \(identity.displayName) (domainId: \(identity.domainId))")
        } catch {
            log.error("Failed to register domain on attach: \(error.localizedDescription)")
        }
    }

    /// Handle device detachment by domainId.
    public func deviceDetached(domainId: String) {
        // Keep domain registered — cached content is still available
        fpManager.signalOffline(domainId: domainId)
        log.info("Device detached: domainId=\(domainId)")
    }

    /// Handle device reconnection by domainId.
    public func deviceReconnected(domainId: String) {
        lastSeen[domainId] = Date()
        fpManager.signalOnline(domainId: domainId)
        log.info("Device reconnected: domainId=\(domainId)")
    }

    /// Clean up domains for devices not seen within the threshold.
    public func cleanupAbsentDevices() async {
        let now = Date()
        for (domainId, lastSeenDate) in lastSeen {
            if now.timeIntervalSince(lastSeenDate) > extendedAbsenceThreshold {
                try? await fpManager.unregisterDomain(domainId: domainId)
                lastSeen.removeValue(forKey: domainId)
                log.info("Unregistered domain for absent device: \(domainId)")
            }
        }
    }
}
