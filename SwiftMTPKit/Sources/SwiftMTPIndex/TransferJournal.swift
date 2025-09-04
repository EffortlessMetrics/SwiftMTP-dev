// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SQLite3

public final class DefaultTransferJournal: TransferJournal {
  private let dbPath: String
  private var db: OpaquePointer?

  public init(dbPath: String) throws {
    self.dbPath = dbPath
    try setupDatabase()
  }

  deinit {
    sqlite3_close(db)
  }

  private func setupDatabase() throws {
    // Open database connection
    let result = sqlite3_open(dbPath, &db)
    guard result == SQLITE_OK else {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }

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

    try executeSQL(schema)
  }

  private func executeSQL(_ sql: String) throws {
    guard let db = db else {
      throw TransferJournalError.databaseError("Database not open")
    }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard result == SQLITE_OK else {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }

    let stepResult = sqlite3_step(statement)
    if stepResult != SQLITE_DONE && stepResult != SQLITE_ROW {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }
  }

  private func executePrepared(_ sql: String, _ parameters: Any?...) throws {
    guard let db = db else {
      throw TransferJournalError.databaseError("Database not open")
    }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard result == SQLITE_OK else {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }

    // Bind parameters
    for (index, parameter) in parameters.enumerated() {
      let paramIndex = Int32(index + 1)
      try bindParameter(statement: statement, index: paramIndex, value: parameter)
    }

    let stepResult = sqlite3_step(statement)
    if stepResult != SQLITE_DONE && stepResult != SQLITE_ROW {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }
  }

  private func bindParameter(statement: OpaquePointer?, index: Int32, value: Any?) throws {
    guard let statement = statement else { return }

    if let value = value {
      switch value {
      case let stringValue as String:
        let result = sqlite3_bind_text(statement, index, stringValue, -1, nil)
        guard result == SQLITE_OK else {
          throw TransferJournalError.databaseError("Failed to bind string parameter")
        }
      case let intValue as Int64:
        let result = sqlite3_bind_int64(statement, index, intValue)
        guard result == SQLITE_OK else {
          throw TransferJournalError.databaseError("Failed to bind int parameter")
        }
      case let intValue as Int:
        let result = sqlite3_bind_int64(statement, index, Int64(intValue))
        guard result == SQLITE_OK else {
          throw TransferJournalError.databaseError("Failed to bind int parameter")
        }
      default:
        let result = sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else {
          throw TransferJournalError.databaseError("Failed to bind null parameter")
        }
      }
    } else {
      let result = sqlite3_bind_null(statement, index)
      guard result == SQLITE_OK else {
        throw TransferJournalError.databaseError("Failed to bind null parameter")
      }
    }
  }

  public func beginRead(device: MTPDeviceID, handle: UInt32, name: String,
                       size: UInt64?, supportsPartial: Bool,
                       tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String {
    let transferId = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970)

    let sql = """
    INSERT INTO transfers (
      id, deviceId, kind, handle, parentHandle, pathKey, name, totalBytes,
      committedBytes, supportsPartial, etag_size, etag_mtime, localTempURL,
      finalURL, state, lastError, updatedAt
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    try executePrepared(sql,
      transferId,
      device.raw,
      "read",
      Int64(handle),
      nil,
      nil,
      name,
      size.map(Int64.init),
      Int64(0),
      supportsPartial ? 1 : 0,
      etag.size.map(Int64.init),
      etag.mtime.map { Int64($0.timeIntervalSince1970) },
      tempURL.path,
      finalURL?.path,
      "active",
      nil,
      now
    )

    return transferId
  }

  public func beginWrite(device: MTPDeviceID, parent: UInt32, name: String,
                        size: UInt64, supportsPartial: Bool,
                        tempURL: URL, sourceURL: URL?) throws -> String {
    let transferId = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970)

    let sql = """
    INSERT INTO transfers (
      id, deviceId, kind, handle, parentHandle, pathKey, name, totalBytes,
      committedBytes, supportsPartial, etag_size, etag_mtime, localTempURL,
      finalURL, state, lastError, updatedAt
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    try executePrepared(sql,
      transferId,
      device.raw,
      "write",
      nil,
      Int64(parent),
      nil,
      name,
      Int64(size),
      Int64(0),
      supportsPartial ? 1 : 0,
      nil,
      nil,
      tempURL.path,
      sourceURL?.path,
      "active",
      nil,
      now
    )

    return transferId
  }

  public func updateProgress(id: String, committed: UInt64) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let sql = "UPDATE transfers SET committedBytes = ?, updatedAt = ? WHERE id = ?"
    try executePrepared(sql, Int64(committed), now, id)
  }

