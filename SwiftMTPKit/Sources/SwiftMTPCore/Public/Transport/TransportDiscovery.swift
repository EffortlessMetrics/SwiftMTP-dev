// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Protocol for transport layer device discovery implementations
public protocol TransportDiscoveryProtocol {
    static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                      onDetach: @escaping (MTPDeviceID) -> Void)
}

/// Core transport discovery interface that transport layers extend to provide device discovery
public struct TransportDiscovery {
    /// Start device discovery with the specified attach/detach handlers
    /// This is extended by concrete transport implementations (USB, Bluetooth, etc.)
    public static func start(onAttach: @escaping (MTPDeviceSummary) -> Void,
                             onDetach: @escaping (MTPDeviceID) -> Void) {
        // For now, this is a no-op - transport layers should implement their own discovery
        // The CLI will call the transport-specific discovery directly
    }
}
