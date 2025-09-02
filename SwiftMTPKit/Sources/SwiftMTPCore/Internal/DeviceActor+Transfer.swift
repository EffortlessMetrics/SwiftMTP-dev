import Foundation
import SwiftMTPObservability

extension MTPDeviceActor {
    public func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress {
        let link = try await getMTPLink()
        let info = try await getObjectInfo(handle, using: link)

        let total = Int64(info.sizeBytes ?? 0)
        let progress = Progress(totalUnitCount: total > 0 ? total : -1)
        let timeout = 10_000 // 10 seconds
        let temp = url.appendingPathExtension("part")
        var sink: any ByteSink = try FileSink(url: temp)

        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                             reason: "SwiftMTP read")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            // For now, use whole object read (partial read support can be added later)
            try await ProtoTransfer.readWholeObject(handle: handle, on: link, dataHandler: { buf in
                do {
                    try sink.write(buf)
                    return buf.count
                } catch {
                    return 0
                }
            }, ioTimeoutMs: timeout)
            if total > 0 { progress.completedUnitCount = total }

            try sink.close()
            try atomicReplace(temp: temp, final: url)
            return progress
        } catch {
            try? sink.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    public func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws -> Progress {
        let link = try await getMTPLink()
        let total = Int64(size)
        let progress = Progress(totalUnitCount: Int64(size))
        var source: any ByteSource = try FileSource(url: url)
        let timeout = 10_000 // 10 seconds

        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                             reason: "SwiftMTP write")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            try await ProtoTransfer.writeWholeObject(parent: parent, name: name, size: size, dataHandler: { buf in
                do {
                    let written = try source.read(into: buf)
                    return written
                } catch {
                    return 0
                }
            }, on: link, ioTimeoutMs: timeout)
            progress.completedUnitCount = total
            try source.close()
            return progress
        } catch {
            try? source.close()
            throw error
        }
    }
}
