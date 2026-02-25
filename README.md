# SwiftMTP

Swift-native Media Transfer Protocol stack with device quirks, modern SwiftUI implementation, and comprehensive verification suite.

A privacy-safe, evidence-gated MTP implementation for macOS and iOS with adaptive device handling and comprehensive device quirk support.

## Release and roadmap status

- Current release train: `2.0.0` (2026-02-08)
- Active work: 2.1.x planning with stability and documentation improvements
- Change tracking: [`CHANGELOG.md`](CHANGELOG.md)
- Docs index: [`Docs/README.md`](Docs/README.md)
- Delivery plan: [`Docs/ROADMAP.md`](Docs/ROADMAP.md)
- Sprint execution playbook: [`Docs/SPRINT-PLAYBOOK.md`](Docs/SPRINT-PLAYBOOK.md)
- Release prep: [`Docs/ROADMAP.release-checklist.md`](Docs/ROADMAP.release-checklist.md)
- Testing gates: [`Docs/ROADMAP.testing.md`](Docs/ROADMAP.testing.md)
- Contribution workflow: [`Docs/ContributionGuide.md`](Docs/ContributionGuide.md)
- Operator troubleshooting: [`Docs/Troubleshooting.md`](Docs/Troubleshooting.md)

## Start Here for Implementation Sprints

Use this order when joining an active sprint:

1. Read scope and acceptance criteria in [`Docs/ROADMAP.md`](Docs/ROADMAP.md).
2. Confirm operating rules in [`Docs/SPRINT-PLAYBOOK.md`](Docs/SPRINT-PLAYBOOK.md).
3. Run the `Sprint Readiness Loop` below.
4. For transport/quirk changes, capture evidence with `device-bringup`.
5. Update docs + `CHANGELOG.md` in the same PR.

Weekly sprint rhythm:

- Monday: confirm scope, risks, and ready-state of sprint items.
- Midweek: run checkpoint gates and resolve drift (test/docs/CI).
- Friday: close or carry over items using DoD from the sprint playbook.

## Sprint Readiness Loop

Use this command loop for implementation sprints:

```bash
# 1) Build + targeted checks while iterating
swift build --package-path SwiftMTPKit
swift test --package-path SwiftMTPKit --filter CoreTests

# 2) No-hardware smoke contract checks
./scripts/smoke.sh

# 3) Milestone/full gate before merge
./run-all-tests.sh
```

For real-device mode evidence capture:

```bash
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1
```

## 🚀 Swift 6 Actor-Based Architecture

SwiftMTP is built with modern Swift 6 concurrency patterns:

### Package Structure
- **`SwiftMTPCore`**: Actor-isolated MTP protocol implementation with async/await
- **`SwiftMTPTransportLibUSB`**: USB transport layer using libusb with fallback support
- **`SwiftMTPIndex`**: SQLite-based device content indexing and snapshots
- **`SwiftMTPSync`**: Mirror, sync, and diff operations with conflict resolution
- **`SwiftMTPUI`**: Modern SwiftUI library using `@Observable` for reactive data flow
- **`SwiftMTPQuirks`**: Device-specific tuning database with learned profiles
- **`SwiftMTPObservability`**: Structured logging and performance monitoring
- **`SwiftMTPStore`**: Persistence layer for device metadata and transfer journals
- **`swiftmtp-cli`**: High-performance CLI tool for automation and power users
- **`SwiftMTPApp`**: Standalone macOS GUI application for device management

### Key Features

- **Privacy-First Design**: Read-only collection mode with strict defaults
- **Device Quirks System**: Learned profiles and static quirks for 50+ devices
- **Transfer Journaling**: Resumable operations with automatic recovery
- **File Provider Integration**: Native Finder integration on macOS (XPC service)
- **Benchmarking Suite**: Performance profiling with p50/p95 metrics
- **Demo Mode**: Simulated hardware profiles for development without physical devices

## 🛠 Installation & Setup

### Prerequisites
- **macOS Tahoe 26.0+** (macOS 2026, requires Apple Silicon or Intel Mac with Tahoe upgrade)
- **iOS 26.0+** (partial support: index, sync, and FileProvider operations; USB transport requires macOS host)

- **macOS 26.0+** / **iOS 26.0+**
- **Xcode 16.0+** with Swift 6 (`6.2` recommended)
- `libusb` installed via Homebrew: `brew install libusb`

### Quick Start (GUI)
```bash
swift run --package-path SwiftMTPKit SwiftMTPApp
```

### Quick Start (CLI)
```bash
swift run swiftmtp --help
```

### Homebrew Installation
```bash
brew tap effortlessmetrics/swiftmtp
brew install swiftmtp
```

## 🧪 Verification & Testing

SwiftMTP utilizes a multi-layered verification strategy:

### Full Verification Suite
```bash
./run-all-tests.sh
```

By default this runs:
- SwiftMTPKit matrix (BDD + property + fuzz + integration + unit + e2e + snapshot + storybook)
- Xcode app + unit + UI automation tests (set `RUN_XCODE_UI_TESTS=0` to skip UI tests)

### BDD Scenarios (CucumberSwift)
```bash
swift test --package-path SwiftMTPKit --filter BDDTests
```

