# Session Lifecycle Management

This document explains how SwiftMTP manages MTP sessions throughout their lifecycle, including connection, operation, and cleanup phases.

## Understanding MTP Sessions

An MTP session represents a logical connection between the host computer and the MTP device. Sessions enable stateful communication and must be properly managed to ensure reliable operations.

```
┌─────────────────────────────────────────────────────────────┐
│              MTP Session Lifecycle                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                           │
│  │   DISCOVERED │                                           │
│  └──────┬───────┘                                           │
│         │ Device found                                       │
│         ▼                                                    │
│  ┌──────────────┐                                           │
│  │   CONNECTED  │◀── USB interface claimed                  │
│  └──────┬───────┘                                           │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                           │
│  │   SESSION    │◀── MTP OpenSession sent                  │
│  │    OPEN      │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│         ▼ Operations                                         │
│  ┌──────────────┐                                           │
│  │   ACTIVE     │◀── Ready for file operations              │
│  │   (Working)   │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                           │
│  │   SESSION    │◀── MTP CloseSession sent                  │
│  │   CLOSING    │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                           │
│  │  DISCONNECTED│◀── USB interface released                  │
│  └──────────────┘                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Session States

### State Diagram

```
                    ┌─────────────────────────────────┐
                    │                                 │
    ┌───────────────▶│         INITIAL                │
    │                │                                 │
    │                └──────────────┬──────────────────┘
    │                                 │
    │                                 │ openSession()
    │                                 ▼
    │                ┌─────────────────────────────────┐
    │                │                                 │
    │                │          OPENING                 │
    │                │   (Sending OpenSession)         │
    │                └──────────────┬──────────────────┘
    │                                 │
    │                                 │ Success
    │                                 ▼
    │                ┌─────────────────────────────────┐
    │                │                                 │
    │                │          ACTIVE                 │
    │                │   (Session ready for ops)       │
    │                └──────────────┬──────────────────┘
    │                                 │
    │   ┌──────────────┐            │
    │   │ Operations   │            │ closeSession()
    │   │ can proceed  │            ▼
    │   └──────────────┘   ┌─────────────────────────────────┐
    │                       │                                 │
    │                       │         CLOSING                 │
    │                       │   (Sending CloseSession)        │
    │                       └──────────────┬──────────────────┘
    │                                            │
    │                                            │ Done
    │                                            ▼
    │                       ┌─────────────────────────────────┐
    └──────────────────────│          CLOSED                 │
                           │                                 │
                           └─────────────────────────────────┘
```

### State Descriptions

| State | Description |
|-------|-------------|
| `initial` | Device discovered but not connected |
| `opening` | In process of establishing connection |
| `active` | Session open, operations allowed |
| `closing` | In process of closing session |
| `closed` | Session closed, device disconnected |

## Session Lifecycle in Code

### Basic Session Usage

```swift
import SwiftMTPCore

// Discover device
let device = try await MTPDevice.discoverFirst()

// Connect (USB level)
try await device.connect()

// Open MTP session
try await device.openSession()

// Perform operations
let files = try await device.list(at: "/DCIM")

// Close session
try await device.closeSession()

// Disconnect (USB level)
try await device.disconnect()
```

### Using DeviceManager

```swift
let manager = MTPDeviceManager.shared

// Start discovery
try await manager.startDiscovery()

// Open device (connects and opens session)
let device = try await manager.openDevice(summary: deviceSummary)

// Device is ready for use
let files = try await device.list(at: "/")

