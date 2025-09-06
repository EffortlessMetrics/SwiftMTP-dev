# SwiftMTP-dev
Swift-native MacOS and iOS MTP library

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

## Getting Started

### Prerequisites
- macOS 12.0+
- Xcode 14.0+
- Swift 5.7+

### Building
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

### CLI Usage
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

### Submit my device

Help improve SwiftMTP by submitting device data for your MTP device. This enables better compatibility and performance optimizations.

```bash
# Safe, read-only by default:
swift run swiftmtp collect --noninteractive --strict --json \
  --vid <hex> --pid <hex> --bundle Contrib/submissions/vendor-model-<date>
./scripts/validate-submission.sh Contrib/submissions/vendor-model-<date>

# (Optional) open a PR with your bundle; CI will validate privacy & schema.
```

**Privacy**: Serial numbers are redacted using HMAC-SHA256; no personal data or device contents are collected.

**Exit codes**: `0=ok`, `64=usage`, `69=unavailable`, `70=software`, `75=tempfail`.

## Legal Compliance

This project includes third-party components. See `/legal/licenses/THIRD-PARTY-NOTICES.md` for details.
