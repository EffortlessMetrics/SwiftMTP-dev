# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SwiftMTP is a macOS/iOS library and tool for interacting with MTP (Media Transfer Protocol) devices over USB. The project uses modern Swift 6 with strict concurrency and actor-based architecture.

**Maturity note**: SwiftMTP is **pre-alpha**. The project has extensive scaffolding (~9,191+ tests across 20 targets, 20,026 quirks entries, 80+ doc files) but minimal real-device validation. Most test coverage uses `VirtualMTPDevice` (in-memory mock). The quirks database (~20,026 entries) is research-based scaffolding sourced from libmtp data and vendor specs — only a handful of devices have been tested with SwiftMTP directly. Only the Xiaomi Mi Note 2 (ff10) has completed real file transfers.

**Waves 37–40 additions**:
- **MTP 1.1 full coverage**: 50+ object formats, 50+ property codes, all 14 events, all 42 response codes
- **Android MTP edit extensions**: `BeginEditObject`, `EndEditObject`, `TruncateObject`
- **New operations**: `CopyObject`, `GetThumb`, `SetObjectPropList`
- **CLI commands**: `cp`, `edit`, `thumb`, `info`
- **Adaptive chunk tuning**: auto-tunes transfer chunk sizes with device persistence (`AdaptiveChunkTuner`)
- **Error recovery layer**: session reset, stall recovery, timeout retry, disconnect handling (`ErrorRecoveryLayer`)
- **Conflict resolution**: 6 strategies for mirror/sync conflicts (`ConflictResolutionStrategy`)
- **Format-based mirror filtering**: filter synced content by MTP object format (`FormatFilter`)
- **Recovery logging**: structured recovery event logging (`RecoveryLog`)
- **IOUSBHost transport scaffold**: native macOS USB transport (scaffold only, throws `notImplemented`)
- **Transport fixes**: Pixel 7 (handle re-open, set_configuration, timeouts), Samsung (skip alt-setting, skip pre-claim reset)
- **Quirks governance**: CI-enforced schema validation

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

# Run full verification suite
./run-all-tests.sh

# Run fuzzing tests
./run-fuzz.sh

# Run storybook demo
./run-storybook.sh
```

### Running the CLI
```bash
cd SwiftMTPKit

# Run CLI tool
swift run swiftmtp --help

# Common commands:
swift run swiftmtp probe          # Discover devices
swift run swiftmtp ls              # List device contents
swift run swiftmtp pull            # Download files
swift run swiftmtp push            # Upload files
swift run swiftmtp snapshot         # Create device snapshot
swift run swiftmtp mirror          # Mirror device content
swift run swiftmtp bench           # Benchmark transfers
swift run swiftmtp events          # Monitor device events
swift run swiftmtp cp              # Copy objects on device (server-side)
swift run swiftmtp edit            # Edit files on Android devices (BeginEdit/EndEdit)
swift run swiftmtp thumb           # Download object thumbnails
swift run swiftmtp info            # Show detailed object/device info
swift run swiftmtp quirks          # Show device quirks
swift run swiftmtp device-lab      # Automated device testing matrix
swift run swiftmtp wizard          # Interactive guided device setup
```

### Running the GUI App
```bash
cd SwiftMTPKit
swift run SwiftMTPApp
```

### Code Quality
```bash
# Format code (required before commits)
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# Lint code
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests
```

## Architecture

### Package Structure (SwiftMTPKit/)
```
SwiftMTPKit/
├── Sources/
│   ├── SwiftMTPCore/              # Core MTP protocol implementation
│   │   ├── Internal/               # Implementation details
│   │   ├── Public/                 # Public APIs
│   │   └── CLI/                    # CLI utilities
│   ├── SwiftMTPTransportLibUSB/     # USB transport layer using libusb
│   ├── SwiftMTPTransportIOUSBHost/ # Native macOS USB transport (scaffold only)
│   ├── SwiftMTPIndex/              # SQLite-based device content indexing
│   │   └── LiveIndex/              # Cache-first live index (SQLiteLiveIndex)
│   ├── SwiftMTPSync/               # Snapshot, diff, and mirror functionality
│   ├── SwiftMTPUI/                 # SwiftUI views
│   ├── SwiftMTPQuirks/             # Device quirks database
│   ├── SwiftMTPObservability/      # Logging and performance monitoring
│   ├── SwiftMTPStore/              # Persistence layer
│   ├── SwiftMTPFileProvider/       # File Provider extension (macOS)
│   ├── SwiftMTPXPC/                # XPC service for File Provider ↔ app bridge
│   ├── SwiftMTPTestKit/            # Test utilities (VirtualMTPDevice, FaultInjectingLink)
│   └── Tools/
│       ├── swiftmtp-cli/           # CLI entry point
│       ├── SwiftMTPApp/            # GUI application
│       ├── simple-probe/           # Simple USB probe utility
│       ├── test-xiaomi/            # Xiaomi device testing
│       └── SwiftMTPFuzz/           # Protocol fuzzing
├── Tests/
│   ├── CoreTests/                  # Core protocol and codec tests
│   ├── TransportTests/             # USB transport layer tests
│   ├── IndexTests/                 # SQLite index and live index tests
│   ├── FileProviderTests/          # File Provider extension tests
│   ├── ErrorHandlingTests/         # Error handling and recovery tests
│   ├── StoreTests/                 # Persistence layer tests
│   ├── SyncTests/                  # Snapshot, diff, and mirror tests
│   ├── ScenarioTests/              # End-to-end scenario tests
│   ├── TestKitTests/               # SwiftMTPTestKit self-tests
│   ├── IntegrationTests/           # Cross-module integration tests
│   ├── XPCTests/                   # XPC service tests
│   ├── ToolingTests/               # CLI and tooling tests
│   ├── BDDTests/                   # CucumberSwift Gherkin scenarios
│   ├── PropertyTests/              # SwiftCheck property tests
│   └── SnapshotTests/              # Visual regression tests
└── Docs/
    └── benchmarks/probes/          # Mock device probes
```

### Key Design Patterns
1. **Actor-based concurrency**: All device operations go through `MTPDeviceActor` for thread safety
2. **Protocol-oriented**: `MTPDevice` protocol allows mock implementations for testing
3. **Async/await**: All I/O operations use Swift concurrency
4. **Transfer journaling**: WAL-mode SQLite with atomic downloads, orphan detection, and automatic resume via `TransferJournal`
5. **Device quirks**: Static and learned profiles for device-specific tuning; CI-enforced schema validation
6. **Write-path safety**: Validation guards on all mutating operations (partial write detection, delete safety, read-only storage enforcement)
7. **MTP 1.1 coverage**: 50+ object formats, 50+ property codes, all 14 events, all 42 response codes, Android edit extensions, server-side CopyObject
8. **Dual transport**: libusb-based transport (current) with IOUSBHost native transport scaffold for future macOS-native USB access

### Key Files and Locations
- Core protocol: `SwiftMTPKit/Sources/SwiftMTPCore/Public/MTPDevice.swift`
- Actor isolation: `SwiftMTPKit/Sources/SwiftMTPCore/Internal/DeviceActor.swift`
- Error recovery: `SwiftMTPKit/Sources/SwiftMTPCore/Internal/ErrorRecoveryLayer.swift`
- Adaptive chunk tuner: `SwiftMTPKit/Sources/SwiftMTPCore/Public/AdaptiveChunkTuner.swift`
- CLI entry point: `SwiftMTPKit/Sources/Tools/swiftmtp-cli/`
- Index database: `SwiftMTPKit/Sources/SwiftMTPIndex/`
- Conflict resolution: `SwiftMTPKit/Sources/SwiftMTPSync/ConflictResolutionStrategy.swift`
- Format filter: `SwiftMTPKit/Sources/SwiftMTPSync/FormatFilter.swift`
- Recovery log: `SwiftMTPKit/Sources/SwiftMTPObservability/RecoveryLog.swift`
- Device quirks: `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`
- Specifications: `Specs/quirks.json`
- Interface probing: `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift`
- IOUSBHost transport: `SwiftMTPKit/Sources/SwiftMTPTransportIOUSBHost/` (scaffold)
- Fallback ladder: `SwiftMTPKit/Sources/SwiftMTPCore/Internal/FallbackLadder.swift`
- USB claim diagnostics: `SwiftMTPKit/Sources/SwiftMTPCore/Internal/Transport/USBClaimDiagnostics.swift`
- Device lab harness: `SwiftMTPKit/Sources/SwiftMTPCore/Public/DeviceLabHarness.swift`
- Device service registry: `SwiftMTPKit/Sources/SwiftMTPCore/Public/DeviceServiceRegistry.swift`
- SQLite live index: `SwiftMTPKit/Sources/SwiftMTPIndex/LiveIndex/SQLiteLiveIndex.swift`
- Virtual test device: `SwiftMTPKit/Sources/SwiftMTPTestKit/VirtualMTPDevice.swift`

### Testing Approach
- Use mock profiles for unit tests without real devices
- Mock profiles available: pixel7, galaxy, iphone, canon
- Failure scenarios: timeout, busy, disconnected
- Tests use XCTest with async/await support
- `SwiftMTPTestKit` provides `VirtualMTPDevice` (in-memory MTP device) and `FaultInjectingLink` for deterministic failure injection
- 20 test targets: CoreTests, TransportTests, IndexTests, FileProviderTests, ErrorHandlingTests, StoreTests, SyncTests, ScenarioTests, TestKitTests, IntegrationTests, XPCTests, ToolingTests, BDDTests, PropertyTests, SnapshotTests, MTPEndianCodecTests, QuirksTests, ObservabilityTests, SwiftMTPCLITests, UITests
- Coverage gating via `SwiftMTPKit/scripts/coverage_gate.py`

### Test Discovery Guide

Which tests to run per change area:
```bash
# Core protocol changes (operations, codecs, actor)
swift test --filter CoreTests

