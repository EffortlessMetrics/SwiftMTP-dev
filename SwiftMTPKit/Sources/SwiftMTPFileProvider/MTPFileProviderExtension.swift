// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import SwiftMTPXPC
import SwiftMTPCore

/// Main File Provider extension for MTP devices
/// This handles domain management and content hydration
public final class MTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private var xpcConnection: NSXPCConnection?

    public init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
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

    // MARK: - Domain Management

    public func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard let xpcService = getXPCService(),
              let components = MTPFileProviderItem.parseItemIdentifier(identifier) else {
            completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
            progress.completedUnitCount = 1
            return progress
        }

        // Fetch item metadata via XPC (Simplified for refactor)
        Task { @MainActor in
            xpcService.ping { _ in
                // Placeholder logic: would call listObjects or getObjectInfo
                completionHandler(nil, NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
                progress.completedUnitCount = 1
            }
        }

        return progress
    }

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

        Task { @MainActor in
            xpcService.readObject(readRequest) { response in
                if response.success, let tempFileURL = response.tempFileURL {
                    let item = MTPFileProviderItem(
                        deviceId: components.deviceId,
                        storageId: components.storageId!,
                        objectHandle: objectHandle,
                        name: tempFileURL.lastPathComponent,
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

        return progress
    }

    public func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let components = MTPFileProviderItem.parseItemIdentifier(containerItemIdentifier) else {
            throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
        }
        return DomainEnumerator(deviceId: components.deviceId, storageId: components.storageId, parentHandle: components.objectHandle)
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
