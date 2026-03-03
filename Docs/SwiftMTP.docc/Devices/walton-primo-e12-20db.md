# Walton Primo E12 20Db

@Metadata {
    @DisplayName: "Walton Primo E12 20Db"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Walton Primo E12 20Db MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e8d |
| Product ID | 0x20db |
| Device Info Pattern | `None` |
| Status | Experimental |

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
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |
