# Blackmagic Ursa Mini Pro 12K 0006

@Metadata {
    @DisplayName: "Blackmagic Ursa Mini Pro 12K 0006"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Blackmagic Ursa Mini Pro 12K 0006 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1edb |
| Product ID | 0x0006 |
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
| I/O Timeout | 45000 | ms |
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

- Blackmagic URSA Mini Pro 12K cinema camera.
- 12,288 x 6,480 Super 35 sensor.
- USB-C for Blackmagic RAW and ProRes file transfer.
- Extremely large file sizes require generous timeouts.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
