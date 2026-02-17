# Events Reference

Complete reference for all SwiftMTP event types and handling.

## Event System Overview

SwiftMTP uses an event-driven architecture. Events notify your application about device state changes, transfer progress, and errors.

## Event Types

### Device Events

Events related to device connection and state.

#### DeviceConnected

Fired when a device is connected and recognized.

```swift
struct DeviceConnectedEvent: MTPEvent {
    let deviceId: String
    let vendorId: UInt16
    let productId: UInt16
    let manufacturer: String
    let model: String
    let serial: String?
}
```

#### DeviceDisconnected

Fired when a device is disconnected.

```swift
struct DeviceDisconnectedEvent: MTPEvent {
    let deviceId: String
    let reason: DisconnectReason
}

enum DisconnectReason {
    case userRequested
    case deviceRemoved
    case error(Error)
    case sessionExpired
}
```

#### DeviceStateChanged

Fired when device state changes.

```swift
struct DeviceStateChangedEvent: MTPEvent {
    let deviceId: String
    let previousState: DeviceState
    let newState: DeviceState
}

enum DeviceState {
    case discovered
    case connecting
    case enumerating
    case ready
    case transferring
    case error(DeviceError)
}
```

### Transfer Events

Events related to file transfers.

#### TransferStarted

Fired when a transfer begins.

```swift
struct TransferStartedEvent: MTPEvent {
    let transferId: UUID
    let direction: TransferDirection
    let sourcePath: String
    let destinationPath: String
    let totalBytes: UInt64
}

enum TransferDirection {
    case download
    case upload
}
```

#### TransferProgress

Fired periodically during transfer.

```swift
struct TransferProgressEvent: MTPEvent {
    let transferId: UUID
    let bytesTransferred: UInt64
    let totalBytes: UInt64
    let bytesPerSecond: Double
    
    var progress: Double {
        Double(bytesTransferred) / Double(totalBytes)
    }
}
```

#### TransferCompleted

Fired when transfer completes successfully.

```swift
struct TransferCompletedEvent: MTPEvent {
    let transferId: UUID
    let bytesTransferred: UInt64
    let duration: Duration
    let checksum: String?
}
```

#### TransferFailed

Fired when transfer fails.

```swift
struct TransferFailedEvent: MTPEvent {
    let transferId: UUID
    let error: TransferError
    let bytesTransferred: UInt64
    let canResume: Bool
}

enum TransferError: Error {
    case deviceError(MTPError)
    case timeout
    case checksumMismatch
    case storageFull
    case permissionDenied
    case cancelled
}
```

### Session Events

Events related to MTP session management.

#### SessionOpened

```swift
struct SessionOpenedEvent: MTPEvent {
    let deviceId: String
    let sessionId: UInt32
}
```

#### SessionClosed

```swift
struct SessionClosedEvent: MTPEvent {
    let deviceId: String
    let sessionId: UInt32
    let reason: SessionCloseReason
}

enum SessionCloseReason {
    case normal
    case error
    case deviceReset
}
```

### Storage Events

Events related to storage detection.

#### StorageDetected

```swift
struct StorageDetectedEvent: MTPEvent {
    let deviceId: String
    let storageId: UInt32
    let name: String
    let totalSpace: UInt64
    let freeSpace: UInt64
}
```

#### StorageChanged

```swift
struct StorageChangedEvent: MTPEvent {
    let deviceId: String
    let storageId: UInt32
    let freeSpace: UInt64
}
```

## Subscribing to Events

### Using AsyncStream

```swift
import SwiftMTPCore

// Subscribe to all device events
for await event in device.events {
    switch event {
    case let e as DeviceConnectedEvent:
        print("Connected: \(e.model)")
    case let e as DeviceDisconnectedEvent:
        print("Disconnected: \(e.deviceId)")
    case let e as TransferProgressEvent:
        print("Progress: \(e.progress * 100)%")
    default:
        break
    }
}
```

### Using Callbacks

```swift
import SwiftMTPCore

// Subscribe to specific event types
device.onEvent(DeviceConnectedEvent.self) { event in
    print("Device connected: \(event.model)")
}

device.onEvent(TransferProgressEvent.self) { event in
    updateProgressBar(event.progress)
}
```

### Using Combine

```swift
import SwiftMTPCore
import Combine

let cancellable = device.eventPublisher
    .filter { $0 is TransferProgressEvent }
    .sink { event in
        let progress = event as! TransferProgressEvent
        print("Progress: \(progress.progress)")
    }
```

## Event Filtering

### Filter by Type

```swift
// Only transfer events
let transferEvents = device.events
    .filter { $0 is TransferEvent }

// Only download events
let downloads = device.events
    .compactMap { $0 as? TransferStartedEvent }
    .filter { $0.direction == .download }
```

### Filter by Device

```swift
// Events for specific device
let deviceEvents = eventStream
    .filter { $0.deviceId == targetDeviceId }
```

## Event History

### Access Recent Events

```swift
// Get last 100 events
let recentEvents = device.eventHistory

// Get events since specific time
let events = device.eventsSince(Date().addingTimeInterval(-60))
```

### Event Replay

```swift
// Replay event history
for event in device.eventHistory.reversed() {
    handleEvent(event)
}
```

## Custom Events

### Defining Custom Events

```swift
struct CustomEvent: MTPEvent, Codable {
    static let type: EventType = "custom.event"
    
    let deviceId: String
    let customData: String
}
```

### Publishing Custom Events

```swift
// From device
device.publish(CustomEvent(
    deviceId: device.id,
    customData: "my data"
))

// Subscribe to custom events
for await event in device.events {
    if event is CustomEvent {
        handleCustomEvent(event as! CustomEvent)
    }
}
```

## Event Best Practices

### Memory Management

```swift
class DeviceManager {
    private var subscriptions: [AnyCancellable] = []
    
    func subscribe(to device: MTPDevice) {
        // Store subscription
        device.eventPublisher
            .sink { ... }
            .store(in: &subscriptions)
    }
    
    deinit {
        subscriptions.removeAll()
    }
}
```

### Error Handling

```swift
for await event in device.events {
    do {
        try handleEvent(event)
    } catch {
        print("Event handling failed: \(error)")
    }
}
```

## Event Flow Diagram

```
USB Plug
    │
    ▼
DeviceDiscovered
    │
    ▼
DeviceConnecting
    │
    ▼
SessionOpening ────► SessionOpened
    │                    │
    ▼                    ▼
DeviceReady ◄──────────┘
    │
    ├──► TransferStarted
    │         │
    │         ▼
    │    TransferProgress (repeated)
    │         │
    │         ▼
    │    TransferCompleted / TransferFailed
    │
    ▼
DeviceDisconnected
```

## Related Documentation

- [API Overview](api-overview.md)
- [Configuration Reference](configuration.md)
- [Architecture Overview](../explanation/architecture.md)

## Summary

This reference covers:

1. ✅ Device events (connection, state changes)
2. ✅ Transfer events (start, progress, complete, fail)
3. ✅ Session events (open, close)
4. ✅ Storage events
5. ✅ Event subscription patterns
6. ✅ Event filtering and history
7. ✅ Custom events