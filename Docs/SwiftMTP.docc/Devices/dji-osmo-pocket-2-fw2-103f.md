# Dji Osmo Pocket 2 Fw2 103F

@Metadata {
    @DisplayName: "Dji Osmo Pocket 2 Fw2 103F"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Dji Osmo Pocket 2 Fw2 103F MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2ca3 |
| Product ID | 0x103f |
| Device Info Pattern | `.*DJI.*Osmo.*Pocket.*2.*` |
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

- DJI Osmo Pocket 2 gimbal camera (firmware v2).
- 1/1.7-inch sensor, 64MP.
- USB-C MTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
