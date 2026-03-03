# Panasonic Lumix G9Ii 4035

@Metadata {
    @DisplayName: "Panasonic Lumix G9Ii 4035"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Panasonic Lumix G9Ii 4035 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04da |
| Product ID | 0x4035 |
| Device Info Pattern | `.*Panasonic.*G9.*II.*` |
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

- Panasonic Lumix G9 II Micro Four Thirds.
- 25.2MP with phase-detect AF.
- SD dual slots, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
