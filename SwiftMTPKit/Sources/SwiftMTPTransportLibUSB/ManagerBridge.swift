// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore

// Extend the core TransportDiscovery to provide the libusb implementation
extension SwiftMTPCore.TransportDiscovery {
    public static func start(onAttach: @escaping (MTPDeviceSummary)->Void,
                             onDetach: @escaping (MTPDeviceID)->Void) {
        USBDeviceWatcher.start(onAttach: onAttach, onDetach: onDetach)
    }
}

// Extend MTPDeviceManager to provide LibUSB-specific implementations
extension SwiftMTPCore.MTPDeviceManager {
    /// Get a snapshot of currently connected real MTP devices using LibUSB.
    public func currentRealDevices() async throws -> [SwiftMTPCore.MTPDeviceSummary] {
        try await LibUSBDiscovery.enumerateMTPDevices()
    }

    /// Open the first available real MTP device using LibUSB transport.
    public func openFirstRealDevice() async throws -> any SwiftMTPCore.MTPDevice {
        let present = try await currentRealDevices()
        guard let summary = present.first else {
            throw SwiftMTPCore.TransportError.noDevice
        }

        let transport = LibUSBTransportFactory.createTransport()
        let currentConfig = getConfig()
        return try await openDevice(with: summary, transport: transport, config: currentConfig)
    }
}
