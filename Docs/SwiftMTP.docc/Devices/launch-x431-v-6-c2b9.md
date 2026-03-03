# Launch X431 V 6 C2B9

@Metadata {
    @DisplayName: "Launch X431 V 6 C2B9"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Launch X431 V 6 C2B9 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0bda |
| Product ID | 0xc2b9 |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Launch X431 V+ 6
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
