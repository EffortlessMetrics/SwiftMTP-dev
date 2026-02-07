# SwiftMTP
Swift-native Media Transfer Protocol stack with device quirks, modern SwiftUI implementation, and comprehensive verification suite.

A privacy-safe, evidence-gated MTP implementation for macOS and Linux with adaptive device handling and comprehensive device quirk support.

## 🚀 Modern Architecture

SwiftMTP has been modernized into a unified Swift Package structure:
- **`SwiftMTPCore`**: The core MTP protocol logic.
- **`SwiftMTPUI`**: A modern SwiftUI library using `@Observable` for high-performance reactive data flow.
- **`SwiftMTPApp`**: A standalone macOS GUI application for browsing and managing devices.
- **`swiftmtp`**: The high-performance CLI tool for automation and power users.

## 🛠 Installation & Setup

### Prerequisites
- **macOS 15.0+** (for modern SwiftUI features) or **Linux**
- **Xcode 16.0+** or **Swift 6.0+**
- `libusb` installed via Homebrew: `brew install libusb`

### Quick Start (GUI)
```bash
# Run the modern SwiftUI app directly from the root
swift run SwiftMTPApp
```

### Quick Start (CLI)
```bash
# Run the CLI tool
swift run swiftmtp --help
```

## 🧪 Verification & Testing

SwiftMTP utilizes a multi-layered verification strategy to ensure 100% reliability:

### 1. Full Verification Suite
Run the entire battery of tests (BDD, Property, Snapshot, Fuzzing, and E2E Demo) with one command:
```bash
./SwiftMTPKit/run-all-tests.sh
```

### 2. BDD Scenarios (CucumberSwift)
Validated behavior via Gherkin feature files.
```bash
swift test --filter BDDTests
```

### 3. Property-Based Testing (SwiftCheck)
Validates invariants across 100+ generated test cases.
```bash
swift test --filter PropertyTests
```

### 4. Snapshot & Visual Regression
Ensures UI components and data structures remain consistent.
```bash
swift test --filter SnapshotTests
```

### 5. Protocol Fuzzing
Stress tests protocol parsers against random input.
```bash
./SwiftMTPKit/run-fuzz.sh
```

### 6. Interactive Storybook (CLI)
Run an interactive end-to-end demo using simulated hardware profiles (Pixel 7, Galaxy, iPhone, Canon).
```bash
./SwiftMTPKit/run-storybook.sh
```

## 🚩 Feature Flags & Simulation

SwiftMTP supports "Demo Mode" for development without physical hardware:
- **Toggle Simulation**: Use the Orange Play button in the GUI toolbar.
- **Global Mocking**: `export SWIFTMTP_DEMO_MODE=1`
- **Select Profile**: `export SWIFTMTP_MOCK_PROFILE=iphone` (Options: `pixel7`, `galaxy`, `iphone`, `canon`)

## 📖 Development

### Building from Source
```bash
git clone https://github.com/your-org/swiftmtp.git
cd swiftmtp
swift build
```

### Documentation
SwiftMTP uses DocC for comprehensive documentation. To generate and view:
```bash
swift package --disable-sandbox preview-documentation --target SwiftMTPCore
```

## ⚖️ Licensing

SwiftMTP is dual-licensed: **AGPL-3.0** for open-source use and a **commercial license** for closed-source/App Store distribution.

See `/legal/outbound/COMMERCIAL-LICENSE.md` or contact licensing@effortlessmetrics.com.