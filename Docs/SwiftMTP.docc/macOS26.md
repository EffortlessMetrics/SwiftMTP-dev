# macOS Tahoe 26 Support

@Metadata {
    @DisplayName("macOS Tahoe 26 Guide")
    @PageKind(article)
    @Available(macOS, introduced: "26.0")
}

Comprehensive guide to SwiftMTP features, optimizations, and best practices for macOS Tahoe 26.

## Overview

SwiftMTP is built for macOS Tahoe 26, leveraging modern Swift 6 concurrency, native USB frameworks, and platform security features to provide a robust MTP device communication layer.

### Key Capabilities

- **Actor-based architecture**: Thread-safe device operations via `MTPDeviceActor`
- **Native USB access**: Direct IOKit/IOUSBLib integration
- **Async/await transfers**: Foundation `Progress` for SwiftUI integration
- **SQLite indexing**: Fast device content enumeration
- **File Provider integration**: Native Finder sidebar support

## Platform Requirements

### Swift Package Manager Configuration

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
        .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    ],
    dependencies: [
        // Add SwiftMTP dependencies here
    ],
    targets: [
        // Add targets here
    ]
)
```

### System Framework Dependencies

| Framework | Purpose |
|-----------|---------|
| IOKit | USB device enumeration and control |
| IOUSBLib | USB bulk/interrupt transfer operations |
| Foundation | `Progress`, `URL`, `FileManager` |
| SwiftUI | GUI application components |
| UniformTypeIdentifiers | File type identification |

### Minimum Hardware

- Apple Silicon Mac (M1 or later) recommended
- USB 3.0+ port for optimal transfer speeds
- Compatible MTP/PTP device

## Swift 6 Concurrency Model

### Actor Isolation

All device operations are isolated through actors for thread safety:

```swift
public actor MTPDeviceActor {
    private var connection: USBConnection?
    private var isOpen: Bool = false
    
    public func open(session: USBSession) async throws {
        guard !isOpen else { return }
        try await session.open()
        isOpen = true
    }
    
    public func read(handle: MTPObjectHandle) async throws -> Data {
        guard isOpen else {
            throw MTPDeviceError.notOpen
        }
        return try await performRead(handle: handle)
    }
}
```

### Sendable Conformances

All public types conform to `Sendable` for safe cross-actor transfer:

```swift
public struct MTPDeviceSummary: Sendable {
    public let id: MTPDeviceID
    public let manufacturer: String
    public let model: String
    public let vendorID: UInt16?
    public let productID: UInt16?
}

public struct MTPStorageInfo: Sendable {
    public let id: MTPStorageID
    public let description: String
    public let capacityBytes: UInt64
    public let freeBytes: UInt64
}
```

### Task Groups

Concurrent operations on multi-storage devices:

```swift
// Enumerate all storages in parallel
let storages = try await device.storages()
let allObjects = try await withThrowingTaskGroup(of: [MTPObjectInfo].self) { group in
    for storage in storages {
        group.addTask {
            try await enumerateStorage(device: device, storage: storage)
        }
    }
    
    var results: [MTPObjectInfo] = []
    for try await batch in group {
        results.append(contentsOf: batch)
    }
    return results
}
```

## USB Device Discovery

### Hotplug Handling

SwiftMTP monitors USB connections and automatically discovers MTP devices:

```swift
let manager = MTPDeviceManager.shared

// Start discovery with custom configuration
var config = SwiftMTPConfig()
config.transferChunkBytes = 4 * 1024 * 1024
config.handshakeTimeoutMs = 10_000

try await manager.startDiscovery(config: config)

// Monitor for device connections
for await summary in manager.deviceAttached {
    print("Device attached: \(summary.manufacturer) \(summary.model)")
    print("  VID: 0x\(String(format: "%04x", summary.vendorID ?? 0))")
    print("  PID: 0x\(String(format: "%04x", summary.productID ?? 0))")
    print("  Serial: \(summary.usbSerial ?? "N/A")")
}

// Monitor for device disconnections
for await deviceID in manager.deviceDetached {
    print("Device detached: \(deviceID.raw)")
}
```

### Device Information Retrieval

```swift
// Get detailed device information
let info = try await device.info
print("Manufacturer: \(info.manufacturer)")
print("Model: \(info.model)")
print("Version: \(info.version)")
print("Serial: \(info.serialNumber ?? "N/A")")
print("Operations supported: \(info.operationsSupported.sorted())")
print("Events supported: \(info.eventsSupported.sorted())")
```

## File Transfers

### Reading Files (Download)

```swift
import Foundation

let destination = URL(fileURLWithPath: "/Users/user/Downloads/photo.jpg")

