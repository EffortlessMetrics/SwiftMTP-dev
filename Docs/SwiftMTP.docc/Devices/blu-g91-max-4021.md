# Blu G91 Max 4021

@Metadata {
    @DisplayName: "Blu G91 Max 4021"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Blu G91 Max 4021 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x271d |
| Product ID | 0x4021 |
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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 15000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
