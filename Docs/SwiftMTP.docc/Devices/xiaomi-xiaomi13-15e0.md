# Xiaomi Xiaomi13 15E0

@Metadata {
    @DisplayName: "Xiaomi Xiaomi13 15E0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xiaomi Xiaomi13 15E0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2717 |
| Product ID | 0x15e0 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Xiaomi 13 flagship phone. MIUI/HyperOS MTP stack.
- Xiaomi/HyperOS MTP stack (Android-based). Kernel detach required on macOS.
- Android MTP extensions supported. GetObjectPropList supported on MIUI 14+.
- 400ms post-session stabilization recommended.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
