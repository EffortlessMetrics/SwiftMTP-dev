// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore
import Observation

@Observable @MainActor
public final class DeviceViewModel {
    private let coordinator: DeviceLifecycleCoordinator

    /// All discovered MTP devices — forwarded from coordinator.
    public var devices: [MTPDeviceSummary] {
        coordinator.discoveredDevices
    }

    /// The currently selected device — forwarded from coordinator.
    public var selectedDevice: (any MTPDevice)? {
        get { coordinator.selectedDevice }
        set { coordinator.selectedDevice = newValue }
    }

    /// Whether a device connection is in progress.
    public var isConnecting: Bool {
        coordinator.isConnecting
    }

    /// Last error — forwarded from coordinator.
    public var error: String? {
        get { coordinator.error }
        set { coordinator.error = newValue }
    }

    public init(coordinator: DeviceLifecycleCoordinator) {
        self.coordinator = coordinator
    }

    /// Start discovery and full lifecycle wiring via the coordinator.
    public func startDiscovery() async throws {
        try await coordinator.bootstrap()
    }

    /// Select a device for viewing. The device is already opened by the coordinator.
    public func connect(to summary: MTPDeviceSummary) async {
        await coordinator.selectDevice(summary)
    }
}
