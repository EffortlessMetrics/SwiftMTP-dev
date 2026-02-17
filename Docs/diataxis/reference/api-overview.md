# API Overview

Quick reference for SwiftMTP's public API.

## Package Structure

```
SwiftMTPKit/
├── SwiftMTPCore/              # Core protocol
├── SwiftMTPTransportLibUSB/    # USB transport
├── SwiftMTPIndex/             # SQLite indexing
├── SwiftMTPSync/              # Mirror/sync
├── SwiftMTPQuirks/            # Device quirks
├── SwiftMTPUI/                # SwiftUI views
├── SwiftMTPStore/             # Persistence
├── SwiftMTPFileProvider/      # File Provider
└── SwiftMTPXPC/               # XPC service
```

## Core Types

### MTPDevice

Main device interface for MTP operations.

```swift
import SwiftMTPCore

let device: MTPDevice = try await manager.openDevice(summary: summary)

// List files
let stream = device.list(parent: nil, in: storageId)
for try await batch in stream {
    for item in batch {
        print(item.name)
    }
}

// Read file
let progress = try await device.read(
    handle: objectHandle,
    range: 0..<fileSize,
    to: localURL
)

// Write file
let progress = try await device.write(
    parent: folderHandle,
    name: "photo.jpg",
    size: fileSize,
    from: localURL
)
```

### MTPDeviceManager

Manages device discovery and lifecycle.

```swift
let manager = MTPDeviceManager.shared

// Start discovery
try await manager.startDiscovery()

// Listen for device events
for await event in manager.deviceEvents {
    switch event {
    case .attached(let summary):
        print("Device attached: \(summary.model)")
    case .detached(let deviceId):
        print("Device detached: \(deviceId)")
    }
}
```

### DeviceSummary

Device information from discovery.

```swift
struct DeviceSummary {
    let deviceId: String        // Unique identifier
    let manufacturer: String     // Manufacturer name
    let model: String           // Model name
    let serialNumber: String?   // Serial (if available)
    let vid: Int                // Vendor ID
    let pid: Int                // Product ID
}
```

### MTPStorage

Storage unit on device.

```swift
struct MTPStorage {
    let id: UInt32              // Storage ID
    let type: StorageType       // Fixed/Removable
    let fileSystemType: String  // FAT, NTFS, etc.
    let capacity: UInt64        // Total bytes
    let freeSpace: UInt64       // Free bytes
    let description: String     // Human-readable name
}
```

### MTPObject

File or folder on device.

```swift
struct MTPObject {
    let handle: UInt32          // Object handle
    let parent: UInt32?         // Parent folder handle
    let name: String            // Filename
    let size: UInt64?           // File size (nil for folders)
    let created: Date?          // Creation date
    let modified: Date?         // Modification date
    let mimeType: String?       // MIME type
    let isFolder: Bool          // Is folder?
}
```

## Configuration

### SwiftMTPConfig

```swift
var config = SwiftMTPConfig()

// Performance
config.transferChunkBytes = 4 * 1024 * 1024  // 4MB
config.ioTimeoutMs = 15_000                   // 15s

// Stability
config.handshakeTimeoutMs = 10_000            // 10s
config.stabilizeMs = 500                      // 500ms

// Apply
try await manager.startDiscovery(config: config)
```

## Key Protocols

### TransferJournal

For resumable transfers.

```swift
protocol TransferJournal {
    func recordTransfer(_: TransferRecord) async throws
    func pendingTransfers() async throws -> [TransferRecord]
    func markCompleted(_: TransferRecord) async throws
}
```

### Persistence

```swift
protocol MTPStore {
    func saveDeviceIdentity(_: DeviceIdentity) async throws
    func loadDeviceIdentity(vid: Int, pid: Int) async throws -> DeviceIdentity?
    func saveSnapshot(_: DeviceSnapshot) async throws
    func loadSnapshot(deviceId: String) async throws -> DeviceSnapshot?
}
```

## SwiftUI Integration

### DeviceListView

```swift
import SwiftMTPUI

struct MyView: View {
    var body: some View {
        DeviceListView()
    }
}
```

### TransferProgressView

```swift
import SwiftMTPUI

ProgressView(transferProgress)
    .progressViewStyle(.circular)
```

## Error Types

See [Error Codes](error-codes.md) for full reference.

## See Also

- [CLI Commands](cli-commands.md)
- [Architecture Overview](../explanation/architecture.md)
- [Device Quirks System](../explanation/device-quirks.md)
- [Full API Docs](../../SwiftMTP.docc/SwiftMTP.md)
