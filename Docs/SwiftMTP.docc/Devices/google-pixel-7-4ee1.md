# Google Pixel 7 4Ee1

@Metadata {
    @DisplayName: "Google Pixel 7 4Ee1"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Google Pixel 7 4Ee1 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x18d1 |
| Product ID | 0x4ee1 |
| Device Info Pattern | `None` |
| Status | Stable |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |

## Tuning Parameters

> **Note**: These tuning values are sourced from `Specs/quirks.json` (quirk ID: `google-pixel-7-4ee1`).

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 20000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 180000 | ms |
| Stabilization Delay | 2000 | ms |

## Notes

- Google Pixel 7 (18d1:4ee1) general Android MTP stack.
- Disabled resetOnOpen as it causes re-enumeration and may revert to 'Charging only' mode.
- Increased stabilization delay to 2000ms.

> **⚠️ Benchmark Data Status**: The benchmark data in `Docs/benchmarks/pixel7/` is currently **MOCK data**. It was generated for testing purposes and has not been validated against a real Google Pixel 7 device. Real device benchmarks are needed for accurate performance characterization.

## Provenance

- **Author**: Gemini CLI
- **Date**: 2026-02-06
- **Commit**: Unknown

### Evidence Artifacts

- [Benchmarks Directory](Docs/benchmarks/pixel7/) - **Note: Contains mock data, needs real device validation**
