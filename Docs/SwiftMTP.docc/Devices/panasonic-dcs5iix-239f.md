# Panasonic Dcs5Iix 239F

@Metadata {
    @DisplayName: "Panasonic Dcs5Iix 239F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Panasonic Dcs5Iix 239F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04da |
| Product ID | 0x239f |
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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
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

- Panasonic Lumix DC-S5IIX full-frame video-centric mirrorless.
- Enhanced video features over S5II (ProRes RAW, SSD recording).
- PTP mode same as S5II for still image transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
