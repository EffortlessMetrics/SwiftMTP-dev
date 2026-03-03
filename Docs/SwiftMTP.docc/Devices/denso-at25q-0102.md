# Denso At25Q 0102

@Metadata {
    @DisplayName: "Denso At25Q 0102"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Denso At25Q 0102 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1769 |
| Product ID | 0x0102 |
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

- Denso Wave AT25Q-SM — industrial 2D scanner with laser aimer. USB HID.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
