# Thorlabs Zelux Cmos 0300

@Metadata {
    @DisplayName: "Thorlabs Zelux Cmos 0300"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Thorlabs Zelux Cmos 0300 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1313 |
| Product ID | 0x0300 |
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

- Thorlabs Zelux 1.6 MP compact CMOS camera.
- USB3 interface with global shutter.
- Cost-effective solution for lab imaging.
- Small form factor for constrained setups.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
