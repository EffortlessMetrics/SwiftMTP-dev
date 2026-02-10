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
| Device Info Pattern | `.*ONEPLUS A3010.*` |
| Status | Stable |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 |
| Subclass | 0x01 |
| Protocol | 0x01 |
## Endpoints

| Property | Value |
|----------|-------|
| Input Endpoint | 0x81 |
| Output Endpoint | 0x01 |
| Event Endpoint | 0x82 |
## Tuning Parameters

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 8000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 120000 | ms |
| Stabilization Delay | 200 | ms |

## Operation Support

| Operation | Supported |
|-----------|-----------|
| 64-bit Partial Object Retrieval | Yes |
| Partial Object Sending | Yes |
| Prefer Object Property List | Yes |
| Write Resume Disabled | No |

## Behavior Limitations

| Operation | Error Code | Description | Workaround |
|-----------|------------|-------------|------------|
| SendObject | 0x201D | Cannot write to storage root (0x00000000). SendObject fails with InvalidParameter when parent handle is 0. | Use first available folder as parent container instead of storage root. |

## Notes

- OnePlus 3T (ONEPLUS A3010) probes in ~115 ms; no resetOnOpen needed with new claim sequence.
- PTP Device Reset (0x66) NOT supported (rc=-9, LIBUSB_ERROR_PIPE); skipPTPReset=true.
- Session opens instantly (0 ms), no retry needed.
- Second USB interface is Mass Storage (class=0x08); ignored by MTP transport.
- Fallback strategies: enum=propList5, read=partial64, write=partial.

## Known Limitations

### Write to Storage Root Fails

The OnePlus 3T does not allow creating files directly in the storage root (handle 0x00000000). This is a device-specific MTP implementation quirk.

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
- **Date**: 2026-02-07
- **Commit**: Unknown

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/oneplus3t-probe.txt)
- [USB Dump](Docs/benchmarks/probes/oneplus3t-usb-dump.txt)
