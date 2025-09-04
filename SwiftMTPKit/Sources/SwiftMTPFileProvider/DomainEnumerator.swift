// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import FileProvider
import SwiftMTPXPC

/// File Provider domain enumerator for browsing MTP device contents
/// This provides the hierarchical view of device storages and files
public final class DomainEnumerator: NSObject, NSFileProviderEnumerator {
    private let deviceId: String
    private let storageId: UInt32?
    private let parentHandle: UInt32?
    private let xpcConnection: NSXPCConnection

    public init(deviceId: String, storageId: UInt32? = nil, parentHandle: UInt32? = nil) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.parentHandle = parentHandle

        // Create XPC connection to the host app
        self.xpcConnection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
        self.xpcConnection.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
        self.xpcConnection.resume()

        super.init()
    }

    deinit {
        xpcConnection.invalidate()
    }

    public func invalidate() {
        // Called when the enumerator should stop providing updates
        xpcConnection.invalidate()
    }

    public func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        guard let xpcService = xpcConnection.remoteObjectProxy as? MTPXPCService else {
            observer.finishEnumerating(upTo: nil)
            return
        }

        Task {
            do {
                var items: [NSFileProviderItem] = []

                if storageId == nil {
                    // Enumerating storages for the device
                    let request = StorageListRequest(deviceId: deviceId)
                    xpcService.listStorages(request) { response in
                        if response.success, let storages = response.storages {
                            for storage in storages {
                                let item = MTPFileProviderItem(
                                    deviceId: self.deviceId,
                                    storageId: storage.storageId,
                                    objectHandle: nil,
                                    name: storage.description,
                                    size: nil,
                                    isDirectory: true,
                                    modifiedDate: nil
                                )
                                items.append(item)
                            }
                        }
                        observer.didEnumerate(items)
                        observer.finishEnumerating(upTo: nil)
                    }
                } else {
                    // Enumerating objects within a storage
                    let request = ObjectListRequest(
                        deviceId: deviceId,
                        storageId: storageId!,
                        parentHandle: parentHandle
                    )

                    xpcService.listObjects(request) { response in
                        if response.success, let objects = response.objects {
                            for object in objects {
                                let item = MTPFileProviderItem(
                                    deviceId: self.deviceId,
                                    storageId: self.storageId!,
                                    objectHandle: object.handle,
                                    name: object.name,
                                    size: object.sizeBytes,
                                    isDirectory: object.isDirectory,
                                    modifiedDate: object.modifiedDate
                                )
                                items.append(item)
                            }
                        }
                        observer.didEnumerate(items)
                        observer.finishEnumerating(upTo: nil)
                    }
                }
            } catch {
                observer.finishEnumerating(upTo: nil)
            }
        }
    }

    public func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // For tech preview, we'll treat all enumerations as full refreshes
        // In a full implementation, you'd track changes and provide incremental updates
        enumerateItems(for: observer, startingAt: NSFileProviderPage(""))
    }

    public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Return a simple anchor for change tracking
        // In practice, you'd return a proper sync anchor based on device state
        completionHandler(NSFileProviderSyncAnchor("v1".data(using: .utf8)!))
    }
}
