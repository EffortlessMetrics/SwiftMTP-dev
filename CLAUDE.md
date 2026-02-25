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
4. **Transfer journaling**: Automatic resume support via `TransferJournal`
5. **Device quirks**: Static and learned profiles for device-specific tuning

### Key Files and Locations
- Core protocol: `SwiftMTPKit/Sources/SwiftMTPCore/Public/MTPDevice.swift`
- Actor isolation: `SwiftMTPKit/Sources/SwiftMTPCore/Internal/DeviceActor.swift`
- CLI entry point: `SwiftMTPKit/Sources/Tools/swiftmtp-cli/`
- Index database: `SwiftMTPKit/Sources/SwiftMTPIndex/`
- Device quirks: `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`
- Specifications: `Specs/quirks.json`
- Interface probing: `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift`
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
- 15 test targets: CoreTests, TransportTests, IndexTests, FileProviderTests, ErrorHandlingTests, StoreTests, SyncTests, ScenarioTests, TestKitTests, IntegrationTests, XPCTests, ToolingTests, BDDTests, PropertyTests, SnapshotTests
- Coverage gating via `SwiftMTPKit/scripts/coverage_gate.py`

## Device Quirks System

Quirks are defined in `Specs/quirks.json` and `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`.

### Supported Devices
| Device | VID:PID | Status | Quirk ID |
|--------|---------|--------|----------|
| Xiaomi Mi Note 2 | 2717:ff10 | Stable | xiaomi-mi-note-2-ff10 |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | Stable | xiaomi-mi-note-2-ff40 |
| Samsung Galaxy S21 | 04e8:6860 | Experimental | samsung-android-6860 |
| OnePlus 3T | 2a70:f003 | Stable | oneplus-3t-f003 |
| Google Pixel 7 | 18d1:4ee1 | Blocked | google-pixel-7-4ee1 |
| Canon EOS Rebel / R-class | 04a9:3139 | Experimental | canon-eos-rebel-3139 |
| Nikon DSLR / Z-series | 04b0:0410 | Experimental | nikon-dslr-0410 |

## Performance Considerations
- Chunk sizes auto-tune from 512KB to 8MB based on device performance
- Use `swiftmtp bench` for performance measurements
- Device fingerprinting stores optimal settings in `~/.swiftmtp/device-tuning.json`
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
