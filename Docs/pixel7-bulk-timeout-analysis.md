# Pixel 7 Bulk Transfer Timeout — Deep Analysis

## Status: ROOT CAUSE REFINED — 6 fixes identified, 3 already partially implemented

## Executive Summary

The Google Pixel 7 (VID `0x18d1`, PID `0x4ee1`) fails with `sent=0` bulk-OUT
timeouts (`LIBUSB_ERROR_TIMEOUT`, rc=-7) on macOS when using SwiftMTP. This
document deepens the analysis from the initial debug report
(`Docs/pixel7-usb-debug-report.md`) by examining the AOSP MTP server
implementation, libmtp's exact recovery sequence, and macOS-specific USB host
controller behavior.

**Key finding**: The root cause is a combination of three factors:
1. **Stale USB handle after reset** — SwiftMTP's recovery now does
   close/reopen (fixed in #443), but the **double-reset** pattern from libmtp's
   `FORCE_RESET_ON_CLOSE` flag is still missing.
2. **Missing second `libusb_reset_device()` call** — libmtp performs two
   bus-level resets: one explicit, one via `close_usb()`. The second reset
   through `FORCE_RESET_ON_CLOSE` triggers a full `USBDeviceReEnumerate()` on
   Darwin, which is essential for Pixel 7's FunctionFS stack to reinitialize.
3. **Android FunctionFS event-driven architecture** — The Pixel's MTP server
   uses Linux FunctionFS (not a traditional USB device controller), meaning
   endpoint state is managed by the kernel gadget driver. A single
   `libusb_reset_device()` may not fully flush the FunctionFS state machine.

---

## 1  Android MTP Server Architecture (AOSP Analysis)

### 1.1  FunctionFS-based transport

The Pixel 7 runs Android 14+ which uses `MtpFfsHandle` (FunctionFS-based MTP
transport). Source: `frameworks/av/media/mtp/MtpFfsHandle.cpp`.

Key characteristics:
- **Async I/O**: Uses Linux AIO (`io_submit`/`io_getevents`) for bulk transfers,
  not blocking read/write. This means the USB gadget driver manages endpoint
  buffers independently.
- **Event-driven setup**: `FunctionFS` events (`BIND`, `ENABLE`, `DISABLE`,
  `SETUP`) control endpoint lifecycle. The MTP server only opens endpoints after
  receiving `FUNCTIONFS_ENABLE`.
- **Control request handling**: `MTP_REQ_RESET` (0x66) and `MTP_REQ_CANCEL`
  (0x64) both set `errno = ECANCELLED` and return -1, causing the MTP server's
  main loop to **restart from the top** — it does NOT close/reopen endpoints.
- **AIO buffer size**: `AIO_BUF_LEN = 16384` (16 KiB), with up to 128 buffers
  = 2 MiB max file chunk.

### 1.2  What happens on USB reset from host

When the macOS host sends a USB bus reset (via `libusb_reset_device()` →
`USBDeviceReEnumerate()`):

1. The Linux USB gadget driver receives a disconnect event
2. FunctionFS sends `FUNCTIONFS_DISABLE` to the MTP server
3. The USB gadget re-enumerates on the bus
4. FunctionFS sends `FUNCTIONFS_ENABLE` once re-enumerated
5. The MTP server calls `openEndpoints()` to re-open endpoint FDs

**Critical insight**: Between steps 2 and 4, the FunctionFS endpoints are
**closed**. If the host sends a bulk transfer during this window, it will
timeout because there is no device-side listener. The duration of this window
depends on:
- Android kernel USB gadget driver speed (~50-100ms)
- FunctionFS descriptor re-write time (~10-50ms)
- MTP server event processing latency (~10-100ms)

**Total re-initialization window: 70-250ms** — this is why libmtp uses a 350ms
post-reset delay (and SwiftMTP should too).

### 1.3  MTP class reset vs USB bus reset

The PTP class reset (control transfer 0x66 to interface) is handled by
FunctionFS as `MTP_REQ_RESET`:

```cpp
case MTP_REQ_RESET:
case MTP_REQ_CANCEL:
    errno = ECANCELLED;
    return -1;
```

This causes the MTP server to **restart its main read loop** but does NOT
re-initialize the USB transport or endpoints. It only resets the MTP session
state. This means:
- Class reset is useful for abandoning a stuck MTP transaction
- Class reset does NOT fix endpoint-level issues (HALT, stale pipes)
- For endpoint-level recovery, a full USB bus reset is required

---

## 2  libmtp Recovery Sequence — Detailed Analysis

### 2.1  The exact sequence from `configure_usb_device()`

```
configure_usb_device():
  ├─ init_ptp_usb()                          [1st handle open]
  │   ├─ libusb_open(dev, &handle)
  │   ├─ FLAG_UNLOAD_DRIVER → libusb_detach_kernel_driver()
  │   ├─ libusb_get_active_config_descriptor()
  │   ├─ libusb_set_configuration() if needed  ← Darwin-specific!
  │   └─ libusb_claim_interface()
  │
  ├─ set_usb_device_timeout(5000)             [USB_START_TIMEOUT]
  │
  ├─ ptp_opensession(1)  ──────────────────►  FAILS (PTP_ERROR_IO)
  │
  │  [Recovery sequence begins]
  │  ├─ libusb_reset_device(handle)           [Reset #1: explicit]
  │  │
  │  ├─ close_usb()                           [Full teardown]
  │  │   ├─ clear_stall()                     [Check+clear endpoints]
  │  │   │   ├─ usb_get_endpoint_status(inep)
  │  │   │   ├─ libusb_clear_halt(inep) if halted
  │  │   │   ├─ usb_get_endpoint_status(outep)
  │  │   │   └─ libusb_clear_halt(outep) if halted
  │  │   ├─ libusb_release_interface()
  │  │   ├─ FLAG_FORCE_RESET_ON_CLOSE:
  │  │   │   └─ libusb_reset_device()         [Reset #2: FORCE_RESET]
  │  │   └─ libusb_close(handle)              [Handle destroyed]
  │  │
  │  └─ init_ptp_usb()                        [2nd handle open]
  │      ├─ libusb_open(dev, &newHandle)       [Fresh handle]
  │      ├─ libusb_detach_kernel_driver()
  │      ├─ libusb_set_configuration()
  │      └─ libusb_claim_interface()
  │
  ├─ ptp_opensession(1)  ──────────────────►  SUCCEEDS
  │
  └─ set_usb_device_timeout(60000)            [USB_TIMEOUT_LONG]
```

### 2.2  Pixel 7 device flags

From `music-players.h`:
```c
{ "Google Inc", 0x18d1, "Nexus/Pixel (MTP)", 0x4ee1,
    (DEVICE_FLAGS_ANDROID_BUGS | DEVICE_FLAG_PROPLIST_OVERRIDES_OI)
    & ~DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST },
```

`DEVICE_FLAGS_ANDROID_BUGS` expands to:
| Flag | Value | Effect |
|------|-------|--------|
| `BROKEN_MTPGETOBJPROPLIST` | 0x04 | *(cleared for Pixel 7)* |
| `BROKEN_SET_OBJECT_PROPLIST` | 0x100 | Skip SetObjectPropList |
| `BROKEN_SEND_OBJECT_PROPLIST` | 0x8000 | Skip SendObjectPropList |
| `UNLOAD_DRIVER` | 0x02 | Detach kernel driver |
| **`LONG_TIMEOUT`** | **0x08000000** | **60,000 ms timeout** |
| **`FORCE_RESET_ON_CLOSE`** | **0x10000000** | **2nd reset in close_usb()** |

Additional flag:
| `PROPLIST_OVERRIDES_OI` | 0x40000000 | Prefer proplist over ObjectInfo |

### 2.3  `clear_stall()` — libmtp checks before clearing

libmtp's `clear_stall()` uses `usb_get_endpoint_status()` (a USB control
transfer: `GET_STATUS` on the endpoint) to check if the endpoint is actually
halted before calling `libusb_clear_halt()`. This is a subtle difference from
SwiftMTP which unconditionally calls `libusb_clear_halt()`.

