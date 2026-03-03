# Phase One Xt R 0207

@Metadata {
    @DisplayName: "Phase One Xt R 0207"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phase One Xt R 0207 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1b1e |
| Product ID | 0x0207 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 240000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Phase One XT-R rocker-body camera system.
- Modular technical camera for IQ4 digital backs.
- USB-C PTP inherited from attached digital back.
- Ultra-compact body for Rodenstock lenses and tilt/shift.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
