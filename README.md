# SwiftMTP

> **Pre-Alpha** — Heavily scaffolded protocol and test infrastructure, but only 1 device has completed real file transfers. Not ready for production use.

A Swift-native MTP (Media Transfer Protocol) implementation for macOS. The protocol layer is well-tested with mocks, but real-device support is still being built out.

## Project Status

SwiftMTP is in **pre-alpha**. The core MTP protocol, codec, and session management are implemented and covered by an extensive test suite (**~9,191+ tests executed** across 20 targets) using in-memory mock devices (`VirtualMTPDevice`). However, real-device validation is minimal — only one device (Xiaomi Mi Note 2) has completed successful file transfers through SwiftMTP.

### What Works

- **MTP 1.1 protocol**: 50+ object formats, 50+ property codes, full event handling (mock-tested)
- **Android MTP extensions**: `BeginEditObject`, `EndEditObject`, `TruncateObject` for in-place file editing
- **Server-side CopyObject**: device-side file copy without re-transfer
- **Adaptive chunk tuning**: auto-tunes transfer sizes 512KB–8MB with device persistence
- **Error recovery layer**: session reset, stall recovery, timeout escalation, disconnect handling
- **Conflict resolution**: 6 strategies for mirror/sync (newer-wins, local-wins, device-wins, keep-both, skip, ask)
- **Format-based mirror filtering**: --photos-only, --format, --exclude-format
- **Write-path safety**: validation guards on all mutating operations
- **Transfer journaling**: WAL-mode SQLite, atomic downloads, orphan detection, resume support
- **SQLite-indexed device content**: optimized queries with 8 dedicated indexes
- **CLI tool**: 15+ commands (`probe`, `ls`, `pull`, `push`, `snapshot`, `mirror`, `bench`, `events`, `quirks`, `device-lab`, `wizard`, `cp`, `edit`, `thumb`, `info`) with "did you mean?" suggestions and categorized help
- **Device quirks database**: 20,026 entries across 1,154 vendors (research-based — see caveat below)
- **File Provider integration**: native Finder support on macOS via XPC (tech preview, read-only)
- **SwiftUI GUI application** (demo mode only)

### What Doesn't Work (Yet)

- Most real MTP devices — only 1 of 7 tested devices can transfer files
- Samsung Galaxy: MTP handshake fails after USB claim (research done, transport fixes shipped — awaiting retest)
- Google Pixel 7: bulk transfer timeout (research done, transport fixes shipped — awaiting retest; see [debug report](Docs/pixel7-usb-debug-report.md))
- OnePlus 3T: reads work but writes fail with InvalidParameter
- Canon/Nikon cameras: never connected to SwiftMTP (research-only quirks)
- File Provider write operations (implemented but no real-device validation)

### Quirks Database Caveat

The 20,000+ entry quirks database is **research-based scaffolding**, sourced from libmtp data and vendor specifications. Only a handful of devices have been tested with SwiftMTP directly. The database represents intended tuning parameters, not validated device support.

- Change tracking: [`CHANGELOG.md`](CHANGELOG.md)
- Docs index: [`Docs/README.md`](Docs/README.md)
- Roadmap: [`Docs/ROADMAP.md`](Docs/ROADMAP.md)
- Testing gates: [`Docs/ROADMAP.testing.md`](Docs/ROADMAP.testing.md)
- Contribution workflow: [`Docs/ContributionGuide.md`](Docs/ContributionGuide.md)
- Troubleshooting: [`Docs/Troubleshooting.md`](Docs/Troubleshooting.md)

## Architecture

Built with Swift 6 strict concurrency and actor-based isolation:

- **`SwiftMTPCore`**: Actor-isolated MTP protocol implementation with async/await
- **`SwiftMTPTransportLibUSB`**: USB transport layer using libusb with fallback support
- **`SwiftMTPIndex`**: SQLite-based device content indexing and snapshots
- **`SwiftMTPSync`**: Mirror, sync, and diff operations
- **`SwiftMTPUI`**: SwiftUI views using `@Observable`
- **`SwiftMTPQuirks`**: Device-specific tuning database
- **`SwiftMTPObservability`**: Structured logging and performance monitoring
- **`SwiftMTPStore`**: Persistence layer for device metadata and transfer journals
- **`SwiftMTPFileProvider`**: macOS File Provider extension (tech preview, read-only)
- **`swiftmtp-cli`**: CLI tool for automation and power users
- **`SwiftMTPApp`**: Standalone macOS GUI application

