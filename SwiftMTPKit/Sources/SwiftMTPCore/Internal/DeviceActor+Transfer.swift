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

      // Determine storage ID and parent handle using WriteTargetLadder
      let availableStorages = try? await self.storages()
      let rootStorages = availableStorages ?? []
      let preferredRootStorage = rootStorages.first(where: { !$0.isReadOnly }) ?? rootStorages.first

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
            .info("Device requires subfolder for writes, resolved to parent handle \(resolvedParent!)")
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
          if let info = try await self.getObjectInfoStrict(handle: parent, link: link) {
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
        try await ProtoTransfer.writeWholeObject(
          storageID: storageRaw, parent: parent, name: name, size: size,
          dataHandler: { buf in
            let produced = sourceAdapter.produce(buf)
            let totalBytes = progressTracker.add(Int(produced))
            progress.completedUnitCount = Int64(totalBytes)
            return Int(produced)
          }, on: link, ioTimeoutMs: timeout,
          useEmptyDates: params.useEmptyDates,
          useUndefinedObjectFormat: params.useUndefinedObjectFormat,
          useUnknownObjectInfoSize: params.useUnknownObjectInfoSize,
          omitOptionalObjectInfoFields: params.omitOptionalObjectInfoFields,
          zeroObjectInfoParentHandle: params.zeroObjectInfoParentHandle
        )
        return progressTracker.total
      }

      func recoverSessionIfNeeded(for reason: String) async {
        guard reason == "session-not-open-0x2003" else { return }
        let postOpenStabilizeMs = max(policy?.tuning.stabilizeMs ?? 0, 200)
        do {
          try await link.openSession(id: 1)
          if postOpenStabilizeMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(postOpenStabilizeMs) * 1_000_000)
          }
          if debugEnabled {
            print(
              "   [USB] Session recovery: reopened session after 0x2003 (stabilized \(postOpenStabilizeMs)ms)"
            )
          }
        } catch let mtpError as MTPError {
          if mtpError.isSessionAlreadyOpen {
            if debugEnabled {
              print("   [USB] Session recovery: session already open")
            }
          } else if debugEnabled {
            print("   [USB] Session recovery: openSession failed (\(mtpError))")
          }
        } catch {
          if debugEnabled {
            print("   [USB] Session recovery: openSession failed (\(error))")
          }
        }
      }

      var bytesRead: UInt64 = 0
      let isLabSmokeWrite = name.hasPrefix("swiftmtp-smoke-")
      let primaryParams = SendObjectRetryParameters(
        useEmptyDates: useEmptyDates,
        useUndefinedObjectFormat: false,
        useUnknownObjectInfoSize: false,
        omitOptionalObjectInfoFields: false,
        zeroObjectInfoParentHandle: false
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

        guard let retryReason = Self.retryableSendObjectFailureReason(for: error) else {
          throw error
        }
        await recoverSessionIfNeeded(for: retryReason)
        let retryClass = Self.sendObjectRetryClass(for: retryReason)

        let configuredStrategy = policy?.fallbacks.write.rawValue ?? "unknown"
        Logger(subsystem: "SwiftMTP", category: "write")
          .warning(
            "SendObject failed (\(retryReason), strategy=\(configuredStrategy)); retrying with fallback parameter ladder")

        let retryParameters = Self.sendObjectRetryParameters(
          primary: primaryParams,
          retryClass: retryClass
        )
        var sawInvalidObjectHandle = retryClass == .invalidObjectHandle
        var lastRetryableError: Error = error
        var recovered = false

        for (index, retryParams) in retryParameters.enumerated() {
          do {
            Logger(subsystem: "SwiftMTP", category: "write")
              .info(
                "SendObject retry rung=\(Self.describeSendObjectRetryRung(index: index, params: retryParams, primary: primaryParams))")
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
            await recoverSessionIfNeeded(for: reason)
            if Self.sendObjectRetryClass(for: reason) == .invalidObjectHandle {
              sawInvalidObjectHandle = true
              if let currentParent = resolvedParent, currentParent != 0xFFFFFFFF {
                var existingParent: MTPObjectInfo?
                do {
                  existingParent = try await self.getObjectInfoStrict(handle: currentParent, link: link)
                } catch {
                  if let reason = Self.retryableSendObjectFailureReason(for: error) {
                    await recoverSessionIfNeeded(for: reason)
                  }
                  do {
                    existingParent = try await self.getObjectInfoStrict(
                      handle: currentParent,
                      link: link
                    )
                  } catch {
                    if debugEnabled {
                      print("   [USB] Parent handle refresh: unable to verify current parent (\(error))")
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
                    storageResolution = try await resolveWriteStorageID(
                      parent: resolvedParent,
                      selectedStorageRaw: targetStorageRaw,
                      link: link
                    )
                    targetStorageRaw = storageResolution.sendObjectInfoStorageID
                    if debugEnabled {
                      print(
                        "   [USB] Parent handle refresh: old=\(String(format: "0x%08x", oldParent)) new=\(String(format: "0x%08x", resolvedParent ?? 0xFFFFFFFF)) storage=\(String(format: "0x%08x", targetStorageRaw))"
                      )
                    }
                  } catch {
                    if let reason = Self.retryableSendObjectFailureReason(for: error) {
                      await recoverSessionIfNeeded(for: reason)
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

        // For InvalidParameter at root, immediately switch target folder after one conservative retry.
        let ladderStorage =
          availableStorages?.first(where: { $0.id.raw == targetStorageRaw })
          ?? availableStorages?.first
        if !recovered,
          (Self.shouldAttemptTargetLadderFallback(parent: parent, retryClass: retryClass)
            || sawInvalidObjectHandle),
          let firstStorage = ladderStorage
        {
          do {
            Logger(subsystem: "SwiftMTP", category: "write")
              .info("SendObject retry rung=target-ladder (Download/DCIM/.../SwiftMTP)")
            let fallback = try await WriteTargetLadder.resolveTarget(
              device: self,
              storage: firstStorage.id,
              explicitParent: nil,
              requiresSubfolder: true,
              preferredWriteFolder: preferredWriteFolder,
              excludingParent: resolvedParent
            )
            targetStorageRaw = fallback.0.raw
            resolvedParent = fallback.1
            storageResolution = try await resolveWriteStorageID(
              parent: resolvedParent,
              selectedStorageRaw: targetStorageRaw,
              link: link
            )
            targetStorageRaw = storageResolution.sendObjectInfoStorageID
            let ladderParams =
              (retryClass == .invalidParameter || sawInvalidObjectHandle)
              ? SendObjectRetryParameters(
                useEmptyDates: true,
                useUndefinedObjectFormat: true,
                useUnknownObjectInfoSize: true,
                omitOptionalObjectInfoFields: true,
                zeroObjectInfoParentHandle: false
              )
              : primaryParams
            bytesRead = try await performWrite(
              to: resolvedParent,
              storageRaw: targetStorageRaw,
              params: ladderParams,
              resolution: storageResolution
            )
            recovered = true
          } catch {
            guard let reason = Self.retryableSendObjectFailureReason(for: error) else {
              throw error
            }
            await recoverSessionIfNeeded(for: reason)
            lastRetryableError = error
          }
        }

        if !recovered { throw lastRetryableError }
      }

      // Update journal after transfer completes
      if let journal = transferJournal, let transferId = journalTransferId {
        try await journal.updateProgress(id: transferId, committed: bytesRead)
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

  static func sendObjectRetryParameters(
    primary: SendObjectRetryParameters,
    retryClass: SendObjectRetryClass
  ) -> [SendObjectRetryParameters] {
    var retries: [SendObjectRetryParameters] = []

    func appendRetry(_ params: SendObjectRetryParameters, allowPrimary: Bool = false) {
      if !allowPrimary && params == primary { return }
      if retries.contains(params) { return }
      retries.append(params)
    }

    switch retryClass {
    case .invalidParameter:
      if !primary.useUndefinedObjectFormat {
        appendRetry(
          SendObjectRetryParameters(
            useEmptyDates: primary.useEmptyDates,
            useUndefinedObjectFormat: true,
            useUnknownObjectInfoSize: false,
            omitOptionalObjectInfoFields: false,
            zeroObjectInfoParentHandle: false
          ))
      }
      if !(primary.useEmptyDates && primary.useUndefinedObjectFormat) {
        appendRetry(
          SendObjectRetryParameters(
            useEmptyDates: true,
            useUndefinedObjectFormat: true,
            useUnknownObjectInfoSize: false,
            omitOptionalObjectInfoFields: false,
            zeroObjectInfoParentHandle: false
          ))
      }
      if !(primary.useEmptyDates && primary.useUndefinedObjectFormat && primary.useUnknownObjectInfoSize) {
        appendRetry(
          SendObjectRetryParameters(
            useEmptyDates: true,
            useUndefinedObjectFormat: true,
            useUnknownObjectInfoSize: true,
            omitOptionalObjectInfoFields: false,
            zeroObjectInfoParentHandle: false
          ))
      }
      if !(
        primary.useEmptyDates
          && primary.useUndefinedObjectFormat
          && primary.useUnknownObjectInfoSize
          && primary.omitOptionalObjectInfoFields
      ) {
        appendRetry(
          SendObjectRetryParameters(
            useEmptyDates: true,
            useUndefinedObjectFormat: true,
            useUnknownObjectInfoSize: true,
            omitOptionalObjectInfoFields: true,
            zeroObjectInfoParentHandle: false
          ))
      }
      if !(
        primary.useEmptyDates
          && primary.useUndefinedObjectFormat
          && primary.useUnknownObjectInfoSize
          && primary.omitOptionalObjectInfoFields
          && primary.zeroObjectInfoParentHandle
      ) {
        appendRetry(
          SendObjectRetryParameters(
            useEmptyDates: true,
            useUndefinedObjectFormat: true,
            useUnknownObjectInfoSize: true,
            omitOptionalObjectInfoFields: true,
            zeroObjectInfoParentHandle: true
          ))
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
    if params.useEmptyDates && params.useUndefinedObjectFormat && params.useUnknownObjectInfoSize {
      if params.omitOptionalObjectInfoFields && params.zeroObjectInfoParentHandle {
        return "minimal-object-info+dataset-parent-zero"
      }
      if params.omitOptionalObjectInfoFields {
        return "minimal-object-info"
      }
    }
    if params.omitOptionalObjectInfoFields && params.zeroObjectInfoParentHandle {
      return "omit-optional-fields+dataset-parent-zero"
    }
    if params.omitOptionalObjectInfoFields {
      return "omit-optional-fields"
    }
    if params.zeroObjectInfoParentHandle {
      return "dataset-parent-zero"
    }
    if params.useEmptyDates && params.useUndefinedObjectFormat {
      if params.useUnknownObjectInfoSize {
        return "empty-dates+format-undefined+size-unknown"
      }
      return "empty-dates+format-undefined"
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

    return MTPObjectInfo(
      handle: handle,
      storage: MTPStorageID(raw: sid),
      parent: parentRaw == 0 ? nil : parentRaw,
      name: name,
      sizeBytes: (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!),
      modified: nil,
      formatCode: format,
      properties: [:]
    )
  }
}
