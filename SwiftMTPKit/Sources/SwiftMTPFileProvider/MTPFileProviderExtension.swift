// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import UniformTypeIdentifiers
@preconcurrency import FileProvider
import SwiftMTPXPC
import SwiftMTPCore
import SwiftMTPIndex

/// Main File Provider extension for MTP devices.
///
/// Cache-first architecture: metadata reads come from the local SQLite index,
/// content materialization goes through XPC to the host app.
public final class MTPFileProviderExtension: NSObject, NSFileProviderReplicatedExtension,
  @unchecked Sendable
{
  private let domain: NSFileProviderDomain
  /// Lazily-established XPC connection; guarded by the extension's own serial dispatch.
  nonisolated(unsafe) private var xpcConnection: NSXPCConnection?
  private let xpcServiceResolver: (() -> MTPXPCService?)?

  /// Read-only index reader opened from the shared app group container.
  private let indexReader: (any LiveIndexReader)?

  public init(domain: NSFileProviderDomain) {
    self.xpcServiceResolver = nil
    self.domain = domain
    // Open the live index in read-only mode from the app group container
    self.indexReader = try? SQLiteLiveIndex.appGroupIndex(readOnly: true)
    super.init()
  }

  init(
    domain: NSFileProviderDomain,
    indexReader: (any LiveIndexReader)?,
    xpcServiceResolver: (() -> MTPXPCService?)? = nil
  ) {
    self.domain = domain
    self.indexReader = indexReader
    self.xpcServiceResolver = xpcServiceResolver
    super.init()
  }

  public func invalidate() {
    xpcConnection?.invalidate()
  }

  private func getXPCService() -> MTPXPCService? {
    if let xpcServiceResolver {
      return xpcServiceResolver()
    }
    if xpcConnection == nil {
      let connection = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
      connection.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
      connection.resume()
      xpcConnection = connection
    }
    return xpcConnection?.remoteObjectProxy as? MTPXPCService
  }

  // MARK: - Item Metadata (cache-first)

  public func item(
    for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    guard let components = MTPFileProviderItem.parseItemIdentifier(identifier) else {
      completionHandler(
        nil,
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
      progress.completedUnitCount = 1
      return progress
    }

    // Try cache-first lookup
    if let reader = indexReader, let objectHandle = components.objectHandle {
      let cb = SendableBox(completionHandler)
      Task {
        let completionHandler = cb.value
        do {
          if let obj = try await reader.object(deviceId: components.deviceId, handle: objectHandle)
          {
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
            completionHandler(
              nil,
              NSError(
                domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
          }
        } catch {
          completionHandler(nil, error)
        }
        progress.completedUnitCount = 1
      }
    } else if let reader = indexReader, let sid = components.storageId,
      components.objectHandle == nil
    {
      // Storage-level item
      let cb = SendableBox(completionHandler)
      Task {
        let completionHandler = cb.value
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
            completionHandler(
              nil,
              NSError(
                domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
          }
        } catch {
          completionHandler(nil, error)
        }
        progress.completedUnitCount = 1
      }
    } else {
      completionHandler(
        nil,
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
      progress.completedUnitCount = 1
    }

    return progress
  }

  // MARK: - Content Materialization (via XPC)

  public func fetchContents(
    for itemIdentifier: NSFileProviderItemIdentifier,
    version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest,
    completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    guard let xpcService = getXPCService(),
      let components = MTPFileProviderItem.parseItemIdentifier(itemIdentifier),
      let objectHandle = components.objectHandle
    else {
      completionHandler(
        nil, nil,
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
      progress.completedUnitCount = 1
      return progress
    }

    let readRequest = ReadRequest(deviceId: components.deviceId, objectHandle: objectHandle)

    // Pre-fetch metadata from cache before XPC call (avoids semaphore deadlock)
    let capturedReader = indexReader
    let capturedDeviceId = components.deviceId
    let capturedStorageId = components.storageId!
    let xpcBox = SendableBox(xpcService)
    let cb = SendableBox(completionHandler)
    Task {
      let completionHandler = cb.value
      let xpcService = xpcBox.value
      let cached: (name: String, parent: UInt32?)? = await {
        guard let reader = capturedReader else { return nil }
        guard let obj = try? await reader.object(deviceId: capturedDeviceId, handle: objectHandle)
        else { return nil }
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
            completionHandler(
              nil, nil,
              NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue))
          }
          progress.completedUnitCount = 1
        }
      }
    }

    return progress
  }

  // MARK: - Enumerator

  public func enumerator(
    for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest
  ) throws -> NSFileProviderEnumerator {
    guard let components = MTPFileProviderItem.parseItemIdentifier(containerItemIdentifier) else {
      throw NSError(
        domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }
    return DomainEnumerator(
      deviceId: components.deviceId,
      storageId: components.storageId,
      parentHandle: components.objectHandle,
      indexReader: indexReader
    )
  }

  // MARK: - Write Operations (via XPC)

  public func createItem(
    basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
    completionHandler:
      @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    guard let xpcService = getXPCService(),
      let components = MTPFileProviderItem.parseItemIdentifier(itemTemplate.itemIdentifier)
    else {
      completionHandler(
        nil, [], false,
        NSError(
          domain: NSFileProviderErrorDomain, code: NSFileProviderError.serverUnreachable.rawValue))
      progress.completedUnitCount = 1
      return progress
    }

    // Folder creation
    if itemTemplate.contentType == .folder || itemTemplate.contentType == .directory {
      guard let storageId = components.storageId else {
        completionHandler(
          nil, [], false,
          NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
        progress.completedUnitCount = 1
        return progress
      }
      let folderParentHandle = MTPFileProviderItem.parseItemIdentifier(
        itemTemplate.parentItemIdentifier)?
        .objectHandle
      let req = CreateFolderRequest(
        deviceId: components.deviceId, storageId: storageId,
        parentHandle: folderParentHandle, name: itemTemplate.filename)
      let xpcBox = SendableBox(xpcService)
      let cb = SendableBox(completionHandler)
      Task {
        let completionHandler = cb.value
        await MainActor.run {
          xpcBox.value.createFolder(req) { response in
            if response.success {
              let item = MTPFileProviderItem(
                deviceId: components.deviceId, storageId: storageId,
                objectHandle: response.newHandle, parentHandle: folderParentHandle,
                name: req.name, size: nil, isDirectory: true, modifiedDate: nil)
              completionHandler(item, [], false, nil)
            } else {
              completionHandler(
                nil, [], false,
                NSError(
                  domain: NSFileProviderErrorDomain,
                  code: NSFileProviderError.serverUnreachable.rawValue))
            }
            progress.completedUnitCount = 1
          }
        }
      }
      return progress
    }

    // File upload
    guard let sourceURL = url, let storageId = components.storageId else {
      completionHandler(
        nil, [], false,
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
      progress.completedUnitCount = 1
      return progress
    }
    let fileSize =
      (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? UInt64) ?? 0
    let bookmark = try? sourceURL.bookmarkData(options: .withSecurityScope)
    // The parent is the container the new file is being created in
    let parentHandle = MTPFileProviderItem.parseItemIdentifier(itemTemplate.parentItemIdentifier)?
      .objectHandle
    let req = WriteRequest(
      deviceId: components.deviceId, storageId: storageId,
      parentHandle: parentHandle, name: itemTemplate.filename,
      size: fileSize, bookmark: bookmark)
    let xpcBox = SendableBox(xpcService)
    let cb = SendableBox(completionHandler)
    Task {
      let completionHandler = cb.value
      await MainActor.run {
        xpcBox.value.writeObject(req) { response in
          if response.success {
            let item = MTPFileProviderItem(
              deviceId: components.deviceId, storageId: storageId,
              objectHandle: response.newHandle, parentHandle: parentHandle,
              name: req.name, size: fileSize, isDirectory: false, modifiedDate: nil)
            completionHandler(item, [], false, nil)
          } else {
            completionHandler(
              nil, [], false,
              NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue))
          }
          progress.completedUnitCount = 1
        }
      }
    }
    return progress
  }

  public func modifyItem(
    _ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
    changedFields: NSFileProviderItemFields, contents newContents: URL?,
    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
    completionHandler:
      @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    // Metadata-only change (rename etc.) — acknowledge with no server mutation for now
    guard changedFields.contains(.contents), let sourceURL = newContents,
      let xpcService = getXPCService(),
      let components = MTPFileProviderItem.parseItemIdentifier(item.itemIdentifier),
      let storageId = components.storageId
    else {
      completionHandler(item, [], false, nil)
      progress.completedUnitCount = 1
      return progress
    }

    // MTP has no in-place modify: delete old handle then upload new content
    let fileSize =
      (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? UInt64) ?? 0
    let bookmark = try? sourceURL.bookmarkData(options: .withSecurityScope)
    let deleteReq = DeleteRequest(
      deviceId: components.deviceId, objectHandle: components.objectHandle ?? 0)
    let writeReq = WriteRequest(
      deviceId: components.deviceId, storageId: storageId,
      parentHandle: MTPFileProviderItem.parseItemIdentifier(item.parentItemIdentifier)?
        .objectHandle,
      name: item.filename, size: fileSize, bookmark: bookmark)
    let xpcBox = SendableBox(xpcService)
    let cb = SendableBox(completionHandler)
    let parentHandle = MTPFileProviderItem.parseItemIdentifier(item.parentItemIdentifier)?
      .objectHandle
    Task {
      let completionHandler = cb.value
      await MainActor.run {
        xpcBox.value.deleteObject(deleteReq) { deleteResponse in
          guard deleteResponse.success else {
            completionHandler(
              nil, [], false,
              NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue))
            progress.completedUnitCount = 1
            return
          }
          xpcBox.value.writeObject(writeReq) { response in
            if response.success {
              let newItem = MTPFileProviderItem(
                deviceId: components.deviceId, storageId: storageId,
                objectHandle: response.newHandle, parentHandle: parentHandle,
                name: writeReq.name, size: fileSize, isDirectory: false, modifiedDate: nil)
              completionHandler(newItem, [], false, nil)
            } else {
              completionHandler(
                nil, [], false,
                NSError(
                  domain: NSFileProviderErrorDomain,
                  code: NSFileProviderError.serverUnreachable.rawValue))
            }
            progress.completedUnitCount = 1
          }
        }
      }
    }
    return progress
  }

  public func deleteItem(
    identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
    completionHandler: @escaping (Error?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    guard let xpcService = getXPCService(),
      let components = MTPFileProviderItem.parseItemIdentifier(identifier),
      let objectHandle = components.objectHandle
    else {
      completionHandler(
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue))
      progress.completedUnitCount = 1
      return progress
    }

    let req = DeleteRequest(
      deviceId: components.deviceId, objectHandle: objectHandle, recursive: true)
    let xpcBox = SendableBox(xpcService)
    let cb = SendableBox(completionHandler)
    Task {
      let completionHandler = cb.value
      await MainActor.run {
        xpcBox.value.deleteObject(req) { response in
          completionHandler(
            response.success
              ? nil
              : NSError(
                domain: NSFileProviderErrorDomain,
                code: NSFileProviderError.serverUnreachable.rawValue))
          progress.completedUnitCount = 1
        }
      }
    }
    return progress
  }
}