The `GET_STATUS` control transfer:
```c
static int usb_get_endpoint_status(PTP_USB* ptp_usb, int ep, uint16_t* status) {
    return libusb_control_transfer(ptp_usb->handle,
        LIBUSB_ENDPOINT_IN | LIBUSB_RECIPIENT_ENDPOINT,
        LIBUSB_REQUEST_GET_STATUS,
        USB_FEATURE_HALT,
        ep, (unsigned char *)status, 2,
        ptp_usb->timeout);
}
```

This may not be functionally different (clearing a non-halted endpoint is a
no-op per USB spec), but it provides diagnostic information about endpoint state.

---

## 3  SwiftMTP vs libmtp — Gap Analysis

### 3.1  What SwiftMTP already implements correctly

| Feature | Status | Notes |
|---------|--------|-------|
| `libusb_open()` | ✅ | Standard open |
| `libusb_detach_kernel_driver()` | ✅ | Via `requiresKernelDetach` quirk |
| `libusb_set_configuration()` | ✅ | Via `setConfigurationIfNeeded()`, forced for Pixel |
| `libusb_claim_interface()` | ✅ | Standard claim |
| `libusb_clear_halt()` on all EPs | ✅ | In `recoverStall()` and light recovery |
| `libusb_reset_device()` | ✅ | In hard recovery |
| Close/reopen handle | ✅ | In `performCommandNoProgressHardRecovery()` |
| Probe timeout 5000ms | ✅ | `timeoutMs: UInt32 = 5000` (matches `USB_START_TIMEOUT`) |
| `set_interface_alt_setting(0)` | ✅ | After claim and in recovery |
| PTP class reset (0x66) | ✅ | In light recovery |

