# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SwiftMTP is a macOS/iOS library and tool for interacting with MTP (Media Transfer Protocol) devices over USB. The project uses modern Swift 6 with strict concurrency and actor-based architecture.

## Development Commands

### Building
```bash
# Build all targets (always build from SwiftMTPKit directory)
cd SwiftMTPKit
swift build -v

# Build release version
swift build -c release

# Build XCFramework for libusb (required for initial setup)
./scripts/build-libusb-xcframework.sh
```

### Testing
```bash
# Run all tests with coverage
swift test -v --enable-code-coverage

# Run tests with Thread Sanitizer (excludes USB transport tests)
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# Run a single test
swift test --filter TestName
```

### Running the CLI
```bash
# Run from SwiftMTPKit directory
swift run swiftmtp [command]

# Common commands:
swift run swiftmtp probe          # Discover devices
swift run swiftmtp pull           # Download files
swift run swiftmtp push           # Upload files
swift run swiftmtp snapshot       # Create device snapshot
swift run swiftmtp mirror         # Mirror device content
```

### Code Quality
```bash
# Format code (required before commits)
swift-format -i -r Sources Tests

# Lint code
swift-format lint -r Sources Tests
```

## Architecture

### Package Structure
- **SwiftMTPCore**: Core MTP protocol implementation with `MTPDevice` protocol
- **SwiftMTPTransportLibUSB**: USB transport layer using libusb
- **SwiftMTPIndex**: SQLite-based device content indexing
- **SwiftMTPSync**: Snapshot, diff, and mirror functionality
- **SwiftMTPObservability**: Logging and performance monitoring
- **SwiftMTPXPC**: XPC service for File Provider integration
- **swiftmtp-cli**: Command-line tool

### Key Design Patterns
1. **Actor-based concurrency**: All device operations go through `MTPDeviceActor` for thread safety
2. **Protocol-oriented**: `MTPDevice` protocol allows mock implementations for testing
3. **Async/await**: All I/O operations use Swift concurrency
4. **Transfer journaling**: Automatic resume support via `TransferJournal`

### Important Files and Locations
- Device implementation: `Sources/SwiftMTPCore/LibUSBMTPDevice.swift`
- Actor wrapper: `Sources/SwiftMTPCore/MTPDeviceActor.swift`
- CLI entry point: `Sources/swiftmtp-cli/SwiftMTPCLI.swift`
- Database schema: `Sources/SwiftMTPIndex/Database.swift`
- Mock devices: `Sources/SwiftMTPCore/MockTransport.swift`

### Testing Approach
- Use `MockTransport` for unit tests without real devices
- Mock profiles available: pixel, galaxy, iphone, canon
- Failure scenarios: timeout, busy, disconnected
- Tests use XCTest with async/await support

### Performance Considerations
- Chunk sizes auto-tune from 512KB to 8MB based on device performance
- Use `Benchmark` struct for performance measurements
- Device fingerprinting stores optimal settings in `~/.swiftmtp/device-tuning.json`