# Understanding MTP Protocol

This document explains the MTP (Media Transfer Protocol) and how SwiftMTP implements it.

## What is MTP?

MTP (Media Transfer Protocol) is a protocol for communicating with MTP devices - typically media players, phones, and cameras. It evolved from PTP (Picture Transfer Protocol).

### Key Characteristics

- **Host-initiated**: The computer initiates all operations
- **Object-oriented**: Files are accessed by handles, not paths
- **Session-based**: Operations occur within an open session
- **No file system exposure**: Device's file system is not exposed

## MTP Operations

### Session Operations

1. **OpenSession** - Start communication
2. **CloseSession** - End communication

### Device Operations

1. **GetDeviceInfo** - Query device capabilities
2. **GetStorageIDs** - List storage units
3. **GetStorageInfo** - Get storage details

### Object Operations

1. **GetObjectHandles** - List files/folders
2. **GetObjectInfo** - Get file metadata
3. **GetObject** - Download file
4. **SendObjectInfo** - Prepare for upload
5. **SendObject** - Upload file
6. **DeleteObject** - Delete file
7. **MoveObject** - Move file
8. **CopyObject** - Copy file

### Partial Transfer Operations

1. **GetPartialObject** - Resume download
2. **GetPartialObject64** - Resume large downloads
3. **SendPartialObject** - Resume upload

## MTP Data Types

### Handles

MTP uses numeric handles instead of paths:

```
Folder: handle = 0x00010001
File:   handle = 0x00010002
```

### Object Format

```swift
struct MTPObject {
    let handle: UInt32      // Unique identifier
    let parent: UInt32?     // Parent folder handle
    let name: String        // Filename
    let size: UInt64?       // File size (files only)
    // ... other properties
}
```

### Storage

MTP devices can have multiple storage units:

- Internal storage
- SD card
- USB storage

## How SwiftMTP Implements MTP

### PTP/MTP Layer

SwiftMTP implements PTP (the base protocol) and MTP extensions:

```
┌─────────────────────────────────────────┐
│              MTPDevice                  │
├─────────────────────────────────────────┤
│  - Session management                  │
│  - Object operations                    │
│  - Event handling                       │
├─────────────────────────────────────────┤
│              PTPLayer                   │
├─────────────────────────────────────────┤
│  - Command/Response packets             │
│  - Event handling                       │
│  - Data phase handling                  │
├─────────────────────────────────────────┤
│           Transport (USB)               │
└─────────────────────────────────────────┘
```

### USB Transport

MTP typically runs over USB:

1. **Bulk Transfer** - For data (file content)
2. **Control Transfer** - For commands/responses
3. **Interrupt Transfer** - For events

### USB Interface

```
Interface 0: Control
├── Endpoint 0: Control (IN/OUT)
└── Endpoint 1: Event (IN)

Interface 1: Data (may be split)
├── Endpoint 2: Bulk OUT (commands/data)
└── Endpoint 6: Bulk IN (responses/data)
```

## MTP vs PTP

| Feature | PTP | MTP |
|---------|-----|-----|
| Media transfers | ✅ | ✅ |
| DRM support | ❌ | ✅ |
| Playlist management | ❌ | ✅ |
| Album art | ❌ | ✅ |
| Object referencing | Handles | Handles |

## Device Quirks

Different devices implement MTP differently:

### Common Variations

- **Timeout values**: Some devices need longer timeouts
- **Chunk sizes**: Maximum transfer size varies
- **Supported operations**: Some devices omit optional operations
- **Event handling**: Some devices don't send events

### SwiftMTP's Approach

SwiftMTP handles these variations through:
- **Quirks database**: Device-specific configurations
- **Auto-detection**: Automatically detects capabilities
- **Adaptive timeouts**: Adjusts based on device responses

## Further Reading

- [MTP Protocol Specification](https://usb.org/sites/default/files/MTP%20v1.1%20Spec.zip)
- [Architecture Overview](architecture.md)
- [Device Quirks System](device-quirks.md)
