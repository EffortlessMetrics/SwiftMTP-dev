// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Observation
import FileProvider
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPIndex
import SwiftMTPQuirks
import SwiftMTPXPC
import SwiftMTPFileProvider

/// Central integration hub that wires device discovery, identity resolution,
/// index orchestration, XPC service, and File Provider domain lifecycle.
///
/// This is the **sole consumer** of `MTPDeviceManager`'s attach/detach streams.
/// UI layers observe this coordinator's `@Observable` state instead of
/// consuming the streams directly.
@MainActor @Observable
public final class DeviceLifecycleCoordinator {

    // MARK: - Observable State

    /// All discovered MTP devices (updated on attach/detach).
    public private(set) var discoveredDevices: [MTPDeviceSummary] = []

    /// Devices that have been opened and fully wired (identity resolved, indexing started).
    public private(set) var openedDevices: [MTPDeviceID: StableDeviceIdentity] = [:]

    /// The currently selected device for UI display.
    public var selectedDevice: (any MTPDevice)?

    /// Whether a device connection is in progress.
    public private(set) var isConnecting = false

    /// Last error encountered during lifecycle operations.
    public var error: String?

    // MARK: - Internal Components

    private let manager: MTPDeviceManager
    private let registry = DeviceServiceRegistry()
    private var liveIndex: SQLiteLiveIndex?
    private var contentCache: ContentCache?
    private var fpService: MTPDeviceService?
    private var xpcListener: MTPXPCListener?
    private var orchestrators: [String: DeviceIndexOrchestrator] = [:]
    private var changeSignalers: [String: ChangeSignaler] = [:]
    private var bootstrapped = false

    public init(manager: MTPDeviceManager = .shared) {
        self.manager = manager
    }

    // MARK: - Bootstrap

    /// One-time initialization. Safe to call multiple times (no-ops after first).
    public func bootstrap() async throws {
        guard !bootstrapped else { return }
        bootstrapped = true

        // Wire manager discovery/opening to the libusb backend.
        await manager.configureLibUSBSupport()

        // 1. Start USB discovery
        try await manager.startDiscovery()

        // 2. Open live index (read-write for host app)
        let index = try SQLiteLiveIndex.appGroupIndex(readOnly: false)
        self.liveIndex = index

        // 3. Create content cache sharing the same SQLiteDB
        let cache = ContentCache.standard(db: index.database)
        self.contentCache = cache

        // 4. Create File Provider domain lifecycle service
        let service = MTPDeviceService()
        self.fpService = service

        // 5. Create and configure XPC service
        let xpcImpl = MTPXPCServiceImpl(deviceManager: manager)
        xpcImpl.registry = registry

        // Wire crawl boost handler: look up orchestrator from coordinator's local dict
        xpcImpl.crawlBoostHandler = { [weak self] deviceId, storageId, parentHandle in
            guard let self else { return false }
            let orchestrator = await MainActor.run { self.orchestrators[deviceId] }
            if let orchestrator {
                await orchestrator.boostSubtree(storageId: storageId, parentHandle: parentHandle)
                return true
            }
            return false
        }

        let listener = MTPXPCListener(serviceImpl: xpcImpl)
        listener.start()
        listener.startTempFileCleanupTimer()
        self.xpcListener = listener

        // 6. Start monitoring — sole consumer of attach/detach streams
        await registry.startMonitoring(
            manager: manager,
            onAttach: { [weak self] summary, _ in
                guard let self else { return }
                await self.handleAttach(summary: summary)
            },
            onDetach: { [weak self] deviceId, _ in
                guard let self else { return }
                await self.handleDetach(deviceId: deviceId)
            }
        )
    }

    // MARK: - Attach

