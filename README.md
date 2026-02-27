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
- **Device Quirks System**: Learned profiles and static quirks for 3,200+ devices
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
| Xiaomi Mi Note 2 | 2717:ff10 | ✅ Promoted | Requires kernel detach; no GetObjectPropList |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | ✅ Promoted | Vendor-specific MTP interface matching |
| Samsung Galaxy | 04e8:6860 | ✅ Promoted | Requires storage unlock prompt; class 0xff interface |
| Samsung Galaxy MTP+ADB | 04e8:685c | ✔ Verified | Dual-interface MTP+ADB configuration |
| Google Pixel 7 | 18d1:4ee1 | ✅ Promoted | Quirk-gated reset+reopen ladder on OpenSession I/O failures |
| Google Nexus/Pixel MTP+ADB | 18d1:4ee2 | ✔ Verified | Dual-interface MTP+ADB |
| Google Pixel 3/4 | 18d1:4eed | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| OnePlus 3T | 2a70:f003 | ✅ Promoted | Probe/read stable; write-path tuning in progress |
| OnePlus 9 | 2a70:9011 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Motorola Moto G/E | 22b8:2e82 | ✔ Verified | GetObjectPropList supported |
| Motorola Moto G/E ADB | 22b8:2e76 | ✔ Verified | Dual-interface MTP+ADB |
| Sony Xperia Z | 0fce:0193 | ✔ Verified | GetObjectPropList supported |
| Sony Xperia Z3 | 0fce:01ba | ✔ Verified | GetObjectPropList supported |
| Sony Xperia XZ1 | 0fce:01f3 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| LG Android | 1004:633e | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| LG Android | 1004:6300 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| HTC Android | 0bb4:0f15 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Huawei Android | 12d1:107e | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Canon EOS Rebel / R-class | 04a9:3139 | ✅ Promoted | PTP over USB; camera must be in PTP/MTP mode |
| Canon EOS 5D Mark III | 04a9:3234 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Canon EOS R5 | 04a9:32b4 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Canon EOS R3 | 04a9:32b5 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Nikon DSLR / Z-series | 04b0:0410 | ✅ Promoted | MTP/PTP mode required; NEF files need extended IO timeout |
| Nikon Z6/Z7 | 04b0:0441 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Nikon Z6II/Z7II | 04b0:0442 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Fujifilm X-series | 04cb:0104 | ⚠ Proposed | Based on libmtp data; needs hardware validation |
| Samsung Galaxy S20/S21 | 04e8:6866 | ⚠ Proposed | Android MTP; broken proplist, long timeout |
| Samsung Galaxy Kies mode | 04e8:6877 | ⚠ Proposed | Kies mode MTP interface |
| LG V20/G5/G6 | 1004:61f1 | ⚠ Proposed | Android MTP with Android bugs |
| LG G4/V10 | 1004:61f9 | ⚠ Proposed | Android MTP with Android bugs |
| HTC U11/U12 | 0bb4:0f91 | ⚠ Proposed | Android MTP with Android bugs |
| HTC One M8/M9 | 0bb4:0ffe | ⚠ Proposed | Android MTP with Android bugs |
| Huawei P9/P10 | 12d1:1052 | ⚠ Proposed | Android MTP; broken proplist |
| Huawei P20 Pro/Mate 20 | 12d1:1054 | ⚠ Proposed | Android MTP; broken proplist |
| Huawei P30/Mate 30 | 12d1:10c1 | ⚠ Proposed | Android MTP; broken proplist |
| ASUS ZenFone 5 | 0b05:7770 | ⚠ Proposed | Android MTP with Android bugs |
| ASUS ZenFone 6 / ROG Phone | 0b05:7776 | ⚠ Proposed | Android MTP with Android bugs |
| Acer Iconia A500 | 0502:3325 | ⚠ Proposed | Android MTP; no proplist |
| Acer Iconia A700 | 0502:3378 | ⚠ Proposed | Android MTP; no proplist |
| Oppo/Realme Android | 22d9:0001 | ⚠ Proposed | Android MTP with Android bugs |
| Google Nexus One | 18d1:4e41 | ⚠ Proposed | Legacy Android MTP |
| Google Nexus 7 | 18d1:4e42 | ⚠ Proposed | Legacy Android MTP |
| Sony Xperia Z1 | 0fce:019e | ⚠ Proposed | GetObjectPropList supported |
| Sony Xperia Z5 | 0fce:01d9 | ⚠ Proposed | GetObjectPropList supported |
| Sony Xperia XZ | 0fce:01e7 | ⚠ Proposed | GetObjectPropList supported |
| Sony Alpha a7 III | 054c:0a79 | ⚠ Proposed | PTP/Camera; GetObjectPropList supported |
| Sony Alpha a7R IV | 054c:0a6f | ⚠ Proposed | PTP/Camera; GetObjectPropList supported |
| Panasonic Lumix G | 04da:2372 | ⚠ Proposed | PTP/Camera; GetObjectPropList supported |
| Olympus E-series | 07b4:0113 | ⚠ Proposed | PTP/Camera; GetObjectPropList supported |
| Ricoh/Pentax K-series | 25fb:0001 | ⚠ Proposed | PTP/Camera; GetObjectPropList supported |

Status: ✅ Promoted = fully verified with evidence · ✔ Verified = confirmed working · ⚠ Proposed = unverified, based on libmtp data

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
