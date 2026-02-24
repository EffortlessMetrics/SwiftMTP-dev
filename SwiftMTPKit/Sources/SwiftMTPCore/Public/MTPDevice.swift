// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftMTPQuirks

public struct MTPDeviceID: Hashable, Sendable, Codable {
  public let raw: String
  public init(raw: String) { self.raw = raw }
}

/// Summary information about an MTP device discovered on the system.
///
/// This lightweight structure provides basic identification information
/// about a connected MTP device without requiring a full device connection.
public struct MTPDeviceSummary: Sendable {
  /// Unique identifier for the device
  public let id: MTPDeviceID
  /// Device manufacturer name
  public let manufacturer: String
  /// Device model name
  public let model: String
  /// USB Vendor ID
  public let vendorID: UInt16?
  /// USB Product ID
  public let productID: UInt16?
  /// USB Bus number
  public let bus: UInt8?
  /// USB Device address
  public let address: UInt8?
  /// USB serial number from iSerialNumber descriptor (most reliable identity signal)
  public let usbSerial: String?

  /// Device fingerprint for quirk matching
  public var fingerprint: String {
    guard let vid = vendorID, let pid = productID else { return "unknown" }
    return String(format: "%04x:%04x", vid, pid)
  }

  /// Creates a new device summary.
  /// - Parameters:
  ///   - id: Unique device identifier
  ///   - manufacturer: Device manufacturer name
  ///   - model: Device model name
  ///   - vendorID: USB Vendor ID
  ///   - productID: USB Product ID
  ///   - bus: USB Bus number
  ///   - address: USB Device address
  public init(
    id: MTPDeviceID, manufacturer: String, model: String, vendorID: UInt16? = nil,
    productID: UInt16? = nil, bus: UInt8? = nil, address: UInt8? = nil, usbSerial: String? = nil
  ) {
    self.id = id
    self.manufacturer = manufacturer
    self.model = model
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.usbSerial = usbSerial
  }
}
/// Events that can be emitted by an MTP device during operation.
///
/// These events notify about changes to the device's content or state
/// that may require UI updates or re-indexing.
public enum MTPEvent: Sendable {
  /// A new object was added to the device
  case objectAdded(MTPObjectHandle)
  /// An object was removed from the device
  case objectRemoved(MTPObjectHandle)
  /// Storage information changed (capacity, free space, etc.)
  case storageInfoChanged(MTPStorageID)

  /// Parse MTP event from raw PTP/MTP event container data
  public static func fromRaw(_ data: Data) -> MTPEvent? {
    guard data.count >= 12 else { return nil }
    // PTP/MTP Event container: [len(4) type(2)=4 code(2) txid(4) params...]
    guard let code: UInt16 = MTPEndianCodec.decodeUInt16(from: data, at: 6) else { return nil }
    let paramCount = (data.count - 12) / 4
    var params: [UInt32] = []
    params.reserveCapacity(paramCount)
    for index in 0..<paramCount {
      guard let value: UInt32 = MTPEndianCodec.decodeUInt32(from: data, at: 12 + index * 4) else { break }
      params.append(value)
    }

    switch code {
    case 0x4002:  // ObjectAdded
      guard let handle = params.first else { return nil }
      return .objectAdded(handle)
    case 0x4003:  // ObjectRemoved
      guard let handle = params.first else { return nil }
      return .objectRemoved(handle)
    case 0x400C:  // StorageInfoChanged
      guard let storageIdRaw = params.first else { return nil }
      return .storageInfoChanged(MTPStorageID(raw: storageIdRaw))
    default:
      return nil
    }
  }
}

public struct MTPStorageID: Hashable, Sendable, Codable {
  public let raw: UInt32
  public init(raw: UInt32) { self.raw = raw }
}

public struct MTPDeviceInfo: Sendable, Codable {
  public let manufacturer: String
  public let model: String
  public let version: String
  public let serialNumber: String?
  public let operationsSupported: Set<UInt16>
  public let eventsSupported: Set<UInt16>

