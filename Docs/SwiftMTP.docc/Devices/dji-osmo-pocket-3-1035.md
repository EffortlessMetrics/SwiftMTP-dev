# Dji Osmo Pocket 3 1035

@Metadata {
    @DisplayName: "Dji Osmo Pocket 3 1035"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Dji Osmo Pocket 3 1035 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2ca3 |
| Product ID | 0x1035 |
| Device Info Pattern | `.*DJI.*Osmo.*Pocket.*3.*` |
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
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- DJI Osmo Pocket 3 gimbal camera.
- 1-inch CMOS sensor, 4K 120fps.
- USB-C MTP for media transfer.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
