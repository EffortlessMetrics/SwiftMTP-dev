// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

extension MTPDeviceActor {
  private enum SendObjectRetryClass {
    case invalidParameter
    case transientTransport
  }

  public func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID)
    async throws -> MTPObjectHandle
  {
    try await openIfNeeded()
    let link = try await getMTPLink()
    let parentHandle = parent ?? 0xFFFFFFFF
    return try await BusyBackoff.onDeviceBusy {
      try await ProtoTransfer.createFolder(
        storageID: storage.raw, parent: parentHandle, name: name,
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
    let timeout = 10_000  // 10 seconds

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

      // Check if device requires subfolder for writes (quirk flag)
      let requiresSubfolder = policy?.flags.writeToSubfolderOnly ?? false
      let preferredWriteFolder = policy?.flags.preferredWriteFolder

      // Check if device requires 0xFFFFFFFF for storage ID in SendObjectInfo
      let forceFFFFFFF = policy?.flags.forceFFFFFFFForSendObject ?? false
      let useEmptyDates = policy?.flags.emptyDatesInSendObject ?? false

      // Determine storage ID and parent handle using WriteTargetLadder
      let availableStorages = try? await self.storages()
      let rootStorages = availableStorages ?? []

      var targetStorageRaw: UInt32 = 0xFFFFFFFF
      var resolvedParent: MTPObjectHandle? = parent

      // If parent is 0 (root) AND device requires subfolder, treat as "no parent" and use WriteTargetLadder
      let effectiveParent: MTPObjectHandle? = (parent == 0 && requiresSubfolder) ? nil : parent

      if let p = effectiveParent {
        // Parent specified - get storage from parent info
        if let parentInfos = try? await link.getObjectInfos([p]), let parentInfo = parentInfos.first {
          targetStorageRaw = parentInfo.storage.raw
        } else if let storage = rootStorages.first {
          targetStorageRaw = storage.id.raw
        }
      } else if let first = rootStorages.first {
        // No parent or parent=0 with requiresSubfolder - need to resolve target
        let target = try await WriteTargetLadder.resolveTarget(
          device: self,
          storage: first.id,
          explicitParent: nil,
          requiresSubfolder: requiresSubfolder,
          preferredWriteFolder: preferredWriteFolder
        )
        targetStorageRaw = target.0.raw
        resolvedParent = target.1

        // Log where we're writing to
        if requiresSubfolder {
          Logger(subsystem: "SwiftMTP", category: "write")
            .info("Device requires subfolder for writes, resolved to parent handle \(resolvedParent!)")
        }
      }

      struct WriteAttemptParameters: Equatable {
        let forceWildcardStorage: Bool
        let useEmptyDates: Bool
      }

      func performWrite(
        to parent: MTPObjectHandle?,
        storageRaw: UInt32,
        params: WriteAttemptParameters
      ) async throws -> UInt64 {
        let source = try FileSource(url: url)
        defer { try? source.close() }

        let sourceAdapter = SendableSourceAdapter(source)
        let progressTracker = AtomicProgressTracker()
        let sendObjectStorageID = params.forceWildcardStorage ? 0xFFFFFFFF : storageRaw
        try await ProtoTransfer.writeWholeObject(
          storageID: sendObjectStorageID, parent: parent, name: name, size: size,
          dataHandler: { buf in
            let produced = sourceAdapter.produce(buf)
            let totalBytes = progressTracker.add(Int(produced))
            progress.completedUnitCount = Int64(totalBytes)
            return Int(produced)
          }, on: link, ioTimeoutMs: timeout,
          forceFFFFFFF: params.forceWildcardStorage,
          useEmptyDates: params.useEmptyDates
        )
        return progressTracker.total
      }

      var bytesRead: UInt64 = 0
      let primaryParams = WriteAttemptParameters(
        forceWildcardStorage: forceFFFFFFF,
        useEmptyDates: useEmptyDates
      )

      do {
        bytesRead = try await performWrite(
          to: resolvedParent,
          storageRaw: targetStorageRaw,
          params: primaryParams
        )
      } catch {
        guard let retryReason = retryableSendObjectFailureReason(error) else {
          throw error
        }
        let retryClass = sendObjectRetryClass(for: retryReason)

        let configuredStrategy = policy?.fallbacks.write.rawValue ?? "unknown"
        Logger(subsystem: "SwiftMTP", category: "write")
          .warning(
            "SendObject failed (\(retryReason), strategy=\(configuredStrategy)); retrying with conservative parameters")

        let conservativeParams = WriteAttemptParameters(
          forceWildcardStorage: true,
          useEmptyDates: true
        )
        var lastRetryableError: Error = error
        var recovered = false

        // Single conservative retry (whole-object compatible metadata/profile).
        if conservativeParams != primaryParams {
          do {
            Logger(subsystem: "SwiftMTP", category: "write")
              .info("SendObject retry rung=conservative (wildcard storage + empty dates)")
            bytesRead = try await performWrite(
              to: resolvedParent,
              storageRaw: targetStorageRaw,
              params: conservativeParams
            )
            recovered = true
          } catch {
            guard retryableSendObjectFailureReason(error) != nil else {
              throw error
            }
            lastRetryableError = error
          }
        }

        // For InvalidParameter at root, immediately switch target folder after one conservative retry.
        if !recovered, retryClass == .invalidParameter, (parent == nil || parent == 0),
          let firstStorage = availableStorages?.first
        {
          do {
            Logger(subsystem: "SwiftMTP", category: "write")
              .info("SendObject retry rung=target-ladder (Download/DCIM/.../SwiftMTP)")
            let fallback = try await WriteTargetLadder.resolveTarget(
              device: self,
              storage: firstStorage.id,
              explicitParent: nil,
              requiresSubfolder: true,
              preferredWriteFolder: preferredWriteFolder
            )
            targetStorageRaw = fallback.0.raw
            resolvedParent = fallback.1
            bytesRead = try await performWrite(
              to: resolvedParent,
              storageRaw: targetStorageRaw,
              params: conservativeParams
            )
            recovered = true
          } catch {
            guard retryableSendObjectFailureReason(error) != nil else {
              throw error
            }
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

  private func retryableSendObjectFailureReason(_ error: Error) -> String? {
    guard let mtpError = error as? MTPError else { return nil }
    switch mtpError {
    case .protocolError(let code, _) where code == 0x201D:
      return "invalid-parameter-0x201d"
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

  private func sendObjectRetryClass(for retryReason: String) -> SendObjectRetryClass {
    if retryReason == "invalid-parameter-0x201d" {
      return .invalidParameter
    }
    return .transientTransport
  }
}
