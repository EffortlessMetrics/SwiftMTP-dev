# Asus Zenfone4 580F

@Metadata {
    @DisplayName: "Asus Zenfone4 580F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Asus Zenfone4 580F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0b05 |
| Product ID | 0x580f |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0xff |
| Protocol | 0x00 |
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

- libmtp: Asus ZenFone 4 (MTP) (DEVICE_FLAGS_ANDROID_BUGS).
- Standard Android MTP stack with broken GetObjPropList.
- Requires kernel detach on macOS before USB claim.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
