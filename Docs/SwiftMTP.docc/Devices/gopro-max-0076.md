# Gopro Max 0076

@Metadata {
    @DisplayName: "Gopro Max 0076"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Gopro Max 0076 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2672 |
| Product ID | 0x0076 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- GoPro MAX — connect via USB-C, MTP mode auto-enabled.
- Large video files; extended timeouts recommended.