// Close when done
try await manager.disposeDevice(id: device.id)
```

## Session Opening Process

### Step-by-Step Breakdown

```
┌─────────────────────────────────────────────────────────────┐
│              Session Opening Sequence                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. USB Connection                                           │
│     ┌────────────────────────────────────────────────┐      │
│     │  - Enumerate USB devices                       │      │
│     │  - Match vendor/product IDs                    │      │
│     │  - Open USB interface                          │      │
│     │  - Claim interface                              │      │
│     └────────────────────────────────────────────────┘      │
│                           │                                  │
│                           ▼                                  │
│  2. MTP Handshake                                           │
│     ┌────────────────────────────────────────────────┐      │
│     │  - GetDeviceInfo (0x1001)                     │      │
│     │  - OpenSession (0x1002)                       │      │
│     │  - GetStorageIDs (0x1005)                      │      │
│     └────────────────────────────────────────────────┘      │
│                           │                                  │
│                           ▼                                  │
│  3. Device Probing                                          │
│     ┌────────────────────────────────────────────────┐      │
│     │  - Check quirks database                       │      │
│     │  - Query capabilities                          │      │
│     │  - Initialize storage info                     │      │
│     └────────────────────────────────────────────────┘      │
│                           │                                  │
│                           ▼                                  │
│  4. Ready for Operations                                    │
│     ┌────────────────────────────────────────────────┐      │
│     │  - Device state = active                       │      │
│     │  - Operations can proceed                      │      │
│     └────────────────────────────────────────────────┘      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Details

```swift
actor SessionManager {
    enum State {
        case initial
        case active
        case opening
        case closing
        case closed
    }
    
    private var state: State = .initial
    
    func openSession() async throws {
        guard state == .initial else {
            throw SessionError.invalidState(state)
        }
        
        state = .opening
        
        do {
            // Step 1: USB connection
            try await transport.connect()
            
            // Step 2: MTP handshake
            let deviceInfo = try await protocolLayer.getDeviceInfo()
            try await protocolLayer.openSession()
            
            // Step 3: Device probing
            let quirks = try await quirkResolver.resolve(
                vid: deviceInfo.vendorId,
                pid: deviceInfo.productId
            )
            
            // Apply quirks
            try await applyQuirks(quirks)
            
            state = .active
            
        } catch {
            state = .closed
            throw SessionError.openingFailed(error)
        }
    }
}
```

## Session Closing Process

### Graceful Shutdown

```swift
func closeSession() async throws {
    guard state == .active else {
        throw SessionError.invalidState(state)
    }
    
    state = .closing
    
    // Step 1: Cancel any pending operations
    await cancelPendingOperations()
    
    // Step 2: Close MTP session
    try await protocolLayer.closeSession()
    
    // Step 3: Disconnect USB
    try await transport.disconnect()
    
    state = .closed
}
```

### Cleanup Operations

```swift
private func cleanup() async {
    // Clear cached data
    await clearCache()
    
    // Close file handles
    await closeFileHandles()
    
    // Cancel subscriptions
    await cancelEventSubscriptions()
    
    // Release resources
    await releaseResources()
}
```

## Session Management Best Practices

### Always Clean Up

```swift
// ✅ CORRECT: Proper cleanup with defer
let device = try await MTPDevice.discoverFirst()
try await device.connect()
try await device.openSession()

defer {
    try? await device.closeSession()
    try? await device.disconnect()
}

// Perform operations...
```

```swift
// ❌ INCORRECT: Missing cleanup
let device = try await MTPDevice.discoverFirst()
try await device.connect()
try await device.openSession()

// If this fails, session stays open!
```

### Using try/finally

```swift
func withSession<T>(_ body: (MTPDevice) async throws -> T) async throws -> T {
    let device = try await MTPDevice.discoverFirst()
    try await device.connect()
    try await device.openSession()
    
    do {
        return try await body(device)
    } finally {
        try? await device.closeSession()
        try? await device.disconnect()
    }
}

// Usage
let files = try await withSession { device in
    try await device.list(at: "/DCIM")
}
```

### Error Recovery

