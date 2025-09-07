# SwiftMTP
Swift-native Media Transfer Protocol CLI with device quirks + JSON tooling

A privacy-safe, evidence-gated MTP implementation for macOS and Linux with adaptive device handling and comprehensive device quirk support.

## Installation

### Homebrew (Recommended)
```bash
brew tap your-org/homebrew-tap
brew install swiftmtp
swiftmtp --version
```

### Manual Install
```bash
# Download the latest release
curl -LO https://github.com/your-org/SwiftMTP/releases/download/v1.0.0/swiftmtp-macos-arm64.tar.gz

# Verify checksum
shasum -a 256 swiftmtp-macos-arm64.tar.gz

# Extract and verify
tar -xzf swiftmtp-macos-arm64.tar.gz
./swiftmtp version --json | jq
```

### Linux
```bash
# Download Linux build
curl -LO https://github.com/your-org/SwiftMTP/releases/download/v1.0.0/swiftmtp-linux-x86_64-v1.0.0.tar.gz
tar -xzf swiftmtp-linux-x86_64-v1.0.0.tar.gz
./swiftmtp --version
```

## Quick Start

### First Run
```bash
# Check version and build info
swiftmtp version

# Probe for connected MTP devices
swiftmtp probe

# List storage devices on your device
swiftmtp storages

# Show device configuration layers
swiftmtp quirks --explain
```

### Device Targeting
```bash
# Target specific device by VID/PID
swiftmtp probe --vid 2717 --pid ff10

# Target by USB bus and address
swiftmtp probe --bus 2 --address 3

# List files in root directory
swiftmtp ls --vid 2717 --pid ff10
```

### Device Contribution (Help Improve Compatibility)
```bash
# Collect device data for submission (safe, read-only)
swiftmtp collect --noninteractive --strict --json \
  --vid 2717 --pid ff10 --bundle Contrib/submissions/xiaomi-mi-note2-ff10-$(date +%Y%m%d-%H%M)

# Validate your submission
./scripts/validate-submission.sh Contrib/submissions/xiaomi-mi-note2-ff10-*
```

## Features

- **Privacy-safe**: HMAC-SHA256 redaction, no personal data collection
- **Device quirks**: Adaptive handling for device-specific behaviors
- **JSON-first**: Structured output with schema versioning
- **Comprehensive operations**: probe, storages, ls, pull, push, delete, move, events
- **Cross-platform**: macOS (Intel/Apple Silicon) and Linux support
- **Evidence-gated**: Bench gates ensure reliability before quirks are applied

## Exit Codes

- `0` - Success
- `64` - Usage error (bad arguments)
- `69` - Unavailable (device not found, permission denied)
- `70` - Internal error (unexpected failure)
- `75` - Temporary failure (device busy/timeout)

## Licensing

SwiftMTP is dual-licensed: **AGPL-3.0** for open-source use and a **commercial license** for closed-source/App Store/OEM distribution.

See `/legal/outbound/COMMERCIAL-LICENSE.md` or contact licensing@effortlessmetrics.com.

### Quick FAQ

**Q: Can I use SwiftMTP in my closed-source app?**
A: Under **AGPL-3.0**, the combined work must be AGPL if you distribute it. For closed-source/App Store use, obtain a **commercial license**.

**Q: Does AGPL trigger over USB/local use?**
A: AGPL's network clause applies to network interaction; your obligations are primarily distribution-based. When linking the library into an app you distribute, AGPL applies to the combined work.

**Q: Is libusb (LGPL-2.1) compatible with iOS/macOS?**
A: Yes via **dynamic** linking. Include the libusb license and notices.

**Q: Do I need to publish my modifications?**
A: If you distribute a modified SwiftMTP under AGPL, yes—publish the source of your modifications. Under the **commercial license**, no.

## Development

### Prerequisites
- macOS 12.0+ or Ubuntu 22.04+
- Xcode 14.0+ (macOS) or Swift toolchain (Linux)
- Swift 5.7+
- libusb development headers

### Building from Source
```bash
# Clone the repository
git clone https://github.com/your-org/swiftmtp.git
cd swiftmtp

# Use the wrapper script for CLI commands
./scripts/swiftmtp.sh --help

# Or use Swift Package Manager directly
cd SwiftMTPKit
swift run swiftmtp probe
```

### CLI Usage Examples
```bash
# Probe for MTP devices
./scripts/swiftmtp.sh probe

# List storage devices
./scripts/swiftmtp.sh storages

# List files
./scripts/swiftmtp.sh ls

# Download a file
./scripts/swiftmtp.sh pull <handle> <output-path>
```

## Legal Compliance

This project includes third-party components. See `/legal/licenses/THIRD-PARTY-NOTICES.md` for details.
