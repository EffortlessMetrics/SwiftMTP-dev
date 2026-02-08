// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPXPC
import SwiftMTPCore
import SwiftMTPIndex

/// Main File Provider extension for MTP devices.
///
/// Cache-first architecture: metadata reads come from the local SQLite index,
/// content materialization goes through XPC to the host app.
public final class MTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private var xpcConnection: NSXPCConnection?

    /// Read-only index reader opened from the shared app group container.
    private var indexReader: (any LiveIndexReader)?

    public init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()

        // Open the live index in read-only mode from the app group container
        do {
            let index = try SQLiteLiveIndex.appGroupIndex(readOnly: true)
            self.indexReader = index
        } catch {
            // Index not available yet — will fall back to XPC
            self.indexReader = nil
        }
    }

    public func invalidate() {
        xpcConnection?.invalidate()
    }

    private func getXPCService() -> MTPXPCService? {
        if xpcConnection == nil {
            let connection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
            connection.resume()
            xpcConnection = connection
        }
        return xpcConnection?.remoteObjectProxy as? MTPXPCService
    }

    // MARK: - Item Metadata (cache-first)

    public func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let components = MTPFileProviderItem.parseItemIdentifier(identifier) else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            progress.completedUnitCount = 1
            return progress
        }

        // Try cache-first lookup
        if let reader = indexReader, let objectHandle = components.objectHandle {
            Task {
                do {
                    if let obj = try await reader.object(deviceId: components.deviceId, handle: objectHandle) {
                        let item = MTPFileProviderItem(
                            deviceId: obj.deviceId,
                            storageId: obj.storageId,
                            objectHandle: obj.handle,
                            parentHandle: obj.parentHandle,
                            name: obj.name,
                            size: obj.sizeBytes,
                            isDirectory: obj.isDirectory,
                            modifiedDate: obj.mtime
                        )
                        completionHandler(item, nil)
                    } else {
                        completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
                    }
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
        } else if let reader = indexReader, let sid = components.storageId, components.objectHandle == nil {
            // Storage-level item
            Task {
                do {
                    let storages = try await reader.storages(deviceId: components.deviceId)
                    if let storage = storages.first(where: { $0.storageId == sid }) {
                        let item = MTPFileProviderItem(
                            deviceId: components.deviceId,
                            storageId: storage.storageId,
                            objectHandle: nil,
                            name: storage.description,
                            size: nil,
                            isDirectory: true,
                            modifiedDate: nil
                        )
                        completionHandler(item, nil)
                    } else {
                        completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
                    }
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
        } else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            progress.completedUnitCount = 1
        }

        return progress
    }

    // MARK: - Content Materialization (via XPC)

    public func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let xpcService = getXPCService(),
              let components = MTPFileProviderItem.parseItemIdentifier(itemIdentifier),
              let objectHandle = components.objectHandle else {
            completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            progress.completedUnitCount = 1
            return progress
        }

        let readRequest = ReadRequest(deviceId: components.deviceId, objectHandle: objectHandle)

        // Pre-fetch metadata from cache before XPC call (avoids semaphore deadlock)
        let capturedReader = indexReader
        let capturedDeviceId = components.deviceId
        let capturedStorageId = components.storageId!
        Task {
            let cached: (name: String, parent: UInt32?)? = await {
                guard let reader = capturedReader else { return nil }
                guard let obj = try? await reader.object(deviceId: capturedDeviceId, handle: objectHandle) else { return nil }
                return (name: obj.name, parent: obj.parentHandle)
            }()

            await MainActor.run {
                xpcService.readObject(readRequest) { response in
                    if response.success, let tempFileURL = response.tempFileURL {
                        let itemName = cached?.name ?? tempFileURL.lastPathComponent
                        let item = MTPFileProviderItem(
                            deviceId: capturedDeviceId,
                            storageId: capturedStorageId,
                            objectHandle: objectHandle,
                            parentHandle: cached?.parent,
                            name: itemName,
                            size: response.fileSize,
                            isDirectory: false,
                            modifiedDate: nil
                        )
                        completionHandler(tempFileURL, item, nil)
                    } else {
                        completionHandler(nil, nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.serverUnreachable.rawValue))
                    }
                    progress.completedUnitCount = 1
                }
            }
        }

        return progress
    }

    // MARK: - Enumerator

    public func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let components = MTPFileProviderItem.parseItemIdentifier(containerItemIdentifier) else {
            throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
        }
        return DomainEnumerator(
            deviceId: components.deviceId,
            storageId: components.storageId,
            parentHandle: components.objectHandle,
            indexReader: indexReader
        )
    }

    // MARK: - Required Stubs for Replicated Extension

    public func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(nil, [], false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.notAuthenticated.rawValue))
        progress.completedUnitCount = 1
        return progress
    }

    public func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(nil, [], false, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.notAuthenticated.rawValue))
        progress.completedUnitCount = 1
        return progress
    }

    public func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        completionHandler(NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.notAuthenticated.rawValue))
        progress.completedUnitCount = 1
        return progress
    }
}
