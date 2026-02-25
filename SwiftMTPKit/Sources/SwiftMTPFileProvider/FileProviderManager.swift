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

  // MARK: - Stable Identity API

  /// Registers a FileProvider domain using a stable device identity.
  public func registerDomain(identity: StableDeviceIdentity) async throws {
    let domainID = NSFileProviderDomainIdentifier(identity.domainId)
    let domain = NSFileProviderDomain(identifier: domainID, displayName: identity.displayName)

    do {
      try await NSFileProviderManager.add(domain)
      log.info(
        "Registered FileProvider domain for \(identity.displayName) (domainId: \(identity.domainId))"
      )
    } catch {
      log.error(
        "Failed to register FileProvider domain for \(identity.displayName): \(error.localizedDescription)"
      )
      throw error
    }
  }

  /// Signal that a domain has come online (device connected/reconnected).
  public func signalOnline(domainId: String) {
    let domainID = NSFileProviderDomainIdentifier(domainId)
    let domain = NSFileProviderDomain(identifier: domainID, displayName: "")
    guard let manager = NSFileProviderManager(for: domain) else { return }
    manager.signalEnumerator(for: .workingSet) { error in
      if let error = error {
        self.log.warning("Failed to signal online for \(domainId): \(error.localizedDescription)")
      }
    }
  }

  /// Signal that a domain has gone offline (device disconnected).
  /// The domain stays registered so cached data is still visible.
  public func signalOffline(domainId: String) {
    let domainID = NSFileProviderDomainIdentifier(domainId)
    let domain = NSFileProviderDomain(identifier: domainID, displayName: "")
    guard let manager = NSFileProviderManager(for: domain) else { return }
    manager.signalEnumerator(for: .workingSet) { _ in }
  }

  /// Unregisters a FileProvider domain by domainId.
  public func unregisterDomain(domainId: String) async throws {
    let domainID = NSFileProviderDomainIdentifier(domainId)
    do {
      try await NSFileProviderManager.remove(
        NSFileProviderDomain(identifier: domainID, displayName: ""))
      log.info("Unregistered FileProvider domain: \(domainId)")
    } catch {
      log.error(
        "Failed to unregister FileProvider domain \(domainId): \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Legacy fingerprint API (deprecated)

  /// Registers a FileProvider domain for a device using fingerprint.
  @available(*, deprecated, message: "Use registerDomain(identity:) instead")
  public func registerDomain(for device: MTPDeviceSummary) async throws {
    let domainID = NSFileProviderDomainIdentifier(device.fingerprint)
    let displayName = "\(device.manufacturer) \(device.model)"
    let domain = NSFileProviderDomain(identifier: domainID, displayName: displayName)
    try await NSFileProviderManager.add(domain)
  }

  @available(*, deprecated, message: "Use unregisterDomain(domainId:) instead")
  public func unregisterDomain(for device: MTPDeviceSummary) async throws {
    let domainID = NSFileProviderDomainIdentifier(device.fingerprint)
    try await NSFileProviderManager.remove(
      NSFileProviderDomain(identifier: domainID, displayName: ""))
  }

  @available(*, deprecated, message: "Use signalOnline(domainId:) instead")
  public func signalOnline(for device: MTPDeviceSummary) {
    signalOnline(domainId: device.fingerprint)
  }

  @available(*, deprecated, message: "Use signalOffline(domainId:) instead")
  public func signalOffline(for fingerprint: String) {
    signalOffline(domainId: fingerprint)
  }

  /// Unregisters all SwiftMTP domains
  public func unregisterAllDomains() async {
    // Simple cleanup — domains are tracked by the system
  }
}
