# Insta360 Ace Pro 2 002A

@Metadata {
    @DisplayName: "Insta360 Ace Pro 2 002A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Insta360 Ace Pro 2 002A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2e1a |
| Product ID | 0x002a |
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
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Insta360 Ace Pro 2 — USB-C MTP mode.
- 360 video files are large; use extended timeouts.