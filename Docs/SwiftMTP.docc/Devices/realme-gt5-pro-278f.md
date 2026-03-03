# Realme Gt5 Pro 278F

@Metadata {
    @DisplayName: "Realme Gt5 Pro 278F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Realme Gt5 Pro 278F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22d9 |
| Product ID | 0x278f |
| Device Info Pattern | `None` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0xff |
| Protocol | 0x00 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Realme GT 5 Pro flagship. Realme UI (ColorOS-based) MTP stack.
- Snapdragon 8 Gen 3. High-performance USB transfers expected.
- Standard Android MTP behavior. Kernel detach required on macOS.
- GetObjectPropList supported on Android 14+.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
