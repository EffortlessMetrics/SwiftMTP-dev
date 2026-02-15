# Pixel 7 (18d1:4ee1) USB Debug Report - Complete Analysis

## Status: BLOCKED - Requires libusb source comparison

## Executive Summary

Pixel 7 in MTP mode (0x4ee1) fails with `sent=0` bulk OUT timeouts. This is NOT a timing issue - the device's bulk OUT endpoint fundamentally doesn't respond to SwiftMTP's commands but works (eventually) with libmtp.

## Key Findings

### 1. libmtp ALSO Fails Initially!

```
PTP_ERROR_IO: failed to open session, trying again after resetting USB interface
LIBMTP libusb: Attempt to reset device
libusb_detach_kernel_driver() failed, continuing anyway...: Operation timed out
```

libmtp fails on the first attempt, then resets the device, and succeeds on retry.

### 2. SwiftMTP Fails Even After Reset

- **libmtp**: fail → reset → retry → **SUCCESS**
- **SwiftMTP**: fail → reset (Pass 2) → re-claim → **STILL FAILS**

### 3. Control Transfers Work, Bulk Doesn't

```
[Ready] GetDeviceStatus len=8 → 0x2001  ← Control transfer works!
[Probe] write rc=-7 sent=0/12           ← Bulk OUT fails!
```

## What Was Tried

| Attempt | Result | Notes |
|---------|--------|-------|
| clear_halt before first command | ❌ | Endpoint still doesn't respond |
| 500ms pre-first-command delay | ❌ | Not a timing issue |
| 2000ms pre-first-command delay | ❌ | Not a timing issue |
| USB reset in Pass 1 | ❌ | Same failure |
| USB reset in Pass 2 | ❌ | Same failure |
| Try OpenSession first | ❌ | Any bulk command fails |
| Post-claim stabilize 3s | ❌ | Already tried |

## Root Cause Hypothesis

The issue is likely one of:

1. **Different libusb handle configuration** - libmtp might use different flags or settings
2. **Different reset sequence** - libmtp resets without re-claiming; we re-claim
3. **Different timing after reset** - libmtp might wait differently
4. **Missing USB initialization** - libmtp might send something we don't

## What Would Fix It

To fix this, we need to compare:

1. **libmtp source code** - How does it handle the initial failure and reset?
2. **libusb debug traces** - Run both with LIBUSB_DEBUG=4 and diff the sequences
3. **Device state** - What does the device need after reset that we're not providing?

## Workaround Options

1. **Use libmtp for Pixel 7** - Document that SwiftMTP doesn't work with Pixel 7 yet
2. **PTP mode** - Try switching device to PTP mode (0x4ee5) if possible
3. **Different USB port** - Try different Mac USB controller

## Debug Commands

```bash
# libmtp debug
LIBUSB_DEBUG=4 mtp-detect 2>&1 | head -100

# SwiftMTP debug  
LIBUSB_DEBUG=4 SWIFTMTP_DEBUG=1 swift run -c release swiftmtp probe --quirks Specs/quirks.json --vid 0x18d1 --pid 0x4ee1
```

## Files Modified

- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` - Added pre-first-command delay, sent=0 diagnostics, reordered probe ladder

## Related Devices

- Samsung (04e8:6860): **WORKS** ✅
- Xiaomi (2717:ff40): libmtp also fails to write (device firmware limitation)
- OnePlus (2a70:f003): Connection issues (separate problem)
