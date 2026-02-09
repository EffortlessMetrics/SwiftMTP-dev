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
    await manager.configureLibUSBSupport()

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

    let filter = DeviceFilter(
        vid: parseDeviceIdentifier(flags.targetVID),
        pid: parseDeviceIdentifier(flags.targetPID),
        bus: flags.targetBus,
        address: flags.targetAddress
    )
    let hasExplicitFilter = filter.vid != nil || filter.pid != nil || filter.bus != nil || filter.address != nil

    let selectedDevice: MTPDeviceSummary
    switch selectDevice(devices, filter: filter, noninteractive: true) {
    case .selected(let device):
        selectedDevice = device
    case .none:
        if hasExplicitFilter {
            log("No connected MTP device matched \(describeFilter(filter)).")
            logDeviceCandidates(devices)
        }
        throw MTPError.transport(.noDevice)
    case .multiple(let matches):
        logDeviceCandidates(matches)
        if hasExplicitFilter {
            throw MTPError.preconditionFailed(
                "multiple devices matched the filter; narrow selection with --bus/--address"
            )
        }
        log("Using device [1]. Specify --vid/--pid or --bus/--address to select another.")
        selectedDevice = matches[0]
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

@inline(__always)
private func parseDeviceIdentifier(_ raw: String?) -> UInt16? {
    guard let raw else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if value.hasPrefix("0x") || value.hasPrefix("0X") {
        return UInt16(value.dropFirst(2), radix: 16)
    }
    if value.range(of: "[a-fA-F]", options: .regularExpression) != nil {
        return UInt16(value, radix: 16)
    }
    return UInt16(value, radix: 10) ?? UInt16(value, radix: 16)
}

private func describeFilter(_ filter: DeviceFilter) -> String {
    var parts: [String] = []
    if let vid = filter.vid { parts.append(String(format: "vid=%04x", vid)) }
    if let pid = filter.pid { parts.append(String(format: "pid=%04x", pid)) }
    if let bus = filter.bus { parts.append("bus=\(bus)") }
    if let address = filter.address { parts.append("address=\(address)") }
    return parts.joined(separator: ", ")
}

private func logDeviceCandidates(_ devices: [MTPDeviceSummary]) {
    guard !devices.isEmpty else { return }
    log("Found \(devices.count) MTP device(s):")
    for (index, device) in devices.enumerated() {
        let vid = String(format: "%04x", device.vendorID ?? 0)
        let pid = String(format: "%04x", device.productID ?? 0)
        let busAddr = "\(device.bus ?? 0):\(device.address ?? 0)"
        log("  [\(index + 1)] \(device.manufacturer) \(device.model)  vid:pid=\(vid):\(pid)  bus:addr=\(busAddr)")
    }
}