### Key Features

- **MTP 1.1 Protocol Coverage**: 50+ object formats, 50+ property codes, full event handling, Android MTP extensions, and server-side CopyObject.
- **Device Quirks Database**: 20,026 entries across 38 categories and 1,154 vendor IDs, sourced from libmtp data and vendor specs. This is research-based scaffolding — only a handful of devices have been tested with SwiftMTP directly.
- **Transfer Journaling**: WAL-mode SQLite with atomic downloads, orphan detection, and automatic resume support. Implemented and tested with mocks; limited real-device validation.
- **Write-Path Safety**: Validation guards on all mutating operations — partial write detection, delete safety, read-only storage enforcement.
- **File Provider Integration**: Native Finder integration on macOS via XPC. Tech preview, read-only.
- **CLI**: 12+ commands with "did you mean?" suggestions, categorized help, and structured error messages.
- **Demo Mode**: Simulated device profiles (pixel7, galaxy, iphone, canon) for development without physical hardware.

## MTP Operation Coverage

| Operation | Status |
|-----------|--------|
| GetDeviceInfo | ✅ Implemented |
| OpenSession / CloseSession | ✅ Implemented |
| GetStorageIDs / GetStorageInfo | ✅ Implemented |
| GetObjectHandles / GetObjectInfo | ✅ Implemented |
| GetObject / GetPartialObject(64) | ✅ Implemented |
| SendObject / SendPartialObject | ✅ Implemented |
| DeleteObject / MoveObject | ✅ Implemented |
| CopyObject | ✅ Implemented (wave 38) |
| BeginEditObject / EndEditObject | ✅ Implemented (wave 38, Android) |
| TruncateObject | ✅ Implemented (wave 38, Android) |
| GetThumb | ✅ Implemented (wave 40) |
| GetObjectPropList | ✅ Implemented |
| SetObjectPropList | ✅ Implemented (wave 40) |

## Device Status

Honest status of devices that have quirk entries with any level of real testing:

