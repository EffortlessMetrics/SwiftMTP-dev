# Oneplus 3T F003

@Metadata {
    @DisplayName: "Oneplus 3T F003"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Oneplus 3T F003 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2a70 |
| Product ID | 0xf003 |
| Device Info Pattern | `None` |
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
| Handshake Timeout | 15000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 1000 | ms |

## Notes

- OnePlus 3T (2a70:f003) fails OpenSession without significant stabilization delay.
- Added 1000ms stabilization and post-OpenSession delay.
- Requires resetOnOpen to recover from previous session hangs.
## Provenance

- **Author**: Gemini CLI
- **Date**: 2026-02-06
- **Commit**: Unknown

### Evidence Artifacts
