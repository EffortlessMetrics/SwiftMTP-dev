# Mamiya Leaf Credo 80 4004

@Metadata {
    @DisplayName: "Mamiya Leaf Credo 80 4004"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Mamiya Leaf Credo 80 4004 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x0e70 |
| Product ID | 0x4004 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
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

- Mamiya Leaf Credo 80 digital back, 80MP CCD sensor.
- Uses PTP for tethered shooting and image transfer.
- Produces very large RAW files (~160MB).
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-15
- **Commit**: <pending>

### Evidence Artifacts
