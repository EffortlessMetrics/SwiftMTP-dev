# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial public release of SwiftMTP
- MTP (Media Transfer Protocol) support for USB devices
- Device discovery and enumeration
- File transfer capabilities with resume support
- Index-based device browsing and synchronization
- CLI tool (`swiftmtp`) for command-line operations
- Comprehensive test suite with Core, Index, Transport, and Scenario tests
- Thread sanitizer support for race condition detection
- SBOM generation for security transparency
- **File Provider tech preview**: XPC service and File Provider extension for Finder integration (macOS)

### Changed
- **API Freeze**: Made implementation details internal for v1.0 stability
  - `DeviceTuningCache`, `DeviceFingerprint`, `DeviceTuningSettings` → internal
  - `ChunkTuner`, `ChunkTunerStats` → internal
  - `TransportDiscoveryProtocol`, `TransportDiscovery` → internal
- Thread sanitizer now only runs Core/Index/Scenario tests (Transport excluded due to _AtomicsShims)

### Fixed
- N/A (initial release)

### Security
- Atomic file operations to prevent partial writes
- Bounded buffer sizes for memory safety
- Path traversal protection in device file systems

## [1.0.0-rc1] - 2024-XX-XX

### Added
- Core MTP protocol implementation
- LibUSB-based USB transport layer
- Device quirk registry for compatibility
- Transfer journaling for resumable operations
- SQLite-based index for device contents
- Mirror and sync operations
- Benchmarking capabilities
- Comprehensive documentation

### Changed
- N/A (initial release)

### Fixed
- N/A (initial release)

### Security
- Input validation for all device communications
- Safe handling of untrusted device data
