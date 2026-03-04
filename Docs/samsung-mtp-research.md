# Samsung Galaxy MTP Initialization Research

**Wave 38** — Deep comparison of libmtp vs SwiftMTP initialization for Samsung Galaxy
devices (VID `0x04e8`, PID `0x6860`).

**Status**: USB claim succeeds, but the first MTP command (OpenSession / GetDeviceInfo)
gets no response or timeout on SwiftMTP. libmtp succeeds on the same device.

---

## 1. libmtp Initialization Sequence (Samsung 0x6860)

Source: `libmtp/src/libusb-glue.c` — `configure_usb_device()` → `init_ptp_usb()`,
then `libmtp/src/libmtp.c` — `LIBMTP_Open_Raw_Device_Uncached()`.

### Device Flags (from `music-players.h`)

Samsung Galaxy MTP (PID `0x6860`) has:

```c
DEVICE_FLAG_UNLOAD_DRIVER          // detach kernel driver before claim
DEVICE_FLAG_LONG_TIMEOUT           // 60,000 ms timeout (vs 20,000 default)
DEVICE_FLAG_PROPLIST_OVERRIDES_OI  // ObjectInfo may have 64-bit fields
DEVICE_FLAG_SAMSUNG_OFFSET_BUG    // 512-byte boundary hang on GetPartialObject
DEVICE_FLAG_OGG_IS_UNKNOWN
DEVICE_FLAG_FLAC_IS_UNKNOWN
```

**NOT set**: `DEVICE_FLAG_NO_ZERO_READS`, `DEVICE_FLAG_NO_RELEASE_INTERFACE`,
`DEVICE_FLAG_FORCE_RESET_ON_CLOSE`, `DEVICE_FLAG_ALWAYS_PROBE_DESCRIPTOR`,
`DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL` (commented out).

### Step-by-Step Init (libmtp)

```
1. find_interface_and_endpoints()
   - Scan USB config descriptors for interface with 3 endpoints (2 bulk + 1 interrupt)
   - Record: config, interface number, altsetting, inep, outep, intep, maxpacket sizes

2. init_ptp_usb()
   a. Set timeout = 60,000 ms (DEVICE_FLAG_LONG_TIMEOUT)
   b. usb_open(dev)
   c. usb_detach_kernel_driver_np() — detach any kernel driver (DEVICE_FLAG_UNLOAD_DRIVER)
   d. usb_set_configuration() — ONLY if current config differs from desired
   e. usb_claim_interface()
   f. *** NO set_interface_alt_setting on macOS ***
      (guarded by #ifndef __APPLE__ and further disabled with #if 0)
   g. No BlackBerry magic (flag not set for Samsung)
   h. No USB reset
   i. No clear_halt
   j. No other control transfers

3. ptp_opensession(params, session_id=1)
   - transaction_id starts at 0
   - Sends PTP_OC_OpenSession (0x1002) with param1 = 1
   - On PTP_ERROR_IO failure:
     a. usb_reset()
     b. close_usb()
     c. Re-run init_ptp_usb()
     d. Retry ptp_opensession()
   - On PTP_RC_InvalidTransactionID:
     a. Increment transaction_id by 10
     b. Retry ptp_opensession()

4. ptp_getdeviceinfo()
   - PTP_OC_GetDeviceInfo (0x1001) — AFTER session is open
   - Parses vendor extension descriptor for "android.com", "samsung" etc.
   - Assigns DEVICE_FLAGS_ANDROID_BUGS if "android.com" extension found
     (includes BROKEN_MTPGETOBJPROPLIST, BROKEN_SET/SEND_OBJECT_PROPLIST,
      UNLOAD_DRIVER, LONG_TIMEOUT, FORCE_RESET_ON_CLOSE)
```

### Critical Notes from libmtp Source

From the Samsung entry comment in `music-players.h`:

> "Devices seem to have a **connection timeout**, the session must be opened in about
> **3 seconds** since the device is plugged in, after that time it will not respond.
> Thus GUI programs work fine."

> "Has a **weird USB bug if it reads exactly 512 bytes** (USB 2.0 packet size)
> the device will hang."

---

## 2. SwiftMTP Initialization Sequence (Samsung 0x6860)

Source: `LibUSBTransport.swift` → `open()`, `InterfaceProbe.swift` → `claimCandidate()`,
`probeCandidateWithLadder()`.

### Step-by-Step Init (SwiftMTP)

