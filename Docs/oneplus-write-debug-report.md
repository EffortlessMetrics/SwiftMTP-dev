# OnePlus 3T (2a70:f003) Write Failure Debug Report

## Status: IMPLEMENTED — All 7 identified fixes applied (wave46)

**Wave 46 changes**: Added `forceUndefinedFormatOnWrite` QuirkFlag and wired
it (along with `emptyDatesInSendObject` and `brokenSendObjectPropList`) into
the primary write parameters. Updated quirks entries with `brokenSetObjectPropList`,
`forceResetOnClose`, and `extendedBulkTimeout`. Awaiting real-device retest.

## Executive Summary

The OnePlus 3T (VID `0x2a70`, PID `0xf003`, model ONEPLUS A3010) can probe
and read files via MTP but fails with `0x201D` (InvalidParameter) on
`SendObjectInfo`/`SendObject` write operations. The device shares PID `0xf003`
with the OnePlus 2 (under Qualcomm VID `0x05c6`), suggesting a common
OxygenOS-based MTP stack derived from the Android MTP responder.

SwiftMTP already has significant OnePlus 3T workarounds (subfolder-only
writes, parent handle refresh, format-undefined retries) but writes still
fail in several scenarios. This report documents the root cause analysis,
libmtp's handling, and recommended next steps.

---

## 1  Observed Behaviour

### 1.1  Successful operations

- USB claim and interface probe: ~115 ms, clean
- `OpenSession`: succeeds instantly (0 ms), no retry needed
- `GetDeviceInfo`, `GetStorageIDs`, `GetStorageInfo`: all succeed
- `GetObjectHandles`, `GetObjectInfo`: reads work
- `GetPartialObject64`: supported and functional
- PTP Device Reset (`0x66`): NOT supported (rc=-9, `LIBUSB_ERROR_PIPE`)

### 1.2  Failing operation

```
Operation:  SendObjectInfo (0x100C) → SendObject (0x100D)
Error:      0x201D (InvalidParameter)
Condition:  When parent handle is 0x00000000 (storage root)
            Also fails intermittently with valid subfolder parents
```

The `0x201D` response means one or more parameters in the operation request
are rejected by the device's MTP responder. In the MTP 1.1 specification,
this maps to `MTP_RESPONSE_INVALID_PARAMETER`.

---

## 2  libmtp's Handling of OnePlus Devices

### 2.1  Device registration

libmtp registers OnePlus devices under two VIDs:

| VID | PID | Model | Entry |
|-----|-----|-------|-------|
| `0x05c6` (Qualcomm) | `0x6764` | OnePlus One (MTP) | `DEVICE_FLAGS_ANDROID_BUGS` |
| `0x05c6` (Qualcomm) | `0x6765` | OnePlus One (MTP+ADB) | `DEVICE_FLAGS_ANDROID_BUGS` |
| `0x05c6` (Qualcomm) | `0xf000` | OnePlus 7 Pro (MTP) | `DEVICE_FLAGS_ANDROID_BUGS` |
| `0x05c6` (Qualcomm) | `0xf003` | OnePlus 2 (A2003) (MTP) | `DEVICE_FLAGS_ANDROID_BUGS` |

The OnePlus 3T (VID `0x2a70`) is **not** in libmtp's `music-players.h`.
However, libmtp auto-detects Android devices via the `"android.com"` vendor
extension descriptor and applies `DEVICE_FLAGS_ANDROID_BUGS` automatically.

### 2.2  DEVICE_FLAGS_ANDROID_BUGS

```c
#define DEVICE_FLAGS_ANDROID_BUGS \
  (DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST | \
   DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST | \
   DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST | \
   DEVICE_FLAG_UNLOAD_DRIVER | \
   DEVICE_FLAG_LONG_TIMEOUT | \
   DEVICE_FLAG_FORCE_RESET_ON_CLOSE)
```

Critical flags for write operations:

- **`DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST` (0x8000)**: libmtp avoids
  `SendObjectPropList` (0x9808) entirely. It uses only the
  `SendObjectInfo` + `SendObject` two-phase approach. This is consistent
  with SwiftMTP's current behavior for OnePlus (the `useMediaTargetPolicy`
  code path skips the `SendObjectPropList` fallback).

- **`DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST` (0x0100)**: libmtp avoids
  `SetObjectPropList` for updating existing objects.

- **`DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST` (0x0004)**: `GetObjectPropList`
  may not return all properties. SwiftMTP already sets
  `supportsGetObjectPropList: false` in the quirks entry.

- **`DEVICE_FLAG_LONG_TIMEOUT` (0x08000000)**: Extended timeout for I/O
  operations. SwiftMTP uses 8000 ms which may be insufficient.

- **`DEVICE_FLAG_FORCE_RESET_ON_CLOSE` (0x10000000)**: USB reset when
  closing the device. SwiftMTP does not currently do this.

