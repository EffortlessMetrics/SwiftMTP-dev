# Platform Integration

This tutorial covers integrating SwiftMTP with platform-specific features on Apple devices.

## What You'll Learn

- Integrate with iOS File Provider
- Use macOS-specific features
- Build Catalyst apps with SwiftMTP
- Handle platform permissions and entitlements

## Prerequisites

- Completed [Getting Started](getting-started.md)
- Completed [Your First Transfer](first-transfer.md)
- Xcode 15.0+ for some features

## Platform Overview

| Platform | Features | Notes |
|----------|----------|-------|
| macOS | Full IOKit, File Provider, CLI | Primary platform |
| iOS | File Provider only | Limited USB access |
| Catalyst | Full IOKit, File Provider | macOS-like experience |

## Step 1: macOS Integration

### Using File Provider

The File Provider extension allows Finder integration:

```swift
import SwiftMTPCore
import FileProvider

class MTPFileProvider: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    
    func item(for identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        // Map MTP paths to File Provider items
        let mtpPath = identifier.rawValue
        let entry = try await device.getEntry(path: mtpPath)
        
        return MTPFileProviderItem(entry: entry)
    }
}
```

### Finder Integration

```swift
import SwiftMTPCore

class FinderSyncExtension: FIFinderSync {
    override func beginObservingDirectory(at url: URL) {
        // Called when Finder views the MTP folder
    }
    
    override func requestBadgeIdentifier(for url: URL) {
        // Display custom badges in Finder
    }
}
```

### Entitlements for macOS

```xml
<!-- SwiftMTP.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.usb</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
</dict>
</plist>
```

### IOKit Integration

```swift
import IOKit
import IOKit.usb

class USBDeviceMonitor {
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    
    func startMonitoring() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        
        IOServiceAddMatchingNotification(
            notificationPort,
            kIOFirstMatchNotification,
            matchingDict,
            deviceAddedCallback,
            nil,
            &addedIterator
        )
        
        // Process existing devices
        processDevices(iterator: addedIterator)
    }
}
```

## Step 2: iOS Integration

### File Provider on iOS

iOS apps use File Provider for document access:

```swift
import FileProvider

class MTPFileProviderExtension: NSFileProviderExtension {
    
    override func item(for identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        // Implement File Provider protocol
        let path = identifier.documentStorageURL.path
        let entry = try await mtpSession.getEntry(path: path)
        
        return MTPProviderItem(entry: entry)
    }
    
    override func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, 
                                 version requestedVersion: NSFileProviderItemVersion?) async throws -> URL {
        // Download file contents
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        try await mtpSession.download(
            path: itemIdentifier.rawValue,
            to: tempURL
        )
        
        return tempURL
    }
}
```

### iOS Entitlements

```xml
<!-- iOS entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.example.SwiftMTP</string>
    </array>
    <key>com.apple.developer.fileprovider.testing</key>
    <true/>
</dict>
</plist>
```

### Info.plist Configuration

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionFileProviderDocumentGroup</key>
    <string>group.com.example.SwiftMTP</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.fileprovider-nonui</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).MTPFileProviderExtension</string>
</dict>
```

## Step 3: Catalyst Integration

Catalyst apps run on iPad and Mac with full USB access:

### Enabling Catalyst

1. Open Xcode project
2. Select Target → Signing & Capabilities
3. Check "Supports Mac Catalyst"
4. Add USB entitlement

### Catalyst-Specific Code

```swift
import SwiftMTPCore

#if targetEnvironment(macCatalyst)
// Full IOKit access available
class CatalystDeviceManager {
    func setupUSBMonitoring() {
        // Use IOKit for device detection
    }
}
#elseif os(iOS)
// Limited to File Provider
class iOSDeviceManager {
    func setupFileProvider() {
        // Use File Provider extension
    }
}
#endif
```

### Adaptive UI

```swift
struct ContentView: View {
    var body: some View {
        #if targetEnvironment(macCatalyst)
        // Use menu bar and toolbar
        NavigationSplitView {
            DeviceSidebar()
        } detail: {
            FileBrowser()
        }
        #else
        // Touch-friendly iPad interface
        NavigationStack {
            List(devices) { device in
                NavigationLink(destination: DeviceView(device: device)) {
                    DeviceRow(device: device)
                }
            }
        }
        #endif
    }
}
```

## Step 4: Shared Code Patterns

### Platform-Abstraction Layer

```swift
import SwiftMTPCore

