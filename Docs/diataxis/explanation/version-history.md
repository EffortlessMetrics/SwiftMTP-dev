# Version History

This document covers SwiftMTP version history, notable changes, and migration guides.

## Version Overview

| Version | Release Date | Status |
|---------|--------------|--------|
| 1.0.0 | 2024-01-15 | Current |
| 0.9.0 | 2023-09-01 | Legacy |
| 0.8.0 | 2023-05-15 | Legacy |

## 1.0.0 (Current)

### New Features

- **Parallel Transfers**: Multiple concurrent transfers (up to 16)
- **Resume Support**: Partial object transfer for interrupted downloads
- **Device Quirks**: Automatic device-specific configuration
- **File Provider**: macOS Finder integration
- **CLI Improvements**: JSON output, better error messages

### Breaking Changes

| Change | Migration |
|--------|------------|
| Package renamed to `SwiftMTPCore` | Update imports |
| `Device` renamed to `MTPDevice` | Rename in code |
| Error codes changed | Update error handling |
| CLI commands restructured | Update scripts |

### Migration from 0.9.x

```swift
// Old API (0.9.x)
import SwiftMTP

let device = try Device.connect()
try device.download(path: "/file.jpg", to: localURL)

// New API (1.0.0)
import SwiftMTPCore

let device = try await MTPDevice.discover()
try await device.read(handle: "/file.jpg", to: localURL)
```

### Environment Variable Changes

| Old | New | Notes |
|-----|-----|-------|
| `SWIFTMTP_TIMEOUT` | `SWIFTMTP_IO_TIMEOUT_MS` | Milliseconds now |
| `SWIFTMTP_CHUNKSIZE` | `SWIFTMTP_CHUNK_SIZE` | Underscore format |
| `SWIFTMTP_DEBUG` | `SWIFTMTP_VERBOSE` | Renamed |

## 0.9.0

### New Features

- Basic MTP support
- USB device discovery
- File transfer operations
- CLI tool

### Known Issues

- No resume support
- Limited device compatibility
- No quirks system

## 0.8.0

### New Features

- Initial release
- PTP protocol support
- Basic file listing

### Known Issues

- USB issues on macOS
- Limited to PTP devices only
- No CLI tool

## Migration Guide

### From 0.9.x to 1.0.0

#### Import Changes

```swift
// Old
import SwiftMTP

// New
import SwiftMTPCore
```

#### Connection

```swift
// Old
let device = try Device.connect()

// New
let device = try await MTPDevice.discover()
```

#### File Operations

```swift
// Old
try device.download(path: "/file.jpg", to: localURL)
try device.upload(from: localURL, to: "/folder/")

// New
try await device.read(handle: "/file.jpg", to: localURL)
try await device.write(fileURL: localURL, to: "/folder/")
```

#### Error Handling

```swift
// Old
catch DeviceError.notFound {
    // Handle
}

// New
catch MTPError.deviceNotFound {
    // Handle
}

catch MTPError.transferFailed(let code, let details) {
    print("Error \(code): \(details)")
}
```

### CLI Migration

```bash
# Old commands
swiftmtp ls /DCIM
swiftmtp get /file.jpg
swiftmtp put ~/file.jpg

# New commands
swift run swiftmtp ls /DCIM
swift run swiftmtp pull /file.jpg
swift run swiftmtp push ~/file.jpg
```

### Configuration Migration

```bash
# Old
export SWIFTMTP_TIMEOUT=30

# New
export SWIFTMTP_IO_TIMEOUT_MS=30000
```

## Feature Deprecations

### Deprecated in 1.0.0

| Feature | Deprecated | Removal |
|---------|-----------|---------|
| `Device.connectSync()` | 1.0.0 | 2.0.0 |
| PTP-only mode | 1.0.0 | 2.0.0 |
| Old error codes | 1.0.0 | 2.0.0 |

### Future Deprecations

| Feature | Planned | Notes |
|---------|---------|-------|
| Callback-based API | 1.1.0 | Async/await preferred |
| Legacy CLI format | 2.0.0 | Use JSON |

## Version Compatibility

### Swift Version Support

| SwiftMTP | Swift | Xcode |
|----------|-------|-------|
| 1.0.x | 5.9+ | 15.0+ |
| 0.9.x | 5.7+ | 14.0+ |
| 0.8.x | 5.6+ | 13.0+ |

### Platform Support

| Platform | 1.0.x | 0.9.x |
|----------|-------|-------|
| macOS 13+ | ✅ | ✅ |
| macOS 12 | ✅ | ✅ |
| iOS 16+ | ✅ | ✅ |
| iOS 15 | ✅ | ✅ |
| Catalyst | ✅ | ✅ |

## Changelog Format

Entries use semantic versioning:

- **Added**: New features
- **Changed**: Existing behavior changes
- **Deprecated**: Soon-to-be-removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security-related changes

## Reporting Issues

When reporting version-specific issues:

1. Note SwiftMTP version: `swift run swiftmtp --version`
2. Note Swift version: `swift --version`
3. Note platform: `uname -a`
4. Include relevant logs

```bash
# Get version info
swift run swiftmtp --version

# Get detailed diagnostics
export SWIFTMTP_VERBOSE=1
swift run swiftmtp probe --verbose
```

## Related Documentation

- [Migration Guide](../../MigrationGuide.md)
- [CLI Commands Reference](cli-commands.md)
- [API Overview](api-overview.md)
