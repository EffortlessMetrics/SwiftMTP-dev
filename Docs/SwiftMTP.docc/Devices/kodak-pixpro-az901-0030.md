# Kodak Pixpro Az901 0030

@Metadata {
    @DisplayName: "Kodak Pixpro Az901 0030"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Kodak Pixpro Az901 0030 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x040a |
| Product ID | 0x0030 |
| Device Info Pattern | `.*Kodak.*PIXPRO.*AZ901.*` |
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

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Kodak PIXPRO AZ901 superzoom.
- 20MP, 90x optical zoom.
- USB micro-B PTP.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
