// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog
import SwiftMTPQuirks
import SwiftMTPObservability

struct EventPump {
    func startIfAvailable(on link: any MTPLink) throws {
        // Implementation needed
    }
    func stop() {
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
    public let summary: MTPDeviceSummary
    private let transport: any MTPTransport
    private var config: SwiftMTPConfig
    private var deviceInfo: MTPDeviceInfo?
    private var mtpLink: (any MTPLink)?
    private var sessionOpen = false
    let transferJournal: (any TransferJournal)?
    public var probedCapabilities: [String: Bool] = [:]
    private var currentTuning: EffectiveTuning = .defaults()
    public var effectiveTuning: EffectiveTuning { get async { currentTuning } }
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
        let infos = try await link.getObjectInfos([handle])
        guard let info = infos.first else {
            throw MTPError.objectNotFound
        }
        return info
    }

    // Note: read/write methods are implemented in DeviceActor+Transfer.swift

    public func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {
        try await openIfNeeded()
        let link = try await getMTPLink()

        if recursive {
            // Recursively delete directory contents first
            // We use 0xFFFFFFFF to search across all storages if needed
            let contents = try await listAllChildren(of: handle)
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
        // Default to current storage
        let info = try await getInfo(handle: handle)
        try await move(handle, to: newParent, storage: info.storage)
    }

    public func move(_ handle: MTPObjectHandle, to parent: MTPObjectHandle?, storage: MTPStorageID) async throws {
        try await openIfNeeded()
        let link = try await getMTPLink()
        // MoveObject (0x1019): params = [handle, storage, parent?]
        try await BusyBackoff.onDeviceBusy {
            try await link.moveObject(handle: handle, to: storage, parent: parent)
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

        // Process incoming events (Stub for now)
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
    public func openIfNeeded() async throws {
        guard !sessionOpen else { return }
        let link = try await getMTPLink()
        try await applyTuningAndOpenSession(link: link)
        sessionOpen = true
    }

    /// Close the device session and release all underlying transport resources.
    public func devClose() async throws {
        eventPump.stop()
        
        if sessionOpen, let link = mtpLink {
            // Attempt to close session, but ignore errors if it fails
            try? await link.closeSession()
        }
        
        // Always close transport to release interface and handles
        try await transport.close()
        
        mtpLink = nil
        sessionOpen = false
    }

    public func devGetDeviceInfoUncached() async throws -> MTPDeviceInfo {
        let link = try await getMTPLink()
        return try await link.getDeviceInfo()
    }

    public func devGetStorageIDsUncached() async throws -> [MTPStorageID] {
        let link = try await getMTPLink()
        return try await link.getStorageIDs()
    }

    public func devGetRootHandlesUncached(storage: MTPStorageID) async throws -> [MTPObjectHandle] {
        let link = try await getMTPLink()
        return try await link.getObjectHandles(storage: storage, parent: nil)
    }

    public func devGetObjectInfoUncached(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        let link = try await getMTPLink()
        let infos = try await link.getObjectInfos([handle])
        guard let info = infos.first else { throw MTPError.objectNotFound }
        return info
    }

    private func applyTuningAndOpenSession(link: any MTPLink) async throws {
      let signposter = MTPLog.Signpost.enumerateSignposter
      let totalState = signposter.beginInterval("applyTuningAndOpenSession", id: signposter.makeSignpostID())
      defer { signposter.endInterval("applyTuningAndOpenSession", totalState) }

      let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
      if debugEnabled { print("   [Actor] applyTuningAndOpenSession starting...") }

      // 1) Build fingerprint from USB IDs and interface details
      let fingerprint = try await self.buildFingerprint()

      // 2) Load quirks DB and learned profile
      if debugEnabled { print("   [Actor] Loading quirks DB...") }
      let qdb = try QuirkDatabase.load()
      
      let persistence = await MTPDeviceManager.shared.persistence
      let learnedProfile = try await persistence.learnedProfiles.loadProfile(for: fingerprint)

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
      if let profile = learnedProfile {
        learnedTuning = EffectiveTuning(
          maxChunkBytes: profile.optimalChunkSize ?? 2 * 1024 * 1024,
          ioTimeoutMs: profile.optimalIoTimeoutMs ?? 10_000,
          handshakeTimeoutMs: profile.avgHandshakeMs ?? 6_000,
          inactivityTimeoutMs: profile.optimalInactivityTimeoutMs ?? 8_000,
          overallDeadlineMs: 60_000,
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
      self.currentTuning = initialTuning
      self.apply(initialTuning)

      // 8) Run hooks: postOpenUSB
      if debugEnabled { print("   [Actor] Running postOpenUSB hooks...") }
      try await self.runHook(.postOpenUSB, tuning: initialTuning)

      // 9) Open session + stabilization (with retry on timeout/IO error)
      if debugEnabled { print("   [Actor] Opening MTP session...") }
      do {
          try await link.openSession(id: 1)
      } catch {
          guard isTimeoutOrIOError(error) else { throw error }
          if debugEnabled { print("   [Actor] OpenSession failed (\(error)), retrying with USB reset...") }

          // Close current link, re-open with resetOnOpen forced
          await link.close()
          self.mtpLink = nil
          self.config.resetOnOpen = true
          let newLink = try await transport.open(summary, config: config)
          self.mtpLink = newLink

          // Stabilize after USB reset
          try await Task.sleep(nanoseconds: 500_000_000)

          // Retry OpenSession
          try await newLink.openSession(id: 1)
          if debugEnabled { print("   [Actor] OpenSession succeeded after USB reset.") }
      }

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
      self.probedCapabilities = realCaps
      
      // Re-build tuning with real capabilities
      let finalTuning = EffectiveTuningBuilder.build(
        capabilities: realCaps,
        learned: learnedTuning,
        quirk: quirk,
        overrides: overrides.isEmpty ? nil : overrides
      )
      self.currentTuning = finalTuning
      self.apply(finalTuning)

      // 12) Start event pump
      if realCaps["supportsEvents"] == true { 
        if debugEnabled { print("   [Actor] Starting event pump...") }
        try await self.startEventPump() 
      }

      // 13) Record success
      let updatedProfile = (learnedProfile ?? LearnedProfile(fingerprint: fingerprint)).merged(with: SessionData(
        actualChunkSize: finalTuning.maxChunkBytes,
        handshakeTimeMs: finalTuning.handshakeTimeoutMs,
        effectiveIoTimeoutMs: finalTuning.ioTimeoutMs,
        effectiveInactivityTimeoutMs: finalTuning.inactivityTimeoutMs,
        wasSuccessful: true
      ))
      try await persistence.learnedProfiles.saveProfile(updatedProfile, for: self.id)
      
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

    private func isTimeoutOrIOError(_ error: Error) -> Bool {
        if case .timeout = error as? MTPError { return true }
        if let mtpErr = error as? MTPError, case .transport(let te) = mtpErr {
            if case .timeout = te { return true }
            if case .io = te { return true }
        }
        return false
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
        if let link = await getMTPLinkIfAvailable() {
            try eventPump.startIfAvailable(on: link)
        }
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
