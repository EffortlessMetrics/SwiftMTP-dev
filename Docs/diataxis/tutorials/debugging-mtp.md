# Debugging MTP Issues

This tutorial teaches you how to diagnose and resolve issues with MTP devices using SwiftMTP's debugging tools.

## What You'll Learn

- Interpret error codes and messages
- Use logging and tracing effectively
- Debug transfer failures
- Handle device-specific issues
- Capture diagnostic information for support

## Prerequisites

- Completed [Getting Started](tutorials/getting-started.md)
- A device with connection or transfer issues

## Step 1: Understanding Error Codes

MTP errors are represented as hex codes. Understanding them is crucial for debugging.

### Common Error Codes

| Error Code | Name | Meaning | Solution |
|------------|------|---------|----------|
| 0x2001 | Undefined | Unknown error | Reconnect device |
| 0x2002 | InvalidParameter | Invalid argument | Check operation parameters |
| 0x2005 | InvalidStorageID | Storage not found | Refresh device state |
| 0x2006 | InvalidObjectHandle | File/folder not found | Re-enumerate files |
| 0x200B | StorageFull | No space left | Free device storage |
| 0x200C | WriteProtected | Read-only storage | Use different folder |
| 0x2011 | AccessDenied | Permission denied | Accept trust prompt |
| 0x201D | StoreNotAvailable | Cannot write | Try /Download folder |
| 0x201E | SessionConflict | Session issue | Reconnect |

### Getting Detailed Error Information

```bash
# Run command with verbose output
swift run swiftmtp ls --verbose 2>&1

# Check exit code
swift run swiftmtp ls
echo "Exit code: $?"
```

### Error Context

Errors include context information:

```
[ERROR] Operation failed: GetObjectHandles
  Storage: 0x00010001
  Error: 0x2006 (InvalidObjectHandle)
  Hint: Object may have been deleted on device
```

## Step 2: Enabling Debug Logging

SwiftMTP provides multiple logging levels for debugging.

### Log Levels

```swift
// Set log level via environment
export SWIFTMTP_LOG_LEVEL=debug

// Run with debug output
swift run swiftmtp --verbose pull /file.jpg
```

### Log Levels Available

| Level | Description | Use Case |
|-------|-------------|----------|
| `error` | Only errors | Production |
| `warn` | Warnings + errors | Basic debugging |
| `info` | General info | Understanding flow |
| `debug` | Detailed debug | Deep debugging |
| `trace` | Protocol traces | Protocol-level issues |

### Component-Specific Logging

```swift
// Enable specific component logging
export SWIFTMTP_LOG_DEVICE=debug
export SWIFTMTP_LOG_TRANSFER=debug
export SWIFTMTP_LOG_USB=trace
```

## Step 3: Debugging Connection Issues

Connection problems are common. Here's how to diagnose them.

### USB Layer Debugging

```bash
# Capture USB traffic
swift run swiftmtp usb-dump --output usb-debug.txt
```

This shows:
- USB device enumeration
- Interface claiming
- Control transfers
- Endpoint communication
- Errors

### Common Connection Issues

#### Issue: "No MTP Device Found"

Diagnosis steps:

```bash
# 1. Check if device is visible to system
system_profiler SPUSBDataType | grep -i mtp

# 2. Check USB devices
ioreg -p IOUSB

# 3. Run probe with verbose output
swift run swiftmtp probe --verbose
```

Solution:
- Verify MTP mode enabled on device
- Use data-capable USB cable
- Connect directly to Mac (not hub)
- Accept trust prompt on device

#### Issue: Device Detected But Operations Fail

Diagnosis:

```bash
# Check if session can be opened
swift run swiftmtp device-info

# Try with longer timeouts
export SWIFTMTP_IO_TIMEOUT_MS=60000
swift run swiftmtp ls
```

Common causes:
- USB debugging enabled (interferes with MTP)
- Device locked
- Trust prompt not accepted
- Other app claiming device

## Step 4: Debugging Transfer Failures

Transfer issues require different debugging approaches.

### Enable Transfer Debugging

```bash
# Enable transfer-level logging
export SWIFTMTP_LOG_TRANSFER=debug
export SWIFTMTP_IO_TIMEOUT_MS=60000

# Run transfer
swift run swiftmtp pull /DCIM/Camera/photo.jpg --verbose
```

### Transfer Debug Output

```
[DEBUG] Transfer: Starting download
  Source: /DCIM/Camera/photo.jpg
  Handle: 0x0000002A
  Size: 4,194,304 bytes
[DEBUG] Transfer: Opening connection
[DEBUG] Transfer: Sending GetObject request
[DEBUG] Transfer: Receiving data (chunk 1/4)
[DEBUG] Transfer: Receiving data (chunk 2/4)
[DEBUG] Transfer: Receiving data (chunk 3/4)
[DEBUG] Transfer: Receiving data (chunk 4/4)
[DEBUG] Transfer: Complete
[INFO] Downloaded: 4.0 MB in 2.3s (1.7 MB/s)
```

### Debugging Specific Transfer Issues