  public init(
    manufacturer: String, model: String, version: String, serialNumber: String?,
    operationsSupported: Set<UInt16>, eventsSupported: Set<UInt16>
  ) {
    self.manufacturer = manufacturer
    self.model = model
    self.version = version
    self.serialNumber = serialNumber
    self.operationsSupported = operationsSupported
    self.eventsSupported = eventsSupported
  }
}

public struct MTPStorageInfo: Sendable, Codable {
  public let id: MTPStorageID
  public let description: String
  public let capacityBytes: UInt64
  public let freeBytes: UInt64
  public let isReadOnly: Bool

  public init(
    id: MTPStorageID, description: String, capacityBytes: UInt64, freeBytes: UInt64,
    isReadOnly: Bool
  ) {
    self.id = id
    self.description = description
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    self.isReadOnly = isReadOnly
  }
}

public typealias MTPObjectHandle = UInt32

public struct MTPObjectInfo: Sendable, Codable {
  public let handle: MTPObjectHandle
  public let storage: MTPStorageID
  public let parent: MTPObjectHandle?
  public let name: String
  public let sizeBytes: UInt64?
  public let modified: Date?
  public let formatCode: UInt16
  public let properties: [UInt16: String]

  public init(
    handle: MTPObjectHandle, storage: MTPStorageID, parent: MTPObjectHandle?, name: String,
    sizeBytes: UInt64?, modified: Date?, formatCode: UInt16, properties: [UInt16: String]
  ) {
    self.handle = handle
    self.storage = storage
    self.parent = parent
    self.name = name
    self.sizeBytes = sizeBytes
    self.modified = modified
    self.formatCode = formatCode
    self.properties = properties
  }
}
/// Protocol defining the interface for interacting with MTP devices.
///
/// This protocol provides the core functionality for browsing, reading from,
/// and writing to MTP-compliant devices such as smartphones, tablets, and cameras.
///
/// ## Example Usage
/// ```swift
/// // Get device information
/// let info = try await device.info
/// print("Connected to \(info.manufacturer) \(info.model)")
///
/// // List storage devices
/// let storages = try await device.storages()
/// for storage in storages {
///     print("Storage: \(storage.description)")
/// }
///
/// // Download a file
/// let progress = try await device.read(handle: fileHandle, range: nil, to: destinationURL)
/// print("Downloaded \(progress.completedUnitCount) bytes")
/// ```
public protocol MTPDevice: Sendable {
  /// Unique identifier for this device instance
  var id: MTPDeviceID { get }

  /// Device summary information
  var summary: MTPDeviceSummary { get }

  /// Detailed information about the device and its capabilities.
  ///
  /// This includes manufacturer, model, version, supported operations,
  /// and other device-specific information.
  var info: MTPDeviceInfo { get async throws }

  /// Get information about all storage devices on this MTP device.
  ///
  /// Most devices have a single storage (internal), but some devices
  /// like cameras may have multiple storages (internal + SD card).
  ///
  /// - Returns: Array of storage information structures
  func storages() async throws -> [MTPStorageInfo]
  /// Enumerate objects (files and folders) in a storage device.
  ///
  /// This method provides an asynchronous stream of object batches for
  /// efficient enumeration of large directories without loading everything
  /// into memory at once.
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root directory
  ///   - storage: Storage device to enumerate
  /// - Returns: Async stream yielding batches of object information
  ///
  /// ## Example
  /// ```swift
  /// let stream = device.list(parent: nil, in: storageID)
  /// for try await batch in stream {
  ///     for object in batch {
  ///         print("\(object.name): \(object.sizeBytes ?? 0) bytes")
  ///     }
  /// }
  /// ```
  func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<
    [MTPObjectInfo], Error
  >

  /// Get detailed information about a specific object.
  ///
  /// - Parameter handle: Handle of the object to query
  /// - Returns: Detailed object information
  func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo

