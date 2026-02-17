# Architecture Overview

This document explains SwiftMTP's architecture and design decisions.

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SwiftMTPApp                               │
│                    (SwiftUI Application)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│  │  SwiftMTPUI │    │  SwiftMTPCore │    │  SwiftMTPSync │     │
│  │  (Views)    │◄──►│  (Protocol)   │◄──►│  (Mirror)     │     │
│  └──────────────┘    └──────────────┘    └──────────────┘     │
│                             │                                    │
│                             ▼                                    │
│                    ┌──────────────┐                            │
│                    │  Transport    │                            │
│                    │  (USB/IOKit)  │                            │
│                    └──────────────┘                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### SwiftMTPCore

The heart of SwiftMTP - implements MTP protocol:

- **MTPDevice** - Main device interface
- **MTPDeviceActor** - Actor-isolated device state
- **PTPCodec** - Protocol encoding/decoding
- **PTPLayer** - PTP/MTP transport

### SwiftMTPTransportLibUSB

USB transport layer:

- Device enumeration
- Interface claiming
- Bulk/Control transfer
- Event handling

### SwiftMTPIndex

SQLite-based indexing:

- Fast directory traversal
- Object metadata caching
- Change tracking

### SwiftMTPSync

Mirror and sync engine:

- Diff computation
- Transfer scheduling
- Conflict resolution

### SwiftMTPQuirks

Device-specific tuning:

- Static quirk database
- Learned profiles
- Adaptive tuning

### SwiftMTPUI

SwiftUI views:

- Device list view
- File browser
- Transfer progress
- Settings panels

## Actor Architecture

SwiftMTP uses Swift 6 actors for concurrency safety:

```swift
actor DeviceActor {
    private var sessionOpen: Bool = false
    private var currentHandles: [UInt32: MTPObject] = [:]
    
    func openSession() async throws {
        // Actor-isolated - safe concurrent access
    }
    
    func listObjects(parent: UInt32?) async throws -> [MTPObject] {
        // All device state is protected
    }
}
```

### Why Actors?

1. **Data race prevention** - Compiler-enforced safety
2. **Simple reasoning** - State changes are serial
3. **Performance** - No locks needed
4. **Swift 6** - Native support

## Transfer System

### Progress Tracking

```swift
let progress = try await device.read(handle: handle, to: url)

// Progress integrates with SwiftUI
ProgressView(progress)
    .progressViewStyle(.circular)

// And Foundation
progress.addObserver(self, forKeyPath: "fractionCompleted")
```

### Resume Support

- **Reads**: Automatic if device supports `GetPartialObject64`
- **Writes**: Single-pass (some devices support partial)
- **Mirror**: Checksum-based incremental

### Transfer Journal

```swift
let journal: any TransferJournal = FileTransferJournal()

// Record progress
await journal.recordTransfer(transfer)

// Resume pending
let pending = await journal.pendingTransfers()
```

## File Provider Integration

### Architecture

```
Finder ──────► File Provider ──────► XPC Service ──────► MTP Device
               Extension             (Host App)
```

### Components

1. **SwiftMTPFileProvider** - Extension
   - Enumerates device storage
   - Handles on-demand downloads
   - Reports metadata

2. **SwiftMTPXPC** - Communication
   - Protocol definitions
   - Service implementation

3. **Host App** - Bridge
   - Manages MTP device
   - Handles file I/O

### Cache-First Design

```
1. Check local SQLite index
2. If cached → return metadata
3. If not cached → fire XPC request
4. Return when content ready
```

## Device Quirks

### Quirk Categories

1. **Timeouts**
   - `handshakeTimeoutMs` - Session open
   - `ioTimeoutMs` - Transfers
   - `stabilizeMs` - Post-open delay

2. **Transfer Limits**
   - `maxChunkBytes` - Maximum chunk size

3. **Behaviors**
   - `resetOnOpen` - Reset before session
   - `hooks` - Custom delays

### Quirk Resolution

```swift
let resolver = QuirkResolver()
let quirks = try await resolver.resolve(vid: vid, pid: pid)
```

## Error Handling

### Error Categories

1. **Protocol Errors** - From device (MTP/PTP)
2. **Transport Errors** - USB issues
3. **Device Errors** - Device state
4. **System Errors** - I/O, permissions

### Recovery Strategies

| Error | Strategy |
|-------|----------|
| Timeout | Retry with longer timeout |
| Busy | Wait and retry |
| Disconnected | Reconnect and resume |
| Permission | Prompt user |

## Design Principles

1. **Privacy-first** - Read-only by default
2. **Actor isolation** - Safe concurrency
3. **Protocol purity** - Standard MTP compliance
4. **Device quirks** - Handle variations gracefully
5. **Progressive enhancement** - Core first, features on top

## Further Reading

- [Understanding MTP Protocol](mtp-protocol.md)
- [Device Quirks System](device-quirks.md)
- [File Provider Tech Preview](../../FileProvider-TechPreview.md)
