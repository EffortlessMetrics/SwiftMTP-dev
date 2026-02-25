# Device Capabilities Reference

Complete reference for MTP device capabilities and how SwiftMTP handles them.

## Capability Types

### Transport Capabilities

| Capability | Description | Detection Method |
|------------|-------------|------------------|
| `usb2` | USB 2.0 High Speed | USB descriptor |
| `usb3` | USB 3.0 SuperSpeed | USB descriptor |
| `wireless` | Wireless MTP | Device info |

### Protocol Capabilities

| Capability | Description | Required For |
|------------|-------------|--------------|
| `mtp` | Basic MTP support | All operations |
| `ptp` | PTP fallback | Legacy devices |
| `getPartialObject64` | Partial reads | Resume support |
| `sendPartialObject` | Partial writes | Large files |
| `deleteObject` | Object deletion | File delete |
| `getObjectPropsSupported` | Property support | Metadata |

### Storage Capabilities

| Capability | Description | Detection |
|------------|-------------|----------|
| `multipleStorage` | Multiple storages | GetStorageIDs |
| `storageInfo` | Storage details | GetStorageInfo |
| `storageDescription` | Named storages | GetStorageInfo |

## Common Device Profiles

### Google Pixel

```
Capabilities:
  - getPartialObject64: Yes
  - sendPartialObject: Yes
  - deleteObject: Yes
  - multipleStorage: Yes (primary + SD card)
  - Transfer: Up to 4MB chunks
```

### Samsung Galaxy

```
Capabilities:
  - getPartialObject64: Yes
  - sendPartialObject: Yes
  - deleteObject: Yes
  - multipleStorage: Yes
  - Transfer: Up to 4MB chunks
  - Notes: May have storage permission issues
```

### OnePlus

```
Capabilities:
  - getPartialObject64: Yes
  - sendPartialObject: Yes  
  - deleteObject: Yes
  - multipleStorage: No (single storage)
  - Transfer: Up to 2MB chunks (slower)
```

### Xiaomi

```
Capabilities:
  - getPartialObject64: No (quirk required)
  - sendPartialObject: No (quirk required)
  - deleteObject: Yes
  - multipleStorage: Yes
  - Transfer: Use 1MB chunks
  - Notes: Requires device quirks
```

## Checking Device Capabilities

### CLI Method

```bash
# Get device info with capabilities
swift run swiftmtp device-info

# Output:
# Manufacturer: Google
# Model: Pixel 7
# Serial: <redacted>
# Version: 1.0
# 
# Capabilities:
#   getPartialObject64: true
#   sendPartialObject: true
#   deleteObject: true
#   multipleStorage: true
```

### Programmatic Method

```swift
import SwiftMTPCore

let device = try await MTPDevice.discover()

// Check capabilities
print("Partial reads: \(device.capabilities.contains(.getPartialObject64))")
print("Partial writes: \(device.capabilities.contains(.sendPartialObject))")
print("Delete: \(device.capabilities.contains(.deleteObject))")

// Check storage
for storage in device.storages {
    print("Storage: \(storage.description)")
    print("  Free: \(storage.freeSpace) bytes")
    print("  Total: \(storage.capacity) bytes")
}
```

## Capability Detection

### Auto-Detection Process

```swift
// SwiftMTP automatically detects capabilities
let device = try await MTPDevice.discover()

// Detection order:
// 1. USB descriptor (speed, vendor, product)
// 2. GetDeviceInfo (manufacturer, model, version)
// 3. GetStorageIDs (storage count)
// 4. GetPartialObject (test partial support)
// 5. Apply quirks from database
```

### Manual Capability Override

```swift
import SwiftMTPCore

var config = DeviceConfiguration()
config.forcePartialObject = true
config.chunkSize = 2 * 1024 * 1024

let device = try await MTPDevice.discover(configuration: config)
```

## Storage Capabilities

### Storage Types

| Type | Description | Access |
|------|-------------|--------|
| `fixed` | Internal storage | Read/Write |
| `removable` | SD card | Read/Write |
| `system` | System partition | Read-only |

### Accessing Storage Info

```bash
# Get storage information
swift run swiftmtp df

# Output:
# Storage: Primary (0x00010001)
#   Type: fixed
#   Used: 45.2 GB
#   Free: 82.8 GB
#   Total: 128 GB
# 
# Storage: SD Card (0x00010002)
#   Type: removable
#   Used: 12.1 GB
#   Free: 59.9 GB
#   Total: 72 GB
```

