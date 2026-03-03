# Phase One Iq2 80Mp 0102

@Metadata {
    @DisplayName: "Phase One Iq2 80Mp 0102"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Phase One Iq2 80Mp 0102 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1b1e |
| Product ID | 0x0102 |
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

- Phase One IQ2 80MP digital back.
- 80MP medium format CCD sensor (53.7x40.4mm).
- USB 3.0 PTP for large IIQ RAW file transfer.
- Second-generation IQ digital back platform.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
