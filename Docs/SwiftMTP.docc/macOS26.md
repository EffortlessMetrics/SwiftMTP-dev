# macOS Tahoe 26 Guide

@Metadata {
    @DisplayName("macOS Tahoe 26")
    @PageKind(article)
    @Available(macOS, introduced: "26.0")
}

SwiftMTP on macOS Tahoe 26: native platform integration without compatibility ballast.

## Toolchain Baseline

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMTP",
    platforms: [
        .macOS(.v26),
        .iOS(.v18)
    ],
    products: [
        .library(name: "SwiftMTPCore", targets: ["SwiftMTPCore"]),
        .executable(name: "swiftmtp", targets: ["swiftmtp-cli"]),
    ],
    targets: [
        // Your targets here
    ]
)
```

**Requirements:**
- Xcode 16.0+
- Swift 6.0+
- SwiftPM 6.2+

## What SwiftMTP Does on Tahoe 26

SwiftMTP is built natively for Tahoe-era platforms. This section describes SwiftMTP's implementation choices and measured behavior—not platform guarantees.

### Hotplug Latency

SwiftMTP's USB hotplug pipeline typically sees attach events in ~50–100ms on our test matrix (USB 3.0 ports, M1/M2 Macs). See [benchmarks](../benchmarks.md) for details.

### Transfer Progress

SwiftMTP exposes transfers as Foundation `Progress` for SwiftUI integration:

```swift
let progress = try await device.read(handle: fileHandle, to: destinationURL)

ProgressView(progress)
    .progressViewStyle(.circular)
```

### Device Power Telemetry

Some devices expose vendor-specific power telemetry. SwiftMTP surfaces it when available:

```swift
let info = try await device.info
if info.operationsSupported.contains(0x9101) {
    let powerInfo = try await device.getPowerDeliveryStatus()
    print("Max power: \(powerInfo.maxWatts)W")
}
```

## Platform Integration

### USB Access

**Entitlement** (required for sandboxed apps):
```xml
<key>com.apple.security.device.usb</key>
<true/>
```

Configure in Xcode: App Sandbox → Hardware → USB.

**Framework surface:**
- `IOUSBHost` — primary framework for custom USB device access
- `IOUSBLib` — legacy compatibility layer

### Accessory Approval

On Apple silicon Macs, users must approve new USB accessories:

**System Settings → Privacy & Security → "Allow accessories to connect"**

### File Provider Integration

MTP devices appear in Finder via NSFileProviderManager:

```swift
import FileProvider

let domain = NSFileProviderDomain(
    identifier: NSFileProviderDomainIdentifier("com.yourorg.swiftmtp.mtp"),
    displayName: "MTP Devices"
)

NSFileProviderManager.add(domain) { error in
    if let error {
        print("Failed to add domain: \(error)")
    }
}
```

### Spotlight Search

Spotlight routes searches into your provider when you implement `NSFileProviderSearching`:

```swift
extension MTPFileProviderExtension: NSFileProviderSearching {
    func search(for itemIdentifier: NSFileProviderItemIdentifier,
                queryString: String?,
                request: NSFileProviderRequest,
                completionHandler: @escaping (Error?) -> Void) -> Progress {
        // Implement search logic
        return Progress()
    }
}
```

## Performance Tuning

SwiftMTP's default chunk sizes are based on throughput testing across our device matrix.

### Configuration

```swift
var config = SwiftMTPConfig()

// Transfer chunk size (default: 4 MiB)
config.transferChunkBytes = 4 * 1024 * 1024

// Timeouts (milliseconds)
config.handshakeTimeoutMs = 10_000
config.ioTimeoutMs = 30_000
```

### Concurrent Storage Enumeration

```swift
let storages = try await device.storages()

let objects: [MTPObjectInfo] = try await withThrowingTaskGroup(of: [MTPObjectInfo].self) { group in
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

## Device Mirroring

SwiftMTP can mirror device content to a local directory. The mirrored folder can then be included in Time Machine backups like any other filesystem path:

```swift
import SwiftMTPSync

let mirror = MirrorOperation(device: device)
mirror.localRoot = "/Users/user/Backups/MTP-Device"
mirror.includeFilters = ["*.jpg", "*.png", "*.mp4"]
mirror.excludeFilters = ["*.tmp", "*.thumb"]

try await mirror.run()

print("Mirrored \(mirror.stats.filesCopied) files")
```

## Troubleshooting

### Device Not Detected

1. **Check cable** — Use a USB data cable (not charge-only)
2. **Try a different port** — Direct USB-C preferred (avoid hubs)
3. **Verify MTP mode** — Ensure device is in MTP/PTP mode
4. **Approve accessory** — System Settings → Privacy & Security → "Allow accessories to connect"
5. **Check entitlement** — Verify `com.apple.security.device.usb` in entitlements
6. **Reboot** — Restart the Mac (most reliable for stuck USB state)

### Transfer Failures

```swift
// Enable debug logging
FeatureFlags.shared.traceUSB = true

// Check device policy
let policy = await device.devicePolicy
if let tuning = policy?.effectiveTuning {
    print("Active tuning: \(tuning)")
}
```

## Related Documentation

- [Getting Started](SwiftMTP.md)
- [Device Tuning Guide](DeviceTuningGuide.md)
- [Device Guides](Devices/index.md)
- [Benchmarks](../benchmarks.md)
