# Zte V790 Blade3 0306

@Metadata {
    @DisplayName: "Zte V790 Blade3 0306"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Zte V790 Blade3 0306 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x19d2 |
| Product ID | 0x0306 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- libmtp: ZTE V790/Blade 3 (DEVICE_FLAGS_ANDROID_BUGS).
- Standard Android MTP stack with broken GetObjPropList.
- Requires kernel detach on macOS before USB claim.