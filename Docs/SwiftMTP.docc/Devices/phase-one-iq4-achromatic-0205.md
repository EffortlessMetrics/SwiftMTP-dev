# Phase One Iq4 Achromatic 0205

@Metadata {
    @DisplayName: "Phase One Iq4 Achromatic 0205"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phase One Iq4 Achromatic 0205 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1b1e |
| Product ID | 0x0205 |
| Device Info Pattern | `None` |
| Status | Experimental |

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
| I/O Timeout | 60000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 600000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Phase One IQ4 150MP Achromatic digital back.
- 150MP medium format monochrome sensor (53.4x40mm).
- USB-C PTP for extremely large IIQ RAW files (~300MB).
- Black-and-white only sensor for maximum detail and tonal range.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