  /// Read data from an object (download file).
  ///
  /// Supports resumable downloads when the device supports partial object operations.
  /// Progress is reported through the returned `Progress` object.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to read
  ///   - range: Byte range to read, or `nil` for entire file
  ///   - url: Local destination URL for the downloaded data
  /// - Returns: Progress object for monitoring transfer progress
  ///
  /// ## Example
  /// ```swift
  /// let progress = try await device.read(handle: fileHandle, range: nil, to: destinationURL)
  ///
  /// // Monitor progress
  /// for await update in progress.publisher.values {
  ///     print("Progress: \(update.fractionCompleted * 100)%")
  /// }
  /// ```
  func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress

  /// Write data to create a new object (upload file).
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root
  ///   - name: Name for the new file
  ///   - size: Size of the data to be written
  ///   - url: Local source URL of the data to upload
  /// - Returns: Progress object for monitoring transfer progress
  func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws
    -> Progress

  /// Create a folder on the device.
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root
  ///   - name: Name for the new folder
  ///   - storage: Target storage ID
  /// - Returns: Handle of the newly created folder
  func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID) async throws
    -> MTPObjectHandle

  /// Delete an object from the device.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to delete
  ///   - recursive: If `true`, delete directories and their contents recursively
  func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws

  /// Move an object to a new location on the device.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to move
  ///   - newParent: New parent directory handle, or `nil` for root
  func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws

  /// Probed capabilities of the device
  var probedCapabilities: [String: Bool] { get async }

  /// Current effective tuning of the device
  var effectiveTuning: EffectiveTuning { get async }

  /// Resolved device policy (tuning + flags + fallbacks + provenance).
  /// Default: `nil` (not yet probed).
  var devicePolicy: DevicePolicy? { get async }

  /// Structured diagnostic record from the most recent probe/open cycle.
  /// Default: `nil` (not yet probed).
  var probeReceipt: ProbeReceipt? { get async }

  /// Ensure the device session is open, opening it if necessary.
  func openIfNeeded() async throws

  /// Close the device session and release all underlying transport resources.
  /// Used for clean lifecycle management during profiling or shutdown.
  @_spi(Dev)
  func devClose() async throws

  @_spi(Dev) func devGetDeviceInfoUncached() async throws -> MTPDeviceInfo
  @_spi(Dev) func devGetStorageIDsUncached() async throws -> [MTPStorageID]
  @_spi(Dev) func devGetRootHandlesUncached(storage: MTPStorageID) async throws -> [MTPObjectHandle]
  @_spi(Dev) func devGetObjectInfoUncached(handle: MTPObjectHandle) async throws -> MTPObjectInfo

  /// Stream of events from the device.
  ///
  /// Listen to this stream to be notified of changes to the device's
  /// content or state, such as files being added or removed.
  ///
  /// ## Example
  /// ```swift
  /// for await event in device.events {
  ///     switch event {
  ///     case .objectAdded(let handle):
  ///         print("New file added: \(handle)")
  ///     case .objectRemoved(let handle):
  ///         print("File removed: \(handle)")
  ///     case .storageInfoChanged(let storageID):
  ///         print("Storage changed: \(storageID)")
  ///     }
  /// }
  /// ```
  var events: AsyncStream<MTPEvent> { get }
}

/// Default implementations for optional MTPDevice properties.
public extension MTPDevice {
  var devicePolicy: DevicePolicy? { get async { nil } }
  var probeReceipt: ProbeReceipt? { get async { nil } }
}

/// Configuration options for SwiftMTP behavior and performance tuning.
///
/// Use this structure to customize the library's behavior for your specific use case.
/// These settings affect memory usage, transfer speeds, and timeout behavior.
public struct SwiftMTPConfig: Sendable {
  /// Maximum memory to use for enumeration page buffering.
  ///
  /// Higher values reduce round trips but increase memory usage.
  /// Default: 512KB
  public var enumPageBudgetBytes = 512 * 1024

  /// Chunk size for file transfers.
  ///
  /// Larger chunks improve throughput but may increase latency for small files.
  /// Auto-tuned based on device capabilities. Default: 2MB
  public var transferChunkBytes = 2 * 1024 * 1024

