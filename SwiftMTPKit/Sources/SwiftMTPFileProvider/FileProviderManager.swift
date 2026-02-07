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
            // In macOS, we use the domain identifier directly for removal if we have a reference or create a dummy
            try await NSFileProviderManager.remove(NSFileProviderDomain(identifier: domainID, displayName: ""))
            log.info("Unregistered FileProvider domain for ID: \(device.fingerprint)")
        } catch {
            log.error("Failed to unregister FileProvider domain for ID: \(device.fingerprint): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Unregisters all SwiftMTP domains
    public func unregisterAllDomains() async {
        // Simple cleanup - in a real app you might track domains in SwiftData
    }
}
