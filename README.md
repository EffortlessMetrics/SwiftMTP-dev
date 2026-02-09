# SwiftMTP

Swift-native Media Transfer Protocol stack with device quirks, modern SwiftUI implementation, and comprehensive verification suite.

A privacy-safe, evidence-gated MTP implementation for macOS and Linux with adaptive device handling and comprehensive device quirk support.

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
- **macOS 15.0+** (for modern SwiftUI features) or **Linux**
- **Xcode 16.0+** or **Swift 6.0+**
- `libusb` installed via Homebrew: `brew install libusb`

### Quick Start (GUI)
```bash
cd SwiftMTPKit
swift run SwiftMTPApp
```

### Quick Start (CLI)
```bash
cd SwiftMTPKit
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
swift test --filter BDDTests
```

### Property-Based Testing (SwiftCheck)
```bash
swift test --filter PropertyTests
```

### Snapshot & Visual Regression
```bash
swift test --filter SnapshotTests
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
| Google Pixel 7 | 18d1:4ee1 | ✅ Stable | Full MTP, USB 3.0 |
| OnePlus 3T | 2a70:f003 | ⚠️ Experimental | Requires device trust |
| Xiaomi Mi Note 2 | 2717:ff10 | ⚠️ Known | Needs stabilization delay |
| Samsung Galaxy S21 | 04e8:6860 | ⚠️ Known | USB 2.0 limited |
| Canon EOS R5 | 04a9:3196 | ⚠️ Known | PTP-derived, limited MTP |

See [`Docs/SwiftMTP.docc/Devices/`](Docs/SwiftMTP.docc/Devices/) for device-specific tuning guides.

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

| Device | Read Speed | Write Speed | USB |
|--------|------------|-------------|-----|
| Google Pixel 7 | ~38 MB/s | ~32 MB/s | USB 3.0 |
| OnePlus 3T | TBD | TBD | USB 3.0 |

See [`Docs/benchmarks.md`](Docs/benchmarks.md) for detailed performance analysis.

## 📖 Development

### Building from Source
```bash
git clone https://github.com/effortlessmetrics/swiftmtp.git
cd swiftmtp/SwiftMTPKit
swift build
```

### Building XCFramework (Required)
```bash
./scripts/build-libusb-xcframework.sh
```

### Documentation
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

See [`legal/outbound/COMMERCIAL-LICENSE.md`](legal/outbound/COMMERCIAL-LICENSE.md) or contact licensing@effortlessmetrics.com.

## 🏆 Acknowledgments

- [CucumberSwift](https://github.com/Tyler-Keith-Thompson/CucumberSwift) for BDD testing
- [SwiftCheck](https://github.com/typelift/SwiftCheck) for property-based testing
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) for visual regression
- [libusb](https://libusb.info/) for cross-platform USB access
