// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import Foundation

// Extend MTPDeviceManager to provide LibUSB-specific implementations
extension SwiftMTPCore.MTPDeviceManager {

    /// Configure libusb-backed discovery/open support for this manager instance.
    public func configureLibUSBSupport() {
        setHotplugDiscoveryStarter { onAttach, onDetach in
            USBDeviceWatcher.start(onAttach: onAttach, onDetach: onDetach)
        }
        setDiscoverySnapshotProvider {
            try await LibUSBDiscovery.enumerateMTPDevices()
        }
        setDefaultTransportFactory {
            LibUSBTransportFactory.createTransport()
        }
    }
    
    public func currentRealDevices() async throws -> [MTPDevice] {
        configureLibUSBSupport()
        let summaries = try await refreshConnectedDevices()
        var devices: [MTPDevice] = []
        let currentConfig = getConfig()
        
        for summary in summaries {
            let transport = LibUSBTransportFactory.createTransport()
            if let device = try? await openDevice(with: summary, transport: transport, config: currentConfig) {
                devices.append(device)
            }
        }
        return devices
    }

    /// Open a real device by ID from the currently connected set.
    public func openRealDevice(id: MTPDeviceID) async throws -> any SwiftMTPCore.MTPDevice {
        configureLibUSBSupport()
        _ = try await refreshConnectedDevices()
        return try await open(id)
    }

    /// Open the first available real MTP device using LibUSB transport.
    public func openFirstRealDevice() async throws -> any SwiftMTPCore.MTPDevice {
        configureLibUSBSupport()
        let summaries = try await refreshConnectedDevices()
        guard let summary = summaries.first else {
            throw SwiftMTPCore.TransportError.noDevice
        }
        return try await open(summary.id)
    }
}
