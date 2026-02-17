# Advanced Transfer Strategies

This tutorial covers advanced file transfer techniques in SwiftMTP, including parallel transfers, resumable transfers, and production-ready patterns.

## What You'll Learn

- Implement parallel multi-file transfers
- Handle interrupted transfers with resume capability
- Build resilient transfer pipelines
- Optimize for large file operations
- Handle edge cases and failures gracefully

## Prerequisites

- Completed [Your First Device Transfer](first-transfer.md)
- Understanding of basic MTP operations
- SwiftMTP installed (see [Getting Started](getting-started.md))

## Understanding Transfer Architecture

SwiftMTP provides several transfer modes optimized for different scenarios:

```
┌─────────────────────────────────────────────────────────────┐
│                    Transfer Pipeline                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  Source  │───▶│  Transfer    │───▶│  Destination     │  │
│  │  Files   │    │  Engine      │    │  (Device/Local)  │  │
│  └──────────┘    └──────────────┘    └──────────────────┘  │
│                           │                                  │
│                           ▼                                  │
│                  ┌────────────────┐                         │
│                  │ Progress/Error │                         │
│                  │ Handler        │                         │
│                  └────────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

## Parallel Transfers

For transferring multiple files, parallel operations significantly improve throughput.

### Using the CLI for Parallel Transfers

```bash
# Transfer multiple files in parallel (default: 3 concurrent)
swift run swiftmtp pull /DCIM/Camera/*.jpg --parallel

# Specify number of parallel transfers
swift run swiftmtp pull /DCIM/Camera/*.jpg --parallel=5

# Parallel upload
swift run swiftmtp push ~/Photos/*.jpg --parallel=4 --to /Pictures/
```

### Parallel Transfer in Swift Code

```swift
import SwiftMTPCore

// Configure parallel transfer options
let options = TransferOptions(
    maxConcurrentTransfers: 4,
    transferChunkSize: 64 * 1024,  // 64KB chunks
    retryAttempts: 3,
    retryDelay: .seconds(2)
)

// Create transfer manager
let manager = TransferManager(options: options)

// Define file batch
let filesToTransfer: [TransferItem] = [
    TransferItem(sourcePath: "/DCIM/photo1.jpg", localPath: "~/Downloads/photo1.jpg"),
    TransferItem(sourcePath: "/DCIM/photo2.jpg", localPath: "~/Downloads/photo2.jpg"),
    TransferItem(sourcePath: "/DCIM/photo3.jpg", localPath: "~/Downloads/photo3.jpg"),
    TransferItem(sourcePath: "/DCIM/photo4.jpg", localPath: "~/Downloads/photo4.jpg"),
]

// Execute parallel transfer
await withCheckedContinuation { continuation in
    manager.transferBatch(
        files: filesToTransfer,
        progress: { progress in
            print("Transfer \(progress.completed)/\(progress.total): \(progress.currentFile)")
        },
        completion: { result in
            switch result {
            case .success(let results):
                print("Transferred \(results.count) files")
                for result in results {
                    print("  - \(result.sourcePath): \(result.bytesTransferred) bytes")
                }
            case .failure(let error):
                print("Transfer failed: \(error)")
            }
            continuation.resume()
        }
    )
}
```

### Transfer Options Reference

| Option | Default | Description |
|--------|---------|-------------|
| `maxConcurrentTransfers` | 3 | Maximum simultaneous transfers |
| `transferChunkSize` | 64KB | Data chunk size per operation |
| `retryAttempts` | 3 | Number of retry attempts |
| `retryDelay` | 1s | Delay between retries |
| `verifyChecksum` | true | Verify file integrity |
| `preserveTimestamps` | true | Preserve file modification times |

## Resumable Transfers

SwiftMTP supports resuming interrupted transfers, crucial for large files or unstable connections.

### How Resume Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Resume Mechanism                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Initial Transfer:                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ File: large-video.mp4 (500MB)                       │   │
│  │                                                      │   │
│  │ [████████████████████████░░░░░░░░░░░░░░░░░░░░░░░]  │   │
│  │ Transferred: 300MB / 500MB                          │   │
│  │                                                      │   │
│  │ ❌ Connection Lost at 60%                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Resume Request:                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Client: "I have 300MB, continue from offset 300MB" │   │
│  │ Device: "OK, starting from offset 300MB"            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Resumed Transfer:                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [███████████████████████████████░░░░░░░░░░░░░░░░░]  │   │
│  │ Transferred: 300MB -> 500MB                          │   │
│  │ ✅ Complete                                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Resume Support by Operation

| Operation | Resume Support | Requirements |
|-----------|----------------|--------------|
| Download (GetPartialObject64) | ✅ Automatic | Device must support 64-bit partial objects |
| Download (GetPartialObject) | ✅ Automatic | Device supports 32-bit partial objects |
| Upload | ⚠️ Manual | Requires implementation + device support |
| Mirror | ✅ Automatic | Based on file checksums |

### Implementing Resume in Code

```swift
import SwiftMTPCore

class ResumableTransfer {
    private let device: MTPDevice
    private let stateFile: URL
    
    struct TransferState: Codable {
        let sourcePath: String
        let localPath: String
        let totalBytes: UInt64
        var transferredBytes: UInt64
        let startTime: Date
        var lastResumeTime: Date?
    }
    
    init(device: MTPDevice, stateDirectory: URL) {
        self.device = device
        self.stateFile = stateDirectory.appendingPathComponent("transfer-state.json")
    }
    
    /// Download with resume capability
    func downloadWithResume(remotePath: String, localPath: String) async throws {
        // Check for existing state
        var state = loadState(for: remotePath)
        
        // Get file info
        let fileInfo = try await device.getFileInfo(at: remotePath)
        
        if let existing = state, existing.transferredBytes > 0 {
            // Resume from previous position
            print("Resuming transfer at \(existing.transferredBytes)/\(fileInfo.size)")
            
            let partialData = try await device.getPartialObject(
                at: remotePath,
                offset: existing.transferredBytes
            )
            
            // Append to existing file
            let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: localPath))
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: partialData)
            try fileHandle.close()
            
            // Update state
            state?.transferredBytes += UInt64(partialData.count)
            state?.lastResumeTime = Date()
            saveState(state!)
        } else {
            // Fresh transfer
            state = TransferState(
                sourcePath: remotePath,
                localPath: localPath,
                totalBytes: fileInfo.size,
                transferredBytes: 0,
                startTime: Date(),
                lastResumeTime: nil
            )
            saveState(state!)
            
            try await performFullTransfer(remotePath: remotePath, localPath: localPath)
        }
        
        // Verify completion
        if let currentState = state, currentState.transferredBytes >= currentState.totalBytes {
            print("Transfer complete!")
            removeState(for: remotePath)
        }
    }
    
    private func loadState(for path: String) -> TransferState? {
        guard let data = try? Data(contentsOf: stateFile),
              let states = try? JSONDecoder().decode([TransferState].self, from: data) else {
            return nil
        }
        return states.first { $0.sourcePath == path }
    }
    
    private func saveState(_ state: TransferState) {
        // Save to persistent storage
    }
    
    private func removeState(for path: String) {
        // Remove from persistent storage
    }
    
    private func performFullTransfer(remotePath: String, localPath: String) async throws {
        // Full transfer implementation
    }
}
```

## Advanced Transfer Strategies

### Strategy 1: Chunked Transfer for Large Files

```swift
/// Transfer large files in chunks for better progress tracking and memory efficiency
func chunkedDownload(
    device: MTPDevice,
    remotePath: String,
    localPath: String,
    chunkSize: UInt64 = 10 * 1024 * 1024  // 10MB chunks
) async throws {
    let fileInfo = try await device.getFileInfo(at: remotePath)
    let totalSize = fileInfo.size
    
    // Create empty file
    FileManager.default.createFile(atPath: localPath, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: localPath))
    defer { try? fileHandle.close() }
    
    var offset: UInt64 = 0
    while offset < totalSize {
        let thisChunkSize = min(chunkSize, totalSize - offset)
        
        let chunkData = try await device.getPartialObject(
            at: remotePath,
            offset: offset,
            size: thisChunkSize
        )
        
        try fileHandle.write(contentsOf: chunkData)
        offset += thisChunkSize
        
        let progress = Double(offset) / Double(totalSize) * 100
        print("Progress: \(String(format: "%.1f", progress))%")
    }
}
```

### Strategy 2: Batch Transfer with Priority

```swift
/// Priority-based transfer queue
struct PriorityTransfer {
    let item: TransferItem
    let priority: Int  // Higher = more urgent
    let createdAt: Date
}

class PriorityTransferManager {
    private var queue: [PriorityTransfer] = []
    private let maxConcurrent: Int
    
    func enqueue(_ item: TransferItem, priority: Int = 0) {
        let transfer = PriorityTransfer(
            item: item,
            priority: priority,
            createdAt: Date()
        )
        queue.append(transfer)
        queue.sort { $0.priority > $1.priority }
    }
    
    func processNext() async throws -> TransferResult? {
        guard let next = queue.first else { return nil }
        queue.removeFirst()
        
        // Process the transfer
        return try await performTransfer(next.item)
    }
}

// Usage: Prioritize important files
let manager = PriorityTransferManager(maxConcurrent: 2)

// High priority - files needed urgently
manager.enqueue(TransferItem(sourcePath: "/DCIM/important.jpg", localPath: "important.jpg"), priority: 10)

// Normal priority
manager.enqueue(TransferItem(sourcePath: "/Download/backup1.zip", localPath: "backup1.zip"), priority: 5)

// Low priority
manager.enqueue(TransferItem(sourcePath: "/Download/old-files/*", localPath: "archive/"), priority: 1)
```

### Strategy 3: Checksum Verification

```swift
/// Verify transferred files using checksums
func verifyTransfer(
    localPath: String,
    expectedChecksum: String,
    algorithm: ChecksumAlgorithm = .sha256
) async throws -> Bool {
    let fileData = try Data(contentsOf: URL(fileURLWithPath: localPath))
    let computedChecksum = computeChecksum(data: fileData, algorithm: algorithm)
    return computedChecksum == expectedChecksum
}

enum ChecksumAlgorithm {
    case md5
    case sha1
    case sha256
    
    var name: String {
        switch self {
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        }
    }
}

func computeChecksum(data: Data, algorithm: ChecksumAlgorithm) -> String {
    // Use CryptoKit for actual implementation
    // This is a placeholder
    return data.base64EncodedString().prefix(32).description
}
```

## Handling Failures Gracefully

### Automatic Retry with Backoff

```swift
class RetryableTransfer {
    enum TransferError: Error {
        case maxRetriesExceeded(attempts: Int, lastError: Error)
        case cancelled
    }
    
    func transferWithRetry(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffMultiplier: Double = 2.0,
        operation: @escaping () async throws -> TransferResult
    ) async throws -> TransferResult {
        var lastError: Error?
        var currentDelay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt == maxAttempts {
                    throw TransferError.maxRetriesExceeded(
                        attempts: maxAttempts,
                        lastError: error
                    )
                }
                
                print("Attempt \(attempt) failed: \(error). Retrying in \(currentDelay)s...")
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                currentDelay = min(currentDelay * backoffMultiplier, maxDelay)
            }
        }
        
        throw lastError!
    }
}
```

### Partial Failure Handling

```swift
/// Handle partial failures in batch transfers
func transferBatchWithPartialFailure(
    items: [TransferItem],
    continueOnError: Bool = true
) async throws -> BatchTransferResult {
    var results: [TransferResult] = []
    var errors: [TransferError] = []
    
    for item in items {
        do {
            let result = try await performTransfer(item)
            results.append(result)
        } catch {
            if !continueOnError {
                throw error
            }
            errors.append(TransferError(item: item, error: error))
        }
    }
    
    return BatchTransferResult(
        successful: results,
        failed: errors,
        totalAttempted: items.count,
        successCount: results.count,
        failureCount: errors.count
    )
}

struct BatchTransferResult {
    let successful: [TransferResult]
    let failed: [TransferError]
    let totalAttempted: Int
    let successCount: Int
    let failureCount: Int
    
    var successRate: Double {
        guard totalAttempted > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempted) * 100
    }
}
```

## Performance Optimization Tips

### 1. Choose the Right Transfer Mode

| Scenario | Recommended Mode |
|----------|-----------------|
| Few large files | Sequential with large chunks |
| Many small files | Parallel with small chunks |
| Unstable connection | Small chunks, more retries |
| Stable high-speed link | Aggressive parallelization |

### 2. Optimize Buffer Sizes

```swift
// Default: 64KB - good for general use
let defaultOptions = TransferOptions()

// High-speed transfers - larger buffers
let fastOptions = TransferOptions(
    transferChunkSize: 1024 * 1024  // 1MB
)

// Memory-constrained - smaller buffers
let lowMemoryOptions = TransferOptions(
    transferChunkSize: 32 * 1024  // 32KB
)
```

### 3. USB-specific Optimizations

```swift
// Configure for USB 3.0 high-speed
let usb3Options = TransferOptions(
    maxConcurrentTransfers: 8,
    transferChunkSize: 512 * 1024,  // 512KB
    useAlignedTransfers: true       // Align to USB packet boundaries
)

// USB 2.0 - more conservative
let usb2Options = TransferOptions(
    maxConcurrentTransfers: 2,
    transferChunkSize: 64 * 1024,
    useAlignedTransfers: false
)
```

## Monitoring and Debugging

### Enable Transfer Logging

```swift
import Logging

var logger = Logger(label: "com.swiftmtp.transfer")
logger.logLevel = .debug

let options = TransferOptions(
    enableLogging: true,
    logger: logger
)

let manager = TransferManager(options: options)
```

### Progress Callbacks

```swift
manager.transferBatch(
    files: files,
    progress: { progress in
        // Detailed progress information
        print("""
//        
        File: \(progress.currentFile)
        Progress: \(progress.percentage)%
        Speed: \(progress.bytesPerSecond.formatted(.byteCount(style: .perUnit)))
        ETA: \(progress.estimatedTimeRemaining?.formatted() ?? "unknown")
        """)
    },
    completion: { result in
        // Handle completion
    }
)
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Slow transfer speeds | USB 2.0, cable quality, device limitation | Use USB 3.0, quality cable |
| Resume not working | Device doesn't support partial objects | Fall back to full retransfer |
| Memory pressure | Large file buffer too big | Reduce chunk size |
| Intermittent failures | Unstable USB connection | Enable retry with backoff |

### Debug Mode

```bash
# Enable debug logging
swift run swiftmtp pull /DCIM/photo.jpg --verbose --debug

# Output includes:
# - USB packet details
# - Timing information
# - Memory usage
# - Retry attempts
```

## Next Steps

- 📋 [Performance Tuning](../howto/performance-tuning.md) - Optimize transfer speeds
- 📋 [Testing Devices](../howto/testing-devices.md) - Test device capabilities
- 📋 [Transfer Files Guide](../howto/transfer-files.md) - Basic transfer operations
- 📋 [API Overview](../reference/api-overview.md) - Complete API reference

## Summary

In this tutorial, you learned:
- ✅ Parallel transfer implementation
- ✅ Resumable transfer patterns
- ✅ Chunked large file transfers
- ✅ Priority-based transfer queues
- ✅ Failure handling and retry strategies
- ✅ Performance optimization techniques
