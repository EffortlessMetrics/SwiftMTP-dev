# macOS Tahoe 26 Support

@Metadata {
    @DisplayName("macOS Tahoe 26 Guide")
    @PageKind(article)
    @Available(macOS, introduced: "26.0")
}

Comprehensive guide to SwiftMTP features and optimizations for macOS Tahoe 26.

## Overview

SwiftMTP supports macOS Tahoe 26 and takes advantage of modern Swift concurrency and macOS security/accessory workflows for USB device access.

## Platform Requirements

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    // ...
)
```

### System Framework Dependencies

SwiftMTP on macOS Tahoe 26 utilizes:

- **USB-related frameworks**: IOKit, IOUSBLib
- **Concurrency**: Swift Structured Concurrency (Swift 6.1+)
- **SwiftUI**: For the built-in GUI application
- **File System**: FileManager with extended attributes

## SwiftMTP Features on macOS Tahoe 26

### USB Hotplug Handling

SwiftMTP provides responsive device discovery with connection notifications:

```swift
// Device discovery with connection monitoring
let manager = MTPDeviceManager.shared
try await manager.startDiscovery()

for await device in manager.deviceAttached {
    print("Device connected: \(device.manufacturer) \(device.model)")
}
```

### Async Transfer Progress

SwiftMTP exposes progress through Foundation's `Progress` type for integration with SwiftUI:

```swift
let progress = try await device.read(
    handle: fileHandle,
    range: nil,
    to: destinationURL
)

// SwiftUI integration
ProgressView(progress)
    .progressViewStyle(.circular)
```

### Device Power Information

Some devices support vendor-specific power delivery queries:

```swift
let info = try await device.info
if info.operationsSupported.contains(0x9101) {
    let powerInfo = try await device.getPowerDeliveryStatus()
    print("Max power: \(powerInfo.maxWatts)W")
}
```

## Performance Tuning

### Transfer Chunk Configuration

macOS Tahoe 26 supports larger transfer chunks:

| Setting | Value |
|---------|-------|
| Default Chunk Size | 4 MB |
| Maximum Chunk Size | 16 MB |
| Minimum Chunk Size | 1 MB |

```swift
var config = SwiftMTPConfig()
config.transferChunkBytes = 4 * 1024 * 1024 // 4MB chunks
```

### Concurrent Storage Enumeration

SwiftMTP supports parallel storage enumeration:

```swift
// Enumerate multiple storages concurrently
let storages = try await device.storages()
let objects = try await withThrowingTaskGroup(of: [MTPObjectInfo].self) { group in
    for storage in storages {
        group.addTask {
            try await collectStorageObjects(device: device, storage: storage)
        }
    }

    var all: [MTPObjectInfo] = []
    for try await batch in group {
        all += batch
    }
    return all
}
```

> **Note**: Concurrent enumeration with a single device connection may have driver-level limitations. Test with your specific devices.

## System Integration

### File Provider Extension

MTP devices appear in Finder via the File Provider extension:

```swift
MTPFileProviderExtension.register(
    domain: .userDomain,
    displayName: "MTP Devices"
)
```

### Spotlight Integration

Files on connected MTP devices are indexed for Spotlight search:

```swift
let query = NSMetadataQuery()
query.searchScopes = [MTPFileProviderExtension.mountPointURL]
query.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS %@", "photo")
```

### Backup Integration

SwiftMTP can mirror device contents to a folder that's included in Time Machine backups:

```swift
let mirror = MirrorOperation(device: device)
mirror.localRoot = "/Users/user/MTP-Backup"
try await mirror.run()

// The backup folder can then be included in Time Machine
```

## Migration from Older Versions

### API Changes

| Old API | New API (macOS Tahoe 26) |
|--------|-------------------------|
| `DeviceActor.open()` | `MTPDevice.openIfNeeded()` |
| `TransferSession.read()` | `MTPDevice.read(handle:range:to:)` |
| `DeviceList.refresh()` | `deviceAttached` async stream |

### Code Migration Example

```swift
// Legacy pattern
let device = try await manager.openDevice(summary: summary)
let files = try await device.enumerateFiles(storage: storageID)

// macOS Tahoe 26 pattern (recommended)
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

## Troubleshooting

### Device Not Detected

1. **Check accessory approval**: On Apple silicon Macs, approve new accessories in System Settings
2. **Verify MTP mode**: Ensure the device is in MTP/PTP mode
3. **Try a different cable**: Use a USB data cable (not charge-only)
4. **Try a different port**: Direct USB-C port recommended (avoid hubs when possible)

### Transfer Errors

Enable verbose logging for debugging:

```swift
FeatureFlags.shared.traceUSB = true

// Check device policy
let policy = await device.devicePolicy
print("Effective tuning: \(policy?.effectiveTuning)")
```

### USB Service Issues (Unofficial)

If devices don't appear after trying the above:

```bash
# Restart USB daemon (may affect keyboard/mouse)
sudo launchctl stop com.apple.usbd
sudo launchctl start com.apple.usbd
```

> **Warning**: This is an unofficial workaround and may affect USB devices. Try hardware solutions first (replug, different port/cable, reboot).

## Related Documentation

- [Getting Started](SwiftMTP.md)
- [Device Tuning Guide](DeviceTuningGuide.md)
- [Device-Specific Guides](Devices/index.md)
- [Benchmark Reports](../benchmarks.md)
