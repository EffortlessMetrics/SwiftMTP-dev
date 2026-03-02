// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Convenience manager for creating transfer journals backed by SQLite.
public struct MTPIndexManager: Sendable {
  private let dbPath: String

  public init(dbPath: String = "~/Library/Application Support/SwiftMTP/transfers.db") {
    self.dbPath = (dbPath as NSString).expandingTildeInPath
  }

  public func createTransferJournal() throws -> SwiftMTPCore.TransferJournal {
    // Ensure directory exists
    let directory = (dbPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    return try SQLiteTransferJournal(dbPath: dbPath)
  }
}
