// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SQLite3

// SQLite constants that might not be available in all environments
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DBError: Error, CustomStringConvertible {
  case open(String), prepare(String), step(String), bind(String)
  case column(String), notFound, constraint(String)

  public var description: String {
    switch self {
    case .open(let m), .prepare(let m), .step(let m), .bind(let m), .constraint(let m): return m
    case .column(let m): return "Missing column: \(m)"
    case .notFound: return "No rows"
    }
  }
}

public final class SQLiteDB: @unchecked Sendable {
  public let path: String
  private var handle: OpaquePointer?
  private let dbLock = NSRecursiveLock()

  /// Execute a block inside an exclusive transaction.
  /// Serializes concurrent callers so only one transaction is active at a time.
  public func withTransaction<R>(_ body: () throws -> R) throws -> R {
    dbLock.lock()
    defer { dbLock.unlock() }
    try exec("BEGIN IMMEDIATE TRANSACTION")
    do {
      let result = try body()
      try exec("COMMIT")
      return result
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }

  public init(path: String) throws {
    self.path = path
    var db: OpaquePointer?
    if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
      throw DBError.open(String(cString: sqlite3_errmsg(db)))
    }
    self.handle = db
    sqlite3_busy_timeout(db, 5000)
    try exec("PRAGMA journal_mode=WAL;")
    try exec("PRAGMA synchronous=NORMAL;")
  }

  /// Open a database in read-only mode (for cross-process WAL readers).
  public init(path: String, readOnly: Bool) throws {
    self.path = path
    var db: OpaquePointer?
    let flags: Int32 = readOnly
      ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
      : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)
    if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
      throw DBError.open(String(cString: sqlite3_errmsg(db)))
    }
    self.handle = db
    sqlite3_busy_timeout(db, 5000)
    if !readOnly {
      try exec("PRAGMA journal_mode=WAL;")
      try exec("PRAGMA synchronous=NORMAL;")
    }
  }

  deinit { if let db = handle { sqlite3_close(db) } }

  @inline(__always) private func err() -> String {
    String(cString: sqlite3_errmsg(handle))
  }

  public func exec(_ sql: String) throws {
    dbLock.lock()
    defer { dbLock.unlock() }
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw DBError.step(err()) }
  }

  public func prepare(_ sql: String) throws -> OpaquePointer {
    dbLock.lock()
    defer { dbLock.unlock() }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DBError.prepare(err()) }
    return stmt!
  }

  public func withStatement<R>(_ sql: String, _ body: (OpaquePointer) throws -> R) throws -> R {
    dbLock.lock()
    defer { dbLock.unlock() }
    let stmt = try prepare(sql)
    defer { sqlite3_finalize(stmt) }
    return try body(stmt)
  }

  public func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Int64?) throws {
    dbLock.lock()
    defer { dbLock.unlock() }
    if let v = value {
      guard sqlite3_bind_int64(stmt, idx, v) == SQLITE_OK else { throw DBError.bind(err()) }
    } else {
      guard sqlite3_bind_null(stmt, idx) == SQLITE_OK else { throw DBError.bind(err()) }
    }
  }

  public func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Double?) throws {
    dbLock.lock()
    defer { dbLock.unlock() }
    if let v = value {
      guard sqlite3_bind_double(stmt, idx, v) == SQLITE_OK else { throw DBError.bind(err()) }
    } else {
      guard sqlite3_bind_null(stmt, idx) == SQLITE_OK else { throw DBError.bind(err()) }
    }
  }

  public func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: String?) throws {
    dbLock.lock()
    defer { dbLock.unlock() }
    if let v = value {
      guard sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw DBError.bind(err()) }
    } else {
      guard sqlite3_bind_null(stmt, idx) == SQLITE_OK else { throw DBError.bind(err()) }
    }
  }

  public func step(_ stmt: OpaquePointer) throws -> Bool {
    dbLock.lock()
    defer { dbLock.unlock() }
    let rc = sqlite3_step(stmt)
    switch rc {
    case SQLITE_ROW:    return true
    case SQLITE_DONE:   return false
    case SQLITE_CONSTRAINT: throw DBError.constraint(err())
    default: throw DBError.step(err())
    }
  }

  public func colInt64(_ stmt: OpaquePointer, _ idx: Int32) -> Int64? {
    dbLock.lock()
    defer { dbLock.unlock() }
    return sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, idx)
  }
  public func colText(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
    dbLock.lock()
    defer { dbLock.unlock() }
    guard sqlite3_column_type(stmt, idx) != SQLITE_NULL, let c = sqlite3_column_text(stmt, idx) else { return nil }
    return String(cString: c)
  }
}
