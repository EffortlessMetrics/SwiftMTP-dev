// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import Observation

@Observable @MainActor
public final class DeviceViewModel {
    public var devices: [MTPDeviceSummary] = []
    public var selectedDevice: (any MTPDevice)?
    public var isConnecting = false
    public var error: String?
    
    public init() {
        // We handle auto-start in DeviceBrowserView.onAppear to avoid capturing self in init
    }
    
    public func startDiscovery() async throws {
        try await MTPDeviceManager.shared.startDiscovery()
        
        // Listen for devices
        Task { [weak self] in
            for await device in await MTPDeviceManager.shared.attachedStream {
                if let self = self {
                    await MainActor.run {
                        self.devices.append(device)
                    }
                }
            }
        }
        
        Task { [weak self] in
            for await id in await MTPDeviceManager.shared.detachedStream {
                if let self = self {
                    await MainActor.run {
                        self.devices.removeAll { $0.id == id }
                    }
                }
            }
        }
    }
    
    public func connect(to summary: MTPDeviceSummary) async {
        isConnecting = true
        error = nil
        
        do {
            let transport = LibUSBTransportFactory.createTransport()
            let device = try await MTPDeviceManager.shared.openDevice(with: summary, transport: transport)
            self.selectedDevice = device
        } catch {
            self.error = "Connection failed: \(error.localizedDescription)"
        }
        
        isConnecting = false
    }
}