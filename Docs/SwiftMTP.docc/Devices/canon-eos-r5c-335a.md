# Canon Eos R5C 335A

@Metadata {
    @DisplayName: "Canon Eos R5C 335A"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Canon Eos R5C 335A MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04a9 |
| Product ID | 0x335a |
| Device Info Pattern | `.*Canon.*EOS R5 C.*` |
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

- Canon EOS R5 C hybrid cinema/photo camera.
- 8K RAW video requires extended timeouts.
- PTP mode must be selected in camera menu.
- Dual CFexpress/SD card slots.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