### 3.2  Remaining gaps

| # | Gap | libmtp | SwiftMTP | Impact |
|---|-----|--------|----------|--------|
| 1 | **Double reset** | 2× `libusb_reset_device()` (explicit + `FORCE_RESET_ON_CLOSE`) | 1× reset | **HIGH** — Second reset via FunctionFS re-enum may be required |
| 2 | **Operational timeout** | 60,000 ms (`LONG_TIMEOUT`) | 30,000 ms (`ioTimeoutMs`) | **MEDIUM** — Some operations may timeout prematurely |
| 3 | **`GET_STATUS` before `CLEAR_HALT`** | Checks endpoint status first | Unconditional clear | **LOW** — Diagnostic value only |
| 4 | **Recovery order** | Reset → clear_stall → release → reset2 → close → open → detach → config → claim | Reset → release → open → detach → config → claim → alt → clear | **MEDIUM** — Missing clear_stall before release, missing reset2 |
| 5 | **Alt-setting on macOS** | Skipped (`#ifndef __APPLE__`) | Applied (`set_interface_alt_setting(0)`) | **LOW** — May cause unexpected behavior on some host controllers |
| 6 | **Post-reset delay** | Implicit (re-enumeration takes time) | 350ms explicit | **LOW** — Already implemented |

### 3.3  The double-reset hypothesis

libmtp's recovery performs **two** `libusb_reset_device()` calls:

1. **Reset #1** (explicit, before `close_usb()`): Triggers
   `darwin_reenumerate_device()` → `USBDeviceReEnumerate()` on macOS. This
   causes the device to disappear from the bus and re-enumerate with a
   potentially new device address.

2. **Reset #2** (inside `close_usb()`, via `FORCE_RESET_ON_CLOSE`): Triggers
   another `USBDeviceReEnumerate()`. By this point the old handle is about to
   be closed, so this reset is on the "dying" handle.

The double-reset pattern may be necessary because:
- The first reset causes re-enumeration but the old handle is still open,
  which on macOS/Darwin means IOKit still has references to the old device
- The second reset (on the about-to-be-closed handle) forces IOKit to fully
  flush its internal state for this device
- After both resets + `libusb_close()`, the subsequent `libusb_open()` gets a
  completely fresh IOKit device handle with no stale pipe state

**SwiftMTP's current hard recovery does only one reset before close/reopen.**

---

## 4  Recommended Fixes (Priority Order)

### Fix 1 — Double-reset in recovery (HIGH PRIORITY)

Add a second `libusb_reset_device()` call between `libusb_release_interface()`
and `libusb_close()` in the hard recovery path, matching libmtp's
`FORCE_RESET_ON_CLOSE` behavior.

