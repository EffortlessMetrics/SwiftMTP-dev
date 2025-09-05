// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

public actor MTPDeviceActor: MTPDevice {
    public let id: MTPDeviceID
    private let transport: any MTPTransport
    private let summary: MTPDeviceSummary
    private let config: SwiftMTPConfig
    private var deviceInfo: MTPDeviceInfo?
    private var mtpLink: (any MTPLink)?
    private var sessionOpen = false
    let transferJournal: (any TransferJournal)?

    public init(id: MTPDeviceID, summary: MTPDeviceSummary, transport: MTPTransport, config: SwiftMTPConfig = .init(), transferJournal: (any TransferJournal)? = nil) {
        self.id = id
        self.summary = summary
        self.transport = transport
        self.config = config
        self.transferJournal = transferJournal
    }

    public var info: MTPDeviceInfo {
        get async throws {
            if let deviceInfo {
                return deviceInfo
            }

            // For mock devices, return the mock device info
            // For real devices, this would parse the actual MTP DeviceInfo response
            let mtpDeviceInfo = MTPDeviceInfo(
                manufacturer: summary.manufacturer,
                model: summary.model,
                version: "Mock Version 1.0",
                serialNumber: "MOCK123456",
                operationsSupported: Set([0x1001, 0x1002, 0x1004, 0x1005]), // Basic operations
                eventsSupported: Set([0x4002, 0x4003]) // Basic events
            )

            self.deviceInfo = mtpDeviceInfo
            return mtpDeviceInfo
        }
    }

    public func storages() async throws -> [MTPStorageInfo] {
        try await openIfNeeded()
        return try await BusyBackoff.onDeviceBusy {
            let link = try await self.getMTPLink()
            let ids = try await link.getStorageIDs()
            return try await withThrowingTaskGroup(of: MTPStorageInfo.self) { g in
                for id in ids { g.addTask { try await link.getStorageInfo(id: id) } }
                var out = [MTPStorageInfo](); out.reserveCapacity(ids.count)
                for try await s in g { out.append(s) }
                return out
            }
        }
    }


    public nonisolated func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<[MTPObjectInfo], Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await openIfNeeded()
                    let items: [MTPObjectInfo] = try await BusyBackoff.onDeviceBusy {
                        let link = try await self.getMTPLink()
                        let handles = try await link.getObjectHandles(storage: storage, parent: parent)
                        return try await link.getObjectInfos(handles)
                    }
                    continuation.yield(items)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        try await openIfNeeded()
        let link = try await getMTPLink()
        return try await link.getObjectInfos([handle])[0]
    }

    // Note: read/write methods are implemented in DeviceActor+Transfer.swift

    public func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {
        try await openIfNeeded()
        let link = try await getMTPLink()

        // Get object info to check if it's a directory
        let objectInfo = try await link.getObjectInfos([handle])[0]

        // Check if it's a directory (format code 0x3001 = Association/Directory)
        let isDirectory = objectInfo.formatCode == 0x3001

        if isDirectory && recursive {
            // Recursively delete directory contents first
            let contents = try await link.getObjectHandles(storage: objectInfo.storage, parent: handle)
            for childHandle in contents {
                try await delete(childHandle, recursive: true)
            }
        }

        // Delete the object itself
        try await BusyBackoff.onDeviceBusy {
            try await link.deleteObject(handle: handle)
        }
    }

    public func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws {
        try await openIfNeeded()
        let link = try await getMTPLink()

        // Get object info to determine storage
        let objectInfo = try await link.getObjectInfos([handle])[0]

        // Move the object
        try await BusyBackoff.onDeviceBusy {
            try await link.moveObject(handle: handle, to: objectInfo.storage, parent: newParent)
        }
    }

    public nonisolated var events: AsyncStream<MTPEvent> {
        AsyncStream { continuation in
            Task {
                await self.startEventPolling(continuation: continuation)
            }
        }
    }

    private func startEventPolling(continuation: AsyncStream<MTPEvent>.Continuation) async {
        // Only poll events if we have an event endpoint
        guard await getMTPLinkIfAvailable() != nil else {
            continuation.finish()
            return
        }

        // Check if device supports events
        do {
            let deviceInfo = try await self.info
            guard !deviceInfo.eventsSupported.isEmpty else {
                continuation.finish()
                return
            }
        } catch {
            continuation.finish()
            return
        }

        // Start event pump in the transport layer
        // Note: Event pump will be started when the transport is opened
        // if it supports event streaming

        // Process events from the transport
        let eventStream = AsyncStream<Data> { cont in
            // This would be connected to the transport's event stream
            // For now, we'll use a placeholder
        }

        // Process incoming events
        for await eventData in eventStream {
            if let event = MTPEvent.fromRaw(eventData) {
                continuation.yield(event)
            }
        }

        continuation.finish()
    }

    private func getMTPLinkIfAvailable() async -> (any MTPLink)? {
        if let link = mtpLink {
            return link
        }
        return nil
    }

    // MARK: - Session Management

    /// Open device session if not already open, with optional stabilization delay.
    internal func openIfNeeded() async throws {
        guard !sessionOpen else { return }
        let link = try await getMTPLink()

        // Extract USB IDs for fingerprinting
        let usbIDs = try await extractUSBIDs(link: link)

        // Load and apply effective tuning
        let effectiveTuning = try await buildEffectiveTuning(usbIDs: usbIDs)

        // Update config with effective tuning
        var updatedConfig = config
        updatedConfig.transferChunkBytes = effectiveTuning.maxChunkBytes
        updatedConfig.ioTimeoutMs = effectiveTuning.ioTimeoutMs
        updatedConfig.handshakeTimeoutMs = effectiveTuning.handshakeTimeoutMs
        updatedConfig.inactivityTimeoutMs = effectiveTuning.inactivityTimeoutMs
        updatedConfig.overallDeadlineMs = effectiveTuning.overallDeadlineMs
        updatedConfig.stabilizeMs = effectiveTuning.stabilizeMs

        try await link.openUSBIfNeeded()
        try await link.openSession(id: 1)
        sessionOpen = true

        // Apply stabilization delay if configured
        if effectiveTuning.stabilizeMs > 0 {
            let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
            if debugEnabled {
                print("⏱️  Waiting \(effectiveTuning.stabilizeMs)ms for device stabilization…")
            }
            try? await Task.sleep(nanoseconds: UInt64(effectiveTuning.stabilizeMs) * 1_000_000)
        }

        // Honor quirk hooks
        for hook in effectiveTuning.hooks where hook.phase == .postOpenSession {
            if let delayMs = hook.delayMs {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }

        // TODO: Update learned profile with successful tuning
        // LearnedStore.update(key: usbIDs.key, obs: effectiveTuning)
    }

    private func extractUSBIDs(link: any MTPLink) async throws -> (vid: UInt16, pid: UInt16, bcdDevice: UInt16?, ifaceClass: UInt8?, ifaceSubclass: UInt8?, ifaceProtocol: UInt8?, key: String) {
        // Extract USB IDs from device summary if available
        if let vid = summary.vendorID, let pid = summary.productID {
            // Use interface defaults for MTP (class 0x06, subclass 0x01, protocol 0x01)
            let key = String(format: "%04x:%04x:06-01-01", vid, pid)
            return (vid, pid, nil, 0x06, 0x01, 0x01, key)
        }

        // Fallback for other transports
        return (0, 0, nil, nil, nil, nil, "unknown")
    }

    private func buildEffectiveTuning(usbIDs: (vid: UInt16, pid: UInt16, bcdDevice: UInt16?, ifaceClass: UInt8?, ifaceSubclass: UInt8?, ifaceProtocol: UInt8?, key: String)) async throws -> EffectiveTuning {
        // Load capabilities (simplified - in practice this would probe the device)
        let capabilities: [String: Bool] = ["partialRead": true, "partialWrite": true]

        // TODO: Load learned profile
        let learned: EffectiveTuning? = nil // LearnedStore.load(key: usbIDs.key).map { ... }

        // Load static quirk
        let db = try? QuirkDatabase.load()
        let quirk = db?.match(
            vid: usbIDs.vid,
            pid: usbIDs.pid,
            bcdDevice: usbIDs.bcdDevice,
            ifaceClass: usbIDs.ifaceClass,
            ifaceSubclass: usbIDs.ifaceSubclass,
            ifaceProtocol: usbIDs.ifaceProtocol
        )

        // Parse user overrides from environment
        let overrides = ProcessInfo.processInfo.environment["SWIFTMTP_OVERRIDES"]
            .flatMap { parseOverrides($0) }

        // Build effective tuning
        return EffectiveTuningBuilder.build(
            capabilities: capabilities,
            learned: learned,
            quirk: quirk,
            overrides: overrides
        )
    }

    private func parseOverrides(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    // MARK: - Helper Methods

    internal func getMTPLink() async throws -> any MTPLink {
        if let link = mtpLink {
            return link
        }

        let link = try await transport.open(summary, config: config)
        self.mtpLink = link
        return link
    }

}
