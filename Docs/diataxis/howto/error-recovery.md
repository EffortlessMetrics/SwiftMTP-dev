# Error Recovery

This guide covers error handling strategies and recovery mechanisms for SwiftMTP operations.

## Quick Reference

| Error Type | Common Cause | Recovery Strategy |
|------------|--------------|-------------------|
| Connection lost | USB disconnect | Reconnect, resume |
| Timeout | Slow device | Increase timeout |
| Device busy | Concurrent access | Retry with backoff |
| Storage full | No space on device | Free space, retry |

## Understanding Errors

### Error Categories

SwiftMTP errors fall into several categories:

```swift
import SwiftMTPCore

enum MTPError: Error {
    case connectionFailed(underlying: Error)
    case transferFailed(code: MTPResponseCode, details: String)
    case deviceBusy(retryAfter: TimeInterval)
    case sessionExpired
    case unsupportedOperation(capability: String)
}
```

### Error Properties

Each error contains helpful information:

```swift
do {
    try await device.read(handle: handle, to: localURL)
} catch let error as MTPError {
    switch error {
    case .transferFailed(let code, let details):
        print("MTP Error \(code.rawValue): \(details)")
    case .deviceBusy(let retryAfter):
        print("Retry after \(retryAfter) seconds")
    default:
        print("Error: \(error)")
    }
}
```

## Connection Error Recovery

### Automatic Reconnection

```swift
import SwiftMTPCore

class ResilientDeviceConnection {
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0
    
    func connectWithRetry() async throws -> MTPDevice {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let device = try await MTPDevice.discover()
                return device
            } catch {
                lastError = error
                print("Attempt \(attempt) failed: \(error)")
                
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }
        
        throw lastError!
    }
}
```

### USB Event Monitoring

```swift
import SwiftMTPCore

class DeviceMonitor {
    private var cancellables = Set<AnyCancellable>()
    
    func monitorConnection() {
        NotificationCenter.default.publisher(for: .deviceConnected)
            .sink { notification in
                if let device = notification.object as? MTPDevice {
                    print("Device connected: \(device.info.model)")
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .deviceDisconnected)
            .sink { notification in
                print("Device disconnected")
                // Trigger reconnection attempt
            }
            .store(in: &cancellables)
    }
}
```

### Session Recovery

```swift
import SwiftMTPCore

class SessionRecovery {
    func withSessionRecovery<T>(
        device: MTPDevice,
        operation: (MTPDevice) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(device)
        } catch MTPError.sessionExpired {
            // Re-establish session
            try await device.openSession()
            // Retry operation
            return try await operation(device)
        }
    }
}
```

## Transfer Error Recovery

### Retry with Exponential Backoff

```swift
import SwiftMTPCore

struct RetryConfiguration {
    var maxRetries: Int = 3
    var initialDelay: TimeInterval = 1.0
    var maxDelay: TimeInterval = 30.0
    var backoffMultiplier: Double = 2.0
}

class RetryableTransfer {
    private let config: RetryConfiguration
    
    init(config: RetryConfiguration = RetryConfiguration()) {
        self.config = config
    }
    
    func execute<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = config.initialDelay
        
        for attempt in 1...config.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry for unrecoverable errors
                if !isRetryable(error) {
                    throw error
                }
                
                print("Transfer failed, attempt \(attempt)/\(config.maxRetries)")
                
                if attempt < config.maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * config.backoffMultiplier, config.maxDelay)
                }
            }
        }
        
        throw lastError!
    }
    
    private func isRetryable(_ error: Error) -> Bool {
        if let mtpError = error as? MTPError {
            switch mtpError {
            case .deviceBusy, .connectionFailed:
                return true
            default:
                return false
            }
        }
        return true // Retry unknown errors
    }
}
```

### Resume Interrupted Transfers

```swift
import SwiftMTPCore

class ResumableTransfer {
    private let device: MTPDevice
    
    func downloadWithResume(
        remotePath: String,
        localURL: URL
    ) async throws {
        let fileManager = FileManager.default
        
        // Check for partial download
        let existingSize: UInt64
        if fileManager.fileExists(atPath: localURL.path) {
            let attrs = try fileManager.attributesOfItem(atPath: localURL.path)
            existingSize = attrs[.size] as? UInt64 ?? 0
        } else {
            existingSize = 0
        }
        
        // Get file info from device
        let fileInfo = try await device.getEntry(path: remotePath)
        let totalSize = fileInfo.size
        
        if existingSize > 0 && existingSize < totalSize {
            // Resume from existing position
            print("Resuming from \(existingSize) bytes")
            try await device.read(
                handle: remotePath,
                offset: existingSize,
                to: localURL,
                append: true
            )
        } else {
            // Start fresh
            try await device.read(handle: remotePath, to: localURL)
        }
    }
}
```

### Partial Download Handling

```swift
import SwiftMTPCore

class ChunkedTransfer {
    private let chunkSize: Int = 1024 * 1024 // 1MB
    
    func downloadInChunks(
        device: MTPDevice,
        path: String,
        to localURL: URL
    ) async throws {
        let fileInfo = try await device.getEntry(path: path)
        let totalSize = fileInfo.size
        
        var offset: UInt64 = 0
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }
        
        while offset < totalSize {
            let remaining = totalSize - offset
            let thisChunk = min(UInt64(chunkSize), remaining)
            
            do {
                try await device.read(
                    handle: path,
                    offset: offset,
                    maxBytes: Int(thisChunk)
                ) { data in
                    fileHandle.write(data)
                }
                
                offset += thisChunk
                let progress = Double(offset) / Double(totalSize)
                print("Progress: \(Int(progress * 100))%")
            } catch {
                // Save checkpoint
                try fileHandle.synchronize()
                throw TransferError.chunkFailed(offset: offset, error: error)
            }
        }
    }
}
```

