# Logging and Debugging

This guide covers logging configuration and debugging techniques for SwiftMTP.

## Quick Reference

| Feature | Environment Variable | Description |
|---------|-------------------|-------------|
| Verbose output | `SWIFTMTP_VERBOSE=1` | Enable debug logging |
| Trace USB | `SWIFTMTP_TRACE_USB=1` | Log USB operations |
| Trace MTP | `SWIFTMTP_TRACE_MTP=1` | Log MTP protocol |
| File logging | `SWIFTMTP_LOG_FILE` | Log to file |

## Logging Configuration

### Environment Variables

```bash
# Enable verbose logging
export SWIFTMTP_VERBOSE=1

# Enable specific traces
export SWIFTMTP_TRACE_USB=1
export SWIFTMTP_TRACE_MTP=1
export SWIFTMTP_TRACE_TRANSFER=1

# Log to file
export SWIFTMTP_LOG_FILE=/tmp/swiftmtp.log
export SWIFTMTP_LOG_LEVEL=debug
```

### Log Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| `error` | Critical errors only | Production |
| `warn` | Warnings and errors | Production |
| `info` | General information | Default |
| `debug` | Detailed debugging | Development |
| `trace` | Protocol-level tracing | Deep debugging |

## Debugging CLI Issues

### Verbose CLI Output

```bash
# Basic verbose
swift run swiftmtp --verbose ls

# Maximum verbosity
swift run swiftmtp --verbose --debug pull /DCIM/photo.jpg
```

### USB Trace

```bash
# Enable USB tracing
export SWIFTMTP_TRACE_USB=1
swift run swiftmtp probe
```

Sample output:
```
[USB] Found device: 18d1:4ee1 (Google Pixel 7)
[USB] Opening interface 0...
[USB] Claimed interface successfully
[USB] Endpoint: OUT 0x01, IN 0x81
```

### MTP Protocol Trace

```bash
# Enable MTP tracing
export SWIFTMTP_TRACE_MTP=1
swift run swiftmtp ls
```

Sample output:
```
[MTP] >>> OpenSession (sessionId: 1)
[MTP] <<< OpenSession OK
[MTP] >>> GetDeviceInfo
[MTP] <<< GetDeviceInfo: manufacturer=Google, model=Pixel 7
[MTP] >>> GetStorageIDs
[MTP] <<< GetStorageIDs: [0x00010001]
```

## Programmatic Logging

### Using the Logging API

```swift
import SwiftMTPCore
import Logging

// Configure logging
var logger = Logger(label: "com.swiftmtp.app")
logger.logLevel = .debug

// Use in operations
logger.debug("Starting transfer: \(fileName)")
logger.info("Transfer completed: \(bytes) bytes")

// SwiftMTP uses swift-log internally
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(level: .debug)
    return handler
}
```

### Custom Log Handlers

```swift
import Logging

// File-based logging
class FileLogHandler: LogHandler {
    let fileHandle: FileHandle
    
    func log(level: Logger.Level, message: String) {
        let entry = "[\(level)] \(message)\n"
        fileHandle.write(entry.data(using: .utf8)!)
    }
    
    // Required protocol members
    var logLevel: Logger.Level = .info
}

// Configure custom handler
LoggingSystem.bootstrap { label in
    let fileURL = URL(fileURLWithPath: "/tmp/swiftmtp.log")
    let handle = try! FileHandle(forWritingTo: fileURL)
    return FileLogHandler(fileHandle: handle)
}
```

## Debugging Connection Issues

### Connection Debug Mode

```bash
# Full connection debugging
export SWIFTMTP_VERBOSE=1
export SWIFTMTP_TRACE_USB=1
swift run swiftmtp probe --verbose
```

### Device State Inspection

```swift
import SwiftMTPCore

// Inspect device state
let device = try await MTPDevice.discover()

print("Device state:")
print("  Connected: \(device.isConnected)")
print("  Session open: \(device.hasOpenSession)")
print("  USB speed: \(device.usbSpeed)")
print("  Manufacturer: \(device.info.manufacturer)")
print("  Model: \(device.info.model)")
print("  Serial: \(device.info.serialNumber)")
```

