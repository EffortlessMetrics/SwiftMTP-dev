# Public Types Reference

Comprehensive reference for all public types in SwiftMTP, including detailed descriptions, properties, and usage examples.

## Core Device Types

### MTPDevice

Main interface for MTP device communication.

```swift
public class MTPDevice: AsyncSequence
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique device identifier |
| `info` | `DeviceInfo` | Cached device information |
| `isConnected` | `Bool` | Connection state |
| `isSessionOpen` | `Bool` | MTP session state |

#### Methods

| Method | Description |
|--------|-------------|
| `connect()` | Establish USB connection |
| `disconnect()` | Close USB connection |
| `openSession()` | Open MTP session |
| `closeSession()` | Close MTP session |
| `list(parent:)` | List directory contents |
| `read(handle:)` | Read file from device |
| `write(parent:name:)` | Write file to device |
| `delete(handle:)` | Delete object |
| `createFolder(name:parent:)` | Create folder |

#### Usage Example

```swift
// Connect to first available device
let device = try await MTPDevice.discoverFirst()
try await device.connect()
try await device.openSession()

// List root directory
for try await item in device.list(parent: nil, in: 0) {
    print(item.name)
}

// Read file
let data = try await device.read(handle: fileHandle, range: 0..<fileSize)

// Write file
try await device.write(
    parent: folderHandle,
    name: "photo.jpg",
    size: fileSize,
    from: localURL
)

// Cleanup
try await device.closeSession()
try await device.disconnect()
```

---

### MTPDeviceManager

Manages device discovery and lifecycle.

```swift
public class MTPDeviceManager: @unchecked Sendable
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `shared` | `MTPDeviceManager` | Singleton instance |
| `deviceEvents` | `AsyncStream<DeviceEvent>` | Device connection events |
| `discoveredDevices` | `[DeviceSummary]` | Currently known devices |

#### Methods

| Method | Description |
|--------|-------------|
| `startDiscovery()` | Begin device scanning |
| `stopDiscovery()` | Stop device scanning |
| `openDevice(summary:)` | Open connection to device |
| `disposeDevice(id:)` | Release device resources |

#### Device Events

```swift
public enum DeviceEvent: Sendable {
    case attached(DeviceSummary)    // New device connected
    case detached(String)           // Device disconnected
    case moved(DeviceSummary)      // Device moved between ports
}
```

#### Usage Example

```swift
let manager = MTPDeviceManager.shared

// Start device discovery
try await manager.startDiscovery()

// Listen for device events
for await event in manager.deviceEvents {
    switch event {
    case .attached(let summary):
        print("Device attached: \(summary.model)")
        
    case .detached(let deviceId):
        print("Device detached: \(deviceId)")
        
    case .moved(let summary):
        print("Device moved: \(summary.model)")
    }
}
```

---

### DeviceSummary

Lightweight device information from discovery.

```swift
public struct DeviceSummary: Sendable, Hashable
```

| Property | Type | Description |
|----------|------|-------------|
| `deviceId` | `String` | Unique identifier |
| `manufacturer` | `String` | Manufacturer name |
| `model` | `String` | Model name |
| `serialNumber` | `String?` | Device serial number |
| `vid` | `Int` | USB Vendor ID |
| `pid` | `Int` | USB Product ID |
| `usbLocation` | `Int` | USB port location |

---

### DeviceInfo

Detailed device information after session opens.

```swift
public struct DeviceInfo: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `deviceId` | `String` | Unique identifier |
| `manufacturer` | `String` | Manufacturer |
| `model` | `String` | Model name |
| `serialNumber` | `String?` | Device serial |
| `firmwareVersion` | `String?` | Firmware version |
| `vendorExtension` | `String` | MTP extensions supported |
| `operations` | `MTPOperations` | Supported operations |
| `capabilities` | `MTPCapabilities` | Device capabilities |
| `storages` | `[MTPStorage]` | Available storages |

---

## Storage Types

### MTPStorage

Represents a storage unit on the device.

```swift
public struct MTPStorage: Sendable, Identifiable
```

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UInt32` | Storage ID |
| `type` | `StorageType` | Fixed/Removable |
| `fileSystemType` | `String` | File system type |
| `capacity` | `UInt64` | Total bytes |
| `freeSpace` | `UInt64` | Available bytes |
| `description` | `String` | Display name |

