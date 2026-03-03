# Garmin Colorado 300 2295

@Metadata {
    @DisplayName: "Garmin Colorado 300 2295"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Colorado 300 2295 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x2295 |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | default | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
