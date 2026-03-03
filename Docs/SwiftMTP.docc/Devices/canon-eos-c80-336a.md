# Canon Eos C80 336A

@Metadata {
    @DisplayName: "Canon Eos C80 336A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos C80 336A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x336a |
| Device Info Pattern | `.*Canon.*EOS C80.*` |
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

- Canon EOS C80 cinema camera.
- RF mount with 6K Super 35 sensor.
- USB-C for offloading CFexpress media.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