protocol DeviceConnector {
    func connect() async throws -> MTPDevice
    func disconnect() async
    var isConnected: Bool { get }
}

#if os(macOS)
class MacDeviceConnector: DeviceConnector {
    // Full IOKit implementation
    func connect() async throws -> MTPDevice {
        try await withCheckedThrowingContinuation { continuation in
            // IOKit device discovery
        }
    }
}
#else
class iOSDeviceConnector: DeviceConnector {
    // File Provider implementation
    func connect() async throws -> MTPDevice {
        throw DeviceError.platformNotSupported("Full MTP not supported on iOS")
    }
}
#endif
```

### Shared Transfer Logic

```swift
import SwiftMTPCore

class TransferManager: ObservableObject {
    @Published var transfers: [Transfer] = []
    
    // Works on all platforms
    func enqueue(transfer: TransferTask) {
        transfers.append(Transfer(state: .pending, task: transfer))
        Task {
            await processQueue()
        }
    }
    
    private func processQueue() async {
        for index in transfers.indices {
            guard transfers[index].state == .pending else { continue }
            
            transfers[index].state = .inProgress
            
            do {
                try await executeTransfer(transfers[index].task)
                transfers[index].state = .completed
            } catch {
                transfers[index].state = .failed
                transfers[index].error = error
            }
        }
    }
}
```

## Step 5: App Groups for Data Sharing

Share data between app and extensions:

```swift
// Shared UserDefaults
let defaults = UserDefaults(suiteName: "group.com.example.SwiftMTP")
defaults?.set(true, forKey: "AutoConnect")

// Shared container
let containerURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.SwiftMTP")

// Shared database
let dbPath = containerURL?.appendingPathComponent("cache.sqlite")
```

## Step 6: Platform-Specific UX

### macOS Toolbar

```swift
import SwiftUI

struct MainWindow: View {
    @StateObject var deviceManager: DeviceManager
    
    var body: some View {
        NavigationSplitView {
            Sidebar(devices: deviceManager.devices)
        } detail: {
            DetailView(selectedDevice: deviceManager.selected)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: connectDevice) {
                    Label("Connect", systemImage: "cable.connector")
                }
                
                Button(action: refreshDevices) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
```

### iOS Navigation

```swift
import SwiftUI

struct iOSDeviceList: View {
    @StateObject var deviceManager: DeviceManager
    
    var body: some View {
        List(deviceManager.devices) { device in
            NavigationLink(destination: DeviceDetail(device: device)) {
                DeviceRow(device: device)
            }
        }
        .navigationTitle("MTP Devices")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}
```

## Platform Considerations

### USB Access

| Platform | USB Access | Notes |
|----------|------------|-------|
| macOS | Full | IOKit, direct USB |
| Catalyst | Full | Same as macOS |
| iOS | Limited | File Provider only |

### Performance

| Platform | Max Transfer Speed | Notes |
|----------|-------------------|-------|
| macOS | USB 3.0 max | Direct access |
| Catalyst | USB 3.0 max | Direct access |
| iOS | Variable | Through File Provider |

## Next Steps

- 📋 [File Provider Integration](../howto/file-provider.md) - Detailed File Provider setup
- 📋 [Performance Tuning](../howto/performance-tuning.md) - Platform-specific optimizations
- 📋 [macOS 26 Features](../SwiftMTP.docc/macOS26.md) - Latest macOS features
- 📋 [SwiftMTP App](SwiftMTP.docc/SwiftMTP.md) - Full app reference

## Summary

In this tutorial, you learned how to:

1. ✅ Integrate SwiftMTP with macOS File Provider
2. ✅ Set up iOS File Provider extension
3. ✅ Build Catalyst apps with SwiftMTP
4. ✅ Implement platform-abstraction layers
5. ✅ Use App Groups for data sharing
6. ✅ Create platform-appropriate user interfaces