    private func handleAttach(summary: MTPDeviceSummary) async {
        // Update discovered devices list
        if !discoveredDevices.contains(where: { $0.id == summary.id }) {
            discoveredDevices.append(summary)
        }

        guard let liveIndex, let contentCache, let fpService else { return }

        do {
            // 1. Build identity signals from summary
            let signals = DeviceIdentitySignals(
                vendorId: summary.vendorID,
                productId: summary.productID,
                usbSerial: summary.usbSerial,
                mtpSerial: nil, // Not available until device is opened
                manufacturer: summary.manufacturer,
                model: summary.model
            )

            // 2. Resolve stable identity
            let identity = try await liveIndex.resolveIdentity(signals: signals)

            // 3. Build quirk-aware config
            let db = try? QuirkDatabase.load()
            let quirk = db?.match(
                vid: summary.vendorID ?? 0,
                pid: summary.productID ?? 0,
                bcdDevice: nil,
                ifaceClass: 0x06,
                ifaceSubclass: 0x01,
                ifaceProtocol: 0x01
            )
            let effectiveTuning = EffectiveTuningBuilder.build(
                capabilities: ["partialRead": true, "partialWrite": true],
                learned: nil,
                quirk: quirk,
                overrides: nil
            )
            var config = SwiftMTPConfig()
            config.apply(effectiveTuning)

            // 4. Open device with transport and quirk-aware config
            let transport = LibUSBTransportFactory.createTransport()
            let device = try await manager.openDevice(with: summary, transport: transport, config: config)

            // 5. Upgrade identity key with MTP serial if available
            let info = try await device.info
            if let mtpSerial = info.serialNumber, !mtpSerial.isEmpty {
                try await liveIndex.updateMTPSerial(domainId: identity.domainId, mtpSerial: mtpSerial)
            }

            // 6. Register DeviceService in registry
            let deviceService = DeviceService(device: device)
            await registry.register(deviceId: summary.id, service: deviceService)

            // 7. Map ephemeral ID ↔ stable domainId
            await registry.registerDomainMapping(deviceId: summary.id, domainId: identity.domainId)

            // 8. Create and start index orchestrator
            let orchestrator = DeviceIndexOrchestrator(
                deviceId: identity.domainId,
                liveIndex: liveIndex,
                contentCache: contentCache
            )
            await registry.registerOrchestrator(orchestrator, for: summary.id)
            orchestrators[identity.domainId] = orchestrator

            // 9. Wire ChangeSignaler into orchestrator's onChange callback
            let signaler = ChangeSignaler(
                domainIdentifier: NSFileProviderDomainIdentifier(rawValue: identity.domainId)
            )
            changeSignalers[identity.domainId] = signaler

            await orchestrator.setOnChange { [signaler] deviceId, parentHandles in
                // parentHandles is Set<MTPObjectHandle?> — signal all affected parents
                // storageId isn't directly available here; signaler uses deviceId-level signaling
                signaler.signalParents(deviceId: deviceId, storageId: 0, parentHandles: parentHandles)
            }

            await orchestrator.start(device: device)

            // 10. Notify File Provider
            await fpService.deviceAttached(identity: identity)

            // 11. Update observable state
            openedDevices[summary.id] = identity

            // Auto-select the first device
            if selectedDevice == nil {
                selectedDevice = device
            }

        } catch {
            self.error = "Failed to set up device \(summary.manufacturer) \(summary.model): \(error.localizedDescription)"
        }
    }

    // MARK: - Detach

    private func handleDetach(deviceId: MTPDeviceID) async {
        // Remove from discovered list
        discoveredDevices.removeAll { $0.id == deviceId }

        // Get stable domainId before cleanup
        let domainId = await registry.domainId(for: deviceId)

        // Stop orchestrator
        if let domainId, let orchestrator = orchestrators[domainId] {
            await orchestrator.stop()
            orchestrators.removeValue(forKey: domainId)
            changeSignalers.removeValue(forKey: domainId)
        }

        // Signal File Provider offline (keep domain registered for cache)
        if let domainId, let fpService {
            await fpService.deviceDetached(domainId: domainId)
        }

        // Clean up selected device if it was the detached one
        if selectedDevice?.id == deviceId {
            selectedDevice = nil
        }

        // Remove from opened devices
        openedDevices.removeValue(forKey: deviceId)
    }

    // MARK: - Public API

    /// Connect to a specific device (for UI selection).
    /// The device is already opened by the coordinator; this just selects it.
    public func selectDevice(_ summary: MTPDeviceSummary) async {
        if let svc = await registry.service(for: summary.id) {
            selectedDevice = await svc.underlyingDevice
        }
    }

    /// Access the device service registry (for XPC and other consumers).
    public var serviceRegistry: DeviceServiceRegistry { registry }

    /// Shut down all lifecycle components.
    public func shutdown() async {
        await registry.stopMonitoring()
        xpcListener?.stop()
        for (_, orchestrator) in orchestrators {
            await orchestrator.stop()
        }
        orchestrators.removeAll()
        changeSignalers.removeAll()
        openedDevices.removeAll()
        discoveredDevices.removeAll()
        selectedDevice = nil
    }
}
