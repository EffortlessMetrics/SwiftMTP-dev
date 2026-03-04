# MTP Compatibility Research: libmtp Device Flags Analysis

> **Date**: July 2025
> **Source**: libmtp `device-flags.h` and `music-players.h` (master branch)
> **Purpose**: Map libmtp's battle-tested device workarounds to SwiftMTP's QuirkFlags, identify gaps, and recommend additions.

## 1. libmtp Device Flags Reference

libmtp defines 32 device flags as a bitmask. Each flag works around a specific firmware bug or hardware limitation discovered through years of community testing across hundreds of devices.

### Transport-Level Flags

| Flag | Value | Description |
|------|-------|-------------|
| `DEVICE_FLAG_UNLOAD_DRIVER` | 0x02 | Detach kernel USB mass-storage driver before claiming MTP interface. Required for dual-mode devices. |
| `DEVICE_FLAG_NO_ZERO_READS` | 0x08 | Device doesn't send zero-length packets (ZLP) at transfer boundaries that are multiples of 64 bytes. Instead sends one extra byte. Critical for USB 1.1/2.0 endpoint size handling. |
| `DEVICE_FLAG_NO_RELEASE_INTERFACE` | 0x40 | Don't release USB interface on close — device locks up if you do. Affects SanDisk Sansa and some Creative devices. |
| `DEVICE_FLAG_ALWAYS_PROBE_DESCRIPTOR` | 0x800 | Always probe the OS Descriptor for proper operation. Required by SanDisk Sansa v2 chipset (AMS AD3525). |
| `DEVICE_FLAG_LONG_TIMEOUT` | 0x08000000 | Use extended timeout for slow operations. Common on Android devices. |
| `DEVICE_FLAG_FORCE_RESET_ON_CLOSE` | 0x10000000 | Issue USB reset after closing the connection. Required by Android and Sony NWZ devices. |

### Protocol-Level Flags

| Flag | Value | Description |
|------|-------|-------------|
| `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST_ALL` | 0x01 | GetObjPropList (0x9805) broken when querying ALL objects (objectHandle=0xFFFFFFFF, depth=0xFFFFFFFF). May return wrong count, missing objects, or cause timeout. |
| `DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST` | 0x04 | GetObjPropList (0x9805) broken for single-object queries. Many Android devices claim to support it but can't handle it. |
| `DEVICE_FLAG_IGNORE_HEADER_ERRORS` | 0x80 | Tolerate broken PTP response headers where code/transaction-ID fields contain junk. Found in Creative ZEN and Aricent MTP stacks. |
| `DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST` | 0x100 | SetObjectPropList fails on metadata updates. Individual SetObjectPropValue may still work. Affects Motorola RAZR2, Android devices. |
| `DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST` | 0x8000 | SendObjectPropList fails when creating new objects. Must fall back to SendObjectInfo + SendObject. Affects all Android devices and Toshiba Gigabeat. |
| `DEVICE_FLAG_CANNOT_HANDLE_DATEMODIFIED` | 0x4000 | Device claims DateModified is read/write but silently fails to update it. Can only set it on first send. Affects SanDisk Sansa E250. |
| `DEVICE_FLAG_BROKEN_BATTERY_LEVEL` | 0x10000 | GetDeviceProperty for battery level doesn't work. |
| `DEVICE_FLAG_DONT_CLOSE_SESSION` | 0x20000000 | Skip CloseSession on exit — 2016+ Canon EOS cameras return PTP errors after CloseSession. |
| `DEVICE_FLAG_PROPLIST_OVERRIDES_OI` | 0x40000000 | Use MTP property list data instead of GetObjectInfo. Samsung Galaxy devices return ObjectInfo with 64-bit fields in 32-bit slots. |

### Samsung-Specific Flags

| Flag | Value | Description |
|------|-------|-------------|
| `DEVICE_FLAG_SAMSUNG_OFFSET_BUG` | 0x80000000 | GetPartialObject hangs when the last USB packet exactly matches USB 2.0 packet size (512 bytes). Must pad or adjust read sizes to avoid the boundary. |

### Filename/Content Flags

| Flag | Value | Description |
|------|-------|-------------|
| `DEVICE_FLAG_ONLY_7BIT_FILENAMES` | 0x20 | Device only accepts 7-bit ASCII filenames (chars ≤ 0x7F). Violates PTP spec which mandates Unicode. Found on Philips Shoqbox. |
| `DEVICE_FLAG_UNIQUE_FILENAMES` | 0x02000000 | Device requires globally unique filenames — no two files can share the same name. |

