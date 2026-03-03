# Fujifilm X T4 0321

@Metadata {
    @DisplayName: "Fujifilm X T4 0321"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Fujifilm X T4 0321 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04cb |
| Product ID | 0x0321 |
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
| Maximum Chunk Size | 2.1 MB | bytes |
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

- Fujifilm X-T4 — set USB mode to MTP/PTP.
- Film simulation settings readable via device props.