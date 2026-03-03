# Nikon Coolpix Coolpix Aw130 0198

@Metadata {
    @DisplayName: "Nikon Coolpix Coolpix Aw130 0198"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Coolpix Coolpix Aw130 0198 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0198 |
| Device Info Pattern | `.*Nikon.*` |
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
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 20000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 200 | ms |
| Event Pump Delay | 100 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Nikon Coolpix AW130 — compact/bridge camera using PTP over USB.
- Camera must be set to MTP/PTP transfer mode before connecting.
- JPEG and NRW raw files supported; use ioTimeoutMs extension for large files.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-17
- **Commit**: <pending>

### Evidence Artifacts
