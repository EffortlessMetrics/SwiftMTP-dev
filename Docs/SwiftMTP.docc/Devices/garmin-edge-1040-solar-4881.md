# Garmin Edge 1040 Solar 4881

@Metadata {
    @DisplayName: "Garmin Edge 1040 Solar 4881"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Garmin Edge 1040 Solar 4881 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x091e |
| Product ID | 0x4881 |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |
