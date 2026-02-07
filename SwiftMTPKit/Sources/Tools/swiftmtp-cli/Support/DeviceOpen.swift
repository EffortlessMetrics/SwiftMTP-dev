// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks

// Import the LibUSB transport to get the extended MTPDeviceManager methods
import struct SwiftMTPTransportLibUSB.LibUSBTransportFactory

@MainActor
public func openDevice(flags: CLIFlags) async throws -> any MTPDevice {
    if flags.useMock {
        throw MTPError.notSupported("Mock transport not available")
    }

    let devices = try await MTPDeviceManager.shared.currentRealDevices()
    let filter = DeviceFilter(
        vid: flags.targetVID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
        pid: flags.targetPID.flatMap { UInt16($0, radix: 16) ?? UInt16($0) },
        bus: flags.targetBus,
        address: flags.targetAddress
    )
    let selection = selectDevice(devices, filter: filter, noninteractive: false)
    let selectedDevice: MTPDeviceSummary
    switch selection {
    case .selected(let device):
        selectedDevice = device
    case .none:
        throw MTPError.notSupported("No device matches filter")
    case .multiple:
        throw MTPError.notSupported("Multiple devices match filter")
    }

    let db = (try? QuirkDatabase.load())
    let fp = DeviceFingerprint(
        vid: selectedDevice.vendorID ?? 0,
        pid: selectedDevice.productID ?? 0,
        bcdDevice: nil as UInt16?,
        ifaceClass: 0x06,
        ifaceSubClass: 0x01,
        ifaceProtocol: 0x01
    )
    _ = db?.bestMatch(for: fp)

    let effectiveTuning = SwiftMTPCore.EffectiveTuningBuilder.build(
        capabilities: ["partialRead": true, "partialWrite": true],
        learned: nil,
        quirk: nil, // TODO: Properly map QuirkEntry to DeviceQuirk
        overrides: nil
    )

    var finalTuning = effectiveTuning
    let (userOverrides, _) = SwiftMTPCore.UserOverride.fromEnvironment(ProcessInfo.processInfo.environment)
    if let maxChunk = userOverrides.maxChunkBytes { finalTuning.maxChunkBytes = maxChunk }
    if let ioTimeout = userOverrides.ioTimeoutMs { finalTuning.ioTimeoutMs = ioTimeout }
    if let handshakeTimeout = userOverrides.handshakeTimeoutMs { finalTuning.handshakeTimeoutMs = handshakeTimeout }
    if let inactivityTimeout = userOverrides.inactivityTimeoutMs { finalTuning.inactivityTimeoutMs = inactivityTimeout }
    if let overallDeadline = userOverrides.overallDeadlineMs { finalTuning.overallDeadlineMs = overallDeadline }

    var config = SwiftMTPConfig()
    config.apply(finalTuning)

    return try await MTPDeviceManager.shared.openDevice(with: selectedDevice, transport: LibUSBTransportFactory.createTransport(), config: config)
}