#### StorageType

```swift
public enum StorageType: UInt8, Sendable {
    case fixed = 0x00
    case removable = 0x01
    case optical = 0x02
    case unknown = 0x03
}
```

---

### MTPObject

Represents a file or folder on the device.

```swift
public struct MTPObject: Sendable, Identifiable
```

| Property | Type | Description |
|----------|------|-------------|
| `handle` | `UInt32` | Unique object handle |
| `parent` | `UInt32?` | Parent folder handle |
| `storageId` | `UInt32` | Storage containing object |
| `name` | `String` | Object name |
| `size` | `UInt64?` | File size (nil for folders) |
| `created` | `Date?` | Creation timestamp |
| `modified` | `Date?` | Modification timestamp |
| `mimeType` | `String?` | MIME type |
| `isFolder` | `Bool` | Is directory |
| `isProtected` | `Bool` | DRM/protected |

---

## Transfer Types

### TransferOptions

Configuration for file transfers.

```swift
public struct TransferOptions: Sendable
```

| Property | Default | Description |
|----------|---------|-------------|
| `maxConcurrentTransfers` | `3` | Parallel transfer count |
| `transferChunkSize` | `65536` | Bytes per chunk |
| `bufferCount` | `16` | I/O buffer count |
| `retryAttempts` | `3` | Retry count |
| `retryDelay` | `1.0` | Seconds between retries |
| `verifyChecksum` | `true` | Verify integrity |
| `preserveTimestamps` | `true` | Keep file dates |
| `useSendObject` | `true` | Use SendObject operation |

---

### TransferProgress

Progress information for transfers.

```swift
public struct TransferProgress: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `totalBytes` | `UInt64` | Total bytes to transfer |
| `transferredBytes` | `UInt64` | Bytes completed |
| `currentFile` | `String` | Current file name |
| `bytesPerSecond` | `Double` | Transfer speed |
| `estimatedTimeRemaining` | `TimeInterval?` | ETA |

#### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `percentage` | `Double` | Progress 0-100 |
| `isComplete` | `Bool` | Transfer finished |
| `formattedSpeed` | `String` | Human-readable speed |

---

### TransferResult

Result of a completed transfer.

```swift
public struct TransferResult: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `sourcePath` | `String` | Original path |
| `destinationPath` | `String` | Target path |
| `bytesTransferred` | `UInt64` | Bytes transferred |
| `duration` | `TimeInterval` | Transfer time |
| `checksum` | `String?` | Verification checksum |

---

### TransferItem

Defines a single transfer operation.

```swift
public struct TransferItem: Sendable
```

| Property | Type | Description |
|----------|------|-------------|
| `sourcePath` | `String` | Source file path |
| `destinationPath` | `String` | Destination path |
| `expectedSize` | `UInt64?` | Expected file size |
| `priority` | `Int` | Transfer priority |
| `metadata` | `[String: String] metadata |

---

##?` | Custom Configuration Types

### SwiftMTPConfig

Global configuration for SwiftMTP.

```swift
public struct SwiftMTPConfig: Sendable
```

#### Performance Settings

| Property | Default | Description |
|----------|---------|-------------|
| `transferChunkBytes` | `4194304` | 4MB chunk size |
| `ioTimeoutMs` | `15000` | 15s I/O timeout |
| `bufferCount` | `16` | Buffer pool size |

#### Stability Settings

| Property | Default | Description |
|----------|---------|-------------|
| `handshakeTimeoutMs` | `10000` | 10s handshake timeout |
| `stabilizeMs` | `500` | 500ms stabilization delay |
| `maxRetries` | `3` | Max retry attempts |

#### Discovery Settings

| Property | Default | Description |
|----------|---------|-------------|
| `autoConnect` | `true` | Auto-connect to devices |
| `discoveryIntervalMs` | `1000` | 1s scan interval |

---

### DeviceOptions

Per-device configuration overrides.

```swift
public struct DeviceOptions: Sendable
```

| Property | Description |
|----------|-------------|
| `quirkOverride` | Override device quirks |
| `transferOptions` | Custom transfer settings |
| `cacheEnabled` | Enable caching |
| `loggingEnabled` | Enable verbose logging |

