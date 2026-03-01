# SwiftMTP

A Swift-native MTP (Media Transfer Protocol) implementation for macOS. Early development — the protocol layer is well-tested with mocks, but real-device support is still being built out.

## Project Status

SwiftMTP is in **early development**. The core MTP protocol, codec, and session management are implemented and covered by an extensive test suite using in-memory mock devices (`VirtualMTPDevice`). Real-device testing is in its early stages — only one device (Xiaomi Mi Note 2) has completed successful file transfers through SwiftMTP.

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

- **Device Quirks Database**: 20,000+ entries across ~1,100 vendor IDs, sourced from libmtp data and vendor specs. This is research-based scaffolding — only a handful of devices have been tested with SwiftMTP directly.
- **Transfer Journaling**: Resumable file operations with automatic recovery. Implemented and tested with mocks; limited real-device validation.
- **File Provider Integration**: Native Finder integration on macOS via XPC. Tech preview, read-only.
- **Demo Mode**: Simulated device profiles (pixel7, galaxy, iphone, canon) for development without physical hardware.

## Device Status

Honest status of devices that have quirk entries with any level of real testing:

| Device | VID:PID | Status | Notes |
|--------|---------|--------|-------|
| Xiaomi Mi Note 2 | 2717:ff10 | Partial | Only device with real file transfer data. Requires kernel detach; no GetObjectPropList. |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | Untested | Has quirk entry. Recent lab run returned 0 storages. |
| Samsung Galaxy S7 | 04e8:6860 | Not Working | USB claim succeeds but MTP handshake fails. |
| Google Pixel 7 | 18d1:4ee1 | Blocked | Bulk transfer timeout — likely macOS kernel-level issue. See [debug report](Docs/pixel7-usb-debug-report.md). |
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
- Samsung Galaxy: MTP session open fails after USB claim — need someone with a Samsung device to debug
- Pixel 7: bulk transfer timeout on macOS — may be a kernel/driver issue
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

Test coverage uses `VirtualMTPDevice` (in-memory mock) extensively. Real-device tests require physical hardware.

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
│   └── Tests/                    # 15 test targets
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
