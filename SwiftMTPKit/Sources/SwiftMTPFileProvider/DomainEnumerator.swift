// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@preconcurrency import FileProvider
import SwiftMTPCore
import SwiftMTPXPC
import OSLog

/// Cache-first File Provider domain enumerator.
///
/// Reads directly from the local SQLite live index (no XPC for metadata).
/// If the index is empty for a folder, fires a background crawl request via XPC.
public final class DomainEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
  /// Maximum items yielded per enumeration page.
  private static let pageSize: Int = 500

  /// Timeout for index read operations during enumeration.
  static let enumerationTimeoutSeconds: UInt64 = 15

  private let deviceId: String
  private let storageId: UInt32?
  private let parentHandle: UInt32?
  private let indexReader: (any LiveIndexReader)?
  private let syncAnchorStore: SyncAnchorStore?
  /// Lazily-established XPC connection; created once and reused.
  nonisolated(unsafe) private var xpcConnection: NSXPCConnection?

  private let log = Logger(subsystem: "SwiftMTP", category: "DomainEnumerator")

  public init(
    deviceId: String, storageId: UInt32? = nil, parentHandle: UInt32? = nil,
    indexReader: (any LiveIndexReader)?,
    syncAnchorStore: SyncAnchorStore? = nil
  ) {
    self.deviceId = deviceId
    self.storageId = storageId
    self.parentHandle = parentHandle
    self.indexReader = indexReader
    self.syncAnchorStore = syncAnchorStore
    super.init()
  }

  deinit {
    xpcConnection?.invalidate()
  }

  public func invalidate() {
    xpcConnection?.invalidate()
    xpcConnection = nil
  }

  // MARK: - Enumeration

  public func enumerateItems(
    for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage
  ) {
    let obs = SendableBox(observer)
    Task {
      let observer = obs.value
      do {
        guard let reader = indexReader else {
          observer.finishEnumerating(upTo: nil)
          return
        }

        var allItems: [NSFileProviderItem] = []

        if storageId == nil {
          // Enumerate storages (with timeout guard)
          let storages = try await withEnumerationTimeout {
            try await reader.storages(deviceId: self.deviceId)
          }
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
            allItems.append(item)
          }

          if storages.isEmpty {
            triggerCrawl(storageId: 0, parentHandle: nil)
          }
        } else {
          // Enumerate objects in a directory (with timeout guard)
          let sid = storageId!
          let ph = parentHandle
          let objects = try await withEnumerationTimeout {
            try await reader.children(
              deviceId: self.deviceId,
              storageId: sid,
              parentHandle: ph
            )
          }
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
            allItems.append(item)
          }

          if objects.isEmpty {
            // Cache is empty for this folder — trigger background crawl
            triggerCrawl(storageId: sid, parentHandle: ph)
          }
        }

        // Page the results: decode the current offset from the page cursor,
        // yield one page of items, and supply a next-page cursor when more remain.
        let offset = decodePageOffset(page)
        let end = min(offset + Self.pageSize, allItems.count)
        observer.didEnumerate(Array(allItems[offset..<end]))
        if end < allItems.count {
          observer.finishEnumerating(upTo: encodePageCursor(UInt64(end)))
        } else {
          observer.finishEnumerating(upTo: nil)
        }
      } catch {
        log.error("Enumeration failed for device=\(self.deviceId): \(error.localizedDescription)")
        observer.finishEnumeratingWithError(Self.mapToFileProviderError(error))
      }
    }
  }

  // MARK: - Page Cursor Encoding

  /// Encodes a byte offset as an `NSFileProviderPage` cursor.
  private func encodePageCursor(_ offset: UInt64) -> NSFileProviderPage {
    var value = offset
    let data = Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    return NSFileProviderPage(data)
  }

  /// Decodes a page cursor back to an item offset.
  /// Returns 0 for the initial (system-supplied) page, which is not 8 bytes.
  private func decodePageOffset(_ page: NSFileProviderPage) -> Int {
    let data = page.rawValue
    guard data.count == MemoryLayout<UInt64>.size else { return 0 }
    var value: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
    return Int(value)
  }

  // MARK: - Change Tracking

  public func enumerateChanges(
    for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor
  ) {
    let obs = SendableBox(observer)
    Task {
      let observer = obs.value

      // --- SyncAnchorStore path (push-based MTP events) ---
      if let store = syncAnchorStore {
        let key = "\(deviceId):\(storageId ?? 0)"
        let result = store.consumeChanges(from: anchor.rawValue, for: key)

        var updatedItems: [NSFileProviderItem] = []
        for identifier in result.added {
          if let components = MTPFileProviderItem.parseItemIdentifier(identifier),
            let handle = components.objectHandle,
            let sid = components.storageId,
            let reader = indexReader,
            let obj = try? await reader.object(deviceId: components.deviceId, handle: handle)
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
            updatedItems.append(item)
            _ = sid  // suppress unused warning
          }
        }

        observer.didUpdate(updatedItems)
        observer.didDeleteItems(withIdentifiers: result.deleted)

        let newAnchor = NSFileProviderSyncAnchor(store.currentAnchor(for: key))
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: result.hasMore)
        return
      }

      // --- LiveIndexReader path (SQLite change counter) ---
      do {
        guard let reader = indexReader else {
          observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
          return
        }

        let anchorValue = decodeSyncAnchor(anchor)
        let did = self.deviceId
        let changes = try await withEnumerationTimeout {
          try await reader.changesSince(deviceId: did, anchor: anchorValue)
        }

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

        let currentCounter = try await withEnumerationTimeout {
          try await reader.currentChangeCounter(deviceId: did)
        }
        let newAnchor = encodeSyncAnchor(currentCounter)
        observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
      } catch {
        log.error("Change enumeration failed for device=\(self.deviceId): \(error.localizedDescription)")
        observer.finishEnumeratingWithError(Self.mapToFileProviderError(error))
      }
    }
  }

  public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
    // SyncAnchorStore path
    if let store = syncAnchorStore {
      let key = "\(deviceId):\(storageId ?? 0)"
      completionHandler(NSFileProviderSyncAnchor(store.currentAnchor(for: key)))
      return
    }

    // LiveIndexReader path
    let cb = SendableBox(completionHandler)
    Task {
      let completionHandler = cb.value
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
    var value: Int64 = 0
    _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
    return value
  }

  // MARK: - Crawl Trigger

  /// Crawl debounce interval: skip crawl if folder was crawled within this window.
  private static let crawlDebounceSeconds: TimeInterval = 30

  /// Fire-and-forget XPC call to trigger a priority crawl for this folder.
  private func triggerCrawl(storageId: UInt32, parentHandle: UInt32?) {
    // Debounce: skip if folder was crawled recently
    if let reader = indexReader {
      Task {
        if let lastCrawled = try? await reader.crawlState(
          deviceId: deviceId, storageId: storageId,
          parentHandle: parentHandle
        ), Date().timeIntervalSince(lastCrawled) < Self.crawlDebounceSeconds {
          return
        }
        self.fireCrawlRequest(storageId: storageId, parentHandle: parentHandle)
      }
    } else {
      fireCrawlRequest(storageId: storageId, parentHandle: parentHandle)
    }
  }

  private func fireCrawlRequest(storageId: UInt32, parentHandle: UInt32?) {
    let connection = getXPCConnection()
    guard let xpcService = connection.remoteObjectProxy as? MTPXPCService else { return }
    let request = CrawlTriggerRequest(
      deviceId: deviceId, storageId: storageId, parentHandle: parentHandle)
    Task { @MainActor in
      xpcService.requestCrawl(request) { _ in /* fire and forget */ }
    }
  }

  private func getXPCConnection() -> NSXPCConnection {
    if let conn = xpcConnection { return conn }
    let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
    conn.remoteObjectInterface = NSXPCInterface(with: MTPXPCService.self)
    conn.interruptionHandler = { [weak self] in
      self?.log.warning("XPC connection interrupted — will reconnect on next use")
    }
    conn.invalidationHandler = { [weak self] in
      self?.log.warning("XPC connection invalidated — will recreate on next use")
      self?.xpcConnection = nil
    }
    conn.resume()
    xpcConnection = conn
    return conn
  }

  // MARK: - Timeout & Error Helpers

  /// Wraps an async index read with a timeout to prevent hangs during device disconnection.
  private func withEnumerationTimeout<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: Self.enumerationTimeoutSeconds * 1_000_000_000)
        throw EnumerationError.timeout
      }
      guard let result = try await group.next() else {
        throw EnumerationError.timeout
      }
      group.cancelAll()
      return result
    }
  }

  /// Maps internal/transport errors to appropriate NSFileProviderError codes.
  static func mapToFileProviderError(_ error: Error) -> NSError {
    let nsError = error as NSError

    // Already an NSFileProviderError — pass through
    if nsError.domain == NSFileProviderErrorDomain {
      return nsError
    }

    // Timeout during enumeration
    if error is EnumerationError {
      return NSError(
        domain: NSFileProviderErrorDomain,
        code: NSFileProviderError.serverUnreachable.rawValue,
        userInfo: [NSUnderlyingErrorKey: error])
    }

    // Cancellation (e.g. user navigated away)
    if error is CancellationError {
      return NSError(
        domain: NSFileProviderErrorDomain,
        code: NSFileProviderError.serverUnreachable.rawValue,
        userInfo: [NSUnderlyingErrorKey: error])
    }

    // Check error description for disconnect-related keywords
    let msg = error.localizedDescription.lowercased()
    let isDisconnect =
      msg.contains("not connected") || msg.contains("disconnected")
      || msg.contains("unavailable") || msg.contains("timeout")
      || msg.contains("no device") || msg.contains("interrupted")
    if isDisconnect {
      return NSError(
        domain: NSFileProviderErrorDomain,
        code: NSFileProviderError.serverUnreachable.rawValue,
        userInfo: [NSUnderlyingErrorKey: error])
    }

    // Default: treat as a transient server error
    return NSError(
      domain: NSFileProviderErrorDomain,
      code: NSFileProviderError.serverUnreachable.rawValue,
      userInfo: [NSUnderlyingErrorKey: error])
  }
}

/// Errors raised by the enumeration timeout guard.
enum EnumerationError: Error, CustomStringConvertible {
  case timeout

  var description: String {
    switch self {
    case .timeout: return "Enumeration timed out — device may be disconnected"
    }
  }
}
