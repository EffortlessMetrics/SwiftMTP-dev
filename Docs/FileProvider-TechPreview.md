# File Provider Tech Preview

This document describes the tech preview implementation of Finder integration for SwiftMTP using macOS/iOS File Provider framework.

## Overview

The File Provider integration allows MTP devices to appear as native volumes in Finder/Files app, enabling users to browse and access device contents directly from the desktop or mobile device.

## Architecture

### Components

1. **SwiftMTPXPC** - XPC communication library
   - Protocol definitions for File Provider ↔ Host communication
   - `MTPXPCServiceImpl` - XPC service implementation running in host app
   - `MTPXPCListener` - XPC listener for the host app
   - Handles communication between File Provider extension and MTP devices
   - Manages file downloads and metadata queries
   - Provides secure access to device contents

2. **SwiftMTPFileProvider** - File Provider extension
   - Implements `NSFileProviderReplicatedExtension`
   - Provides virtual filesystem view of MTP devices
   - Handles on-demand content hydration
   - Components:
     - `MTPFileProviderExtension` - Main extension entry point
     - `MTPFileProviderItem` - File/Folder item representation
     - `DomainEnumerator` - Enumerates device contents
     - `FileProviderManager` - Manages domain lifecycle
     - `ChangeSignaler` - Signals content changes
     - `MTPDeviceService` - Device service coordination

3. **Host App Integration**
   - Starts XPC listener on launch via `MTPDeviceManager.startXPCService()`
   - Manages File Provider domains via `MTPDeviceService`
   - Handles device connection/disconnection via `DeviceLifecycleCoordinator`

### Data Flow

```
Finder/Files App → File Provider Extension → XPC Service → MTP Device
     ↑                     ↓                    ↓
     └── Content ← Temp File ←────── Download

Metadata (cache-first): File Provider Extension → Local SQLite Index
Content (on-demand): File Provider Extension → XPC → Host App → MTP Device
```

### Cache-First Architecture

The implementation uses a **cache-first architecture** for optimal performance:
- **Metadata reads** come from the local SQLite live index (no XPC needed)
- **Content materialization** goes through XPC to the host app, then to the MTP device
- If the index is empty for a folder, a background crawl request is fired via XPC

This architecture avoids semaphore deadlocks and provides fast metadata access while still allowing on-demand content fetching.

## Usage

### Host App Setup

```swift
import SwiftMTPXPC
import SwiftMTPUI

// In AppDelegate or SceneDelegate initialization
let coordinator = DeviceLifecycleCoordinator()
coordinator.start()

// Or manually via MTPDeviceManager
let deviceManager = MTPDeviceManager.shared
deviceManager.startXPCService()

// When device connects - use MTPDeviceService
let service = MTPDeviceService()
service.registerDevice(deviceId: deviceId)
```

### File Provider Extension

The extension automatically:
- Enumerates device storages as top-level folders
- Lists files and folders within storages
- Downloads content on-demand when accessed
- Provides metadata for Finder display
- Uses local SQLite index for fast metadata access
- Fires background crawls via XPC when needed

## Current Status

### ✅ Implemented
- XPC service protocol and implementation
- Basic File Provider domain enumeration
- On-demand content hydration
- Temp file management with cleanup
- Cache-first architecture (metadata from local index)
- Background crawl triggering via XPC
- Device lifecycle coordination

### 🚧 Tech Preview Limitations
- Read-only access (no upload support)
- Simplified device tracking
- Basic error handling
- No incremental change notifications
- Limited content type detection

### 🔄 Future Enhancements
- Bidirectional sync (upload support)
- Change notifications for device modifications
- Improved content type detection
- Background sync capabilities
- Conflict resolution

## Testing

### Manual Testing Steps

1. Build and run the host app with XPC service enabled
2. Connect an MTP device
3. Add File Provider domain for the device
4. Open Finder and locate the device volume
5. Browse folders and open files
6. Verify content downloads work correctly

### Debug Commands

```bash
# Check File Provider domains
pluginkit -m | grep SwiftMTP

# Monitor XPC connections
log stream --predicate 'subsystem == "com.effortlessmetrics.swiftmtp"'
```

## Security Considerations

- All file access goes through XPC service in host app
- Temporary files stored in app group container
- No direct device access from extension
- Sandbox-compliant implementation
- Input validation on all XPC messages

## Configuration

### App Group
Set up app group entitlement for shared temp file access:
```
group.com.effortlessmetrics.swiftmtp
```

### File Provider Entitlements
Extension needs File Provider entitlements:
- `com.apple.fileprovider.nonui` (for background operation)
- App group for temp file sharing

### XPC Service Name
The XPC service uses the name defined in `MTPXPCServiceName`:
```
com.effortlessmetrics.swiftmtp.xpc
```

## Troubleshooting

### Common Issues

1. **Device not appearing in Finder**
   - Verify XPC service is running
   - Check File Provider domain was added successfully
   - Ensure device is connected and accessible

2. **Files not downloading**
   - Check XPC connection is established
   - Verify temp directory permissions
   - Look for device access errors

3. **Permission denied errors**
   - Ensure proper entitlements are set
   - Check app group configuration
   - Verify USB device access permissions

### Debug Logging

Enable verbose logging:
```swift
import os.log

let logger = Logger(subsystem: "com.effortlessmetrics.swiftmtp", category: "FileProvider")
// Use logger.debug(), logger.info(), etc.
```

## Next Steps

For production use, consider:
- Implementing full bidirectional sync
- Adding conflict resolution UI
- Supporting incremental updates
- Enhancing error recovery
- Adding telemetry and monitoring
