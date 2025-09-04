// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

public final class DefaultTransferJournal: TransferJournal {
  private let db: Connection
  private let transfers = Table("transfers")

  // Column definitions
  private let id = Expression<String>("id")
  private let deviceId = Expression<String>("deviceId")
  private let kind = Expression<String>("kind")
  private let handle = Expression<Int64?>("handle")
  private let parentHandle = Expression<Int64?>("parentHandle")
  private let pathKey = Expression<String?>("pathKey")
  private let name = Expression<String>("name")
  private let totalBytes = Expression<Int64?>("totalBytes")
  private let committedBytes = Expression<Int64>("committedBytes")
  private let supportsPartial = Expression<Int64>("supportsPartial")
  private let etag_size = Expression<Int64?>("etag_size")
  private let etag_mtime = Expression<Int64?>("etag_mtime")
  private let localTempURL = Expression<String>("localTempURL")
  private let finalURL = Expression<String?>("finalURL")
  private let state = Expression<String>("state")
  private let lastError = Expression<String?>("lastError")
  private let updatedAt = Expression<Int64>("updatedAt")

  public init(dbPath: String) throws {
    self.db = try Connection(dbPath)
    try setupDatabase()
  }

  private func setupDatabase() throws {
    // Embedded schema for transfer journal database
    let schema = """
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA cache_size = 1000;
    PRAGMA temp_store = memory;

    CREATE TABLE IF NOT EXISTS transfers(
      id TEXT PRIMARY KEY,           -- UUID
      deviceId TEXT NOT NULL,
      kind TEXT NOT NULL,            -- "read" | "write"
      handle INTEGER,                -- target object handle (read OR new handle from SendObjectInfo for write)
      parentHandle INTEGER,          -- for writes
      pathKey TEXT,                  -- best-effort identity across sessions
      name TEXT NOT NULL,
      totalBytes INTEGER,            -- expected size (if known)
      committedBytes INTEGER NOT NULL DEFAULT 0,
      supportsPartial INTEGER NOT NULL DEFAULT 0,
      etag_size INTEGER,             -- preconditions: size from ObjectInfo
      etag_mtime INTEGER,            -- preconditions: Date().timeIntervalSince1970 (secs)
      localTempURL TEXT NOT NULL,    -- temp path (host)
      finalURL TEXT,                 -- destination (read) or source (write)
      state TEXT NOT NULL,           -- "active" | "paused" | "failed" | "done"
      lastError TEXT,
      updatedAt INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_transfers_active ON transfers(state);
    CREATE INDEX IF NOT EXISTS idx_transfers_device ON transfers(deviceId);

    -- M6: Index, Diff, Mirror schema

    CREATE TABLE IF NOT EXISTS devices(
      id TEXT PRIMARY KEY,
      model TEXT,
      lastSeenAt INTEGER
    );

    CREATE TABLE IF NOT EXISTS storages(
      id INTEGER,
      deviceId TEXT,
      description TEXT,
      capacity INTEGER,
      free INTEGER,
      readOnly INTEGER,
      lastIndexedAt INTEGER,
      PRIMARY KEY(id, deviceId),
      FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
    );

    -- Current object catalog (single table, "generation" partitioning)
    CREATE TABLE IF NOT EXISTS objects(
      deviceId TEXT NOT NULL,
      storageId INTEGER NOT NULL,
      handle INTEGER NOT NULL,
      parentHandle INTEGER,
      name TEXT NOT NULL,
      pathKey TEXT NOT NULL,           -- normalized NFC, storage-rooted: "<sid>/<a>/<b>/<name>"
      size INTEGER,                    -- NULL if unknown
      mtime INTEGER,                   -- UNIX seconds; NULL if unknown
      format INTEGER NOT NULL,
      gen INTEGER NOT NULL,            -- snapshot generation
      tombstone INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(deviceId, storageId, handle),
      FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_objects_path ON objects(deviceId, pathKey);
    CREATE INDEX IF NOT EXISTS idx_objects_gen  ON objects(deviceId, gen);

    -- Snapshot bookkeeping
    CREATE TABLE IF NOT EXISTS snapshots(
      deviceId TEXT NOT NULL,
      gen INTEGER NOT NULL,
      createdAt INTEGER NOT NULL,
      PRIMARY KEY(deviceId, gen),
      FOREIGN KEY(deviceId) REFERENCES devices(id) ON DELETE CASCADE
    );
    """
    try db.execute(schema)
  }

