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
