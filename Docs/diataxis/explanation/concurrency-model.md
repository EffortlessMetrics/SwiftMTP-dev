# Concurrency Model

This document explains SwiftMTP's concurrency and threading model.

## Overview

SwiftMTP uses Swift's modern concurrency features (`async/await`, `actors`) to provide safe, efficient concurrent operations.

## Concurrency Architecture

### Actor-Based Design

```swift
import SwiftMTPCore

// MTPDevice is an actor - safe for concurrent access
actor DeviceManager {
    private var device: MTPDevice?
    
    func connect() async throws {
        device = try await MTPDevice.discover()
    }
    
    func transferFile(path: String, to url: URL) async throws {
        guard let device = device else {
            throw DeviceError.notConnected
        }
        
        try await device.read(handle: path, to: url)
    }
}
```

### Key Actors

| Actor | Purpose |
|-------|---------|
| `MTPDevice` | Device communication and state |
| `TransferManager` | Transfer queue and scheduling |
| `SessionManager` | Session lifecycle |
| `CacheManager` | Caching operations |

## Async/Await Usage

### Basic Operations

```swift
import SwiftMTPCore

// All operations are async
let device = try await MTPDevice.discover()

// File transfer
try await device.read(handle: "/photo.jpg", to: localURL)

// Directory listing
let entries = try await device.listDirectory(path: "/DCIM")

// Object deletion
try await device.delete(path: "/temp/file.txt")
```

### Concurrent Operations

```swift
// Run multiple transfers concurrently
try await withThrowingTaskGroup(of: Void.self) { group in
    for file in files {
        group.addTask {
            try await device.read(handle: file.path, to: file.localURL)
        }
    }
    
    try await group.waitForAll()
}

// Parallel with results
let results = try await withThrowingTaskGroup(of: (String, Data).self) { group in
    for file in files {
        group.addTask {
            let data = try await device.readData(handle: file.path)
            return (file.path, data)
        }
    }
    
    var results: [(String, Data)] = []
    for try await result in group {
        results.append(result)
    }
    return results
}
```

## Threading Model

### Main Thread Safety

SwiftMTP is designed to be used from any Swift concurrency context:

```swift
// Can be called from main actor
@MainActor
func updateUI() async {
    let device = try await MTPDevice.discover()
    let files = try await device.listDirectory(path: "/DCIM")
    
    // Update UI directly
    self.files = files
}

// Can be called from background
func processInBackground() async {
    let device = try await MTPDevice.discover()
    // Processing happens off main thread
}
```

### Actor Isolation

```swift
actor DeviceState {
    private var isConnected = false
    private var currentSession: UInt32?
    
    func connect() async throws {
        // Actor guarantees no data races
        isConnected = true
    }
    
    func disconnect() {
        isConnected = false
        currentSession = nil
    }
}

// Usage
let state = DeviceState()
try await state.connect()
// No locks needed - actor handles synchronization
```

## Transfer Concurrency

### Parallel Transfers

SwiftMTP supports configurable parallel transfers:

```swift
import SwiftMTPCore

let config = DeviceConfiguration(
    parallelTransfers: 4,  // Number of concurrent transfers
    chunkSize: 2 * 1024 * 1024
)

let device = try await MTPDevice.discover(configuration: config)

// Multiple files transfer concurrently
for file in files {
    Task {
        try await device.read(handle: file.path, to: file.localURL)
    }
}
```

### Transfer Queue

```swift
import SwiftMTPCore

class TransferQueue {
    private var pending: [Transfer] = []
    private var active: [Transfer] = []
    private let maxConcurrent: Int
    
    init(maxConcurrent: Int = 2) {
        self.maxConcurrent = maxConcurrent
    }
    
    func enqueue(_ transfer: Transfer) {
        pending.append(transfer)
    }
    
    func process() async throws {
        while !pending.isEmpty && active.count < maxConcurrent {
            let transfer = pending.removeFirst()
            active.append(transfer)
            
            Task {
                defer {
                    Task { await self.complete(transfer) }
                }
                try await transfer.execute()
            }
        }
    }
    
    private func complete(_ transfer: Transfer) async {
        active.removeAll { $0.id == transfer.id }
    }
}
```

## Session Management

### Session Concurrency

```swift
import SwiftMTPCore

// Each session is isolated
actor SessionManager {
    private var sessions: [UInt32: MTPDevice] = [:]
    
    func createSession(for device: MTPDevice) async throws -> UInt32 {
        let sessionId = try await device.openSession()
        sessions[sessionId] = device
        return sessionId
    }
    
    func closeSession(_ sessionId: UInt32) async throws {
        guard let device = sessions[sessionId] else {
            throw SessionError.invalidSession
        }
        
        try await device.closeSession()
        sessions.removeValue(forKey: sessionId)
    }
}
```

### Session Timeout

```swift
import SwiftMTPCore

let config = DeviceConfiguration(
    sessionTimeout: 300  // 5 minutes
)

// Auto-reconnect on timeout
do {
    try await device.read(handle: path, to: url)
} catch MTPError.sessionExpired {
    // Re-establish session
    try await device.openSession()
    // Retry operation
    try await device.read(handle: path, to: url)
}
```

## Thread Safety

### No Data Races

The actor model prevents data races:

```swift
actor FileCache {
    private var cache: [String: Data] = [:]
    
    func get(_ key: String) -> Data? {
        cache[key]
    }
    
    func set(_ key: String, value: Data) {
        cache[key] = value
    }
}

// Multiple threads can safely access
let cache = FileCache()
await cache.set("key1", data1)
let value = await cache.get("key1")
```

### Sendable Compliance

All SwiftMTP types are `Sendable`:

```swift
import SwiftMTPCore

// MTPDevice is Sendable - safe to pass between tasks
func processDevice(_ device: MTPDevice) async {
    // Safe to use across actors
}

// DeviceInfo is also Sendable
let info = device.info  // Can be accessed from any context
```

## Performance Considerations

### Task Groups

```swift
// Efficient parallel processing
try await withThrowingTaskGroup(of: Result<FileEntry, Error>.self) { group in
    for entry in entries {
        group.addTask {
            do {
                let data = try await device.readData(handle: entry.handle)
                return .success(entry)
            } catch {
                return .failure(error)
            }
        }
    }
    
    var results: [FileEntry] = []
    var errors: [Error] = []
    
    for try await result in group {
        switch result {
        case .success(let entry):
            results.append(entry)
        case .failure(let error):
            errors.append(error)
        }
    }
}
```

### Continuation Usage

```swift
// Converting callbacks to async
func getDevice() async throws -> MTPDevice {
    try await withCheckedThrowingContinuation { continuation in
        MTPDevice.discover { result in
            switch result {
            case .success(let device):
                continuation.resume(returning: device)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
```

## Best Practices

### Do

```swift
// ✅ Use async/await
let device = try await MTPDevice.discover()

// ✅ Use actors for state
actor DeviceState { ... }

// ✅ Use Task groups for parallelism
try await withThrowingTaskGroup(of: Void.self) { ... }
```

### Don't

```swift
// ❌ Don't use locks with actors
let lock = NSLock()  // Not needed with actors

// ❌ Don't use callbacks
device.discover { device in  // Old style
    // ...
}

// ❌ Don't mix sync and async
// This blocks the thread
let device = try Device.connectSync()
```

## Related Documentation

- [Architecture Overview](architecture.md)
- [Session Management](session-management.md)
- [API Overview](api-overview.md)
- [Performance Tuning](../howto/performance-tuning.md)
