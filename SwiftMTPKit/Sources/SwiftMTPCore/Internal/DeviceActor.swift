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

        // Start polling loop
        while !Task.isCancelled {
            do {
                // Poll for events (this is a simplified implementation)
                // In a real implementation, you'd read from the event endpoint
                try await Task.sleep(nanoseconds: 1_000_000_000) // Poll every second

                // For now, we don't yield any events since event reading isn't fully implemented
                // This would need to be implemented in the USB transport layer
            } catch {
                break
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
        try await link.openUSBIfNeeded()
        try await link.openSession(id: 1)
        sessionOpen = true

        // Apply stabilization delay if configured (e.g., for Xiaomi devices)
        if config.stabilizeMs > 0 {
            let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
            if debugEnabled {
                print("⏱️  Waiting \(config.stabilizeMs)ms for device stabilization…")
            }
            try? await Task.sleep(nanoseconds: UInt64(config.stabilizeMs) * 1_000_000)
        }
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