# Transport layer changes (USB, libusb, IOUSBHost)
swift test --filter TransportTests

# Index/SQLite changes (live index, snapshots)
swift test --filter IndexTests

# Sync/mirror changes (diff, conflict resolution, format filter)
swift test --filter SyncTests

# CLI changes (commands, argument parsing)
swift test --filter ToolingTests

# FileProvider changes (macOS Finder integration)
swift test --filter FileProviderTests

# Quirks changes (device profiles, schema)
swift test --filter QuirksTests

# Error handling changes (recovery layer, fallback)
swift test --filter ErrorHandlingTests

# Observability changes (logging, recovery log)
swift test --filter ObservabilityTests

# Store/persistence changes (transfer journal)
swift test --filter StoreTests

# Full suite (use for cross-cutting changes)
swift test -v --enable-code-coverage
```

## Device Quirks System

Quirks are defined in `Specs/quirks.json` and `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`.

### Tested Devices
| Device | VID:PID | Status | Quirk ID |
|--------|---------|--------|----------|
| Xiaomi Mi Note 2 | 2717:ff10 | Partial — only device with real transfer data | xiaomi-mi-note-2-ff10 |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | Partial — recent lab run returned 0 storages | xiaomi-mi-note-2-ff40 |
| Samsung Galaxy S7 (SM-G930W8) | 04e8:6860 | In Progress — handshake fails after USB claim; research (#428) identified 8 init differences; transport fixes (#445) skip alt-setting and skip pre-claim reset — awaiting retest | samsung-android-6860 |
| OnePlus 3T | 2a70:f003 | Partial — probe/read works, writes fail (0x201D) | oneplus-3t-f003 |
| Google Pixel 7 | 18d1:4ee1 | In Progress — bulk transfer timeout; research (#429) identified 5 differences; transport fixes (#443) add handle re-open, set_configuration, and timeout tuning — awaiting retest | google-pixel-7-4ee1 |
| Canon EOS Rebel / R-class | 04a9:3139 | Research Only — never connected to SwiftMTP | canon-eos-rebel-3139 |
| Nikon DSLR / Z-series | 04b0:0410 | Research Only — never connected to SwiftMTP | nikon-dslr-0410 |

## Performance Considerations
- Chunk sizes auto-tune from 512KB to 8MB based on device performance via `AdaptiveChunkTuner`
- Tuner persists optimal settings per device fingerprint in `~/.swiftmtp/device-tuning.json`
- Use `swiftmtp bench` for performance measurements
- Benchmark results in `Docs/benchmarks/`

## CI & Coverage
- CI workflows: `.github/workflows/ci.yml`, `.github/workflows/swiftmtp-ci.yml`, `.github/workflows/smoke.yml`
  - `ci.yml`: runs on ALL pushes and PRs; covers build, full tests, **TSAN**, fuzz, SBOM on tags.
  - `swiftmtp-ci.yml`: runs on main branch and nightly; covers full coverage report, CLI smoke, DocC docs.
  - `smoke.yml`: minimal sanity build (product swiftmtp) for fast feedback.
- **TSAN** (Thread Sanitizer) execution:
  - CI: `ci.yml` → `tsan` job: `swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests`
  - Local: `cd SwiftMTPKit && swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests`
  - Scope: TransportTests excluded (USB I/O is inherently single-threaded at the libusb level).
  - Exit criteria: zero race warnings or TSan-reported errors.
- Coverage gating: `SwiftMTPKit/scripts/coverage_gate.py` enforces minimum thresholds
- Run locally: `./run-all-tests.sh` (full verification suite)

## Documentation
- Main docs: `Docs/SwiftMTP.docc/SwiftMTP.md`
- macOS 26 Guide: `Docs/SwiftMTP.docc/macOS26.md`
- Device guides: `Docs/SwiftMTP.docc/Devices/`
- Benchmarks: `Docs/benchmarks.md`
- Contribution: `Docs/ContributionGuide.md`
- Roadmap: `Docs/ROADMAP.md`
- Device submission: `Docs/ROADMAP.device-submission.md`
- Testing roadmap: `Docs/ROADMAP.testing.md`
- Release checklist: `Docs/ROADMAP.release-checklist.md`
- Pixel 7 debug report: `Docs/pixel7-usb-debug-report.md`
- File Provider tech preview: `Docs/FileProvider-TechPreview.md`
- Troubleshooting: `Docs/Troubleshooting.md`

## Pre-PR Checklist

Before opening a pull request, run:
```bash
# Automated pre-PR checks (if scripts/pre-pr.sh exists)
./scripts/pre-pr.sh

# Or manually:
cd SwiftMTPKit
swift-format -i -r Sources Tests           # Format
swift-format lint -r Sources Tests          # Lint
swift build -v                              # Build
swift test --filter <RelevantTests>         # Test (see Test Discovery Guide)
```
