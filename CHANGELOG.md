# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-02-08

### Added

- macOS Tahoe 26 native support with SwiftPM 6.2+
- iOS 26 support
- macOS Tahoe 26 Guide documentation
- Swift 6.2 toolchain with latest concurrency features

### Changed

- Minimum platform: macOS 15 / iOS 18 deprecated; macOS 26 / iOS 26 required
- Swift 6 native with full actor isolation and strict concurrency
- IOUSBHost framework adopted as primary USB interface
- All DocC documentation updated with correct metadata syntax

### Removed

- macOS 15 backward compatibility
- Legacy USB entitlements (simplified to modern model)

### Documentation

- New comprehensive macOS Tahoe 26 Guide
- Main SwiftMTP.md documentation refreshed
- Device Tuning Guide with corrected metadata

## [1.1.0] - 2026-02-07

### Added

- File Provider Integration: XPC service and extension for Finder sidebar
- Transfer Journaling: Resumable operations with automatic recovery
- Mirror & Sync: Bidirectional synchronization with conflict resolution
- Benchmarking Suite: Performance profiling with p50/p95 metrics
- OnePlus 3T support with experimental quirk entry
- Storybook Mode: Interactive CLI demo with simulated devices

### Changed

- Unified Swift Package with modular targets
- Thread Sanitizer runs only Core/Index/Scenario tests
- Structured JSON error envelopes with enhanced context
- Improved USB enumeration with fallback handling

### Fixed

- Race conditions via actor isolation
- Memory leaks in long-running transfers
- USB timeouts for slow devices with adaptive backoff
- Trust prompt workflow on macOS

### Performance

- Chunk auto-tuning: 512KB–8MB dynamic adjustment
- Batch operations for large file throughput
- SQLite indexing optimization

## [1.0.2] - 2025-09-07

### Fixed

- Events/delete/move commands use shared DeviceOpen.swift
- Events exits correctly with code 69 when no device present

### Notes

- Supersedes v1.0.1 artifacts; no API changes

## [1.0.1] - 2025-09-03

### Fixed

- Events command crash resolved with proper device enumeration
- Unified device open across delete, move, events commands

### Behavior

- Standardized exit codes: 64 (usage), 69 (unavailable), 70 (software)
- JSON outputs include schemaVersion, timestamp, event.code, event.parameters

### Compatibility

- No API changes; patch release is safe to adopt

## [1.0.0] - 2025-01-09

### Added

- Privacy-safe collect: Read-only device data collection
- Device quirks system with learned profiles and static entries
- Targeting flags: --vid/--pid/--bus/--address
- Core operations: probe, storages, ls, events, delete, move
- Version command with --version [--json] and build info
- Cross-platform support: macOS (Intel/Apple Silicon) and Linux
- Homebrew tap installation
- SBOM generation with SPDX format
- Comprehensive test suite with CI validation
- DocC documentation for devices and API

### Reliability

- Layered timeouts: I/O, handshake, inactivity
- Xiaomi stabilization with backoff and retry
- TTY guard for non-interactive environments
- Standardized exit codes

### Docs & CI

- DocC device pages generated from quirks.json
- CI pipeline with smoke tests and quirks validation
- Evidence gates for reliability (≥12.0 MB/s read, ≥10.0 MB/s write)

### Security

- HMAC-SHA256 redaction for serial numbers
- Input validation for device communications
- Atomic file operations
- Path traversal protection

### Changed

- API stabilization with internal implementation details
- JSON schema versioning in all outputs
- Build system with auto-generated BuildInfo.swift

### Security

## [v1.1.0] – 2026-02-07

### Added
- **File Provider Integration**: XPC service and File Provider extension for native Finder integration (macOS)
- **Transfer Journaling**: Resumable operations with automatic recovery from interruptions
- **Mirror & Sync**: Bidirectional synchronization with conflict resolution strategies
- **Benchmarking Suite**: Performance profiling with p50/p95 metrics and device tuning recommendations
- **OnePlus 3T Support**: New device quirk entry with experimental tuning (VID: 0x2A70, PID: 0xF003)
- **Storybook Mode**: Interactive CLI demo with simulated hardware profiles (Pixel 7, Galaxy, iPhone, Canon)

