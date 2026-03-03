# Tomtom Go 520 7474

@Metadata {
    @DisplayName: "Tomtom Go 520 7474"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Tomtom Go 520 7474 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x1390 |
| Product ID | 0x7474 |
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
| Maximum Chunk Size | 524 KB | bytes |
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
