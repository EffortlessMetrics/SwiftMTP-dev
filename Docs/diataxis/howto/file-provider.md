# How to Use File Provider Integration

This guide explains how to integrate SwiftMTP with macOS/iOS File Provider for native Finder/Files app integration.

## Overview

File Provider integration allows MTP devices to appear as native volumes in Finder and the Files app, providing seamless access to device contents without a separate application.

## What You'll Learn

- Enable File Provider integration
- Configure domains for connected devices
- Browse devices in Finder
- Understand current limitations

## Prerequisites

- macOS 12.0+ or iOS 15.0+
- SwiftMTP with File Provider extension built
- App Group entitlements configured

## Step 1: Understanding the Architecture

The File Provider system consists of several components:

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│   Finder/Files  │────▶│ File Provider    │────▶│   XPC       │
│     App         │     │   Extension      │     │   Service   │
└─────────────────┘     └──────────────────┘     └─────────────┘
                                │                        │
                                ▼                        ▼
                        ┌──────────────────┐     ┌─────────────┐
                        │   SQLite Index   │     │  MTP Device │
                        │   (Metadata)     │     │             │
                        └──────────────────┘     └─────────────┘
```

### Cache-First Architecture

- **Metadata** comes from local SQLite index (fast)
- **Content** is fetched on-demand via XPC

This ensures responsive browsing even for large devices.

## Step 2: Host App Setup

### Basic Setup

```swift
import SwiftMTPXPC
import SwiftMTPUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the XPC service
        let coordinator = DeviceLifecycleCoordinator()
        coordinator.start()
    }
}
```

### Manual Setup

```swift
import SwiftMTPCore

// Or manually via MTPDeviceManager
let deviceManager = MTPDeviceManager.shared
deviceManager.startXPCService()
```

### Device Service Registration

When a device connects, register it with the File Provider:

```swift
import SwiftMTPCore

let service = MTPDeviceService()

// When device connects
func deviceConnected(_ device: MTPDevice) {
    service.registerDevice(
        deviceId: device.id,
        name: device.modelName
    )
}
```

## Step 3: File Provider Extension

The extension automatically handles:

- Enumerating device storages as folders
- Listing files and folders
- Downloading content on-demand
- Providing metadata for Finder

### Extension Configuration

In your extension's Info.plist:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionFileProviderDocumentGroup</key>
    <string>group.com.yourcompany.swiftmtp</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.fileprovider.nonui</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).MTPFileProviderExtension</string>
</dict>
```

## Step 4: Using the Integration

### Finding Your Device in Finder

1. Open Finder
2. Look in the sidebar under "Locations" or "Network"
3. Your MTP device should appear as a mounted volume

### Browsing Device Contents

```
📱 DeviceName
├── 📁 Internal Storage
│   ├── 📁 DCIM
│   │   └── 📁 Camera
│   ├── 📁 Download
│   └── 📁 Pictures
└── 📁 SD Card (if present)
```

### Accessing Files

Files are downloaded on-demand when you:
- Double-click to open
- Preview in Quick Look
- Copy to another location

### Performance

- **First browse**: May be slow as metadata is indexed
- **Subsequent access**: Fast (from cache)
- **Large files**: Downloaded transparently

## Step 5: Configuration Options

### Environment Variables

```bash
# Enable verbose File Provider logging
export SWIFTMTP_FILEPROVIDER_LOG=debug

# Cache size limit (MB)
export SWIFTMTP_FILEPROVIDER_CACHE_SIZE=500

# Enable background indexing
export SWIFTMTP_FILEPROVIDER_BACKGROUND_INDEX=true
```

### Programmatic Configuration

```swift
import SwiftMTPFileProvider

let config = FileProviderConfiguration(
    maxCacheSize: 500 * 1024 * 1024,
    backgroundIndexEnabled: true,
    prefetchEnabled: true
)

let manager = FileProviderManager(configuration: config)
```

## Step 6: Current Limitations

The tech preview has these limitations:

| Feature | Status | Notes |
|---------|--------|-------|
| Read access | ✅ Working | Browse and open files |
| Write access | 🔄 Limited | Upload coming soon |
| Change notifications | 🔄 Limited | Basic support only |
| Background sync | 🔄 Future | On roadmap |
| Conflict resolution | 🔄 Future | On roadmap |

## Step 7: Troubleshooting

### Device Not Appearing in Finder

1. **Verify XPC service is running**:
   ```bash
   # Check if service is active
   ps aux | grep swiftmtp
   ```

2. **Check File Provider domains**:
   ```bash
   pluginkit -m | grep -i swiftmtp
   ```

3. **Enable debug logging**:
   ```swift
   // In your app
   let logger = Logger(subsystem: "com.effortlessmetrics.swiftmtp", category: "FileProvider")
   logger.debug("Debug message")
   ```

### Files Not Opening

1. Check XPC connection is active
2. Verify temp directory permissions
3. Ensure device is still connected

### Slow Performance

1. First-time: Wait for indexing to complete
2. Check network (for cached content)
3. Try closing and reopening Finder

## Advanced: Manual Domain Management

### Adding a Domain

```swift
import SwiftMTPFileProvider

let domain = FileProviderDomain(
    identifier: "com.mtp.device.1234",
    displayName: "My Phone"
)

try await FileProviderManager.default.addDomain(domain)
```

### Removing a Domain

```swift
try await FileProviderManager.default.removeDomain(domain)
```

### Enumerating Domains

```swift
let domains = try await FileProviderManager.default.domains
for domain in domains {
    print(domain.displayName)
}
```

## Security

The File Provider integration is designed with security in mind:

- All access goes through XPC service in host app
- Temporary files in app group container
- No direct device access from extension
- Sandbox-compliant
- Input validation on XPC messages

## Related Documentation

- [File Provider Tech Preview](../../FileProvider-TechPreview.md) - Full technical details
- [Connect Device](connect-device.md) - Device connection
- [Transfer Files](transfer-files.md) - File operations

## Summary

You now know how to:

1. ✅ Set up host app for File Provider
2. ✅ Configure File Provider extension
3. ✅ Browse devices in Finder/Files app
4. ✅ Understand the cache-first architecture
5. ✅ Configure options and troubleshoot issues