// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

// Extension to add computed properties to MTPEvent for easier access
extension MTPEvent {
    var code: UInt16 {
        switch self {
        case .objectAdded(_):
            return 0x4002
        case .objectRemoved(_):
            return 0x4003
        case .storageInfoChanged(_):
            return 0x400C
        }
    }

    var parameters: [UInt32] {
        switch self {
        case .objectAdded(let handle):
            return [handle]
        case .objectRemoved(let handle):
            return [handle]
        case .storageInfoChanged(let storageId):
            return [storageId.raw]
        }
    }
}

// Central place to open a real device using CLI flags / filters.
struct OpenedDevice: Sendable {
    let summary: MTPDeviceSummary
    let device: any MTPDevice
}

enum DeviceOpenError: Error, Sendable {
    case noneMatched(available: [MTPDeviceSummary])
    case ambiguous(matches: [MTPDeviceSummary])
}

@Sendable
func openFilteredDevice(
    filter: DeviceFilter,
    noninteractive: Bool,
    strict: Bool,
    safe: Bool
) async throws -> OpenedDevice {

    // Enumerate devices via libusb (already used by your `usb-dump` & probe paths)
    let candidates = try await LibUSBDiscovery.enumerateMTPDevices()

    // Re-use the existing selection logic you already expose to the CLI
    switch selectDevice(from: candidates, filter: filter, noninteractive: noninteractive) {
    case .selected(let summary):
        // Open via transport + manager. Your DeviceActor handles quirks/learned internally.
        let transport = LibUSBTransportFactory.createTransport()

        // Build a base config; tuning/hook phases get applied in DeviceActor.openIfNeeded()
        var config = SwiftMTPConfig()
        if safe {
            // Safe mode: conservative chunk + long timeouts.
            config.transferChunkBytes = 128 * 1024
            config.ioTimeoutMs        = max(config.ioTimeoutMs, 30_000)
        }
        // Note: strict mode is respected inside your open path (no quirks/learned);
        // The flag is passed via environment or manager (see below).
        if strict { setenv("SWIFTMTP_STRICT", "1", 1) }
        if safe   { setenv("SWIFTMTP_SAFE",   "1", 1) }

        let device = try await MTPDeviceManager.shared.openDevice(
            with: summary,
            transport: transport,
            config: config
        )

        // Compat shim you already added; ensures OpenSession + stabilization + hooks run.
        try await device.openIfNeeded()

        return OpenedDevice(summary: summary, device: device)

    case .none:
        throw DeviceOpenError.noneMatched(available: [])

    case .multiple(let matches):
        throw DeviceOpenError.ambiguous(matches: matches)
    }
}

// Helper function to select device from candidates based on filter
enum SelectionOutcome {
    case selected(MTPDeviceSummary)
    case none
    case multiple([MTPDeviceSummary])
}

func selectDevice(from candidates: [MTPDeviceSummary], filter: DeviceFilter, noninteractive: Bool) -> SelectionOutcome {
    let filtered = candidates.filter { d in
        if let v = filter.vid, d.vendorID != v { return false }
        if let p = filter.pid, d.productID != p { return false }
        if let b = filter.bus, let db = d.bus, b != db { return false }
        if let a = filter.address, let da = d.address, a != da { return false }
        return true
    }
    if filtered.isEmpty { return .none }
    if filtered.count == 1 { return .selected(filtered[0]) }
    return noninteractive ? .multiple(filtered) : .multiple(filtered) // in interactive, you prompt
}
