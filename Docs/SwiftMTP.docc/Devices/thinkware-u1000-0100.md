# Thinkware U1000 0100

@Metadata {
    @DisplayName: "Thinkware U1000 0100"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Thinkware U1000 0100 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1eac |
| Product ID | 0x0100 |
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
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
