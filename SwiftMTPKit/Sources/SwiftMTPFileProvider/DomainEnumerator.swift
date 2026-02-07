// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPXPC

/// File Provider domain enumerator for browsing MTP device contents
public final class DomainEnumerator: NSObject, NSFileProviderEnumerator {
    private let deviceId: String
    private let storageId: UInt32?
    private let parentHandle: UInt32?
    private let xpcConnection: NSXPCConnection

    public init(deviceId: String, storageId: UInt32? = nil, parentHandle: UInt32? = nil) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.parentHandle = parentHandle

        self.xpcConnection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
        self.xpcConnection.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
        self.xpcConnection.resume()

        super.init()
    }

    deinit {
        xpcConnection.invalidate()
    }

    public func invalidate() {
        xpcConnection.invalidate()
    }

    public func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task { @MainActor in
            guard let xpcService = self.xpcConnection.remoteObjectProxy as? MTPXPCService else {
                observer.finishEnumerating(upTo: nil)
                return
            }

            if self.storageId == nil {
                let request = StorageListRequest(deviceId: self.deviceId)
                xpcService.listStorages(request) { response in
                    var items: [NSFileProviderItem] = []
                    if response.success, let storages = response.storages {
                        for storage in storages {
                            let item = MTPFileProviderItem(
                                deviceId: self.deviceId,
                                storageId: storage.storageId,
                                objectHandle: nil,
                                name: storage.storageDescription,
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
                let request = ObjectListRequest(
                    deviceId: self.deviceId,
                    storageId: self.storageId!,
                    parentHandle: self.parentHandle
                )

                xpcService.listObjects(request) { response in
                    var items: [NSFileProviderItem] = []
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
        }
    }

    public func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // Not implemented for tech preview
    }

    public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(nil)
    }
}