```swift
func withSessionRetry<T>(
    maxAttempts: Int = 3,
    body: (MTPDevice) async throws -> T
) async throws -> T {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await withSession(body)
        } catch {
            lastError = error
            
            // Only retry on recoverable errors
            guard isRecoverable(error) else {
                throw error
            }
            
            // Wait before retry
            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
        }
    }
    
    throw lastError!
}

func isRecoverable(_ error: Error) -> Bool {
    switch error {
    case is MTPError.connectionFailed,
         is MTPError.timeout:
        return true
    default:
        return false
    }
}
```

## Concurrent Session Management

### Multiple Devices

```swift
class DevicePool {
    private var activeDevices: [String: MTPDevice] = [:]
    private let maxConcurrent = 5
    
    func acquireDevice() async throws -> MTPDevice {
        guard activeDevices.count < maxConcurrent else {
            throw DevicePoolError.tooManyDevices
        }
        
        let device = try await MTPDevice.discoverFirst()
        try await device.connect()
        try await device.openSession()
        
        activeDevices[device.id] = device
        return device
    }
    
    func releaseDevice(_ device: MTPDevice) async {
        try? await device.closeSession()
        try? await device.disconnect()
        activeDevices.removeValue(forKey: device.id)
    }
}
```

### Session Isolation

```swift
// Each device operates in its own session
actor DeviceManager {
    private var sessions: [String: Session] = [:]
    
    func createSession(for deviceId: String) async throws -> Session {
        if let existing = sessions[deviceId] {
            throw SessionError.alreadyExists(deviceId)
        }
        
        let session = try await Session.open(deviceId: deviceId)
        sessions[deviceId] = session
        return session
    }
    
    func closeSession(for deviceId: String) async throws {
        guard let session = sessions[deviceId] else {
            throw SessionError.notFound(deviceId)
        }
        
        try await session.close()
        sessions.removeValue(forKey: deviceId)
    }
}
```

## Session Timeouts

### Configuring Timeouts

```swift
let config = SwiftMTPConfig(
    handshakeTimeoutMs: 10_000,    // 10s for session open
    ioTimeoutMs: 30_000,          // 30s for operations
    stabilizeMs: 500              // 500ms post-open
)

// Apply to device
try await device.connect(config: config)
```

### Timeout Handling

```swift
enum SessionError: Error {
    case timeout
    case invalidState(State)
    case openingFailed(Error)
    case alreadyExists(String)
    case notFound(String)
}

func withTimeout<T>(
    seconds: TimeInterval,
    operation: () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SessionError.timeout
        }
        
        guard let result = try await group.next() else {
            throw SessionError.timeout
        }
        
        group.cancelAll()
        return result
    }
}
```

## Troubleshooting Session Issues

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `SessionError.timeout` | Device not responding | Check USB connection |
| `SessionError.invalidState` | Wrong sequence | Ensure proper open/close |
| `MTPError.sessionFailed` | MTP handshake failed | Check device compatibility |
| `MTPError.deviceNotTrusted` | Trust prompt not accepted | Unlock device, accept prompt |

### Debugging Session State

```swift
// Enable session debugging
let config = SwiftMTPConfig(
    loggingEnabled: true,
    logLevel: .debug
)

// Check session state
print("Session state: \(device.sessionState)")

// Enable verbose logging
// SWIFTMTP_LOG_LEVEL=debug swift run swiftmtp ls
```

## Related Documentation

- [Architecture Overview](architecture.md) - System architecture
- [MTP Protocol](mtp-protocol.md) - Protocol details
- [Transfer Modes](transfer-modes.md) - Data transfer methods
- [Troubleshooting Connection](../howto/troubleshoot-connection.md) - Connection issues

## Summary

Key points about session management:

1. ✅ Sessions follow a defined lifecycle (discover → connect → open → active → close)
2. ✅ Always clean up sessions with defer/finally
3. ✅ Handle errors and implement retry logic
4. ✅ Use timeouts to prevent hangs
5. ✅ Manage concurrent sessions with proper isolation
6. ✅ Log session events for debugging
