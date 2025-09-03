import Foundation
import SwiftMTPObservability
import OSLog

extension MTPDeviceActor {
    public func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress {
        let link = try await getMTPLink()
        let info = try await getObjectInfo(handle, using: link)
        let deviceInfo = try await self.info

        let total = Int64(info.sizeBytes ?? 0)
        let progress = Progress(totalUnitCount: total > 0 ? total : -1)
        let timeout = 10_000 // 10 seconds
        let temp = url.appendingPathExtension("part")

        // Performance logging: begin transfer
        let startTime = Date()
        MTPLog.perf.info("Transfer begin: read \(info.name) handle=\(handle) size=\(info.sizeBytes ?? 0)")

        // Check if partial read is supported
        let supportsPartial = deviceInfo.operationsSupported.contains(0x95C4) // GetPartialObject64

        var journalTransferId: String?
        var sink: any ByteSink

        // Try to resume if we have a journal
        if let journal = transferJournal {
            do {
                let resumables = try journal.loadResumables(for: id)
                if let existing = resumables.first(where: { $0.handle == handle && $0.kind == "read" }) {
                    // Resume from existing temp file
                    if FileManager.default.fileExists(atPath: existing.localTempURL.path) {
                        sink = try FileSink(url: existing.localTempURL, append: true)
                        journalTransferId = existing.id
                        progress.completedUnitCount = Int64(existing.committedBytes)
                    } else {
                        // Temp file missing, start fresh
                        sink = try FileSink(url: temp)
                        journalTransferId = try journal.beginRead(
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
                                            journalTransferId = try journal.beginRead(
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

        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                             reason: "SwiftMTP read")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            // Create Sendable adapter to avoid capturing non-Sendable sink
            let sinkAdapter = SendableSinkAdapter(sink)

            // Use thread-safe progress tracking
            let progressTracker = AtomicProgressTracker()

            try await ProtoTransfer.readWholeObject(handle: handle, on: link, dataHandler: { buf in
                let consumed = sinkAdapter.consume(buf)
                let totalBytes = progressTracker.add(consumed)
                progress.completedUnitCount = Int64(totalBytes)
                return consumed
            }, ioTimeoutMs: timeout)

            let bytesWritten = progressTracker.total

            // Update journal after transfer completes
            if let journal = transferJournal, let transferId = journalTransferId {
                try journal.updateProgress(id: transferId, committed: bytesWritten)
            }

            try sink.close()

            // Mark as complete in journal
            if let journal = transferJournal, let transferId = journalTransferId {
                try journal.complete(id: transferId)
            }

            try atomicReplace(temp: temp, final: url)

            // Performance logging: end transfer (success)
            let duration = Date().timeIntervalSince(startTime)
            let throughput = Double(bytesWritten) / duration
            MTPLog.perf.info("Transfer completed: read \(bytesWritten) bytes in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", throughput/1024/1024)) MB/s)")

            return progress
        } catch {
            try? sink.close()
            try? FileManager.default.removeItem(at: temp)

            // Performance logging: end transfer (failure)
            let duration = Date().timeIntervalSince(startTime)
            MTPLog.perf.error("Transfer failed: read after \(String(format: "%.2f", duration))s - \(error.localizedDescription)")

            // Mark as failed in journal
            if let journal = transferJournal, let transferId = journalTransferId {
                try? journal.fail(id: transferId, error: error)
            }

            throw error
        }
    }

    public func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws -> Progress {
        let link = try await getMTPLink()
        let deviceInfo = try await self.info
        let total = Int64(size)
        let progress = Progress(totalUnitCount: Int64(size))

        // Performance logging: begin transfer
        let startTime = Date()
        MTPLog.perf.info("Transfer begin: write \(name) size=\(size)")

        // Check if partial write is supported
        let supportsPartial = deviceInfo.operationsSupported.contains(0x95C1) // SendPartialObject

        var journalTransferId: String?
        var source: any ByteSource = try FileSource(url: url)
        let timeout = 10_000 // 10 seconds

        // Initialize transfer journal if available
        if let journal = transferJournal {
            do {
                journalTransferId = try journal.beginWrite(
                    device: id,
                    parent: parent ?? 0,
                    name: name,
                    size: size,
                    supportsPartial: supportsPartial,
                    tempURL: url, // Not really a temp for writes, but we need a URL
                    sourceURL: url
                )
            } catch {
                // Journal failed, proceed without it
            }
        }

        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                             reason: "SwiftMTP write")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            // Create Sendable adapter to avoid capturing non-Sendable source
            let sourceAdapter = SendableSourceAdapter(source)

            // Use thread-safe progress tracking
            let progressTracker = AtomicProgressTracker()

            try await ProtoTransfer.writeWholeObject(parent: parent, name: name, size: size, dataHandler: { buf in
                let produced = sourceAdapter.produce(buf)
                let totalBytes = progressTracker.add(produced)
                progress.completedUnitCount = Int64(totalBytes)
                return produced
            }, on: link, ioTimeoutMs: timeout)

            let bytesRead = progressTracker.total

            // Update journal after transfer completes
            if let journal = transferJournal, let transferId = journalTransferId {
                try journal.updateProgress(id: transferId, committed: bytesRead)
            }

            progress.completedUnitCount = total
            try source.close()

            // Mark as complete in journal
            if let journal = transferJournal, let transferId = journalTransferId {
                try journal.complete(id: transferId)
            }

            // Performance logging: end transfer (success)
            let duration = Date().timeIntervalSince(startTime)
            let throughput = Double(bytesRead) / duration
            MTPLog.perf.info("Transfer completed: write \(bytesRead) bytes in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", throughput/1024/1024)) MB/s)")

            return progress
        } catch {
            try? source.close()

            // Performance logging: end transfer (failure)
            let duration = Date().timeIntervalSince(startTime)
            MTPLog.perf.error("Transfer failed: write after \(String(format: "%.2f", duration))s - \(error.localizedDescription)")

            // Mark as failed in journal
            if let journal = transferJournal, let transferId = journalTransferId {
                try? journal.fail(id: transferId, error: error)
            }

            throw error
        }
    }
}