### Composite Bug Profiles

libmtp defines pre-built flag combinations for common device families:

```c
// All Android devices (auto-detected via "android.com" extension)
DEVICE_FLAGS_ANDROID_BUGS =
    BROKEN_MTPGETOBJPROPLIST |       // 0x04 - single-object prop list broken
    BROKEN_SET_OBJECT_PROPLIST |     // 0x100 - can't update props via proplist
    BROKEN_SEND_OBJECT_PROPLIST |    // 0x8000 - can't create via proplist
    UNLOAD_DRIVER |                  // 0x02 - detach kernel driver
    LONG_TIMEOUT |                   // 0x08000000 - slow operations
    FORCE_RESET_ON_CLOSE             // 0x10000000 - USB reset on close

// Sony NWZ Walkman players (auto-detected via "sony.net" extension)
DEVICE_FLAGS_SONY_NWZ_BUGS =
    UNLOAD_DRIVER |
    BROKEN_MTPGETOBJPROPLIST |
    UNIQUE_FILENAMES |
    FORCE_RESET_ON_CLOSE

// Aricent MTP stack (SonyEricsson non-Android, auto-detected via "sonyericsson.com/SE")
DEVICE_FLAGS_ARICENT_BUGS =
    IGNORE_HEADER_ERRORS |
    BROKEN_SEND_OBJECT_PROPLIST |
    BROKEN_MTPGETOBJPROPLIST
```

## 2. SwiftMTP Coverage Analysis

### Already Handled ✅

| libmtp Flag | SwiftMTP QuirkFlag | Notes |
|-------------|-------------------|-------|
| `UNLOAD_DRIVER` | `requiresKernelDetach` | Default `true`. Uses `libusb_detach_kernel_driver`. |
| `LONG_TIMEOUT` | `extendedBulkTimeout` | 60s bulk transfer timeout. |
| `BROKEN_MTPGETOBJPROPLIST` | `supportsGetObjectPropList = false` | Disables 0x9805 for individual queries. |
| `BROKEN_MTPGETOBJPROPLIST_ALL` | `prefersPropListEnumeration = false` | Falls back to per-object GetObjectInfo. |
| Slow handshake | `needsLongerOpenTimeout` | Extended open/session timeout. |
| Samsung alt-setting | `skipAltSetting` | Avoids MTP state machine reset. |
| Samsung session window | `skipPreClaimReset` | Preserves 3-second session window. |

### Partially Handled ⚠️

| libmtp Flag | SwiftMTP QuirkFlag | Gap |
|-------------|-------------------|-----|
| `CANNOT_HANDLE_DATEMODIFIED` | `emptyDatesInSendObject` | SwiftMTP empties dates entirely; libmtp allows setting on first send only. Close enough for most devices. |
| `FORCE_RESET_ON_CLOSE` | `resetOnOpen` | SwiftMTP resets on *open*, not on *close*. Missing the close-time reset that Android/Sony devices need. |

### MISSING — Should Add 🔴

| libmtp Flag | Priority | Affected Devices | Recommended QuirkFlag |
|-------------|----------|------------------|-----------------------|
| `NO_ZERO_READS` | **HIGH** | Samsung (YP-K5, YP-P2, YP-T10, Galaxy), iRiver, many legacy players | `noZeroReads` |
| `BROKEN_SEND_OBJECT_PROPLIST` | **HIGH** | All Android, Aricent stack, Toshiba | `brokenSendObjectPropList` |
| `BROKEN_SET_OBJECT_PROPLIST` | **HIGH** | All Android, Motorola RAZR2 | `brokenSetObjectPropList` |
| `FORCE_RESET_ON_CLOSE` | **HIGH** | All Android, Sony NWZ | `forceResetOnClose` |
| `PROPLIST_OVERRIDES_OI` | **HIGH** | Samsung Galaxy (0x685c, 0x6860, 0x6877) | `propListOverridesObjectInfo` |
| `SAMSUNG_OFFSET_BUG` | **HIGH** | Samsung Galaxy (all MTP PIDs) | `samsungPartialObjectBoundaryBug` |
| `IGNORE_HEADER_ERRORS` | **MEDIUM** | Creative ZEN, Aricent stack (SonyEricsson) | `ignoreHeaderErrors` |
| `NO_RELEASE_INTERFACE` | **MEDIUM** | SanDisk Sansa, Creative Vision:M | `noReleaseInterface` |
| `DONT_CLOSE_SESSION` | **MEDIUM** | Canon EOS (2016+) | `skipCloseSession` |
| `ONLY_7BIT_FILENAMES` | **LOW** | Philips Shoqbox (rare device) | `only7BitFilenames` |
| `UNIQUE_FILENAMES` | **LOW** | Sony NWZ, Samsung YP-R1/U5/R0 | `requireUniqueFilenames` |

