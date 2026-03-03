# Dji Air 3 0041

@Metadata {
    @DisplayName: "Dji Air 3 0041"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Dji Air 3 0041 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2ca3 |
| Product ID | 0x0041 |
| Device Info Pattern | `None` |
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
| I/O Timeout | 10000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- DJI Air 3 drone, USB-C MTP mode for media transfer.
- Connect directly to drone (not remote controller) for MTP access.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