#### Issue: Timeout During Transfer

```bash
# Increase timeout
export SWIFTMTP_IO_TIMEOUT_MS=120000

# Try transfer again
swift run swiftmtp pull /large-file.mp4
```

Also try:
- Different USB cable (USB 3.0 recommended)
- Direct port connection
- Keep device screen unlocked
- Close other apps

#### Issue: Corrupted Download

```bash
# Enable checksum verification
export SWIFTMTP_VERIFY_CHECKSUM=true

# Re-download with verification
swift run swiftmtp pull /file.jpg --verify
```

#### Issue: Partial Transfer

Some devices don't support resume:

```bash
# Check if device supports partial objects
swift run swiftmtp device-info | grep -i partial
```

If not supported, interrupted transfers cannot be resumed.

## Step 5: Debugging Device Quirks

Some devices require special handling via quirks.

### Identifying Quirk Issues

```bash
# Validate quirks for your device
swift run swiftmtp validate-quirks --vid 0x1234 --pid 0x5678
```

### Common Quirk Problems

| Symptom | Likely Quirk Issue |
|---------|-------------------|
| Slow transfers | `maxChunkBytes` too small |
| Timeouts on open | `handshakeTimeoutMs` too short |
| Intermittent failures | `stabilizeMs` needed |
| Write failures | Missing folder permissions |

### Testing Quirk Changes

```bash
# Apply test quirks via environment
export SWIFTMTP_TEST_QUIRK_maxChunkBytes=2097152
export SWIFTMTP_TEST_QUIRK_ioTimeoutMs=30000

# Test operations
swift run swiftmtp ls
```

## Step 6: Capturing Diagnostic Information

When reporting issues, capture comprehensive diagnostics.

### Full Diagnostic Capture

```bash
# Create diagnostic directory
mkdir -p ~/mtp-diagnostics/$(date +%Y%m%d)

# Capture all diagnostics
swift run swiftmtp probe --verbose > ~/mtp-diagnostics/$(date +%Y%m%d)/probe.txt
swift run swiftmtp device-info > ~/mtp-diagnostics/$(date +%Y%m%d)/device-info.txt
swift run swiftmtp usb-dump > ~/mtp-diagnostics/$(date +%Y%m%d)/usb-dump.txt

# Compress for sharing
tar -czvf mtp-diagnostics.tar.gz ~/mtp-diagnostics/
```

### Device Lab Diagnostics

```bash
# Generate full device lab report
swift run swiftmtp device-lab connected --json > device-lab-report.json
```

This includes:
- Device properties
- Capabilities
- Transfer performance
- Error history

### Automated Bring-Up Script

For new or problematic devices:

```bash
# Run full bring-up diagnostics
./scripts/device-bringup.sh \
  --mode mtp-unlocked \
  --vid 0x1234 \
  --pid 0x5678 \
  --output ~/mtp-diagnostics/
```

This captures everything needed for analysis.

## Step 7: Advanced Debugging

### Protocol Tracing

For deep protocol-level debugging:

```bash
# Enable protocol traces
export SWIFTMTP_LOG_PROTOCOL=trace

# Run operation
swift run swiftmtp ls
```

Protocol traces show:
- PTP/MTP packets sent/received
- Operation codes
- Parameter encoding
- Response codes

### USB Traffic Analysis

```bash
# Capture low-level USB
swift run swiftmtp usb-dump --hex --output usb-hex.txt
```

### Memory Debugging

For memory-related issues:

```bash
# Enable memory debugging
export SWIFTMTP_DEBUG_MEMORY=true

# Run with memory tracking
swift run swiftmtp ls
```

## Debugging Checklist

When facing issues, work through this checklist:

- [ ] Device in MTP mode (not PTP/charging)
- [ ] USB cable is data-capable
- [ ] Device screen unlocked
- [ ] Trust prompt accepted
- [ ] USB debugging disabled (Android)
- [ ] No other app using device
- [ ] Direct USB port (not hub)
- [ ] Try different port/cable
- [ ] Check error code meaning
- [ ] Enable debug logging
- [ ] Try with longer timeout
- [ ] Validate quirks

## Getting Help

If issues persist after debugging:

1. Capture full diagnostics (see Step 6)
2. Note exact error messages
3. Include device model and OS version
4. Document steps to reproduce
5. Open issue with diagnostic archive

## Next Steps

- 📋 [Device Probing](device-probing.md) - Analyze device capabilities
- 📋 [Connect Device](../howto/connect-device.md) - Fix connection issues
- 📋 [Device Quirks](../howto/device-quirks.md) - Configure device-specific settings
- 📋 [Run Benchmarks](../howto/run-benchmarks.md) - Test performance

## Summary

In this tutorial, you learned how to:

1. ✅ Understand MTP error codes
2. ✅ Enable debug logging
3. ✅ Debug connection issues
4. ✅ Debug transfer failures
5. ✅ Debug device quirks
6. ✅ Capture diagnostic information
7. ✅ Use advanced debugging tools

These skills are essential for troubleshooting MTP issues effectively.