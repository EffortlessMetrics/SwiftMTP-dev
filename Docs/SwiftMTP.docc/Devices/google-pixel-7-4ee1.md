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

- Bulk transfers time out (write rc=-7, LIBUSB_ERROR_TIMEOUT) on macOS when Chrome holds device.
- Use requiresKernelDetach=true to attempt releasing from Chrome/WebUSB.
- libmtp-aligned claim (set_configuration + set_alt_setting) reinitializes pipes without USB reset.
- Fallback USB reset uses stabilizeMs=3000 as poll budget for waitForMTPReady.
- If kernel detach fails, user must manually quit Chrome and replug device.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-07
- **Commit**: Unknown

### Evidence Artifacts
- [Device Probe](Docs/benchmarks/probes/pixel7-probe.txt)
- [USB Dump](Docs/benchmarks/probes/pixel7-usb-dump.txt)
