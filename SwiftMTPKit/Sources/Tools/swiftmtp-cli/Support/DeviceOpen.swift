// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftMTPCore
import SwiftMTPTransportLibUSB
import SwiftMTPQuirks
import Foundation

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

    // Enumerate MTP devices directly via libusb (avoids hotplug-based discovery)
    let devices = try await LibUSBDiscovery.enumerateMTPDevices()
    if devices.isEmpty {
        throw MTPError.transport(.noDevice)
    }

    let selectedDevice: MTPDeviceSummary
    let hasVIDPID = flags.targetVID != nil && flags.targetPID != nil
    let hasBusAddr = flags.targetBus != nil && flags.targetAddress != nil

    if hasVIDPID {
        guard let found = devices.first(where: {
            String(format: "%04x", $0.vendorID ?? 0) == flags.targetVID!.lowercased() &&
            String(format: "%04x", $0.productID ?? 0) == flags.targetPID!.lowercased()
        }) else {
            throw MTPError.transport(.noDevice)
        }
        selectedDevice = found
    } else if hasBusAddr {
        guard let found = devices.first(where: {
            Int($0.bus ?? 0) == flags.targetBus! &&
            Int($0.address ?? 0) == flags.targetAddress!
        }) else {
            throw MTPError.transport(.noDevice)
        }
        selectedDevice = found
    } else if devices.count > 1 {
        log("Found \(devices.count) MTP devices:")
        for (i, dev) in devices.enumerated() {
            let vid = String(format: "%04x", dev.vendorID ?? 0)
            let pid = String(format: "%04x", dev.productID ?? 0)
            let busAddr = "\(dev.bus ?? 0):\(dev.address ?? 0)"
            log("  [\(i + 1)] \(dev.manufacturer) \(dev.model)  vid:pid=\(vid):\(pid)  bus:addr=\(busAddr)")
        }
        log("Using device [1]. Specify --vid/--pid or --bus/--address to select another.")
        selectedDevice = devices[0]
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