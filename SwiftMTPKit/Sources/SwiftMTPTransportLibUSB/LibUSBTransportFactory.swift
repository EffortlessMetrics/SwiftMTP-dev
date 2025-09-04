// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

public struct LibUSBTransportFactory: TransportFactory {
    public static func createTransport() -> MTPTransport {
        return LibUSBTransport()
    }
}
