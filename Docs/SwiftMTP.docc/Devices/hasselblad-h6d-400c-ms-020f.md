# Hasselblad H6D 400C Ms 020F

@Metadata {
    @DisplayName: "Hasselblad H6D 400C Ms 020F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Hasselblad H6D 400C Ms 020F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x25b7 |
| Product ID | 0x020f |
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
| I/O Timeout | 60000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 600000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Hasselblad H6D-400c Multi-Shot medium format camera.
- 100MP sensor with 400MP multi-shot capability.
- USB 3.0 PTP for extremely large multi-shot RAW files (~800MB).
- Six-shot capture mode for maximum resolution studio work.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