| Device | VID:PID | Status | Notes |
|--------|---------|--------|-------|
| Xiaomi Mi Note 2 | 2717:ff10 | Partial | Only device with real file transfer data. Requires kernel detach; no GetObjectPropList. |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | Untested | Has quirk entry. Recent lab run returned 0 storages. |
| Samsung Galaxy S7 | 04e8:6860 | Blocked | USB claim succeeds but MTP handshake fails. Research done (#428), transport fixes shipped (#445: skipAltSetting, skipPreClaimReset). Awaiting retest. |
| Google Pixel 7 | 18d1:4ee1 | Blocked | Bulk transfer timeout — research done (#429), transport fixes shipped (#443: handle re-open, set_configuration, extended timeouts). Awaiting retest. See [debug report](Docs/pixel7-usb-debug-report.md). |
| OnePlus 3T | 2a70:f003 | Partial | Probe and read work. Writes fail with 0x201D (InvalidParameter). |
| Canon EOS Rebel / R-class | 04a9:3139 | Research Only | Quirks from libmtp/vendor specs. Never connected to SwiftMTP. |
| Nikon DSLR / Z-series | 04b0:0410 | Research Only | Quirks from libmtp/vendor specs. Never connected to SwiftMTP. |

The quirks database contains entries for many additional devices (phones, cameras, tablets, audio players, drones, etc.) but these are sourced from libmtp data and vendor specifications, not from SwiftMTP testing. See `Specs/quirks.json` for the full database.

## Help Wanted

Real-device testing is the main bottleneck. If you have an MTP device and want to help:

1. **Run a probe**: `swift run --package-path SwiftMTPKit swiftmtp probe` and share the output
2. **Try file listing**: `swift run --package-path SwiftMTPKit swiftmtp ls`
3. **Report results**: Open an issue with your device model, VID:PID, and what worked/failed
4. **Submit a snapshot**: `swift run --package-path SwiftMTPKit swiftmtp snapshot` captures device metadata for debugging

Known blockers we need help with:
- Samsung Galaxy: MTP handshake fails after USB claim — transport fixes shipped, awaiting retest with real device
- Pixel 7: bulk transfer timeout on macOS — transport fixes shipped, awaiting retest
- OnePlus: write path returns InvalidParameter — need to determine if this is a path or format issue
- Canon/Nikon: no one has tried connecting a camera yet

## Installation & Setup

### Prerequisites
- **macOS 26.0+** (Apple Silicon or Intel)
- **Xcode 16.0+** with Swift 6
- `libusb` via Homebrew: `brew install libusb`

### Quick Start (CLI)
```bash
cd SwiftMTPKit
swift run swiftmtp --help
```

### Quick Start (GUI)
```bash
cd SwiftMTPKit
swift run SwiftMTPApp
```

## Verification & Testing

~9,191+ tests executed across 20 test targets, using `VirtualMTPDevice` (in-memory mock) extensively. Includes unit, BDD (CucumberSwift), property-based (SwiftCheck), snapshot, and fuzz tests. Real-device tests require physical hardware.

### Full Verification Suite
```bash
./run-all-tests.sh
```

### Targeted Tests
```bash
# From SwiftMTPKit directory
cd SwiftMTPKit

swift test --filter CoreTests           # Core protocol and codec
swift test --filter BDDTests            # CucumberSwift scenarios
swift test --filter PropertyTests       # SwiftCheck property tests
swift test --filter SnapshotTests       # Visual regression
```

### Protocol Fuzzing
```bash
./SwiftMTPKit/run-fuzz.sh
```

## Demo Mode

Develop without physical hardware using simulated profiles:

```bash
export SWIFTMTP_DEMO_MODE=1
export SWIFTMTP_MOCK_PROFILE=pixel7  # Options: pixel7, galaxy, iphone, canon

cd SwiftMTPKit
swift run swiftmtp probe
```

GUI users can toggle simulation via the Orange Play button in the toolbar.

## Building from Source

```bash
git clone https://github.com/effortlessmetrics/swiftmtp.git
cd swiftmtp/SwiftMTPKit
swift build
```

### Building XCFramework (Required for libusb)
```bash
./scripts/build-libusb-xcframework.sh
```

### Code Quality
```bash
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests
```

## Project Structure

```
SwiftMTP/
├── SwiftMTPKit/           # Swift Package root
│   ├── Sources/
│   │   ├── SwiftMTPCore/          # Core MTP protocol
│   │   ├── SwiftMTPTransportLibUSB/
│   │   ├── SwiftMTPIndex/         # SQLite indexing
│   │   ├── SwiftMTPSync/           # Mirror/sync
│   │   ├── SwiftMTPUI/             # SwiftUI views
│   │   ├── SwiftMTPQuirks/        # Device quirks
│   │   ├── SwiftMTPObservability/  # Logging
│   │   ├── SwiftMTPStore/         # Persistence
│   │   └── Tools/                 # CLI & App targets
│   └── Tests/                    # 20 test targets
├── Docs/                  # Documentation
│   ├── SwiftMTP.docc/     # DocC documentation
│   └── benchmarks/       # Performance data
├── Specs/                 # Schemas & quirks
├── legal/                 # Licensing
└── scripts/              # Build & release tools
```

## Documentation

- [Contribution guide](Docs/ContributionGuide.md)
- [Roadmap](Docs/ROADMAP.md)
- [Testing guide](Docs/ROADMAP.testing.md)
- [Device submission workflow](Docs/ROADMAP.device-submission.md)
- [Pixel 7 debug report](Docs/pixel7-usb-debug-report.md)
- [File Provider tech preview](Docs/FileProvider-TechPreview.md)
- [Troubleshooting](Docs/Troubleshooting.md)

## Licensing

SwiftMTP is dual-licensed:
- **AGPL-3.0** for open-source use
- **Commercial license** for closed-source/App Store distribution

See [`legal/outbound/COMMERCIAL-LICENSE.md`](legal/outbound/COMMERCIAL-LICENSE.md) or contact git@effortlesssteven.com.

## Acknowledgments

- [libusb](https://libusb.info/) for cross-platform USB access
- [CucumberSwift](https://github.com/Tyler-Keith-Thompson/CucumberSwift) for BDD testing
- [SwiftCheck](https://github.com/typelift/SwiftCheck) for property-based testing
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) for visual regression
