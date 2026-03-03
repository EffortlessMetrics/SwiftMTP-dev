# Blackmagic Studio 4K Plus 0509

@Metadata {
    @DisplayName: "Blackmagic Studio 4K Plus 0509"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Blackmagic Studio 4K Plus 0509 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1edb |
| Product ID | 0x0509 |
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
| Maximum Chunk Size | 8.4 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 45000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Blackmagic Studio Camera 4K Plus — M4/3 studio cam
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
