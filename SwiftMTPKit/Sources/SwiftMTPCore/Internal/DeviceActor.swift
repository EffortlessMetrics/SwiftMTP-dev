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
    static func execute(_ phase: String, tuning: EffectiveTuning, link: any MTPLink) async throws {
        for hook in tuning.hooks {
            if hook.phase.rawValue == phase {
                if let delay = hook.delayMs, delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                }
            }
        }
    }
}

struct UserOverrides {
    static nonisolated(unsafe) var current: [String: String] = [:]
}

public actor MTPDeviceActor: MTPDevice, @unchecked Sendable {
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

    public func getMTPLinkIfAvailable() -> (any MTPLink)? {
        return mtpLink
    }

    public var info: MTPDeviceInfo {
        get async throws {
            if let deviceInfo {
                return deviceInfo
            }

            let link = try await self.getMTPLink()
            let realInfo = try await link.getDeviceInfo()
            self.deviceInfo = realInfo
            return realInfo
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
                        return try await link.getObjectInfos(storage: storage, parent: parent, format: nil)
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
      let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
      if debugEnabled { print("   [Actor] applyTuningAndOpenSession starting...") }

      // 1) Build fingerprint from USB IDs and interface details
      _ = try await self.buildFingerprint()

      // 2) Load quirks DB and learned profile
      if debugEnabled { print("   [Actor] Loading quirks DB...") }
      let qdb = try QuirkDatabase.load()
      let learnedKey = "\(summary.vendorID ?? 0):\(summary.productID ?? 0)"
      let learnedStored = LearnedStore.load(key: learnedKey)

      // 3) Probing capabilities (deferred until after OpenSession)
      let caps: [String: Bool] = [:] // Default until open

      // 4) Parse user overrides (env)
      let (userOverrides, _) = UserOverride.fromEnvironment()
      var overrides: [String: String] = [:]
      if let maxChunk = userOverrides.maxChunkBytes { overrides["maxChunkBytes"] = String(maxChunk) }
      if let ioTimeout = userOverrides.ioTimeoutMs { overrides["ioTimeoutMs"] = String(ioTimeout) }
      if let handshakeTimeout = userOverrides.handshakeTimeoutMs { overrides["handshakeTimeoutMs"] = String(handshakeTimeout) }
      if let inactivityTimeout = userOverrides.inactivityTimeoutMs { overrides["inactivityTimeoutMs"] = String(inactivityTimeout) }
      if let overallDeadline = userOverrides.overallDeadlineMs { overrides["overallDeadlineMs"] = String(overallDeadline) }
      if let stabilize = userOverrides.stabilizeMs { overrides["stabilizeMs"] = String(stabilize) }

      // 5) Convert learned profile
      var learnedTuning: EffectiveTuning?
      if let stored = learnedStored {
        learnedTuning = EffectiveTuning(
          maxChunkBytes: stored.maxChunkBytes,
          ioTimeoutMs: stored.ioTimeoutMs,
          handshakeTimeoutMs: stored.handshakeTimeoutMs,
          inactivityTimeoutMs: stored.inactivityTimeoutMs,
          overallDeadlineMs: stored.overallDeadlineMs,
          stabilizeMs: 0,
          resetOnOpen: false,
          disableEventPump: false,
          operations: [:],
          hooks: []
        )
      }

      // 6) Find matching quirk
      let quirk = qdb.match(
        vid: summary.vendorID ?? 0,
        pid: summary.productID ?? 0,
        bcdDevice: nil,
        ifaceClass: nil,
        ifaceSubclass: nil,
        ifaceProtocol: nil
      )
      if debugEnabled, let q = quirk { print("   [Actor] Matched quirk: \(q.id)") }

      // 7) Build initial effective tuning
      let initialTuning = EffectiveTuningBuilder.build(
        capabilities: [:],
        learned: learnedTuning,
        quirk: quirk,
        overrides: overrides.isEmpty ? nil : overrides
      )
      self.apply(initialTuning)

      // 8) Run hooks: postOpenUSB
      if debugEnabled { print("   [Actor] Running postOpenUSB hooks...") }
      try await self.runHook(.postOpenUSB, tuning: initialTuning)

      // 9) Open session + stabilization
      if debugEnabled { print("   [Actor] Opening MTP session...") }
      try await link.openSession(id: 1)
      if initialTuning.stabilizeMs > 0 {
        if debugEnabled { print("   [Actor] Stabilizing for \(initialTuning.stabilizeMs)ms...") }
        try await Task.sleep(nanoseconds: UInt64(initialTuning.stabilizeMs) * 1_000_000)
      }

      // 10) Hooks after session
      if debugEnabled { print("   [Actor] Running postOpenSession hooks...") }
      try await self.runHook(.postOpenSession, tuning: initialTuning)

      // 11) Probe capabilities NOW that session is open
      if debugEnabled { print("   [Actor] Probing capabilities (post-open)...") }
      let realCaps: [String: Bool] = [
        "partialRead": await self.capabilityPartialRead(),
        "partialWrite": await self.capabilityPartialWrite(),
        "supportsEvents": await self.capabilityEvents()
      ]
      
      // Re-build tuning with real capabilities
      let finalTuning = EffectiveTuningBuilder.build(
        capabilities: realCaps,
        learned: learnedTuning,
        quirk: quirk,
        overrides: overrides.isEmpty ? nil : overrides
      )
      self.apply(finalTuning)

      // 12) Start event pump
      if realCaps["supportsEvents"] == true { 
        if debugEnabled { print("   [Actor] Starting event pump...") }
        try await self.startEventPump() 
      }

      // 13) Record success
      LearnedStore.update(key: learnedKey, obs: finalTuning)
      if debugEnabled { print("   [Actor] applyTuningAndOpenSession complete.") }
    }


    // MARK: - Helper Methods

    public func getMTPLink() async throws -> any MTPLink {
        if let link = mtpLink {
            return link
        }

        let link = try await transport.open(summary, config: config)
        self.mtpLink = link
        return link
    }

    // MARK: - Tuning and Capability Methods

    private func buildFingerprint() async throws -> MTPDeviceFingerprint {
        // Build fingerprint from USB IDs and interface details
        let interfaceTripleData = try JSONSerialization.data(withJSONObject: ["class": "06", "subclass": "01", "protocol": "01"])
        let endpointAddressesData = try JSONSerialization.data(withJSONObject: ["input": "81", "output": "01", "event": "82"])
        let interfaceTriple = try JSONDecoder().decode(InterfaceTriple.self, from: interfaceTripleData)
        let endpointAddresses = try JSONDecoder().decode(EndpointAddresses.self, from: endpointAddressesData)

        return MTPDeviceFingerprint(
            vid: String(format: "%04x", summary.vendorID ?? 0),
            pid: String(format: "%04x", summary.productID ?? 0),
            interfaceTriple: interfaceTriple,
            endpointAddresses: endpointAddresses
        )
    }

    private func capabilityPartialRead() async -> Bool {
        // Probe for partial read capability
        // This would typically involve testing the device
        return true // Default assumption for now
    }

    private func capabilityPartialWrite() async -> Bool {
        // Probe for partial write capability
        // This would typically involve testing the device
        return true // Default assumption for now
    }

    private func capabilityEvents() async -> Bool {
        // Check if device supports events
        do {
            let deviceInfo = try await self.info
            return !deviceInfo.eventsSupported.isEmpty
        } catch {
            return false
        }
    }

    private func apply(_ tuning: EffectiveTuning) {
        // Apply tuning to config
        self.config.apply(tuning)
    }

    private func runHook(_ phase: QuirkHook.Phase, tuning: EffectiveTuning) async throws {
        // Run hooks for the specified phase
        try await QuirkHooks.execute(phase.rawValue, tuning: tuning, link: try await getMTPLink())
    }

    private func startEventPump() async throws {
        // Start event pump if supported
        if let link = try await getMTPLinkIfAvailable() {
            try eventPump.startIfAvailable(on: link)
        }
    }

}

extension MTPDeviceActor {
  public func delete(handle: MTPObjectHandle, recursive: Bool) async throws {
    try await openIfNeeded()
    if recursive, let children = try? await listAllChildren(of: handle) {
      for kid in children { try await delete(handle: kid, recursive: true) }
    }
    let link = try await getMTPLink()
    try await link.deleteObject(handle: handle) // wraps opcode 0x100B
  }

  public func move(handle: MTPObjectHandle, to parent: MTPObjectHandle?, storage: MTPStorageID?) async throws {
    try await openIfNeeded()
    let link = try await getMTPLink()
    // MoveObject (0x1019): params = [handle, storage, parent?]
    try await link.moveObject(handle: handle, to: storage ?? MTPStorageID(raw: 0xFFFFFFFF), parent: parent)
  }


  private func listAllChildren(of parent: MTPObjectHandle) async throws -> [MTPObjectHandle] {
    let storageID = MTPStorageID(raw: 0xFFFFFFFF) // Use all storages
    var allInfos: [MTPObjectInfo] = []
    for try await batch in self.list(parent: parent, in: storageID) {
      allInfos.append(contentsOf: batch)
    }
    return allInfos.map { $0.handle }
  }
}