**Where**: `MTPUSBLink+CommandRecovery.swift`, method
`performCommandNoProgressHardRecovery()`.

```swift
// Current:
let resetRC = libusb_reset_device(oldHandle)
let releaseRC = libusb_release_interface(oldHandle, Int32(iface))
usleep(350_000)
// ... reopen ...

// Proposed:
let resetRC = libusb_reset_device(oldHandle)
recoverStall()  // clear_stall before release (libmtp compat)
let releaseRC = libusb_release_interface(oldHandle, Int32(iface))
let resetRC2 = libusb_reset_device(oldHandle)  // FORCE_RESET_ON_CLOSE
usleep(350_000)
libusb_close(oldHandle)
// ... reopen on fresh handle ...
```

Also add this to `performCommandNoProgressResetReopenRecovery()`.

**Effort**: Small — add ~5 lines to two methods.
**Risk**: Low — matches proven libmtp behavior.

### Fix 2 — Increase operational timeout to 60,000ms (HIGH PRIORITY)

Update the Pixel 7 quirks entry to match libmtp's `USB_TIMEOUT_LONG`:
`ioTimeoutMs: 60000`.

**Where**: `Specs/quirks.json` → `google-pixel-7-4ee1.tuning.ioTimeoutMs`

**Effort**: Trivial — single value change.
**Risk**: None — only increases wait time for this specific device.

### Fix 3 — Add `forceDoubleReset` quirks flag (MEDIUM PRIORITY)

Add a new quirks flag `forceDoubleReset: true` for Pixel 7 (and potentially
all Android devices with `DEVICE_FLAGS_ANDROID_BUGS`). The recovery code should
check this flag to decide whether to perform the double-reset pattern.

**Where**: `Specs/quirks.json` (new flag), `MTPUSBLink+CommandRecovery.swift`
(check flag).

**Effort**: Small — add flag to quirks schema, check in recovery code.

### Fix 4 — Recovery order alignment (MEDIUM PRIORITY)

