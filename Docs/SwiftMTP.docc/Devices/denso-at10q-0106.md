# Denso At10Q 0106

@Metadata {
    @DisplayName: "Denso At10Q 0106"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Denso At10Q 0106 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1769 |
| Product ID | 0x0106 |
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

- Denso Wave AT10Q — entry-level 2D handheld scanner. USB cable.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
