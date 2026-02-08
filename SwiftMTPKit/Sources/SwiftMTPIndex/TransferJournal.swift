// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SQLite3
import SwiftMTPCore

// SQLite constants that might not be available in all environments
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteTransferRecord: Sendable {
  public let id: String
  public let deviceId: String
  public let kind: String   // "read" | "write"
  public let handle: Int64?
  public let parentHandle: Int64?
  public let pathKey: String?
  public let name: String?
  public let totalBytes: Int64?
  public let committedBytes: Int64
  public let supportsPartial: Bool
  public let etagSize: Int64?
  public let etagMtime: Int64?
  public let localTempURL: String?
  public let finalURL: String?
  public let state: String   // "active" | "failed" | "done"
  public let lastError: String?
  public let updatedAt: Int64
}

public final class SQLiteTransferJournal: SwiftMTPCore.TransferJournal, @unchecked Sendable {
  private var db: OpaquePointer?

  public init(dbPath: String) throws {
    if sqlite3_open(dbPath, &db) != SQLITE_OK {
      defer { if db != nil { sqlite3_close(db) } }
      throw makeError("sqlite3_open failed")
    }
    try setupSchema()
  }

  deinit { if db != nil { sqlite3_close(db) } }

  private func setupSchema() throws {
    let sql = """
    CREATE TABLE IF NOT EXISTS transfers (
      id TEXT PRIMARY KEY,
      deviceId TEXT NOT NULL,
      kind TEXT NOT NULL,
      handle INTEGER,
      parentHandle INTEGER,
      pathKey TEXT,
      name TEXT,
      totalBytes INTEGER,
      committedBytes INTEGER NOT NULL DEFAULT 0,
      supportsPartial INTEGER NOT NULL DEFAULT 0,
      etag_size INTEGER,
      etag_mtime INTEGER,
      localTempURL TEXT,
      finalURL TEXT,
      state TEXT NOT NULL,
      lastError TEXT,
      updatedAt INTEGER NOT NULL
    );
    """
    try exec(sql)
  }

  // MARK: - Public API (TransferJournal Conformance)

  public func beginRead(
    device: MTPDeviceID,
    handle: UInt32,
    name: String,
    size: UInt64?,
    supportsPartial: Bool,
    tempURL: URL,
    finalURL: URL?,
    etag: (size: UInt64?, mtime: Date?)
  ) throws -> String {
    let transferId = UUID().uuidString
    try insertTransfer(
      id: transferId, deviceId: device.raw, kind: "read",
      handle: Int64(handle), parentHandle: nil, pathKey: nil, name: name,
      totalBytes: size.map { Int64($0) }, supportsPartial: supportsPartial,
      localTempPath: tempURL.path, finalPath: finalURL?.path
    )
    return transferId
  }

  public func beginWrite(
    device: MTPDeviceID,
    parent: UInt32,
    name: String,
    size: UInt64,
    supportsPartial: Bool,
    tempURL: URL,
    sourceURL: URL?
  ) throws -> String {
    let transferId = UUID().uuidString
    try insertTransfer(
      id: transferId, deviceId: device.raw, kind: "write",
      handle: nil, parentHandle: Int64(parent), pathKey: nil, name: name,
      totalBytes: Int64(size), supportsPartial: supportsPartial,
      localTempPath: tempURL.path, finalPath: sourceURL?.path
    )
    return transferId
  }

  public func updateProgress(id: String, committed: UInt64) throws {
    try updateCommitted(id: id, committed: Int64(committed))
  }

  public func fail(id: String, error: Error) throws {
    try markFailed(id: id, error: error)
  }

  public func complete(id: String) throws {
    try markDone(id: id)
  }

