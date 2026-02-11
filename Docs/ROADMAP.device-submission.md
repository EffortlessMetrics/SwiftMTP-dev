# SwiftMTP Device Submission Guide

This guide explains how to submit new device profiles (quirks) to SwiftMTP for inclusion in the official quirks database.

## Overview

Device submissions help SwiftMTP recognize and properly handle MTP/PTP devices with unique characteristics. A complete submission includes:

- Device identification (VID:PID, fingerprint)
- Tuning parameters (timeouts, chunk sizes)
- Benchmarks demonstrating performance
- USB communication traces for debugging

## Prerequisites

### Required Tools

```bash
# Install dependencies
brew install jq python3

# For schema validation (optional but recommended)
pip install jsonschema  # or: npm install -g ajv-cli
```

### Device Preparation

1. **Enable Developer Options** on your Android device
2. **Enable USB Debugging** (Settings → Developer Options)
3. **Set USB Mode to MTP** (not PTP or File Transfer)
4. **Unlock device** and accept "Trust this computer" prompt
5. **Keep screen unlocked** during testing

## Step-by-Step Submission Process

### Step 1: Collect Device Data

#### Option A: Using the Benchmark Script (Recommended)

```bash
# Navigate to project root
cd /path/to/SwiftMTP

# Run comprehensive device collection
./scripts/benchmark-device.sh <device-name>

# Example for a new Pixel device
./scripts/benchmark-device.sh pixel-8-pro
```

This script will:
- Build the SwiftMTP CLI
- Probe the device for capabilities
- Run benchmarks (100M, 500M, 1G transfers)
- Test mirror functionality
- Generate a report

#### Option B: Manual Collection

```bash
# Build CLI
cd SwiftMTPKit
swift build --configuration release

# Probe device
swift run swiftmtp --real-only probe > ../probes/my-device.txt

# Run benchmarks
swift run swiftmtp --real-only bench 100M --repeat 3 --out ../benches/my-device-100m.csv
swift run swiftmtp --real-only bench 500M --repeat 3 --out ../benches/my-device-500m.csv
swift run swiftmtp --real-only bench 1G --repeat 3 --out ../benches/my-device-1g.csv
```

### Step 2: Create Submission Bundle

Create a directory structure for your submission:

```
Contrib/submissions/<device-id>-<timestamp>/
├── submission.json          # Submission manifest
├── probe.json              # Device probe output
├── usb-dump.txt            # USB communication trace
├── quirk-suggestion.json   # Proposed quirk entry
├── bench-100m.csv          # Benchmark results
├── bench-500m.csv          # Benchmark results
├── bench-1g.csv            # Benchmark results
└── .salt                   # Privacy salt (NOT committed)
```

### Step 3: Generate Submission Manifest

Create `submission.json`:

```json
{
  "schemaVersion": "1.0.0",
  "tool": {
    "name": "swiftmtp",
    "version": "2.0.0",
    "commit": "abc1234"
  },
  "host": {
    "os": "macOS 14.4",
    "arch": "arm64"
  },
  "timestamp": "2026-02-08T10:30:00Z",
  "user": {
    "github": "yourusername"
  },
  "device": {
    "vendorId": "0x18D1",
    "productId": "0x4EE1",
    "vendor": "Google",
    "model": "Pixel 7",
    "interface": {
      "class": "0x06",
      "subclass": "0x01",
      "protocol": "0x01",
      "in": "0x81",
      "out": "0x01",
      "evt": "0x82"
    },
    "fingerprintHash": "sha256:...",
    "serialRedacted": "hmacsha256:..."
  },
  "artifacts": {
    "probe": "probe.json",
    "usbDump": "usb-dump.txt",
    "bench": ["bench-100m.csv", "bench-500m.csv", "bench-1g.csv"]
  },
  "consent": {
    "anonymizeSerial": true,
    "allowBench": true
  }
}
```

### Step 4: Create Quirk Suggestion

Create `quirk-suggestion.json` following the schema:

```json
{
  "schemaVersion": "1.0.0",
  "id": "google-pixel-7-4ee1",
  "match": {
    "vidPid": "0x18D1:0x4EE1"
  },
  "status": "experimental",
  "confidence": "medium",
  "overrides": {
    "maxChunkBytes": 2097152,
    "handshakeTimeoutMs": 20000,
    "ioTimeoutMs": 30000,
    "inactivityTimeoutMs": 10000,
    "overallDeadlineMs": 180000,
    "stabilizeMs": 2000,
    "resetOnOpen": false
  },
  "hooks": [],
  "benchGates": {
    "readMBps": 35.0,
    "writeMBps": 25.0
  },
  "provenance": {
    "submittedBy": "yourusername",
    "date": "2026-02-08"
  }
}
```

