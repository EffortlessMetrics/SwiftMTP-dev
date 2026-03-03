# Lumenera Lt Usb3 0010

@Metadata {
    @DisplayName: "Lumenera Lt Usb3 0010"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Lumenera Lt Usb3 0010 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x7468 |
| Product ID | 0x0010 |
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

- Lumenera Lt series USB3 industrial camera.
- 9.1 MP Sony Pregius sensor.
- Compact metal housing for machine vision.
- Used in traffic monitoring and inspection.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
