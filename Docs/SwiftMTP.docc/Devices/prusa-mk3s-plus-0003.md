# Prusa Mk3S Plus 0003

@Metadata {
    @DisplayName: "Prusa Mk3S Plus 0003"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Prusa Mk3S Plus 0003 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2c99 |
| Product ID | 0x0003 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