### Multiple Storage Handling

```swift
import SwiftMTPCore

let device = try await MTPDevice.discover()

// List all storages
for storage in device.storages {
    print("\(storage.description): \(storage.type)")
}

// Access specific storage
let primaryStorage = device.storages.first { $0.isPrimary }
let sdCard = device.storages.first { $0.type == .removable }
```

## Transfer Capabilities

### Chunk Transfer

| Capability | Description | Benefit |
|------------|-------------|---------|
| `chunkedTransfer` | Split large files | Memory efficient |
| `getPartialObject64` | Resume downloads | Recover interrupted |
| `sendPartialObject` | Resume uploads | Large file support |

### Fallback Ladder

When devices don't support optimal transfer:

```swift
// Default fallback ladder
let ladder: [Int] = [
    4_194_304,  // 4 MB
    2_097_152,  // 2 MB
    1_048_576,  // 1 MB
    524_288,    // 512 KB
    262_144     // 256 KB
]

// SwiftMTP automatically tries smaller chunks
// until transfer succeeds
```

### Performance by Capability

These are practical MTP-over-USB transfer speeds observed in real-device testing,
not USB theoretical maximums (USB 3.0 theoretical max is 625 MB/s; MTP protocol
overhead and device firmware limits reduce this significantly).

| Connection | Practical MTP Speed | Max Chunk |
|------------|---------------------|-----------|
| USB 3.0    | 40–80 MB/s          | 4 MB      |
| USB 2.0    | 10–15 MB/s          | 2 MB      |
| Wireless   | 2–5 MB/s            | 1 MB      |

## Object Operations

### Supported Operations

| Operation | Capability | Description |
|-----------|------------|-------------|
| `GetObject` | Required | Read file |
| `GetPartialObject64` | Optional | Resume read |
| `SendObjectInfo` | Required | Prepare upload |
| `SendObject` | Required | Write file |
| `SendPartialObject` | Optional | Resume write |
| `DeleteObject` | Optional | Delete file |
| `GetObjectProps` | Optional | Read metadata |
| `SetObjectProps` | Optional | Write metadata |

### Operation Support Check

```swift
import SwiftMTPCore

let device = try await MTPDevice.discover()

// Check specific operation support
func supportsOperation(_ operation: MTPOperation) -> Bool {
    return device.supportedOperations.contains(operation)
}

print("Delete: \(supportsOperation(.deleteObject))")
print("Partial Read: \(supportsOperation(.getPartialObject64))")
print("Partial Write: \(supportsOperation(.sendPartialObject))")
```

## Device Quirks

### Common Quirk Requirements

| Device | Required Quirk | Reason |
|--------|---------------|--------|
| Xiaomi | `no_getpartialobject` | Doesn't support partial |
| Some Samsung | `chunk_size_limit` | Transfer limit |
| Old devices | `ptp_only` | MTP not supported |

### Applying Quirks

```bash
# View applied quirks
swift run swiftmtp quirks --explain

# Output:
# Device: Google Pixel 7 (18d1:4ee1)
# Applied quirks:
#   chunked_transfer: true
#   fallback_ladder: [4194304, 2097152, 1048576]
```

### Custom Quirk Configuration

```swift
import SwiftMTPCore

// Create custom quirk configuration
var quirks = DeviceQuirks()
quirks.forceChunkedTransfer = true
quirks.disablePartialObject = false
quirks.fallbackLadder = [2_097_152, 1_048_576, 524_288]

let config = DeviceConfiguration(quirks: quirks)
let device = try await MTPDevice.discover(configuration: config)
```

## Capability Errors

### Common Capability Errors

| Error Code | Meaning | Capability Missing |
|------------|---------|-------------------|
| `0x2001` | Operation not supported | Required capability |
| `0x2019` | Partial not supported | `getPartialObject64` |
| `0x201C` | Invalid storage | `multipleStorage` |

### Handling Capability Errors

```swift
import SwiftMTPCore

do {
    // Try optimized transfer
    try await device.read(handle: handle, to: localURL, offset: resumeOffset)
} catch MTPError.operationNotSupported {
    // Fall back to full download
    print("Device doesn't support partial, downloading full file")
    try await device.read(handle: handle, to: localURL)
}
```

## Related Documentation

- [Device Quirks](quirks-schema.md)
- [Transfer Modes Explanation](../explanation/transfer-modes.md)
- [CLI Commands](cli-commands.md)
- [Device Quirks How-To](../howto/device-quirks.md)
