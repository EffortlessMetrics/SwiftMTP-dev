# Migration Guide: v1.x to v2.x

This guide helps you migrate from SwiftMTP v1.x to v2.x. Version 2.0.0 includes breaking changes focused on modern Swift and platform support.

## Table of Contents

1. [Breaking Changes Summary](#breaking-changes-summary)
2. [Platform Requirements](#platform-requirements)
3. [API Replacements](#api-replacements)
4. [Configuration Changes](#configuration-changes)
5. [Common Migration Issues](#common-migration-issues)
6. [Swift 6 Migration Checklist](#swift-6-migration-checklist)

---

## Breaking Changes Summary

| Category | v1.x | v2.x |
|----------|------|------|
| **Minimum macOS** | 15.0 | 26.0 |
| **Minimum iOS** | 18.0 | 26.0 |
| **Swift Version** | 5.x | 6.x (strict concurrency) |
| **USB Framework** | libusb direct | IOUSBHost (primary) |
| **Concurrency Model** | Actors (opt-in) | Full actor isolation |
| **Entitlements** | Legacy USB | Simplified modern model |

---

## Platform Requirements

### Before (v1.x)
- macOS 15.0+ / iOS 18.0+
- Swift 5.x toolchain
- Xcode 15+

### After (v2.x)
- **macOS 26.0+** (macOS Tahoe 26)
- **iOS 26.0+**
- Swift 6.2+ toolchain
- Xcode 16.0+

> **Note**: Linux support was available in v1.x but is not included in v2.x due to IOUSBHost dependency. For Linux users, v1.x remains available.

---

## API Replacements

### Device Initialization

**v1.x:**
```swift
import SwiftMTPCore

let device = try await MTPDevice.open(vid: 0x2717, pid: 0xff40)
```

**v2.x:**
```swift
import SwiftMTPCore
import SwiftMTPTransportLibUSB

let transport = LibUSBTransport()
let device = try await MTPDevice.open(transport: transport, vid: 0x2717, pid: 0xff40)
```

### Transport Layer

**v1.x:**
```swift
// Direct libusb access
let connection = try MTPDevice.connect(...)
```

**v2.x:**
```swift
// Explicit transport selection
let transport = LibUSBTransport()
let device = try await MTPDevice.open(transport: transport, ...)
```

### Async/Await Pattern

**v1.x:**
```swift
// Completion handler pattern supported
device.getObjectHandles { result in
    // handle result
}
```

**v2.x:**
```swift
// Async/await only (modern Swift 6)
let handles = try await device.getObjectHandles()
```

---

## Configuration Changes

### Package.swift Dependencies

**v1.x:**
```swift
dependencies: [
    .package(url: "...", from: "1.0.0")
]
```

**v2.x:**
```swift
dependencies: [
    .package(url: "...", from: "2.0.0")
]
```

### Entitlements

**v1.x** required explicit USB entitlements:
```xml
<key>com.apple.security.device.usb</key>
<true/>
```

**v2.x** uses simplified entitlements (no USB-specific entries needed for modern macOS).

### Environment Variables

| Variable | v1.x | v2.x |
|----------|------|------|
| `SWIFTMTP_DEMO_MODE` | Supported | Supported |
| `SWIFTMTP_MOCK_PROFILE` | Supported | Supported |
| `SWIFTMTP_MAX_CHUNK_BYTES` | - | Supported |
| `SWIFTMTP_IO_TIMEOUT_MS` | - | Supported |

---

## Common Migration Issues

### Issue 1: "Cannot find 'LibUSBTransport' in scope"

**Cause**: Missing `SwiftMTPTransportLibUSB` dependency

**Solution:**
```swift
// Add to Package.swift dependencies
.product(name: "SwiftMTPTransportLibUSB", package: "SwiftMTPKit")
```

### Issue 2: Actor isolation errors with Swift 6

**Cause**: Strict concurrency checking in Swift 6

**Solution:**
- Mark all `@Sendable` conformances explicitly
- Use `nonisolated` for immutable state
- Review [Swift 6 Migration Guide](https://docs.swift.org/swift-book/documentation/the-swift-programming-language-sixth-edition/)

### Issue 3: IOUSBHost framework not found

**Cause**: Running on older macOS

**Solution:**
- Verify macOS 26.0+: `sw_vers -productVersion`
- Or stay on v1.x for older macOS support

### Issue 4: Device not detected after upgrade

**Cause**: USB stack changes between versions

**Solution:**
1. Unplug and reconnect device
2. Ensure device is in **File Transfer (MTP)** mode
3. Unlock device screen
4. Accept any trust prompts
5. Run: `swift run swiftmtp probe`

### Issue 5: Transfer timeouts increase

**Cause**: New adaptive timeout algorithm in v2.x

**Solution:**
```bash
# Increase timeout manually
export SWIFTMTP_IO_TIMEOUT_MS=30000
swift run swiftmtp push <file>
```

---

## Swift 6 Migration Checklist

- [ ] Update `Package.swift` platforms to `.macOS(.v26)` and `.iOS(.v26)`
- [ ] Update Swift toolchain to 6.2+
- [ ] Add `SwiftMTPTransportLibUSB` if using USB transport
- [ ] Replace completion handlers with async/await
- [ ] Review `@Sendable` conformance on error types
- [ ] Test with strict concurrency: `swift build -Xfrontend -strict-concurrency=complete`
- [ ] Update entitlements file (simplified in v2.x)
- [ ] Verify device detection: `swift run swiftmtp probe`

---

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/EffortlessMetrics/SwiftMTP/issues)
- **Discussions**: [GitHub Discussions](https://github.com/EffortlessMetrics/SwiftMTP/discussions)
- **Troubleshooting**: [Docs/Troubleshooting.md](Troubleshooting.md)
- **Error Codes**: [Docs/ErrorCodes.md](ErrorCodes.md)

---

## Version Compatibility Matrix

| SwiftMTP | macOS | iOS | Swift |
|----------|-------|-----|-------|
| 1.x | 15.0+ | 18.0+ | 5.x |
| 2.x | 26.0+ | 26.0+ | 6.x |

For macOS 15-25 or iOS 18-25, continue using v1.x releases.
