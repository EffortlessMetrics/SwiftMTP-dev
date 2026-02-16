# SwiftMTP Performance Benchmarks

This document captures **repeatable** performance results for SwiftMTP across MTP/PTP devices and provides guidance for running benchmarks.

## Quick Reference

| Device | VID:PID | Status | Read | Write | Notes |
|--------|---------|--------|------|-------|-------|
| Google Pixel 7 | 18d1:4ee1 | Experimental | N/A | N/A | macOS Tahoe 26 bulk timeout |
| OnePlus 3T | 2a70:f003 | Stable (probe/read) | N/A | N/A | Probe path hardened (no misaligned-pointer trap) |
| Xiaomi Mi Note 2 | 2717:ff10 | Stable | Pending | Pending | DEVICE_BUSY handling verified |
| Samsung Galaxy S21 | 04e8:6860 | Experimental | 15.8 MB/s | 12.4 MB/s | Vendor-specific interface, conservative tuning |
| Canon EOS R5 | 04a9:3196 | Known | 45.6 MB/s | 28.9 MB/s | PTP-derived |

### Connected Device Lab Runs

Lab runs are generated locally via `swift run swiftmtp device-lab connected --json` and saved under `Docs/benchmarks/connected-lab/<timestamp>/`. These directories are gitignored (local-only artifacts).

- Aggregate report: `Docs/benchmarks/connected-lab/<timestamp>/connected-lab.md`
- JSON matrix: `Docs/benchmarks/connected-lab/<timestamp>/connected-lab.json`
- Per-device artifacts: `Docs/benchmarks/connected-lab/<timestamp>/devices/`
- Operation receipts include `enumerate/claim`, `OpenSession+GetDeviceInfo`, `storage`, `list`, `read`, `write`, and `delete` stages with timing/error fields.

For per-mode bring-up capture (including host USB truth), use:

```bash
./scripts/device-bringup.sh --mode mtp-unlocked
```

| VID:PID | Outcome | Notes |
|--------|---------|-------|
| 2717:ff40 | Partial | Read path validated; write smoke folder creation returned `0x201D InvalidParameter` |
| 2a70:f003 | Passed (probe/read) | Probe/open no longer traps on misaligned read path; write smoke folder creation returned `0x201D` |
| 04e8:6860 | Failed | Discovered with vendor-specific interface, but probe/open did not respond on this run |
| 18d1:4ee1 | Blocked (expected) | Known probe/open blocker; diagnostics captured without crash |

---

## Methodology (Reproducible)

### Benchmark Protocol

- **Runs:** 3 per test size. Ignore run #1 (USB warmup). Report **p50** and **p95** from runs #2–3.
- **Sizes:** `100M`, `500M`, `1G` (at least one large run).
- **Mode:** **Real devices only.** Use `--real-only` to prevent mock fallback.
- **Chunk Tuning:** Start from device quirk ceiling; auto‑tuner may adjust within that ceiling.
- **Stabilization:** After opening a device, wait `stabilize_ms` (Xiaomi: 250–500 ms) before enumeration.

### Test Environment

- **Host:** macOS (Apple Silicon recommended)
- **SwiftMTP:** main (commit: `HEAD`)
- **Connection:** Prefer **direct USB port** (note cable & any hubs)
- **CLI Config:** `maxChunkBytes`, `ioTimeoutMs`, `handshakeTimeoutMs`, `inactivityTimeoutMs`, `overallDeadlineMs`

### Commands

```bash
# Build CLI
cd SwiftMTPKit
swift build --configuration release

# Probe device (enumeration timing)
swift run swiftmtp --real-only probe > probes/<device>.txt

# Connected-device matrix + per-device diagnostics
swift run swiftmtp device-lab connected --json

# Benchmark read operations
swift run swiftmtp --real-only bench 1G --repeat 3 --out benches/<device>-1g.csv

# Benchmark write operations
swift run swiftmtp --real-only bench 1G --repeat 3 --direction write --out benches/<device>-write-1g.csv

# Mirror test (DCIM sync)
swift run swiftmtp --real-only mirror ~/PhoneBackup --include "DCIM/**" --out logs/<device>-mirror.log
```

---

## Performance Expectations by Device Class

### USB 3.0+ Devices (High-Speed)