  public func beginRead(device: MTPDeviceID, handle: UInt32, name: String,
                       size: UInt64?, supportsPartial: Bool,
                       tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String {
    let transferId = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970)

    try db.run(transfers.insert(
      id <- transferId,
      deviceId <- device.raw,
      kind <- "read",
      self.handle <- Int64(handle),
      parentHandle <- nil,
      pathKey <- nil,
      self.name <- name,
      totalBytes <- size.map(Int64.init),
      committedBytes <- 0,
      self.supportsPartial <- supportsPartial ? 1 : 0,
      etag_size <- etag.size.map(Int64.init),
      etag_mtime <- etag.mtime.map { Int64($0.timeIntervalSince1970) },
      localTempURL <- tempURL.path,
      self.finalURL <- finalURL?.path,
      state <- "active",
      lastError <- nil,
      updatedAt <- now
    ))

    return transferId
  }

  public func beginWrite(device: MTPDeviceID, parent: UInt32, name: String,
                        size: UInt64, supportsPartial: Bool,
                        tempURL: URL, sourceURL: URL?) throws -> String {
    let transferId = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970)

    try db.run(transfers.insert(
      id <- transferId,
      deviceId <- device.raw,
      kind <- "write",
      handle <- nil,
      parentHandle <- Int64(parent),
      pathKey <- nil,
      self.name <- name,
      totalBytes <- Int64(size),
      committedBytes <- 0,
      self.supportsPartial <- supportsPartial ? 1 : 0,
      etag_size <- nil,
      etag_mtime <- nil,
      localTempURL <- tempURL.path,
      self.finalURL <- sourceURL?.path,
      state <- "active",
      lastError <- nil,
      updatedAt <- now
    ))

    return transferId
  }

  public func updateProgress(id: String, committed: UInt64) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let query = transfers.filter(self.id == id)
    try db.run(query.update(
      committedBytes <- Int64(committed),
      updatedAt <- now
    ))
  }

  public func fail(id: String, error: Error) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let query = transfers.filter(self.id == id)
    try db.run(query.update(
      state <- "failed",
      lastError <- error.localizedDescription,
      updatedAt <- now
    ))
  }

  public func complete(id: String) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let query = transfers.filter(self.id == id)
    try db.run(query.update(
      state <- "done",
      updatedAt <- now
    ))
  }

  public func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord] {
    let query = transfers.filter(deviceId == device.raw && (state == "active" || state == "paused"))
    let rows = try db.prepare(query)

    return try rows.map { row in
      TransferRecord(
        id: try row.get(id),
        deviceId: MTPDeviceID(raw: try row.get(deviceId)),
        kind: try row.get(kind),
        handle: try row.get(handle).map(UInt32.init),
        parentHandle: try row.get(parentHandle).map(UInt32.init),
        name: try row.get(name),
        totalBytes: try row.get(totalBytes).map(UInt64.init),
        committedBytes: UInt64(try row.get(committedBytes)),
        supportsPartial: try row.get(supportsPartial) == 1,
        localTempURL: URL(fileURLWithPath: try row.get(localTempURL)),
        finalURL: (try row.get(finalURL)).map { URL(fileURLWithPath: $0) },
        state: try row.get(state),
        updatedAt: Date(timeIntervalSince1970: TimeInterval(try row.get(updatedAt)))
      )
    }
  }

  public func clearStaleTemps(olderThan: TimeInterval) throws {
    let cutoff = Int64(Date().timeIntervalSince1970 - olderThan)
    let query = transfers.filter(updatedAt < cutoff && (state == "failed" || state == "paused"))

    // Get temp URLs before deleting
    let tempURLs = try db.prepare(query.select(localTempURL)).map { try $0.get(localTempURL) }

    // Delete records
    try db.run(query.delete())

    // Clean up temp files
    for tempPath in tempURLs {
      try? FileManager.default.removeItem(atPath: tempPath)
    }
  }
}

enum TransferJournalError: Error {
  case schemaNotFound
}
