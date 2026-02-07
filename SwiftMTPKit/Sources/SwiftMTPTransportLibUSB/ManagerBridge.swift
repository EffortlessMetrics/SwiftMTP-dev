// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import CLibusb
import Foundation

// Extend the core TransportDiscovery to provide the libusb implementation
extension SwiftMTPCore.TransportDiscovery {
    public static func start(onAttach: @escaping (MTPDeviceSummary)->Void,
                             onDetach: @escaping (MTPDeviceID)->Void) {
        USBDeviceWatcher.start(onAttach: onAttach, onDetach: onDetach)
    }
}

// Extend MTPDeviceManager to provide LibUSB-specific implementations
extension SwiftMTPCore.MTPDeviceManager {
    
    public func currentRealDevices() async throws -> [MTPDevice] {
        let summaries = try await LibUSBDiscovery.enumerateMTPDevices()
        var devices: [MTPDevice] = []
        
        for summary in summaries {
            // We use the shared transport and current config
            let transport = LibUSBTransport()
            if let device = try? await openDevice(with: summary, transport: transport, config: getConfig()) {
                devices.append(device)
            }
        }
        return devices
    }

    /// Open the first available real MTP device using LibUSB transport.
    public func openFirstRealDevice() async throws -> any SwiftMTPCore.MTPDevice {
        let present = try await currentRealDevices()
        guard let summary = present.first?.summary else {
            throw SwiftMTPCore.TransportError.noDevice
        }

        let transport = LibUSBTransport()
        let currentConfig = getConfig()
        return try await openDevice(with: summary, transport: transport, config: currentConfig)
    }
}
