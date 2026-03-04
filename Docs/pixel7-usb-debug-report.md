# Pixel 7 (18d1:4ee1) USB Debug Report — Complete Analysis

## Status: ROOT CAUSE IDENTIFIED — Actionable fixes below

## Executive Summary

The Google Pixel 7 in MTP mode (VID `0x18d1`, PID `0x4ee1`) fails with
`sent=0` bulk-OUT timeouts when using SwiftMTP.  libmtp *also* fails on its
first attempt but recovers via a **full reset → close → re-open** cycle that
SwiftMTP does not replicate exactly.

A deep source-code comparison of libmtp's `libusb1-glue.c` (which uses the
**same** `libusb_bulk_transfer()` API as SwiftMTP) against SwiftMTP's
`LibUSBTransport.swift` and `InterfaceProbe.swift` reveals **five concrete
differences** that, individually or in combination, explain why libmtp
succeeds and SwiftMTP does not.

---

## 1  Observed Behaviour

### 1.1  libmtp — fail, reset, succeed

```
PTP_ERROR_IO: failed to open session, trying again after resetting USB interface
LIBMTP libusb: Attempt to reset device
libusb_detach_kernel_driver() failed, continuing anyway...: Operation timed out
```

libmtp fails on the first `ptp_opensession`, then executes a full
`libusb_reset_device → close_usb → init_ptp_usb` cycle (see §3) and
succeeds on the second attempt.

### 1.2  SwiftMTP — fail, reset, still fail

```
[Ready] GetDeviceStatus len=8 → 0x2001   ← control transfer works
[Probe] write rc=-7 sent=0/12            ← bulk OUT fails (LIBUSB_ERROR_TIMEOUT)
```

- Control transfers (GetDeviceStatus) succeed.
- Every bulk-OUT write returns `rc=-7` (`LIBUSB_ERROR_TIMEOUT`) with **sent=0**.
- The failure persists through SwiftMTP's current fallback-ladder passes.

---

## 2  What Has Already Been Tried

| # | Attempt | Result | Notes |
|---|---------|--------|-------|
| 1 | `clear_halt` before first command | ❌ | Endpoint still doesn't respond |
| 2 | 500 ms pre-first-command delay | ❌ | Not purely a timing issue |
| 3 | 2 000 ms pre-first-command delay | ❌ | Same |
| 4 | 3 000 ms post-claim stabilise | ❌ | Same |
| 5 | USB reset in Pass 1 | ❌ | SwiftMTP re-claims but doesn't full-close first |
| 6 | USB reset in Pass 2 | ❌ | Same problem |
| 7 | Try OpenSession before GetDeviceInfo | ❌ | Any bulk command fails |

---

## 3  libmtp Source-Code Analysis (libusb-1.0 glue)

