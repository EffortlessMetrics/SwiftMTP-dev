# Microsoft Kin One 071C

@Metadata {
    @DisplayName: "Microsoft Kin One 071C"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Microsoft Kin One 071C MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x045e |
| Product ID | 0x071c |
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
| Maximum Chunk Size | 524 KB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
