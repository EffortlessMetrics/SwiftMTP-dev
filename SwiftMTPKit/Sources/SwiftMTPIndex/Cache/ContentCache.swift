// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

// MARK: - Cache Result

/// Result of a content cache lookup.
public enum CacheResult: Sendable {
  /// File is fully cached at the given URL.
  case hit(URL)
  /// File is partially cached (resumable).
  case partial(URL, committed: Int64)
  /// File is currently being downloaded.
  case downloading
  /// File is not in the cache.
  case miss
}

// MARK: - ContentCache

/// Manages a local content cache for MTP file data.
///
/// The cache stores downloaded file content on disk and tracks state in the same
/// SQLite database as the live index. This allows the File Provider extension to
/// serve cached content without going through XPC for cache hits.
public actor ContentCache {
  private let db: SQLiteDB
  private let cacheRoot: URL
  private let maxSizeBytes: Int64

  /// Active downloads keyed by "deviceId:storageId:handle".
  private var activeDownloads: Set<String> = []

  /// Create a content cache.
  /// - Parameters:
  ///   - db: The SQLiteDB instance (shared with SQLiteLiveIndex).
  ///   - cacheRoot: Root directory for cached files.
  ///   - maxSizeBytes: Maximum cache size in bytes (default 2GB).
  public init(db: SQLiteDB, cacheRoot: URL, maxSizeBytes: Int64 = 2 * 1024 * 1024 * 1024) {
    self.db = db
    self.cacheRoot = cacheRoot
    self.maxSizeBytes = maxSizeBytes
  }

  /// Create a content cache using the standard cache directory.
  public static func standard(db: SQLiteDB) -> ContentCache {
    let cacheDir =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let root = cacheDir.appendingPathComponent("SwiftMTP/content")
    return ContentCache(db: db, cacheRoot: root)
  }

  /// Look up a file in the cache.
  public func lookup(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) -> CacheResult {
    let key = cacheKey(deviceId: deviceId, storageId: storageId, handle: handle)
    if activeDownloads.contains(key) { return .downloading }

    do {
      let sql =
        "SELECT localPath, state, committedBytes FROM cached_content WHERE deviceId = ? AND storageId = ? AND handle = ?"
      return try db.withStatement(sql) { stmt in
        try db.bind(stmt, 1, deviceId)
        try db.bind(stmt, 2, Int64(storageId))
        try db.bind(stmt, 3, Int64(handle))

        guard try db.step(stmt) else { return .miss }

        let localPath = db.colText(stmt, 0) ?? ""
        let state = db.colText(stmt, 1) ?? "complete"
        let committed = db.colInt64(stmt, 2) ?? 0

        let url = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: localPath) else { return .miss }

        switch state {
        case "complete": return .hit(url)
        case "partial": return .partial(url, committed: committed)
        default: return .miss
        }
      }
    } catch {
      return .miss
    }
  }

  /// Materialize file content, downloading if not cached.
  /// - Parameters:
  ///   - deviceId: Device identifier.
  ///   - storageId: Storage identifier.
  ///   - handle: Object handle.
  ///   - device: The MTP device to download from (if cache miss).
  /// - Returns: Local file URL.
  public func materialize(
    deviceId: String, storageId: UInt32, handle: MTPObjectHandle,
    device: any MTPDevice
  ) async throws -> URL {
    // Check cache first
    switch lookup(deviceId: deviceId, storageId: storageId, handle: handle) {
    case .hit(let url):
      try touchAccessTime(deviceId: deviceId, storageId: storageId, handle: handle)
      return url
    case .partial, .downloading, .miss:
      break
    }

    let key = cacheKey(deviceId: deviceId, storageId: storageId, handle: handle)
    activeDownloads.insert(key)
    defer { activeDownloads.remove(key) }

    // Prepare local path
    let dir =
      cacheRoot
      .appendingPathComponent(deviceId)
      .appendingPathComponent("\(storageId)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let localURL = dir.appendingPathComponent("\(handle).dat")

    // Download
    _ = try await device.read(handle: handle, range: nil, to: localURL)

    // Get file size
    let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
    let fileSize = (attrs[.size] as? Int64) ?? 0

    // Record in database
    let now = Int64(Date().timeIntervalSince1970)
    let sql = """
      INSERT INTO cached_content (deviceId, storageId, handle, localPath, sizeBytes, state, committedBytes, lastAccessedAt)
      VALUES (?, ?, ?, ?, ?, 'complete', ?, ?)
      ON CONFLICT(deviceId, storageId, handle) DO UPDATE SET
          localPath = excluded.localPath,
          sizeBytes = excluded.sizeBytes,
          state = 'complete',
          committedBytes = excluded.committedBytes,
          lastAccessedAt = excluded.lastAccessedAt
      """
    try db.withStatement(sql) { stmt in
      try db.bind(stmt, 1, deviceId)
      try db.bind(stmt, 2, Int64(storageId))
      try db.bind(stmt, 3, Int64(handle))
      try db.bind(stmt, 4, localURL.path)
      try db.bind(stmt, 5, fileSize)
      try db.bind(stmt, 6, fileSize)
      try db.bind(stmt, 7, now)
      _ = try db.step(stmt)
    }

    // Evict if over budget
    try evictIfNeeded()

    return localURL
  }

  /// Evict least-recently-used entries until cache is within budget.
  public func evictIfNeeded() throws {
    let totalSQL = "SELECT COALESCE(SUM(sizeBytes), 0) FROM cached_content WHERE state = 'complete'"
    let totalSize: Int64 = try db.withStatement(totalSQL) { stmt in
      guard try db.step(stmt) else { return 0 }
      return db.colInt64(stmt, 0) ?? 0
    }

    guard totalSize > maxSizeBytes else { return }
    var toFree = totalSize - maxSizeBytes

    let lruSQL =
      "SELECT deviceId, storageId, handle, localPath, sizeBytes FROM cached_content WHERE state = 'complete' ORDER BY lastAccessedAt ASC"
    try db.withStatement(lruSQL) { stmt in
      while toFree > 0, try db.step(stmt) {
        let devId = db.colText(stmt, 0) ?? ""
        let sid = db.colInt64(stmt, 1) ?? 0
        let h = db.colInt64(stmt, 2) ?? 0
        let path = db.colText(stmt, 3) ?? ""
        let size = db.colInt64(stmt, 4) ?? 0

        // Delete file
        try? FileManager.default.removeItem(atPath: path)

        // Delete DB record
        let delSQL =
          "DELETE FROM cached_content WHERE deviceId = ? AND storageId = ? AND handle = ?"
        try db.withStatement(delSQL) { delStmt in
          try db.bind(delStmt, 1, devId)
          try db.bind(delStmt, 2, sid)
          try db.bind(delStmt, 3, h)
          _ = try db.step(delStmt)
        }

        toFree -= size
      }
    }
  }

  // MARK: - Helpers

  private func cacheKey(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) -> String {
    "\(deviceId):\(storageId):\(handle)"
  }

  private func touchAccessTime(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) throws
  {
    let now = Int64(Date().timeIntervalSince1970)
    let sql =
      "UPDATE cached_content SET lastAccessedAt = ? WHERE deviceId = ? AND storageId = ? AND handle = ?"
    try db.withStatement(sql) { stmt in
      try db.bind(stmt, 1, now)
      try db.bind(stmt, 2, deviceId)
      try db.bind(stmt, 3, Int64(storageId))
      try db.bind(stmt, 4, Int64(handle))
      _ = try db.step(stmt)
    }
  }
}