```
1. rankMTPInterfaces()
   - Scan USB descriptors, score interfaces by class/endpoints/name
   - Samsung scores via vendor-specific class (0xFF) heuristic

2. Pre-claim USB reset (vendor-specific devices)
   a. libusb_reset_device()           ← *** NOT done by libmtp ***
   b. usleep(300,000) — 300ms settle  ← *** NOT done by libmtp ***

3. claimCandidate() with retry loop
   a. libusb_set_auto_detach_kernel_driver(1)
   b. libusb_detach_kernel_driver()
   c. setConfigurationIfNeeded()
   d. libusb_claim_interface()
   e. libusb_set_interface_alt_setting()  ← *** DISABLED on macOS by libmtp ***
   f. usleep(250,000-500,000) — post-claim stabilize

4. probeCandidateWithLadder() — probe ladder
   Step 1: OpenSession (0x1002) + GetDeviceInfo (0x1001)
   Step 2: Sessionless GetDeviceInfo (0x1001)
   Step 3: GetStorageIDs (0x1004)

   But the Samsung quirk overrides probe order to:
   Step 1: sessionlessGetDeviceInfo (5s)     ← *** WRONG ORDER vs libmtp ***
   Step 2: openSessionThenGetDeviceInfo (5s)
   Step 3: getStorageIDs (5s)

5. probeCandidate() (for GetDeviceInfo)
   a. libusb_clear_halt(bulkIn)    ← *** NOT done by libmtp ***
   b. libusb_clear_halt(bulkOut)   ← *** NOT done by libmtp ***
   c. usleep() — pre-command delay
   d. Send PTP_OC_GetDeviceInfo (0x1001) with txid=1
   e. Read response with deadline loop

6. Effective timeout: max(8000*2, 5000) = 16,000 ms
   ← *** libmtp uses 60,000 ms ***
```

---

## 3. Differences Identified

| # | Aspect | libmtp | SwiftMTP | Impact |
|---|--------|--------|----------|--------|
| **D1** | **set_interface_alt_setting** | Explicitly **disabled** on macOS (`#ifndef __APPLE__` + `#if 0`) | Always called after claim | **HIGH** — On macOS, this may reset the interface's endpoint state, causing Samsung to stop responding. This is the #1 suspect. |
| **D2** | **Pre-claim USB reset** | **Never** done for Samsung | Done for all vendor-specific (class 0xFF) devices | **HIGH** — USB reset may cause Samsung to re-enumerate or reset its MTP state machine, losing the 3-second session window. |
| **D3** | **Timeout** | 60,000 ms (`DEVICE_FLAG_LONG_TIMEOUT`) | ~16,000 ms (quirk 8000 × 2) | **MEDIUM** — May not be the root cause but could mask recovery attempts. |
| **D4** | **clear_halt before first command** | **Not done** during init | Done on both IN and OUT endpoints before first probe command | **MEDIUM** — clear_halt sends a USB control transfer that may confuse Samsung's MTP state. |
| **D5** | **Command order** | OpenSession **before** GetDeviceInfo (always) | Samsung quirk overrides to try sessionless GetDeviceInfo first | **MEDIUM** — Samsung devices may not respond to GetDeviceInfo without a session. The 3-second timeout note supports session-first. |
| **D6** | **Post-claim delay** | None (0 ms) | 250–500 ms | **LOW** — Adding delay eats into the 3-second session window. Samsung may stop responding before we even send the first command. |
| **D7** | **Pre-first-command delay** | None | Variable (via `preFirstProbeCommandDelayMs`) | **LOW** — Same issue as D6. |
| **D8** | **USB reset on session failure** | Done as recovery (reset + reinit + retry) | Multi-pass with increasing escalation | **LOW** — Recovery approach differs but result should be similar. |

---

## 4. Root Cause Analysis

The most likely root cause is **D1 (set_interface_alt_setting on macOS)** combined with
**D2 (pre-claim USB reset)**.

### Why set_interface_alt_setting breaks Samsung on macOS

libmtp explicitly disabled `usb_set_altinterface()` on macOS with this comment:

```c
/* FIXME: this seems to cause trouble on the Mac:s so disable it. */
#ifndef __APPLE__
#if 0 /* Disable this always */
```

On macOS, `IOUSBHostInterface::SetAlternateInterface` triggers a full endpoint pipe reset
at the IOKit level. For Samsung devices using vendor-specific class (0xFF), this may:

1. Clear the MTP state machine in the device firmware
2. Reset endpoint toggle bits, causing the device to ignore subsequent bulk transfers
3. On Samsung's internal MTP stack, trigger a mode switch back to "waiting for host"

### Why pre-claim USB reset makes it worse

The Samsung 3-second window starts when the device is plugged in (or mode-switched to MTP).
A USB reset re-enumerates the device, effectively restarting this timer. Combined with our
300ms post-reset delay + claim retries + alt-setting + stabilize delays, we may exceed
the 3-second window before sending the first MTP command.

**Timeline comparison:**

