# How to Troubleshoot Connection Issues

This guide helps you diagnose and fix common SwiftMTP connection problems.

## Quick Fix Checklist

Before diving deep, try these quick fixes:

- [ ] Unplug and reconnect the device
- [ ] Unlock the device screen
- [ ] Confirm USB mode is **File Transfer (MTP)**
- [ ] Close competing apps (Android File Transfer, adb, etc.)
- [ ] Try a different USB cable/port

## Common Problems

### Problem: "No MTP Device Found"

**Symptoms:**
- `swiftmtp probe` returns "No MTP device connected"
- Device doesn't appear in Finder

**Solutions:**

1. Verify device is in MTP mode:
   ```bash
   # On Android: Settings > Storage > USB Computer Connection
   # Select "File Transfer (MTP)"
   ```

2. Check cable is data-capable:
   ```bash
   # Try a known-good cable
   # Avoid charge-only cables
   ```

3. Try direct USB port:
   ```bash
   # Connect directly to Mac, not via hub
   ```

4. Run probe with verbose output:
   ```bash
   swift run swiftmtp probe --verbose
   ```

---

### Problem: Device Detected But Operations Fail

**Symptoms:**
- Device appears but transfers fail
- `permissionDenied` errors

**Solutions:**

1. Accept "Trust This Computer" prompt on device
2. Disable USB debugging (interferes with MTP):
   ```bash
   # On Android: Settings > Developer Options > USB Debugging = OFF
   ```
3. Check no other app has claimed the device

---

### Problem: Intermittent Connection

**Symptoms:**
- Device sometimes detected, sometimes not
- Flaky connections

**Solutions:**

1. Use high-quality USB cable
2. Connect directly to Mac (not via hub)
3. Ensure device has sufficient battery
4. Disable USB power saving:
   ```bash
   sudo pmset -a usbpowersleep 0
   ```

---

### Problem: Transfer Timeout

**Symptoms:**
- Operations hang then fail
- `TransportError.timeout`

**Solutions:**

1. Increase timeout:
   ```bash
   export SWIFTMTP_IO_TIMEOUT_MS=60000
   swift run swiftmtp pull /file.jpg
   ```

2. Use different USB port/cable
3. Close other USB applications
4. Keep device screen unlocked during transfer

---

### Problem: Write Fails with 0x201D Error

**Error:** `Protocol error InvalidParameter (0x201D)`

**Solutions:**

1. Write to a writable folder instead of root:
   ```bash
   # Try /Download, /DCIM, or nested folders
   swift run swiftmtp push photo.jpg --to /Download
   ```

2. Check device quirk notes for folder restrictions

---

### Problem: Slow Transfer Speeds

**Symptoms:**
- Transfer speeds below expectations

**Solutions:**

1. Check USB version (USB2 vs USB3)
2. Use direct port (not hub)
3. Verify cable is USB 3.0 capable
4. Check for background device operations (indexing, backup)

---

## Diagnostic Commands

### Basic Diagnostics

```bash
# Probe for devices
swift run swiftmtp probe

# Full device lab diagnostics
swift run swiftmtp device-lab connected --json

# USB traffic capture
swift run swiftmtp usb-dump
```

### Device Bring-Up

For new device troubleshooting:

```bash
./scripts/device-bringup.sh --mode mtp-unlocked --vid 0x1234 --pid 0x5678
```

This captures detailed evidence for analysis.

---

## Error Code Quick Reference

| Error | Meaning | Quick Fix |
|-------|---------|-----------|
| 0x2001 | Undefined | Reconnect device |
| 0x2002 | InvalidParameter | Check operation parameters |
| 0x2005 | InvalidStorageID | Refresh device |
| 0x2006 | InvalidObjectHandle | Re-enumerate files |
| 0x200B | StorageFull | Free device space |
| 0x200C | WriteProtected | Use different folder |
| 0x201D | Write Rejected | Try /Download folder |
| 0x201E | Session Conflict | Reconnect device |

See [Error Codes Reference](../reference/error-codes.md) for full details.

---

## macOS-Specific Issues

### Trust Prompt Not Appearing

1. Unlock device and replug USB
2. Reset USB daemon:
   ```bash
   sudo killall -HUP usbd
   ```
3. Check device is not locked/encrypted

### Finder Not Showing Device

1. Verify device is in MTP mode
2. Enable in Finder:
   ```
   Finder > Preferences > Sidebar > Enable CDs, DVDs, and iOS Devices
   ```
3. Restart Finder:
   ```bash
   killall Finder
   ```

---

## Getting Help

When opening an issue, include:

1. Command and exact exit code
2. One artifact folder path (if any)
3. Expected vs actual behavior (one sentence)
4. macOS version: `sw_vers -productVersion`
5. SwiftMTP version: `swift run swiftmtp version`

---

## Related Documentation

- [Error Codes Reference](../reference/error-codes.md)
- [Connect Device](connect-device.md)
- [Run Benchmarks](run-benchmarks.md)
- [Device Bring-Up Guide](../../device-bringup.md)