### Step 5: Validate Submission

Run the validation scripts:

```bash
# Validate quirks format
./scripts/validate-quirks.sh

# Validate submission bundle
./scripts/validate-submission.sh Contrib/submissions/my-device/
```

**Expected output for valid submission:**
```
🔍 Validating SwiftMTP device submission
=======================================
Bundle: Contrib/submissions/my-device/

✅ All required files present
✅ JSON syntax is valid
✅ Submission manifest valid
✅ Probe JSON structure valid
✅ Quirk suggestion valid
✅ Benchmark CSVs valid
✅ Privacy redaction validated

🎉 Submission validation complete!
   All checks passed. Ready for submission.
```

### Step 6: Submit Pull Request

1. Fork the repository
2. Create a branch: `git checkout -b device/my-new-device`
3. Add your submission files
4. Update `Specs/quirks.json` with your suggestion
5. Run `./scripts/validate-quirks.sh` one more time
6. Commit and push
7. Open a pull request

## Reference: Validation Scripts

### validate-quirks.sh

Validates the quirks database against the JSON schema.

```bash
./scripts/validate-quirks.sh
```

**Checks performed:**
- JSON syntax validity
- Schema version compatibility
- Entry ID uniqueness
- Artifact file references
- Benchmark gate validation
- DocC generator availability

### validate-submission.sh

Validates a complete device submission bundle.

```bash
./scripts/validate-submission.sh <bundle-directory>
```

**Checks performed:**
- Required files present
- JSON syntax and schema validation
- USB dump privacy redaction
- Salt file existence (not committed)
- Benchmark CSV format

### benchmark-device.sh

Collects comprehensive device data for submission.

```bash
./scripts/benchmark-device.sh <device-name>
```

**Output:**
- `benches/<device>/bench-*.csv` - Benchmark results
- `probes/<device>-probe.txt` - Device probe
- `logs/<device>-mirror.log` - Mirror test log
- `benches/<device>/benchmark-report.md` - Summary report

## Reference: Schemas

### quirk-suggestion.schema.json

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schemaVersion` | string | Yes | Schema version (e.g., "1.0.0") |
| `id` | string | Yes | Unique quirk identifier |
| `match.vidPid` | string | Yes | VID:PID in format "0xABCD:0x1234" |
| `status` | enum | Yes | "experimental", "stable", "deprecated" |
| `confidence` | enum | Yes | "low", "medium", "high" |
| `overrides.*` | various | No | Tuning parameters |
| `hooks` | array | No | Phase-specific hooks |
| `benchGates` | object | No | Minimum performance thresholds |
| `provenance` | object | Yes | Submission metadata |

### submission.schema.json

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schemaVersion` | string | Yes | Schema version |
| `tool` | object | Yes | SwiftMTP version info |
| `host` | object | Yes | Test environment |
| `timestamp` | string | Yes | ISO 8601 timestamp |
| `device` | object | Yes | Device identification |
| `artifacts` | object | Yes | File references |
| `consent` | object | Yes | User consent flags |

## Privacy Requirements

All submissions MUST:

- [ ] Have serial numbers redacted (use HMAC-SHA256)
- [ ] Have user paths removed from USB dumps
- [ ] Have host identifiers removed
- [ ] Have `.salt` file NOT committed to git

### Redaction Patterns Checked

```bash
# validate-submission.sh checks for:
Serial Number: <REDACTED>
iSerial: <redacted>
/Users/<username>/ -> /Users/<redacted>/
C:\Users\<username>\ -> C:\Users\<redacted>\
```

## Common Issues

### "Missing required field"

Ensure all schema-required fields are present. Run with `jq` for detailed errors:

```bash
jq -e '.device.vendorId' submission.json
```

### "Benchmark CSV invalid header"

CSV files must have header:
```
timestamp,operation,size_bytes,duration_seconds,speed_mbps
```

### "Salt file is committed"

Remove from git and add to `.gitignore`:
```bash
git rm --cached .salt
echo ".salt" >> .gitignore
```

## Next Steps

After your submission is merged:

1. Your device will be listed in `Docs/SwiftMTP.docc/Devices/`
2. Automatic DocC documentation will be generated
3. Device will be included in benchmark reports
4. Community can test with your quirk settings

---

*See also: [ROADMAP.md](ROADMAP.md) | [Testing Guide](ROADMAP.testing.md) | [Release Checklist](ROADMAP.release-checklist.md)*
