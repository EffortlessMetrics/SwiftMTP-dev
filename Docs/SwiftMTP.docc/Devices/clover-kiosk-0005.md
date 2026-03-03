# Clover Kiosk 0005

@Metadata {
    @DisplayName: "Clover Kiosk 0005"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Clover Kiosk 0005 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2b03 |
| Product ID | 0x0005 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 131 KB | bytes |
| Handshake Timeout | 5000 | ms |
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Clover Kiosk — self-service payment kiosk terminal. USB management.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
