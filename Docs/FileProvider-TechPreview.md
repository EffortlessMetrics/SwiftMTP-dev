# File Provider Tech Preview

This document describes the tech preview implementation of Finder integration for SwiftMTP using macOS File Provider framework.

## Overview

The File Provider integration allows MTP devices to appear as native volumes in Finder, enabling users to browse and access device contents directly from the desktop.

## Architecture

### Components

1. **SwiftMTPXPC** - XPC service running in the host app
   - Handles communication between File Provider extension and MTP devices
   - Manages file downloads and metadata queries
   - Provides secure access to device contents

2. **SwiftMTPFileProvider** - File Provider extension
   - Implements `NSFileProviderReplicatedExtension`
   - Provides virtual filesystem view of MTP devices
   - Handles on-demand content hydration

3. **Host App Integration**
   - Starts XPC listener on launch
   - Manages File Provider domains
   - Handles device connection/disconnection

### Data Flow

```
Finder → File Provider Extension → XPC Service → MTP Device
    ↑              ↓                    ↓
    └── Content ← Temp File ←────── Download
```

## Usage

### Host App Setup

```swift
import SwiftMTPXPC

// In AppDelegate or similar
let deviceManager = MTPDeviceManager.shared
deviceManager.startXPCService()

// When device connects
let domain = MTPFileProviderDomain.createDomain(for: deviceId)
NSFileProviderManager.add(domain) { error in
    // Handle error
}
```

### File Provider Extension

The extension automatically:
- Enumerates device storages as top-level folders
- Lists files and folders within storages
- Downloads content on-demand when accessed
- Provides metadata for Finder display

## Current Status

### ✅ Implemented
- XPC service protocol and implementation
- Basic File Provider domain enumeration
- On-demand content hydration
- Temp file management with cleanup

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
log stream --predicate 'subsystem == "com.example.SwiftMTP"'
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
group.com.example.SwiftMTP
```

### File Provider Entitlements
Extension needs File Provider entitlements:
- `com.apple.fileprovider.nonui` (for background operation)
- App group for temp file sharing

### XPC Service Name
The XPC service uses the name defined in `MTPXPCServiceName`:
```
com.example.SwiftMTP.MTPXPCService
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

let logger = Logger(subsystem: "com.example.SwiftMTP", category: "FileProvider")
// Use logger.debug(), logger.info(), etc.
```

## Next Steps

For production use, consider:
- Implementing full bidirectional sync
- Adding conflict resolution UI
- Supporting incremental updates
- Enhancing error recovery
- Adding telemetry and monitoring