### Property-Based Testing (SwiftCheck)
```bash
swift test --package-path SwiftMTPKit --filter PropertyTests
```

### Snapshot & Visual Regression
```bash
swift test --package-path SwiftMTPKit --filter SnapshotTests
```

### Protocol Fuzzing
```bash
./SwiftMTPKit/run-fuzz.sh
```

### Interactive Storybook (CLI)
```bash
./SwiftMTPKit/run-storybook.sh
```

## 📱 Supported Devices

| Device | VID:PID | Status | Notes |
|--------|---------|--------|-------|
| Google Pixel 7 | 18d1:4ee1 | ⚠️ Experimental | Uses quirk-gated reset+reopen ladder on OpenSession I/O failures |
| OnePlus 3T | 2a70:f003 | ⚠️ Partial | Probe/read stable; write-path tuning is still in-progress |
| Xiaomi Mi Note 2 | 2717:ff10 / 2717:ff40 | ✅ Stable | ff40 variant uses vendor-specific MTP interface matching |
| Samsung Galaxy S21 | 04e8:6860 | ⚠️ Experimental | Requires storage unlock prompt; class 0xff interface |
| Canon EOS (Rebel / R-class) | 04a9:3139 | 🧪 Experimental | PTP over USB; camera must be in PTP/MTP mode |
| Nikon DSLR / Z-series | 04b0:0410 | 🧪 Experimental | MTP/PTP mode required; NEF files need extended IO timeout |

See [`Docs/SwiftMTP.docc/Devices/`](Docs/SwiftMTP.docc/Devices/) for device-specific tuning guides.

### Connected Device Lab (repeatable host workflow)
```bash
swift run swiftmtp device-lab connected --json
```

Artifacts are written under `Docs/benchmarks/connected-lab/<timestamp>/` with per-device JSON reports.

### Device Bring-Up Wrapper (mode evidence capture)
```bash
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x18d1 --pid 0x4ee1
```

This captures `system_profiler` USB data, `swiftmtp usb-dump`, and `device-lab` outputs under `Docs/benchmarks/device-bringup/<timestamp>-<mode>/`.
See [`Docs/device-bringup.md`](Docs/device-bringup.md) for the `(device × mode × operation)` matrix.

## 🎮 Demo Mode & Simulation

Develop without physical hardware using simulated profiles:

```bash
# Enable demo mode
export SWIFTMTP_DEMO_MODE=1

# Select mock profile
export SWIFTMTP_MOCK_PROFILE=pixel7  # Options: pixel7, galaxy, iphone, canon

# Run CLI in demo mode
swift run swiftmtp probe
```

GUI users can toggle simulation via the Orange Play button in the toolbar.

## 📊 Performance

Benchmark results from real devices:

| Device | Read Speed | Write Speed | Status |
|--------|------------|-------------|--------|
| Google Pixel 7 | N/A | N/A | Blocked on Tahoe 26 bulk-transfer timeout |
| OnePlus 3T | N/A | N/A | Probe/read stable, large write path in progress |
| Samsung Galaxy S21 | 15.8 MB/s | 12.4 MB/s | Experimental but measurable |

See [`Docs/benchmarks.md`](Docs/benchmarks.md) for detailed performance analysis.

## 📖 Development

### Documentation
- [Contribution guide](Docs/ContributionGuide.md)
- [Roadmap and milestones](Docs/ROADMAP.md)
- [Sprint playbook](Docs/SPRINT-PLAYBOOK.md)
- [Testing guide](Docs/ROADMAP.testing.md)
- [Device submission workflow](Docs/ROADMAP.device-submission.md)
- [Release runbook](RELEASE.md)

### Building from Source
```bash
git clone https://github.com/effortlessmetrics/swiftmtp.git
cd swiftmtp
swift build
```

### Building XCFramework (Required)
```bash
./scripts/build-libusb-xcframework.sh
```

### DocC Preview
```bash
swift package --disable-sandbox preview-documentation --target SwiftMTPCore
```

### Code Quality
```bash
swift-format -i -r Sources Tests
swift-format lint -r Sources Tests
```

## 📁 Project Structure

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
│   └── Tests/                    # BDD, Property, Snapshot
├── Docs/                  # Documentation
│   ├── SwiftMTP.docc/     # DocC documentation
│   └── benchmarks/       # Performance data
├── Specs/                 # Schemas & quirks
├── legal/                 # Licensing
└── scripts/              # Build & release tools
```

## ⚖️ Licensing

SwiftMTP is dual-licensed:
- **AGPL-3.0** for open-source use
- **Commercial license** for closed-source/App Store distribution

See [`legal/outbound/COMMERCIAL-LICENSE.md`](legal/outbound/COMMERCIAL-LICENSE.md) or contact git@effortlesssteven.com.

## 🏆 Acknowledgments

- [CucumberSwift](https://github.com/Tyler-Keith-Thompson/CucumberSwift) for BDD testing
- [SwiftCheck](https://github.com/typelift/SwiftCheck) for property-based testing
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) for visual regression
- [libusb](https://libusb.info/) for cross-platform USB access
