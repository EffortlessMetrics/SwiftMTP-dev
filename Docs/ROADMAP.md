# Roadmap

This document outlines the future direction for SwiftMTP.

## Version 2.x - Tahoe Era

### Completed (v2.0.0)

- [x] macOS Tahoe 26 native support
- [x] SwiftPM 6.2+ toolchain
- [x] IOUSBHost framework adoption
- [x] Comprehensive macOS Tahoe 26 documentation
- [x] Swift-DocC metadata fixes

### In Progress

### Upcoming

#### Platform Enhancements

- [ ] visionOS 26 support
- [ ] iPadOS 26 parity with macOS
- [ ] Apple Silicon-optimized USB transfers

#### Device Support

- [ ] Samsung Galaxy S25 quirk entry
- [ ] Sony Xperia device quirks database expansion
- [ ] Camera device RAW transfer optimization
- [ ] Nintendo Switch MTP support investigation

#### Performance

- [ ] Transfer throughput benchmarks (>100 MB/s on USB 3.2)
- [ ] Parallel multi-device enumeration
- [ ] Memory-mapped I/O for large files
- [ ] GPU-accelerated thumbnail generation

#### Developer Experience

- [ ] Swift Package Plugin for quirks generation
- [ ] Xcode Cloud CI integration
- [ ] VS Code extension for device debugging
- [ ] Interactive benchmark visualization

## Version 3.x - Future

### Exploratory

- **Network MTP (MTP/IP)**: Support for remote device access over IP
- **WebUSB Integration**: Browser-based device access via WebUSB
- **Rust Transport Layer**: Alternative high-performance transport in Rust
- **Embedded Device Support**: RTOS-based MTP device development kit

### Long-term Goals

- **Cross-platform USB stack**: libusb 2.0 backend for Linux/Windows
- **Cloud Device Bridge**: Cloud-based device mirroring
- **ML-powered Device Detection**: Intelligent device quirk prediction
- **Plugin Architecture**: Extensible transfer handlers for specialized devices

## Release Cadence

| Version | Target | Schedule |
|---------|--------|----------|
| v2.0.0 | macOS 26 | Q1 2026 |
| v2.1.0 | visionOS 26 | Q2 2026 |
| v2.2.0 | Performance & benchmarks | Q3 2026 |
| v3.0.0 | Cross-platform | 2027 |

## Deprecation Schedule

| Feature | Deprecated | Removed |
|---------|------------|---------|
| macOS 15 support | v2.0.0 | v3.0.0 |
| IOUSBLib (legacy) | v2.0.0 | v3.0.0 |
| Swift 5 compatibility | v2.0.0 | v2.5.0 |

## Contributing

See [Contribution Guide](ContributionGuide.md) for how to contribute to the roadmap.

## Issue Tracking

Use GitHub Issues for:
- **Feature Requests**: Tag with `enhancement`
- **Bug Reports**: Tag with `bug`
- **Device Quirks**: Tag with `device-support`
- **Documentation**: Tag with `documentation`
