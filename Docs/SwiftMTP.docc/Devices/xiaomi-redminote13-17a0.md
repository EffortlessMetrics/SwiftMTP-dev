# Xiaomi Redminote13 17A0

@Metadata {
    @DisplayName: "Xiaomi Redminote13 17A0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xiaomi Redminote13 17A0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2717 |
| Product ID | 0x17a0 |
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

- Xiaomi Redmi Note 13. Popular mid-range phone with MIUI/HyperOS MTP stack.
- Xiaomi/HyperOS MTP stack (Android-based). Kernel detach required on macOS.
- Standard Android MTP behavior. Budget device may have slower USB 2.0 transfers.
- 2MB chunk size recommended for this tier of device.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
