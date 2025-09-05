# Device Contribution Guide

This guide explains how to contribute device support to SwiftMTP by submitting device evidence and quirk configurations.

## Overview

SwiftMTP uses a data-driven approach to device compatibility. Instead of hardcoded device support, we collect evidence from real devices and generate optimized configurations (called "quirks") based on observed behavior.

## Quick Start

### 1. Connect Your Device

Ensure your MTP device is:
- Connected via USB
- Unlocked/screen on
- Recognized by your operating system
- Not connected as "Charging only" (enable "File Transfer" mode)

### 2. Run the Collection Tool

The easiest way to contribute is using our automated collection tool:

```bash
# 1) Strict, no write ops, noninteractive, JSON summary:
swift run swiftmtp collect --noninteractive --strict --no-bench --json

# 2) With benchmarks:
swift run swiftmtp collect --noninteractive --strict --run-bench 100M,1G --json
```

### 3. Review and Submit

The tool will:
- ✅ Collect device information
- ✅ Run USB protocol analysis
- ✅ Generate performance benchmarks (if requested)
- ✅ Create a quirk suggestion
- ✅ Package everything into a submission bundle
- ✅ Optionally create a GitHub pull request

## Detailed Workflow

### Prerequisites

1. **SwiftMTP CLI**: Ensure you can run `swift run swiftmtp --help`
2. **Connected Device**: Your MTP device should be connected and accessible
3. **GitHub CLI** (optional): For automated PR creation, install `gh` and run `gh auth login`

### Step-by-Step Process

#### Step 1: Device Preparation

```bash
# Check if your device is detected
swift run swiftmtp probe

# If no device found, try:
# - Different USB port
# - Enable "File Transfer" mode on device
# - Unlock device screen
# - Check USB permissions (macOS: System Settings > Privacy & Security)
```

#### Step 2: Run Collection

Choose the appropriate collection mode:

```bash
# For basic device support
swift run swiftmtp collect --device-name "Your Device Name" --noninteractive

# For performance-optimized support (recommended)
swift run swiftmtp collect --device-name "Your Device Name" --run-bench 100M,1G

# For maximum compatibility data
swift run swiftmtp collect --device-name "Your Device Name" --run-bench 100M,1G,10G
```

#### Step 3: Review Generated Data

The tool creates a submission bundle in `Contrib/submissions/`:

```
Contrib/submissions/your-device-1234-abcd-2025-09-03/
├── submission.json          # Main manifest
├── probe.json              # Device capabilities
├── usb-dump.txt            # USB interface details
├── bench-100m.csv          # Benchmark results (if run)
├── bench-1g.csv            # Benchmark results (if run)
├── quirk-suggestion.json   # Generated quirk config
└── .salt                   # Redaction salt
```

#### Step 4: Validate Locally

Before submitting, validate your bundle:

```bash
./scripts/validate-submission.sh Contrib/submissions/your-device-1234-abcd-2025-09-03
```

This will check:
- ✅ JSON syntax and schema compliance
- ✅ Required files present
- ✅ Benchmark data integrity
- ✅ Privacy redaction applied

**Privacy checklist:**
- [ ] No personal paths, hostnames, or emails in USB dumps/logs
- [ ] No `.salt` in commits
- [ ] Bundle validated locally: `./scripts/validate-submission.sh Contrib/submissions/<bundle>`

#### Step 5: Submit

**Option A: Automated (Recommended)**

```bash
swift run swiftmtp collect --device-name "Your Device" --open-pr
```

**Option B: Manual**

```bash
# Create branch
git checkout -b device/your-device-name

# Add submission
git add Contrib/submissions/your-device-1234-abcd-2025-09-03

# Commit
git commit -s -m "Device submission: Your Device Name"

# Push
git push -u origin HEAD

# Create PR manually via GitHub web interface
```

## Collection Options

### Benchmark Sizes

Choose appropriate benchmark sizes based on your device:

- **100M**: Quick validation (recommended for most devices)
- **1G**: Standard performance characterization
- **10G**: Large transfer optimization (may take several minutes)

```bash
# Multiple sizes
--run-bench 100M,1G

# Single size
--run-bench 1G

# Skip benchmarks
--no-bench
```

### Device Naming

Use descriptive, consistent naming:

```bash
# Good examples
--device-name "Samsung Galaxy S21"
--device-name "Google Pixel 7 Pro"
--device-name "Xiaomi Mi Note 2"

# Avoid
--device-name "my phone"
--device-name "android device"
```

### Privacy and Automation

```bash
# Skip interactive prompts
--noninteractive

# Force real device (no mock fallback)
--real-only

# Enable debug output
--trace-usb
--trace-usb-details
```