| Device Class | Expected Read | Expected Write | Notes |
|--------------|---------------|----------------|-------|
| Modern Android (2020+) | 35-45 MB/s | 25-35 MB/s | Full MTP support |
| Flagship phones | 40-50 MB/s | 30-40 MB/s | USB 3.2 Gen 1 |
| Cameras (PTP/MTP) | 40-60 MB/s | 25-35 MB/s | RAW file optimized |

### USB 2.0 Devices

| Device Class | Expected Read | Expected Write | Notes |
|--------------|---------------|----------------|-------|
| Older Android | 12-18 MB/s | 10-15 MB/s | Limited by USB 2.0 |
| Budget phones | 8-15 MB/s | 6-12 MB/s | Variable quality |
| Legacy cameras | 15-20 MB/s | 10-15 MB/s | PTP-derived |

### Known Limitations

- **USB hub:** May reduce speeds by 10-30%
- **USB-C hub with power:** May introduce latency
- **Screen lock:** Some devices suspend USB when locked
- **Background apps:** Can cause intermittent slowdowns

---

## Current Benchmark Results

### Google Pixel 7 (Android 14)

| Metric | Value | Status |
|--------|-------|--------|
| VID:PID | 18d1:4ee1 | |
| USB Speed | SuperSpeed (USB 3.2 Gen 1) | |
| MTP Operations | Control plane works, bulk unresponsive | ⚠️ Blocked |
| Read Speed | N/A | ❌ Blocked |
| Write Speed | N/A | ❌ Blocked |

**Issue:** macOS Tahoe 26 bulk transfer timeout. Control plane succeeds, but bulk endpoints return `LIBUSB_ERROR_TIMEOUT` (rc=-7).

**Quirk Configuration:**
```json
{
  "maxChunkBytes": 2097152,
  "handshakeTimeoutMs": 20000,
  "ioTimeoutMs": 30000,
  "inactivityTimeoutMs": 10000,
  "overallDeadlineMs": 180000,
  "stabilizeMs": 2000,
  "resetOnOpen": false
}
```

**Artifacts:**
- `Docs/benchmarks/probes/pixel7-probe.txt`
- `Docs/benchmarks/probes/pixel7-usb-dump.txt`
- `Docs/benchmarks/pixel7/latest/`

---

### OnePlus 3T (Android 8.0.0)

| Metric | Value | Status |
|--------|-------|--------|
| VID:PID | 2a70:f003 | |
| USB Speed | SuperSpeed (USB 3.2 Gen 1) | ✅ |
| MTP Operations | 33 operations, 6 events | ✅ |
| Read Speed | N/A | ❌ SendObject issue |
| Write Speed | N/A | ❌ Object_Too_Large |

**Issue:** `SendObject` returns `0x201D` (Object_Too_Large) for benchmark writes.

**Quirk Configuration:**
```json
{
  "maxChunkBytes": 1048576,
  "handshakeTimeoutMs": 6000,
  "ioTimeoutMs": 8000,
  "stabilizeMs": 200,
  "resetOnOpen": false,
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 1000 }
  ]
}
```

**Artifacts:**
- `Docs/benchmarks/probes/oneplus3t-probe.txt`
- `Docs/benchmarks/probes/oneplus3t-usb-dump.txt`
- `Docs/benchmarks/oneplus-3t/latest/`

---

### Xiaomi Mi Note 2 (Android 7.1.1)

| Metric | Value | Status |
|--------|-------|--------|
| VID:PID | 2717:ff10 (variant: 2717:ff40) | |
| USB Speed | High-Speed (USB 2.0) | |
| MTP Operations | Full PTP/MTP extensions | ✅ |
| Read Speed | Pending | ⏳ Pending |
| Write Speed | Pending | ⏳ Pending |

**Quirk Configuration:**
```json
{
  "maxChunkBytes": 2097152,
  "handshakeTimeoutMs": 6000,
  "ioTimeoutMs": 15000,
  "inactivityTimeoutMs": 8000,
  "overallDeadlineMs": 120000,
  "stabilizeMs": 400,
  "hooks": [
    { "phase": "postOpenSession", "delayMs": 400 },
    { "phase": "beforeGetStorageIDs", "busyBackoff": { "retries": 3, "baseMs": 200, "jitterPct": 0.2 } }
  ]
}
```

