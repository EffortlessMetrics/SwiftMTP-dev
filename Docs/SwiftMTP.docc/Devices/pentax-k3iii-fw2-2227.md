# Pentax K3Iii Fw2 2227

@Metadata {
    @DisplayName: "Pentax K3Iii Fw2 2227"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Pentax K3Iii Fw2 2227 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x05ca |
| Product ID | 0x2227 |
| Device Info Pattern | `.*Pentax.*K-3.*III.*` |
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

- Pentax K-3 Mark III APS-C DSLR (firmware v2).
- 25.7MP with optical viewfinder.
- SD dual slots, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
