import Foundation
public struct MTPDeviceSummary: Sendable {
  public let id: MTPDeviceID
  public let manufacturer: String
  public let model: String
}
public enum MTPEvent: Sendable { case objectAdded(MTPObjectHandle), objectRemoved(MTPObjectHandle), storageInfoChanged(MTPStorageID) }
public protocol MTPDevice: Sendable {
  var id: MTPDeviceID { get }
  var info: MTPDeviceInfo { get async throws }
  func storages() async throws -> [MTPStorageInfo]
  func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<[MTPObjectInfo], Error>
  func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo
  func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress
  func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws -> Progress
  func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws
  func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws
  var events: AsyncStream<MTPEvent> { get }
}
public struct SwiftMTPConfig: Sendable {
  public var enumPageBudgetBytes = 512 * 1024
  public var transferChunkBytes  = 2 * 1024 * 1024
  public var ioTimeoutMs         = 10_000
  public var resumeEnabled       = true
  public var progressUpdateThrottleMs = 150
  public var indexingPriority: TaskPriority = .utility
  public var transferPriority: TaskPriority = .userInitiated
  public var timeSkewTolerance: TimeInterval = 300
  public init() {}
}
public actor MTPDeviceManager {
  public static let shared = MTPDeviceManager()
  public func startDiscovery(config: SwiftMTPConfig = .init()) async throws {}
  public func stopDiscovery() async {}
  public var devices: [MTPDeviceSummary] { get async { [] } }
  public var deviceAttached: AsyncStream<MTPDeviceSummary> { AsyncStream { _ in } }
  public var deviceDetached: AsyncStream<MTPDeviceID> { AsyncStream { _ in } }
  public func open(_ id: MTPDeviceID) async throws -> MTPDevice { throw MTPError.notSupported("not wired") }
}
