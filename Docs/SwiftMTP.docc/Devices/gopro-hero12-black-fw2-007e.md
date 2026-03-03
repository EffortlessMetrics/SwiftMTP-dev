# Gopro Hero12 Black Fw2 007E

@Metadata {
    @DisplayName: "Gopro Hero12 Black Fw2 007E"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Gopro Hero12 Black Fw2 007E MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2672 |
| Product ID | 0x007e |
| Device Info Pattern | `.*GoPro.*HERO12.*` |
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

- GoPro HERO12 Black (firmware v2).
- 27MP with HDR video and HyperSmooth 6.
- USB-C PTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