### USB Information

```swift
// Get detailed USB info
let usbInfo = device.usbInfo

print("USB Configuration:")
print("  Vendor ID: \(String(format: "0x%04x", usbInfo.vendorId))")
print("  Product ID: \(String(format: "0x%04x", usbInfo.productId))")
print("  Speed: \(usbInfo.speed) Mbps")
print("  Max packet size: \(usbInfo.maxPacketSize)")
```

## Debugging Transfer Issues

### Transfer Debugging

```bash
# Verbose transfer
swift run swiftmtp pull /DCIM/photo.jpg --verbose

# Output:
# [INFO] Connecting to device...
# [INFO] Device: Google Pixel 7
# [DEBUG] Opening session 1
# [DEBUG] Getting handle for /DCIM/photo.jpg
# [DEBUG] Handle: 0x00001234
# [DEBUG] File size: 5242880 bytes
# [DEBUG] Starting transfer...
# [DEBUG] Chunk 1/5: 1048576 bytes @ 45 MB/s
# [DEBUG] Chunk 2/5: 1048576 bytes @ 42 MB/s
# [INFO] Transfer completed: 5.2 MB in 0.12s
```

### Progress Callback Debugging

```swift
import SwiftMTPCore

// Enable transfer callbacks
class DebugTransferMonitor: TransferMonitor {
    func transferStarted(path: String, size: UInt64) {
        print("[DEBUG] Transfer started: \(path) (\(size) bytes)")
    }
    
    func transferProgress(path: String, bytes: UInt64, total: UInt64) {
        let percent = Double(bytes) / Double(total) * 100
        print("[DEBUG] Progress: \(path) - \(Int(percent))%")
    }
    
    func transferCompleted(path: String, duration: TimeInterval) {
        print("[DEBUG] Completed: \(path) in \(duration)s")
    }
    
    func transferFailed(path: String, error: Error) {
        print("[ERROR] Failed: \(path) - \(error)")
    }
}

let device = try await MTPDevice.discover()
device.transferMonitor = DebugTransferMonitor()
```

### Checksum Verification

```bash
# Verify transfer integrity
swift run swiftmtp pull /DCIM/photo.jpg --verify

# Verify with checksum only (faster)
swift run swiftmtp pull /DCIM/photo.jpg --checksum
```

## Debugging Device Quirks

### Quirk Debugging

```bash
# Show applied quirks
swift run swiftmtp quirks --explain

# Output:
# Device: Google Pixel 7 (18d1:4ee1)
# Applied quirks:
#   - chunked_transfer: true (for large files)
#   - no_getpartialobject: false
#   - fallback_ladder: [4MB, 2MB, 1MB]
```

### Testing Quirks

```swift
import SwiftMTPCore

// Create custom configuration
var config = DeviceConfiguration.default

// Override quirks for testing
config.forceChunkedTransfer = true
config.disablePartialObject = false

let device = try await MTPDevice.discover(configuration: config)

// Test with different settings
for chunkSize in [1_048_576, 2_097_152, 4_194_304] {
    config.chunkSize = chunkSize
    let start = Date()
    try await device.read(handle: handle, to: output)
    let duration = Date().timeIntervalSince(start)
    print("Chunk size \(chunkSize): \(duration)s")
}
```

## Debugging with Xcode

### LLDB Commands

```bash
# In LLDB:
# Set breakpoint on error
breakpoint set -name MTPError

# Break on specific error code
breakpoint set -s SwiftMTPCore -o -c 'error.code == 0x2019'

# Log device operations
breakpoint command add -o 'frame var device'
```

### Symbolic Breakpoints

In Xcode:
1. Debug → Breakpoints → Create Symbolic Breakpoint
2. Symbol: `SwiftMTPCore.MTPDevice.transfer`
3. Action: Log "Transfer called"

### Memory Debugging