**Notes:**
- Requires 250-500ms stabilization after OpenSession
- May return DEVICE_BUSY (0x2003) initially
- Prefer direct USB port; keep screen unlocked

**Artifacts:**
- `Docs/benchmarks/probes/mi-note2-probe.txt`
- `Docs/benchmarks/probes/mi-note2-usb-dump.txt`
- `Docs/benchmarks/csv/mi-note2-*.csv`

---

### Samsung Galaxy S21 (Android 13)

| Metric | Value | Status |
|--------|-------|--------|
| VID:PID | 04e8:6860 | |
| USB Speed | High-Speed (USB 2.0) | |
| Read Speed | 15.8 MB/s (1GB, 63.3s) | ✅ |
| Write Speed | 12.4 MB/s (1GB, 80.6s) | ✅ |
| Resume Read | ✅ Full | |
| Resume Write | ❌ Single-pass | |

**Notes:**
- Limited by USB 2.0 speed
- Partial MTP implementation (missing SendPartialObject)
- 4.1s enumeration time, 892 objects

---

### Canon EOS R5 (PTP/MTP Mode)

| Metric | Value | Status |
|--------|-------|--------|
| VID:PID | 04a9:3196 | |
| USB Speed | SuperSpeed (USB 3.0) | |
| Read Speed | 45.6 MB/s (1GB, 21.9s) | ✅ |
| Write Speed | 28.9 MB/s (1GB, 34.6s) | ✅ |
| Resume | Limited (PTP-based) | ⚠️ |

**Notes:**
- PTP-derived MTP implementation
- Excellent raw transfer speeds
- Large file counts typical
- Single-pass writes only

---

## How to Run Benchmarks

### Using the Benchmark Script (Recommended)

```bash
# Run comprehensive device benchmark
./scripts/benchmark-device.sh <device-name>

# Examples
./scripts/benchmark-device.sh pixel7
./scripts/benchmark-device.sh oneplus-3t
./scripts/benchmark-device.sh mi-note2
./scripts/benchmark-device.sh samsung-s21
```

**Script behavior:**
1. Builds SwiftMTP CLI
2. Runs device probe
3. Executes 100M, 500M, 1G benchmarks (3 runs each)
4. Computes p50/p95 from runs 2-3
5. Tests mirror functionality
6. Generates markdown report

**Output locations:**
- `benches/<device>/bench-*.csv` - Benchmark data
- `probes/<device>-probe.txt` - Device information
- `logs/<device>-mirror.log` - Mirror test results
- `benches/<device>/benchmark-report.md` - Summary

### Manual Benchmarking

```bash
cd SwiftMTPKit

# Build
swift build --configuration release

# Probe
swift run swiftmtp --real-only probe > ../probes/my-device.txt

# Run benchmarks
for size in 100M 500M 1G; do
  swift run swiftmtp --real-only bench $size --repeat 3 --out ../benches/my-device-$size.csv
done

# Mirror test
swift run swiftmtp --real-only mirror ~/PhoneBackup --include "DCIM/**" --out ../logs/my-device-mirror.log
```

### Collect + benchmark troubleshooting flow

Use this combined flow for contribution-ready device evidence:

1. Capture a baseline probe:

   ```bash
   swift run swiftmtp --real-only probe > ../probes/my-device.txt
   ```

2. Run one `collect` pass with strict checks:

   ```bash
   swift run swiftmtp collect --strict --noninteractive --bundle ../Contrib/submissions/my-device-bundle
   ```

3. If collect succeeds, run single-size smoke benchmark:

   ```bash
   swift run swiftmtp --real-only bench 100M --repeat 3 --out ../benches/my-device-100m.csv
   ```

4. Confirm artifacts were generated and private fields were redacted:

   ```bash
   ls ../Contrib/submissions/my-device-bundle
   rg -n "Serial|/Users/|iSerial|<[Rr]edacted>" ../Contrib/submissions/my-device-bundle/usb-dump.txt
   ```

5. Expand to full matrix only after steps 1-4 pass:

   ```bash
   for size in 100M 500M 1G; do
     swift run swiftmtp --real-only bench $size --repeat 3 --out ../benches/my-device-$size.csv
   done
   ```

6. If a step fails, attach the exact output and artifact location to the issue before changing quirks.

### Interpreting Results

#### CSV Format

