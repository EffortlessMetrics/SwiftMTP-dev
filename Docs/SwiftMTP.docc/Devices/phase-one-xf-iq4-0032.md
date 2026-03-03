# Phase One Xf Iq4 0032

@Metadata {
    @DisplayName: "Phase One Xf Iq4 0032"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phase One Xf Iq4 0032 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1b1e |
| Product ID | 0x0032 |
| Device Info Pattern | `.*Phase.*One.*XF.*` |
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

- Phase One XF camera system.
- Modular body with IQ4 digital back.
- USB-C PTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
