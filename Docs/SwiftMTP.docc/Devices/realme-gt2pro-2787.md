# Realme Gt2Pro 2787

@Metadata {
    @DisplayName: "Realme Gt2Pro 2787"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Realme Gt2Pro 2787 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22d9 |
| Product ID | 0x2787 |
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
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Realme GT 2 Pro. Realme UI (ColorOS-based) MTP stack.
- Standard Android MTP behavior. Kernel detach required on macOS.
- GetObjectPropList supported.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
