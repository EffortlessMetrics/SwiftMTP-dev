// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

extension MTPDeviceActor {
  private final class LockedDataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ raw: UnsafeRawBufferPointer) {
      lock.lock()
      data.append(contentsOf: raw.bindMemory(to: UInt8.self))
      lock.unlock()
    }

    func snapshot() -> Data {
      lock.lock()
      defer { lock.unlock() }
      return data
    }
  }

  private struct WriteStorageResolution: Sendable {
    let sendObjectInfoStorageID: UInt32
    let parentStorageID: UInt32?
    let source: String
  }

  enum SendObjectRetryClass: Sendable {
    case invalidParameter
    case invalidObjectHandle
    case transientTransport
  }

  struct SendObjectRetryParameters: Equatable, Sendable {
    let useEmptyDates: Bool
    let useUndefinedObjectFormat: Bool
    let useUnknownObjectInfoSize: Bool
    let omitOptionalObjectInfoFields: Bool
    let zeroObjectInfoParentHandle: Bool
    let useRootCommandParentHandle: Bool
  }

  public func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID)
    async throws -> MTPObjectHandle
  {
    try await openIfNeeded()
    let link = try await getMTPLink()
    let resolvedParent = (parent == 0xFFFFFFFF) ? nil : parent
    let parentHandle = resolvedParent ?? 0xFFFFFFFF
    let storageResolution = try await resolveWriteStorageID(
      parent: resolvedParent,
      selectedStorageRaw: storage.raw,
      link: link
    )
    return try await BusyBackoff.onDeviceBusy {
      try await ProtoTransfer.createFolder(
        storageID: storageResolution.sendObjectInfoStorageID, parent: parentHandle, name: name,
        on: link, ioTimeoutMs: 10_000
      )
    }
  }

  public func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws
    -> Progress
  {
    let link = try await getMTPLink()
    let info = try await link.getObjectInfos([handle])[0]
    let deviceInfo = try await self.info

    let total = Int64(info.sizeBytes ?? 0)
    let progress = Progress(totalUnitCount: total > 0 ? total : -1)
    let timeout = 10_000  // 10 seconds
    let temp = url.appendingPathExtension("part")

    // Performance logging: begin transfer
    let startTime = Date()
    Logger(subsystem: "SwiftMTP", category: "performance")
      .info("Transfer begin: read \(info.name) handle=\(handle) size=\(info.sizeBytes ?? 0)")

    // Check if partial read is supported
    let supportsPartial = deviceInfo.operationsSupported.contains(0x95C4)  // GetPartialObject64

    var journalTransferId: String?
    var sink: any ByteSink

    // Try to resume if we have a journal
    if let journal = transferJournal {
      do {
        let resumables = try await journal.loadResumables(for: id)
        if let existing = resumables.first(where: { $0.handle == handle && $0.kind == "read" }) {
          // Resume from existing temp file
          if FileManager.default.fileExists(atPath: existing.localTempURL.path) {
            sink = try FileSink(url: existing.localTempURL, append: true)
            journalTransferId = existing.id
            progress.completedUnitCount = Int64(existing.committedBytes)
          } else {
            // Temp file missing, start fresh
            sink = try FileSink(url: temp)
            journalTransferId = try await journal.beginRead(
              device: id,
              handle: handle,
              name: info.name,
              size: info.sizeBytes,
              supportsPartial: supportsPartial,
              tempURL: temp,
              finalURL: url,
              etag: (size: info.sizeBytes, mtime: info.modified)
            )
          }
        } else {
          // New transfer
          sink = try FileSink(url: temp)
          journalTransferId = try await journal.beginRead(
            device: id,
            handle: handle,
            name: info.name,
            size: info.sizeBytes,
            supportsPartial: supportsPartial,
            tempURL: temp,
            finalURL: url,
            etag: (size: info.sizeBytes, mtime: info.modified)
          )
        }
      } catch {
        // Journal failed, proceed without it
        sink = try FileSink(url: temp)
      }
    } else {
      sink = try FileSink(url: temp)
    }

    let activity = ProcessInfo.processInfo.beginActivity(
      options: [.idleSystemSleepDisabled, .userInitiated],
      reason: "SwiftMTP read")
    defer { ProcessInfo.processInfo.endActivity(activity) }

    do {
      // Create Sendable adapter to avoid capturing non-Sendable sink
      let sinkAdapter = SendableSinkAdapter(sink)

      // Use thread-safe progress tracking
      let progressTracker = AtomicProgressTracker()

      try await ProtoTransfer.readWholeObject(
        handle: handle, on: link,
        dataHandler: { buf in
          let consumed = sinkAdapter.consume(buf)
          let totalBytes = progressTracker.add(consumed)
          progress.completedUnitCount = Int64(totalBytes)
          return consumed
        }, ioTimeoutMs: timeout)

      let bytesWritten = progressTracker.total

      // Update journal after transfer completes
      if let journal = transferJournal, let transferId = journalTransferId {
        try await journal.updateProgress(id: transferId, committed: bytesWritten)
      }

      try sink.close()

      // Mark as complete in journal
      if let journal = transferJournal, let transferId = journalTransferId {
        try await journal.complete(id: transferId)
      }

      try atomicReplace(temp: temp, final: url)

      // Performance logging: end transfer (success)
      let duration = Date().timeIntervalSince(startTime)
      let throughput = Double(bytesWritten) / duration
      Logger(subsystem: "SwiftMTP", category: "performance")
        .info(
          "Transfer completed: read \(bytesWritten) bytes in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", throughput/1024/1024)) MB/s)"
        )

      // Record throughput telemetry in journal
      if let journal = transferJournal, let transferId = journalTransferId, duration > 0 {
        try? await journal.recordThroughput(id: transferId, throughputMBps: throughput / 1_048_576)
      }

      return progress
    } catch {
      try? sink.close()
      try? FileManager.default.removeItem(at: temp)

      // Performance logging: end transfer (failure)
      let duration = Date().timeIntervalSince(startTime)
      Logger(subsystem: "SwiftMTP", category: "performance")
        .error(
          "Transfer failed: read after \(String(format: "%.2f", duration))s - \(error.localizedDescription)"
        )

      // Mark as failed in journal
      if let journal = transferJournal, let transferId = journalTransferId {
        try? await journal.fail(id: transferId, error: error)
      }

      throw error
    }
  }

  public func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL)
    async throws -> Progress
  {
    return try await withTransaction {
      let link = try await getMTPLink()
      let deviceInfo = try await self.info
      let total = Int64(size)
      let progress = Progress(totalUnitCount: Int64(size))

      // Performance logging: begin transfer
      let startTime = Date()
      Logger(subsystem: "SwiftMTP", category: "performance")
        .info("Transfer begin: write \(name) size=\(size)")

      // Check if partial write is supported
      let supportsPartial = deviceInfo.operationsSupported.contains(0x95C1)  // SendPartialObject
      let supportsSendObjectPropList = deviceInfo.operationsSupported.contains(
        MTPOp.sendObjectPropList.rawValue)

      var journalTransferId: String?

      // Initialize transfer journal if available
      if let journal = transferJournal {
        do {
          journalTransferId = try await journal.beginWrite(
            device: id,
            parent: parent ?? 0,
            name: name,
            size: size,
            supportsPartial: supportsPartial,
            tempURL: url,  // Not really a temp for writes, but we need a URL
            sourceURL: url
          )
        } catch {
          // Journal failed, proceed without it
        }
      }

      // Shared box filled by writeWholeObject/writeWholeObjectViaPropList immediately after
      // SendObjectInfo succeeds, so the remote handle is available even if SendObject fails.
      let remoteHandleCapture = AtomicHandleBox()
      var lastKnownRemoteHandle: UInt32?

      let activity = ProcessInfo.processInfo.beginActivity(
        options: [.idleSystemSleepDisabled, .userInitiated],
        reason: "SwiftMTP write")
      defer { ProcessInfo.processInfo.endActivity(activity) }

      do {
        let policy = await self.devicePolicy
        let policyTimeout = max(policy?.tuning.ioTimeoutMs ?? 10_000, 1_000)
        // Keep small write-smoke requests from spending minutes in per-command timeout recovery.
        let timeout = size <= 256 * 1024 ? min(policyTimeout, 4_000) : policyTimeout

        // Check if device requires subfolder for writes (quirk flag)
        let requiresSubfolder = policy?.flags.writeToSubfolderOnly ?? false
        let preferredWriteFolder = policy?.flags.preferredWriteFolder

        let useEmptyDates = policy?.flags.emptyDatesInSendObject ?? false
        let allowUnknownObjectInfoSizeRetry = policy?.flags.unknownSizeInSendObjectInfo ?? false
        let isXiaomiFF40 = Self.isXiaomiMiNote2FF40(summary: summary)
        let isOnePlusF003 = Self.isOnePlus3TF003(summary: summary)
        let useMediaTargetPolicy = isXiaomiFF40 || isOnePlusF003

        // Determine storage ID and parent handle using WriteTargetLadder
        let availableStorages = try? await self.storages()
        let rootStorages = availableStorages ?? []
        let preferredRootStorage =
          rootStorages.first(where: { !$0.isReadOnly }) ?? rootStorages.first

        var selectedStorageRaw: UInt32? = preferredRootStorage?.id.raw
        var resolvedParent: MTPObjectHandle? = parent

        // If parent is 0 (root) AND device requires subfolder, treat as "no parent" and use WriteTargetLadder
        let effectiveParent: MTPObjectHandle? = (parent == 0 && requiresSubfolder) ? nil : parent

        if let p = effectiveParent {
          resolvedParent = p
        } else if let first = preferredRootStorage {
          // No parent or parent=0 with requiresSubfolder - need to resolve target
          let target = try await WriteTargetLadder.resolveTarget(
            device: self,
            storage: first.id,
            explicitParent: nil,
            requiresSubfolder: requiresSubfolder,
            preferredWriteFolder: preferredWriteFolder
          )
          selectedStorageRaw = target.0.raw
          resolvedParent = target.1

          // Log where we're writing to
          if requiresSubfolder {
            Logger(subsystem: "SwiftMTP", category: "write")
              .info(
                "Device requires subfolder for writes, resolved to parent handle \(resolvedParent!)"
              )
          }
        }
        let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
        var storageResolution = try await resolveWriteStorageID(
          parent: resolvedParent,
          selectedStorageRaw: selectedStorageRaw,
          link: link
        )
        var targetStorageRaw = storageResolution.sendObjectInfoStorageID

        func logSendObjectInfoContext(
          parent: MTPObjectHandle?,
          storageRaw: UInt32,
          resolution: WriteStorageResolution
        ) {
          guard debugEnabled else { return }
          let parentHandle = parent ?? 0xFFFFFFFF
          let parentStorageText: String
          if let parentStorageID = resolution.parentStorageID {
            parentStorageText = String(format: "0x%08x", parentStorageID)
          } else {
            parentStorageText = "n/a"
          }
          print(
            "   [USB] SendObjectInfo context: parentHandle=\(String(format: "0x%08x", parentHandle)) parentStorageId=\(parentStorageText) sendObjectInfo.storageId=\(String(format: "0x%08x", storageRaw)) source=\(resolution.source)"
          )
        }

        func logParentHandleCheck(parent: MTPObjectHandle?) async {
          guard debugEnabled, let parent, parent != 0xFFFFFFFF else { return }
          do {
            let currentLink = try await self.getMTPLink()
            if let info = try await self.getObjectInfoStrict(handle: parent, link: currentLink) {
              let parentOfParent = info.parent ?? 0xFFFFFFFF
              print(
                "   [USB] Parent handle check: handle=\(String(format: "0x%08x", parent)) exists=yes name=\(info.name) storage=\(String(format: "0x%08x", info.storage.raw)) parent=\(String(format: "0x%08x", parentOfParent))"
              )
            } else {
              print(
                "   [USB] Parent handle check: handle=\(String(format: "0x%08x", parent)) exists=no (GetObjectInfo returned object-not-found)"
              )
            }
          } catch {
            print(
              "   [USB] Parent handle check: handle=\(String(format: "0x%08x", parent)) lookup-error=\(error)"
            )
          }
        }

        func performWrite(
          to parent: MTPObjectHandle?,
          storageRaw: UInt32,
          params: SendObjectRetryParameters,
          resolution: WriteStorageResolution
        ) async throws -> UInt64 {
          logSendObjectInfoContext(parent: parent, storageRaw: storageRaw, resolution: resolution)
          let source = try FileSource(url: url)
          defer { try? source.close() }

          let sourceAdapter = SendableSourceAdapter(source)
          let progressTracker = AtomicProgressTracker()
          let currentLink = try await self.getMTPLink()
          try await ProtoTransfer.writeWholeObject(
            storageID: storageRaw, parent: parent, name: name, size: size,
            dataHandler: { buf in
              let produced = sourceAdapter.produce(buf)
              let totalBytes = progressTracker.add(Int(produced))
              progress.completedUnitCount = Int64(totalBytes)
              return Int(produced)
            }, on: currentLink, ioTimeoutMs: timeout,
            useEmptyDates: params.useEmptyDates,
            useUndefinedObjectFormat: params.useUndefinedObjectFormat,
            useUnknownObjectInfoSize: params.useUnknownObjectInfoSize,
            omitOptionalObjectInfoFields: params.omitOptionalObjectInfoFields,
            zeroObjectInfoParentHandle: params.zeroObjectInfoParentHandle,
            useRootCommandParentHandle: params.useRootCommandParentHandle,
            handleOut: remoteHandleCapture
          )
          return progressTracker.total
        }

        func performWriteViaPropList(
          to parent: MTPObjectHandle?,
          storageRaw: UInt32,
          params: SendObjectRetryParameters,
          resolution: WriteStorageResolution
        ) async throws -> UInt64 {
          logSendObjectInfoContext(parent: parent, storageRaw: storageRaw, resolution: resolution)
          let source = try FileSource(url: url)
          defer { try? source.close() }

          let sourceAdapter = SendableSourceAdapter(source)
          let progressTracker = AtomicProgressTracker()
          let currentLink = try await self.getMTPLink()
          try await ProtoTransfer.writeWholeObjectViaPropList(
            storageID: storageRaw, parent: parent, name: name, size: size,
            dataHandler: { buf in
              let produced = sourceAdapter.produce(buf)
              let totalBytes = progressTracker.add(Int(produced))
              progress.completedUnitCount = Int64(totalBytes)
              return Int(produced)
            },
            on: currentLink,
            ioTimeoutMs: timeout,
            useUndefinedObjectFormat: params.useUndefinedObjectFormat,
            zeroObjectInfoParentHandle: params.zeroObjectInfoParentHandle,
            handleOut: remoteHandleCapture
          )
          return progressTracker.total
        }

        var bytesRead: UInt64 = 0
        let isLabSmokeWrite = name.hasPrefix("swiftmtp-smoke-")
        let primaryParams = SendObjectRetryParameters(
          useEmptyDates: useEmptyDates,
          useUndefinedObjectFormat: false,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false,
          useRootCommandParentHandle: false
        )
        await logParentHandleCheck(parent: resolvedParent)

        do {
          bytesRead = try await performWrite(
            to: resolvedParent,
            storageRaw: targetStorageRaw,
            params: primaryParams,
            resolution: storageResolution
          )
        } catch {
          // For lab smoke writes, return the first concrete failure quickly.
          // Device-lab controls target climbing and retry budget deterministically.
          if isLabSmokeWrite {
            throw error
          }

          // Update last known remote handle so reconciliation can find the partial.
          lastKnownRemoteHandle = remoteHandleCapture.value
          if let handle = lastKnownRemoteHandle, let journal = transferJournal,
            let transferId = journalTransferId
          {
            try? await journal.recordRemoteHandle(id: transferId, handle: handle)
          }

          guard let retryReason = Self.retryableSendObjectFailureReason(for: error) else {
            throw error
          }
          let retryClass = Self.sendObjectRetryClass(for: retryReason)
          if !Self.shouldSkipDeepRecovery(
            reason: retryReason, useMediaTargetPolicy: useMediaTargetPolicy),
            await self.hardResetWriteSessionIfNeeded(
              reason: retryReason, debugEnabled: debugEnabled)
          {
            // After session reset, delete any partial object left on the device from the
            // previous SendObjectInfo → failed SendObject sequence.
            if let partialHandle = lastKnownRemoteHandle {
              if let info = try? await self.getInfo(handle: partialHandle),
                let expected = info.sizeBytes,
                expected < size
              {
                Logger(subsystem: "SwiftMTP", category: "write")
                  .info(
                    "Deleting partial object before retry: handle=\(partialHandle) name=\(name) actual=\(expected) expected=\(size)"
                  )
                try? await self.delete(partialHandle, recursive: false)
              }
            }
            do {
              let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                effectiveParent: effectiveParent,
                preferredRootStorage: preferredRootStorage,
                requiresSubfolder: requiresSubfolder,
                preferredWriteFolder: preferredWriteFolder,
                selectedStorageRaw: selectedStorageRaw
              )
              selectedStorageRaw = refreshedContext.selectedStorageRaw
              resolvedParent = refreshedContext.resolvedParent
              storageResolution = refreshedContext.resolution
              targetStorageRaw = refreshedContext.targetStorageRaw
              await logParentHandleCheck(parent: resolvedParent)
            } catch {
              if debugEnabled {
                print("   [USB] Session recovery: target re-resolve failed (\(error))")
              }
            }
          }

          let configuredStrategy = policy?.fallbacks.write.rawValue ?? "unknown"
          Logger(subsystem: "SwiftMTP", category: "write")
            .warning(
              "SendObject failed (\(retryReason), strategy=\(configuredStrategy)); retrying with fallback parameter ladder"
            )

          var retryParameters = Self.sendObjectRetryParameters(
            primary: primaryParams,
            retryClass: retryClass,
            isRootParent: (resolvedParent ?? 0xFFFFFFFF) == 0xFFFFFFFF,
            allowUnknownObjectInfoSizeRetry: allowUnknownObjectInfoSizeRetry
          )
          if useMediaTargetPolicy {
            retryParameters = []
          }
          var sawInvalidObjectHandle = retryClass == .invalidObjectHandle
          var lastRetryableError: Error = error
          var recovered = false

          if useMediaTargetPolicy, retryClass == .invalidParameter {
            let formatRetry =
              Self.sendObjectRetryParameters(
                primary: primaryParams,
                retryClass: .invalidParameter,
                isRootParent: (resolvedParent ?? 0xFFFFFFFF) == 0xFFFFFFFF,
                allowUnknownObjectInfoSizeRetry: false
              )
              .first

            if let formatRetry {
              var shouldAttemptFormatRetry = true
              if isOnePlusF003 {
                let refreshStorage =
                  availableStorages?.first(where: { $0.id.raw == targetStorageRaw })?.id
                  ?? availableStorages?.first?.id
                  ?? MTPStorageID(raw: targetStorageRaw)
                if let currentParent = resolvedParent, currentParent != 0xFFFFFFFF {
                  let refreshResult = await self.refreshOnePlusParentByNameForRetry(
                    currentParent: currentParent,
                    storageID: refreshStorage,
                    debugEnabled: debugEnabled
                  )
                  switch refreshResult {
                  case .refreshed(let refreshedParent):
                    resolvedParent = refreshedParent
                    do {
                      let currentLink = try await self.getMTPLink()
                      storageResolution = try await resolveWriteStorageID(
                        parent: resolvedParent,
                        selectedStorageRaw: targetStorageRaw,
                        link: currentLink
                      )
                      targetStorageRaw = storageResolution.sendObjectInfoStorageID
                    } catch {
                      shouldAttemptFormatRetry = false
                    }
                  case .unchanged, .unresolved:
                    shouldAttemptFormatRetry = false
                  }
                }
              }

              if shouldAttemptFormatRetry {
                do {
                  Logger(subsystem: "SwiftMTP", category: "write")
                    .info("SendObject retry rung=format-undefined")
                  bytesRead = try await performWrite(
                    to: resolvedParent,
                    storageRaw: targetStorageRaw,
                    params: formatRetry,
                    resolution: storageResolution
                  )
                  recovered = true
                } catch {
                  if let formatReason = Self.retryableSendObjectFailureReason(for: error) {
                    if !Self.shouldSkipDeepRecovery(
                      reason: formatReason,
                      useMediaTargetPolicy: useMediaTargetPolicy
                    ),
                      await self.hardResetWriteSessionIfNeeded(
                        reason: formatReason,
                        debugEnabled: debugEnabled
                      )
                    {
                      do {
                        let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                          effectiveParent: effectiveParent,
                          preferredRootStorage: preferredRootStorage,
                          requiresSubfolder: requiresSubfolder,
                          preferredWriteFolder: preferredWriteFolder,
                          selectedStorageRaw: selectedStorageRaw
                        )
                        selectedStorageRaw = refreshedContext.selectedStorageRaw
                        resolvedParent = refreshedContext.resolvedParent
                        storageResolution = refreshedContext.resolution
                        targetStorageRaw = refreshedContext.targetStorageRaw
                        await logParentHandleCheck(parent: resolvedParent)
                      } catch {
                        if debugEnabled {
                          print("   [USB] Session recovery: target re-resolve failed (\(error))")
                        }
                      }
                    }
                    if Self.sendObjectRetryClass(for: formatReason) == .invalidObjectHandle {
                      sawInvalidObjectHandle = true
                    }
                  }
                  lastRetryableError = error
                }
              }
            }
          }

          for (index, retryParams) in retryParameters.enumerated() where !recovered {
            do {
              Logger(subsystem: "SwiftMTP", category: "write")
                .info(
                  "SendObject retry rung=\(Self.describeSendObjectRetryRung(index: index, params: retryParams, primary: primaryParams))"
                )
              bytesRead = try await performWrite(
                to: resolvedParent,
                storageRaw: targetStorageRaw,
                params: retryParams,
                resolution: storageResolution
              )
              recovered = true
              break
            } catch {
              guard let reason = Self.retryableSendObjectFailureReason(for: error) else {
                throw error
              }
              if !Self.shouldSkipDeepRecovery(
                reason: reason, useMediaTargetPolicy: useMediaTargetPolicy),
                await self.hardResetWriteSessionIfNeeded(reason: reason, debugEnabled: debugEnabled)
              {
                do {
                  let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                    effectiveParent: effectiveParent,
                    preferredRootStorage: preferredRootStorage,
                    requiresSubfolder: requiresSubfolder,
                    preferredWriteFolder: preferredWriteFolder,
                    selectedStorageRaw: selectedStorageRaw
                  )
                  selectedStorageRaw = refreshedContext.selectedStorageRaw
                  resolvedParent = refreshedContext.resolvedParent
                  storageResolution = refreshedContext.resolution
                  targetStorageRaw = refreshedContext.targetStorageRaw
                  await logParentHandleCheck(parent: resolvedParent)
                } catch {
                  if debugEnabled {
                    print("   [USB] Session recovery: target re-resolve failed (\(error))")
                  }
                }
              }
              if Self.sendObjectRetryClass(for: reason) == .invalidObjectHandle {
                sawInvalidObjectHandle = true
                if useMediaTargetPolicy {
                  lastRetryableError = error
                  continue
                }
                if let currentParent = resolvedParent, currentParent != 0xFFFFFFFF {
                  var existingParent: MTPObjectInfo?
                  do {
                    let currentLink = try await self.getMTPLink()
                    existingParent = try await self.getObjectInfoStrict(
                      handle: currentParent,
                      link: currentLink
                    )
                  } catch {
                    if let reason = Self.retryableSendObjectFailureReason(for: error) {
                      if await self.hardResetWriteSessionIfNeeded(
                        reason: reason,
                        debugEnabled: debugEnabled
                      ) {
                        do {
                          let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                            effectiveParent: effectiveParent,
                            preferredRootStorage: preferredRootStorage,
                            requiresSubfolder: requiresSubfolder,
                            preferredWriteFolder: preferredWriteFolder,
                            selectedStorageRaw: selectedStorageRaw
                          )
                          selectedStorageRaw = refreshedContext.selectedStorageRaw
                          resolvedParent = refreshedContext.resolvedParent
                          storageResolution = refreshedContext.resolution
                          targetStorageRaw = refreshedContext.targetStorageRaw
                          await logParentHandleCheck(parent: resolvedParent)
                        } catch {
                          if debugEnabled {
                            print("   [USB] Session recovery: target re-resolve failed (\(error))")
                          }
                        }
                      }
                    }
                    do {
                      let currentLink = try await self.getMTPLink()
                      existingParent = try await self.getObjectInfoStrict(
                        handle: currentParent,
                        link: currentLink
                      )
                    } catch {
                      if debugEnabled {
                        print(
                          "   [USB] Parent handle refresh: unable to verify current parent (\(error))"
                        )
                      }
                      lastRetryableError = error
                      continue
                    }
                  }
                  if existingParent == nil,
                    let fallbackStorage =
                      availableStorages?.first(where: { $0.id.raw == targetStorageRaw })
                      ?? availableStorages?.first
                  {
                    do {
                      let fallback = try await WriteTargetLadder.resolveTarget(
                        device: self,
                        storage: fallbackStorage.id,
                        explicitParent: nil,
                        requiresSubfolder: true,
                        preferredWriteFolder: preferredWriteFolder,
                        excludingParent: currentParent
                      )
                      let oldParent = currentParent
                      targetStorageRaw = fallback.0.raw
                      resolvedParent = fallback.1
                      let currentLink = try await self.getMTPLink()
                      storageResolution = try await resolveWriteStorageID(
                        parent: resolvedParent,
                        selectedStorageRaw: targetStorageRaw,
                        link: currentLink
                      )
                      targetStorageRaw = storageResolution.sendObjectInfoStorageID
                      if debugEnabled {
                        print(
                          "   [USB] Parent handle refresh: old=\(String(format: "0x%08x", oldParent)) new=\(String(format: "0x%08x", resolvedParent ?? 0xFFFFFFFF)) storage=\(String(format: "0x%08x", targetStorageRaw))"
                        )
                      }
                    } catch {
                      if let reason = Self.retryableSendObjectFailureReason(for: error) {
                        if await self.hardResetWriteSessionIfNeeded(
                          reason: reason,
                          debugEnabled: debugEnabled
                        ) {
                          do {
                            let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                              effectiveParent: effectiveParent,
                              preferredRootStorage: preferredRootStorage,
                              requiresSubfolder: requiresSubfolder,
                              preferredWriteFolder: preferredWriteFolder,
                              selectedStorageRaw: selectedStorageRaw
                            )
                            selectedStorageRaw = refreshedContext.selectedStorageRaw
                            resolvedParent = refreshedContext.resolvedParent
                            storageResolution = refreshedContext.resolution
                            targetStorageRaw = refreshedContext.targetStorageRaw
                            await logParentHandleCheck(parent: resolvedParent)
                          } catch {
                            if debugEnabled {
                              print(
                                "   [USB] Session recovery: target re-resolve failed (\(error))")
                            }
                          }
                        }
                      }
                      if debugEnabled {
                        print("   [USB] Parent handle refresh: failed (\(error))")
                      }
                    }
                  }
                }
              }
              lastRetryableError = error
            }
          }

          if !useMediaTargetPolicy && !recovered && retryClass == .invalidParameter
            && supportsSendObjectPropList
          {
            let propListParams = retryParameters.last ?? primaryParams
            do {
              Logger(subsystem: "SwiftMTP", category: "write")
                .info("SendObject retry rung=send-object-prop-list")
              bytesRead = try await performWriteViaPropList(
                to: resolvedParent,
                storageRaw: targetStorageRaw,
                params: propListParams,
                resolution: storageResolution
              )
              recovered = true
            } catch {
              if let reason = Self.retryableSendObjectFailureReason(for: error) {
                if !Self.shouldSkipDeepRecovery(
                  reason: reason, useMediaTargetPolicy: useMediaTargetPolicy),
                  await self.hardResetWriteSessionIfNeeded(
                    reason: reason, debugEnabled: debugEnabled)
                {
                  do {
                    let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                      effectiveParent: effectiveParent,
                      preferredRootStorage: preferredRootStorage,
                      requiresSubfolder: requiresSubfolder,
                      preferredWriteFolder: preferredWriteFolder,
                      selectedStorageRaw: selectedStorageRaw
                    )
                    selectedStorageRaw = refreshedContext.selectedStorageRaw
                    resolvedParent = refreshedContext.resolvedParent
                    storageResolution = refreshedContext.resolution
                    targetStorageRaw = refreshedContext.targetStorageRaw
                    await logParentHandleCheck(parent: resolvedParent)
                  } catch {
                    if debugEnabled {
                      print("   [USB] Session recovery: target re-resolve failed (\(error))")
                    }
                  }
                }
              }
              lastRetryableError = error
            }
          }

          // Keep per-target retries tight and climb folders quickly when a target is policy-gated.
          var attemptedParents = Set<MTPObjectHandle>()
          if let currentParent = resolvedParent {
            attemptedParents.insert(currentParent)
          }
          let ladderStorage =
            availableStorages?.first(where: { $0.id.raw == targetStorageRaw })
            ?? availableStorages?.first
          var ladderAttempt = 0
          while !recovered,
            Self.shouldAttemptTargetLadderFallback(parent: parent, retryClass: retryClass)
              || sawInvalidObjectHandle,
            let firstStorage = ladderStorage,
            ladderAttempt < 4
          {
            ladderAttempt += 1
            do {
              Logger(subsystem: "SwiftMTP", category: "write")
                .info("SendObject retry rung=target-ladder-\(ladderAttempt)")
              let fallback = try await WriteTargetLadder.resolveTarget(
                device: self,
                storage: firstStorage.id,
                explicitParent: nil,
                requiresSubfolder: true,
                preferredWriteFolder: preferredWriteFolder,
                excludingParents: attemptedParents
              )
              targetStorageRaw = fallback.0.raw
              resolvedParent = fallback.1
              attemptedParents.insert(fallback.1)
              let currentLink = try await self.getMTPLink()
              storageResolution = try await resolveWriteStorageID(
                parent: resolvedParent,
                selectedStorageRaw: targetStorageRaw,
                link: currentLink
              )
              targetStorageRaw = storageResolution.sendObjectInfoStorageID

              bytesRead = try await performWrite(
                to: resolvedParent,
                storageRaw: targetStorageRaw,
                params: primaryParams,
                resolution: storageResolution
              )
              recovered = true
              break
            } catch {
              guard let reason = Self.retryableSendObjectFailureReason(for: error) else {
                throw error
              }
              if !Self.shouldSkipDeepRecovery(
                reason: reason, useMediaTargetPolicy: useMediaTargetPolicy),
                await self.hardResetWriteSessionIfNeeded(reason: reason, debugEnabled: debugEnabled)
              {
                do {
                  let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                    effectiveParent: effectiveParent,
                    preferredRootStorage: preferredRootStorage,
                    requiresSubfolder: requiresSubfolder,
                    preferredWriteFolder: preferredWriteFolder,
                    selectedStorageRaw: selectedStorageRaw
                  )
                  selectedStorageRaw = refreshedContext.selectedStorageRaw
                  resolvedParent = refreshedContext.resolvedParent
                  storageResolution = refreshedContext.resolution
                  targetStorageRaw = refreshedContext.targetStorageRaw
                  await logParentHandleCheck(parent: resolvedParent)
                } catch {
                  if debugEnabled {
                    print("   [USB] Session recovery: target re-resolve failed (\(error))")
                  }
                }
              }
              lastRetryableError = error

              if useMediaTargetPolicy,
                Self.sendObjectRetryClass(for: reason) == .invalidObjectHandle
              {
                sawInvalidObjectHandle = true
                if debugEnabled {
                  print("   [USB] Target ladder: parent handle stale (0x2009); advancing target")
                }
                continue
              }

              if Self.sendObjectRetryClass(for: reason) == .invalidParameter {
                let ladderRetries = Self.sendObjectRetryParameters(
                  primary: primaryParams,
                  retryClass: .invalidParameter,
                  isRootParent: false,
                  allowUnknownObjectInfoSizeRetry: useMediaTargetPolicy
                    ? false : allowUnknownObjectInfoSizeRetry
                )
                if let ladderRetry = ladderRetries.first {
                  if isOnePlusF003 {
                    if let currentParent = resolvedParent, currentParent != 0xFFFFFFFF {
                      let refreshResult = await self.refreshOnePlusParentByNameForRetry(
                        currentParent: currentParent,
                        storageID: firstStorage.id,
                        debugEnabled: debugEnabled
                      )
                      switch refreshResult {
                      case .refreshed(let refreshedParent):
                        resolvedParent = refreshedParent
                        attemptedParents.insert(refreshedParent)
                        do {
                          let currentLink = try await self.getMTPLink()
                          storageResolution = try await resolveWriteStorageID(
                            parent: resolvedParent,
                            selectedStorageRaw: targetStorageRaw,
                            link: currentLink
                          )
                          targetStorageRaw = storageResolution.sendObjectInfoStorageID
                        } catch {
                          continue
                        }
                      case .unchanged, .unresolved:
                        continue
                      }
                    }
                  }
                  do {
                    Logger(subsystem: "SwiftMTP", category: "write")
                      .info("SendObject retry rung=target-ladder-format")
                    bytesRead = try await performWrite(
                      to: resolvedParent,
                      storageRaw: targetStorageRaw,
                      params: ladderRetry,
                      resolution: storageResolution
                    )
                    recovered = true
                    break
                  } catch {
                    if let retryReason = Self.retryableSendObjectFailureReason(for: error) {
                      if !Self.shouldSkipDeepRecovery(
                        reason: retryReason,
                        useMediaTargetPolicy: useMediaTargetPolicy
                      ),
                        await self.hardResetWriteSessionIfNeeded(
                          reason: retryReason,
                          debugEnabled: debugEnabled
                        )
                      {
                        do {
                          let refreshedContext = try await self.resolveWriteContextAfterRecovery(
                            effectiveParent: effectiveParent,
                            preferredRootStorage: preferredRootStorage,
                            requiresSubfolder: requiresSubfolder,
                            preferredWriteFolder: preferredWriteFolder,
                            selectedStorageRaw: selectedStorageRaw
                          )
                          selectedStorageRaw = refreshedContext.selectedStorageRaw
                          resolvedParent = refreshedContext.resolvedParent
                          storageResolution = refreshedContext.resolution
                          targetStorageRaw = refreshedContext.targetStorageRaw
                          await logParentHandleCheck(parent: resolvedParent)
                        } catch {
                          if debugEnabled {
                            print("   [USB] Session recovery: target re-resolve failed (\(error))")
                          }
                        }
                      }
                      if useMediaTargetPolicy,
                        Self.sendObjectRetryClass(for: retryReason) == .invalidObjectHandle
                      {
                        sawInvalidObjectHandle = true
                      }
                    }
                    lastRetryableError = error
                  }
                }
              }
            }
          }

          if !recovered { throw lastRetryableError }
        }

        // Update journal after transfer completes
        if let journal = transferJournal, let transferId = journalTransferId {
          try await journal.updateProgress(id: transferId, committed: bytesRead)
        }

        // Persist the final remote handle (updated after the successful SendObjectInfo).
        if let handle = remoteHandleCapture.value, let journal = transferJournal,
          let transferId = journalTransferId
        {
          try? await journal.recordRemoteHandle(id: transferId, handle: handle)
        }

        progress.completedUnitCount = total

        // Mark as complete in journal
        if let journal = transferJournal, let transferId = journalTransferId {
          try await journal.complete(id: transferId)
        }

        // Performance logging: end transfer (success)
        let duration = Date().timeIntervalSince(startTime)
        let throughput = Double(bytesRead) / duration
        Logger(subsystem: "SwiftMTP", category: "performance")
          .info(
            "Transfer completed: write \(bytesRead) bytes in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", throughput/1024/1024)) MB/s)"
          )

        // Record throughput telemetry in journal
        if let journal = transferJournal, let transferId = journalTransferId, duration > 0 {
          try? await journal.recordThroughput(
            id: transferId, throughputMBps: throughput / 1_048_576)
        }

        return progress
      } catch {
        // Performance logging: end transfer (failure)
        let duration = Date().timeIntervalSince(startTime)
        Logger(subsystem: "SwiftMTP", category: "performance")
          .error(
            "Transfer failed: write after \(String(format: "%.2f", duration))s - \(error.localizedDescription)"
          )

        // Mark as failed in journal
        if let journal = transferJournal, let transferId = journalTransferId {
          try? await journal.fail(id: transferId, error: error)
        }

        throw error
      }
    }
  }

  private enum OnePlusParentRefreshResult: Sendable {
    case refreshed(MTPObjectHandle)
    case unchanged
    case unresolved
  }

  private func refreshOnePlusParentByNameForRetry(
    currentParent: MTPObjectHandle,
    storageID: MTPStorageID,
    debugEnabled: Bool
  ) async -> OnePlusParentRefreshResult {
    do {
      let currentLink = try await self.getMTPLink()
      guard
        let currentInfo = try await self.getObjectInfoStrict(
          handle: currentParent,
          link: currentLink
        )
      else {
        if debugEnabled {
          print(
            "   [USB] OnePlus parent refresh: current handle \(String(format: "0x%08x", currentParent)) no longer resolvable; advancing target"
          )
        }
        return .unresolved
      }

      guard
        let refreshedParent = try await WriteTargetLadder.resolveFolderHandleByName(
          device: self,
          storage: storageID,
          folderName: currentInfo.name
        )
      else {
        if debugEnabled {
          print(
            "   [USB] OnePlus parent refresh: name=\(currentInfo.name) not found; advancing target")
        }
        return .unresolved
      }

      if refreshedParent == currentParent {
        if debugEnabled {
          print(
            "   [USB] OnePlus parent refresh: unchanged handle \(String(format: "0x%08x", currentParent)); advancing target"
          )
        }
        return .unchanged
      }

      if debugEnabled {
        print(
          "   [USB] OnePlus parent refresh: old=\(String(format: "0x%08x", currentParent)) new=\(String(format: "0x%08x", refreshedParent))"
        )
      }
      return .refreshed(refreshedParent)
    } catch {
      if debugEnabled {
        print("   [USB] OnePlus parent refresh: failed (\(error)); advancing target")
      }
      return .unresolved
    }
  }

  private static func isXiaomiMiNote2FF40(summary: MTPDeviceSummary) -> Bool {
    summary.vendorID == 0x2717 && summary.productID == 0xFF40
  }

  private static func isOnePlus3TF003(summary: MTPDeviceSummary) -> Bool {
    summary.vendorID == 0x2A70 && summary.productID == 0xF003
  }

  private static func shouldSkipDeepRecovery(reason: String, useMediaTargetPolicy: Bool) -> Bool {
    guard useMediaTargetPolicy else { return false }
    return reason == "invalid-parameter-0x201d"
      || reason == "invalid-object-handle-0x2009"
      || reason == "session-not-open-0x2003"
  }

  static func retryableSendObjectFailureReason(for error: Error) -> String? {
    guard let mtpError = error as? MTPError else { return nil }
    switch mtpError {
    case .protocolError(let code, _) where code == 0x201D:
      return "invalid-parameter-0x201d"
    case .protocolError(let code, _) where code == 0x2008:
      return "invalid-storage-id-0x2008"
    case .protocolError(let code, _) where code == 0x2009:
      return "invalid-object-handle-0x2009"
    case .protocolError(let code, _) where code == 0x2003:
      return "session-not-open-0x2003"
    case .objectNotFound:
      return "invalid-object-handle-0x2009"
    case .busy:
      return "busy"
    case .timeout:
      return "timeout"
    case .transport(let transportError):
      switch transportError {
      case .timeout:
        return "transport-timeout"
      case .busy:
        return "transport-busy"
      case .io(let message):
        let lowered = message.lowercased()
        if lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("busy")
        {
          return "transport-io-transient"
        }
        return nil
      default:
        return nil
      }
    default:
      return nil
    }
  }

  static func sendObjectRetryClass(for retryReason: String) -> SendObjectRetryClass {
    switch retryReason {
    case "invalid-parameter-0x201d", "invalid-storage-id-0x2008":
      return .invalidParameter
    case "invalid-object-handle-0x2009":
      return .invalidObjectHandle
    default:
      return .transientTransport
    }
  }

  static func shouldAttemptTargetLadderFallback(
    parent: MTPObjectHandle?,
    retryClass: SendObjectRetryClass
  ) -> Bool {
    switch retryClass {
    case .invalidParameter:
      return true
    case .invalidObjectHandle:
      return parent != nil && parent != 0xFFFFFFFF
    case .transientTransport:
      return false
    }
  }

  private static func requiresHardWriteSessionRecovery(for reason: String) -> Bool {
    reason == "session-not-open-0x2003" || reason == "invalid-object-handle-0x2009"
  }

  private func hardResetWriteSessionIfNeeded(reason: String, debugEnabled: Bool) async -> Bool {
    guard Self.requiresHardWriteSessionRecovery(for: reason) else { return false }
    do {
      if debugEnabled {
        print("   [USB] Session recovery: hard reset for \(reason) (close/reopen/reset tx)")
      }
      try? await self.devClose()
      try await self.openIfNeeded()
      parentStorageIDCache.removeAll(keepingCapacity: true)
      if debugEnabled {
        print("   [USB] Session recovery: hard reset complete")
      }
      return true
    } catch {
      if debugEnabled {
        print("   [USB] Session recovery: hard reset failed (\(error))")
      }
      return false
    }
  }

  private func resolveWriteContextAfterRecovery(
    effectiveParent: MTPObjectHandle?,
    preferredRootStorage: MTPStorageInfo?,
    requiresSubfolder: Bool,
    preferredWriteFolder: String?,
    selectedStorageRaw: UInt32?
  ) async throws -> (
    selectedStorageRaw: UInt32?,
    resolvedParent: MTPObjectHandle?,
    resolution: WriteStorageResolution,
    targetStorageRaw: UInt32
  ) {
    var resolvedParent = effectiveParent
    var nextSelectedStorageRaw = selectedStorageRaw

    if effectiveParent == nil, let first = preferredRootStorage {
      let target = try await WriteTargetLadder.resolveTarget(
        device: self,
        storage: first.id,
        explicitParent: nil,
        requiresSubfolder: requiresSubfolder,
        preferredWriteFolder: preferredWriteFolder
      )
      nextSelectedStorageRaw = target.0.raw
      resolvedParent = target.1
    }

    let link = try await self.getMTPLink()
    let resolution = try await resolveWriteStorageID(
      parent: resolvedParent,
      selectedStorageRaw: nextSelectedStorageRaw,
      link: link
    )
    return (
      selectedStorageRaw: nextSelectedStorageRaw,
      resolvedParent: resolvedParent,
      resolution: resolution,
      targetStorageRaw: resolution.sendObjectInfoStorageID
    )
  }

  static func sendObjectRetryParameters(
    primary: SendObjectRetryParameters,
    retryClass: SendObjectRetryClass,
    isRootParent: Bool,
    allowUnknownObjectInfoSizeRetry: Bool
  ) -> [SendObjectRetryParameters] {
    var retries: [SendObjectRetryParameters] = []

    func appendRetry(_ params: SendObjectRetryParameters, allowPrimary: Bool = false) {
      if !allowPrimary && params == primary { return }
      if retries.contains(params) { return }
      retries.append(params)
    }

    switch retryClass {
    case .invalidParameter:
      let semanticRetry = SendObjectRetryParameters(
        useEmptyDates: primary.useEmptyDates,
        useUndefinedObjectFormat: !primary.useUndefinedObjectFormat,
        useUnknownObjectInfoSize: false,
        omitOptionalObjectInfoFields: false,
        zeroObjectInfoParentHandle: isRootParent,
        useRootCommandParentHandle: false
      )
      appendRetry(semanticRetry)

      if allowUnknownObjectInfoSizeRetry {
        let unknownSizeRetry = SendObjectRetryParameters(
          useEmptyDates: semanticRetry.useEmptyDates,
          useUndefinedObjectFormat: semanticRetry.useUndefinedObjectFormat,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: semanticRetry.omitOptionalObjectInfoFields,
          zeroObjectInfoParentHandle: semanticRetry.zeroObjectInfoParentHandle,
          useRootCommandParentHandle: semanticRetry.useRootCommandParentHandle
        )
        appendRetry(unknownSizeRetry)
      }
    case .invalidObjectHandle:
      break
    case .transientTransport:
      appendRetry(primary, allowPrimary: true)
    }

    return retries
  }

  static func describeSendObjectRetryRung(
    index: Int,
    params: SendObjectRetryParameters,
    primary: SendObjectRetryParameters
  ) -> String {
    if index == 0 && params == primary {
      return "retry-same-params"
    }
    if params.useRootCommandParentHandle {
      if params.zeroObjectInfoParentHandle {
        return "root-command-parent+dataset-parent-zero"
      }
      return "root-command-parent"
    }
    if params.zeroObjectInfoParentHandle && params.useUndefinedObjectFormat {
      if params.useUnknownObjectInfoSize {
        return "format-undefined+dataset-parent-zero+size-unknown"
      }
      return "format-undefined+dataset-parent-zero"
    }
    if params.zeroObjectInfoParentHandle {
      return "dataset-parent-zero"
    }
    if params.useUndefinedObjectFormat && params.useUnknownObjectInfoSize {
      return "format-undefined+size-unknown"
    }
    if params.useUnknownObjectInfoSize {
      return "size-unknown"
    }
    if params.useUndefinedObjectFormat {
      return "format-undefined"
    }
    if params.useEmptyDates {
      return "empty-dates"
    }
    return "retry-\(index + 1)"
  }

  private static func isConcreteStorageID(_ raw: UInt32) -> Bool {
    raw != 0 && raw != 0xFFFFFFFF
  }

  private func resolveWriteStorageID(
    parent: MTPObjectHandle?,
    selectedStorageRaw: UInt32?,
    link: any MTPLink
  ) async throws -> WriteStorageResolution {
    if let parent, parent != 0xFFFFFFFF {
      if let cached = parentStorageIDCache[parent], Self.isConcreteStorageID(cached) {
        return WriteStorageResolution(
          sendObjectInfoStorageID: cached,
          parentStorageID: cached,
          source: "parent-cache"
        )
      }
      if let parentInfo = try await getObjectInfoStrict(handle: parent, link: link) {
        let raw = parentInfo.storage.raw
        if Self.isConcreteStorageID(raw) {
          parentStorageIDCache[parent] = raw
          return WriteStorageResolution(
            sendObjectInfoStorageID: raw,
            parentStorageID: raw,
            source: "parent-object-info"
          )
        }
      }
      throw MTPError.preconditionFailed(
        "Unable to resolve concrete storage ID for parent \(String(format: "0x%08x", parent)).")
    }

    if let selectedStorageRaw, Self.isConcreteStorageID(selectedStorageRaw) {
      return WriteStorageResolution(
        sendObjectInfoStorageID: selectedStorageRaw,
        parentStorageID: nil,
        source: "selected-storage"
      )
    }
    throw MTPError.preconditionFailed("No concrete storage ID available for SendObjectInfo.")
  }

  private func getObjectInfoStrict(handle: MTPObjectHandle, link: any MTPLink) async throws
    -> MTPObjectInfo?
  {
    let payloadBuffer = LockedDataBuffer()
    let result = try await link.executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1008, txid: 0, params: [handle]),
      dataPhaseLength: nil,
      dataInHandler: { raw in
        payloadBuffer.append(raw)
        return raw.count
      },
      dataOutHandler: nil
    )

    do {
      try result.checkOK()
    } catch MTPError.objectNotFound {
      return nil
    }

    let payload = payloadBuffer.snapshot()
    guard !payload.isEmpty else { return nil }

    var reader = PTPReader(data: payload)
    guard let sid = reader.u32(), let format = reader.u16() else { return nil }
    _ = reader.u16()  // ProtectionStatus
    let size = reader.u32()
    _ = reader.u16()  // ThumbFormat
    _ = reader.u32()  // ThumbCompressedSize
    _ = reader.u32()  // ThumbPixWidth
    _ = reader.u32()  // ThumbPixHeight
    _ = reader.u32()  // ImagePixWidth
    _ = reader.u32()  // ImagePixHeight
    _ = reader.u32()  // ImageBitDepth
    let parentRaw = reader.u32()
    _ = reader.u16()  // AssociationType
    _ = reader.u32()  // AssociationDesc
    _ = reader.u32()  // SequenceNumber
    let name = reader.string() ?? "Unknown"
    _ = reader.string()  // CaptureDate — skip
    let modDateStr = reader.string()
    let modified = modDateStr.flatMap { MTPDateString.decode($0) }

    // If the ObjectInfoDataset reports 0xFFFFFFFF for size, the object is > 4 GB.
    // Fall back to GetObjectPropValue(0xDC04) which returns the actual UInt64 size,
    // unless the device quirk flags indicate prop value calls should be skipped.
    var resolvedSize: UInt64? = (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!)
    let skipPropValue = await devicePolicy?.flags.skipGetObjectPropValue ?? false
    if resolvedSize == nil, let _ = size, !skipPropValue {
      if let u64Size = try? await PTPLayer.getObjectSizeU64(handle: handle, on: link) {
        resolvedSize = u64Size
      }
    }

    return MTPObjectInfo(
      handle: handle,
      storage: MTPStorageID(raw: sid),
      parent: parentRaw == 0 ? nil : parentRaw,
      name: name,
      sizeBytes: resolvedSize,
      modified: modified,
      formatCode: format,
      properties: [:]
    )
  }
}
