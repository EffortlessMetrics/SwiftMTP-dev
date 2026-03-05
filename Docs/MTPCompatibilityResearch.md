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
| `NO_ZERO_READS` | `noZeroReads` | Handles missing ZLP at USB transfer boundaries. |
| `NO_RELEASE_INTERFACE` | `noReleaseInterface` | Skips `libusb_release_interface` on close. |
| `IGNORE_HEADER_ERRORS` | `ignoreHeaderErrors` | Tolerates junk in PTP response headers. |
| `BROKEN_SEND_OBJECT_PROPLIST` | `brokenSendObjectPropList` | Falls back to SendObjectInfo+SendObject. |
| `BROKEN_SET_OBJECT_PROPLIST` | `brokenSetObjectPropList` | Falls back to individual SetObjectPropValue. |
| `FORCE_RESET_ON_CLOSE` | `forceResetOnClose` | USB reset after session close. |
| `DONT_CLOSE_SESSION` | `skipCloseSession` | Skips CloseSession (Canon EOS 2016+). |
| `PROPLIST_OVERRIDES_OI` | `propListOverridesObjectInfo` | Prefers MTP prop list over ObjectInfo. |
| `SAMSUNG_OFFSET_BUG` | `samsungPartialObjectBoundaryBug` | Adjusts reads to avoid 512-byte boundary. |
| `ONLY_7BIT_FILENAMES` | `only7BitFilenames` | Strips non-ASCII from filenames. Wired into PathSanitizer + write path. |
| `UNIQUE_FILENAMES` | `requireUniqueFilenames` | Flag for unique filename enforcement. |
| `CANNOT_HANDLE_DATEMODIFIED` | `cannotHandleDateModified` | Explicit flag; `emptyDatesInSendObject` also available for broader date suppression. |
| `BROKEN_BATTERY_LEVEL` | `brokenBatteryLevel` | Skips battery level property queries. |
| `ALWAYS_PROBE_DESCRIPTOR` | `alwaysProbeDescriptor` | Forces OS descriptor probe on SanDisk Sansa v2. |
| `DELETE_SENDS_EVENT` | `deleteSendsEvent` | Device sends ObjectDeleted events after delete. |
| Slow handshake | `needsLongerOpenTimeout` | Extended open/session timeout. |
| Samsung alt-setting | `skipAltSetting` | Avoids MTP state machine reset. |
| Samsung session window | `skipPreClaimReset` | Preserves 3-second session window. |

### Partially Handled ⚠️

| libmtp Flag | SwiftMTP QuirkFlag | Gap |
|-------------|-------------------|-----|
| `CANNOT_HANDLE_DATEMODIFIED` | `emptyDatesInSendObject` + `cannotHandleDateModified` | `emptyDatesInSendObject` empties dates entirely; `cannotHandleDateModified` is the explicit flag for first-send-only semantics. Both available. |

### Remaining libmtp Flags (Low Priority) 🟡

| libmtp Flag | Priority | Reason Not Implemented |
|-------------|----------|----------------------|
| `IRIVER_OGG_ALZHEIMER` | **LOW** | Audio-player-specific OGG format detection; not relevant for file transfer. |
| `OGG_IS_UNKNOWN` | **LOW** | Audio codec metadata; not relevant for file transfer. |
| `FLAC_IS_UNKNOWN` | **LOW** | Audio codec metadata; not relevant for file transfer. |
| `BROKEN_SET_SAMPLE_DIMENSIONS` | **LOW** | Album art dimensions; Creative ZEN only. |
| `PLAYLIST_SPL_V1` / `V2` | **LOW** | Samsung proprietary playlist format. |
| `CAPTURE` / `CAPTURE_PREVIEW` | **LOW** | PTP camera capture; out of scope for MTP file transfer. |
| `NIKON_BROKEN_CAPTURE` / `NIKON_1` | **LOW** | Nikon-specific PTP capture quirks. |
| `NO_CAPTURE_COMPLETE` | **LOW** | Missing CaptureComplete events; camera-specific. |
| `OLYMPUS_XML_WRAPPED` | **LOW** | Olympus XML wrapping; camera-specific. |
| `SWITCH_MODE_BLACKBERRY` | **LOW** | BlackBerry USB mode switch; obsolete hardware. |

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

### Implemented ✅ (Wave 47)

All high-priority flags from the original research are now implemented in `QuirkFlags.swift`:

1. ✅ **`noZeroReads`** — Handles missing ZLP at USB transfer boundaries. Wired into transport layer.
2. ✅ **`brokenSendObjectPropList`** — Falls back to SendObjectInfo+SendObject. Wired into DeviceActor transfer path.
3. ✅ **`brokenSetObjectPropList`** — Falls back to individual SetObjectPropValue calls.
4. ✅ **`forceResetOnClose`** — USB reset after session close. Wired into LibUSBTransport.
5. ✅ **`propListOverridesObjectInfo`** — Prefers MTP property list data. Wired into DeviceActor.
6. ✅ **`samsungPartialObjectBoundaryBug`** — 512-byte boundary workaround. Wired into DeviceActor+PropList.
7. ✅ **`ignoreHeaderErrors`** — Tolerates junk PTP headers. Wired into MTPUSBLink+CommandExecution.
8. ✅ **`noReleaseInterface`** — Skips interface release. Wired into LibUSBTransport.
9. ✅ **`skipCloseSession`** — Skips CloseSession. Wired into DeviceActor.
10. ✅ **`only7BitFilenames`** — Restricts filenames to ASCII. Wired into PathSanitizer + DeviceActor write path.
11. ✅ **`requireUniqueFilenames`** — Flag for unique filename enforcement.

### Added in Wave 47 (New Flags)

12. ✅ **`cannotHandleDateModified`** — Explicit flag for devices where DateModified can only be set on first send. Complements `emptyDatesInSendObject`.
13. ✅ **`brokenBatteryLevel`** — Skip battery level (0x5001) property queries on broken devices.
14. ✅ **`alwaysProbeDescriptor`** — Force OS descriptor probe for SanDisk Sansa v2 chipset.
15. ✅ **`deleteSendsEvent`** — Device sends ObjectDeleted events after deletion, enabling event-driven cache invalidation.

### Future Work

- **Auto-detection by vendor extension**: Implement automatic flag assignment based on the vendor extension string from GetDeviceInfo (see section below).
- **`requireUniqueFilenames` enforcement**: Add collision detection + hash suffix logic in the write path.
- **`cannotHandleDateModified` wiring**: Add DateModified skip logic in SetObjectPropValue path for metadata updates.

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

6. **Coverage status (Wave 47)**: SwiftMTP now covers 22 of 32 libmtp device flags. The 10 remaining flags are audio-player-specific (OGG/FLAC format handling, Samsung SPL playlists), camera-capture-specific (Nikon/Olympus PTP), or obsolete (BlackBerry mode switch). These are intentionally deferred as they don't affect MTP file transfer reliability.