```swift
// Enable memory debugging
import _Concurrency

// Check for memory leaks
withExtendedLifetime(device) {
    // Perform operations
}

// Monitor memory
print("Memory used: \(currentMemoryUsage()) bytes")
```

## Performance Debugging

### Timing Operations

```swift
import Foundation

// Simple timing
let start = CFAbsoluteTimeGetCurrent()
try await device.read(handle: handle, to: localURL)
let duration = CFAbsoluteTimeGetCurrent() - start
print("Transfer took \(duration)s")

// Detailed profiling
import os.signpost

let signpostID = OSSignpostID(log: .transfer)
os_signpost(.begin, log: .transfer, signpostID: signpostID, "Transfer")

try await device.read(handle: handle, to: localURL)

os_signpost(.end, log: .transfer, signpostID: signpostID, "Transfer")
```

### Throughput Calculation

```swift
import SwiftMTPCore

class ThroughputMonitor {
    private var totalBytes: UInt64 = 0
    private var startTime: CFAbsoluteTime = 0
    
    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
        totalBytes = 0
    }
    
    func addBytes(_ bytes: UInt64) {
        totalBytes += bytes
    }
    
    func report() {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(totalBytes) / duration / 1_000_000
        print("Average throughput: \(String(format: "%.1f", throughput)) MB/s")
    }
}
```

## Debugging Common Issues

### Device Not Found

```bash
# Enable USB tracing
export SWIFTMTP_TRACE_USB=1

# Check device detection
swift run swiftmtp probe --verbose

# Check USB permissions
system_profiler SPUSBDataType
```

### Permission Denied

```bash
# Check entitlements
codesign -dvvv SwiftMTP.app

# Verify sandbox disabled for USB
# (required for IOKit access on macOS)
```

### Timeout Issues

```bash
# Increase timeout
export SWIFTMTP_IO_TIMEOUT_MS=120000

# Trace operations
export SWIFTMTP_TRACE_TRANSFER=1
swift run swiftmtp pull /large-file.mp4 --verbose
```

## Log Analysis

### Common Patterns

| Pattern | Meaning | Solution |
|---------|---------|----------|
| `Timeout waiting for response` | Device slow | Increase timeout |
| `USB error -1` | Connection lost | Check cable |
| `Session expired` | Session timeout | Re-open session |
| `Invalid handle` | Handle stale | Re-list directory |

### Log Collection

```bash
# Collect logs for support
swift run swiftmtp collect --bundle ./support-bundle

# Include verbose logs
export SWIFTMTP_LOG_FILE=./support-bundle/swiftmtp.log
export SWIFTMTP_VERBOSE=1
swift run swiftmtp probe
```

## Best Practices

### Development Settings

```bash
# Development environment
export SWIFTMTP_VERBOSE=1
export SWIFTMTP_LOG_LEVEL=debug
export SWIFTMTP_TRACE_USB=1
export SWIFTMTP_TRACE_MTP=1
export SWIFTMTP_LOG_FILE=/tmp/swiftmtp-dev.log
```

### Production Settings

```bash
# Production environment
export SWIFTMTP_LOG_LEVEL=warn
export SWIFTMTP_IO_TIMEOUT_MS=60000
export SWIFTMTP_MAX_RETRIES=3
```

## Related Documentation

- [Troubleshooting Connection](troubleshoot-connection.md)
- [Device Quirks](device-quirks.md)
- [CLI Commands Reference](../reference/cli-commands.md)
- [Debugging MTP Tutorial](../tutorials/debugging-mtp.md)

## Summary

Debugging techniques covered:

1. ✅ **Environment variables** - Enable verbose/trace logging
2. ✅ **CLI debugging** - Use `--verbose` and trace flags
3. ✅ **Programmatic logging** - Configure swift-log
4. ✅ **Connection debugging** - Inspect device state
5. ✅ **Transfer debugging** - Monitor progress and timing
6. ✅ **Quirk debugging** - Test device configurations
7. ✅ **Performance profiling** - Measure throughput
8. ✅ **Log analysis** - Identify common patterns
