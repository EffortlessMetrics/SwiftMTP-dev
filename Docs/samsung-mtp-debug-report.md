# Samsung Galaxy S7 (04e8:6860) MTP Debug Report — Complete Analysis

## Status: FIXES SHIPPED — Awaiting real-device retest

## Executive Summary

The Samsung Galaxy S7 (SM-G930W8) in MTP mode (VID `0x04e8`, PID `0x6860`)
fails after USB claim: the first MTP command (OpenSession or GetDeviceInfo)
gets no response or times out. libmtp succeeds on the same device.

Wave 38 research (#428) identified **8 critical initialization differences**
between libmtp and SwiftMTP. Wave 39 (#445) shipped transport fixes for the
two highest-priority items (skipAltSetting, skipPreClaimReset). This report
consolidates all findings, adds deeper libmtp source analysis, documents
remaining gaps, and provides a prioritized implementation plan for full
Samsung Galaxy MTP support.

---

## 1  Observed Behaviour

### 1.1  libmtp — succeeds (sometimes after one retry)

```
1. libusb_open()
2. libusb_detach_kernel_driver()
3. libusb_set_configuration() — only if current != desired
4. libusb_claim_interface()
   (NO set_interface_alt_setting on macOS — #ifndef __APPLE__)
5. ptp_opensession(session_id=1) with 5s timeout
   → On PTP_ERROR_IO: reset_device → close → reinit → retry
   → On PTP_RC_InvalidTransactionID: txid += 10, retry
6. ptp_getdeviceinfo() — AFTER session open
7. Set timeout to 60,000ms (DEVICE_FLAG_LONG_TIMEOUT)
```

libmtp's first `ptp_opensession` uses a short 5-second timeout
(`USB_START_TIMEOUT`). If it fails with `PTP_ERROR_IO`, libmtp performs a
**full reset → close → reinit → retry** cycle. The second attempt typically
succeeds.

### 1.2  SwiftMTP — fails

```
[Open] Pre-claim reset (300ms)           ← NOT done by libmtp
[Claim] libusb_claim_interface rc=0
[Claim] set_interface_alt_setting rc=0   ← DISABLED on macOS by libmtp
[Claim] wait 500ms for stabilization     ← NOT done by libmtp
[Claim] clear_halt on bulkIn/bulkOut     ← NOT done by libmtp
[Probe] OpenSession timeout / no response
```

After wave 39 fixes, with `skipAltSetting` and `skipPreClaimReset` enabled,
the sequence should now be closer to libmtp's flow. **Retest is needed** to
confirm whether the remaining differences (clear_halt, delays, recovery
strategy) still cause failures.

---

## 2  What Has Been Implemented

| # | Fix | Wave | PR | Status |
|---|-----|------|----|--------|
| 1 | Skip `set_interface_alt_setting` on macOS | 39 | #445 | ✅ Shipped |
| 2 | Skip pre-claim `libusb_reset_device` | 39 | #445 | ✅ Shipped |
| 3 | Probe ladder: OpenSession before GetDeviceInfo | 38 | #428 | ✅ Shipped (quirks) |
| 4 | Timeout increased to 60,000ms | 38 | #428 | ✅ Shipped (quirks) |
| 5 | Post-claim stabilize reduced to 100ms | 38 | #428 | ✅ Shipped (quirks) |
| 6 | `skipClearHaltBeforeProbe` flag in quirks JSON | 38 | #428 | ⚠️ Quirk set, **not wired** |
| 7 | Reset-reopen recovery on OpenSession I/O error | — | — | ❌ Not implemented |
| 8 | `forceResetOnClose` for Samsung | — | — | ❌ Not implemented |
| 9 | Samsung 512-byte boundary bug workaround | — | — | ❌ Not implemented |

---

## 3  libmtp Source-Code Analysis (libusb-1.0 backend)

### 3.1  Samsung device flags (`music-players.h`)

```c
// PID 0x6860 — "Galaxy models (MTP)"
{ "Samsung", 0x04e8, "Galaxy models (MTP)", 0x6860,
    /* DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL | BROKEN_MTPGETOBJPROPLIST | */
    DEVICE_FLAG_UNLOAD_DRIVER |         // detach kernel driver
    DEVICE_FLAG_LONG_TIMEOUT |          // 60,000ms timeout
    DEVICE_FLAG_PROPLIST_OVERRIDES_OI | // ObjectInfo has 64-bit fields
    DEVICE_FLAG_SAMSUNG_OFFSET_BUG |    // 512-byte boundary hang
    DEVICE_FLAG_OGG_IS_UNKNOWN |
    DEVICE_FLAG_FLAC_IS_UNKNOWN },
```

Note: `BROKEN_MTPGETOBJPROPLIST_ALL` and `BROKEN_MTPGETOBJPROPLIST` are
**commented out** for PID `0x6860` but **enabled** for PID `0x685c` (MTP+ADB).
The comment explains that the 512-byte bug is one reason these were added and
then removed: "this is one of the reasons we need to disable
DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST as it can hit this size".

Additionally, when the device reports `"android.com"` in its vendor extension,
libmtp auto-assigns `DEVICE_FLAGS_ANDROID_BUGS`:

```c
#define DEVICE_FLAGS_ANDROID_BUGS \
  (DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST |
   DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST |
   DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST |
   DEVICE_FLAG_UNLOAD_DRIVER |
   DEVICE_FLAG_LONG_TIMEOUT |
   DEVICE_FLAG_FORCE_RESET_ON_CLOSE)
```

This means Samsung Galaxy devices get `FORCE_RESET_ON_CLOSE` dynamically
even though it's not in the static device entry. **SwiftMTP should match this.**

### 3.2  `init_ptp_usb()` — the critical init function

From `libusb1-glue.c`, the Samsung init path is:

```c
static int init_ptp_usb(PTPParams* params, PTP_USB* ptp_usb, libusb_device* dev)
{
    // 1. Set timeout based on device flags
    ptp_usb->timeout = get_timeout(ptp_usb);  // 60,000ms for Samsung

    // 2. Open device handle
    libusb_open(dev, &device_handle);

    // 3. Detach kernel driver (DEVICE_FLAG_UNLOAD_DRIVER)
    if (FLAG_UNLOAD_DRIVER(ptp_usb))
        libusb_detach_kernel_driver(device_handle, ptp_usb->interface);

    // 4. Set configuration ONLY if different from desired
    libusb_get_active_config_descriptor(dev, &config);
    if (config->bConfigurationValue != ptp_usb->config)
        libusb_set_configuration(device_handle, ptp_usb->config);

    // 5. Claim interface
    libusb_claim_interface(device_handle, ptp_usb->interface);

    // 6. Alt-setting — DISABLED on macOS
    #ifndef __APPLE__
    #if 0 /* Disable this always, no idea on how to handle it */
        libusb_set_interface_alt_setting(...);
    #endif
    #endif

    // 7. BlackBerry mode switch — NOT applicable to Samsung
    // 8. Return — NO reset, NO clear_halt, NO delays
}
```

### 3.3  `configure_usb_device()` — session open with recovery

```c
LIBMTP_error_number_t configure_usb_device(...)
{
    // 1. Find interface and endpoints
    find_interface_and_endpoints(ldevice, ...);

    // 2. Initialize USB (calls init_ptp_usb above)
    init_ptp_usb(params, ptp_usb, ldevice);

    // 3. First OpenSession attempt with SHORT timeout (5,000ms)
    set_usb_device_timeout(ptp_usb, USB_START_TIMEOUT);  // 5000ms
    ret = ptp_opensession(params, 1);

    // 4. Recovery on I/O error — THE KEY DIFFERENCE
    if (ret == PTP_ERROR_IO) {
        LIBMTP_ERROR("PTP_ERROR_IO: failed to open session, "
                     "trying again after resetting USB interface\n");
        libusb_reset_device(ptp_usb->handle);  // reset
        close_usb(ptp_usb);                     // close + clear_stall + release
        init_ptp_usb(params, ptp_usb, ldevice); // full reinit
        ret = ptp_opensession(params, 1);        // retry
    }

    // 5. Recovery on invalid transaction ID
    if (ret == PTP_RC_InvalidTransactionID) {
        params->transaction_id += 10;
        ret = ptp_opensession(params, 1);
    }

    // 6. Restore full timeout
    set_usb_device_timeout(ptp_usb, get_timeout(ptp_usb));  // 60,000ms
}
```

**Key insight**: libmtp **expects** the first OpenSession to fail on Samsung.
The 5-second short timeout is intentional — it lets libmtp quickly detect the
failure and execute the reset-reinit-retry cycle. This recovery path is what
makes Samsung devices work.

### 3.4  `close_usb()` — cleanup on close

```c
static void close_usb(PTP_USB* ptp_usb)
{
    if (!FLAG_NO_RELEASE_INTERFACE(ptp_usb)) {
        clear_stall(ptp_usb);                    // clear any stalled endpoints
        libusb_release_interface(ptp_usb->handle, ptp_usb->interface);
    }
    if (FLAG_FORCE_RESET_ON_CLOSE(ptp_usb)) {
        libusb_reset_device(ptp_usb->handle);    // Samsung gets this via ANDROID_BUGS
    }
    libusb_close(ptp_usb->handle);
}
```

### 3.5  `clear_stall()` — conditional endpoint clearing

```c
static void clear_stall(PTP_USB* ptp_usb)
{
    // Only clears halt if endpoint status reports HALTED
    status = 0;
    usb_get_endpoint_status(ptp_usb, ptp_usb->inep, &status);
    if (status)
        libusb_clear_halt(ptp_usb->handle, ptp_usb->inep);

    usb_get_endpoint_status(ptp_usb, ptp_usb->outep, &status);
    if (status)
        libusb_clear_halt(ptp_usb->handle, ptp_usb->outep);
}
```

**Contrast with SwiftMTP**: We unconditionally call `libusb_clear_halt()`
before the first probe command. libmtp only calls it during close/recovery
and only when the endpoint reports HALTED status.

---

## 4  Samsung-Specific MTP Quirks

### 4.1  3-Second Session Window

From `music-players.h`:

> "Devices seem to have a **connection timeout**, the session must be opened
> in about **3 seconds** since the device is plugged in, after that time it
> will not respond. Thus GUI programs work fine."

**Impact on SwiftMTP**: Every unnecessary step between USB claim and
OpenSession consumes this budget. Before wave 39 fixes, our init path had:

```
Pre-claim reset:     300ms
Post-claim stabilize: 500ms
Alt-setting call:       ~5ms (but resets MTP state!)
Clear_halt calls:      ~10ms
Pre-command delays:  variable
────────────────────────────
Total overhead: ~800ms+ before first MTP command
```

After wave 39 fixes (skipPreClaimReset, skipAltSetting):

```
Post-claim stabilize: 100ms
Clear_halt calls:      ~10ms (still done!)
────────────────────────────
Total overhead: ~110ms before first MTP command ← much better
```

**Remaining risk**: The `clear_halt` calls (10ms) plus any code path delays
may still be enough to cause issues on devices with a very tight window.

### 4.2  512-Byte Packet Boundary Bug (`DEVICE_FLAG_SAMSUNG_OFFSET_BUG`)

From `device-flags.h`:

> "When GetPartialObject is invoked to read the last bytes of a file and the
> amount of data to read is such that the last USB packet sent in the reply
> matches exactly the USB 2.0 packet size, then the Samsung Galaxy device
> hangs, resulting in a timeout error."

**Workaround**: When reading the last chunk of a file, if the remaining bytes
would produce a response where `(PTP_header + data_remaining) % 512 == 0`,
adjust the read size by ±1 byte. Specifically:

```
if (offset + length == fileSize) {
    let responseLen = 12 + length  // PTP header (12) + data
    if responseLen % 512 == 0 {
        length -= 1  // read one fewer byte
        // then read the final byte separately
    }
}
```

**Status**: Not yet implemented in SwiftMTP's transfer layer.

### 4.3  ObjectInfo 64-bit Fields (`DEVICE_FLAG_PROPLIST_OVERRIDES_OI`)

Samsung Galaxy devices sometimes pack 64-bit values into ObjectInfo fields
that the PTP spec defines as 32-bit. The `propListOverridesObjectInfo` flag
is already set in our quirks entry. When this flag is set, always prefer
property list values over ObjectInfo for file sizes and dates.

### 4.4  Force Reset on Close (`DEVICE_FLAG_FORCE_RESET_ON_CLOSE`)

libmtp dynamically assigns this via `DEVICE_FLAGS_ANDROID_BUGS` when the
device reports `"android.com"` in its vendor extension. This ensures the
device is left in a clean state for the next connection. Without this,
subsequent connections may find stale session state.

**Status**: The `forceResetOnClose` flag exists in `QuirkFlags` but is not
set for Samsung devices. Should be enabled.

---

## 5  Differences Summary — Complete Status

| # | Difference | Priority | libmtp | SwiftMTP | Status |
|---|-----------|----------|--------|----------|--------|
| **D1** | `set_interface_alt_setting` disabled on macOS | **HIGH** | Disabled (`#ifndef __APPLE__` + `#if 0`) | Skipped via `skipAltSetting` quirk | ✅ Fixed (#445) |
| **D2** | No pre-claim USB reset | **HIGH** | Never done for Samsung | Skipped via `skipPreClaimReset` quirk | ✅ Fixed (#445) |
| **D3** | 60s timeout | **MEDIUM** | 60,000ms (`DEVICE_FLAG_LONG_TIMEOUT`) | 60,000ms via quirk | ✅ Fixed (#428) |
| **D4** | No `clear_halt` during init | **MEDIUM** | Not called during init | `skipClearHaltBeforeProbe` in quirks JSON but **not wired to transport** | ⚠️ Gap |
| **D5** | OpenSession before GetDeviceInfo | **MEDIUM** | Always OpenSession first | `openSessionThenGetDeviceInfo` is first in probe ladder | ✅ Fixed (#428) |
| **D6** | Minimal post-claim delay | **LOW** | 0ms delay | 100ms via quirk | ✅ Acceptable |
| **D7** | Short initial OpenSession timeout (5s) | **MEDIUM** | 5,000ms first attempt | 8,000ms first step | ⚠️ Close but different |
| **D8** | Reset-reopen on OpenSession I/O error | **HIGH** | `reset → close → reinit → retry` | Multi-pass escalation (different) | ❌ Gap |
| **D9** | `forceResetOnClose` for Android devices | **MEDIUM** | Auto-set via `DEVICE_FLAGS_ANDROID_BUGS` | Not set in Samsung quirks | ❌ Gap |
| **D10** | Conditional `clear_stall` (only if HALTED) | **LOW** | Check endpoint status first | Unconditional `clear_halt` | ⚠️ Difference |

---

## 6  Remaining Implementation Plan

### Phase 1: Wire `skipClearHaltBeforeProbe` (MEDIUM priority)

**Problem**: The `skipClearHaltBeforeProbe` flag is set in the Samsung quirks
JSON tuning section but is not plumbed through `SwiftMTPConfig` or
`QuirkFlags` to the transport layer. The clear_halt calls in
`InterfaceProbe.swift` still execute unconditionally.

**Implementation**:
1. Add `skipClearHaltBeforeProbe: Bool` to `QuirkFlags`
2. Add `skipClearHaltBeforeProbe: Bool` to `SwiftMTPConfig`
3. Plumb through `DeviceActor.openIfNeeded()` (same pattern as skipAltSetting)
4. Guard `libusb_clear_halt()` calls in `claimCandidate()` with this flag

**Files to change**:
- `SwiftMTPKit/Sources/SwiftMTPQuirks/Public/QuirkFlags.swift`
- `SwiftMTPKit/Sources/SwiftMTPCore/Public/MTPDevice.swift` (SwiftMTPConfig)
- `SwiftMTPKit/Sources/SwiftMTPCore/Internal/DeviceActor.swift`
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift`

**Risk**: Low — Samsung doesn't need clear_halt and libmtp never does it.

### Phase 2: Reset-Reopen Recovery Strategy (HIGH priority)

**Problem**: libmtp's recovery cycle (`reset → close → reinit → retry`) is
the primary mechanism that makes Samsung work. SwiftMTP's multi-pass
escalation differs significantly.

**Implementation**:
1. Add `resetReopenOnOpenSessionIOError: Bool` to `QuirkFlags` (already exists!)
2. In `LibUSBTransport.open()`, after first probe pass fails with I/O error:
   a. Call `libusb_reset_device(handle)`
   b. Close and release the handle completely
   c. Re-open the device from scratch (`libusb_open`)
   d. Re-run the full claim + probe sequence
3. Use a short initial timeout (5,000ms) matching libmtp's `USB_START_TIMEOUT`
4. Set full timeout (60,000ms) after successful OpenSession

**Files to change**:
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift`
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift`

**Risk**: Medium — full close+reopen cycle needs careful handle management.

### Phase 3: Enable `forceResetOnClose` (MEDIUM priority)

**Problem**: libmtp resets Samsung devices on close via
`DEVICE_FLAG_FORCE_RESET_ON_CLOSE` (auto-set for Android devices).
Without this, subsequent connections may encounter stale state.

**Implementation**:
1. Set `forceResetOnClose: true` in Samsung quirks flags section
2. Wire `forceResetOnClose` in `LibUSBTransport.close()` or session teardown

**Files to change**:
- `Specs/quirks.json` (Samsung entries)
- `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json`
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift`

**Risk**: Low — matches libmtp behavior exactly.

### Phase 4: Samsung Offset Bug Workaround (LOW priority, transfer-time)

**Problem**: Reads that produce responses exactly 512 bytes cause device hang.

**Implementation**:
1. In the partial-read transfer path, check if response would be 512-aligned
2. If so, reduce read size by 1 byte and do a second 1-byte read
3. Guard behind `samsungPartialObjectBoundaryBug` flag (already in QuirkFlags)

**Files to change**:
- `SwiftMTPKit/Sources/SwiftMTPCore/Internal/Transfer/` (read path)
- Tests in `CoreTests` or `TransportTests`

**Risk**: Low — only affects the last chunk of file reads.

### Phase 5: Transaction ID Recovery (LOW priority)

**Problem**: libmtp handles `PTP_RC_InvalidTransactionID` by incrementing
the transaction ID by 10 and retrying. SwiftMTP may not handle this case.

**Implementation**:
1. In OpenSession response handling, detect `InvalidTransactionID` (0x2004)
2. Increment transaction counter by 10
3. Retry OpenSession

**Risk**: Very low — simple response code handling.

---

## 7  AOSP MTP Server Behavior

The Android MTP server (`frameworks/av/media/mtp/MtpServer.cpp`) provides
context for understanding Samsung's device-side behavior:

- **Session handling**: The server accepts only one session at a time.
  `OpenSession` when a session is already open returns
  `MTP_RESPONSE_SESSION_ALREADY_OPEN`.

- **No init handshake**: The device side simply starts its event loop
  (`mRequest.read(mHandle)`) and waits for the host. There is no device-side
  timeout or keepalive — the "3-second window" is likely a Samsung-specific
  firmware addition, not an AOSP feature.

- **Supported operations**: Includes `GetPartialObject64`, `SendPartialObject`,
  `TruncateObject`, `BeginEditObject`, `EndEditObject` — confirming Android
  edit extension support.

- **Storage events**: The server sends `ObjectAdded`, `ObjectRemoved`,
  `StoreAdded`, `StoreRemoved`, `DevicePropChanged`, `ObjectInfoChanged`
  events. Our event handling covers all of these.

---

## 8  Verification Plan

### Step 1: Retest with Current Fixes

Connect Samsung Galaxy S7 and run:

```bash
cd SwiftMTPKit
SWIFTMTP_DEBUG=1 swift run swiftmtp probe
```

**Expected result** (if D1+D2 fixes are sufficient):
- USB claim succeeds
- OpenSession response received within 8s
- GetDeviceInfo returns Samsung device info
- GetStorageIDs returns at least one storage

**Expected result** (if additional fixes needed):
- USB claim succeeds
- OpenSession times out after 8s → pass 1 fails
- Pass 2 may or may not recover

### Step 2: If Retest Fails — Apply Phase 1 + Phase 2

1. Wire `skipClearHaltBeforeProbe` → eliminates D4
2. Implement reset-reopen recovery → matches libmtp's D8

### Step 3: Full Operational Validation

After successful probe:

```bash
# List files
SWIFTMTP_DEBUG=1 swift run swiftmtp ls

# Download a small file
SWIFTMTP_DEBUG=1 swift run swiftmtp pull --path "/Internal storage/DCIM/test.jpg" -o /tmp/

# Verify 512-byte boundary handling
SWIFTMTP_DEBUG=1 swift run swiftmtp pull --path "/Internal storage/DCIM/512test.dat" -o /tmp/
```

### Step 4: Device Lab Entry

After successful validation, run:

```bash
SWIFTMTP_DEBUG=1 swift run swiftmtp device-lab --quick
```

---

## 9  Timeline and Priority

| Phase | Priority | Estimated Effort | Dependencies |
|-------|----------|-----------------|--------------|
| Phase 1: skipClearHaltBeforeProbe | Medium | 1–2 hours | None |
| Phase 2: Reset-Reopen Recovery | High | 3–4 hours | None |
| Phase 3: forceResetOnClose | Medium | 30 min | None |
| Phase 4: 512-byte Boundary Bug | Low | 2 hours | Successful probe first |
| Phase 5: Transaction ID Recovery | Low | 30 min | None |

**Recommended order**: Retest first → Phase 2 (if retest fails) → Phase 1 →
Phase 3 → Phase 5 → Phase 4.

---

## 10  Samsung Galaxy Device Family

The same PID `0x6860` is used across many Samsung Galaxy models:

| Model | VID:PID | Notes |
|-------|---------|-------|
| Galaxy S (GT-I9000) | 04e8:6860 | Original Galaxy S |
| Galaxy S2 (GT-I9100) | 04e8:6860 | |
| Galaxy S3 (GT-I9300) | 04e8:6860 | |
| Galaxy S7 (SM-G930W8) | 04e8:6860 | Our test device |
| Galaxy Note (GT-N7000) | 04e8:6860 | |
| Galaxy Nexus (GT-I9250) | 04e8:6860 | |
| Galaxy Tab 7.7/10.1 | 04e8:6860 | |
| Galaxy A5 | 04e8:6860 | |
| Galaxy Core | 04e8:6860 | |
| Galaxy Xcover | 04e8:6860 | |
| Galaxy Y | 04e8:6860 | |

Related PIDs:
- `0x685c` — MTP+ADB mode (has additional `BROKEN_MTPGETOBJPROPLIST_ALL`)
- `0x6877` — Kies mode
- `0x6865` — PTP mode (not MTP)
- `0x685d` — ODIN mode (not MTP)

All fixes for `0x6860` should also apply to `0x685c` and `0x6877`.

---

## 11  References

### libmtp Source (libusb-1.0 backend)
- `src/libusb1-glue.c` — `init_ptp_usb()` (line ~1050), `configure_usb_device()` (line ~1200), `close_usb()` (line ~1100), `clear_stall()` (line ~1090)
- `src/music-players.h` — Samsung device entries and 3-second window comment
- `src/device-flags.h` — `DEVICE_FLAG_SAMSUNG_OFFSET_BUG`, `DEVICE_FLAG_LONG_TIMEOUT`, `DEVICE_FLAGS_ANDROID_BUGS`
- `src/libmtp.c` — `LIBMTP_Open_Raw_Device_Uncached()`, Android vendor extension detection

### AOSP MTP
- `frameworks/av/media/mtp/MtpServer.cpp` — Device-side MTP command loop
- `frameworks/av/media/mtp/MtpFfsHandle.cpp` — FunctionFS USB transport
- `frameworks/av/media/mtp/MtpDescriptors.cpp` — USB descriptor setup

### SwiftMTP Source
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift` — Transport open, pre-claim reset
- `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` — Claim, alt-setting, clear_halt, probe ladder
- `SwiftMTPKit/Sources/SwiftMTPQuirks/Public/QuirkFlags.swift` — QuirkFlags definitions
- `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json` — Samsung quirk entry
- `SwiftMTPKit/Sources/SwiftMTPCore/Internal/DeviceActor.swift` — Pre-resolved quirk flags
- `Docs/samsung-mtp-research.md` — Wave 38 initial research

### Prior Work
- PR #428 — Samsung MTP initialization research (8 differences)
- PR #445 — Transport fixes: skipAltSetting, skipPreClaimReset
- PR #429 — Pixel 7 research (similar methodology)
- PR #443 — Pixel 7 transport fixes (handle re-open pattern)
