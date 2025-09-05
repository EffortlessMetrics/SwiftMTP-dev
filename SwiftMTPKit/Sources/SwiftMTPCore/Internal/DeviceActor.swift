// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

// Placeholder types - these should be implemented elsewhere
struct EventPump {
    func startIfAvailable(on link: any MTPLink) throws {
        // Implementation needed
    }
}

struct QuirkHooks {
    static func execute(_ phase: String, tuning: Any, link: any MTPLink) async throws {
        // Implementation needed
    }
}

struct UserOverrides {
    static nonisolated(unsafe) var current: [String: String] = [:]
}

public actor MTPDeviceActor: MTPDevice {
    public let id: MTPDeviceID
    private let transport: any MTPTransport
    private let summary: MTPDeviceSummary
    private var config: SwiftMTPConfig
    private var deviceInfo: MTPDeviceInfo?
    private var mtpLink: (any MTPLink)?
    private var sessionOpen = false
    let transferJournal: (any TransferJournal)?
    private var probedCapabilities: [String: Bool] = [:]
    private var eventPump: EventPump = EventPump()

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
        try await applyTuningAndOpenSession(link: link)
        sessionOpen = true
    }

    private func applyTuningAndOpenSession(link: any MTPLink) async throws {
      // 1) fingerprint (from discovery summary populated with USBIDs)
      let fp = self.summary.fingerprint // includes vid/pid/bcd/iface triple

      // 2) load databases
      let quirks = try QuirkDatabase.load()
      let learned = LearnedStore.load(key: fp)

      // 3) capability probe (you likely already computed)
      let caps = self.probedCapabilities

      // 4) merge to effective tuning
      let tuning = EffectiveTuningBuilder.build(
        capabilities: caps,
        learned: learned,
        quirk: quirks.match(fingerprint: fp),
        overrides: UserOverrides.current // from env
      )

      // 5) apply to config (timeouts, chunk sizes, flags)
      self.config.apply(tuning)

      // 6) pre‑open hooks that run before OpenSession if any
      try await QuirkHooks.execute(.postOpenUSB, tuning: tuning, link: link)

      // 7) open session
      try link.openSession(sessionID: 1)

      // 8) post‑open stabilization
      if self.config.stabilizeMs > 0 {
        try await Task.sleep(nanoseconds: UInt64(self.config.stabilizeMs) * 1_000_000)
      }

      // 9) hooks that must run after OpenSession
      try await QuirkHooks.execute(.postOpenSession, tuning: tuning, link: link)

      // 10) event pump (start only after session — avoids Xiaomi wedge)
      try self.eventPump.startIfAvailable(on: link)

      // 11) successful session → update learned profile
      try await LearnedProfileStore.shared.recordSuccess(for: fp, using: tuning)
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

extension MTPDeviceActor {
  public func delete(handle: MTPObjectHandle, recursive: Bool) async throws {
    try await openIfNeeded()
    if recursive, let children = try? await listAllChildren(of: handle) {
      for kid in children { try await delete(handle: kid, recursive: true) }
    }
    let link = try await getMTPLink()
    try await link.deleteObject(handle) // wraps opcode 0x100B
  }

  public func move(handle: MTPObjectHandle, to parent: MTPObjectHandle?, storage: MTPStorageID?) async throws {
    try await openIfNeeded()
    let link = try await getMTPLink()
    // MoveObject (0x1019): params = [handle, parent?, storage?]
    try await link.moveObject(handle: handle, newParent: parent ?? 0xFFFFFFFF, newStorage: storage ?? 0xFFFFFFFF)
  }


  private func listAllChildren(of parent: MTPObjectHandle) async throws -> [MTPObjectHandle] {
    let infos = try await self.list(parent: parent, in: 0xFFFFFFFF).collect() // adapt to your stream API
    return infos.map { $0.handle }
  }
}
