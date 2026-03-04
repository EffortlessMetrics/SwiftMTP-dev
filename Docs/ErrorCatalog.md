# Error Catalog

> Complete reference of all error codes and types in SwiftMTP, with causes and troubleshooting steps.
> For scenario-based troubleshooting, see [Troubleshooting.md](Troubleshooting.md).

## Table of Contents

1. [MTP Response Codes (PTP/MTP Standard)](#mtp-response-codes)
2. [MTP Extension Response Codes](#mtp-extension-response-codes)
3. [MTPError Cases](#mtperror-cases)
4. [Transport Errors](#transport-errors)
5. [Error Recovery Layer](#error-recovery-layer)
6. [Module-Specific Errors](#module-specific-errors)
7. [Common Troubleshooting Scenarios](#common-troubleshooting-scenarios)
8. [Environment Variables](#environment-variables)

---

## MTP Response Codes

These are standard PTP/MTP response codes returned by devices. Defined in
`SwiftMTPCore/Internal/Protocol/PTPCodec.swift` and surfaced as
`MTPError.protocolError(code:message:)`.

| Code | Name | Description | Common Causes | Recovery |
|------|------|-------------|---------------|----------|
| `0x2001` | OK | The operation completed successfully. | — | No action needed. |
| `0x2002` | GeneralError | The device reported an unspecified failure. | Internal device error, firmware bug. | Retry the operation. If it persists, reconnect the device. |
| `0x2003` | SessionNotOpen | No MTP session is currently open. | Session was closed or never opened; device reset mid-operation. | Re-open the MTP session (disconnect and reconnect if needed), then retry. The [error recovery layer](#error-recovery-layer) handles this automatically. |
| `0x2004` | InvalidTransactionID | The transaction ID is invalid or out of sequence. | Transaction counter desync after partial failure. | Reconnect the device to reset the transaction counter. |
| `0x2005` | OperationNotSupported | The device does not support this operation. | Device firmware lacks the requested MTP operation (e.g. `CopyObject`, `GetThumb`). | Check the device's supported operations list. Try an alternative approach or update device firmware. |
| `0x2006` | ParameterNotSupported | One or more parameters are not supported by the device. | Sending unrecognized parameter values. | Check that all parameters are valid for this device and firmware version. |
| `0x2007` | IncompleteTransfer | The transfer did not complete; data may be partial. | Cable disconnect during transfer, USB bus error. | Retry the transfer. If it fails repeatedly, try a smaller file or check the cable. |
| `0x2008` | InvalidStorageID | The storage ID is not recognized by the device. | Storage was ejected, or stale storage ID after device reconnect. | Refresh the storage list (`swiftmtp ls`) and retry with a valid storage ID. |
| `0x2009` | InvalidObjectHandle | The object handle does not refer to a valid object. | Object was deleted on-device, or handle invalidated after disconnect. | Refresh the object listing and retry with a valid object handle. |
| `0x200A` | DevicePropNotSupported | The specified device property is not supported. | Querying a property the device firmware doesn't implement. | Use a different device property, or check the device's supported properties list. |
| `0x200B` | InvalidObjectFormatCode | The object format code is not valid for this operation. | Sending an unrecognized or unsupported format code. | Verify the file format is supported by the device. |
| `0x200C` | StoreFull | The device storage is full. | No free space remaining on the target storage. | Free space on the device by deleting unneeded files, then retry. |
| `0x200D` | ObjectWriteProtected | The target object is write-protected. | File or folder marked read-only on device. | Remove write-protection on the device, or choose a different target file. |
| `0x200E` | StoreReadOnly | The device storage is read-only. | SD card write-protect switch enabled, or storage mounted read-only. | Check for a read-only lock (e.g. SD card switch) and remount as writable. |
| `0x200F` | AccessDenied | Access to the object was denied by the device. | DRM restrictions, permission policy on device. | Check device permissions and DRM restrictions. |
| `0x2010` | NoThumbnailPresent | No thumbnail is available for this object. | Object type doesn't embed thumbnails (e.g. documents). | Skip thumbnail requests for this object. Not all objects have thumbnails. |
| `0x2011` | SelfTestFailed | The device self-test failed. | Hardware or firmware issue. | The device may need servicing. Check manufacturer support. |
| `0x2012` | PartialDeletion | Only some of the requested objects were deleted. | Some objects locked or in use. | Retry deleting the remaining objects individually. |
| `0x2013` | StoreNotAvailable | The specified storage is not currently available. | Storage media ejected, unmounted, or inaccessible. | Check that the storage media is inserted and the device is unlocked, then retry. |
| `0x2014` | SpecificationByFormatUnsupported | Filtering by object format is not supported. | Device doesn't support format-based queries. | Remove the format filter and retry the operation. |
| `0x2015` | NoValidObjectInfo | No valid ObjectInfo was sent before the transfer. | Attempting `SendObject` without prior `SendObjectInfo`. | Send ObjectInfo (`SendObjectInfo`) before attempting to send the object data. |
| `0x2016` | InvalidCodeFormat | The code format is not valid. | Malformed code format value. | Verify the code format matches the MTP specification. |
| `0x2017` | UnknownVendorCode | The vendor extension code is not recognized. | Using vendor-specific codes on a device that doesn't support them. | Use only standard MTP codes unless the device's vendor extension is confirmed. |
| `0x2018` | CaptureAlreadyTerminated | The capture operation has already been terminated. | Stopping an already-stopped capture. | No action needed — the capture is already stopped. |
| `0x2019` | DeviceBusy | The device is busy processing another request. | Device processing a prior MTP command. | Wait a moment for the device to finish, then retry. Ensure device screen is on. |
| `0x201A` | InvalidParentObject | The specified parent object is invalid. | Parent folder was deleted or handle is stale. | Verify the parent folder exists and use a valid parent object handle. |
| `0x201B` | InvalidDevicePropFormat | The device property format is invalid. | Property value sent in wrong data type. | Check the property type and send the value in the correct format. |
| `0x201C` | InvalidDevicePropValue | The device property value is out of range or invalid. | Property value outside allowed range. | Check the allowed range for this property and send a valid value. |
| `0x201D` | InvalidParameter | One or more parameters in the request are invalid. | Writing to storage root on devices that forbid it (Xiaomi, OnePlus); stale handle. | Write to a writable folder (e.g. `Download`, `DCIM`) instead of root. See [WriteTargetLadder](#write-target-ladder). |
| `0x201E` | SessionAlreadyOpen | An MTP session is already open on this device. | Calling `OpenSession` when one is already open. | Close the existing session first, or disconnect and reconnect the device. |
| `0x201F` | TransactionCancelled | The transaction was cancelled. | Host or device cancelled an in-progress operation. | Retry the operation if the cancellation was unintentional. |
| `0x2020` | SpecificationOfDestinationUnsupported | The specified destination is not supported. | Device doesn't support the copy/move destination. | Choose a different destination that the device supports. |

---

## MTP Extension Response Codes

Extended codes defined by the MTP 1.1 specification for object property operations.

| Code | Name | Description | Recovery |
|------|------|-------------|----------|
| `0xA801` | InvalidObjectPropCode | The object property code is not recognized by the device. | Use only object property codes supported by the device. |
| `0xA802` | InvalidObjectPropFormat | The object property format does not match the expected type. | Check the property type and send the value in the correct format. |
| `0xA803` | InvalidObjectPropValue | The object property value is outside the allowed range. | Check the allowed range for this property and send a valid value. |
| `0xA804` | InvalidObjectReference | The referenced object does not exist or the reference is broken. | Refresh the object listing and use a valid object reference. |
| `0xA805` | GroupNotSupported | The device does not support group-based operations. | Perform operations on individual objects instead of groups. |
| `0xA806` | InvalidDataset | The property dataset sent to the device is malformed or incomplete. | Verify the property dataset structure matches the MTP specification. |
| `0xA807` | SpecificationByGroupUnsupported | The device does not support filtering by object property group. | Remove the unsupported filter and retry the operation. |
| `0xA808` | SpecificationByDepthUnsupported | The device does not support filtering by hierarchy depth. | Remove the depth filter and retry the operation. |
| `0xA809` | ObjectTooLarge | The file exceeds the maximum object size the device can store. | Reduce the file size or split the file into smaller parts. |
| `0xA80A` | ObjectPropNotSupported | The specified object property is not implemented by the device. | Use only object property codes supported by the device. |

---

## MTPError Cases

The primary error type for SwiftMTP operations, defined in `SwiftMTPCore/Public/Errors.swift`.

| Case | Description | Failure Reason | Recovery Suggestion |
|------|-------------|----------------|---------------------|
| `.deviceDisconnected` | The device disconnected during the operation. | USB cable unplugged or device powered off mid-transfer. | Reconnect the cable, unlock the device, and retry. |
| `.permissionDenied` | Access to the USB device was denied. | macOS requires explicit permission for USB device access. | Open System Settings → Privacy & Security and grant USB access. Re-approve the device trust prompt. |
| `.notSupported(String)` | The device or firmware does not support the requested operation. | Device firmware lacks the requested MTP operation. | Check that the device firmware is up to date, or try a different operation. |
| `.transport(TransportError)` | A low-level USB transport error occurred. | See [Transport Errors](#transport-errors) below. | See [Transport Errors](#transport-errors) below. |
| `.protocolError(code, message)` | The device returned an MTP error response code. | See [MTP Response Codes](#mtp-response-codes) above. | See [MTP Response Codes](#mtp-response-codes) above. |
| `.objectNotFound` | The requested object was not found on the device. | Object handle invalidated by a device-side change. | Refresh the object listing and verify the file still exists. |
| `.objectWriteProtected` | The target object is write-protected. | File or folder marked as write-protected on device. | Remove write-protection on the device, or choose a different target. |
| `.storageFull` | The destination storage is full. | Device storage has no remaining free space. | Free space on the device, then re-attempt the transfer. |
| `.readOnly` | The storage is read-only. | Storage volume mounted as read-only (e.g. SD card lock). | Check for a read-only lock and remount as writable. |
| `.timeout` | The operation timed out waiting for the device. | Device did not respond within the configured timeout. | Ensure the device is unlocked and screen is on. Increase `SWIFTMTP_IO_TIMEOUT_MS`. |
| `.busy` | The device is busy. | Device processing another request or in a locked state. | Unlock the device screen, dismiss prompts, wait, then retry. |
| `.sessionBusy` | A protocol transaction is already in progress. | Only one MTP transaction can be in-flight per session. | Wait for the current operation to complete, then retry. |
| `.preconditionFailed(String)` | A required precondition was not met. | Missing storage, missing arguments, or invalid state. | Verify the device session is open and storage IDs are valid. |
| `.verificationFailed(expected, actual)` | Write verification failed — remote size doesn't match. | File truncated or corrupted during transfer. | Re-send the file and verify the transfer completes without interruption. |

---

## Transport Errors

Low-level USB transport errors defined in `SwiftMTPCore/Public/Errors.swift` as `TransportError`.
These are wrapped in `MTPError.transport(...)` when surfaced to callers.

| Case | Description | Failure Reason | Recovery Suggestion |
|------|-------------|----------------|---------------------|
| `.noDevice` | No MTP-capable USB device found. | No matching USB interface was claimed for MTP. | Unplug and replug the device. Confirm screen unlocked and trust prompt accepted. Ensure device is in File Transfer (MTP) mode. |
| `.timeout` | The USB transfer timed out. | Device did not complete the USB request on time. | Retry after increasing `SWIFTMTP_IO_TIMEOUT_MS`. Ensure the device screen is on. |
| `.busy` | USB access is temporarily busy. | USB bus or host controller contended by another transfer. | Wait a moment, close other USB-intensive applications, then retry. |
| `.accessDenied` | USB device unavailable due to access/claim restrictions. | Another process owns the interface (Android File Transfer, adb, browsers). | Close competing USB tools (Android File Transfer, adb, Samsung Smart Switch), then retry. |
| `.stall` | A USB endpoint stalled; the transfer was aborted. | Unsupported command or protocol mismatch caused endpoint halt. | Disconnect and reconnect the device. Try a different USB port or cable. |
| `.timeoutInPhase(phase)` | USB transfer timed out during a specific phase (bulk-out, bulk-in, or response-wait). | Device stopped responding during the named transfer phase. | Check the cable connection, ensure device is unlocked. Increase `SWIFTMTP_IO_TIMEOUT_MS`. |
| `.io(String)` | A low-level USB I/O error occurred. | Hardware-level USB communication failure. | Try a different USB port or cable. Reconnect the device and retry. |

---

## Error Recovery Layer

SwiftMTP includes an automatic error recovery layer (`ErrorRecoveryLayer` in
`SwiftMTPCore/Internal/ErrorRecoveryLayer.swift`) that handles transient failures
without manual intervention. Understanding these strategies helps diagnose persistent errors.

### Recovery Strategies

| Strategy | Trigger | Behavior | Max Retries |
|----------|---------|----------|-------------|
| **Session Recovery** | `SessionNotOpen` (0x2003) or `SessionAlreadyOpen` (0x201E) | Closes and re-opens the MTP session, then retries the operation. | 3 |
| **Stall Recovery** | `TransportError.stall` (LIBUSB_ERROR_PIPE) | Clears the endpoint halt condition and retries the transfer. | 3 |
| **Timeout Escalation** | `TransportError.timeout` or `.timeoutInPhase` | Doubles the timeout on each retry, up to 60,000 ms maximum. | Escalates until max timeout reached |
| **Disconnect Recovery** | `MTPError.deviceDisconnected` | Saves transfer journal state for later resume; emits disconnect event. | N/A (terminal) |

### When Recovery Fails

If automatic recovery exhausts all retries, the original error is re-thrown to the caller.
Check the recovery log for diagnostics:

```swift
// In code
let events = await RecoveryLog.shared.recentEvents()

// Via CLI
swiftmtp events  # Shows recovery events in the event stream
```

### Write Target Ladder

When writing files, some devices (Xiaomi, OnePlus) return `InvalidParameter` (0x201D) for
writes to the storage root. The `WriteTargetLadder` (`SwiftMTPCore/Internal/Transfer/WriteTargetLadder.swift`)
automatically tries alternative parent folders:

1. Requested parent folder
2. `Download` folder
3. `DCIM` folder
4. Other writable folders in storage root

---

## Module-Specific Errors

### DBError (SwiftMTPIndex)

SQLite database errors from `SwiftMTPIndex/DB/SQLiteHelpers.swift`.

| Case | Description |
|------|-------------|
| `.open(String)` | Failed to open the SQLite database. |
| `.prepare(String)` | Failed to prepare a SQL statement. |
| `.step(String)` | Failed to execute a SQL statement step. |
| `.bind(String)` | Failed to bind a parameter to a SQL statement. |
| `.column(String)` | A required column is missing from the result. |
| `.notFound` | No rows matched the query. |
| `.constraint(String)` | A database constraint was violated. |

### EnumerationError (SwiftMTPFileProvider)

File Provider enumeration errors from `SwiftMTPFileProvider/DomainEnumerator.swift`.

| Case | Description |
|------|-------------|
| `.timeout` | Enumeration timed out — device may be disconnected. |

### XPCDeviceError (SwiftMTPXPC)

XPC service errors from `SwiftMTPXPC/MTPXPCServiceImpl.swift`.

| Case | Description |
|------|-------------|
| `.operationTimeout` | Device operation timed out — device may be disconnected. |

---

## Common Troubleshooting Scenarios

### "No devices found"

**Error**: `TransportError.noDevice`

**Checklist**:
1. Check the USB cable is connected and the device screen is unlocked
2. Confirm the device is in **File Transfer (MTP)** mode (not charging-only or PTP)
3. Accept any trust/authorization prompts on the device
4. Close competing apps: Android File Transfer, adb, Samsung Smart Switch, Image Capture
5. Try a different USB port or cable
6. On macOS, check System Settings → Privacy & Security → USB access

```bash
# Diagnose USB claim issues
swiftmtp probe --verbose
```

### "Operation not supported" (0x2005)

**Error**: `MTPError.protocolError(code: 0x2005, ...)`

**Checklist**:
1. Check the device's MTP version and supported operations (`swiftmtp info`)
2. Some operations (e.g. `CopyObject`, Android edit extensions) are not universally supported
3. Update device firmware if possible
4. Try an alternative approach (e.g. download-then-reupload instead of server-side copy)

### "Store full" (0x200C)

**Error**: `MTPError.storageFull` or `MTPError.protocolError(code: 0x200C, ...)`

**Checklist**:
1. Free space on the device by deleting unneeded files
2. Check available space: `swiftmtp ls --storage`
3. Try a different storage if available (internal vs SD card)

### "Invalid parameter" (0x201D)

**Error**: `MTPError.protocolError(code: 0x201D, ...)`

**Checklist**:
1. If writing files — avoid storage root; use a subfolder like `Download` or `DCIM`
2. Object handles may be stale after disconnect — refresh the listing
3. Some devices (Xiaomi, OnePlus) have strict parent-folder requirements
4. The `WriteTargetLadder` handles this automatically for push/upload operations

### "Device busy" (0x2019)

**Error**: `MTPError.busy` or `MTPError.protocolError(code: 0x2019, ...)`

**Checklist**:
1. Unlock the device screen and dismiss any on-screen prompts
2. Wait a few seconds and retry
3. Close other apps using the device (camera, gallery, file manager)
4. The error recovery layer retries automatically for transient busy states

### "Session not open" (0x2003)

**Error**: `MTPError.protocolError(code: 0x2003, ...)`

**Checklist**:
1. The error recovery layer should handle this automatically (up to 3 retries)
2. If persistent, disconnect and reconnect the device
3. Ensure no other MTP client has the session open

### "USB claim failed" / "Access denied"

**Error**: `TransportError.accessDenied`

**Checklist**:
1. Close **Android File Transfer** — it aggressively claims MTP devices on macOS
2. Stop `adb` server: `adb kill-server`
3. Close Samsung Smart Switch, Image Capture, or any photo import tools
4. Check macOS USB permissions in System Settings → Privacy & Security
5. Try: `swiftmtp probe --verbose` for detailed claim diagnostics

### "Bulk transfer timeout"

**Error**: `TransportError.timeout` or `TransportError.timeoutInPhase(...)`

**Checklist**:
1. Ensure the device screen is on and unlocked during transfers
2. Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=30000`
3. The timeout escalation recovery strategy doubles timeouts automatically
4. Try a different USB port (prefer USB 3.0+ ports)
5. Check the cable — some cables are charge-only

### "Pipe stall"

**Error**: `TransportError.stall`

**Checklist**:
1. The stall recovery layer clears the halt condition and retries automatically
2. If persistent, disconnect and reconnect the device
3. Try a different USB port or cable
4. May indicate a protocol mismatch — check device quirks (`swiftmtp quirks`)

### "Write verification failed"

**Error**: `MTPError.verificationFailed(expected:actual:)`

**Checklist**:
1. The file may have been truncated during transfer
2. Re-send the file and verify the transfer completes without interruption
3. Check for available storage space on the device
4. Try a smaller file to isolate the issue
5. Check the transfer journal for resume capability

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SWIFTMTP_IO_TIMEOUT_MS` | `10000` | USB I/O timeout in milliseconds. Increase for slow devices or large transfers. |
| `SWIFTMTP_DEMO_MODE` | `0` | Set to `1` to enable demo mode with simulated devices. |
| `SWIFTMTP_MOCK_PROFILE` | — | Mock device profile: `pixel7`, `galaxy`, `iphone`, `canon`. |

---

## Related Documentation

- [Troubleshooting Guide](Troubleshooting.md) — scenario-based device troubleshooting
- [Device Guides](SwiftMTP.docc/Devices/) — device-specific documentation
- [Benchmarks](benchmarks.md) — transfer performance data
- [Pixel 7 Debug Report](pixel7-usb-debug-report.md) — detailed USB debugging for Pixel 7

---

## Source Files

| File | Contents |
|------|----------|
| `SwiftMTPCore/Public/Errors.swift` | `MTPError`, `TransportError`, `TransportPhase` |
| `SwiftMTPCore/Internal/Protocol/PTPCodec.swift` | `PTPResponseCode` names and user messages |
| `SwiftMTPCore/Internal/ErrorRecoveryLayer.swift` | Automatic recovery strategies |
| `SwiftMTPCore/Internal/Transfer/WriteTargetLadder.swift` | Write target fallback logic |
| `SwiftMTPObservability/RecoveryLog.swift` | Recovery event logging |
| `SwiftMTPIndex/DB/SQLiteHelpers.swift` | `DBError` |
| `SwiftMTPFileProvider/DomainEnumerator.swift` | `EnumerationError` |
| `SwiftMTPXPC/MTPXPCServiceImpl.swift` | `XPCDeviceError` |