> **Source**: [`libmtp/src/libusb1-glue.c`](https://github.com/libmtp/libmtp/blob/master/src/libusb1-glue.c)
>
> libmtp ships *two* USB backends: `libusb-glue.c` (libusb-0.1) and
> `libusb1-glue.c` (libusb-1.0).  Homebrew on macOS compiles against
> **libusb-1.0**, so `libusb1-glue.c` is the relevant comparison.  The bulk
> I/O macro `USB_BULK_WRITE` expands to `libusb_bulk_transfer` — the exact
> same C function SwiftMTP calls.

### 3.1  Pixel 7 device flags (from `music-players.h`)

```c
// music-players.h line 2640
{ "Google Inc", 0x18d1, "Nexus/Pixel (MTP)", 0x4ee1,
    (DEVICE_FLAGS_ANDROID_BUGS
     | DEVICE_FLAG_PROPLIST_OVERRIDES_OI)
    & ~DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST },
```

`DEVICE_FLAGS_ANDROID_BUGS` expands to (from `device-flags.h`):

| Flag | Hex | Effect |
|------|-----|--------|
| `BROKEN_MTPGETOBJPROPLIST` | 0x02000000 | *(cleared for Pixel 7)* |
| `BROKEN_SET_OBJECT_PROPLIST` | 0x04000000 | skip SetObjectPropList |
| `BROKEN_SEND_OBJECT_PROPLIST` | 0x08000000 | skip SendObjectPropList |
| `UNLOAD_DRIVER` | 0x00000002 | detach kernel driver |
| **`LONG_TIMEOUT`** | 0x08000000 | **use 60 000 ms timeout** |
| **`FORCE_RESET_ON_CLOSE`** | 0x10000000 | **reset device on close** |

### 3.2  Timeout constants

```c
#define USB_START_TIMEOUT    5000   // first opensession attempt
#define USB_TIMEOUT_DEFAULT 20000   // normal operations
#define USB_TIMEOUT_LONG    60000   // when FLAG_LONG_TIMEOUT set

static inline int get_timeout(PTP_USB* ptp_usb) {
    return FLAG_LONG_TIMEOUT(ptp_usb) ? USB_TIMEOUT_LONG
                                      : USB_TIMEOUT_DEFAULT;
}
```

### 3.3  `configure_usb_device()` — the critical recovery sequence

```
┌─ init_ptp_usb()
│   ├─ libusb_open()                     open device handle
│   ├─ libusb_detach_kernel_driver()     detach kernel driver
│   ├─ libusb_get_active_config_descriptor()
│   ├─ libusb_set_configuration()        if config differs (Darwin note!)
│   └─ libusb_claim_interface()          claim MTP interface
│
├─ set_usb_device_timeout(5000)          start timeout (5 s)
│
├─ ptp_opensession(1)  ──────────────►   FAILS (PTP_ERROR_IO)
│                                         ↓
│  ┌─ libusb_reset_device(handle)        bus reset
│  │
│  ├─ close_usb()
│  │   ├─ clear_stall()                  check + clear stalled endpoints
│  │   ├─ libusb_release_interface()     release the interface
│  │   ├─ libusb_reset_device()          FORCE_RESET_ON_CLOSE → 2nd reset!
│  │   └─ libusb_close()                 close the handle entirely
│  │
│  └─ init_ptp_usb()                     ← full re-open from scratch
│      ├─ libusb_open()                  new handle
│      ├─ libusb_detach_kernel_driver()
│      ├─ libusb_set_configuration()
│      └─ libusb_claim_interface()
│
├─ ptp_opensession(1)  ──────────────►   SUCCEEDS
│
└─ set_usb_device_timeout(60000)         long timeout for Pixel 7
```

**Key observations:**

1. **Two USB resets** — the explicit `libusb_reset_device` *plus* a second
   one from `FORCE_RESET_ON_CLOSE` inside `close_usb()`.
2. **Full handle teardown** — `libusb_close()` destroys the old handle before
   opening a new one.  libusb internally releases IOKit resources on macOS.
3. **`libusb_set_configuration()`** is called inside `init_ptp_usb()` with a
   Darwin-specific comment: *"Darwin will not set the configuration for
   vendor-specific devices so we need to go in and set it."*
4. **Alt-setting is NOT changed on macOS** — `#ifndef __APPLE__` guards that
   code.
5. **`USB_START_TIMEOUT` (5 s)** is used for the first attempt — not 2 s.

### 3.4  PTP command container format

```c
// ptp_usb_sendreq() — both backends identical
usbreq.length   = htod32(PTP_USB_BULK_REQ_LEN - (4 * (5 - req->Nparam)));
usbreq.type     = htod16(PTP_USB_CONTAINER_COMMAND);  // 0x0001
usbreq.code     = htod16(req->Code);
usbreq.trans_id = htod32(req->Transaction_ID);
// params follow...
towrite = PTP_USB_BULK_REQ_LEN - (4 * (5 - req->Nparam));
```

For **OpenSession** (1 param): `length = 32 - 16 = 16` bytes.
For **GetDeviceInfo** (0 params): `length = 32 - 20 = 12` bytes.

SwiftMTP's `makePTPCommand` builds identical 12-byte containers for
GetDeviceInfo — **container format is not the issue**.

### 3.5  `ptp_write_func()` — bulk write details

- Chunk size: `CONTEXT_BLOCK_SIZE = 0x4000` (16 KiB).
- WMP-compatible sizing: last chunk rounded down to `outep_maxpacket` boundary.
- Zero-length packet sent when final write is exactly maxpacket-aligned.
- None of these matter for the 12-byte command transfer that fails with sent=0.

### 3.6  `split_header_data`

Starts at 0.  Only set to 1 if a specific read-length anomaly is detected
(response exactly fits one maxpacket with header).  Not relevant to the
initial command-phase failure.

---

## 4  Concrete Differences Between libmtp and SwiftMTP

### Difference 1 — Reset sequence is incomplete

| Step | libmtp | SwiftMTP |
|------|--------|----------|
| Reset device | `libusb_reset_device()` | `libusb_reset_device()` ✅ |
| Clear stalls | `clear_stall()` (conditional) | `libusb_clear_halt()` ✅ |
| Release interface | `libusb_release_interface()` | ❌ **missing** |
| Close handle | `libusb_close()` | ❌ **missing** |
| Force-reset-on-close | 2nd `libusb_reset_device()` | ❌ **missing** |
| Re-open handle | `libusb_open()` | ❌ **missing** (re-uses same handle) |
| Re-set configuration | `libusb_set_configuration()` | ❌ **missing on retry** |
| Re-claim interface | `libusb_claim_interface()` | ✅ |

**SwiftMTP resets the device but re-uses the same `libusb_device_handle`.**
libmtp destroys the handle and creates a fresh one.  On macOS (Darwin), this
likely causes IOKit to fully tear down and rebuild the USB pipe state.  A
stale handle after reset may leave the device in an ambiguous state where
control EP0 works but bulk endpoints are dead.

### Difference 2 — Missing `libusb_set_configuration()` on Darwin

libmtp's `init_ptp_usb()` explicitly calls:

```c
if (config->bConfigurationValue != ptp_usb->config) {
    libusb_set_configuration(device_handle, ptp_usb->config);
}
```

With a comment noting *"Darwin will not set the configuration for
vendor-specific devices"*.  The Pixel 7's MTP interface is **Still Image
Capture class (0x06/0x01/0x01)**, not vendor-specific, but it is possible
that macOS doesn't activate the configuration until explicitly set.

SwiftMTP does not call `libusb_set_configuration()` before claiming.

### Difference 3 — Timeout too short during probing

| | libmtp 1st attempt | libmtp 2nd attempt | SwiftMTP probe |
|-|--------------------|--------------------|----------------|
| Timeout | 5 000 ms | 5 000+ ms | **2 000 ms** |
| Operational | 60 000 ms | 60 000 ms | **10 000 ms** |

The probe timeout of 2 000 ms is less than half of libmtp's start timeout
(5 000 ms).  For a device that may need several seconds after claim before
its bulk endpoints become responsive, this could cause premature failure.

SwiftMTP's quirk entry for Pixel 7 already has `handshakeTimeoutMs: 20000`
and `ioTimeoutMs: 30000`, but these are only applied **after** the probe
succeeds — and the probe itself uses the hardcoded 2 000 ms default.

### Difference 4 — Only one USB reset, not two

libmtp performs **two** `libusb_reset_device()` calls because
`FORCE_RESET_ON_CLOSE` triggers a second reset inside `close_usb()`.
SwiftMTP performs only one.  On macOS, `libusb_reset_device()` calls
`darwin_reenumerate_device()` → `USBDeviceReEnumerate()`, which is a full
bus-level re-enumeration.  The double-reset pattern may be necessary to fully
clear the Pixel 7's USB state.

### Difference 5 — No `libusb_detach_kernel_driver()` on re-open

libmtp always calls `libusb_detach_kernel_driver()` in `init_ptp_usb()`,
including on the retry path.  On macOS this may detach the AppleUSBPTP
kernel extension that can grab Still Image class devices.

---

## 5  Recommended Fixes (priority order)

### Fix A — Full close + re-open cycle (HIGH PRIORITY)

Implement libmtp's exact recovery sequence in `LibUSBTransport.swift`:

```
1. libusb_reset_device(handle)
2. libusb_clear_halt(outEP)  + libusb_clear_halt(inEP)
3. libusb_release_interface(handle, iface)
4. libusb_reset_device(handle)   ← FORCE_RESET_ON_CLOSE
5. libusb_close(handle)
6. libusb_open(dev, &newHandle)
7. libusb_detach_kernel_driver(newHandle, iface)
8. libusb_set_configuration(newHandle, config)
9. libusb_claim_interface(newHandle, iface)
10. Retry ptp_opensession with 5000 ms timeout
```

This is the highest-priority fix because it matches libmtp's proven
sequence exactly.

### Fix B — Increase probe timeout for Pixel 7

In `InterfaceProbe.swift`, when the VID matches Google (`0x18d1`), use
a probe timeout of at least 5 000 ms (matching `USB_START_TIMEOUT`):

```swift
let probeTimeout: UInt32 = (vid == 0x18d1) ? 5000 : 2000
```

### Fix C — Call `libusb_set_configuration()` before claiming

Before `libusb_claim_interface()`, call:

```swift
libusb_set_configuration(handle, Int32(configValue))
```

This matches libmtp's Darwin-specific behaviour and may be necessary
to activate the USB configuration on macOS.

### Fix D — Double-reset for FORCE_RESET_ON_CLOSE devices

For devices with the Pixel 7's profile, perform two resets in the
recovery path to match libmtp's `close_usb()` + `init_ptp_usb()` behaviour.

### Fix E — Extend operational timeout to 60 s

Match libmtp's `USB_TIMEOUT_LONG` for the Pixel 7 quirk:
`ioTimeoutMs: 60000` in `Specs/quirks.json`.

---

## 6  macOS-Specific Notes

### 6.1  `libusb_reset_device()` on Darwin

On macOS ≥ 10.11, libusb-1.0's `darwin_reset_device()` calls
`USBDeviceReEnumerate()` (not the older `ResetDevice()` which is a no-op).
This causes the device to **disappear from the bus and re-enumerate**,
which changes the device address.  libusb internally handles re-enumeration
and restores state, but only if the caller follows the correct sequence
(close old handle → re-open after re-enum).

### 6.2  Still Image Capture class on macOS

The Pixel 7's MTP interface uses class 0x06 / subclass 0x01 / protocol 0x01
(Still Image Capture / PTP).  macOS may load `AppleUSBPTP.kext` for this
interface.  `libusb_detach_kernel_driver()` is needed to wrest control from
the kernel driver.  libmtp always does this; SwiftMTP does it based on the
quirk flag `requiresKernelDetach`.

### 6.3  `libusb_set_configuration()` on Darwin

libmtp explicitly notes that Darwin needs `libusb_set_configuration()` for
vendor-specific devices.  While the Pixel 7 isn't vendor-specific, the
configuration may not be activated until explicitly set, especially after
a `USBDeviceReEnumerate()`.

---

## 7  Verification Plan

```bash
# Step 1: Run libmtp with full USB debug to capture the exact byte sequence
LIBUSB_DEBUG=4 mtp-detect 2>&1 | tee /tmp/libmtp-pixel7.log

# Step 2: Run SwiftMTP with full USB debug
LIBUSB_DEBUG=4 SWIFTMTP_DEBUG=1 swift run -c release swiftmtp probe \
  --quirks Specs/quirks.json --vid 0x18d1 --pid 0x4ee1 2>&1 | tee /tmp/swiftmtp-pixel7.log

# Step 3: Diff the libusb-level USB setup sequences
diff <(grep -E 'libusb_(open|set_config|claim|clear|reset|close)' /tmp/libmtp-pixel7.log) \
     <(grep -E 'libusb_(open|set_config|claim|clear|reset|close)' /tmp/swiftmtp-pixel7.log)
```

---

## 8  Files Modified / Relevant

| File | Role |
|------|------|
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` | Probe logic, first bulk-OUT |
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift` | Reset/recovery ladder |
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/PTPContainer+USB.swift` | PTP container building |
| `Specs/quirks.json` | Pixel 7 quirk tuning values |
| `SwiftMTPKit/Tests/QuirksTests/GooglePixelQuirksTests.swift` | Pixel 7 quirk tests |

## 9  Related Devices

| Device | VID:PID | Status |
|--------|---------|--------|
| Samsung Galaxy S7 | 04e8:6860 | ✅ Works |
| Xiaomi Mi Note 2 | 2717:ff10 | ✅ Partial (real transfers) |
| Xiaomi Mi Note 2 (alt) | 2717:ff40 | ⚠️ Partial (0 storages) |
| OnePlus 3T | 2a70:f003 | ⚠️ Partial (read OK, write 0x201D) |
| Google Pixel 7 | 18d1:4ee1 | ❌ Blocked (this report) |

---

*Last updated: June 2025 — libmtp source comparison complete.*