### Changed
- **Package Structure**: Unified Swift Package with modular targets (SwiftMTPCore, SwiftMTPUI, SwiftMTPIndex, SwiftMTPSync)
- **Thread Sanitizer**: Updated to run only Core/Index/Scenario tests (Transport excluded due to _AtomicsShims)
- **Error Reporting**: Structured JSON envelopes with enhanced error context
- **Device Discovery**: Improved USB enumeration with better fallback handling

### Fixed
- **Race Conditions**: Resolved concurrent device operation conflicts using actor isolation
- **Memory Management**: Fixed leaks in long-running transfer operations
- **USB Timeouts**: Enhanced handling for slow devices with adaptive backoff
- **Device Trust**: Improved workflow for macOS "Trust this computer" authorization prompts

### Security
- **Input Validation**: Comprehensive validation for all device communications
- **Path Traversal**: Enhanced protection against malicious file paths
- **Buffer Safety**: Explicit bounds checking for all buffer operations
- **HMAC Redaction**: Cryptographic hashing of serial numbers in logs

### Performance
- **Chunk Auto-tuning**: Dynamic chunk size adjustment (512KB–8MB) based on device performance
- **Batch Operations**: Improved throughput for large file operations
- **SQLite Indexing**: Optimized queries for device content enumeration

## [v1.0.2] – 2025-09-07

### Fixed
- Packaging/CLI: Ensures `events/delete/move` use shared `DeviceOpen.swift`. `events` correctly exits `69` when no device is present (no crash).

### Notes
- Supersedes v1.0.1 artifacts; no API changes.

## [v1.0.1] – 2025-09-03

### Fixed
- `events`: crash on invocation resolved. Implements proper device enumeration, filtering, and event stream.
- Unified device open across `delete`, `move`, `events` using `DeviceOpen.swift`. Consistent error handling & spinner behavior.

### Behavior
- Standardized exit codes: `64` (usage), `69` (unavailable/no matching device), `70` (software error).
- JSON outputs include `schemaVersion`, `timestamp`, `event.code`, `event.parameters`.

### Compatibility
- No API changes; patch release is safe to adopt.

## [1.0.0] - 2025-01-09

### Added
- **Privacy-safe `collect`**: Read-only device data collection with strict defaults; JSON-first CLI.
- **Device quirks system**: Learned profiles and static quirks for device-specific handling; `quirks --explain`.
- **Targeting flags**: `--vid/--pid/--bus/--address` for precise device selection.
- **Core operations**: `probe`, `storages`, `ls`, `events`, `delete`, `move` with comprehensive error handling.
- **Version command**: `--version [--json]` with build info, git SHA, and schema version.
- **Cross-platform support**: macOS (Intel/Apple Silicon) and Linux builds.
- **Homebrew tap**: Easy installation via `brew install swiftmtp`.
- **SBOM generation**: Supply chain transparency with SPDX SBOM files.
- **Comprehensive test suite**: Unit, integration, and scenario tests with CI validation.
- **DocC documentation**: Device-specific tuning guides and API documentation.

### Reliability
- **Layered timeouts**: I/O, handshake, and inactivity timeouts with device-specific tuning.
- **Xiaomi stabilization**: Backoff and retry logic for Xiaomi device compatibility.
- **TTY guard**: Spinner UI that gracefully handles non-interactive environments.
- **Exit codes**: Standardized exit codes (0=ok, 64=usage, 69=unavailable, 70=software, 75=tempfail).

### Docs & CI
- **DocC device pages**: Generated from `Specs/quirks.json` with device-specific tuning information.
- **CI pipeline**: smoke tests, quirks validation, multi-platform builds, and release automation.
- **Evidence gates**: Bench gates ensure reliability before quirk application (≥12.0 MB/s read, ≥10.0 MB/s write).

### Security
- **HMAC-SHA256 redaction**: Serial numbers and sensitive data are redacted using cryptographic hashing.
- **Input validation**: All device communications validated against schemas.
- **Atomic operations**: File operations prevent partial writes and race conditions.
- **Path traversal protection**: Safe handling of device file system paths.

### Changed
- **API stabilization**: Implementation details made internal for v1.0 stability.
- **JSON schema versioning**: All outputs include `schemaVersion: "1.0.0"` and structured metadata.
- **Build system**: Integrated build info generation with auto-generated `BuildInfo.swift`.

### Fixed
- N/A (initial stable release)

### Security
- **No personal data collection**: Device submissions contain only technical compatibility data.
- **Safe defaults**: All operations default to conservative, privacy-preserving settings.
- **Transparent provenance**: Full SBOM and build attestation for supply chain security.
