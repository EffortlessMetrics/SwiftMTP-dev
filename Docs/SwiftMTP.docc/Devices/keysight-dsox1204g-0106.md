# Keysight Dsox1204G 0106

@Metadata {
    @DisplayName: "Keysight Dsox1204G 0106"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Keysight Dsox1204G 0106 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2a8d |
| Product ID | 0x0106 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0x00 |
| Protocol | 0x00 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
