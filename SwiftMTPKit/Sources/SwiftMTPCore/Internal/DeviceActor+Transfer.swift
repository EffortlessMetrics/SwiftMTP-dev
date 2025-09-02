import Foundation
import SwiftMTPObservability

extension MTPDeviceActor {
    public func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress {
        let link = try await getMTPLink()
        let info = try await getObjectInfo(handle, using: link)
        let deviceInfo = try await self.info

        let total = Int64(info.sizeBytes ?? 0)
        let progress = Progress(totalUnitCount: total > 0 ? total : -1)
        let timeout = 10_000 // 10 seconds
        let temp = url.appendingPathExtension("part")

        // Check if partial read is supported
        let supportsPartial = deviceInfo.operationsSupported.contains(0x95C4) // GetPartialObject64

        var transferId: String?
        var sink: any ByteSink

        // Try to resume if we have a journal
        if let journal = transferJournal {
            do {
                let resumables = try journal.loadResumables(for: id)
                if let existing = resumables.first(where: { $0.handle == handle && $0.kind == "read" }) {
                    // Resume from existing temp file
                    if FileManager.default.fileExists(atPath: existing.localTempURL.path) {
                        sink = try FileSink(url: existing.localTempURL, append: true)
                        transferId = existing.id
                        progress.completedUnitCount = Int64(existing.committedBytes)
                    } else {
                        // Temp file missing, start fresh
                        sink = try FileSink(url: temp)
                        transferId = try journal.beginRead(
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
                    transferId = try journal.beginRead(
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
            var bytesWritten: UInt64 = 0

            try await ProtoTransfer.readWholeObject(handle: handle, on: link, dataHandler: { buf in
                do {
                    try sink.write(buf)
                    bytesWritten += UInt64(buf.count)
                    progress.completedUnitCount = Int64(bytesWritten)
                    return buf.count
                } catch {
                    return 0
                }
            }, ioTimeoutMs: timeout)

            // Update journal after transfer completes
            if let journal = transferJournal, let transferId = transferId {
                try journal.updateProgress(id: transferId, committed: bytesWritten)
            }

            try sink.close()

            // Mark as complete in journal
            if let journal = transferJournal, let transferId = transferId {
                try journal.complete(id: transferId)
            }

            try atomicReplace(temp: temp, final: url)
            return progress
        } catch {
            try? sink.close()
            try? FileManager.default.removeItem(at: temp)

            // Mark as failed in journal
            if let journal = transferJournal, let transferId = transferId {
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

        // Check if partial write is supported
        let supportsPartial = deviceInfo.operationsSupported.contains(0x95C1) // SendPartialObject

        var transferId: String?
        var source: any ByteSource = try FileSource(url: url)
        let timeout = 10_000 // 10 seconds

        // Initialize transfer journal if available
        if let journal = transferJournal {
            do {
                transferId = try journal.beginWrite(
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
            var bytesRead: UInt64 = 0

            try await ProtoTransfer.writeWholeObject(parent: parent, name: name, size: size, dataHandler: { buf in
                do {
                    let read = try source.read(into: buf)
                    bytesRead += UInt64(read)
                    progress.completedUnitCount = Int64(bytesRead)
                    return read
                } catch {
                    return 0
                }
            }, on: link, ioTimeoutMs: timeout)

            // Update journal after transfer completes
            if let journal = transferJournal, let transferId = transferId {
                try journal.updateProgress(id: transferId, committed: bytesRead)
            }

            progress.completedUnitCount = total
            try source.close()

            // Mark as complete in journal
            if let journal = transferJournal, let transferId = transferId {
                try journal.complete(id: transferId)
            }

            return progress
        } catch {
            try? source.close()

            // Mark as failed in journal
            if let journal = transferJournal, let transferId = transferId {
                try? journal.fail(id: transferId, error: error)
            }

            throw error
        }
    }
}