  public func loadResumables(for device: MTPDeviceID) throws -> [SwiftMTPCore.TransferRecord] {
    let active = try listResumables(deviceId: device.raw)
    return active.map { row in
        SwiftMTPCore.TransferRecord(
            id: row.id,
            deviceId: MTPDeviceID(raw: row.deviceId),
            kind: row.kind,
            handle: row.handle.map { UInt32($0) },
            parentHandle: row.parentHandle.map { UInt32($0) },
            name: row.name ?? "",
            totalBytes: row.totalBytes.map { UInt64($0) },
            committedBytes: UInt64(row.committedBytes),
            supportsPartial: row.supportsPartial,
            localTempURL: URL(fileURLWithPath: row.localTempURL ?? ""),
            finalURL: row.finalURL.map { URL(fileURLWithPath: $0) },
            state: row.state,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        )
    }
  }

  public func clearStaleTemps(olderThan: TimeInterval) throws {
    let ageSeconds = Int64(max(0, olderThan).rounded(.down))
    let cutoff = nowSec() - ageSeconds

    let staleRecords = try listCleanupCandidates(cutoff: cutoff)
    for record in staleRecords {
      guard let tempPath = record.localTempURL, !tempPath.isEmpty else { continue }
      try? FileManager.default.removeItem(atPath: tempPath)
    }

    try exec(
      "DELETE FROM transfers WHERE state != 'active' AND updatedAt <= ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, cutoff)
      }
    )
  }

  // MARK: - Internal implementations

  private func updateCommitted(id: String, committed: Int64) throws {
    let now = nowSec()
    try exec(
      "UPDATE transfers SET committedBytes = ?, updatedAt = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, committed)
        sqlite3_bind_int64(stmt, 2, now)
        sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
      }
    )
  }

  private func markFailed(id: String, error: Error) throws {
    let now = nowSec()
    try exec(
      "UPDATE transfers SET state = 'failed', lastError = ?, updatedAt = ? WHERE id = ?",
      bind: { s in
        let msg = String(describing: error)
        sqlite3_bind_text(s, 1, msg, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(s, 2, now)
        sqlite3_bind_text(s, 3, id, -1, SQLITE_TRANSIENT)
      }
    )
  }

  private func markDone(id: String) throws {
    let now = nowSec()
    try exec(
      "UPDATE transfers SET state = 'done', lastError = NULL, updatedAt = ? WHERE id = ?",
      bind: { s in
        sqlite3_bind_int64(s, 1, now)
        sqlite3_bind_text(s, 2, id, -1, SQLITE_TRANSIENT)
      }
    )
  }

  public func listActive() throws -> [SQLiteTransferRecord] {
    var out: [SQLiteTransferRecord] = []
    try query("SELECT id,deviceId,kind,handle,parentHandle,pathKey,name,totalBytes,committedBytes,supportsPartial,etag_size,etag_mtime,localTempURL,finalURL,state,lastError,updatedAt FROM transfers WHERE state='active' ORDER BY updatedAt DESC") { row in
      out.append(row)
    }
    return out
  }

  public func listFailed() throws -> [SQLiteTransferRecord] {
    var out: [SQLiteTransferRecord] = []
    try query("SELECT id,deviceId,kind,handle,parentHandle,pathKey,name,totalBytes,committedBytes,supportsPartial,etag_size,etag_mtime,localTempURL,finalURL,state,lastError,updatedAt FROM transfers WHERE state='failed' ORDER BY updatedAt DESC") { row in
      out.append(row)
    }
    return out
  }

  private func listResumables(deviceId: String) throws -> [SQLiteTransferRecord] {
    var out: [SQLiteTransferRecord] = []
    try query(
      "SELECT id,deviceId,kind,handle,parentHandle,pathKey,name,totalBytes,committedBytes,supportsPartial,etag_size,etag_mtime,localTempURL,finalURL,state,lastError,updatedAt FROM transfers WHERE deviceId = ? AND state IN ('active','failed') ORDER BY updatedAt DESC",
      bind: { s in
        sqlite3_bind_text(s, 1, deviceId, -1, SQLITE_TRANSIENT)
      }
    ) { row in
      out.append(row)
    }
    return out
  }

  // MARK: - Internals

  private func insertTransfer(
    id: String, deviceId: String, kind: String,
    handle: Int64?, parentHandle: Int64?, pathKey: String?, name: String?,
    totalBytes: Int64?, supportsPartial: Bool,
    localTempPath: String?, finalPath: String?
  ) throws {
    let now = nowSec()
    let sql = """
    INSERT INTO transfers
    (id,deviceId,kind,handle,parentHandle,pathKey,name,totalBytes,committedBytes,supportsPartial,etag_size,etag_mtime,localTempURL,finalURL,state,lastError,updatedAt)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'active', NULL, ?)
    """
    try exec(sql) { [self] s in
      sqlite3_bind_text(s, 1, id, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(s, 2, deviceId, -1, SQLITE_TRANSIENT)
      sqlite3_bind_text(s, 3, kind, -1, SQLITE_TRANSIENT)
      self.bindOptInt64(s, 4, handle)
      self.bindOptInt64(s, 5, parentHandle)
      self.bindOptText(s, 6, pathKey)
      self.bindOptText(s, 7, name)
      self.bindOptInt64(s, 8, totalBytes)
      sqlite3_bind_int64(s, 9, 0)
      sqlite3_bind_int(s, 10, supportsPartial ? 1 : 0)
      sqlite3_bind_null(s, 11)
      sqlite3_bind_null(s, 12)
      self.bindOptText(s, 13, localTempPath)
      self.bindOptText(s, 14, finalPath)
      sqlite3_bind_int64(s, 15, now)
    }
  }

  private func nowSec() -> Int64 { Int64(Date().timeIntervalSince1970) }

  private func exec(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw makeError("prepare") }
    defer { sqlite3_finalize(stmt) }
    if let b = bind { b(stmt!) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { throw makeError("step") }
  }

  private func query(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil, row: (SQLiteTransferRecord) -> Void) throws {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw makeError("prepare") }
    defer { sqlite3_finalize(stmt) }
    if let b = bind { b(stmt!) }
    while sqlite3_step(stmt) == SQLITE_ROW {
      row(SQLiteTransferRecord(
        id: getText(stmt!, 0),
        deviceId: getText(stmt!, 1),
        kind: getText(stmt!, 2),
        handle: getOptInt64(stmt!, 3),
        parentHandle: getOptInt64(stmt!, 4),
        pathKey: getOptText(stmt!, 5),
        name: getOptText(stmt!, 6),
        totalBytes: getOptInt64(stmt!, 7),
        committedBytes: sqlite3_column_int64(stmt!, 8),
        supportsPartial: sqlite3_column_int(stmt!, 9) != 0,
        etagSize: getOptInt64(stmt!,10),
        etagMtime: getOptInt64(stmt!,11),
        localTempURL: getOptText(stmt!,12),
        finalURL: getOptText(stmt!,13),
        state: getText(stmt!,14),
        lastError: getOptText(stmt!,15),
        updatedAt: sqlite3_column_int64(stmt!,16)
      ))
    }
  }

  private func getText(_ s: OpaquePointer, _ idx: Int32) -> String {
    guard let c = sqlite3_column_text(s, idx) else { return "" }
    return String(cString: c)
  }
  private func getOptText(_ s: OpaquePointer, _ idx: Int32) -> String? {
    sqlite3_column_type(s, idx) == SQLITE_NULL ? nil : getText(s, idx)
  }
  private func getOptInt64(_ s: OpaquePointer, _ idx: Int32) -> Int64? {
    sqlite3_column_type(s, idx) == SQLITE_NULL ? nil : sqlite3_column_int64(s, idx)
  }
  private func bindOptText(_ s: OpaquePointer, _ idx: Int32, _ v: String?) {
    if let v { sqlite3_bind_text(s, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } else { sqlite3_bind_null(s, idx) }
  }
  private func bindOptInt64(_ s: OpaquePointer, _ idx: Int32, _ v: Int64?) {
    if let v { sqlite3_bind_int64(s, idx, v) } else { sqlite3_bind_null(s, idx) }
  }
  private func makeError(_ msg: String) -> NSError {
    let err = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0!) } ?? "unknown"
    return NSError(domain: "TransferJournal", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(msg): \(err)"])
  }
}
