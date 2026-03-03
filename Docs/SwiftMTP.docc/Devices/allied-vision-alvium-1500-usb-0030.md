# Allied Vision Alvium 1500 Usb 0030

@Metadata {
    @DisplayName: "Allied Vision Alvium 1500 Usb 0030"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Allied Vision Alvium 1500 Usb 0030 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1ab2 |
| Product ID | 0x0030 |
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

- Allied Vision Alvium 1500 USB3 compact camera.
- Cost-effective embedded vision module.
- 29x29 mm board-level design.
- Ideal for smart sensor and IoT applications.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-27
- **Commit**: <pending>

### Evidence Artifacts
