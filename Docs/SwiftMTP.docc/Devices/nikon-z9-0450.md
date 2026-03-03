# Nikon Z9 0450

@Metadata {
    @DisplayName: "Nikon Z9 0450"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Z9 0450 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0450 |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 10000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 300000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 50 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Notes

- Nikon Z9. Full-frame mirrorless flagship, 45.7 MP with stacked CMOS sensor.
- PTP vendor extension ID: 0x0000000A. Nikon Z-mount professional camera.
- Nikon vendor extensions: GetEvent (0x90C7), DeviceReady (0x90C8), GetEventEx (0x941C).
- GetEventEx (0x941C) supports multi-parameter events, preferred over GetEvent (0x90C7).
- High-speed transfer: GetPartialObjectHiSpeed (0x9400) for fast bulk downloads.
- GetPartialObjectEx (0x9431) with 64-bit offset support for large 8K video files.
- GetObjectsMetaData (0x9434) for batch metadata retrieval.
- 120fps continuous shooting generates rapid ObjectAdded events. Low event pump delay recommended.
- CFexpress Type B only (no SD slot). Single storage ID expected.
## Provenance

- **Author**: Unknown
- **Date**: Unknown
- **Commit**: Unknown

### Evidence Artifacts
