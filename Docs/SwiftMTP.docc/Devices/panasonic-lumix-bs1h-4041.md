# Panasonic Lumix Bs1H 4041

@Metadata {
    @DisplayName: "Panasonic Lumix Bs1H 4041"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Panasonic Lumix Bs1H 4041 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04da |
| Product ID | 0x4041 |
| Device Info Pattern | `.*Panasonic.*BS1H.*` |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Panasonic Lumix BS1H box-style cinema camera.
- 24.2MP full-frame, V-Log/V-Gamut.
- SD + HDMI, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
