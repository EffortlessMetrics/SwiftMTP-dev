# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [Unreleased]

### Added
- File Provider tech preview: XPC service and File Provider extension for Finder integration (macOS)
- Transfer journaling for resumable operations
- Mirror and sync operations with conflict resolution
- Benchmarking capabilities with performance profiling

### Changed
- Thread sanitizer now only runs Core/Index/Scenario tests (Transport excluded due to _AtomicsShims)
- Enhanced error reporting with structured JSON envelopes

### Fixed
- Race conditions in concurrent device operations
- Memory leaks in long-running transfer operations
- USB timeout handling for slow devices

### Security
- Additional input validation for device communications
- Enhanced path traversal protection
- Buffer size bounds checking