  /// Timeout for I/O operations in milliseconds.
  ///
  /// Increase for slow devices or unreliable connections. Default: 10 seconds
  public var ioTimeoutMs = 10_000

  /// Timeout for handshake phase (waiting for first DATA-IN packet).
  ///
  /// Time budget for the first DATA-IN packet of a command (e.g., GetDeviceInfo).
  /// Default: 6 seconds
  public var handshakeTimeoutMs = 6_000

  /// Timeout for inactivity during streaming phases.
  ///
  /// Abort if no bytes arrive (or depart) for this duration during data transfers.
  /// Default: 8 seconds
  public var inactivityTimeoutMs = 8_000

  /// Overall operation deadline.
  ///
  /// Absolute wall-clock cap for the whole command (command → data → response).
  /// Default: 60 seconds
  public var overallDeadlineMs = 60_000

  /// Post-open stabilization delay in milliseconds.
  ///
  /// Time to wait after opening a device session before first storage operation.
  /// Some devices (e.g., Xiaomi) need this delay to become ready. Default: 0
  public var stabilizeMs = 0

  /// Post-claim stabilization delay in milliseconds.
  ///
  /// Time to wait after claiming the USB interface before sending commands.
  /// Some devices (e.g., Pixel 7, Samsung) need this delay for MTP stack readiness.
  /// Default: 250ms
  public var postClaimStabilizeMs = 250

  /// Post-probe stabilization delay in milliseconds.
  ///
  /// Time to wait after successfully probing the MTP interface before proceeding.
  /// Some devices (e.g., Pixel) need additional time for the MTP stack to become fully ready.
  /// Default: 0ms
  public var postProbeStabilizeMs = 0

  /// Whether to call libusb_reset_device after opening the device handle.
  /// Defaults to false.
  public var resetOnOpen = false

  /// Whether to temporarily disable the interrupt event pump.
  /// Defaults to false.
  public var disableEventPump = false

  /// Enable resumable transfers when device supports partial operations.
  ///
  /// When disabled, all transfers restart from beginning on interruption. Default: true
  public var resumeEnabled = true

  /// Minimum time between progress updates in milliseconds.
  ///
  /// Lower values provide more responsive progress but may impact performance. Default: 150ms
  public var progressUpdateThrottleMs = 150

  /// Task priority for background indexing operations.
  ///
  /// Use `.background` for invisible indexing, `.utility` for user-visible but not urgent. Default: `.utility`
  public var indexingPriority: TaskPriority = .utility

  /// Task priority for file transfer operations.
  ///
  /// Use `.userInitiated` for user-requested transfers. Default: `.userInitiated`
  public var transferPriority: TaskPriority = .userInitiated

  /// Time skew tolerance for file modification time comparisons.
  ///
  /// Accounts for clock differences between host and device. Default: 5 minutes
  public var timeSkewTolerance: TimeInterval = 300

  /// Creates a default configuration.
  public init() {}

