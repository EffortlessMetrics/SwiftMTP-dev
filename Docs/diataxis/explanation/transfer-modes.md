# Transfer Modes Explained

This document explains the different transfer modes supported by SwiftMTP and when to use each.

## Overview

SwiftMTP supports multiple modes for transferring files between a host and MTP device. Each mode has different characteristics for performance, reliability, and resumability.

## Transfer Mode Types

### 1. Single-Pass Transfer

The most basic transfer mode - entire file sent in one operation.

```swift
// Simple single-pass upload
try await device.write(
    parent: folderHandle,
    name: "photo.jpg",
    data: photoData
)
```

**Characteristics:**
- Simple to implement
- No resume capability
- Entire file in memory
- Suitable for small files (< 10 MB)

**Use Cases:**
- Small files
- Quick operations
- When memory is not a concern

### 2. Chunked Transfer

Large files are divided into chunks for transfer.

```swift
// Chunked download with configurable size
let config = TransferConfiguration(
    chunkSize: 2 * 1024 * 1024  // 2 MB chunks
)

for await chunk in device.readChunks(handle: fileHandle, config: config) {
    try fileOutputStream.write(chunk)
}
```

**Characteristics:**
- Configurable chunk size
- Progress reporting per chunk
- Memory-efficient
- May support resume (device-dependent)

**Use Cases:**
- Large files (video, photos)
- Limited memory situations
- Progress monitoring needed

### 3. Stream Transfer

Continuous streaming for very large files.

```swift
// Stream download
let stream = try await device.read(
    handle: largeFileHandle,
    to: outputStream
)

for try await data in stream {
    // Process data continuously
    processVideoFrame(data)
}
```

**Characteristics:**
- Constant memory usage
- Real-time processing
- No full file buffering
- Best for media files

**Use Cases:**
- Video playback during transfer
- Media streaming
- Very large files (GB+)

### 4. Resumable Transfer

Supports resuming interrupted transfers.

```swift
// Check if resume is supported
let supportsResume = device.capabilities.contains(.getPartialObject64)

// Resume from offset
let existingSize = try FileManager.default.attributesOfItem(atPath: localPath)[.size] as? UInt64 ?? 0

if supportsResume {
    try await device.readPartial(
        handle: fileHandle,
        offset: existingSize,
        to: outputURL
    )
}
```

**Characteristics:**
- Resume from interruption
- Checksum verification
- Efficient for large files
- Requires device support

**Requirements:**
- `GetPartialObject64` operation support
- Device must support random access

**Use Cases:**
- Large file downloads
- Unstable connections
- Background transfers

### 5. Parallel Transfer

Multiple files transferred simultaneously.

```swift
// Parallel uploads
try await withThrowingTaskGroup(of: Void.self) { group in
    for file in files {
        group.addTask {
            try await device.write(
                parent: folderHandle,
                name: file.name,
                data: file.data
            )
        }
    }
    try await group.waitForAll()
}
```

**Characteristics:**
- Multiple concurrent transfers
- Total throughput improved
- Higher resource usage
- May need device bandwidth limits

**Use Cases:**
- Backing up multiple files
- Fast batch transfers
- When device supports concurrent ops

## Comparison Matrix

| Mode | Memory | Resume | Large Files | Speed |
|------|--------|--------|-------------|-------|
| Single-Pass | High | ❌ | ❌ | Good |
| Chunked | Medium | Maybe | ✅ | Good |
| Stream | Low | ❌ | ✅ | Good |
| Resumable | Medium | ✅ | ✅ | Good |
| Parallel | Variable | Per-file | ✅ | Best |

## Choosing a Transfer Mode

### Decision Tree

```
Is file > 100 MB?
│
├─ YES → Is connection stable?
│       │
│       ├─ YES → Use Chunked or Stream
│       └─ NO → Use Resumable (if supported)
│
└─ NO → Is memory limited?
        │
        ├─ YES → Use Chunked
        └─ NO → Use Single-Pass
```

