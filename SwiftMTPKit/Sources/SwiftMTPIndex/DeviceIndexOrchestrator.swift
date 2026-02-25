// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Per-device lifecycle coordinator for the live index, crawler, and content cache.
///
/// Created on device attach, stopped on detach. Owns the full indexing pipeline
/// for a single device.
public actor DeviceIndexOrchestrator {
  private let deviceId: String
  private let liveIndex: SQLiteLiveIndex
  private let crawler: CrawlScheduler
  private let eventBridge: EventBridge
  private let cache: ContentCache

  /// Read-only access to the index (for File Provider extension).
  public var indexReader: any LiveIndexReader { liveIndex }

  /// Create an orchestrator for a device.
  /// - Parameters:
  ///   - deviceId: The device identifier string.
  ///   - liveIndex: The shared live index instance.
  ///   - contentCache: The content cache instance.
  public init(deviceId: String, liveIndex: SQLiteLiveIndex, contentCache: ContentCache) {
    self.deviceId = deviceId
    self.liveIndex = liveIndex
    self.crawler = CrawlScheduler(indexWriter: liveIndex)
    self.eventBridge = EventBridge(scheduler: crawler, deviceId: deviceId)
    self.cache = contentCache
  }

  /// Start the indexing pipeline for this device.
  /// - Parameter device: The connected MTP device.
  public func start(device: any MTPDevice) async {
    // Seed initial crawl with storage discovery
    await crawler.seedOnConnect(deviceId: deviceId, device: device)

    // Start the event bridge (listens for device events or falls back to periodic refresh)
    await eventBridge.start(device: device)

    // Start the crawler loop
    await crawler.startCrawling(device: device)
  }

  /// Stop the indexing pipeline (on device detach).
  public func stop() async {
    await crawler.stop()
    await eventBridge.stop()
  }

  /// Boost a subtree to immediate priority (user opened a folder).
  public func boostSubtree(storageId: UInt32, parentHandle: MTPObjectHandle?) async {
    await crawler.boostSubtree(deviceId: deviceId, storageId: storageId, parentHandle: parentHandle)
  }

  /// Materialize file content (download if not cached).
  public func materializeContent(
    storageId: UInt32,
    handle: MTPObjectHandle,
    device: any MTPDevice
  ) async throws -> URL {
    try await cache.materialize(
      deviceId: deviceId,
      storageId: storageId,
      handle: handle,
      device: device
    )
  }

  /// Set up change notification callback.
  public func setOnChange(_ callback: @Sendable @escaping (String, Set<MTPObjectHandle?>) -> Void)
    async
  {
    await crawler.setOnChange(callback)
  }

  // Expose for CrawlScheduler's onChange
  private func setOnChange(_ callback: @Sendable @escaping (String, Set<MTPObjectHandle?>) -> Void)
  {
    // Forward to crawler
    Task { await crawler.setOnChange(callback) }
  }
}

// Add setter to CrawlScheduler
extension CrawlScheduler {
  /// Set the onChange callback.
  public func setOnChange(_ callback: @Sendable @escaping (String, Set<MTPObjectHandle?>) -> Void) {
    self.onChange = callback
  }
}
