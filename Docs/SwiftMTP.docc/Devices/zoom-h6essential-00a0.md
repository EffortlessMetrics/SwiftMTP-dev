# Zoom H6Essential 00A0

@Metadata {
    @DisplayName: "Zoom H6Essential 00A0"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Zoom H6Essential 00A0 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1686 |
| Product ID | 0x00a0 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
