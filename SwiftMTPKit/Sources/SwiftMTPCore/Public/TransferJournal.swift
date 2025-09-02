import Foundation

public protocol TransferJournal: Sendable {
  func beginRead(device: MTPDeviceID, handle: UInt32, name: String,
                 size: UInt64?, supportsPartial: Bool,
                 tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String // returns id
  func beginWrite(device: MTPDeviceID, parent: UInt32, name: String,
                  size: UInt64, supportsPartial: Bool,
                  tempURL: URL, sourceURL: URL?) throws -> String
  func updateProgress(id: String, committed: UInt64) throws
  func fail(id: String, error: Error) throws
  func complete(id: String) throws
  func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord]
  func clearStaleTemps(olderThan: TimeInterval) throws
}

public struct TransferRecord: Sendable {
  public let id: String
  public let deviceId: MTPDeviceID
  public let kind: String
  public let handle: UInt32?
  public let parentHandle: UInt32?
  public let name: String
  public let totalBytes: UInt64?
  public let committedBytes: UInt64
  public let supportsPartial: Bool
  public let localTempURL: URL
  public let finalURL: URL?
  public let state: String
  public let updatedAt: Date

  public init(id: String, deviceId: MTPDeviceID, kind: String, handle: UInt32?, parentHandle: UInt32?, name: String, totalBytes: UInt64?, committedBytes: UInt64, supportsPartial: Bool, localTempURL: URL, finalURL: URL?, state: String, updatedAt: Date) {
    self.id = id
    self.deviceId = deviceId
    self.kind = kind
    self.handle = handle
    self.parentHandle = parentHandle
    self.name = name
    self.totalBytes = totalBytes
    self.committedBytes = committedBytes
    self.supportsPartial = supportsPartial
    self.localTempURL = localTempURL
    self.finalURL = finalURL
    self.state = state
    self.updatedAt = updatedAt
  }
}
