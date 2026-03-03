# Pocketbook Inkpad 5 A4B5

@Metadata {
    @DisplayName: "Pocketbook Inkpad 5 A4B5"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pocketbook Inkpad 5 A4B5 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0525 |
| Product ID | 0xa4b5 |
| Device Info Pattern | `None` |
| Status | Proposed |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | Unknown |
| Protocol | Unknown |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
