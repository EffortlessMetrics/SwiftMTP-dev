# Quectel Rm500Q 0800

@Metadata {
    @DisplayName: "Quectel Rm500Q 0800"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Quectel Rm500Q 0800 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2c7c |
| Product ID | 0x0800 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | 0xff |
| Protocol | 0x00 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 131 KB | bytes |
| Handshake Timeout | 12000 | ms |
| I/O Timeout | 25000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 500 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