let progress = try await device.read(
    handle: 0x00010001,  // Object handle from enumeration
    range: nil,          // nil = entire file
    to: destination
)

// Monitor progress
for await update in progress.publisher.values {
    print("Progress: \(update.fractionCompleted * 100)%")
    print("Completed: \(update.completedUnitCount) / \(update.totalUnitCount)")
}
```

### Partial Downloads (Resume Support)

```swift
// Resume from offset (if device supports GetPartialObject64)
let fileSize = getFileSize(handle: handle)
let startOffset = fileSize / 2  // Resume from middle

let progress = try await device.read(
    handle: handle,
    range: startOffset..<fileSize,
    to: destinationURL
)
```

### Writing Files (Upload)

```swift
let source = URL(fileURLWithPath: "/Users/user/Documents/document.pdf")

let progress = try await device.write(
    parent: 0x00000000,  // Root storage
    name: "document.pdf",
    size: 1024 * 500,    // 500 KB
    from: source
)

print("Upload complete: \(progress.completedUnitCount) bytes")
```

### Progress Reporting in SwiftUI

```swift
import SwiftUI
import Combine

struct DeviceTransferView: View {
    let device: MTPDevice
    let sourceURL: URL
    let destinationName: String
    
    @State private var progress: Double = 0
    @State private var isComplete = false
    @State private var error: Error?
    
