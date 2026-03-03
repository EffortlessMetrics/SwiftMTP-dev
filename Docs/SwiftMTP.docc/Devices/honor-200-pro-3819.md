# Honor 200 Pro 3819

@Metadata {
    @DisplayName: "Honor 200 Pro 3819"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Honor 200 Pro 3819 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x12d1 |
| Product ID | 0x3819 |
| Device Info Pattern | `None` |
| Status | Proposed |

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
| Handshake Timeout | 15000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
