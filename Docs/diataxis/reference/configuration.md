# Configuration Reference

Complete reference for all SwiftMTP configuration options.

## Configuration Sources

SwiftMTP can be configured through multiple sources (in order of precedence):

1. **Environment variables** - Highest priority
2. **Runtime configuration** - Programmatic setup
3. **Configuration files** - Persistent settings

## Environment Variables

### General Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_LOG_LEVEL` | String | `info` | Log level: error, warn, info, debug, trace |
| `SWIFTMTP_CONFIG_PATH` | Path | `./config.json` | Path to configuration file |
| `SWIFTMTP_REAL_ONLY` | Bool | `false` | Fail if no real device connected |

### Connection Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_IO_TIMEOUT_MS` | Int | `15000` | Transfer operation timeout (ms) |
| `SWIFTMTP_HANDSHAKE_TIMEOUT_MS` | Int | `10000` | Session open timeout (ms) |
| `SWIFTMTP_RETRY_COUNT` | Int | `3` | Number of retries for failed operations |
| `SWIFTMTP_RETRY_DELAY_MS` | Int | `1000` | Delay between retries (ms) |

### Transfer Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_CHUNK_SIZE` | Int | `4194304` | Transfer chunk size (bytes) |
| `SWIFTMTP_BUFFER_SIZE` | Int | `65536` | I/O buffer size (bytes) |
| `SWIFTMTP_PARALLEL_TRANSFERS` | Int | `4` | Max parallel transfers |
| `SWIFTMTP_VERIFY_CHECKSUM` | Bool | `false` | Verify transfer integrity |

### Quirks Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_QUIRKS_PATH` | Path | `./Specs/quirks.json` | Path to quirks file |
| `SWIFTMTP_DISABLE_ALL_QUIRKS` | Bool | `false` | Disable all quirks |
| `SWIFTMTP_TEST_QUIRK_*` | Any | - | Test specific quirk value |

### USB Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_USB_SCAN_INTERVAL_MS` | Int | `1000` | Device scan interval |
| `SWIFTMTP_USB_CLAIM_TIMEOUT_MS` | Int | `5000` | Interface claim timeout |

### File Provider Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `SWIFTMTP_FILEPROVIDER_CACHE_SIZE` | Int | `524288000` | Cache size (bytes) |
| `SWIFTMTP_FILEPROVIDER_LOG` | String | `info` | File Provider log level |

## Programmatic Configuration

### MTPDevice Configuration

```swift
import SwiftMTPCore

let config = MTPDevice.Configuration(
    timeout: .milliseconds(15000),
    handshakeTimeout: .milliseconds(10000),
    retryCount: 3,
    chunkSize: 4 * 1024 * 1024,
    bufferSize: 64 * 1024,
    verifyChecksum: false
)

let device = try await MTPDevice(
    summary: deviceSummary,
    configuration: config
)
```

### TransferConfiguration

```swift
import SwiftMTPCore

let transferConfig = TransferConfiguration(
    chunkSize: 4 * 1024 * 1024,
    timeout: .seconds(30),
    retryCount: 3,
    retryDelay: .seconds(2),
    backoffMultiplier: 2.0,
    verifyChecksum: true,
    parallelTransfers: 4
)
```

### DeviceActor.Configuration

```swift
let actorConfig = DeviceActor.Configuration(
    sessionTimeout: .seconds(60),
    maxConcurrentOperations: 10,
    operationQueue: .global(qos: .userInitiated)
)
```

## Configuration Files

### Main Configuration (config.json)

```json
{
  "device": {
    "timeoutMs": 15000,
    "handshakeTimeoutMs": 10000,
    "retryCount": 3
  },
  "transfer": {
    "chunkSize": 4194304,
    "bufferSize": 65536,
    "verifyChecksum": false,
    "parallelTransfers": 4
  },
  "logging": {
    "level": "info",
    "components": {
      "device": "debug",
      "transfer": "debug",
      "usb": "warn"
    }
  },
  "quirks": {
    "enabled": true,
    "path": "./Specs/quirks.json"
  }
}
```

### Quirks Configuration (quirks.json)

```json
{
  "devices": [
    {
      "vid": "0x18d1",
      "pid": "0x4ee1",
      "description": "Google Pixel 7",
      "quirks": {
        "maxChunkBytes": 2097152,
        "handshakeTimeoutMs": 20000,
        "ioTimeoutMs": 30000,
        "stabilizeMs": 2000
      }
    }
  ]
}
```

## Configuration Structures

### MTPDevice.Configuration

```swift
public struct Configuration: Sendable {
    public var timeout: Duration
    public var handshakeTimeout: Duration
    public var retryCount: Int
    public var chunkSize: Int
    public var bufferSize: Int
    public var verifyChecksum: Bool
}
```

### TransferConfiguration

```swift
public struct TransferConfiguration: Sendable {
    public var chunkSize: Int
    public var timeout: Duration
    public var retryCount: Int
    public var retryDelay: Duration
    public var backoffMultiplier: Double
    public var verifyChecksum: Bool
    public var parallelTransfers: Int
}
```

### FileProviderConfiguration

```swift
public struct FileProviderConfiguration: Sendable {
    public var maxCacheSize: Int
    public var backgroundIndexEnabled: Bool
    public var prefetchEnabled: Bool
}
```

## Default Values

### Connection Timeouts

| Operation | Default |
|-----------|---------|
| Session open | 10 seconds |
| Session close | 5 seconds |
| I/O operation | 15 seconds |
| USB claim | 5 seconds |

### Transfer Defaults

| Parameter | Default |
|-----------|---------|
| Chunk size | 4 MB |
| Buffer size | 64 KB |
| Max parallel | 4 |
| Retry count | 3 |

## Loading Configuration

### From Environment

```swift
import SwiftMTPCore

// Environment variables are loaded automatically
let config = try await MTPDevice.Configuration.fromEnvironment()
```

### From File

```swift
// Load from custom path
let config = try await MTPDevice.Configuration.load(
    from: "/path/to/config.json"
)
```

### Merging Configurations

```swift
// Environment overrides file, runtime overrides all
let finalConfig = MTPDevice.Configuration
    .loadFromFile()
    .merged(with: MTPDevice.Configuration.fromEnvironment())
    .merged(with: runtimeConfig)
```

## Validation

Configuration values are validated on load:

```swift
do {
    let config = try MTPDevice.Configuration(
        timeout: .milliseconds(100), // Too short!
        chunkSize: 1024 * 1024 * 1024 // 1GB - too large!
    )
} catch {
    // ConfigurationError.invalidValue
}
```

## Related Documentation

- [Events Reference](events.md)
- [Device Quirks Explanation](../explanation/device-quirks.md)
- [CLI Commands Reference](cli-commands.md)

## Summary

This reference covers:

1. ✅ Environment variable configuration
2. ✅ Programmatic configuration
3. ✅ Configuration file formats
4. ✅ Configuration structures
5. ✅ Default values
6. ✅ Configuration loading and merging