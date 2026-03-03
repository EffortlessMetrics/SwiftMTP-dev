# Mediatek Qin F21 Pro 2026

@Metadata {
    @DisplayName: "Mediatek Qin F21 Pro 2026"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Mediatek Qin F21 Pro 2026 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e8d |
| Product ID | 0x2026 |
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

- libmtp: Qin F21 Pro (DEVICE_FLAGS_ANDROID_BUGS).
- Standard Android MTP stack with broken GetObjPropList.
- Requires kernel detach on macOS before USB claim.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
