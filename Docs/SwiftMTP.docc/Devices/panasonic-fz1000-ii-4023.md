# Panasonic Fz1000 Ii 4023

@Metadata {
    @DisplayName: "Panasonic Fz1000 Ii 4023"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Panasonic Fz1000 Ii 4023 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04da |
| Product ID | 0x4023 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | Yes |

## Notes

- Panasonic Lumix FZ1000 II — PC connection mode (USB) required.
- V-Log data accessible via MTP device properties.