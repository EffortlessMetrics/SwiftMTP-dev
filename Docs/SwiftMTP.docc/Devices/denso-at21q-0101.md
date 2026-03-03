# Denso At21Q 0101

@Metadata {
    @DisplayName: "Denso At21Q 0101"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Denso At21Q 0101 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1769 |
| Product ID | 0x0101 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 131 KB | bytes |
| Handshake Timeout | 4000 | ms |
| I/O Timeout | 8000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Denso Wave AT21Q-SM — handheld 2D scanner. QR code inventor's brand. USB.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
