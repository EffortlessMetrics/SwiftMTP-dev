// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Central coordinator managing per-device `DeviceService` instances.
///
/// Listens to `MTPDeviceManager` attach/detach streams and maintains
/// a registry of active device services and their orchestrators.
///
/// The registry does NOT own `DeviceIndexOrchestrator` instances directly —
/// those are created by the host app layer that has access to `SwiftMTPIndex`.
/// Instead, orchestrators are registered externally via `registerOrchestrator`.
public actor DeviceServiceRegistry {
    private var services: [MTPDeviceID: DeviceService] = [:]
    private var orchestratorHandles: [MTPDeviceID: AnyObject] = [:]
    private var monitorTask: Task<Void, Never>?

    /// Maps ephemeral MTPDeviceID → stable domainId (UUID).
    private var domainMap: [MTPDeviceID: String] = [:]
    /// Reverse map: domainId → ephemeral MTPDeviceID (for XPC lookups).
    private var reverseDomainMap: [String: MTPDeviceID] = [:]

    public init() {}

    /// Get the device service for a given device.
    public func service(for deviceId: MTPDeviceID) -> DeviceService? {
        services[deviceId]
    }

    /// Register an orchestrator handle for a device.
    /// The orchestrator is stored as AnyObject to avoid importing SwiftMTPIndex.
    public func registerOrchestrator(_ orchestrator: AnyObject, for deviceId: MTPDeviceID) {
        orchestratorHandles[deviceId] = orchestrator
    }

    /// Get the orchestrator handle for a device.
    public func orchestrator(for deviceId: MTPDeviceID) -> AnyObject? {
        orchestratorHandles[deviceId]
    }

    /// Register a device service.
    public func register(deviceId: MTPDeviceID, service: DeviceService) {
        services[deviceId] = service
    }

    // MARK: - Domain Mapping

    /// Register the mapping from ephemeral device ID to stable domainId.
    public func registerDomainMapping(deviceId: MTPDeviceID, domainId: String) {
        domainMap[deviceId] = domainId
        reverseDomainMap[domainId] = deviceId
    }

    /// Look up the stable domainId for an ephemeral device ID.
    public func domainId(for deviceId: MTPDeviceID) -> String? {
        domainMap[deviceId]
    }

    /// Look up the ephemeral device ID for a stable domainId (used by XPC).
    public func deviceId(for domainId: String) -> MTPDeviceID? {
        reverseDomainMap[domainId]
    }

    /// Start monitoring device attach/detach events.
    /// - Parameters:
    ///   - manager: The device manager to monitor.
    ///   - onAttach: Called when a device is attached. Should set up transport, service, orchestrator.
    ///   - onDetach: Called when a device is detached. Should stop crawling, cancel ops.
    public func startMonitoring(
        manager: MTPDeviceManager,
        onAttach: @Sendable @escaping (MTPDeviceSummary, DeviceServiceRegistry) async -> Void,
        onDetach: @Sendable @escaping (MTPDeviceID, DeviceServiceRegistry) async -> Void
    ) {
        let registry = self
        monitorTask = Task {
            // Monitor attachments
            async let attachTask: Void = {
                let stream = await manager.attachedStream
                for await summary in stream {
                    await onAttach(summary, registry)
                }
            }()

            // Monitor detachments
            async let detachTask: Void = {
                let stream = await manager.detachedStream
                for await deviceId in stream {
                    if let svc = await registry.service(for: deviceId) {
                        await svc.markDisconnected()
                    }
                    await onDetach(deviceId, registry)
                }
            }()

            _ = await (attachTask, detachTask)
        }
    }

    /// Stop monitoring.
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Handle device detach: mark disconnected but keep service for cached reads.
    public func handleDetach(deviceId: MTPDeviceID) async {
        if let svc = services[deviceId] {
            await svc.markDisconnected()
        }
        // Don't remove — cache is still usable
    }

    /// Handle reconnect: re-enable service.
    public func handleReconnect(deviceId: MTPDeviceID) async {
        if let svc = services[deviceId] {
            await svc.markReconnected()
        }
    }

    /// Remove a device entirely (e.g., after extended absence).
    public func remove(deviceId: MTPDeviceID) {
        services.removeValue(forKey: deviceId)
        orchestratorHandles.removeValue(forKey: deviceId)
        if let domainId = domainMap.removeValue(forKey: deviceId) {
            reverseDomainMap.removeValue(forKey: domainId)
        }
    }
}