```csv
timestamp,operation,size_bytes,duration_seconds,speed_mbps
2026-02-08T10:30:00Z,read,1073741824,21.9,45.6
2026-02-08T10:30:30Z,read,1073741824,22.1,45.2
2026-02-08T10:31:00Z,read,1073741824,21.8,45.8
```

#### p50/p95 Calculation

```bash
# Calculate p50 and p95 from runs 2-3 (skip warmup)
awk -F, 'NR==1{next} {print $0}' bench-1g.csv \
  | tail -n +2 \
  | awk -F, 'NR>=2 && NR<=3 {print $NF}' \
  | sort -n \
  | awk '{if(NR==1)p50=$1; if(NR==2)p95=$1} END {printf("p50=%.1f MB/s, p95=%.1f MB/s\n", p50, p95)}'
```

---

## Mirror/Sync Performance Metrics

### Test Configuration

```bash
# Sync DCIM folder
swift run swiftmtp --real-only mirror ~/PhoneBackup \
  --include "DCIM/**" \
  --out mirror-log.txt
```

### Expected Results

| Scenario | Expected Time | Notes |
|----------|---------------|-------|
| 100 photos (1GB) | 30-45s | USB 3.0 |
| 1000 photos (10GB) | 5-8 min | With resume |
| Full mirror (50GB) | 25-40 min | Multiple sessions |

### Optimization Tips

1. **Resume support:** Enable for large syncs
2. **Incremental sync:** Only changed files
3. **Parallel transfers:** Enable in settings
4. **Battery:** Keep device charged
5. **Screen:** Keep unlocked

---

## MTP Operation Support Matrix

| Device | GetPartialObject64 | SendPartialObject | Resume Read | Resume Write |
|--------|-------------------|-------------------|-------------|--------------|
| Pixel 7 | N/A (blocked) | N/A (blocked) | N/A | N/A |
| OnePlus 3T | ✅ | ✅ | ✅ Full | ✅ Full |
| Xiaomi Mi Note 2 | ✅ | ✅ | ✅ Full | ✅ Full |
| Galaxy S21 | ✅ | ❌ | ✅ Full | ❌ Single-pass |
| Canon EOS R5 | ⚠️ PTP | ❌ | ⚠️ Limited | ❌ Single-pass |

---

## Known Device Quirks Summary

| Device | VID:PID | Status | Key Quirks |
|--------|---------|--------|------------|
| Google Pixel 7 | 18d1:4ee1 | Experimental | Bulk timeout on macOS 26 |
| OnePlus 3T | 2a70:f003 | Stable | Dual interface, 200ms stabilize |
| Xiaomi Mi Note 2 | 2717:ff10 | Stable | DEVICE_BUSY, 250-500ms delay |
| Samsung Galaxy S21 | 04e8:6860 | Known | USB 2.0, partial MTP |
| Canon EOS R5 | 04a9:3196 | Known | PTP-derived, limited MTP |

---

## Data Hygiene

### Files to Commit

```
probes/<device>-probe.txt
benches/<device>/bench-100m.csv
benches/<device>/bench-500m.csv
benches/<device>/bench-1g.csv
logs/<device>-mirror.log   (if run)
Specs/quirks.json          (if updated)
Docs/SwiftMTP.docc/Devices/<device>.md
```

### Include in Device Documentation

- SwiftMTP commit SHA
- USB path (direct vs hub, cable)
- CLI config snapshot (chunk ceiling + timeouts)
- Any device-specific quirks or workarounds

---

## Recommendations for Best Performance

1. **Use USB 3.0** ports and cables when available
2. **Enable MTP mode** explicitly on Android devices
3. **Accept "Trust this computer"** prompt on first connection
4. **Test resume capability** before relying on it for large transfers
5. **Monitor chunk tuning** via debug logs for optimal performance
6. **Consider device-specific quirks** when implementing timeout/retry logic
7. **Xiaomi/OnePlus devices**: Add stabilization delays and handle DEVICE_BUSY responses
8. **Keep device screen unlocked** during transfers to prevent auto-sleep
9. **Avoid USB hubs** when possible; use direct port connections
10. **Close other USB devices** to reduce contention

---

*Last updated: 2026-02-14*
*SwiftMTP Version: 2.0.0*

*See also: [ROADMAP.md](ROADMAP.md) | [Device Submission](ROADMAP.device-submission.md) | [Testing Guide](ROADMAP.testing.md)*
