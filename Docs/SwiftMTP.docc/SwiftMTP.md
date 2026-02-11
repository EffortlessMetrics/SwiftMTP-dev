# SwiftMTP

@Metadata {
    @DisplayName("SwiftMTP")
    @Available(macOS, introduced: "26.0")
}

Swift 6-native, actor-isolated MTP backend for macOS Tahoe 26.

## macOS Tahoe 26 Support

SwiftMTP supports macOS Tahoe 26 with full leverage of modern Swift concurrency and platform features.

### Platform-Specific Features

| Feature | Description |
|---------|-------------|
| Swift 6 Concurrency | Actor-based architecture with strict isolation |
| Native USB Access | Direct IOKit/IOUSBLib integration |
| Progress Reporting | Foundation `Progress` for SwiftUI integration |
| File Provider | Native Finder integration |

See the [macOS Tahoe 26 Guide](macOS26.md) for detailed platform-specific documentation.

## Getting Started

1. Add the package via SwiftPM.
2. macOS app: (if sandboxed) add `com.apple.security.device.usb = true`.
3. Start discovery, open device, enumerate storages, mirror files.

## Installation

### Swift Package Manager

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/EffortlessMetrics/SwiftMTP.git", from: "1.0.0")
    ]
)
```

### Xcode

1. File > Add Package Dependencies
2. Enter: `https://github.com/EffortlessMetrics/SwiftMTP.git`
3. Select "Add to Target"

## Quick Start

### Basic Device Discovery and Transfer

```swift
import SwiftMTPCore

@main
struct MTPDemo {
    static func main() async throws {
        // Start device discovery
        let manager = MTPDeviceManager.shared
        try await manager.startDiscovery()
        
        // Monitor device connections
        for await summary in manager.deviceAttached {
            print("Device connected: \(summary.manufacturer) \(summary.model)")
            
            // Open device
            let device = try await manager.openDevice(summary: summary)
            
            // List storages
            let storages = try await device.storages()
            for storage in storages {
                print("Storage: \(storage.description)")
                
                // Enumerate files
                let fileStream = device.list(parent: nil, in: storage.id)
                for try await files in fileStream {
                    for file in files {
                        print("  \(file.name)")
                    }
                }
            }
            
            // Download a file
            let progress = try await device.read(
                handle: 0x00000001,
                range: nil,
                to: URL(fileURLWithPath: "/tmp/downloaded.jpg")
            )
            
            print("Download complete: \(progress.completedUnitCount) bytes")
        }
    }
}
```

### File Upload

```swift
// Upload a file to the device
let progress = try await device.write(
    parent: nil,           // Root directory
    name: "photo.jpg",     // Filename
    size: 1024 * 1024,     // File size
    from: URL(fileURLWithPath: "/local/photo.jpg")
)

print("Upload progress: \(progress.fractionCompleted * 100)%")
```

### Mirror Entire Device

```swift
import SwiftMTPSync

let mirror = MirrorOperation(device: device)
mirror.localRoot = "/Users/user/MTP-Backup"
mirror.includeFilters = ["*.jpg", "*.png", "*.mp4"]
mirror.excludeFilters = ["*.tmp", "*.log"]

try await mirror.run()
print("Mirror complete!")
```

## Architecture

### Core Components

```
SwiftMTP/
├── SwiftMTPCore/           # Protocol implementation
├── SwiftMTPTransportLibUSB/ # USB transport
├── SwiftMTPIndex/          # SQLite indexing
├── SwiftMTPSync/           # Sync & mirror
├── SwiftMTPQuirks/         # Device tuning
└── SwiftMTPUI/             # SwiftUI views
```

### Key Design Patterns

1. **Actor-based concurrency**: All device operations go through `MTPDeviceActor`
2. **Protocol-oriented**: `MTPDevice` protocol allows mock implementations
3. **Async/await**: All I/O operations use Swift structured concurrency
4. **Transfer journaling**: Automatic resume via `TransferJournal`
5. **Device quirks**: Static and learned profiles for device-specific tuning

## Transfers & Resume

- Reads resume automatically on devices that support `GetPartialObject64`
- Writes are single-pass unless `SendPartialObject` is available
- Progress reporting via `Progress` object

```swift
let progress = try await device.read(handle: handle, range: nil, to: destination)

// SwiftUI integration
ProgressView(progress)
    .progressViewStyle(.circular)
    .frame(width: 200)
```

## Performance

- Chunk auto-tuning per device (up to 16MB on macOS Tahoe 26)
- Signposts for enumeration and transfers; use Instruments
- SQLite-based indexing for fast directory traversal

### Benchmarking

```bash
# Run transfer benchmarks
swift run swiftmtp bench --size 100M

# Generate benchmark report
swift run swiftmtp bench --size 1G --output benchmark.csv
```

## Configuration

```swift
var config = SwiftMTPConfig()

// Performance tuning
config.transferChunkBytes = 4 * 1024 * 1024  // 4MB chunks
config.ioTimeoutMs = 15_000                    // 15 second I/O timeout

// Stability tuning
config.handshakeTimeoutMs = 10_000
config.stabilizeMs = 500                      // Post-open delay

// Apply to manager
try await manager.startDiscovery(config: config)
```

## Error Handling

```swift
do {
    let device = try await manager.openDevice(summary: summary)
} catch MTPDeviceError.busy {
    print("Device is busy, retrying...")
} catch MTPDeviceError.timeout {
    print("Operation timed out")
} catch MTPDeviceError.disconnected {
    print("Device was disconnected")
} catch {
    print("Unknown error: \(error)")
}
```

## CLI Tool

SwiftMTP includes a command-line tool for device management:

```bash
# Discover devices
swift run swiftmtp probe

# List device contents
swift run swiftmtp ls

# Download files
swift run swiftmtp pull /DCIM/photo.jpg

# Upload files
swift run swiftmtp push photo.jpg

# Create device snapshot
swift run swiftmtp snapshot

# Mirror device content
swift run swiftmtp mirror --output ~/MTP-Backup

# Benchmark transfers
swift run swiftmtp bench --size 100M

# Monitor device events
swift run swiftmtp events

# Show device quirks
swift run swiftmtp quirks --explain
```

## Device Quirks

SwiftMTP maintains a device quirks database for optimized performance:

```bash
# See active quirks for connected device
swift run swiftmtp quirks --explain
```

See the [Device Tuning Guide](DeviceTuningGuide.md) for adding new devices.

## GUI Application

SwiftMTP includes a SwiftUI-based GUI application:

```bash
# Launch the GUI
swift run SwiftMTPApp
```

Features:
- Device discovery and management
- File browser with preview
- Drag-and-drop transfers
- Progress monitoring
- Device-specific tuning

## Testing

```bash
# Run all tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Run Thread Sanitizer
swift test -Xswiftc -sanitize=thread
```

## Requirements

- macOS 26.0+ / iOS 26.0+
- Swift 6.0+
- Xcode 16.0+

## License

AGPL-3.0-only. See [LICENSE](../LICENSE) for details.

## Related Documentation

- [macOS Tahoe 26 Guide](macOS26.md) - Platform-specific features and optimizations
- [Device Tuning Guide](DeviceTuningGuide.md) - Device-specific tuning
- [Device Guides](Devices/index.md) - Individual device documentation
- [Benchmarks](../benchmarks.md) - Performance benchmarks
