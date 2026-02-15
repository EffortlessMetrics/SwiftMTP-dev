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
mirror.excludeFilters = ["*.tmp", ".thumb"]

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

## Known Issues

### Google Pixel 7 (18d1:4ee1) - macOS 26.2+ Compatibility

**Status:** Known Limitation

**Symptom:** Device claim succeeds but all bulk transfers timeout (`write rc=-7 sent=0/12`).

**Root Cause:** The Pixel 7 is not exposing MTP/PTP interfaces to macOS. The device appears in ioreg as `IOUSBHostDevice` with **no child IOUSBInterface** entries. This indicates the Pixel's USB stack is not properly exposing the Still Image class (0x06) interface.

**Diagnostic Steps:**

```bash
# Check ioreg for interface children
ioreg -p IOUSB -l -w0 | rg -A30 -B5 "Pixel 7"

# Verify device is in MTP mode
adb shell getprop sys.usb.config
# Expected: "mtp" or "mtp,adb"

# Check USB state
adb shell getprop sys.usb.state
# Expected: "mtp" or "mtp"

# Verify USB debugging
adb devices
# Should show "device" (not "unauthorized")
```

**Required User Actions:**

1. **Enable Developer Options on Pixel 7:**
   - Settings → About Phone → Build Number (tap 7 times)

2. **Enable USB Debugging:**
   - Settings → System → Developer options → USB debugging

3. **Trust the Computer:**
   - Unlock Pixel 7 and check for "Trust this computer?" prompt
   - Tap "Trust" and verify

4. **Verify MTP Mode:**
   - Settings → Connected devices → USB → Select "File transfer (MTP)"

**Alternative Workarounds:**

1. **Use PTP Mode:** Try Picture Transfer Protocol instead of MTP:
   ```bash
   adb usb ptp
   ```

2. **Use Different Port:** Connect directly to Mac USB-C (avoid hubs)

3. **Use Different Cable:** Ensure it's a data-capable USB-C cable

4. **Restart Pixel 7:** Sometimes the USB stack needs a fresh start

**Technical Notes:**

- Samsung devices (04e8:6860) work correctly with vendor-specific interface (class=0xff)
- Xiaomi Mi Note 2 (2717:ff10) works correctly with vendor-specific interface (class=0xff)
- Pixel 7's Still Image class (0x06) interface is not being exposed by the device
- This is a Pixel 7 / macOS USB stack interaction issue, not a SwiftMTP bug

**Related Issues:**
- [GitHub Issue: Pixel 7 macOS compatibility](https://github.com/example/SwiftMTP/issues/XXX)
- Android Open Source Project: USB accessory mode documentation

## Related Documentation

- [Getting Started](SwiftMTP.md)
- [Device Tuning Guide](DeviceTuningGuide.md)
- [Device Guides](Devices/index.md)
- [Benchmarks](../benchmarks.md)
