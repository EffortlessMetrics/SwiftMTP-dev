# Thorlabs Kiralux Cmos 0400

@Metadata {
    @DisplayName: "Thorlabs Kiralux Cmos 0400"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Thorlabs Kiralux Cmos 0400 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1313 |
| Product ID | 0x0400 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Thorlabs Kiralux 5 MP scientific CMOS camera.
- USB3 with Sony Pregius sensor.
- Low read noise for quantitative imaging.
- Supports ROI and binning for high FPS.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
