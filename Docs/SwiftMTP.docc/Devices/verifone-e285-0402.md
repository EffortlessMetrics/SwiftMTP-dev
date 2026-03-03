# Verifone E285 0402

@Metadata {
    @DisplayName: "Verifone E285 0402"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Verifone E285 0402 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x11ca |
| Product ID | 0x0402 |
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

- Verifone e285 — mobile mPOS reader. Bluetooth + USB. EMV + contactless.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
