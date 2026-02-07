// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

// MARK: - Crawl Priority

/// Priority levels for crawl jobs.
public enum CrawlPriority: Int, Comparable, Sendable {
    case background = 0   // full tree scan
    case foreground = 1   // root listing on connect
    case immediate = 2    // user opened folder in Finder

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Crawl Job

private struct CrawlJob: Comparable, Sendable {
    let id: UInt64
    let deviceId: String
    let storageId: UInt32
    let parentHandle: MTPObjectHandle?
    var priority: CrawlPriority

    static func < (lhs: CrawlJob, rhs: CrawlJob) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id < rhs.id
    }

    static func == (lhs: CrawlJob, rhs: CrawlJob) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CrawlScheduler

/// Manages ordered crawling of MTP device trees, feeding results into a `LiveIndexWriter`.
///
/// The scheduler prioritizes user-visible folders (immediate) over background discovery,
/// and yields between folders to avoid starving user operations.
public actor CrawlScheduler {
    private let indexWriter: any LiveIndexWriter
    private var queue: [CrawlJob] = []
    private var nextId: UInt64 = 0
    private var crawlTask: Task<Void, Never>?
    private var cancelled = false

    /// Called when the index changes. Parameters: (deviceId, set of changed parentHandles).
    public var onChange: (@Sendable (String, Set<MTPObjectHandle?>) -> Void)?

    /// Inter-folder yield duration to prevent crawl from starving user ops.
    public var interFolderYield: Duration = .milliseconds(50)

    public init(indexWriter: any LiveIndexWriter) {
        self.indexWriter = indexWriter
    }

    /// Seed the initial crawl on device connect.
    /// Enumerates storages and root folders at foreground priority.
    public func seedOnConnect(deviceId: String, device: any MTPDevice) async {
        do {
            let storages = try await device.storages()
            for storage in storages {
                // Upsert storage metadata
                try await indexWriter.upsertStorage(IndexedStorage(
                    deviceId: deviceId,
                    storageId: storage.id.raw,
                    description: storage.description,
                    capacity: storage.capacityBytes,
                    free: storage.freeBytes,
                    readOnly: storage.isReadOnly
                ))
                // Enqueue root folder crawl
                enqueueJob(deviceId: deviceId, storageId: storage.id.raw, parentHandle: nil, priority: .foreground)
            }
        } catch {
            // Device may have disconnected; silently stop seeding
        }
    }

    /// Boost a subtree to immediate priority (user opened this folder).
    public func boostSubtree(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) {
        // Promote existing job if found, or insert new one
        if let idx = queue.firstIndex(where: {
            $0.deviceId == deviceId && $0.storageId == storageId && $0.parentHandle == parentHandle
        }) {
            queue[idx].priority = .immediate
            queue.sort()
        } else {
            enqueueJob(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle, priority: .immediate)
        }
    }

    /// Start crawling with the given device.
    public func startCrawling(device: any MTPDevice) {
        cancelled = false
        crawlTask = Task { [weak self] in
            guard let self else { return }
            await self.crawlLoop(device: device)
        }
    }

    /// Stop crawling.
    public func stop() {
        cancelled = true
        crawlTask?.cancel()
        crawlTask = nil
    }

    /// Handle an objectAdded event from the device.
    public func handleObjectAdded(deviceId: String, handle: MTPObjectHandle, device: any MTPDevice) async {
        do {
            let objInfo = try await device.getInfo(handle: handle)
            let obj = IndexedObject(
                deviceId: deviceId,
                storageId: objInfo.storage.raw,
                handle: objInfo.handle,
                parentHandle: objInfo.parent,
                name: objInfo.name,
                pathKey: buildPathKey(name: objInfo.name, parent: objInfo.parent),
                sizeBytes: objInfo.sizeBytes,
                mtime: objInfo.modified,
                formatCode: objInfo.formatCode,
                isDirectory: objInfo.formatCode == 0x3001,
                changeCounter: 0 // Will be set by upsertObjects
            )
            try await indexWriter.insertObject(obj, deviceId: deviceId)
            onChange?(deviceId, [objInfo.parent])
        } catch {
            // Object may already be gone
        }
    }

    /// Handle an objectRemoved event from the device.
    public func handleObjectRemoved(deviceId: String, handle: MTPObjectHandle) async {
        // We don't know the storageId from just the handle; mark stale across all storages
        // The object will be found by handle in removeObject
        do {
            // Try to look up the object to know its parent for change notification
            if let obj = try await (indexWriter as? LiveIndexReader)?.object(deviceId: deviceId, handle: handle) {
                try await indexWriter.removeObject(deviceId: deviceId, storageId: obj.storageId, handle: handle)
                onChange?(deviceId, [obj.parentHandle])
            }
        } catch {
            // Already removed
        }
    }

    /// Start periodic refresh for devices that don't support events.
    public func startPeriodicRefresh(deviceId: String, device: any MTPDevice, interval: Duration = .seconds(30)) {
        Task { [weak self] in
            while let s = self, await s.isNotCancelled() != nil {
                try? await Task.sleep(for: interval)
                guard let s2 = self, await s2.isNotCancelled() != nil else { break }
                // Re-seed to refresh the tree
                await s2.seedOnConnect(deviceId: deviceId, device: device)
                await s2.startCrawling(device: device)
            }
        }
    }

    // MARK: - Internal

    private func isNotCancelled() -> Bool? {
        cancelled ? nil : true
    }

    private func enqueueJob(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?, priority: CrawlPriority) {
        let job = CrawlJob(id: nextId, deviceId: deviceId, storageId: storageId, parentHandle: parentHandle, priority: priority)
        nextId += 1
        queue.append(job)
        queue.sort()
    }

    private func crawlLoop(device: any MTPDevice) async {
        while !cancelled, !Task.isCancelled {
            guard !queue.isEmpty else { return }
            let job = queue.removeFirst()

            await crawlFolder(job: job, device: device)

            // Yield to prevent starving user operations
            try? await Task.sleep(for: interFolderYield)
        }
    }

    private func crawlFolder(job: CrawlJob, device: any MTPDevice) async {
        let storageId = MTPStorageID(raw: job.storageId)
        var changedParents: Set<MTPObjectHandle?> = []

        do {
            // Mark existing children stale
            try await indexWriter.markStaleChildren(deviceId: job.deviceId, storageId: job.storageId, parentHandle: job.parentHandle)

            // Enumerate from device
            let stream = device.list(parent: job.parentHandle, in: storageId)
            var objects: [IndexedObject] = []

            for try await batch in stream {
                for objInfo in batch {
                    let isDir = objInfo.formatCode == 0x3001
                    objects.append(IndexedObject(
                        deviceId: job.deviceId,
                        storageId: job.storageId,
                        handle: objInfo.handle,
                        parentHandle: objInfo.parent,
                        name: objInfo.name,
                        pathKey: buildPathKey(name: objInfo.name, parent: objInfo.parent),
                        sizeBytes: objInfo.sizeBytes,
                        mtime: objInfo.modified,
                        formatCode: objInfo.formatCode,
                        isDirectory: isDir,
                        changeCounter: 0
                    ))

                    // Enqueue subdirectories at background priority
                    if isDir {
                        enqueueJob(deviceId: job.deviceId, storageId: job.storageId, parentHandle: objInfo.handle, priority: .background)
                    }
                }
            }

            // Upsert discovered objects
            if !objects.isEmpty {
                try await indexWriter.upsertObjects(objects, deviceId: job.deviceId)
            }

            // Purge objects that were stale and not refreshed
            try await indexWriter.purgeStale(deviceId: job.deviceId, storageId: job.storageId, parentHandle: job.parentHandle)

            changedParents.insert(job.parentHandle)
            onChange?(job.deviceId, changedParents)

        } catch {
            // Crawl failed (device may have disconnected) — leave stale marks for next attempt
        }
    }

    private func buildPathKey(name: String, parent: MTPObjectHandle?) -> String {
        if let p = parent {
            return "\(p)/\(name)"
        }
        return "/\(name)"
    }
}