---

## Error Types

### MTPError

Main error type for MTP operations.

```swift
public enum MTPError: Error, Sendable
```

#### Connection Errors

| Case | Description |
|------|-------------|
| `.deviceNotFound` | No device found |
| `.connectionFailed(String)` | USB connection failed |
| `.sessionFailed(String)` | MTP session failed |

#### Operation Errors

| Case | Description |
|------|-------------|
| `.notConnected` | Device not connected |
| `.sessionNotOpen` | Session not open |
| `.operationNotSupported` | Operation not supported |
| `.objectNotFound` | Object handle invalid |
| `.storeNotAvailable` | Storage unavailable |
| `.storeReadOnly` | Storage is read-only |

#### Transfer Errors

| Case | Description |
|------|-------------|
| `.transferFailed(String)` | Transfer failed |
| `.checksumMismatch` | Verification failed |
| `.partialTransferFailed` | Resume failed |

---

### DeviceError

Device-specific errors.

```swift
public enum DeviceError: Error, Sendable {
    case unsupportedDevice(vid: Int, pid: Int)
    case deviceBusy
    case timeout
    case permissionDenied
    case trustPromptRequired
}
```

---

## Protocol Types

### TransferJournal

Protocol for resumable transfers.

```swift
public protocol TransferJournal: Sendable {
    func recordTransfer(_: TransferRecord) async throws
    func pendingTransfers() async throws -> [TransferRecord]
    func markCompleted(_: TransferRecord) async throws
    func markFailed(_: TransferRecord, error: Error) async throws
}
```

### TransferRecord

Records transfer state for resume.

```swift
public struct TransferRecord: Sendable, Codable {
    public let id: UUID
    public let sourcePath: String
    public let destinationPath: String
    public let totalBytes: UInt64
    public var transferredBytes: UInt64
    public let startTime: Date
    public var lastResumeTime: Date?
    public var status: TransferStatus
}
```

### MTPStore

Protocol for data persistence.

```swift
public protocol MTPStore: Sendable {
    func saveDeviceIdentity(_: DeviceIdentity) async throws
    func loadDeviceIdentity(vid: Int, pid: Int) async throws -> DeviceIdentity?
    func saveSnapshot(_: DeviceSnapshot) async throws
    func loadSnapshot(deviceId: String) async throws -> DeviceSnapshot?
    func saveQuirks(_: DeviceQuirks) async throws
    func loadQuirks(deviceId: String) async throws -> DeviceQuirks?
}
```

---

## Event Types

### MTPEvent

Asynchronous events from device.

```swift
public enum MTPEvent: Sendable {
    case objectAdded(handle: UInt32, parent: UInt32)
    case objectRemoved(handle: UInt32)
    case objectMoved(handle: UInt32, newParent: UInt32)
    case storageAdded(id: UInt32)
    case storageRemoved(id: UInt32)
    case deviceReset
    case deviceCapabilityChanged
}
```

---

## CLI Types

### DeviceFilter

Filter for CLI device selection.

```swift
public struct DeviceFilter: Sendable {
    public var vendorId: Int?
    public var productId: Int?
    public var serialNumber: String?
    public var manufacturer: String?
    public var model: String?
}
```

### JSONOutput

CLI JSON output format.

```swift
public struct JSONOutput: Codable {
    public let success: Bool
    public let data: AnyCodable?
    public let error: String?
    public let timestamp: Date
}
```

---

## Related Documentation

- [API Overview](api-overview.md) - Quick API reference
- [Error Codes](error-codes.md) - Error code reference
- [Configuration](configuration.md) - Configuration options
- [Events](events.md) - Event handling

---

## Summary

This reference covers:

- ✅ Core device types (MTPDevice, MTPDeviceManager)
- ✅ Storage types (MTPStorage, MTPObject)
- ✅ Transfer types (TransferOptions, TransferProgress)
- ✅ Configuration types (SwiftMTPConfig, DeviceOptions)
- ✅ Error types (MTPError, DeviceError)
- ✅ Protocol types (TransferJournal, MTPStore)
- ✅ Event types (MTPEvent)
