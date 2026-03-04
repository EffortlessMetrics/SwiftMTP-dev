# Troubleshooting

> **Pre-Alpha Note**: SwiftMTP is in pre-alpha with limited real-device validation. Many of the device-specific solutions below are based on research and initial testing — your mileage may vary. If you encounter issues not covered here, please open an issue with your device model, VID:PID, and the exact error.

Comprehensive troubleshooting guide for SwiftMTP operations.

## Table of Contents

1. [Quick Fixes](#quick-fixes)
2. [Known Device Status](#known-device-status)
3. [USB Claim Debugging](#usb-claim-debugging)
4. [Device Detection Issues](#device-detection-issues)
5. [Transfer Problems](#transfer-problems)
6. [Performance Issues](#performance-issues)
7. [Error-Specific Solutions](#error-specific-solutions)
8. [Samsung Galaxy Troubleshooting](#samsung-galaxy-troubleshooting)
9. [Google Pixel Troubleshooting](#google-pixel-troubleshooting)
10. [OnePlus Troubleshooting](#oneplus-troubleshooting)
11. [macOS-Specific Issues](#macos-specific-issues)
12. [Common macOS Issues](#common-macos-issues)
13. [Submission & Benchmark Issues](#submission--benchmark-issues)
14. [Diagnostic Commands](#diagnostic-commands)

---

## Quick Fixes

Start here if you're experiencing issues:

1. **Unplug and reconnect** the device
2. **Unlock** the device screen
3. **Confirm USB mode** is set to **File Transfer (MTP)** not PTP or charging
4. **Close competing apps**: Android File Transfer, adb, photo apps, browsers
5. **Try a different USB cable/port** (avoid unpowered hubs)

---

## Known Device Status

Current real-device test status (see CLAUDE.md for full details):

| Device | VID:PID | Status | Notes |
|--------|---------|--------|-------|
| Xiaomi Mi Note 2 | 2717:ff10 | **Partial** | Only device with real transfer data |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | **Partial** | Recent lab run returned 0 storages |
| Samsung Galaxy S7 (SM-G930W8) | 04e8:6860 | **Not Working** | Handshake fails after USB claim |
| OnePlus 3T | 2a70:f003 | **Partial** | Probe/read works; writes fail with 0x201D |
| Google Pixel 7 | 18d1:4ee1 | **Blocked** | Bulk transfer timeout — macOS kernel issue |
| Canon EOS Rebel / R-class | 04a9:3139 | **Research Only** | Never connected to SwiftMTP |
| Nikon DSLR / Z-series | 04b0:0410 | **Research Only** | Never connected to SwiftMTP |

> **Note:** SwiftMTP is pre-alpha. Most test coverage uses `VirtualMTPDevice` (in-memory mock). Only the Xiaomi Mi Note 2 (ff10) has completed real file transfers.

---

## USB Claim Debugging

When SwiftMTP cannot claim a USB device, another process is usually holding the interface. Use these steps to diagnose and resolve claim conflicts.

### Check Which Process Has the Device

```bash
# List processes using USB devices
lsof /dev/cu.usbmodem*

# Inspect the macOS USB device tree
ioreg -p IOUSB -l

# Show USB devices with vendor/product info
system_profiler SPUSBDataType
```

### Common macOS Processes That Grab USB Devices

These macOS services automatically claim MTP/PTP devices on connection:

| Process | What It Does | How to Stop |
|---------|-------------|-------------|
| `PTPd` | PTP camera daemon | `killall PTPd` (restarts automatically) |
| `Photos` | Imports from cameras/phones | Quit Photos before connecting |
| `Image Capture` | Image import agent | Quit or disable (see below) |
| `AMPDeviceDiscoveryAgent` | Apple Music/device pairing | Usually harmless; quit if conflicting |
| `adb` | Android Debug Bridge | `adb kill-server` |

### Disable Auto-Grabbing (Image Capture)

Prevent macOS Image Capture from automatically claiming USB devices:

```bash
defaults write com.apple.ImageCapture disableHotPlug -bool YES
```

To re-enable:

```bash
defaults delete com.apple.ImageCapture disableHotPlug
```

### Inspect the USB Tree with `ioreg`

```bash
# Full USB tree with properties
ioreg -p IOUSB -l

# Filter to a specific vendor (e.g., Samsung 04e8)
ioreg -p IOUSB -l | grep -A 20 "Samsung"

# Show just device names and addresses
ioreg -p IOUSB -w 0 | grep -i "+-o"
```

Look for `IOService` entries with `USBDeviceFunction` — if another driver is listed under `IOProviderClass`, that driver has claimed the device.

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

**Cause:** Device restricts writes to certain folders or rejects the write outright. This is a common failure on **OnePlus 3T** (2a70:f003) where probe and read succeed but all writes return 0x201D.

**Solutions:**
- Write to a writable folder instead of root:
  - Use `0` or explicit folder name for `push` command
  - Try: `Download`, `DCIM`, or nested folders
- Check device quirk notes for folder restrictions
- On OnePlus 3T specifically:
  - Confirm device is on Android 9+ (earlier firmware has wider write restrictions)
  - Try writing to `Internal storage/Download/` — some firmware builds only allow writes there
  - Run `swiftmtp quirks` and verify the `oneplus-3t-f003` profile is active
  - Status: **Partial** — reads work, writes remain blocked by 0x201D on tested firmware

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

> **See also**: [Error Catalog](ErrorCatalog.md) for a complete reference of all MTP response codes, transport errors, and recovery strategies.

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

## Samsung Galaxy Troubleshooting

**Status:** Not Working — handshake fails after USB claim (tested on Galaxy S7, SM-G930W8, VID:PID 04e8:6860)

### Symptoms
- `swiftmtp probe` detects the device but `OpenSession` never completes
- Log shows `USB claim succeeded` followed by handshake timeout or protocol error
- Known 512-byte packet boundary bug in Samsung's MTP stack

### Debugging Steps

1. **Ensure MTP mode** (Samsung defaults to charging-only on many cables):
   - Settings → Developer Options → USB Configuration → **MTP (Media Transfer Protocol)**
   - If Developer Options isn't visible: Settings → About Phone → tap Build Number 7 times
2. **Unlock the screen** and authorize the computer when prompted
3. **Disable USB debugging** — ADB and MTP cannot share the USB interface simultaneously
4. **Replug the cable** after changing USB mode (Samsung doesn't hot-switch reliably)
5. Try toggling: switch to PTP, wait 5 seconds, switch back to MTP
6. Use a **USB-A cable** directly to the Mac (USB-C adapters add negotiation latency)

### Current Theory

Samsung's MTP stack requires a specific initialization sequence with precise timing on the 512-byte packet boundaries. SwiftMTP's current handshake does not yet match this sequence. Reboot the phone and reconnect within 10 seconds as a workaround — the Samsung USB stack may hold stale sessions.

---

## Google Pixel Troubleshooting

**Status:** Blocked — bulk transfer timeout, likely macOS kernel issue (tested on Pixel 7, VID:PID 18d1:4ee1)

### Symptoms
- USB claim works, control transfers work (OpenSession succeeds)
- Bulk OUT returns `sent=0` — data path is broken
- `LIBUSB_ERROR_TIMEOUT` in logs after a successful handshake
- `swiftmtp probe` succeeds but `swiftmtp ls` hangs or returns timeout

### Debugging Steps

1. **Verify MTP mode** on the Pixel:
   - Settings → Connected Devices → USB → **File Transfer / Android Auto**
2. Use a **direct USB-A port** (not a hub or USB-C adapter) — macOS 26 Tahoe has known USB-C timing regressions
3. Keep `stabilizeMs` elevated (≥ 600 ms): `swiftmtp quirks` to confirm active quirk
4. Run `swiftmtp probe` first and wait for ✅ before any transfer command

### libmtp Workaround

libmtp uses a reset+retry loop for Pixel bulk transfer failures. This does not currently work in SwiftMTP's implementation because the macOS kernel does not re-enumerate the device after a USB reset in the same process.

### Current Theory

The bulk transfer timeout is a macOS kernel-level issue with the Pixel 7's USB controller. Control-plane operations succeed, but the data plane (bulk OUT endpoint) never completes. This is documented in detail in `Docs/pixel7-usb-debug-report.md`. Awaiting kernel-level fix in macOS 26 Tahoe.

---

## OnePlus Troubleshooting

**Status:** Partial — probe and read work, writes fail with 0x201D InvalidParameter (tested on OnePlus 3T, VID:PID 2a70:f003)

### Symptoms
- `swiftmtp probe` and `swiftmtp ls` succeed normally
- All write operations (`push`, `SendObject`) return `Protocol error InvalidParameter (0x201D)`
- Large writes (> 512 MB) stall at 50–80% with timeout

### Debugging Steps

1. Confirm device is on **Android 9+** (earlier firmware has wider write restrictions)
2. Write to a specific folder — OnePlus may require explicit storage/folder targeting:
   - Try: `Internal storage/Download/`, `DCIM/`, or other user-writable folders
   - Root-level writes are rejected on all tested firmware
3. Run `swiftmtp quirks` and verify the `oneplus-3t-f003` profile is active
4. For large files: use `--chunk 1M` to limit write-chunk size (device firmware rejects 8 MB default chunks)
5. Keep transfers under 500 MB per session; reconnect between large sessions

### Current Theory

OnePlus requires specific storage/folder targeting for write operations. The device's MTP stack rejects `SendObjectInfo` when the parent object handle doesn't match an explicitly writable directory. This is distinct from a permission error — the device returns `InvalidParameter` rather than `AccessDenied`.

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

### Samsung Galaxy S7 Handshake Failure

**Known Issue:** Samsung Galaxy S7 (SM-G930W8, VID:PID 04e8:6860) fails during MTP handshake after USB interface claim.

**Symptoms:**
- `swiftmtp probe` detects the device but `OpenSession` never completes
- Log shows `USB claim succeeded` followed by handshake timeout or protocol error
- Device may appear briefly then disconnect

**Solutions:**
1. Ensure the device is set to **File Transfer (MTP)** — Samsung defaults to charging-only on many cable types
2. Disable **USB debugging** in Developer Options — ADB and MTP cannot share the interface simultaneously
3. Try toggling USB mode: switch to PTP, wait 5 s, switch back to MTP
4. Use a USB-A cable directly to the Mac (USB-C adapters add negotiation latency that triggers the timeout)
5. If the handshake still fails, the Samsung USB stack may be holding a stale session — reboot the phone and reconnect within 10 s
6. Status: **Not Working** — handshake fails on all tested firmware versions. Samsung's MTP stack requires a specific init sequence that SwiftMTP does not yet implement.

### Pixel 7 / macOS 26 Tahoe Issues

**Known Issue:** macOS 26 Tahoe USB stack timing on Pixel 7 — bulk transfer path times out even though control-plane (`OpenSession`) succeeds.

**Symptoms:**
- `swiftmtp probe` succeeds but `swiftmtp ls` hangs or returns timeout
- `LIBUSB_ERROR_TIMEOUT` in logs after a successful handshake

**Solutions:**
- Keep `stabilizeMs` elevated (≥ 600 ms); use `swiftmtp quirks` to confirm active quirk
- Treat `LIBUSB_ERROR_TIMEOUT` as a transport-layer symptom, not a protocol error
- Use a direct USB-A port (not a hub or USB-C adapter); macOS 26 Tahoe has known USB-C timing regressions
- Run `swiftmtp probe` first and wait for the ✅ before any transfer command
- Status: **Blocked** — awaiting kernel-level fix in macOS 26 Tahoe beta chain (see `Docs/pixel7-usb-debug-report.md`)

### OnePlus 3T Issues

**Known Issue:** OnePlus 3T (2a70:f003) has two distinct failure modes:

1. **0x201D write rejection** — all writes return `InvalidParameter (0x201D)` regardless of target folder. Probe and read operations work. See [Write Fails with 0x201D Error](#write-fails-with-0x201d-error) above.
2. **`SendObject` timeout on large writes** (> 512 MB) — uploads stall at 50–80%.

**Symptoms:**
- `swiftmtp push` returns `Protocol error InvalidParameter (0x201D)` on any write attempt
- Upload of large files (videos, disk images) stalls at 50–80% and returns `timeout`
- `swiftmtp push` exits with code 1 and `Device timed out` message

**Solutions:**
- For 0x201D: see the [0x201D section](#write-fails-with-0x201d-error) — write to `Download/` or `DCIM/`, confirm Android 9+
- For large-write timeouts: use `--chunk 1M` to limit write-chunk size; the device firmware cannot handle default 8 MB chunks reliably
- Keep transfers under 500 MB per session; reconnect between large sessions
- Confirm the device is on Android 9 or later (earlier builds have a SCSI bridge bug)
- Workaround: use `--size` flag to split large files before pushing
- Status: **Partial** — probe/read works, writes fail with 0x201D on tested firmware

### Canon EOS / DSLR Issues

**Known Issue:** Canon EOS devices expose both MTP and PTP interfaces; macOS Image Capture claims the PTP interface on connection.

**Symptoms:**
- `swiftmtp probe` returns `permissionDenied` or `noDevice`
- Images are visible in Photos but not via SwiftMTP

**Solutions:**
1. Quit Image Capture and Photos before running SwiftMTP
2. Set the camera to **MTP** mode in its USB connection settings (not PTP or PC Remote)
3. Run `swift run swiftmtp probe` within 5 s of connection; macOS may re-claim after idle
4. For Canon R-series: enable "WiFi + USB" in connection settings to force MTP over PTP

### Nikon DSLR Issues

**Known Issue:** Nikon Z-series and D-series require the `Nikon Object` vendor extension for NEF raw files; standard `GetObject` may return an empty blob.

**Symptoms:**
- `.NEF` files download as 0-byte files
- `objectNotFound` for raw files that are visible on the camera LCD

**Solutions:**
1. Use `swiftmtp quirks` to confirm the `allowNikonExtensions` flag is active
2. Set Nikon USB to **MTP/PTP** (not PC Control) — PC Control mode disables file access
3. For large NEF files (> 50 MB): increase `ioTimeoutMs` via `--timeout 30000` flag
4. If the issue persists, use in-camera formatting on the SD card and re-import

---

## Common macOS Issues

### TSAN Interceptor Failure on macOS 26 / Xcode 26.x

**Error:** `Interceptors are not working. This may be caused by a non-instrumented library`

**Cause:** Xcode 26.x TSAN runtime conflicts with DTXConnectionServices.

**Solutions:**
- Pin **Xcode 16.2** for TSAN runs: `xcode-version: '16.2'` in CI
- Use `setup-swift` action for Swift 6.2 toolchain independent of Xcode
- CI uses `continue-on-error: true` on TSAN jobs as mitigation
- Monitor Xcode 26.x releases for a fix

### libusb Homebrew vs System Conflict

**Symptoms:** Build fails with `ld: library not found for -lusb-1.0` or runtime crash with mismatched libusb versions.

**Solutions:**
1. Use the project's XCFramework: `./scripts/build-libusb-xcframework.sh`
2. If using Homebrew libusb: ensure `PKG_CONFIG_PATH` includes `/opt/homebrew/lib/pkgconfig`
3. Do not mix Homebrew and system libusb — pick one and remove the other
4. After switching: `cd SwiftMTPKit && swift package clean && swift build`

### SIP and USB Entitlements

**Issue:** App Store distribution requires USB entitlements that conflict with SIP (System Integrity Protection).

**Solutions:**
- Development: use `com.apple.security.device.usb` entitlement in debug signing
- For App Store: USB access requires a DriverKit extension or approved entitlement
- File Provider extension uses XPC bridge to avoid direct USB entitlement in the app target
- See `Docs/FileProvider-TechPreview.md` for the sandboxed architecture

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

### Quick Reference

```bash
swift run swiftmtp probe --verbose    # Detailed USB/MTP probe
swift run swiftmtp device-lab         # Full device test matrix
ioreg -p IOUSB -l                     # macOS USB device tree
system_profiler SPUSBDataType          # USB device info
```

### Basic Probe
```bash
swift run swiftmtp probe
```

### Verbose Probe (detailed USB/MTP negotiation output)
```bash
swift run swiftmtp probe --verbose
```

### List Tests (verify test count)
```bash
cd SwiftMTPKit
swift test list                    # preferred (--list-tests is deprecated)
swift test list 2>&1 | grep -c '/' # count test methods
```

### Full Diagnostics
```bash
swift run swiftmtp device-lab connected --json
```

### USB Traffic Capture
```bash
swift run swiftmtp usb-dump
```

### macOS USB Inspection
```bash
# Full USB device tree with all properties
ioreg -p IOUSB -l

# Compact USB tree (device names only)
ioreg -p IOUSB -w 0 | grep -i "+-o"

# System-level USB device report
system_profiler SPUSBDataType
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

## CI & Build Troubleshooting (Wave 28-29)

### TSAN Interceptor Failure on Xcode 26.x

**Error:** `Interceptors are not working. This may be caused by a non-instrumented library`

**Cause:** Xcode 26.3 RC2 TSAN runtime conflicts with DTXConnectionServices on CI runners.

**Solutions:**
- Pin Xcode 16.2 in CI: `xcode-version: '16.2'`
- Use `setup-swift` action for Swift 6.2 toolchain
- CI uses `continue-on-error: true` on TSAN jobs as mitigation
- Monitor Xcode 26.x releases for a fix

### `--list-tests` Deprecation Warning

**Warning:** `'--list-tests' option is deprecated; use 'swift test list' instead`

**Solutions:**
- Use `swift test list` instead of `swift test --list-tests`
- Both produce identical output; the new form is preferred from Swift 6.2+

### SPM Cache Missing on CI Jobs

**Issue:** TSAN and smoke CI jobs lack SPM dependency caching, causing full resolves on every run.

**Solutions:**
- Add `actions/cache` for `.build` directory in CI workflow
- This was fixed for the main `build-test` job; ensure TSAN and smoke jobs also cache

---

## Related Documentation

- [Error Catalog](ErrorCatalog.md) — complete error code reference with troubleshooting
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
4. macOS version: `sw_vers -productVersion` (macOS 15 Sequoia or macOS 26 Tahoe)
5. SwiftMTP version: `swift run swiftmtp version`
