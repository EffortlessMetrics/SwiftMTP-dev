// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import Foundation

extension MTPDeviceManager {
    /// Get the current real devices, excluding mocks
    public func currentRealDevices() async throws -> [MTPDeviceSummary] {
        let allDevices = await devices
        return allDevices.filter { summary in
            // Filter out common mock patterns if needed
            !summary.manufacturer.contains("(Demo)")
        }
    }
}

/// Helper to find and open a device based on CLI flags
@MainActor
func openDevice(flags: CLIFlags) async throws -> any MTPDevice {
    let manager = MTPDeviceManager.shared
    
    if flags.useMock {
        // Mock is handled by MTPDeviceManager yielding it during discovery
        try await manager.startDiscovery()
        let devices = await manager.devices
        guard let mock = devices.first(where: { $0.manufacturer.contains("(Demo)") }) else {
            throw MTPError.transport(.noDevice)
        }
        return try await manager.openDevice(with: mock, transport: LibUSBTransportFactory.createTransport())
    }

    let devices = try await manager.currentRealDevices()
    if devices.isEmpty {
        throw MTPError.transport(.noDevice)
    }

    let selectedDevice: MTPDeviceSummary
    if let vid = flags.targetVID, let pid = flags.targetPID {
        guard let found = devices.first(where: { 
            String(format: "%04x", $0.vendorID ?? 0) == vid.lowercased() && 
            String(format: "%04x", $0.productID ?? 0) == pid.lowercased() 
        }) else {
            throw MTPError.transport(.noDevice)
        }
        selectedDevice = found
    } else {
        selectedDevice = devices[0]
    }

    let db = (try? QuirkDatabase.load())
    let quirk = db?.match(
        vid: selectedDevice.vendorID ?? 0,
        pid: selectedDevice.productID ?? 0,
        bcdDevice: nil,
        ifaceClass: 0x06,
        ifaceSubclass: 0x01,
        ifaceProtocol: 0x01
    )

    let effectiveTuning = EffectiveTuningBuilder.build(
        capabilities: ["partialRead": true, "partialWrite": true],
        learned: nil,
        quirk: quirk,
        overrides: nil
    )

    var finalTuning = effectiveTuning
    let (userOverrides, _) = UserOverride.fromEnvironment(ProcessInfo.processInfo.environment)
    if let maxChunk = userOverrides.maxChunkBytes { finalTuning.maxChunkBytes = maxChunk }
    if let ioTimeout = userOverrides.ioTimeoutMs { finalTuning.ioTimeoutMs = ioTimeout }
    if let handshakeTimeout = userOverrides.handshakeTimeoutMs { finalTuning.handshakeTimeoutMs = handshakeTimeout }
    if let inactivityTimeout = userOverrides.inactivityTimeoutMs { finalTuning.inactivityTimeoutMs = inactivityTimeout }
    if let overallDeadline = userOverrides.overallDeadlineMs { finalTuning.overallDeadlineMs = overallDeadline }

    var config = SwiftMTPConfig()
    config.apply(finalTuning)

    return try await manager.openDevice(with: selectedDevice, transport: LibUSBTransportFactory.createTransport(), config: config)
}