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
  private var currentPolicy: DevicePolicy?
  public var devicePolicy: DevicePolicy? { get async { currentPolicy } }
  private var currentProbeReceipt: ProbeReceipt?
  public var probeReceipt: ProbeReceipt? { get async { currentProbeReceipt } }
  private var eventPump: EventPump = EventPump()
  /// Session-scoped cache to avoid repeated GetObjectInfo(parent) calls on writes.
  var parentStorageIDCache: [MTPObjectHandle: UInt32] = [:]

  public init(
    id: MTPDeviceID, summary: MTPDeviceSummary, transport: MTPTransport,
    config: SwiftMTPConfig = .init(), transferJournal: (any TransferJournal)? = nil
  ) {
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

      // Run beforeGetStorageIDs hook for devices that need preparation time
      try await self.runHook(.beforeGetStorageIDs, tuning: self.currentTuning)

      var ids = try await link.getStorageIDs()

      // If zero storages, apply fallback retry logic with escalating backoff
      if ids.isEmpty {
        var attempt = 0
        let maxRetries = 5
        let backoffMs: [UInt32] = [400, 800, 1600, 3200, 5000]

        while ids.isEmpty && attempt < maxRetries {
          attempt += 1
          let delay = backoffMs[min(attempt - 1, backoffMs.count - 1)]
          try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

          // Retry GetStorageIDs
          ids = try await link.getStorageIDs()
        }

        // All retries exhausted, return empty
        if ids.isEmpty { return [] }
      }

      return try await withThrowingTaskGroup(of: MTPStorageInfo.self) { g in
        for id in ids { g.addTask { try await link.getStorageInfo(id: id) } }
        var out = [MTPStorageInfo]()
        out.reserveCapacity(ids.count)
        for try await s in g { out.append(s) }
        return out
      }
    }
  }

  public nonisolated func list(parent: MTPObjectHandle?, in storage: MTPStorageID)
    -> AsyncThrowingStream<[MTPObjectInfo], Error>
  {
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

  public func move(_ handle: MTPObjectHandle, to parent: MTPObjectHandle?, storage: MTPStorageID)
    async throws
  {
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
    parentStorageIDCache.removeAll(keepingCapacity: true)
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
    parentStorageIDCache.removeAll(keepingCapacity: true)
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
    let totalState = signposter.beginInterval(
      "applyTuningAndOpenSession", id: signposter.makeSignpostID())
    defer { signposter.endInterval("applyTuningAndOpenSession", totalState) }

    let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    let probeStart = DispatchTime.now()
    if debugEnabled { print("   [Actor] applyTuningAndOpenSession starting...") }

    // 1) Build fingerprint from USB IDs and interface details
    let fingerprint = try await self.buildFingerprint()

    // Initialize probe receipt
    var receipt = ProbeReceipt(
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

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
    if let handshakeTimeout = userOverrides.handshakeTimeoutMs {
      overrides["handshakeTimeoutMs"] = String(handshakeTimeout)
    }
    if let inactivityTimeout = userOverrides.inactivityTimeoutMs {
      overrides["inactivityTimeoutMs"] = String(inactivityTimeout)
    }
    if let overallDeadline = userOverrides.overallDeadlineMs {
      overrides["overallDeadlineMs"] = String(overallDeadline)
    }
    if let stabilize = userOverrides.stabilizeMs { overrides["stabilizeMs"] = String(stabilize) }
    if config.postClaimStabilizeMs > 0 {
      overrides["postClaimStabilizeMs"] = String(config.postClaimStabilizeMs)
    }

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
        postClaimStabilizeMs: 250,
        postProbeStabilizeMs: 0,
        resetOnOpen: false,
        disableEventPump: false,
        operations: [:],
        hooks: []
      )
    }

    // 6) Find matching quirk — use real interface descriptor when available
    let linkDesc = mtpLink?.linkDescriptor
    let quirk = qdb.match(
      vid: summary.vendorID ?? 0,
      pid: summary.productID ?? 0,
      bcdDevice: nil,
      ifaceClass: linkDesc?.interfaceClass,
      ifaceSubclass: linkDesc?.interfaceSubclass,
      ifaceProtocol: linkDesc?.interfaceProtocol
    )
    if debugEnabled, let q = quirk { print("   [Actor] Matched quirk: \(q.id)") }

    // 7) Build initial effective tuning + policy
    let initialPolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: learnedTuning,
      quirk: quirk,
      overrides: overrides.isEmpty ? nil : overrides
    )
    let initialTuning = initialPolicy.tuning
    self.currentTuning = initialTuning
    self.currentPolicy = initialPolicy
    self.apply(initialTuning)

    // 8) Run hooks: postOpenUSB
    if debugEnabled { print("   [Actor] Running postOpenUSB hooks...") }
    try await self.runHook(.postOpenUSB, tuning: initialTuning)

    let enableResetReopenLadder = initialPolicy.flags.resetReopenOnOpenSessionIOError

    // 9) Open session + stabilization (with optional quirk-gated reset/reopen ladder)
    if debugEnabled { print("   [Actor] Opening MTP session...") }
    var sessionResult = SessionProbeResult()
    let sessionStart = DispatchTime.now()

    // Preemptive CloseSession to clear any stale session from a previous crash
    if debugEnabled { print("   [Actor] Preemptive CloseSession (clear stale)...") }
    try? await link.closeSession()

    do {
      try await link.openSession(id: 1)
      sessionResult.succeeded = true
    } catch let error as MTPError where error.isSessionAlreadyOpen {
      // Session already open — close it and retry
      if debugEnabled { print("   [Actor] SessionAlreadyOpen (0x201E), closing and retrying...") }
      sessionResult.requiredRetry = true
      try? await link.closeSession()
      try await link.openSession(id: 1)
      sessionResult.succeeded = true
      if debugEnabled { print("   [Actor] OpenSession succeeded after close+retry.") }
    } catch {
      guard isTimeoutOrIOError(error) else {
        sessionResult.error = "\(error)"
        receipt.sessionEstablishment = sessionResult
        throw error
      }
      sessionResult.firstFailure = "\(error)"
      guard enableResetReopenLadder else {
        sessionResult.error = "\(error)"
        receipt.sessionEstablishment = sessionResult
        throw error
      }
      if debugEnabled {
        print("   [Actor] OpenSession failed (\(error)), applying quirk reset+reopen ladder...")
      }
      sessionResult.requiredRetry = true
      sessionResult.recoveryAction = "reset-reopen"

      // Step 1: Attempt device reset on current handle.
      sessionResult.resetAttempted = true
      do {
        try await link.resetDevice()
      } catch {
        sessionResult.resetError = "\(error)"
      }

      // Step 2: Full teardown before re-opening a fresh handle/interface claim.
      eventPump.stop()
      await link.close()
      self.mtpLink = nil
      try? await transport.close()

      var reopenConfig = self.config
      reopenConfig.resetOnOpen = false
      let newLink = try await transport.open(summary, config: reopenConfig)
      self.mtpLink = newLink
      self.config = reopenConfig

      // Step 3: Brief settle time after re-enumeration/re-claim.
      let settleMs = max(initialTuning.postClaimStabilizeMs, 250)
      try await Task.sleep(nanoseconds: UInt64(settleMs) * 1_000_000)

      // Step 4: Retry OpenSession once with fresh link state.
      try await newLink.openSession(id: 1)
      sessionResult.succeeded = true
      if debugEnabled { print("   [Actor] OpenSession succeeded after reset+reopen.") }
    }
    sessionResult.durationMs = Int(
      (DispatchTime.now().uptimeNanoseconds - sessionStart.uptimeNanoseconds) / 1_000_000)
    receipt.sessionEstablishment = sessionResult

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
      "supportsEvents": await self.capabilityEvents(),
    ]
    self.probedCapabilities = realCaps

    // Determine fallback selections from device capabilities
    let fallbacks = await self.determineFallbackSelections()
    if debugEnabled {
      print(
        "   [Actor] Fallbacks: enum=\(fallbacks.enumeration) read=\(fallbacks.read) write=\(fallbacks.write)"
      )
    }

    // Re-build tuning + policy with real capabilities
    var finalPolicy = EffectiveTuningBuilder.buildPolicy(
      capabilities: realCaps,
      learned: learnedTuning,
      quirk: quirk,
      overrides: overrides.isEmpty ? nil : overrides
    )
    finalPolicy.fallbacks = fallbacks
    let finalTuning = finalPolicy.tuning
    self.currentTuning = finalTuning
    self.currentPolicy = finalPolicy
    self.apply(finalTuning)

    // 12) Start event pump
    if realCaps["supportsEvents"] == true {
      if debugEnabled { print("   [Actor] Starting event pump...") }
      try await self.startEventPump()
    }

    // 12b) Finalize probe receipt
    receipt.capabilities = realCaps
    receipt.fallbackResults = [
      "enumeration": fallbacks.enumeration.rawValue,
      "read": fallbacks.read.rawValue,
      "write": fallbacks.write.rawValue,
    ]
    receipt.resolvedPolicy = PolicySummary(from: finalPolicy)
    receipt.totalProbeTimeMs = Int(
      (DispatchTime.now().uptimeNanoseconds - probeStart.uptimeNanoseconds) / 1_000_000)
    self.currentProbeReceipt = receipt

    // 13) Record success
    let updatedProfile = (learnedProfile ?? LearnedProfile(fingerprint: fingerprint))
      .merged(
        with: SessionData(
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
    // Use real USB descriptor data from transport probing when available
    if let desc = mtpLink?.linkDescriptor {
      return MTPDeviceFingerprint.fromUSB(
        vid: summary.vendorID ?? 0,
        pid: summary.productID ?? 0,
        interfaceClass: desc.interfaceClass,
        interfaceSubclass: desc.interfaceSubclass,
        interfaceProtocol: desc.interfaceProtocol,
        epIn: desc.bulkInEndpoint,
        epOut: desc.bulkOutEndpoint,
        epEvt: desc.interruptEndpoint
      )
    }
    // Fallback for mock transports without real descriptor data
    return MTPDeviceFingerprint.fromUSB(
      vid: summary.vendorID ?? 0,
      pid: summary.productID ?? 0,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01
    )
  }

  private func capabilityPartialRead() async -> Bool {
    do {
      let deviceInfo = try await self.info
      return deviceInfo.operationsSupported.contains(PTPOp.getPartialObject64.rawValue)
        || deviceInfo.operationsSupported.contains(PTPOp.getPartialObject.rawValue)
    } catch {
      return true  // Default assumption if device info unavailable
    }
  }

  private func capabilityPartialWrite() async -> Bool {
    do {
      let deviceInfo = try await self.info
      return deviceInfo.operationsSupported.contains(PTPOp.sendPartialObject.rawValue)
    } catch {
      return true
    }
  }

  private func capabilityEvents() async -> Bool {
    do {
      let deviceInfo = try await self.info
      return !deviceInfo.eventsSupported.isEmpty
    } catch {
      return false
    }
  }

  /// Determine which strategies to use for enumeration, read, and write
  /// based on the device's advertised operation support.
  private func determineFallbackSelections() async -> FallbackSelections {
    var sel = FallbackSelections()
    do {
      let di = try await self.info
      let ops = di.operationsSupported

      // Read strategy
      if ops.contains(PTPOp.getPartialObject64.rawValue) {
        sel.read = .partial64
      } else if ops.contains(PTPOp.getPartialObject.rawValue) {
        sel.read = .partial32
      } else {
        sel.read = .wholeObject
      }

      // Write strategy
      if ops.contains(PTPOp.sendPartialObject.rawValue) {
        sel.write = .partial
      } else {
        sel.write = .wholeObject
      }

      // Enumeration strategy — prefer propList if supported
      if ops.contains(0x9805) {  // GetObjectPropList
        sel.enumeration = .propList5
      } else {
        sel.enumeration = .handlesThenInfo
      }
    } catch {
      // Leave as .unknown
    }
    return sel
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
    let storageID = MTPStorageID(raw: 0xFFFFFFFF)  // Use all storages
    var allInfos: [MTPObjectInfo] = []
    for try await batch in self.list(parent: parent, in: storageID) {
      allInfos.append(contentsOf: batch)
    }
    return allInfos.map { $0.handle }
  }
}