### Mode Selection Example

```swift
import SwiftMTPCore

func selectTransferMode(
    fileSize: UInt64,
    deviceCapabilities: DeviceCapabilities,
    options: TransferOptions
) -> TransferMode {
    
    // Check for resumable support
    if fileSize > 100 * 1024 * 1024 &&
       deviceCapabilities.supports(.getPartialObject64) &&
       !options.stableConnection {
        return .resumable
    }
    
    // Large files with stable connection
    if fileSize > 50 * 1024 * 1024 {
        return options.useStreaming ? .stream : .chunked
    }
    
    // Small files
    return .singlePass
}
```

## Implementation Details

### Chunked Transfer Internals

```
File (100 MB)
    │
    ▼
┌─────────────────────────────────────┐
│ Split into chunks (default 4 MB)    │
├─────────┬─────────┬─────┬───────────┤
│ Chunk 1 │ Chunk 2 │ ... │ Chunk 25  │
└────┬────┴────┬────┴─────┴─────┬────┘
     │         │                 │
     ▼         ▼                 ▼
┌─────────┐ ┌─────────┐    ┌─────────┐
│  Send   │ │  Send   │    │  Send   │
│ Cmd +   │ │ Cmd +   │    │ Cmd +   │
│  Data   │ │  Data   │    │  Data   │
└────┬────┘ └────┬────┘    └────┬────┘
     │         │                 │
     ▼         ▼                 ▼
  Complete   Complete         Complete
```

### Transfer Protocol

```swift
// Simplified chunked transfer protocol
func transferChunked(
    device: MTPDevice,
    handle: ObjectHandle,
    chunkSize: Int
) async throws {
    var offset: UInt64 = 0
    
    while offset < fileSize {
        let chunk = try await device.read(
            handle: handle,
            offset: offset,
            length: min(chunkSize, fileSize - offset)
        )
        
        try outputStream.write(chunk)
        offset += UInt64(chunk.count)
        
        // Report progress
        reportProgress(bytes: offset, total: fileSize)
    }
}
```

## Error Recovery

### Automatic Retry

```swift
let config = TransferConfiguration(
    retryCount: 3,
    retryDelay: .seconds(2),
    backoffMultiplier: 2.0
)
```

### Manual Resume

```swift
func downloadWithResume(
    device: MTPDevice,
    handle: ObjectHandle,
    localURL: URL
) async throws {
    
    // Check local file size
    let existingSize = try? FileManager.default
        .attributesOfItem(atPath: localURL.path)[.size] as? UInt64
    
    // Resume if possible
    if let offset = existingSize, offset > 0 {
        let remaining = try await device.readPartial(
            handle: handle,
            offset: offset,
            to: localURL,
            options: .append
        )
        try await processRemaining(remaining)
    } else {
        // Fresh download
        try await device.read(handle: handle, to: localURL)
    }
}
```

## Performance Tuning

### Optimal Chunk Size

Chunk size affects performance:

| Chunk Size | Memory | Overhead | Best For |
|------------|--------|----------|----------|
| 64 KB | Very Low | Higher | Low-end devices |
| 1 MB | Low | Medium | Default |
| 4 MB | Medium | Lower | Most devices |
| 8 MB+ | High | Lowest | Fast devices |

### Adjusting for Device

```swift
// Query device for optimal size
let optimalSize = device.optimalChunkSize ?? 4 * 1024 * 1024

let config = TransferConfiguration(
    chunkSize: optimalSize
)
```

## Related Documentation

- [Transfer Files How-To](../howto/transfer-files.md)
- [Transport Layers](transport-layers.md)
- [Configuration Reference](../reference/configuration.md)

## Summary

This document covered:

1. ✅ Single-pass transfer mode
2. ✅ Chunked transfer mode
3. ✅ Stream transfer mode
4. ✅ Resumable transfer mode
5. ✅ Parallel transfer mode
6. ✅ Mode selection criteria
7. ✅ Implementation details
8. ✅ Performance tuning