# Xiaomi Mi Note 2 Ff40

@Metadata {
    @DisplayName: "Xiaomi Mi Note 2 Ff40"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Xiaomi Mi Note 2 Ff40 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x2717 |
| Product ID | 0xff40 |
| Device Info Pattern | `.*Mi Note 2.*` |
| Status | Stable |

## Interface

| Property | Value |
|----------|-------|
| Class | 0xff |
| Subclass | Unknown |
| Protocol | Unknown |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Notes

- Same tuning as ff10 variant with vendor-specific (0xff) MTP interface matching.
- Requires 250-500 ms stabilization after OpenSession.
- Prefer direct USB port; keep screen unlocked.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2025-01-09
- **Commit**: <current-commit>

### Evidence Artifacts
- [Device Probe](probes/mi-note2-probe.txt)
- [100MB Benchmark](Docs/benchmarks/csv/mi-note2-100m.csv)
- [1GB Benchmark](Docs/benchmarks/csv/mi-note2-1g.csv)
