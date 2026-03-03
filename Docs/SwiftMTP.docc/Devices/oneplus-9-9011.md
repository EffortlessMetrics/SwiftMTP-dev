# Oneplus 9 9011

@Metadata {
    @DisplayName: "Oneplus 9 9011"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Oneplus 9 9011 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2a70 |
| Product ID | 0x9011 |
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

- OnePlus 9 MTP mode. Uses OxygenOS/ColorOS MTP stack (Android-based).
- GetObjectPropList supported; proplist enumeration preferred.
- OnePlus devices may need writeToSubfolderOnly if root storage writes return InvalidParameter.
- Standard Android MTP behavior; kernel detach required on macOS.