  /// Apply effective tuning parameters to this configuration
  public mutating func apply(_ tuning: EffectiveTuning) {
    self.transferChunkBytes = tuning.maxChunkBytes
    self.ioTimeoutMs = tuning.ioTimeoutMs
    self.handshakeTimeoutMs = tuning.handshakeTimeoutMs
    self.inactivityTimeoutMs = tuning.inactivityTimeoutMs
    self.overallDeadlineMs = tuning.overallDeadlineMs
    self.stabilizeMs = tuning.stabilizeMs
    self.resetOnOpen = tuning.resetOnOpen
    self.disableEventPump = tuning.disableEventPump
  }
}
/// Central manager for MTP device discovery and lifecycle management.
///
/// This actor coordinates device discovery, hotplug events, and provides
/// the main entry point for connecting to MTP devices. Use the shared instance
/// for all device management operations.
///
/// ## Example Usage
/// ```swift
/// // Start discovery
/// try await MTPDeviceManager.shared.startDiscovery()
///
/// // Monitor for device connections
/// for await deviceSummary in MTPDeviceManager.shared.deviceAttached {
///     print("Device connected: \(deviceSummary.manufacturer) \(deviceSummary.model)")
/// }
/// ```
public actor MTPDeviceManager {
  /// Shared instance for device management
  public static let shared = MTPDeviceManager()

  /// Persistence provider for learned profiles, profiling runs, etc.
  public var persistence: any MTPPersistenceProvider = NullPersistenceProvider()

  public func setPersistence(_ provider: any MTPPersistenceProvider) {
    self.persistence = provider
  }

  private var attachedContinuation: AsyncStream<MTPDeviceSummary>.Continuation?
  private var detachedContinuation: AsyncStream<MTPDeviceID>.Continuation?
  private var currentDevices: [MTPDeviceSummary] = []
  private var defaultTransportFactory: (@Sendable () -> any MTPTransport)?
  private var discoverySnapshotProvider: (@Sendable () async throws -> [MTPDeviceSummary])?
  private var hotplugDiscoveryStarter:
    (
      @Sendable (
        @escaping (MTPDeviceSummary) -> Void,
        @escaping (MTPDeviceID) -> Void
      ) -> Void
    )?

  /// Start MTP device discovery with the specified configuration.
  ///
  /// This method initializes the USB transport layer and begins monitoring
  /// for MTP device connections and disconnections. Once started, use the
  /// `deviceAttached` and `deviceDetached` streams to monitor device events.
  ///
  /// - Parameter config: Configuration options for device discovery and behavior
  /// - Throws: Errors related to USB subsystem initialization
  ///
  /// ## Example
  /// ```swift
  /// var config = SwiftMTPConfig()
  /// config.transferChunkBytes = 4 * 1024 * 1024  // 4MB chunks
  /// try await MTPDeviceManager.shared.startDiscovery(config: config)
  /// ```
  public func startDiscovery(config: SwiftMTPConfig = .init()) async throws {
    attachedContinuation?.finish()
    detachedContinuation?.finish()
    currentDevices.removeAll(keepingCapacity: true)

    self.config = config
    let (attachedStream, attachedCont) = AsyncStream<MTPDeviceSummary>.makeStream()
    let (detachedStream, detachedCont) = AsyncStream<MTPDeviceID>.makeStream()
    self.attachedContinuation = attachedCont
    self.detachedContinuation = detachedCont
    self.deviceAttached = attachedStream
    self.deviceDetached = detachedStream

    // Start USB transport discovery
    await startTransportDiscovery()

    // Best-effort refresh for devices that were already connected before discovery started.
    _ = try? await refreshConnectedDevices()

    // DEMO MODE: Automatically yield a mock device
    if FeatureFlags.shared.useMockTransport {
      let profile = FeatureFlags.shared.mockProfile
      let summary: MTPDeviceSummary
      switch profile.lowercased() {
      case "s21", "galaxy":
        summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "04e8:6860@1:3"), manufacturer: "Samsung (Demo)",
          model: "Galaxy S21", vendorID: 0x04e8, productID: 0x6860, bus: 1, address: 3)
      case "oneplus", "oneplus3t":
        summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "2a70:f003@3:2"), manufacturer: "OnePlus (Demo)",
          model: "ONEPLUS A3010", vendorID: 0x2a70, productID: 0xf003, bus: 3, address: 2)
      case "iphone", "ios":
        summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "05ac:12a8@1:4"), manufacturer: "Apple (Demo)", model: "iPhone",
          vendorID: 0x05ac, productID: 0x12a8, bus: 1, address: 4)
      case "canon", "camera":
        summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "04a9:317a@1:5"), manufacturer: "Canon (Demo)", model: "EOS R5",
          vendorID: 0x04a9, productID: 0x317a, bus: 1, address: 5)
      default:
        summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "18d1:4ee1@1:2"), manufacturer: "Google (Demo)", model: "Pixel 7",
          vendorID: 0x18d1, productID: 0x4ee1, bus: 1, address: 2)
      }
      await yieldAttached(summary)
    }
  }

  private func startTransportDiscovery() async {
    if let starter = hotplugDiscoveryStarter {
      starter(
        { [weak self] dev in
          Task { [weak self] in
            await self?.yieldAttached(dev)
          }
        },
        { [weak self] id in
          Task { [weak self] in
            await self?.yieldDetached(id)
          }
        }
      )
      return
    }

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

  /// Configure the default transport used by `open(_:)`.
  public func setDefaultTransportFactory(_ factory: @escaping @Sendable () -> any MTPTransport) {
    defaultTransportFactory = factory
  }

  /// Configure the snapshot provider used to enumerate currently connected devices.
  public func setDiscoverySnapshotProvider(
    _ provider: @escaping @Sendable () async throws -> [MTPDeviceSummary]
  ) {
    discoverySnapshotProvider = provider
  }

  /// Configure the hotplug watcher starter used by discovery.
  public func setHotplugDiscoveryStarter(
    _ starter:
      @escaping @Sendable (
        @escaping (MTPDeviceSummary) -> Void,
        @escaping (MTPDeviceID) -> Void
      ) -> Void
  ) {
    hotplugDiscoveryStarter = starter
  }

  /// Refresh the connected-device snapshot from the configured provider.
  ///
  /// - Returns: Updated list of connected devices.
  public func refreshConnectedDevices() async throws -> [MTPDeviceSummary] {
    guard let provider = discoverySnapshotProvider else { return currentDevices }
    let snapshot = try await provider()
    syncConnectedDeviceSnapshot(snapshot)
    return currentDevices
  }

  /// Replace current connected-device state with a fresh snapshot.
  ///
  /// Emits attach events for newly seen devices and detach events for removed devices.
  public func syncConnectedDeviceSnapshot(_ snapshot: [MTPDeviceSummary]) {
    var uniqueSnapshot: [MTPDeviceSummary] = []
    var latestById: [MTPDeviceID: MTPDeviceSummary] = [:]
    var orderedIds: [MTPDeviceID] = []

    for device in snapshot {
      if latestById[device.id] == nil {
        orderedIds.append(device.id)
      }
      latestById[device.id] = device
    }
    uniqueSnapshot = orderedIds.compactMap { latestById[$0] }

    let previousIDs = Set(currentDevices.map(\.id))
    let nextIDs = Set(uniqueSnapshot.map(\.id))

    currentDevices = uniqueSnapshot

    for removedID in previousIDs.subtracting(nextIDs) {
      detachedContinuation?.yield(removedID)
    }

    for device in uniqueSnapshot where !previousIDs.contains(device.id) {
      attachedContinuation?.yield(device)
    }
  }

  private func yieldAttached(_ dev: MTPDeviceSummary) async {
    let isNewDevice = upsertConnectedDevice(dev)
    if isNewDevice {
      attachedContinuation?.yield(dev)
    }
  }

  private func yieldDetached(_ id: MTPDeviceID) async {
    let removed = removeConnectedDevice(id)
    if removed {
      detachedContinuation?.yield(id)
    }
  }

  /// Stop MTP device discovery and clean up resources.
  ///
  /// This method stops monitoring for device connections and releases
  /// any associated resources. Call this when your application no longer
  /// needs to discover MTP devices.
  public func stopDiscovery() async {
    attachedContinuation?.finish()
    detachedContinuation?.finish()
    attachedContinuation = nil
    detachedContinuation = nil
  }

  /// Currently connected MTP devices.
  ///
  /// This property provides a snapshot of all currently connected devices.
  /// For real-time monitoring, use the `deviceAttached` and `deviceDetached` streams.
  public var devices: [MTPDeviceSummary] { get async { currentDevices } }

  /// Stream of device attachment events.
  ///
  /// This stream yields a new `MTPDeviceSummary` whenever an MTP device
  /// is connected to the system. Use this to react to new device connections.
  ///
  /// ## Example
  /// ```swift
  /// for await deviceSummary in MTPDeviceManager.shared.deviceAttached {
  ///     print("Device connected: \(deviceSummary.manufacturer)")
  ///     // Open the device for file operations
  ///     let transport = LibUSBTransportFactory.createTransport()
  ///     let device = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport)
  /// }
  /// ```
  public private(set) var deviceAttached: AsyncStream<MTPDeviceSummary> = AsyncStream { _ in }

  /// Stream of device detachment events.
  ///
  /// This stream yields the `MTPDeviceID` of devices that have been disconnected
  /// from the system. Use this to clean up resources associated with disconnected devices.
  public private(set) var deviceDetached: AsyncStream<MTPDeviceID> = AsyncStream { _ in }

  /// Access to device streams for non-isolated contexts (like ViewModels)
  public var attachedStream: AsyncStream<MTPDeviceSummary> { deviceAttached }
  public var detachedStream: AsyncStream<MTPDeviceID> { deviceDetached }

  /// Open a currently connected device by ID.
  ///
  /// The manager first checks its in-memory connected-device registry and then
  /// falls back to refreshing via the configured discovery snapshot provider.
  ///
  /// - Parameter id: Device identifier
  /// - Returns: Configured device instance
  /// - Throws: `MTPError.transport(.noDevice)` if device is not currently connected
  ///           or `MTPError.notSupported` when no default transport is configured.
  public func open(_ id: MTPDeviceID) async throws -> MTPDevice {
    if let summary = currentDevices.first(where: { $0.id == id }) {
      return try await openDeviceWithDefaultTransport(summary: summary)
    }

    if discoverySnapshotProvider != nil {
      _ = try await refreshConnectedDevices()
      if let summary = currentDevices.first(where: { $0.id == id }) {
        return try await openDeviceWithDefaultTransport(summary: summary)
      }
    }

    throw MTPError.transport(.noDevice)
  }

  /// Open a device using its summary and transport layer.
  ///
  /// This is the primary method for connecting to an MTP device. You typically
  /// obtain the device summary from the `deviceAttached` stream and create
  /// an appropriate transport (usually `LibUSBTransportFactory.createTransport()`).
  ///
  /// - Parameters:
  ///   - summary: Device summary from attachment event
  ///   - transport: Configured transport layer for communication
  /// - Returns: Configured device instance ready for file operations
  /// - Throws: Errors related to device initialization or transport setup
  ///
  /// ## Example
  /// ```swift
  /// // From device attachment event
  /// for await deviceSummary in MTPDeviceManager.shared.deviceAttached {
  ///     let transport = LibUSBTransportFactory.createTransport()
  ///     let device = try await MTPDeviceManager.shared.openDevice(with: deviceSummary, transport: transport)
  ///
  ///     // Now you can use the device for file operations
  ///     let storages = try await device.storages()
  /// }
  /// ```
  public func openDevice(
    with summary: MTPDeviceSummary, transport: any MTPTransport, config: SwiftMTPConfig = .init()
  ) async throws -> MTPDevice {
    let journal = self.persistence.transferJournal
    return MTPDeviceActor(
      id: summary.id, summary: summary, transport: transport, config: config,
      transferJournal: journal)
  }

  /// Get the current configuration used by this device manager.
  public func getConfig() -> SwiftMTPConfig {
    config
  }

  private func upsertConnectedDevice(_ device: MTPDeviceSummary) -> Bool {
    guard let existingIndex = currentDevices.firstIndex(where: { $0.id == device.id }) else {
      currentDevices.append(device)
      return true
    }
    currentDevices[existingIndex] = device
    return false
  }

  private func removeConnectedDevice(_ id: MTPDeviceID) -> Bool {
    let before = currentDevices.count
    currentDevices.removeAll { $0.id == id }
    return before != currentDevices.count
  }

  private func openDeviceWithDefaultTransport(summary: MTPDeviceSummary) async throws -> MTPDevice {
    guard let factory = defaultTransportFactory else {
      throw MTPError.notSupported("No default transport factory configured")
    }
    return try await openDevice(with: summary, transport: factory(), config: config)
  }

  private var config: SwiftMTPConfig = .init()
}
