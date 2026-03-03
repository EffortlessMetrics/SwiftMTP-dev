# Hasselblad H6D 100C 020E

@Metadata {
    @DisplayName: "Hasselblad H6D 100C 020E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad H6D 100C 020E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x25b7 |
| Product ID | 0x020e |
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

- Hasselblad H6D-100c medium format camera.
- 100MP medium format CMOS sensor (53.4x40mm).
- USB 3.0 PTP for large Hasselblad 3FR RAW transfer (~200MB).
- H-system modular body with interchangeable digital backs.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
