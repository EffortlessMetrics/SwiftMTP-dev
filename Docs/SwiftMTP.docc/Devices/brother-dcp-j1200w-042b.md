# Brother Dcp J1200W 042B

@Metadata {
    @DisplayName: "Brother Dcp J1200W 042B"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Brother Dcp J1200W 042B MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04f9 |
| Product ID | 0x042b |
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
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 12000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms || Stabilization Delay | 300 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
