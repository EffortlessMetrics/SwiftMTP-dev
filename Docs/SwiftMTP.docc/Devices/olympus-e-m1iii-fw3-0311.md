# Olympus E M1Iii Fw3 0311

@Metadata {
    @DisplayName: "Olympus E M1Iii Fw3 0311"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Olympus E M1Iii Fw3 0311 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x07b4 |
| Product ID | 0x0311 |
| Device Info Pattern | `.*Olympus.*E-M1.*III.*` |
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

- Olympus OM-D E-M1 Mark III (firmware v3).
- 20.4MP with handheld high-res mode.
- Dual SD UHS-II, USB-C.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2025-07-13
- **Commit**: <pending>

### Evidence Artifacts