## 3. Common Failure Patterns by Manufacturer

### Samsung Galaxy (VID 0x04e8)

Samsung Galaxy devices running Samsung's own MTP stack (not stock Android MTP) are the most quirk-heavy devices in the libmtp database:

- **Session timeout window**: Device must receive OpenSession within ~3 seconds of USB connection, or it stops responding. libmtp comments: "GUI programs work fine" (because they connect immediately).
- **512-byte boundary hang** (`SAMSUNG_OFFSET_BUG`): GetPartialObject hangs when the response's last USB packet is exactly 512 bytes (USB 2.0 packet size). Workaround: adjust read size to avoid boundary.
- **64-bit ObjectInfo fields** (`PROPLIST_OVERRIDES_OI`): Samsung encodes some ObjectInfo fields as 64-bit where the spec says 32-bit. Must prefer MTP property list data.
- **GetObjPropList inconsistency**: Some Samsung PIDs (0x685c) need `BROKEN_MTPGETOBJPROPLIST_ALL` while others (0x6860) work without it — but the 512-byte USB packet bug can trigger failures that look like broken prop lists.
- **Flags needed**: `LONG_TIMEOUT | PROPLIST_OVERRIDES_OI | SAMSUNG_OFFSET_BUG | UNLOAD_DRIVER`

### Google Pixel / Stock Android (VID 0x18d1)

Stock Android MTP (AOSP) has a consistent set of limitations:

- **GetObjPropList (0x9805)**: Claims support but implementation is broken for single-object queries.
- **SendObjectPropList**: Broken — must use SendObjectInfo + SendObject path.
- **SetObjectPropList**: Broken — individual SetObjectPropValue may work.
- **Timeout**: Operations can be slow; extended timeout required.
- **Close behavior**: Needs USB reset after session close.
- **Flags needed**: `DEVICE_FLAGS_ANDROID_BUGS` (all six flags)

### Xiaomi (VID 0x2717)

Based on SwiftMTP's own testing:

- **Mi Note 2 (ff10)**: Only device with confirmed real file transfers. Works with current quirks.
- **Mi Note 2 (ff40)**: Returns 0 storages — may need session timing quirk.
- **Write failures**: Some Xiaomi/OnePlus devices reject writes to storage root (0x201D InvalidParameter). SwiftMTP handles this with `writeToSubfolderOnly`.

### Canon EOS (VID 0x04a9)

- **2016+ EOS cameras** (EOS R, etc.): Must NOT close the session on exit, or the device enters an error state and stops responding to PTP until power cycled.
- **Capture support**: Many Canon cameras support PTP capture operations (not MTP-specific but relevant for PTP cameras).
- **Flags needed**: `DONT_CLOSE_SESSION` (for 2016+ models)

### Nikon (VID 0x04b0)

- **Broken capture events**: Nikon DSLRs don't send proper ObjectAdded events after capture.
- **V1 series**: Needs different handling from DSLRs.
- These are primarily PTP/capture issues; less relevant for MTP file transfer.

### SanDisk Sansa (VID 0x0781)

- **Interface release lockup** (`NO_RELEASE_INTERFACE`): Device locks up if you release the USB interface or check endpoint status on close.
- **No zero reads**: Multiple models need `NO_ZERO_READS`.
- **DateModified**: Claims read/write but silently ignores updates.
- **Dual mode**: All Sansa devices are dual-mode (UMS + MTP) requiring kernel driver detach.
- **Flags needed**: `UNLOAD_DRIVER | BROKEN_MTPGETOBJPROPLIST | NO_RELEASE_INTERFACE | NO_ZERO_READS | CANNOT_HANDLE_DATEMODIFIED`

### Sony NWZ Walkman

- **Unique filenames**: Device requires globally unique filenames.
- **Force reset on close**: Needs USB device reset when disconnecting.
- **Flags needed**: `DEVICE_FLAGS_SONY_NWZ_BUGS`

### OnePlus (VID 0x2a70)

Based on SwiftMTP's testing (OnePlus 3T, PID 0xf003):

- Probe and read works, but writes fail with 0x201D (InvalidParameter).
- Likely needs `writeToSubfolderOnly` (already in SwiftMTP) plus standard Android bugs.

