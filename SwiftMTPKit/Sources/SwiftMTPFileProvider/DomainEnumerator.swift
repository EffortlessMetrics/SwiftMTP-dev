// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPCore
import SwiftMTPXPC

/// Cache-first File Provider domain enumerator.
///
/// Reads directly from the local SQLite live index (no XPC for metadata).
/// If the index is empty for a folder, fires a background crawl request via XPC.
public final class DomainEnumerator: NSObject, NSFileProviderEnumerator {
    private let deviceId: String
    private let storageId: UInt32?
    private let parentHandle: UInt32?
    private let indexReader: (any LiveIndexReader)?
    private var xpcConnection: NSXPCConnection?

    public init(deviceId: String, storageId: UInt32? = nil, parentHandle: UInt32? = nil, indexReader: (any LiveIndexReader)?) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.parentHandle = parentHandle
        self.indexReader = indexReader
        super.init()
    }

    deinit {
        xpcConnection?.invalidate()
    }

    public func invalidate() {
        xpcConnection?.invalidate()
    }

    // MARK: - Enumeration

    public func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                guard let reader = indexReader else {
                    observer.finishEnumerating(upTo: nil)
                    return
                }

                var items: [NSFileProviderItem] = []

                if storageId == nil {
                    // Enumerate storages
                    let storages = try await reader.storages(deviceId: deviceId)
                    for storage in storages {
                        let item = MTPFileProviderItem(
                            deviceId: deviceId,
                            storageId: storage.storageId,
                            objectHandle: nil,
                            name: storage.description,
                            size: nil,
                            isDirectory: true,
                            modifiedDate: nil
                        )
                        items.append(item)
                    }

                    if storages.isEmpty {
                        triggerCrawl(storageId: 0, parentHandle: nil)
                    }
                } else {
                    // Enumerate objects in a directory
                    let objects = try await reader.children(
                        deviceId: deviceId,
                        storageId: storageId!,
                        parentHandle: parentHandle
                    )
                    for obj in objects {
                        let item = MTPFileProviderItem(
                            deviceId: deviceId,
                            storageId: obj.storageId,
                            objectHandle: obj.handle,
                            parentHandle: obj.parentHandle,
                            name: obj.name,
                            size: obj.sizeBytes,
                            isDirectory: obj.isDirectory,
                            modifiedDate: obj.mtime
                        )
                        items.append(item)
                    }

                    if objects.isEmpty {
                        // Cache is empty for this folder — trigger background crawl
                        triggerCrawl(storageId: storageId!, parentHandle: parentHandle)
                    }
                }

                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    // MARK: - Change Tracking

    public func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                guard let reader = indexReader else {
                    observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
                    return
                }

                // Decode anchor as Int64 change counter
                let anchorValue = decodeSyncAnchor(anchor)

                let changes = try await reader.changesSince(deviceId: deviceId, anchor: anchorValue)

                var updatedItems: [NSFileProviderItem] = []
                var deletedIdentifiers: [NSFileProviderItemIdentifier] = []

                for change in changes {
                    switch change.kind {
                    case .upserted:
                        let item = MTPFileProviderItem(
                            deviceId: change.object.deviceId,
                            storageId: change.object.storageId,
                            objectHandle: change.object.handle,
                            parentHandle: change.object.parentHandle,
                            name: change.object.name,
                            size: change.object.sizeBytes,
                            isDirectory: change.object.isDirectory,
                            modifiedDate: change.object.mtime
                        )
                        updatedItems.append(item)
                    case .deleted:
                        let identifier = NSFileProviderItemIdentifier(
                            "\(change.object.deviceId):\(change.object.storageId):\(change.object.handle)"
                        )
                        deletedIdentifiers.append(identifier)
                    }
                }

                observer.didUpdate(updatedItems)
                observer.didDeleteItems(withIdentifiers: deletedIdentifiers)

                // Encode new anchor
                let currentCounter = try await reader.currentChangeCounter(deviceId: deviceId)
                let newAnchor = encodeSyncAnchor(currentCounter)
                observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        Task {
            guard let reader = indexReader else {
                completionHandler(nil)
                return
            }
            do {
                let counter = try await reader.currentChangeCounter(deviceId: deviceId)
                completionHandler(encodeSyncAnchor(counter))
            } catch {
                completionHandler(nil)
            }
        }
    }

    // MARK: - Sync Anchor Encoding

    private func encodeSyncAnchor(_ counter: Int64) -> NSFileProviderSyncAnchor {
        var value = counter
        let data = Data(bytes: &value, count: MemoryLayout<Int64>.size)
        return NSFileProviderSyncAnchor(data)
    }

    private func decodeSyncAnchor(_ anchor: NSFileProviderSyncAnchor) -> Int64 {
        let data = anchor.rawValue
        guard data.count == MemoryLayout<Int64>.size else { return 0 }
        return data.withUnsafeBytes { $0.load(as: Int64.self) }
    }

    // MARK: - Crawl Trigger

    /// Fire-and-forget XPC call to trigger a priority crawl for this folder.
    private func triggerCrawl(storageId: UInt32, parentHandle: UInt32?) {
        let connection = getXPCConnection()
        guard let xpcService = connection.remoteObjectProxy as? MTPXPCService else { return }
        let request = CrawlTriggerRequest(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle)
        Task { @MainActor in
            xpcService.requestCrawl(request) { _ in /* fire and forget */ }
        }
    }

    private func getXPCConnection() -> NSXPCConnection {
        if let conn = xpcConnection { return conn }
        let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
        conn.resume()
        xpcConnection = conn
        return conn
    }
}
