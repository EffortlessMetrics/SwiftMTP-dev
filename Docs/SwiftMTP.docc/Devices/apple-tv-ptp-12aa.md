# Apple Tv Ptp 12Aa

@Metadata {
    @DisplayName: "Apple Tv Ptp 12Aa"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Apple Tv Ptp 12Aa MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05ac |
| Product ID | 0x12aa |
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
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | default | ms |
| Overall Deadline | default | ms |
## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- iOS camera-roll PTP — photo import only, limited to DCIM; full MTP not supported by iOS
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
