# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **FileProvider write operations**: `createItem`, `modifyItem`, `deleteItem` now fully wired to XPC backend (`MTPFileProviderExtension.swift`).
- **XPC write protocol**: `WriteRequest`, `DeleteRequest`, `CreateFolderRequest`, `WriteResponse` — all NSSecureCoding with round-trip tests.
- **`swiftmtp-docs` tool**: Hands-off DocC device page generator. Reads `Specs/quirks.json` and emits per-device `.md` pages to `Docs/SwiftMTP.docc/Devices/`. Run: `swift run swiftmtp-docs Specs/quirks.json Docs/SwiftMTP.docc/Devices/`.
- **`learn-promote` tool** re-added to Package.swift and fixed: now uses correct `QuirkDatabase.match(vid:pid:...)` API and `DeviceQuirk` field names.
- **Multi-device `DeviceServiceRegistry` tests**: 4 new tests covering concurrent registration of 3 devices, isolated detach/reconnect, domain remapping, and remove-one-keeps-others.
- **FileProvider integration tests**: Replaced 12 all-skipped stubs with 10 real mock-based tests (`FileProviderWriteIntegrationTests`, `MTPFileProviderItemIntegrationTests`) plus 3 correctly-documented sandbox-only skips.
- `SendableBox<T>` helper for bridging ObjC completion handlers into Swift 6.2 `sending Task` closures.
- Sprint execution playbook with DoR/DoD, weekly cadence, carry-over rules, and evidence contracts (`Docs/SPRINT-PLAYBOOK.md`).
- Central documentation hub for sprint/release workflows and technical references (`Docs/README.md`).
- Sprint kickoff routing in `README.md` so contributors can find roadmap, playbook, gates, and troubleshooting flows quickly.

### Changed

- **`Package.swift`**: swift-tools-version upgraded to 6.2; platforms upgraded to macOS 26 / iOS 26; added `SwiftMTPCLI`, `SwiftMTPUI`, `SwiftMTPApp`, `MTPEndianCodecFuzz`, `SwiftMTPFuzz`, `simple-probe`, `test-xiaomi`, `learn-promote`, `swiftmtp-docs`, `SwiftMTPCLITests` targets.
- **`SwiftMTPFileProvider` / `SwiftMTPXPC`**: Removed `.swiftLanguageMode(.v5)`; now strict Swift 6. `MTPFileProviderItem.ItemComponents` is now `Sendable`.
- **`parseUSBIdentifier` test**: Corrected expectation — unprefixed bare numbers are treated as hex per USB convention (`"4660"` → `0x4660`, not decimal 4660).
- `MTPEndianCodecFuzz` harness now emits per-iteration failure counters and crash corpus hex dump.
- Snapshot baselines regenerated for 5 stale probe/quirks snapshots.
- Roadmap now includes explicit sprint execution rules, active sprint snapshot, and 2.1 dependency/risk register (`Docs/ROADMAP.md`).
- Release checklist and runbook now require docs/changelog sync, required workflow health, and sprint carry-over alignment before tag cut (`Docs/ROADMAP.release-checklist.md`, `RELEASE.md`).
- Testing guide now separates required merge workflows from optional/nightly surfaces and includes a standard PR evidence snippet (`Docs/ROADMAP.testing.md`).
- Contribution and submission docs now include sprint-prefixed naming conventions, DoR alignment, and sprint fast-path submission guidance (`Docs/ContributionGuide.md`, `Docs/ROADMAP.device-submission.md`).
- PR templates now use repository-root command examples with `--package-path SwiftMTPKit` for operational consistency (`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/device-submission.md`).
- Troubleshooting now defines minimum evidence expected when opening/updating sprint issues (`Docs/Troubleshooting.md`).

### Fixed

- Build blocker: `SwiftMTPCLI` module existed on disk but had no Package.swift target declaration.
- `MTPEndianCodec` missing as linker dep of `SwiftMTPCore` (linker failure in protocol codec paths).
- Swift 6 `let` property ordering: `indexReader` now initialized before `super.init()` in `MTPFileProviderExtension`.
- `FuzzTests.swift`: static member access qualified with `Self.` for Swift 6 strict-mode `@Suite` structs.
- `DeviceFilterBehaviorTests.swift`: ambiguous `parseUSBIdentifier`/`selectDevice` qualified with `SwiftMTPCLI.` module prefix.
- `learn-promote/main.swift`: replaced non-existent `DeviceFingerprint` type and `bestMatch(for:)` / `.overrides.` accessors with correct `QuirkDatabase.match(vid:pid:...)` and `DeviceQuirk` field names.

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
- **Linux support**: IOUSBHost dependency is macOS-only. Linux users should remain on v1.x.

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

### Privacy

- No personal data collection in submissions
- Safe defaults for privacy-preserving operations
- Full SBOM and build attestation

[Unreleased]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/EffortlessMetrics/SwiftMTP/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/EffortlessMetrics/SwiftMTP/releases/tag/v1.0.0
