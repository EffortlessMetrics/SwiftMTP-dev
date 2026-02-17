# Error Codes Reference

Quick reference for SwiftMTP error codes.

## MTP Errors

| Code | Hex | Name | Description |
|------|-----|------|-------------|
| 0x2001 | 8193 | Undefined | Undefined error |
| 0x2002 | 8194 | InvalidParameter | Invalid operation parameter |
| 0x2003 | 8195 | Unknown | Device is busy |
| 0x2005 | 8197 | InvalidStorageID | Storage not found |
| 0x2006 | 8198 | InvalidObjectHandle | Object reference invalid |
| 0x2007 | 8199 | DevicePropNotSupported | Property not supported |
| 0x2008 | 8200 | InvalidObjectFormatCode | Format not supported |
| 0x200B | 8203 | StorageFull | No space left |
| 0x200C | 8204 | ObjectWriteProtected | Cannot write to object |
| 0x200E | 8206 | NoThumbnailPresent | No thumbnail available |
| 0x201D | 8221 | InvalidParameter | Write request rejected |
| 0x201E | 8222 | SessionAlreadyOpen | Session conflict |

## SwiftMTP Errors

### MTPError

```swift
enum MTPError: Error {
    case deviceDisconnected
    case permissionDenied
    case notSupported(String)
    case transport(TransportError)
    case protocolError(code: UInt16, message: String?)
    case objectNotFound
    case objectWriteProtected
    case storageFull
    case readOnly
    case timeout
    case busy
    case preConditionFailed(String)
}
```

### TransportError

```swift
enum TransportError: Error {
    case noDevice
    case timeout
    case busy
    case accessDenied
    case io(String)
}
```

## Common Error Solutions

### deviceDisconnected

- Reconnect device
- Ensure screen is unlocked
- Try different USB port/cable

### permissionDenied

- Accept trust prompt on device
- Check USB debugging is disabled
- Verify sandbox/entitlements

### timeout

- Increase timeout: `export SWIFTMTP_IO_TIMEOUT_MS=60000`
- Use better USB cable
- Connect directly (not via hub)

### storageFull

- Free space on device
- Delete unnecessary files
- Check for multiple storage partitions

### objectWriteProtected

- Try different folder (e.g., /Download)
- Check if file is DRM-protected
- Verify SD card not locked

### protocolError (0x201D)

- Write to a writable folder
- Common on restricted devices

### protocolError (0x201E)

- Close other MTP sessions
- Reconnect device
- Restart device

## Recovery Patterns

| Error Type | Recovery Strategy |
|------------|-------------------|
| Disconnect | Reconnect and retry |
| Timeout | Increase timeout, check cable |
| Busy | Wait and retry |
| Permission | Check trust prompt, entitlements |
| Storage | Free device space |

## Error Handling Best Practices

```swift
do {
    let device = try await manager.openDevice(summary: summary)
} catch MTPError.deviceDisconnected {
    // Handle disconnect
} catch MTPError.timeout {
    // Increase timeout and retry
} catch MTPError.protocolError(let code, let message) {
    // Handle protocol error
} catch {
    // Handle unknown error
}
```

## See Also

- [Troubleshooting Guide](../howto/troubleshoot-connection.md)
- [CLI Commands](cli-commands.md)
- [Full Error Documentation](../../ErrorCodes.md)