## Device Busy Recovery

### Handling Device Conflicts

```swift
import SwiftMTPCore

class BusyDeviceHandler {
    private let maxRetries = 5
    private let baseDelay: TimeInterval = 0.5
    
    func handleBusyDevice<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch MTPError.deviceBusy(let retryAfter) {
                let delay = retryAfter ?? (baseDelay * pow(2, Double(attempt - 1)))
                print("Device busy, waiting \(delay)s (attempt \(attempt)/\(maxRetries))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw MTPError.deviceBusy(retryAfter: nil)
    }
}
```

### Avoiding Concurrent Access

```swift
import SwiftMTPCore

actor DeviceAccessControl {
    private var activeOperations = 0
    private let maxConcurrent = 1 // MTP devices typically allow single session
    
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        while activeOperations >= maxConcurrent {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        activeOperations += 1
        defer { activeOperations -= 1 }
        
        return try await operation()
    }
}
```

## Storage Error Recovery

### Handling Full Storage

```swift
import SwiftMTPCore

class StorageErrorHandler {
    func handleFullStorage(device: MTPDevice) async throws {
        // Get storage info
        let storages = try await device.getStorageInfo()
        
        for storage in storages {
            print("\(storage.description): \(storage.freeSpace) bytes free")
        }
        
        // Recommend cleanup
        print("Please free up space on your device and try again")
    }
}
```

### Verify Before Transfer

```swift
import SwiftMTPCore

class StorageChecker {
    func ensureSpace(for fileSize: UInt64, on device: MTPDevice) async throws {
        let storages = try await device.getStorageInfo()
        
        guard let primary = storages.first(where: { $0.isPrimary }) else {
            throw DeviceError.noStorage
        }
        
        if primary.freeSpace < fileSize {
            throw StorageError.insufficientSpace(
                required: fileSize,
                available: primary.freeSpace
            )
        }
    }
}
```

## Error Recovery Patterns

### Circuit Breaker

```swift
import SwiftMTPCore

class CircuitBreaker {
    enum State { case closed, open, halfOpen }
    
    private var state: State = .closed
    private var failureCount = 0
    private let threshold = 5
    private var lastFailure: Date?
    
    func execute<T>(
        operation: () async throws -> T
    ) async throws -> T {
        guard state == .closed || state == .halfOpen else {
            throw CircuitBreakerError.open
        }
        
        do {
            let result = try await operation()
            onSuccess()
            return result
        } catch {
            onFailure()
            throw error
        }
    }
    
    private func onSuccess() {
        failureCount = 0
        state = .closed
    }
    
    private func onFailure() {
        failureCount += 1
        if failureCount >= threshold {
            state = .open
            lastFailure = Date()
        }
    }
}
```

### Checkpoint Pattern

```swift
import SwiftMTPCore

class CheckpointManager {
    private let checkpointURL: URL
    private var completedItems: Set<String> = []
    
    init(checkpointPath: URL) {
        self.checkpointURL = checkpointPath
        load()
    }
    
    func isCompleted(_ item: String) -> Bool {
        completedItems.contains(item)
    }
    
    func markCompleted(_ item: String) {
        completedItems.insert(item)
        save()
    }
    
    func reset() {
        completedItems.removeAll()
        try? FileManager.default.removeItem(at: checkpointURL)
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: checkpointURL.path),
              let data = try? Data(contentsOf: checkpointURL),
              let items = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return
        }
        completedItems = items
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(completedItems) else { return }
        try? data.write(to: checkpointURL)
    }
}
```

## CLI Error Recovery

### Built-in Retry

```bash
# Downloads with automatic retry
swift run swiftmtp pull /DCIM/photo.jpg --retry 3 --retry-delay 2

# Verbose output for debugging
swift run swiftmtp pull /DCIM/photo.jpg --verbose
```

### Scripted Recovery

```bash
#!/bin/bash
# Robust download with error handling

OUTPUT_DIR="./downloads"
MAX_RETRIES=3

download_file() {
    local path="$1"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if swift run swiftmtp pull "$path" --output "$OUTPUT_DIR" 2>/dev/null; then
            return 0
        fi
        retries=$((retries + 1))
        echo "Retry $retries for $path"
        sleep 2
    done
    
    echo "FAILED: $path" >> failures.log
    return 1
}

# Download multiple files
for file in $(cat filelist.txt); do
    download_file "$file"
done

# Report failures
if [ -f failures.log ]; then
    echo "Failed files:"
    cat failures.log
fi
```

## Best Practices

### Error Handling Checklist

1. **Always catch specific errors** - Handle MTPError specifically
2. **Implement retry logic** - Use exponential backoff
3. **Add checkpoints** - Save progress for large operations
4. **Log errors** - Include context for debugging
5. **Notify users** - Show meaningful error messages

### Configuration for Reliability

```bash
# Recommended for production
export SWIFTMTP_IO_TIMEOUT_MS=60000
export SWIFTMTP_MAX_RETRIES=3
export SWIFTMTP_RETRY_DELAY_MS=2000
```

## Related Documentation

- [Error Codes Reference](../reference/error-codes.md)
- [CLI Commands Reference](../reference/cli-commands.md)
- [Troubleshooting Connection](troubleshoot-connection.md)
- [Batch Operations Tutorial](../tutorials/batch-operations.md)

## Summary

Key error recovery strategies:

1. ✅ **Connection errors** - Automatic reconnection with retry
2. ✅ **Transfer errors** - Resume and checkpoint patterns
3. ✅ **Busy device** - Exponential backoff
4. ✅ **Storage errors** - Pre-check available space
5. ✅ **Circuit breaker** - Prevent cascade failures
6. ✅ **CLI recovery** - Script-based retry mechanisms