    var body: some View {
        VStack {
            if isComplete {
                Label("Transfer Complete", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            } else {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
            }
        }
        .task {
            do {
                let progress = try await device.write(
                    parent: nil,
                    name: destinationName,
                    size: getFileSize(at: sourceURL),
                    from: sourceURL
                )
                
                for await update in progress.publisher.values {
                    await MainActor.run {
                        self.progress = update.fractionCompleted
                    }
                }
                await MainActor.run {
                    self.isComplete = true
                }
            } catch {
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
}
```

## Performance Tuning

### Chunk Size Configuration

```swift
var config = SwiftMTPConfig()

// Transfer chunk size (default: 4MB on macOS Tahoe 26)
config.transferChunkBytes = 4 * 1024 * 1024

// Timeouts (in milliseconds)
config.handshakeTimeoutMs = 10_000   // Initial connection
config.ioTimeoutMs = 30_000          // Individual operations
config.inactivityTimeoutMs = 15_000  // Idle connection
config.overallDeadlineMs = 300_000   // Total operation cap (5 min)

// Stability
config.stabilizeMs = 500             // Post-open delay for slow devices
```

### Device-Specific Tuning

```swift
// Query effective tuning for connected device
let tuning = await device.effectiveTuning
print("Max chunk: \(tuning.maxChunkBytes / 1024 / 1024) MB")
print("I/O timeout: \(tuning.ioTimeoutMs) ms")
print("Handshake: \(tuning.handshakeTimeoutMs) ms")

// Apply tuning to configuration
var config = SwiftMTPConfig()
config.apply(tuning)
```

### Benchmarking

```bash
# Run CLI benchmarks
swift run swiftmtp bench --size 100M --output benchmark.csv

# Mirror test
swift run swiftmtp mirror --source /MTP/ --output ~/MTP-Backup --log mirror.log
```

## System Integration

### File Provider Extension

MTP devices appear in Finder's sidebar:

```swift
// Registration happens automatically in the app bundle
// Devices appear under "Locations" in Finder
```

### Spotlight Integration

Files are indexed for Spotlight search:

```swift
// Search for photos on connected device
let query = NSMetadataQuery()
query.searchScopes = [
    "/Volumes/MTP Device/DCIM/",
    "/Volumes/MTP Device/DCIM/100APPLE/"
]
query.predicate = NSPredicate(
    format: "kMDItemDisplayName CONTAINS[cd] %@",
    "IMG"
)
query.sortDescriptors = [
    NSSortDescriptor(key: "kMDItemContentCreationDate", ascending: false)
]

// Execute search
query.startQuery()
```

### Backup Integration

Mirror device contents for backup purposes:

```swift
import SwiftMTPSync

let mirror = MirrorOperation(device: device)
mirror.localRoot = "/Users/user/Backups/MTP-Device"
mirror.includeFilters = [
    "*.jpg", "*.jpeg", "*.png", "*.heic",
    "*.mp4", "*.mov", "*.mkv",
    "*.pdf", "*.doc", "*.docx"
]
mirror.excludeFilters = [
    "*.tmp", "*.log", "*.thumb",
    "@eaDir", ".Spotlight-V100"
]
mirror.deleteOrphans = true
mirror.createHardLinks = false  // Use copies for safety

try await mirror.run()

print("Mirrored \(mirror.stats.filesCopied) files")
print("Total size: \(mirror.stats.totalBytesCopied / 1024 / 1024) MB")
```

## Error Handling

### Common Error Types

```swift
do {
    let device = try await manager.openDevice(summary: summary)
} catch MTPDeviceError.notSupported {
    print("Device does not support required MTP operations")
} catch MTPDeviceError.busy {
    print("Device is busy; retry after brief delay")
} catch MTPDeviceError.timeout {
    print("Operation timed out; device may be slow or unresponsive")
} catch MTPDeviceError.disconnected {
    print("Device was disconnected during operation")
} catch MTPDeviceError.permissionDenied {
    print("USB access not granted; check System Settings")
} catch {
    print("Unknown error: \(error)")
}
```

### Recovery Patterns

```swift
// Retry with exponential backoff
func connectWithRetry(summary: MTPDeviceSummary, maxRetries: Int = 3) async throws -> MTPDevice {
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            return try await manager.openDevice(summary: summary)
        } catch MTPDeviceError.busy, MTPDeviceError.timeout {
            lastError = error
            let delay = UInt64(attempt * attempt) * 1_000_000_000  // Exponential backoff
            try await Task.sleep(nanoseconds: delay)
            continue
        }
    }
    
    throw lastError!
}
```

## Security Considerations

### USB Access Entitlement

For sandboxed apps:

```xml
<!-- YourApp.entitlements -->
<key>com.apple.security.device.usb</key>
<true/>
```

### Accessory Approval

On Apple silicon Macs, users must approve new USB accessories:

1. Connect the MTP device
2. System Settings → Privacy & Security
3. Click "Allow" next to the accessory prompt

### Privacy Best Practices

- Only request necessary USB device access
- Handle device data securely
- Don't persist sensitive device information without encryption
- Clear cached data when device disconnects

## Troubleshooting

### Device Not Detected

1. **Check USB cable**: Use a data-capable USB cable (not charge-only)
2. **Try different port**: Direct USB-C port preferred
3. **Check device mode**: Ensure MTP/PTP mode is enabled
4. **Approve accessory**: Check System Settings → Privacy & Security
5. **Restart USB daemon** (last resort):

```bash
# Unofficial - may affect keyboard/mouse
sudo launchctl stop com.apple.usbd
sudo launchctl start com.apple.usbd
```

### Transfer Failures

```swift
// Enable debug logging
FeatureFlags.shared.traceUSB = true

// Check device policy
let policy = await device.devicePolicy
if let tuning = policy?.effectiveTuning {
    print("Active tuning: \(tuning)")
}

// Verify device capabilities
let caps = await device.probedCapabilities
print("Supports partial reads: \(caps["partialRead64"] ?? false)")
print("Supports partial writes: \(caps["partialWrite"] ?? false)")
```

### Performance Issues

1. Use USB 3.0+ port directly (avoid hubs)
2. Reduce chunk size for unstable connections:

```swift
var config = SwiftMTPConfig()
config.transferChunkBytes = 1 * 1024 * 1024  // 1MB chunks
```

3. Increase timeouts for slow devices:

```swift
config.ioTimeoutMs = 60_000  // 60 seconds
```

## Migration Guide

### From macOS 15 / iOS 18

```swift
// OLD (macOS 15 pattern)
let session = try await manager.connect(to: summary)
let files = try await session.enumerate(storage: storageID)
let data = try await session.read(handle: fileHandle)

// NEW (macOS Tahoe 26 pattern)
let manager = MTPDeviceManager.shared
try await manager.startDiscovery()

for await summary in manager.deviceAttached {
    let device = try await manager.openDevice(summary: summary)
    let stream = device.list(parent: nil, in: storageID)
    
    for try await batch in stream {
        for file in batch {
            print(file.name)
        }
    }
}
```

### Key Changes

| Aspect | Before | After |
|--------|--------|-------|
| Discovery | `connect(to:)` | `startDiscovery()` + `deviceAttached` stream |
| Enumeration | `enumerate(storage:)` | `list(parent:in:)` async stream |
| Progress | Custom callback | Foundation `Progress` |
| Error types | `Error` | `MTPDeviceError` enum |

## Related Documentation

- [Getting Started](SwiftMTP.md) - Main SwiftMTP documentation
- [Device Tuning Guide](DeviceTuningGuide.md) - Device-specific quirks
- [Device Guides](Devices/index.md) - Individual device documentation
- [Benchmarks](../benchmarks.md) - Performance reports
- [CLI Reference](https://github.com/EffortlessMetrics/SwiftMTP#cli-tool) - Command-line tool docs