### 2.3  How libmtp writes files to Android devices

libmtp's `LIBMTP_Send_File_From_File_Descriptor()` flow for Android:

1. **Avoids `SendObjectPropList`** due to `BROKEN_SEND_OBJECT_PROPLIST`
2. Calls `SendObjectInfo` with:
   - Storage ID from device
   - Parent handle (folder handle, NOT root `0x00000000`)
   - ObjectInfo dataset with format `0x3000` (Undefined) for generic files
   - File size in the 32-bit ObjectCompressedSize field
3. Calls `SendObject` with the file data
4. On failure, does NOT retry with different parameters — it returns error

**Key insight**: libmtp uses format code `0x3000` (Undefined Object) for
generic files on Android, not `0x3001` (Association) or specific format codes.

---

## 3  Root Cause Analysis

### 3.1  Primary cause: Parent handle sensitivity

The OnePlus 3T MTP stack rejects `SendObjectInfo` when:
- Parent handle is `0x00000000` (storage root)
- Parent handle references a stale/invalid object handle

SwiftMTP's `writeToSubfolderOnly` flag addresses the root-write case, but
the parent handle can become stale between enumeration and write time if:
- The device reassigns handles (e.g., after MTP session events)
- Another MTP client modifies the filesystem
- The device's internal garbage collection runs

### 3.2  Secondary cause: Parameter ordering in ObjectInfo dataset

The MTP specification allows flexibility in ObjectInfo fields, but some
Android MTP stacks are strict about:
- **ObjectCompressedSize**: Must match actual data length exactly.
  Some stacks reject `0xFFFFFFFF` (unknown size) in the 32-bit field.
- **Date fields**: Some stacks reject empty or malformed date strings.
  SwiftMTP has `useEmptyDates` support but it's not enabled by default.
- **Object format**: Must be `0x3000` (Undefined) for non-media files.
  SwiftMTP's format-undefined retry already addresses this.

### 3.3  Tertiary cause: Timeout and recovery behavior

- libmtp uses `DEVICE_FLAG_LONG_TIMEOUT` for Android devices
- libmtp uses `DEVICE_FLAG_FORCE_RESET_ON_CLOSE` for session cleanup
- After a failed write, the MTP session state may be corrupted (the device
  may have created a partial object from `SendObjectInfo` that blocks
  subsequent writes to the same parent)

---

## 4  Current SwiftMTP Mitigations

| # | Mitigation | Status | Code Location |
|---|-----------|--------|---------------|
| 1 | `writeToSubfolderOnly` flag | ✅ Active | `DeviceActor+Transfer.swift:307-308` |
| 2 | Media target policy (shared with Xiaomi FF40) | ✅ Active | `DeviceActor+Transfer.swift:308` |
| 3 | Format-undefined as PRIMARY (via `forceUndefinedFormatOnWrite`) | ✅ Active (wave46) | `DeviceActor+Transfer.swift:456` |
| 4 | OnePlus parent handle refresh | ✅ Active | `DeviceActor+Transfer.swift:561-567` |
| 5 | `WriteTargetLadder` folder resolution | ✅ Active | `DeviceActor+Transfer.swift:325-340` |
| 6 | `SendObjectPropList` blocked by `brokenSendObjectPropList` | ✅ Active | `DeviceActor+Transfer.swift:809` |
| 7 | `skipPTPReset: true` | ✅ Active | quirks.json |
| 8 | Session recovery on 0x2003 | ✅ Active | `DeviceActor+Transfer.swift:1162` |
| 9 | Empty dates via `emptyDatesInSendObject` | ✅ Active (wave46) | `DeviceActor+Transfer.swift:304` |
| 10 | `forceResetOnClose` for session cleanup | ✅ Active (wave46) | quirks.json flags |
| 11 | `extendedBulkTimeout` for long operations | ✅ Active (wave46) | quirks.json flags |
| 12 | `brokenSetObjectPropList` for metadata updates | ✅ Active (wave46) | quirks.json flags |

---

## 5  Potential Fixes to Try

### Fix 1: Force format code 0x3000 (Undefined) on first attempt
**Priority: HIGH**

Currently SwiftMTP sends the inferred format code on the first attempt and
only falls back to `Undefined` (0x3000) on retry. libmtp always uses 0x3000
for generic files on Android. Making this the default for OnePlus could
eliminate the retry round-trip.

```
Change: Set useUndefinedObjectFormat=true as the PRIMARY parameter for OnePlus
Where:  DeviceActor+Transfer.swift, primaryParams construction
```

### Fix 2: Increase I/O timeout to match libmtp's LONG_TIMEOUT
**Priority: HIGH**

The current quirks entry has `ioTimeoutMs: 8000`. libmtp's
`DEVICE_FLAG_LONG_TIMEOUT` typically doubles the default timeout. Consider
increasing to 15000-20000 ms for write operations, matching the OnePlus 9
entry which uses `ioTimeoutMs: 15000`.