## What Gets Collected

### Device Information
- Manufacturer and model
- USB Vendor/Product IDs
- Interface configuration
- MTP capabilities and operations
- Storage information

### USB Analysis
- Interface classes and protocols
- Endpoint configurations
- USB descriptor details
- Protocol compliance

### Performance Benchmarks
- Read/write throughput
- Transfer stability
- Error patterns
- Optimal chunk sizes

### Privacy Protection
- **Serial numbers**: HMAC-SHA256 redacted
- **Personal data**: Never collected
- **File contents**: Never accessed
- **Location data**: Never requested

## Understanding the Generated Quirk

The tool automatically generates a `quirk-suggestion.json` with:

```json
{
  "schemaVersion": "1.0.0",
  "id": "samsung-galaxy-s21-04e8-6860",
  "match": {
    "vidPid": "0x04e8:0x6860"
  },
  "status": "experimental",
  "confidence": "low",
  "overrides": {
    "maxChunkBytes": 2097152,
    "ioTimeoutMs": 15000,
    "stabilizeMs": 400
  },
  "hooks": [
    {
      "phase": "postOpenSession",
      "delayMs": 400
    }
  ],
  "benchGates": {
    "readMBps": 12.0,
    "writeMBps": 10.0
  }
}
```

This suggestion is reviewed by maintainers and may be:
- ✅ Accepted as-is
- 🔧 Refined based on additional testing
- 📊 Enhanced with community feedback

## Troubleshooting

### Device Not Found

```bash
# Check device detection
swift run swiftmtp probe

# Try different USB port
# Enable file transfer mode on device
# Check USB permissions
```

### Permission Denied

**macOS:**
```bash
# Check System Settings > Privacy & Security > USB
# Or reset USB permissions:
sudo killall usbd
```

**Linux:**
```bash
# Check udev rules
lsusb
ls /dev/bus/usb/
```

### Collection Fails

```bash
# Try with conservative settings
swift run swiftmtp collect --safe --device-name "Your Device"

# Enable detailed tracing
swift run swiftmtp collect --trace-usb-details --device-name "Your Device"
```

### Validation Errors

```bash
# Run validation with verbose output
./scripts/validate-submission.sh Contrib/submissions/your-device-dir

# Check for missing dependencies
python3 -c "import jsonschema"  # For schema validation
```

### Exit Codes

The collect command uses standard exit codes for reliable scripting:

- **0**: Success - device found and collection completed
- **64**: Usage error - invalid arguments or conflicting selectors
- **69**: Unavailable - no device found or device inaccessible

## Advanced Usage

### Custom Benchmark Sizes

```bash
# Very small for slow devices
swift run swiftmtp collect --run-bench 10M,50M

# Very large for fast devices
swift run swiftmtp collect --run-bench 1G,5G,10G
```

### Multiple Device Testing

```bash
# Test same device on different computers
swift run swiftmtp collect --device-name "Device on MacBook"
swift run swiftmtp collect --device-name "Device on Linux"

# Compare different firmware versions
swift run swiftmtp collect --device-name "Android 12"
swift run swiftmtp collect --device-name "Android 13"
```

### Integration with CI/CD

```bash
# Non-interactive mode for automation
swift run swiftmtp collect --noninteractive --no-bench

# Validate in CI
./scripts/validate-submission.sh Contrib/submissions/*
```

## Contributing Guidelines

### Device Support Levels

1. **Basic**: Device detected and basic operations work
2. **Standard**: Reliable transfers with good performance
3. **Optimized**: Tuned for maximum performance and reliability
4. **Certified**: Extensively tested across multiple environments

### Quality Standards

- ✅ **Required**: Device detection and basic file operations
- ✅ **Required**: No crashes or hangs
- ✅ **Recommended**: Good performance (>10MB/s read/write)
- ✅ **Recommended**: Stable large transfers
- ✅ **Optional**: Maximum optimization

### Community Support

- 📖 **Documentation**: Device-specific notes added to docs
- 🧪 **Testing**: Multiple users validate the quirk
- 📊 **Benchmarks**: Performance data from multiple systems
- 🔄 **Maintenance**: Updates for firmware changes

## Getting Help

- 📋 **Issues**: [GitHub Issues](https://github.com/your-org/swiftmtp/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/your-org/swiftmtp/discussions)
- 📖 **Documentation**: [Device Tuning Guide](./DeviceTuningGuide.md)

## Recognition

Contributors are recognized in:
- `Specs/quirks.json` provenance fields
- `CHANGELOG.md` for significant contributions
- GitHub release notes

Thank you for helping improve SwiftMTP device compatibility! 🎉
