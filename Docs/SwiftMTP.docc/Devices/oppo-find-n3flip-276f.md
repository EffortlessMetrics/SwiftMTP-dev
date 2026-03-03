# Oppo Find N3Flip 276F

@Metadata {
    @DisplayName: "Oppo Find N3Flip 276F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Oppo Find N3Flip 276F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x22d9 |
| Product ID | 0x276f |
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
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- OPPO Find N3 Flip foldable. ColorOS MTP stack.
- Standard Android MTP behavior. Kernel detach required on macOS.
- Foldable form factor; no special MTP considerations.