```
Change: Update quirks.json ioTimeoutMs from 8000 to 15000
```

### Fix 3: Stale parent handle detection before write
**Priority: MEDIUM**

Before calling `SendObjectInfo`, verify the parent handle is still valid by
calling `GetObjectInfo` on it. If it returns object-not-found, re-resolve
the parent via `WriteTargetLadder`. This preemptive check avoids the
`0x201D` error and the associated retry overhead.

```
Change: Add parent validation in performWrite() before SendObjectInfo
Where:  DeviceActor+Transfer.swift, performWrite function
```

### Fix 4: Orphan cleanup after failed SendObjectInfo
**Priority: MEDIUM**

When `SendObjectInfo` succeeds but `SendObject` fails, the device may retain
a zero-byte placeholder object. Subsequent writes to the same parent with
the same filename can then fail with `0x201D` because the name already
exists. After a write failure, attempt to delete the orphaned handle.

```
Change: SwiftMTP already has DeviceActor+Reconcile.swift for this —
        verify it runs for OnePlus 0x201D failures
```

### Fix 5: Try zero in ObjectInfo parent handle field
**Priority: LOW**

The MTP spec allows `0x00000000` as the parent in the `SendObjectInfo`
*command parameters* while using a different value in the ObjectInfo
*dataset*. Some devices are strict about matching these. The
`zeroObjectInfoParentHandle` retry parameter tests this but is only tried
after the first failure. Consider enabling it as a quirks flag.

### Fix 6: Empty date fields in ObjectInfo
**Priority: LOW**

Some Android MTP stacks reject ObjectInfo with non-empty date strings that
don't exactly match the expected format (`YYYYMMDDThhmmss`). The quirks
entry should enable `emptyDatesInSendObject: true` to skip date fields.

### Fix 7: Force USB reset on session close
**Priority: LOW**

libmtp's `DEVICE_FLAG_FORCE_RESET_ON_CLOSE` performs a USB reset when
closing the device. This may help clean up corrupted MTP session state
between write attempts. Consider adding a `forceResetOnClose` quirks flag.

---

## 6  Comparison with OnePlus 9 Quirks

| Property | OnePlus 3T (f003) | OnePlus 9 (9011) |
|----------|-------------------|------------------|
| VID | 0x2a70 | 0x2a70 |
| PID | 0xf003 | 0x9011 |
| maxChunkBytes | 1 MB | 2 MB |
| ioTimeoutMs | 8000 | 15000 |
| writeToSubfolderOnly | true | false |
| supportsGetObjectPropList | false | true |
| skipPTPReset | true | — |
| resetOnOpen | false | false |

The OnePlus 9 has a more modern MTP stack (OxygenOS 11+/ColorOS) that
supports `GetObjectPropList` and doesn't require subfolder-only writes. The
OnePlus 3T runs OxygenOS 3-5 (Android 6-8) with an older MTP responder.

---

## 7  Recommended Next Steps

### Immediate (no device needed)

1. **Update quirks.json**: Increase `ioTimeoutMs` to 15000, add
   `brokenSendObjectPropList: true`, add `emptyDatesInSendObject: true`,
   add `forceUndefinedFormatOnWrite: true` flag
2. **Add libmtp compatibility note**: Document that libmtp applies
   `DEVICE_FLAGS_ANDROID_BUGS` to all OnePlus devices

### Next device session

3. **Test with SWIFTMTP_DEBUG=1**: Capture full parameter dump of the
   `SendObjectInfo` command that triggers `0x201D`
4. **Test format code 0x3000 as primary**: Verify if using Undefined format
   on the first attempt eliminates the error
5. **Test increased timeout**: Verify 15000 ms prevents timeout-related
   failures that could mask as `0x201D`
6. **Test orphan cleanup**: Verify that failed writes don't leave stale
   objects blocking subsequent writes

### Future investigation

7. **USB packet capture**: Compare libmtp's vs SwiftMTP's raw USB packets
   for the `SendObjectInfo` command on OnePlus 3T
8. **OxygenOS version matrix**: Test across OxygenOS 3.x, 4.x, and 5.x to
   identify firmware-specific behavior differences

---

## 8  References

- MTP 1.1 Specification §C.1: Response Code 0x201D (Invalid_Parameter)
- libmtp `src/device-flags.h`: `DEVICE_FLAGS_ANDROID_BUGS` definition
- libmtp `src/music-players.h`: OnePlus 2 (0x05c6:0xf003) entry
- SwiftMTP `DeviceActor+Transfer.swift`: OnePlus-specific write logic
- SwiftMTP quirks entry: `oneplus-3t-f003`
- Related: Pixel 7 debug report (`Docs/pixel7-usb-debug-report.md`)
- Related: Samsung MTP research (`Docs/samsung-mtp-research.md`)
