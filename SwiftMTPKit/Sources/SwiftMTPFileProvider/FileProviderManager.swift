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
        // Domain ID should be stable device fingerprint
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
            try await NSFileProviderManager.remove(domainID)
            log.info("Unregistered FileProvider domain for ID: \(device.fingerprint)")
        } catch {
            log.error("Failed to unregister FileProvider domain for ID: \(device.fingerprint): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Unregisters all SwiftMTP domains
    public func unregisterAllDomains() async {
        let domains = await NSFileProviderManager.allDomains
        for domain in domains {
            // Check if it's our domain (simple check for now)
            // In a real app, we'd use a specific identifier prefix or metadata
            try? await NSFileProviderManager.remove(domain.identifier)
        }
    }
}
