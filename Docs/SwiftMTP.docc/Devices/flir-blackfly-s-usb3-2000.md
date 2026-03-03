# Flir Blackfly S Usb3 2000

@Metadata {
    @DisplayName: "Flir Blackfly S Usb3 2000"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Flir Blackfly S Usb3 2000 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1e10 |
| Product ID | 0x2000 |
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

- FLIR Blackfly S USB3 machine vision camera.
- High-performance global shutter CMOS sensor.
- Used in factory automation, robotics, and inspection.
- USB3 Vision with MTP fallback for image retrieval.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
