# Verifone P200 0D00

@Metadata {
    @DisplayName: "Verifone P200 0D00"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Verifone P200 0D00 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x11ca |
| Product ID | 0x0d00 |
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

- Verifone P200 — PIN pad with color touchscreen. USB interface.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
