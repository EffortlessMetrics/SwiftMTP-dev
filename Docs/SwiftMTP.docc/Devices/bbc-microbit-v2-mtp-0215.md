# Bbc Microbit V2 Mtp 0215

@Metadata {
    @DisplayName: "Bbc Microbit V2 Mtp 0215"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Bbc Microbit V2 Mtp 0215 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0d28 |
| Product ID | 0x0215 |
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
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
