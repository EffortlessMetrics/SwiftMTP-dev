// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

extension MTPDeviceActor {
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
    let source: any ByteSource = try FileSource(url: url)
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
      // Create Sendable adapter to avoid capturing non-Sendable source
      let sourceAdapter = SendableSourceAdapter(source)

      // Check if device requires subfolder for writes (quirk flag)
      let requiresSubfolder: Bool
      let preferredWriteFolder: String?
      if let policy = await self.devicePolicy {
        requiresSubfolder = policy.flags.writeToSubfolderOnly
        preferredWriteFolder = policy.flags.preferredWriteFolder
      } else {
        requiresSubfolder = false
        preferredWriteFolder = nil
      }

      // Determine storage ID and parent handle using WriteTargetLadder
      var targetStorageRaw: UInt32 = 0xFFFFFFFF
      var resolvedParent: MTPObjectHandle? = parent

      // If parent is 0 (root) AND device requires subfolder, treat as "no parent" and use WriteTargetLadder
      let effectiveParent: MTPObjectHandle? = (parent == 0 && requiresSubfolder) ? nil : parent

      if let p = effectiveParent {
        // Parent specified - get storage from parent info
        if let parentInfos = try? await link.getObjectInfos([p]), let parentInfo = parentInfos.first
        {
          targetStorageRaw = parentInfo.storage.raw
        }
      } else {
        // No parent or parent=0 with requiresSubfolder - need to resolve target
        if let storages = try? await self.storages(), let first = storages.first {
          targetStorageRaw = first.id.raw
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
              .info(
                "Device requires subfolder for writes, resolved to parent handle \(resolvedParent!)"
              )
          }
        }
      }

      // Check if device requires 0xFFFFFFFF for storage ID in SendObjectInfo
      let forceFFFFFFF = (await self.devicePolicy?.flags.forceFFFFFFFForSendObject) ?? false
      let useEmptyDates = (await self.devicePolicy?.flags.emptyDatesInSendObject) ?? false
      let sendObjectStorageID = forceFFFFFFF ? 0xFFFFFFFF : targetStorageRaw

      // Use thread-safe progress tracking
      let progressTracker = AtomicProgressTracker()

      try await ProtoTransfer.writeWholeObject(
        storageID: sendObjectStorageID, parent: resolvedParent, name: name, size: size,
        dataHandler: { buf in
          let produced = sourceAdapter.produce(buf)
          let totalBytes = progressTracker.add(Int(produced))
          progress.completedUnitCount = Int64(totalBytes)
          return Int(produced)
        }, on: link, ioTimeoutMs: timeout,
        forceFFFFFFF: forceFFFFFFF,
        useEmptyDates: useEmptyDates)

      let bytesRead = progressTracker.total

      // Update journal after transfer completes
      if let journal = transferJournal, let transferId = journalTransferId {
        try await journal.updateProgress(id: transferId, committed: bytesRead)
      }

      progress.completedUnitCount = total
      try source.close()

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
      try? source.close()

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
