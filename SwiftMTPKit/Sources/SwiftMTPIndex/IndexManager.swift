import Foundation
import SwiftMTPCore
import Collections

public struct MTPIndexManager {
  private let dbPath: String

  public init(dbPath: String = "~/Library/Application Support/SwiftMTP/transfers.db") {
    self.dbPath = (dbPath as NSString).expandingTildeInPath
  }

  public func createTransferJournal() throws -> TransferJournal {
    // Ensure directory exists
    let directory = (dbPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    return try DefaultTransferJournal(dbPath: dbPath)
  }
}
