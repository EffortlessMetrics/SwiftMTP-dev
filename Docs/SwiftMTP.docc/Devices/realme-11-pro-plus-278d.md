# Realme 11 Pro Plus 278D

@Metadata {
    @DisplayName: "Realme 11 Pro Plus 278D"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Realme 11 Pro Plus 278D MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22d9 |
| Product ID | 0x278d |
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
| Maximum Chunk Size | 2.1 MB | bytes |
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

- Realme 11 Pro+. Realme UI (ColorOS-based) MTP stack.
- Mid-range MediaTek Dimensity chipset. Standard Android MTP.
- Kernel detach required on macOS.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
