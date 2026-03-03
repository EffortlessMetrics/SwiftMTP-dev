# Nikon Z6 Iii 0454

@Metadata {
    @DisplayName: "Nikon Z6 Iii 0454"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Nikon Z6 Iii 0454 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x04b0 |
| Product ID | 0x0454 |
| Device Info Pattern | `.*Nikon.*` |
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
| Maximum Chunk Size | 4.2 MB | bytes |
| Handshake Timeout | 8000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 15000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 300 | ms |
| Event Pump Delay | 100 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | No |
| Partial Object Sending | No |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Notes

- Nikon Z6-III uses PTP over USB.
- Camera must be in MTP/PTP mode via Settings > USB Options.
- NEF raw files are large (15-50 MB); extend ioTimeoutMs if needed.
- Liveview and capture events require Nikon vendor extensions (0x9xxx).
- 24.5 MP partially-stacked BSI CMOS, 3rd gen Z6.
## Provenance

- **Author**: SwiftMTP Contributors
- **Date**: 2026-03-01
- **Commit**: <pending>

### Evidence Artifacts