## 4. go-mtpfs and jmtpfs Common Issues

From go-mtpfs GitHub issues:

- **Timeout on initial connection** (issue #137): `LIBUSB_ERROR_TIMEOUT` on first USB read, recovered by close+reopen+new session. This pattern matches SwiftMTP's `resetReopenOnOpenSessionIOError`.
- **Stale directory listings** (issue #148): Files created by Android apps while mounted aren't visible until remount. MTP has no filesystem-level notification — must re-enumerate or poll events.
- **SessionAlreadyOpened recovery**: go-mtpfs handles this by closing the stale session and reopening. SwiftMTP should ensure similar recovery in `ErrorRecoveryLayer`.

## 5. Recommendations

### Immediate Additions (Wave 43+)

Add these QuirkFlags to `QuirkFlags.swift`:

1. **`noZeroReads`** — Devices that don't send zero-length packets at USB transfer boundaries. Without this, reads can hang waiting for a terminator that never comes. Affects Samsung, iRiver, and many legacy players.

2. **`brokenSendObjectPropList`** — Device can't handle SendObjectPropList (0x9808) for creating new objects. Must fall back to SendObjectInfo (0x100C) + SendObject (0x100D). This is the #1 Android compatibility flag.

3. **`brokenSetObjectPropList`** — SetObjectPropList (0x9806) fails. Fall back to individual SetObjectPropValue (0x9804) calls. Affects all Android devices.

4. **`forceResetOnClose`** — Issue `libusb_reset_device` after closing the session. Required by Android and Sony NWZ to leave the device in a clean state.

5. **`propListOverridesObjectInfo`** — Samsung Galaxy devices return malformed ObjectInfo (64-bit fields in 32-bit slots). When set, prefer MTP property list data over GetObjectInfo results.

6. **`samsungPartialObjectBoundaryBug`** — GetPartialObject hangs when the last USB packet exactly matches 512-byte USB 2.0 packet size. Workaround: adjust read offset/size to avoid the boundary.

### Future Additions (Lower Priority)

7. **`ignoreHeaderErrors`** — Tolerate malformed PTP response headers (broken code/transaction-ID). For Creative ZEN and Aricent stacks.

8. **`noReleaseInterface`** — Skip `libusb_release_interface` on close. For SanDisk Sansa devices.

9. **`skipCloseSession`** — Don't send CloseSession on disconnect. For 2016+ Canon EOS cameras.

10. **`only7BitFilenames`** — Restrict filenames to 7-bit ASCII. For Philips Shoqbox.

11. **`requireUniqueFilenames`** — Enforce globally unique filenames. For Sony NWZ Walkman.

### Auto-Detection by Vendor Extension

libmtp auto-assigns bug profiles based on the vendor extension string in GetDeviceInfo:

| Extension String | Auto-assigned Flags |
|------------------|-------------------|
| `"android.com"` | `DEVICE_FLAGS_ANDROID_BUGS` |
| `"sony.net"` | `DEVICE_FLAGS_SONY_NWZ_BUGS` |
| `"sonyericsson.com/SE"` (without `"android.com"`) | `DEVICE_FLAGS_ARICENT_BUGS` |

**Recommendation**: SwiftMTP should implement similar auto-detection in the quirk resolution layer. When a device connects with no matching VID:PID quirk entry, check the vendor extension string and apply the appropriate default profile. This would provide reasonable defaults for the thousands of Android devices not explicitly listed in `quirks.json`.

## 6. Key Takeaways

1. **Android is the hardest**: The composite `DEVICE_FLAGS_ANDROID_BUGS` (6 flags) is the single most commonly applied profile in libmtp's 900+ device database. SwiftMTP must handle all six.

2. **Samsung needs special love**: Samsung's custom MTP stack (not stock Android) has unique bugs (offset boundary hang, 64-bit ObjectInfo, 3-second session window) that require Samsung-specific flags beyond the standard Android set.

3. **Zero-length packet handling is critical**: `NO_ZERO_READS` affects USB transfer termination semantics. Getting this wrong causes hangs on affected devices. This is a transport-layer concern that SwiftMTP's libusb wrapper should handle.

4. **Camera devices are simpler**: PTP cameras (Canon, Nikon, Garmin) generally have fewer MTP bugs. The main concern is `DONT_CLOSE_SESSION` for Canon EOS and capture-related issues.

5. **Auto-detection reduces database maintenance**: libmtp's extension-string-based auto-detection covers unknown devices gracefully. SwiftMTP should adopt this pattern.
