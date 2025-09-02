import Foundation
public struct MTPDeviceSummary: Sendable {
  public let id: MTPDeviceID
  public let manufacturer: String
  public let model: String
  public init(id: MTPDeviceID, manufacturer: String, model: String) {
    self.id = id
    self.manufacturer = manufacturer
    self.model = model
  }
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
  private var attachedContinuation: AsyncStream<MTPDeviceSummary>.Continuation?
  private var detachedContinuation: AsyncStream<MTPDeviceID>.Continuation?

  public func startDiscovery(config: SwiftMTPConfig = .init()) async throws {
    self.config = config
    let (attachedStream, attachedCont) = AsyncStream<MTPDeviceSummary>.makeStream()
    let (detachedStream, detachedCont) = AsyncStream<MTPDeviceID>.makeStream()
    self.attachedContinuation = attachedCont
    self.detachedContinuation = detachedCont
    self.deviceAttached = attachedStream
    self.deviceDetached = detachedStream

    // Start USB transport discovery
    await startTransportDiscovery()
  }

  private func startTransportDiscovery() async {
    TransportDiscovery.start(
      onAttach: { [weak self] dev in
        Task { [weak self] in
          await self?.yieldAttached(dev)
        }
      },
      onDetach: { [weak self] id in
        Task { [weak self] in
          await self?.yieldDetached(id)
        }
      }
    )
  }

  private func yieldAttached(_ dev: MTPDeviceSummary) async {
    attachedContinuation?.yield(dev)
  }

  private func yieldDetached(_ id: MTPDeviceID) async {
    detachedContinuation?.yield(id)
  }

  public func stopDiscovery() async {
    attachedContinuation?.finish()
    detachedContinuation?.finish()
    attachedContinuation = nil
    detachedContinuation = nil
  }

  public var devices: [MTPDeviceSummary] { get async { [] } } // TODO: track current devices
  public private(set) var deviceAttached: AsyncStream<MTPDeviceSummary> = AsyncStream { _ in }
  public private(set) var deviceDetached: AsyncStream<MTPDeviceID> = AsyncStream { _ in }
  public func open(_ id: MTPDeviceID) async throws -> MTPDevice {
    // For now, we need the device summary to create the device
    // In a real implementation, we'd track connected devices
    throw MTPError.notSupported("Use openDevice(with:) instead")
  }

  public func openDevice(with summary: MTPDeviceSummary, transport: any MTPTransport, indexManager: MTPIndexManager? = nil) async throws -> MTPDevice {
    return try MTPDeviceActor(id: summary.id, summary: summary, transport: transport, indexManager: indexManager)
  }

  private var config: SwiftMTPConfig = .init()
}