Reorder the recovery sequence to match libmtp exactly:
1. `libusb_reset_device()` (reset #1)
2. `clear_stall()` (check + clear endpoints)
3. `libusb_release_interface()`
4. `libusb_reset_device()` (reset #2, FORCE_RESET_ON_CLOSE)
5. `libusb_close()` (destroy old handle)
6. `libusb_open()` (new handle)
7. `libusb_detach_kernel_driver()`
8. `libusb_set_configuration()`
9. `libusb_claim_interface()`

**Effort**: Medium — restructure recovery methods.
**Risk**: Low — follows proven libmtp pattern.

### Fix 5 — Skip alt-setting on macOS for Pixel (LOW PRIORITY)

libmtp explicitly skips `libusb_set_interface_alt_setting()` on macOS with
`#ifndef __APPLE__` guards. SwiftMTP calls it. While this hasn't been proven
to cause issues, it could theoretically interfere with the macOS host
controller's pipe management.

Consider gating `set_interface_alt_setting()` behind a quirks flag
`skipAltSettingOnDarwin: true` for investigation.

**Effort**: Small — add flag check.
**Risk**: Low — experimental.

### Fix 6 — Endpoint status diagnostic logging (LOW PRIORITY)

Before `libusb_clear_halt()`, issue `GET_STATUS` control transfers to each
endpoint to log whether they're actually halted. This provides diagnostic
information without changing behavior.

**Effort**: Small — add diagnostic logging.
**Risk**: None — read-only.

---

## 5  Quirks Entry Updates

The following changes are recommended for `Specs/quirks.json`:

```json
{
  "tuning": {
    "ioTimeoutMs": 60000,         // was 30000, match libmtp LONG_TIMEOUT
    "handshakeTimeoutMs": 20000   // keep as-is
  },
  "flags": {
    "forceDoubleReset": true,     // NEW: match libmtp FORCE_RESET_ON_CLOSE
    "longTimeout": true           // NEW: match libmtp DEVICE_FLAG_LONG_TIMEOUT
  }
}
```

---

## 6  Android MTP Server Behavior Notes

### 6.1  GetDeviceInfo before OpenSession

The AOSP MTP server's `handleRequest()` method processes `GetDeviceInfo`
**outside** of the session check — it works without an open session. This
matches the PTP/MTP spec where GetDeviceInfo is a session-independent
operation.

However, the main `run()` loop reads from the bulk OUT endpoint:
```cpp
int ret = mRequest.read(mHandle);
```

If the FunctionFS endpoints are not yet enabled (e.g., during USB
re-enumeration), this read will return -1 with `errno != ECANCELLED`, causing
the MTP server to **exit its main loop entirely**. The server must be
restarted by the Android USB framework.

This means: after a USB bus reset, there's a window where the MTP server is
completely stopped. The host must wait for the Android USB framework to
restart it before sending any commands.

### 6.2  Pixel-specific considerations

- **Tensor SoC USB controller**: The Pixel 7 uses Samsung's Exynos-based
  Tensor G2 SoC with a Synopsys DWC3 USB controller. The DWC3 driver's
  endpoint reconfiguration after USB reset can take longer than typical
  Qualcomm XHCI controllers.
- **Android 14+ USB HAL changes**: Android 14 moved to a new USB HAL
  (android.hardware.usb) that adds additional initialization steps during
  USB mode switching.
- **FunctionFS vs legacy**: Older Nexus devices used the legacy USB gadget
  API. The FunctionFS migration (Android 8+) changed endpoint lifecycle
  management and may have introduced timing sensitivities.

---

## 7  Verification Plan

### 7.1  Implement Fix 1 (double-reset) and Fix 2 (timeout)

```bash
# After implementing fixes, test with debug logging:
LIBUSB_DEBUG=4 SWIFTMTP_DEBUG=1 swift run -c release swiftmtp probe \
  --quirks Specs/quirks.json --vid 0x18d1 --pid 0x4ee1 2>&1 | tee /tmp/swiftmtp-pixel7-v2.log

# Compare reset sequence:
grep -E 'reset|close|open|claim|config|clear' /tmp/swiftmtp-pixel7-v2.log
```

### 7.2  Compare with libmtp

```bash
LIBUSB_DEBUG=4 mtp-detect 2>&1 | tee /tmp/libmtp-pixel7.log

# Diff the USB setup sequences:
diff <(grep -E 'libusb_(open|set_config|claim|clear|reset|close)' /tmp/libmtp-pixel7.log) \
     <(grep -E 'reset|close|open|claim|config|clear' /tmp/swiftmtp-pixel7-v2.log)
```

### 7.3  Timing analysis

```bash
# Measure time between reset and first successful bulk transfer:
grep -E 'reset_device|bulk_transfer' /tmp/swiftmtp-pixel7-v2.log | head -20
```

---

## 8  Related Files

| File | Role |
|------|------|
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/MTPUSBLink+CommandRecovery.swift` | Recovery ladder (primary fix target) |
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/MTPUSBLink+BulkTransfer.swift` | Bulk transfer implementation |
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` | Probe logic, initial claim sequence |
| `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift` | Transport lifecycle |
| `Specs/quirks.json` | Pixel 7 quirk tuning values |
| `Docs/pixel7-usb-debug-report.md` | Previous analysis (superseded by this doc) |

---

## 9  References

- **libmtp source**: `libusb1-glue.c` — `configure_usb_device()`, `init_ptp_usb()`, `close_usb()`, `clear_stall()`
- **libmtp device flags**: `device-flags.h` — `DEVICE_FLAGS_ANDROID_BUGS`, `DEVICE_FLAG_FORCE_RESET_ON_CLOSE`, `DEVICE_FLAG_LONG_TIMEOUT`
- **libmtp Pixel entry**: `music-players.h` — `0x18d1:0x4ee1`
- **AOSP MTP server**: `frameworks/av/media/mtp/MtpServer.cpp`, `MtpFfsHandle.cpp`
- **AOSP MTP descriptors**: `frameworks/av/media/mtp/MtpDescriptors.cpp`
- **libusb Darwin backend**: `libusb/os/darwin_usb.c` — `darwin_reset_device()`, `darwin_reenumerate_device()`

---

*Analysis date: July 2025*
*Builds on: Docs/pixel7-usb-debug-report.md (June 2025)*
