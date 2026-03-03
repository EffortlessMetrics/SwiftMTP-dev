# Limesdr Usb 6108

@Metadata {
    @DisplayName: "Limesdr Usb 6108"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Limesdr Usb 6108 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1d50 |
| Product ID | 0x6108 |
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
| Maximum Chunk Size | 262 KB | bytes |
| Handshake Timeout | 5000 | ms |
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
