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
| Status | Experimental |

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
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 20000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 3000 | ms |

## Notes

- ROOT CAUSE: Device is not exposing MTP interfaces to macOS (no IOUSBInterface children in ioreg).
- Symptom: Claim succeeds but bulk writes timeout (sent=0/12, rc=-7).
- This is a Pixel 7 / macOS 26.2 USB stack incompatibility, NOT a SwiftMTP bug.
- Required: Enable Developer Options, USB debugging, and trust the computer on the Pixel.
- Alternative: Try PTP mode (adb usb ptp) instead of MTP.
- Samsung and Xiaomi devices work correctly; Pixel 7 Still Image class is not being exposed.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-12
- **Commit**: Unknown

### Evidence Artifacts
