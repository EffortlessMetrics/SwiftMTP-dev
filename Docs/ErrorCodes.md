# Error Codes Reference

Complete reference for all error types in SwiftMTP with explanations and recovery suggestions.

## Table of Contents

1. [MTPError](#mperror)
2. [TransportError](#transporterror)
3. [Protocol Error Codes](#protocol-error-codes)
4. [Error Handling Best Practices](#error-handling-best-practices)

---

## MTPError

Main error enum for MTP operations. All cases are `@Sendable` and `Equatable`.

### Error Cases

#### `deviceDisconnected`

```swift
case deviceDisconnected
```

- **Description**: The device disconnected during the operation
- **Cause**: Physical disconnection, device lock, or USB cable issues
- **Recovery**: Reconnect device, ensure it stays unlocked, retry operation

---

#### `permissionDenied`

```swift
case permissionDenied
```

- **Description**: Access to the USB device was denied
- **Cause**: Missing entitlements, sandbox restrictions, or system permission issues
- **Recovery**: 
  - Verify app entitlements include USB access
  - Check system preferences for USB device permissions
  - Run with elevated privileges if needed (development)

---

#### `notSupported(String)`

```swift
case notSupported(String)
```

- **Description**: Operation not supported by device or configuration
- **Cause**: Feature not implemented, device lacks capability, or invalid parameters
- **Recovery**: 
  - Check device specifications
  - Verify MTP mode is enabled
  - Update device firmware

---

#### `transport(TransportError)`

```swift
case transport(TransportError)
```

- **Description**: Wraps transport layer errors
- **Cause**: USB communication failures
- **Recovery**: See [TransportError](#transporterror) section

---

#### `protocolError(code: UInt16, message: String?)`

```swift
case protocolError(code: UInt16, message: String?)
```

- **Description**: MTP protocol-level error from device
- **Cause**: Device rejected the operation per MTP specification
- **Recovery**: Depends on specific error code - see [Protocol Error Codes](#protocol-error-codes)

---

#### `objectNotFound`

```swift
case objectNotFound
```

- **Description**: The requested object was not found
- **Cause**: File/folder deleted, incorrect handle, or path invalid
- **Recovery**: 
  - Refresh device storage listing
  - Verify object handle is valid
  - Check if file was deleted on device

---

#### `objectWriteProtected`

```swift
case objectWriteProtected
```

- **Description**: The target object is write-protected
- **Cause**: Read-only file, DRM-protected content, or system files
- **Recovery**:
  - Check file properties on device
  - Try a different folder (e.g., Download, DCIM)
  - Verify device storage is not locked

---

#### `storageFull`

```swift
case storageFull
```

- **Description**: The destination storage is full
- **Cause**: No free space on device
- **Recovery**:
  - Free up space on device
  - Delete unnecessary files
  - Use a different storage partition if available

---

#### `readOnly`

```swift
case readOnly
```

- **Description**: The storage is read-only
- **Cause**: SD card locked, device in read-only mode, or USB debugging restrictions
- **Recovery**:
  - Check SD card lock switch
  - Disable read-only mode in device settings
  - Verify USB mode is "File Transfer" not "PTP"

---

#### `timeout`

```swift
case timeout
```

- **Description**: The operation timed out while waiting for the device
- **Cause**: Device slow to respond, USB issues, or heavy I/O load
- **Recovery**:
  - Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=30000`
  - Try different USB port/cable
  - Close other USB applications

---

#### `busy`

```swift
case busy
```

- **Description**: The device is busy. Retry shortly.
- **Cause**: Device processing another operation, indexing, or locked
- **Recovery**:
  - Wait briefly and retry
  - Ensure device screen is unlocked
  - Close other apps accessing the device

---

#### `preconditionFailed(String)`

```swift
case preConditionFailed(String)
```

- **Description**: Precondition for operation was not met
- **Cause**: Invalid state, missing initialization, or assertion failure
- **Recovery**:
  - Review the failure reason string
  - Ensure device session is open
  - Check operation ordering

---

## TransportError

USB transport layer errors.

### Error Cases

#### `noDevice`

```swift
case noDevice
```

- **Description**: No MTP-capable USB device found
- **Recovery**:
  - Unplug and replug device
  - Confirm screen unlocked and trust prompt accepted
  - Verify USB mode is **File Transfer (MTP)**

---

#### `timeout`

```swift
case timeout
```

- **Description**: The USB transfer timed out
- **Recovery**:
  - Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=60000`
  - Use different USB port (direct, not hub)
  - Try different cable

---

#### `busy`

```swift
case busy
```

- **Description**: USB access is temporarily busy
- **Recovery**:
  - Retry after brief delay
  - Close competing USB applications
  - Wait for device to finish operations

---

#### `accessDenied`

```swift
case accessDenied
```

- **Description**: USB device is unavailable due to access restrictions
- **Recovery**:
  - Close competing apps: Android File Transfer, adb, browsers
  - Check if another process claimed the USB interface
  - Verify entitlements and permissions

---

#### `io(String)`

```swift
case io(String)
```

- **Description**: I/O error with custom message
- **Recovery**: See error message for details

---

## Protocol Error Codes

MTP protocol defines specific error codes returned by devices.

### Common Error Codes

| Code | Hex | Name | Description |
|------|-----|------|-------------|
| 0x2001 | 8193 | Undefined | Undefined error |
| 0x2002 | 8194 | InvalidParameter | Invalid operation parameter |
| 0x2005 | 8197 | InvalidStorageID | Storage not found |
| 0x2006 | 8198 | InvalidObjectHandle | Object reference invalid |
| 0x2007 | 8199 | DevicePropNotSupported | Property not supported |
| 0x2008 | 8200 | InvalidObjectFormatCode | Format not supported |
| 0x200B | 8203 | StorageFull | No space left |
| 0x200C | 8204 | ObjectWriteProtected | Cannot write to object |
| 0x200E | 8206 | NoThumbnailPresent | No thumbnail available |
| 0x201D | 8221 | InvalidParameter | Write request rejected |
| 0x201E | 8222 | SessionAlreadyOpen | Session conflict |

### Important Codes

#### `0x201D` - InvalidParameter (Write Rejected)

- **Message**: "Protocol error InvalidParameter (0x201D): write request rejected by device"
- **Recovery**: Write to a writable folder instead of root
  - Use folder handles: `0` (root), or explicit folder names
  - Try: `Download`, `DCIM`, or nested folders

#### `0x201E` - SessionAlreadyOpen

- **Message**: Session already open on device
- **Recovery**:
  - Close other MTP sessions (apps, File Transfer)
  - Restart USB connection
  - Reopen session explicitly

---

## Error Handling Best Practices

### Always Handle Async Errors

```swift
do {
    let handles = try await device.getObjectHandles()
} catch MTPError.deviceDisconnected {
    // Handle disconnect
} catch MTPError.timeout {
    // Handle timeout - maybe retry
} catch {
    // Log and handle generic error
}
```

### Use Recovery Suggestions

```swift
if let error = error as? MTPError,
   let suggestion = error.recoverySuggestion {
    print("Suggestion: \(suggestion)")
}
```

### Log Full Error Context

```swift
func logMTPError(_ error: MTPError) {
    print("Error: \(error.localizedDescription)")
    if let reason = error.failureReason {
        print("Reason: \(reason)")
    }
    if let suggestion = error.recoverySuggestion {
        print("Recovery: \(suggestion)")
    }
}
```

### Implement Retry Logic

```swift
func withRetry<T>(
    maxAttempts: Int = 3,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch MTPError.timeout {
            lastError = error
            // Wait before retry with exponential backoff
            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
        }
    }
    
    throw lastError!
}
```

---

## Related Documentation

- [Troubleshooting Guide](Troubleshooting.md)
- [Migration Guide](MigrationGuide.md)
- [API Documentation](SwiftMTP.docc/SwiftMTP.md)
- [Device-Specific Guides](SwiftMTP.docc/Devices/)
