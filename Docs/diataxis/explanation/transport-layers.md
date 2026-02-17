# Understanding Transport Layers

This document explains the transport layers that SwiftMTP uses to communicate with MTP devices.

## Overview

SwiftMTP supports multiple transport mechanisms for device communication. The transport layer is abstracted, allowing different underlying technologies.

## Transport Architecture

```
┌─────────────────────────────────────────────┐
│              SwiftMTPCore                    │
│            (MTP Protocol Layer)              │
├─────────────────────────────────────────────┤
│              Transport Layer                 │
│  ┌──────────────┐  ┌──────────────┐        │
│  │   USB/IOKit  │  │    Future    │        │
│  │  Transport   │  │  Transports  │        │
│  └──────────────┘  └──────────────┘        │
├─────────────────────────────────────────────┤
│              Physical Layer                  │
│           USB Hardware/Bus                   │
└─────────────────────────────────────────────┘
```

## USB Transport (Current)

The primary transport uses USB via IOKit framework.

### How USB Transport Works

1. **Device Discovery**
   - IOKit enumerates USB devices
   - Filters for MTP device class
   - Creates device summaries

2. **Interface Claiming**
   - Selects MTP interface
   - Claims endpoints (bulk in/out, interrupt)
   - Configures USB session

3. **Data Transfer**
   - Bulk transfers for data
   - Control transfers for commands
   - Interrupt for events

### USB Endpoint Types

| Endpoint | Direction | Type | Purpose |
|----------|-----------|------|---------|
| Control | In/Out | Control | MTP commands |
| Bulk In | In | Bulk | Data from device |
| Bulk Out | Out | Bulk | Data to device |
| Interrupt | In | Interrupt | Event notifications |

### USB Transfer Flow

```
┌──────────┐      ┌───────────┐      ┌──────────┐
│  Host    │ ───▶ │  Control  │ ───▶ │ Device   │
│ Request  │      │ Transfer  │      │          │
└──────────┘      └───────────┘      └──────────┘
                          │
                          ▼
                   ┌───────────┐
                   │  Response │
                   └───────────┘
                          │
                          ▼
┌──────────┐      ┌───────────┐      ┌──────────┐
│  Data    │ ◀─── │   Bulk    │ ◀─── │ Device   │
│ Response │      │ Transfer  │      │          │
└──────────┘      └───────────┘      └──────────┘
```

## IOKit Integration

SwiftMTP uses IOKit for low-level USB access.

### Device Enumeration

```swift
import IOKit
import IOKit.usb

// IOKit notification for device changes
let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
let notification = IOServiceAddMatchingNotification(
    kIOMasterPortDefault,
    kIOFirstMatchNotification,
    matchingDict,
    deviceCallback,
    context,
    &notificationPort
)
```

### Interface Selection

```swift
// Find MTP interface
let interfaceNumber: UInt8 = 0
let alternateSetting: UInt8 = 0

// Claim interface
let result = USBDeviceInterface.ClaimInterface(
    interface: interface,
    force: false
)
```

### Transfer Operations

```swift
// Bulk write
try await usbTransport.bulkWrite(
    data: commandData,
    endpoint: bulkOutEndpoint,
    timeout: .seconds(10)
)

// Bulk read
let response = try await usbTransport.bulkRead(
    endpoint: bulkInEndpoint,
    size: 4096,
    timeout: .seconds(30)
)
```

## Transport Protocols

### USB Protocol Structure

```
┌────────────────────────────────────────────┐
│                 USB Layer                   │
├────────────────────────────────────────────┤
│  USB Request Block (URB)                   │
├────────────────────────────────────────────┤
│  PTP/MTP Packet                            │
│  ┌────────────────────────────────────┐   │
│  │ Container Header (12 bytes)        │   │
│  │ - Type (4 bytes)                   │   │
│  │ - Code (2 bytes)                   │   │
│  │ - Transaction ID (4 bytes)         │   │
│  │ - Payload Length (4 bytes)         │   │
│  ├────────────────────────────────────┤   │
│  │ Payload Data                       │   │
│  └────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

### Packet Types

| Type | Value | Description |
|------|-------|-------------|
| Operation Request | 0x01 | Command to device |
| Operation Response | 0x02 | Response from device |
| Event | 0x03 | Async event from device |
| Start Packet | 0x04 | Start of data packet |
| Data Packet | 0x05 | Data payload |
| Cancel Packet | 0x06 | Cancel operation |

## Alternative Transport Layers

Future transport implementations could include:

### Bluetooth (Future)

```swift
// Conceptual Bluetooth transport
class BluetoothTransport: MTPTransport {
    func connect(to device: BluetoothDevice) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
}
```

### Network (Future)

```swift
// Conceptual network transport
class NetworkTransport: MTPTransport {
    func connect(to endpoint: URL) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
}
```

## Transport Comparison

| Transport | Speed | Availability | Use Case |
|-----------|-------|--------------|----------|
| USB/IOKit | Fast (480 Mbps+) | Current | Direct device |
| Bluetooth | Slow | Future | Wireless |
| Network | Variable | Future | Remote |

## Transport Selection

SwiftMTP automatically selects the appropriate transport:

```swift
// Automatic transport selection
let device = try await MTPDeviceManager.shared
    .openDevice(
        summary: deviceSummary,
        transportPreference: .auto // .usb, .bluetooth, .network
    )
```

## Error Handling

Transport errors are wrapped:

```swift
enum TransportError: Error {
    case notFound
    case notConnected
    case claimFailed(OSStatus)
    case transferFailed(OSStatus)
    case timeout
    case invalidResponse
    case unsupportedTransport
}
```

## Performance Considerations

### USB Version

| Version | Max Speed | Practical Speed |
|---------|-----------|-----------------|
| USB 2.0 | 480 Mbps | ~280 Mbps |
| USB 3.0 | 5 Gbps | ~3 Gbps |
| USB 3.1 | 10 Gbps | ~7 Gbps |

### Endpoint Performance

- **High-speed endpoints** (480 Mbps) - Best for transfers
- **Full-speed endpoints** (12 Mbps) - Slower, older devices
- **Interrupt endpoints** - Used sparingly for events

### Latency

| Operation | Typical Latency |
|-----------|-----------------|
| Control transfer | 1-5 ms |
| Bulk transfer (start) | 1-3 ms |
| Bulk transfer (per chunk) | 0.5-2 ms |

## Related Documentation

- [Transfer Modes Explained](transfer-modes.md)
- [MTP Protocol](mtp-protocol.md)
- [Architecture Overview](architecture.md)

## Summary

This document covered:

1. ✅ Transport layer architecture
2. ✅ USB/IOKit transport implementation
3. ✅ USB endpoint types and transfers
4. ✅ Protocol packet structure
5. ✅ Future transport possibilities
6. ✅ Performance characteristics