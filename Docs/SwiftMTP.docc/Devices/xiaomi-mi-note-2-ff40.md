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
| Overall Deadline | 120000 | ms |
| Stabilization Delay | 400 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|
| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | No |
| Write Resume Disabled | No |

## Behavior Limitations

| Operation | Error Code | Description | Workaround |
|-----------|------------|-------------|------------|
| SendObject | 0x201D | Cannot write to storage root (0x00000000). SendObject fails with InvalidParameter when parent handle is 0. | Use first available folder as parent container instead of storage root. |

## Notes

- Same tuning as ff10 variant with vendor-specific (0xff) MTP interface matching.
- Requires 250-500 ms stabilization after OpenSession.
- Prefer direct USB port; keep screen unlocked.

## Known Limitations

### Write to Storage Root Fails

The Xiaomi Mi Note 2 does not allow creating files directly in the storage root (handle 0x00000000). This is a device-specific MTP implementation quirk that affects both the ff10 and ff40 variants.

**Symptoms:**
- SendObject operation fails with error code 0x201D (InvalidParameter)
- Error message: "Cannot write to storage root"

**Solution:**
SwiftMTP automatically handles this by:
1. Detecting the 0x201D error code
2. Falling back to use the first available folder (usually "Internal storage" or similar) as the parent container
3. Retrying the write operation

Users do not need to take manual action; this is handled transparently.

## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2025-01-09
- **Commit**: <current-commit>

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/mi-note2-probe.txt)
- [USB Dump](Docs/benchmarks/probes/mi-note2-usb-dump.txt)
- [100MB Benchmark](Docs/benchmarks/csv/mi-note2-100m.csv)
- [1GB Benchmark](Docs/benchmarks/csv/mi-note2-1g.csv)
- [Mirror Log](Docs/benchmarks/logs/mi-note2-mirror.log)
