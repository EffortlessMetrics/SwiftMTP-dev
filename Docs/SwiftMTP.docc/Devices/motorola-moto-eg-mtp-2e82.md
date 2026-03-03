# Motorola Moto Eg Mtp 2E82

@Metadata {
    @DisplayName: "Motorola Moto Eg Mtp 2E82"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Motorola Moto Eg Mtp 2E82 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22b8 |
| Product ID | 0x2e82 |
| Device Info Pattern | `None` |
| Status | Verified |

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
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Motorola Moto E/G series MTP mode. Standard Android MTP stack.
- Used by Moto G Power, Moto G Stylus, Moto G Play, Moto E series, and Edge series.
- GetObjectPropList supported and preferred for enumeration.
- Motorola devices use near-stock Android; MTP behavior is predictable and reliable.
- Kernel detach required on macOS for USB interface claim.