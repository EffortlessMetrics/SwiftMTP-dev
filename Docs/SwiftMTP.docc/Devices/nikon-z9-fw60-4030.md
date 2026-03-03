# Nikon Z9 Fw60 4030

@Metadata {
    @DisplayName: "Nikon Z9 Fw60 4030"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Z9 Fw60 4030 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x4030 |
| Device Info Pattern | `.*Nikon.*Z ?9.*` |
| Status | Experimental |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon Z9 firmware v6.0 update.
- New pre-release capture and bird detection.
- CFexpress Type B media.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
