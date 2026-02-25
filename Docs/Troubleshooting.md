# Troubleshooting

Comprehensive troubleshooting guide for SwiftMTP operations.

## Table of Contents

1. [Quick Fixes](#quick-fixes)
2. [Device Detection Issues](#device-detection-issues)
3. [Transfer Problems](#transfer-problems)
4. [Performance Issues](#performance-issues)
5. [Error-Specific Solutions](#error-specific-solutions)
6. [macOS-Specific Issues](#macos-specific-issues)
7. [Submission & Benchmark Issues](#submission--benchmark-issues)
8. [Diagnostic Commands](#diagnostic-commands)

---

## Quick Fixes

Start here if you're experiencing issues:

1. **Unplug and reconnect** the device
2. **Unlock** the device screen
3. **Confirm USB mode** is set to **File Transfer (MTP)** not PTP or charging
4. **Close competing apps**: Android File Transfer, adb, photo apps, browsers
5. **Try a different USB cable/port** (avoid unpowered hubs)

---

## Device Detection Issues

### No Device Detected

**Symptoms:**
- `swiftmtp probe` returns "No MTP device connected"
- Device doesn't appear in Finder

**Solutions:**
1. Verify device is in **File Transfer (MTP)** mode
2. Check USB cable is data-capable (not charge-only)
3. Try direct USB port (not hub)
4. Run: `swift run swiftmtp probe`

### Device Detected But Not Accessible

**Symptoms:**
- Device appears but operations fail
- `permissionDenied` error

**Solutions:**
1. Accept any "Trust This Computer" prompt on device
2. Check USB debugging is disabled (interferes with MTP)
3. Verify no other app has claimed the device

### Intermittent Detection

**Symptoms:**
- Device sometimes detected, sometimes not
- Flaky connections

**Solutions:**
1. Use a high-quality USB cable
2. Connect directly to Mac (not via hub)
3. Ensure device has sufficient battery
4. Disable USB power saving: `sudo pmset -a usbpowersleep 0`

---

## Transfer Problems

### Write Fails with 0x201D Error

**Error:** `Protocol error InvalidParameter (0x201D): write request rejected by device`

**Cause:** Device restricts writes to certain folders

**Solutions:**
- Write to a writable folder instead of root:
  - Use `0` or explicit folder name for `push` command
  - Try: `Download`, `DCIM`, or nested folders
- Check device quirk notes for folder restrictions

### Storage Full

**Error:** `MTPError.storageFull`

**Solutions:**
1. Free space on device
2. Delete unnecessary files
3. Check if device has multiple storage partitions

### Object Not Found

**Error:** `MTPError.objectNotFound`

**Solutions:**
1. Refresh the storage listing
2. Verify the object handle is still valid
3. Check if file was deleted externally

### Read-Only Storage

**Error:** `MTPError.readOnly`

**Solutions:**
1. Check SD card lock switch (if applicable)
2. Verify USB mode is MTP not PTP
3. Check device storage settings

---

## Performance Issues

### Slow Transfers

**Symptoms:**
- Transfer speeds below expectations
- Operations take unusually long

**Solutions:**
1. Check USB version (USB2 vs USB3)
2. Use a direct port (not hub)
3. Verify cable is USB 3.0 capable
4. Check for background device operations (indexing, backup)

### Benchmark Tuning

Run benchmarking to find optimal settings:
```bash
swift run swiftmtp bench 1G
```

The tuner automatically adjusts chunk size. See [Docs/benchmarks.md](benchmarks.md) for detailed analysis.

### Resume Not Working

**Cause:** Some devices don't advertise `GetPartialObject64`

**Solutions:**
- Reads restart by design on unsupported devices
- Use transfer journaling for write operations

---

## Error-Specific Solutions

### Exit Code 69 - No Device

**Command:** `swiftmtp events` exits with code 69

**Solutions:**
1. No matching device present or filter didn't match
2. Ensure device is connected in **File Transfer (MTP)** mode
3. Use explicit targeting: `--vid 0x2717 --pid 0xff40`
4. Run `swiftmtp probe` to verify detection

### Timeout Errors

**Error:** `TransportError.timeout` or `MTPError.timeout`

**Solutions:**
1. Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=30000`
2. Use different USB port/cable
3. Close other USB applications
4. Check device is not in low-power mode

### Permission Denied

**Error:** `MTPError.permissionDenied`

**Solutions:**
1. Verify app entitlements
2. Check system preferences for USB access
3. Run without sandbox for development

### Session Already Open (0x201E)

**Error:** `MTPError.protocolError(code: 0x201E, ...)`

**Solutions:**
1. Close other MTP sessions
2. Disconnect and reconnect device
3. Restart the device

---

## macOS-Specific Issues

### Trust Prompt Not Appearing

**Solutions:**
1. Unlock device and replug USB
2. Reset USB location: `sudo killall -HUP usbd`
3. Check device is not locked/encrypted

### Finder Not Showing Device

**Solutions:**
1. Verify device is in MTP mode
2. Open Finder → Preferences → Sidebar → Enable CDs, DVDs, and iOS Devices
3. Restart Finder: `killall Finder`

### Pixel 7 / Tahoe 26 Issues

**Known Issue:** macOS Tahoe 26 USB stack timing on Pixel 7

**Solutions:**
- Keep `stabilizeMs` elevated
- Treat `LIBUSB_ERROR_TIMEOUT` as transport layer symptom
- Use direct port and probe before benchmarking

---

## Submission & Benchmark Issues

### Canonical `collect` + `benchmark` Sequence

Use this exact sequence when gathering evidence for a device submission or debugging a transfer issue:

```bash
# Step 1: Confirm device is reachable
swift run swiftmtp probe

# Step 2: Capture a submission bundle (privacy-safe, JSON output)
swift run swiftmtp collect --strict --json --noninteractive

# Step 3: Validate the bundle (check redaction and required fields)
./scripts/validate-submission.sh Docs/benchmarks/<timestamp>/submission.json

# Step 4: Warm-up + single-size check (confirms write path is working)
swift run swiftmtp bench 100M --out /tmp/bench-100m.csv

# Step 5: Full benchmark at two sizes with 3 repeats
swift run swiftmtp bench 500M --repeat 3
swift run swiftmtp bench 1G --repeat 3

# Step 6: Snapshot for regression comparison
swift run swiftmtp snapshot --out /tmp/snapshot.json
```

**Expected artifacts after Step 5:**
- `/tmp/bench-100m.csv` — CSV with write+read speed per run
- `Docs/benchmarks/<timestamp>/submission.json` — privacy-safe device profile
- `Docs/benchmarks/<timestamp>/usb-dump.txt` — USB interface dump (redacted)

**If `collect` fails:**
1. Run `swift run swiftmtp probe` first — confirms MTP handshake works
2. If `DEVICE_BUSY` is returned, wait 30 s then retry (device may have a background sync in progress)
3. If `permissionDenied`, accept "Trust This Computer" on the device screen
4. Re-run with `--lax` to skip strict redaction check (not for submission — for local debug only)

**If `bench` fails mid-run:**
1. Check available storage: `swift run swiftmtp ls` — confirm at least 2× bench size is free
2. If timeout, the device dropped the session — reconnect and reduce to `--size 50M` to isolate
3. Use `swift run swiftmtp quirks` to check if the device has known write-timeout quirks

### Device Lab Diagnostics

```bash
swift run swiftmtp device-lab connected --json
```

Artifacts written to `Docs/benchmarks/connected-lab/<timestamp>/`.

### USB Dump Analysis

If `usb-dump.txt` contains serial numbers or paths:
1. Re-run with `--strict`
2. Check for patterns: `Serial Number`, `iSerial`, `/Users/<...>`, UUIDs
3. Report redaction failures

---

## Diagnostic Commands

### Basic Probe
```bash
swift run swiftmtp probe
```

### Full Diagnostics
```bash
swift run swiftmtp device-lab connected --json
```

### USB Traffic Capture
```bash
swift run swiftmtp usb-dump
```

### Device Bring-Up
```bash
./scripts/device-bringup.sh --mode <label> --vid <vid> --pid <pid>
```

See [Docs/device-bringup.md](device-bringup.md) for mode options.

---

## Pre-PR Local Gate

Before opening a PR, run this minimal gate to match CI checks:

```bash
# 1. Format (required — CI rejects unformatted code)
swift-format -i -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# 2. Lint (must be clean)
swift-format lint -r SwiftMTPKit/Sources SwiftMTPKit/Tests

# 3. Full test suite
cd SwiftMTPKit && swift test -v

# 4. TSAN on concurrency-heavy targets
swift test -Xswiftc -sanitize=thread --filter CoreTests --filter IndexTests --filter ScenarioTests

# 5. Quirks validation
./scripts/validate-quirks.sh
```

All five must pass before pushing. CI runs the same checks. The full matrix run (`./run-all-tests.sh`) is recommended for release PRs.

---

## Related Documentation

- [Error Codes Reference](ErrorCodes.md)
- [Migration Guide](MigrationGuide.md)
- [Benchmarks](benchmarks.md)
- [Device-Specific Guides](SwiftMTP.docc/Devices/)
- [Device Bring-Up](device-bringup.md)

---

## Getting Help

When opening issues, include:

1. Failing command and exact exit code
2. One artifact folder path under `Docs/benchmarks/`
3. Expected vs actual behavior (one sentence)
4. macOS version: `sw_vers -productVersion`
5. SwiftMTP version: `swift run swiftmtp version`
