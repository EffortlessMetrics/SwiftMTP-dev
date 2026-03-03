# Denso At30Q 0103

@Metadata {
    @DisplayName: "Denso At30Q 0103"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Denso At30Q 0103 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1769 |
| Product ID | 0x0103 |
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

- Denso Wave AT30Q — high-speed 2D area imager. IP65. USB interface.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
