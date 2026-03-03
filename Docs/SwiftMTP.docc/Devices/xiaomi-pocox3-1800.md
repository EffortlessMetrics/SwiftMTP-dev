# Xiaomi Pocox3 1800

@Metadata {
    @DisplayName: "Xiaomi Pocox3 1800"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xiaomi Pocox3 1800 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2717 |
| Product ID | 0x1800 |
| Device Info Pattern | `None` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- POCO X3 NFC. Popular mid-range gaming phone. MIUI/POCO Launcher MTP stack.
- Xiaomi/HyperOS MTP stack (Android-based). Kernel detach required on macOS.
- Standard Android MTP. Snapdragon 732G with USB 2.0.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
