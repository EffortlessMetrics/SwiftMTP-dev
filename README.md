<div align="center">

# SwiftMTP

**A Swift-native MTP (Media Transfer Protocol) implementation for macOS**

[![CI](https://github.com/EffortlessMetrics/SwiftMTP-dev/actions/workflows/ci.yml/badge.svg)](https://github.com/EffortlessMetrics/SwiftMTP-dev/actions/workflows/ci.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue.svg)](https://developer.apple.com/macos/)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green.svg)](LICENSE-AGPL-3.0.md)

Connect Android phones, cameras, and other MTP devices to your Mac — no Android File Transfer needed.

</div>

> **⚠️ Pre-Alpha** — The protocol layer is well-tested with mocks (~8,700+ tests across 20 targets), but only 1 device has completed real file transfers. Not ready for production use.

---

## Quick Start

### Install via Homebrew

```bash
brew tap EffortlessMetrics/swiftmtp https://github.com/EffortlessMetrics/SwiftMTP-dev.git
brew install swiftmtp
```

### Or build from source

```bash
git clone https://github.com/EffortlessMetrics/SwiftMTP-dev.git
cd SwiftMTP-dev
./scripts/bootstrap.sh
```

### Usage

```bash
swiftmtp probe              # Discover connected MTP devices
swiftmtp ls                 # List files on device
swiftmtp pull photo.jpg     # Download a file
swiftmtp push track.mp3     # Upload a file
swiftmtp mirror ~/Photos    # Mirror device content locally
swiftmtp search vacation    # Search device contents (FTS5)
swiftmtp snapshot           # Capture device metadata for debugging
```

See the [CLI Command Map](Docs/CLICommandMap.md) for all 30+ commands.

---

## Feature Matrix

### MTP Operations

| Operation | Status | Notes |
|-----------|--------|-------|
| GetDeviceInfo | ✅ Implemented | |
| OpenSession / CloseSession | ✅ Implemented | |
| GetStorageIDs / GetStorageInfo | ✅ Implemented | |
| GetObjectHandles / GetObjectInfo | ✅ Implemented | |
| GetObject / GetPartialObject(64) | ✅ Implemented | |
| SendObject / SendPartialObject | ✅ Implemented | |
| DeleteObject / MoveObject | ✅ Implemented | |
| CopyObject | ✅ Implemented | Server-side copy, no re-transfer |
| GetThumb | ✅ Implemented | Download object thumbnails |
| GetObjectPropList / SetObjectPropList | ✅ Implemented | |
| BeginEditObject / EndEditObject | ✅ Implemented | Android MTP extension |
| TruncateObject | ✅ Implemented | Android MTP extension |

### Platform Features

| Feature | Status | Notes |
|---------|--------|-------|
| MTP 1.1 protocol coverage | ✅ Done | 50+ object formats, 50+ property codes, all 14 events, all 42 response codes |
| Android MTP edit extensions | ✅ Done | In-place file editing on Android devices |
| Adaptive chunk tuning | ✅ Done | Auto-tunes 512 KB–8 MB with per-device persistence |
| Error recovery layer | ✅ Done | Session reset, stall recovery, timeout escalation, disconnect handling |
| Transfer journaling | ✅ Done | WAL-mode SQLite, atomic downloads, orphan detection, resume |
| Conflict resolution | ✅ Done | 6 strategies: newer-wins, local-wins, device-wins, keep-both, skip, ask |
| Format-based mirror filtering | ✅ Done | `--photos-only`, `--format`, `--exclude-format` |
| SQLite content indexing | ✅ Done | Optimized queries with 8 dedicated indexes |
| Device quirks database | ✅ Done | 20,026 entries across 1,154 vendors (research-based — see [caveat](#quirks-database-caveat)) |
| FTS5 full-text search | ✅ Done | SQLite FTS5-based device content search |
| CLI tool | ✅ Done | 30+ commands with "did you mean?" suggestions and categorized help |
| XPC auto-reconnect | ✅ Done | Automatic XPC service reconnection on failure |
| Mirror progress | ✅ Done | Real-time progress reporting with ETA for mirror operations |
| DiagnosticFormatter | ✅ Done | Structured error diagnostics with cause, suggestion, and related commands |
| PrivacyRedactor | ✅ Done | SHA-256 serial obfuscation for safe device submission artifacts |
| SwiftUI GUI | 🔨 In Progress | Demo mode functional; real-device integration pending |
| File Provider (Finder) | 🔨 In Progress | Tech preview — scaffolded and mock-tested; no real-device validation |
| IOUSBHost native transport | ✅ Done | Discovery, session, bulk transfers, file transfer, event polling — awaiting real-device validation |

---

## Device Compatibility

> **Transparency note**: Most quirks entries are research-based, sourced from libmtp data and vendor specifications. The "Mock-Tested" and "Real-Device" columns reflect actual SwiftMTP testing.

| Device | VID:PID | Mock-Tested | Real-Device | Status |
|--------|---------|:-----------:|:-----------:|--------|
| Xiaomi Mi Note 2 | `2717:ff10` | ✅ | ✅ Partial | Only device with real file transfers. Requires kernel detach. |
| Xiaomi Mi Note 2 (alt) | `2717:ff40` | ✅ | ✅ Partial | Probe, listing, and storage enumeration confirmed (wave 50). File transfers TBD. |
| Samsung Galaxy S7 | `04e8:6860` | ✅ | ❌ Blocked | USB claim succeeds but MTP handshake fails. Transport fixes shipped ([#445](https://github.com/EffortlessMetrics/SwiftMTP-dev/pull/445)) — awaiting retest. |
| Google Pixel 7 | `18d1:4ee1` | ✅ | ❌ Blocked | Bulk transfer timeout. Transport fixes shipped ([#443](https://github.com/EffortlessMetrics/SwiftMTP-dev/pull/443)) — awaiting retest. See [debug report](Docs/pixel7-usb-debug-report.md). |
| OnePlus 3T | `2a70:f003` | ✅ | ⚠️ Partial | Probe, listing, and search confirmed working (wave 50). Writes still fail with `0x201D`. |
| Canon EOS Rebel / R-class | `04a9:3139` | ✅ | — | Research-only quirks from libmtp/vendor specs. Never connected. |
| Nikon DSLR / Z-series | `04b0:0410` | ✅ | — | Research-only quirks from libmtp/vendor specs. Never connected. |

The full quirks database covers 20,026 device entries (phones, cameras, tablets, audio players, drones, etc.). See [`Specs/quirks.json`](Specs/quirks.json).

### Quirks Database Caveat

The quirks database is **research-based scaffolding** sourced from libmtp data and vendor specifications. It represents intended tuning parameters, not validated device support. Only a handful of devices listed above have been tested with SwiftMTP directly.

---

## Architecture

Built with **Swift 6 strict concurrency** and **actor-based isolation**.

```
┌──────────────────────────────────────────────────────┐
│                    SwiftMTP CLI / GUI                 │
├──────────┬───────────┬───────────┬───────────────────┤
│ SwiftMTP │ SwiftMTP  │ SwiftMTP  │   SwiftMTP        │
│   Sync   │   Index   │   Store   │   Observability   │
├──────────┴───────────┴───────────┴───────────────────┤
│                   SwiftMTPCore                        │
│   MTPDeviceActor · ErrorRecoveryLayer · ChunkTuner   │
├──────────────────────┬───────────────────────────────┤
│  TransportLibUSB     │  TransportIOUSBHost             │
├──────────────────────┴───────────────────────────────┤
│              SwiftMTPQuirks (20,026 entries)          │
└──────────────────────────────────────────────────────┘
```

| Module | Responsibility |
|--------|---------------|
| **SwiftMTPCore** | Actor-isolated MTP protocol, async/await I/O, error recovery |
| **SwiftMTPTransportLibUSB** | USB transport via libusb with fallback support |
| **SwiftMTPTransportIOUSBHost** | Native macOS USB transport (discovery, session, bulk, file transfer, events) — awaiting real-device validation |
| **SwiftMTPIndex** | SQLite-based device content indexing and snapshots |
| **SwiftMTPSync** | Mirror, diff, and sync with conflict resolution |
| **SwiftMTPUI** | SwiftUI views using `@Observable` |
| **SwiftMTPQuirks** | Device-specific tuning database |
| **SwiftMTPObservability** | Structured logging and performance monitoring |
| **SwiftMTPStore** | Transfer journals and device metadata persistence |
| **SwiftMTPFileProvider** | macOS File Provider extension via XPC (tech preview) |
| **SwiftMTPTestKit** | `VirtualMTPDevice`, `FaultInjectingLink`, test utilities |
| **MTPCoreTypes** | Shared MTP type definitions (extracted from Core) |
| **MTPEndianCodec** | PTP/MTP binary codec (little-endian wire format) |
| **SwiftMTPCLI** | CLI shared utilities (flags, formatting, output helpers) |

---

## Installation & Setup

### Prerequisites

- **macOS 15+** (Apple Silicon or Intel)
- **Xcode 16+** with Swift 6
- `libusb` via Homebrew: `brew install libusb`

### From Source

```bash
git clone https://github.com/EffortlessMetrics/SwiftMTP-dev.git
cd SwiftMTP-dev/SwiftMTPKit
swift build -v
```

### Build libusb XCFramework (first time only)

```bash
./scripts/build-libusb-xcframework.sh
```

### Run the CLI

```bash
cd SwiftMTPKit
swift run swiftmtp --help
```

### Run the GUI

```bash
cd SwiftMTPKit
swift run SwiftMTPApp
```

See [Docs/Installation.md](Docs/Installation.md) for shell completions, Homebrew details, and more.

---

## Demo Mode

Develop without physical hardware using simulated device profiles:

```bash
export SWIFTMTP_DEMO_MODE=1
export SWIFTMTP_MOCK_PROFILE=pixel7  # Options: pixel7, galaxy, iphone, canon

swiftmtp probe    # Shows simulated Pixel 7
swiftmtp ls       # Lists simulated files
```

GUI users can toggle simulation via the Orange Play button in the toolbar.

---

## Testing

~8,700+ tests across 20 targets using `VirtualMTPDevice` (in-memory mock). Includes unit, BDD ([CucumberSwift](https://github.com/Tyler-Keith-Thompson/CucumberSwift)), property-based ([SwiftCheck](https://github.com/typelift/SwiftCheck)), snapshot, and fuzz tests.

```bash
# Full verification suite
./run-all-tests.sh

# Targeted tests (from SwiftMTPKit/)
cd SwiftMTPKit
swift test --filter CoreTests           # Core protocol and codec
swift test --filter SyncTests           # Mirror/sync/diff
swift test --filter ToolingTests        # CLI commands
swift test --filter BDDTests            # Gherkin scenarios
swift test --filter PropertyTests       # Property-based tests

# Thread Sanitizer
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# Fuzzing
./run-fuzz.sh
```

### Code Quality

```bash
# Format (required before commits)
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# Lint
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# Full pre-PR checks
./scripts/pre-pr.sh
```

---

## Help Wanted

Real-device testing is the main bottleneck. If you have an MTP device and want to help:

1. **Run a probe**: `swiftmtp probe` and share the output
2. **Try file listing**: `swiftmtp ls`
3. **Report results**: Open an issue with your device model, VID:PID, and what worked/failed
4. **Submit a snapshot**: `swiftmtp snapshot` captures device metadata for debugging

**Known blockers needing real-device retests:**
- **Samsung Galaxy**: MTP handshake fails after USB claim — transport fixes shipped, awaiting retest
- **Pixel 7**: bulk transfer timeout — transport fixes shipped, awaiting retest
- **OnePlus**: write path returns InvalidParameter — root cause identified (SendObjectPropList + format mismatch), awaiting retest with quirk flags
- **Canon/Nikon**: no one has tried connecting a camera yet

---

## Documentation

| Resource | Description |
|----------|-------------|
| [Error Catalog](Docs/ErrorCatalog.md) | Complete error code reference with causes and fixes |
| [CLI Command Map](Docs/CLICommandMap.md) | All CLI commands, flags, and usage patterns |
| [Installation Guide](Docs/Installation.md) | Homebrew, source builds, shell completions |
| [Troubleshooting](Docs/Troubleshooting.md) | Common issues and device-specific solutions |
| [Contribution Guide](Docs/ContributionGuide.md) | Development workflow and PR process |
| [Roadmap](Docs/ROADMAP.md) | Project roadmap and priorities |
| [Testing Guide](Docs/ROADMAP.testing.md) | Test targets, coverage gates, and CI |
| [Device Submission](Docs/ROADMAP.device-submission.md) | How to submit device test results |
| [File Provider Tech Preview](Docs/FileProvider-TechPreview.md) | Finder integration status |
| [Pixel 7 Debug Report](Docs/pixel7-usb-debug-report.md) | Detailed USB debug analysis |
| [Changelog](CHANGELOG.md) | Release notes and change history |

---

## Project Structure

```
SwiftMTP/
├── SwiftMTPKit/               # Swift Package root (build from here)
│   ├── Sources/
│   │   ├── SwiftMTPCore/              # Core MTP protocol
│   │   ├── MTPCoreTypes/             # Shared MTP type definitions
│   │   ├── MTPEndianCodec/           # PTP/MTP binary codec
│   │   ├── SwiftMTPCLI/             # CLI shared utilities
│   │   ├── CLibusb/                  # C module map for libusb
│   │   ├── CSQLite/                  # C module map for SQLite
│   │   ├── SwiftMTPTransportLibUSB/   # libusb transport
│   │   ├── SwiftMTPTransportIOUSBHost/# Native transport (fully implemented)
│   │   ├── SwiftMTPIndex/             # SQLite indexing
│   │   ├── SwiftMTPSync/              # Mirror/sync/diff
│   │   ├── SwiftMTPUI/               # SwiftUI views
│   │   ├── SwiftMTPQuirks/           # Device quirks
│   │   ├── SwiftMTPObservability/     # Logging & monitoring
│   │   ├── SwiftMTPStore/            # Persistence
│   │   ├── SwiftMTPFileProvider/      # File Provider extension
│   │   ├── SwiftMTPXPC/              # XPC bridge
│   │   ├── SwiftMTPTestKit/          # Test utilities
│   │   └── Tools/                    # CLI, GUI, fuzz harnesses
│   └── Tests/                        # 20 test targets
├── Docs/                              # Documentation
├── Specs/                             # Schemas & quirks database
├── scripts/                           # Build, release & CI tools
└── legal/                             # Licensing
```

---

## Contributing

We welcome contributions! See the [Contribution Guide](Docs/ContributionGuide.md) for development workflow, coding standards, and PR process.

---

## License

SwiftMTP is dual-licensed:

- **[AGPL-3.0](LICENSE-AGPL-3.0.md)** for open-source use
- **[Commercial license](legal/outbound/COMMERCIAL-LICENSE.md)** for closed-source / App Store distribution

Contact git@effortlesssteven.com for commercial licensing inquiries.

---

## Acknowledgments

- [libusb](https://libusb.info/) — cross-platform USB access
- [CucumberSwift](https://github.com/Tyler-Keith-Thompson/CucumberSwift) — BDD testing
- [SwiftCheck](https://github.com/typelift/SwiftCheck) — property-based testing
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — visual regression testing