  public func fail(id: String, error: Error) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let sql = "UPDATE transfers SET state = ?, lastError = ?, updatedAt = ? WHERE id = ?"
    try executePrepared(sql, "failed", error.localizedDescription, now, id)
  }

  public func complete(id: String) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let sql = "UPDATE transfers SET state = ?, updatedAt = ? WHERE id = ?"
    try executePrepared(sql, "done", now, id)
  }

  public func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord] {
    let sql = """
    SELECT id, deviceId, kind, handle, parentHandle, name, totalBytes, committedBytes,
           supportsPartial, localTempURL, finalURL, state, updatedAt
    FROM transfers
    WHERE deviceId = ? AND (state = 'active' OR state = 'paused')
    """

    guard let db = db else {
      throw TransferJournalError.databaseError("Database not open")
    }

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }

    let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard result == SQLITE_OK else {
      throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
    }

    // Bind device ID parameter
    let deviceIdResult = sqlite3_bind_text(statement, 1, device.raw, -1, nil)
    guard deviceIdResult == SQLITE_OK else {
      throw TransferJournalError.databaseError("Failed to bind deviceId parameter")
    }

    var records: [TransferRecord] = []

    while sqlite3_step(statement) == SQLITE_ROW {
      let record = try TransferRecord(
        id: String(cString: sqlite3_column_text(statement, 0)),
        deviceId: MTPDeviceID(raw: String(cString: sqlite3_column_text(statement, 1))),
        kind: String(cString: sqlite3_column_text(statement, 2)),
        handle: sqlite3_column_type(statement, 3) != SQLITE_NULL ? UInt32(sqlite3_column_int64(statement, 3)) : nil,
        parentHandle: sqlite3_column_type(statement, 4) != SQLITE_NULL ? UInt32(sqlite3_column_int64(statement, 4)) : nil,
        name: String(cString: sqlite3_column_text(statement, 5)),
        totalBytes: sqlite3_column_type(statement, 6) != SQLITE_NULL ? UInt64(sqlite3_column_int64(statement, 6)) : nil,
        committedBytes: UInt64(sqlite3_column_int64(statement, 7)),
        supportsPartial: sqlite3_column_int64(statement, 8) == 1,
        localTempURL: URL(fileURLWithPath: String(cString: sqlite3_column_text(statement, 9))),
        finalURL: sqlite3_column_type(statement, 10) != SQLITE_NULL ? URL(fileURLWithPath: String(cString: sqlite3_column_text(statement, 10))) : nil,
        state: String(cString: sqlite3_column_text(statement, 11)),
        updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 12)))
      )
      records.append(record)
    }

    return records
  }

  public func clearStaleTemps(olderThan: TimeInterval) throws {
    let cutoff = Int64(Date().timeIntervalSince1970 - olderThan)

    // First, get temp URLs for stale records
    let selectSQL = """
    SELECT localTempURL FROM transfers
    WHERE updatedAt < ? AND (state = 'failed' OR state = 'paused')
    """

    guard let db = db else {
      throw TransferJournalError.databaseError("Database not open")
    }

    var tempURLs: [String] = []

    do {
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }

      let result = sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil)
      guard result == SQLITE_OK else {
        throw TransferJournalError.databaseError(String(cString: sqlite3_errmsg(db)))
      }

      let cutoffResult = sqlite3_bind_int64(statement, 1, cutoff)
      guard cutoffResult == SQLITE_OK else {
        throw TransferJournalError.databaseError("Failed to bind cutoff parameter")
      }

      while sqlite3_step(statement) == SQLITE_ROW {
        if let tempURL = sqlite3_column_text(statement, 0) {
          tempURLs.append(String(cString: tempURL))
        }
      }
    }

    // Delete the stale records
    let deleteSQL = """
    DELETE FROM transfers
    WHERE updatedAt < ? AND (state = 'failed' OR state = 'paused')
    """
    try executePrepared(deleteSQL, cutoff)

    // Clean up temp files
    for tempPath in tempURLs {
      try? FileManager.default.removeItem(atPath: tempPath)
    }
  }
}

enum TransferJournalError: Error {
  case schemaNotFound
  case databaseError(String)
}
