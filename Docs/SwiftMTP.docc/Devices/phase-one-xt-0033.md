# Phase One Xt 0033

@Metadata {
    @DisplayName: "Phase One Xt 0033"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phase One Xt 0033 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1b1e |
| Product ID | 0x0033 |
| Device Info Pattern | `.*Phase.*One.*XT.*` |
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

- Phase One XT field camera system.
- Technical camera with Rodenstock lenses.
- USB-C PTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