```
libmtp:    claim → OpenSession  (< 100ms total)
SwiftMTP:  reset(300ms) → claim → alt_setting → stabilize(500ms) → clear_halt → delay → probe
           (> 1000ms before first MTP command, possibly 2-3s)
```

---

## 5. Proposed Fixes

### Fix 1: Skip set_interface_alt_setting for Samsung on macOS (HIGH priority)

In `claimCandidate()`, detect Samsung VID (`0x04e8`) and skip
`libusb_set_interface_alt_setting()` when running on macOS (Darwin). This matches
libmtp's behavior exactly.

**Implementation**: Add a `skipAltSettingOnMac` flag to the quirk system, or detect
Samsung VID in `claimCandidate()`.

### Fix 2: Skip pre-claim USB reset for Samsung (HIGH priority)

The Samsung quirk already has `"resetOnOpen": false` in the `flags` section, but the
transport code applies pre-claim reset to ALL vendor-specific (class 0xFF) devices.
Ensure Samsung (VID `0x04e8`) is exempted from this reset.

**Implementation**: Check VID before applying pre-claim reset in `open()`.

### Fix 3: Fix probe ladder order (MEDIUM priority)

Change the Samsung quirk's `probeLadder` to try OpenSession first (matching libmtp):

```json
"probeLadder": {
  "steps": [
    { "method": "openSessionThenGetDeviceInfo", "timeoutMs": 8000 },
    { "method": "sessionlessGetDeviceInfo", "timeoutMs": 5000 },
    { "method": "getStorageIDs", "timeoutMs": 5000 }
  ]
}
```

### Fix 4: Increase timeout to 60s (MEDIUM priority)

Match libmtp's 60,000 ms timeout for Samsung. Update quirk `handshakeTimeoutMs` to 60000
and `ioTimeoutMs` to 60000.

### Fix 5: Skip clear_halt before first probe command (MEDIUM priority)

For Samsung devices, skip the `libusb_clear_halt()` calls in `probeCandidate()`. libmtp
does not do this during initialization and it may confuse the Samsung MTP state.

### Fix 6: Minimize pre-command delays (LOW priority)

For Samsung, reduce `postClaimStabilizeMs` to 50–100ms (or 0) to stay within the
3-second session window. libmtp has zero delay between claim and first command.

---

## 6. Samsung-Specific USB Bugs

### 512-byte Packet Boundary Bug (`DEVICE_FLAG_SAMSUNG_OFFSET_BUG`)

From `device-flags.h`:

> "When GetPartialObject is invoked to read the last bytes of a file and the amount of
> data to read is such that the last USB packet sent in the reply matches exactly the
> USB 2.0 packet size, then the Samsung Galaxy device hangs, resulting in a timeout error."

**Impact**: This affects file transfer reads, not initialization. Our transfer layer should
ensure reads never align exactly to 512-byte boundaries. When reading the last chunk of a
file, if `(offset + length) % 512 == 0`, request one fewer byte and do a second read.

### ObjectInfo 64-bit Fields (`DEVICE_FLAG_PROPLIST_OVERRIDES_OI`)

Samsung Galaxy devices report ObjectInfo with 64-bit fields instead of 32-bit in some cases.
Always prefer MTP property list values over ObjectInfo when both are available.

### Connection Timeout Window

Samsung devices have an approximate 3-second window after USB enumeration to open an MTP
session. After this window, the device stops responding to MTP commands.

**Mitigation**: Minimize time between USB claim and OpenSession. Remove unnecessary delays
and intermediate steps.

---

## 7. Verification Plan

After implementing fixes, test with this sequence:

1. **Minimal init test**: Claim → OpenSession (no reset, no alt-setting, no clear_halt)
2. **GetDeviceInfo test**: After successful OpenSession, send GetDeviceInfo
3. **Storage enumeration**: GetStorageIDs with busy-backoff
4. **File listing**: GetObjectHandles on first storage
5. **Read test**: Download a small file, verify 512-byte boundary handling

Environment variable for debugging: `SWIFTMTP_DEBUG=1`

---

## 8. References

- libmtp source: https://github.com/libmtp/libmtp
  - `src/libusb-glue.c` — USB initialization, `init_ptp_usb()`, `configure_usb_device()`
  - `src/libmtp.c` — `LIBMTP_Open_Raw_Device_Uncached()`, device extension parsing
  - `src/music-players.h` — Samsung device flags and comments
  - `src/device-flags.h` — Flag definitions (SAMSUNG_OFFSET_BUG, LONG_TIMEOUT, etc.)
  - `src/ptp.c` — PTP transaction layer, `ptp_opensession()`
- SwiftMTP source:
  - `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/LibUSBTransport.swift` — Transport open
  - `SwiftMTPKit/Sources/SwiftMTPTransportLibUSB/InterfaceProbe.swift` — Claim and probe
  - `SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json` — Samsung quirk entry
