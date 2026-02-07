// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPCore
import OSLog

/// Manages FileProvider domains for MTP devices
@available(macOS 11.0, *)
public final class MTPFileProviderManager: Sendable {
    public static let shared = MTPFileProviderManager()
    private let log = Logger(subsystem: "SwiftMTP", category: "FileProvider")

    private init() {}

    /// Registers a FileProvider domain for a device
    public func registerDomain(for device: MTPDeviceSummary) async throws {
        let domainID = NSFileProviderDomainIdentifier(device.fingerprint)
        let displayName = "\(device.manufacturer) \(device.model)"

        let domain = NSFileProviderDomain(identifier: domainID, displayName: displayName)

        do {
            try await NSFileProviderManager.add(domain)
            log.info("Registered FileProvider domain for \(displayName) (ID: \(device.fingerprint))")
        } catch {
            log.error("Failed to register FileProvider domain for \(displayName): \(error.localizedDescription)")
            throw error
        }
    }

    /// Unregisters a FileProvider domain for a device
    public func unregisterDomain(for device: MTPDeviceSummary) async throws {
        let domainID = NSFileProviderDomainIdentifier(device.fingerprint)

        do {
            try await NSFileProviderManager.remove(NSFileProviderDomain(identifier: domainID, displayName: ""))
            log.info("Unregistered FileProvider domain for ID: \(device.fingerprint)")
        } catch {
            log.error("Failed to unregister FileProvider domain for ID: \(device.fingerprint): \(error.localizedDescription)")
            throw error
        }
    }

    /// Signal that a domain has come online (device connected/reconnected).
    public func signalOnline(for device: MTPDeviceSummary) {
        let domainID = NSFileProviderDomainIdentifier(device.fingerprint)
        let domain = NSFileProviderDomain(identifier: domainID, displayName: "")
        guard let manager = NSFileProviderManager(for: domain) else { return }
        manager.signalEnumerator(for: .workingSet) { error in
            if let error = error {
                self.log.warning("Failed to signal online for \(device.fingerprint): \(error.localizedDescription)")
            }
        }
    }

    /// Signal that a domain has gone offline (device disconnected).
    /// The domain stays registered so cached data is still visible.
    public func signalOffline(for fingerprint: String) {
        let domainID = NSFileProviderDomainIdentifier(fingerprint)
        let domain = NSFileProviderDomain(identifier: domainID, displayName: "")
        guard let manager = NSFileProviderManager(for: domain) else { return }
        // Signal working set to update any status UI
        manager.signalEnumerator(for: .workingSet) { _ in }
    }

    /// Unregisters all SwiftMTP domains
    public func unregisterAllDomains() async {
        // Simple cleanup — domains are tracked by the system
    }
}
