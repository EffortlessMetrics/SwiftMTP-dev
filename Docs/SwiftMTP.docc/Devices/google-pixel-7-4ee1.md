# Google Pixel 7 (4ee1)

@Metadata {
    @DisplayName: "Google Pixel 7 (4ee1)"
    @PageKind: article
    @Available: iOS 15.0, macOS 12.0
}

Device-specific configuration for Google Pixel 7 MTP implementation.

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x18d1 |
| Product ID | 0x4ee1 |
| Quirk ID | `google-pixel-7-4ee1` |
| Status | Experimental |
| Confidence | Low |

## Interface

| Property | Value |
|----------|-------|
| Class | 0x06 (Still Image / PTP) |
| Subclass | 0x01 |
| Protocol | 0x01 |
| Endpoint In | 0x81 |
| Endpoint Out | 0x01 |
| Endpoint Event | 0x82 |

## Current Issue: macOS Tahoe 26 Bulk Transfer Timeout

The Pixel 7 is currently **non-functional** on macOS Tahoe 26 due to bulk endpoint unresponsiveness.

### What works

- `set_configuration` succeeds
- `claim_interface` succeeds
- `set_alt_setting` succeeds
- Device is detected and control plane is operational

### What fails

- **Bulk write times out** with `rc=-7` (LIBUSB_ERROR_TIMEOUT), `sent=0/12`
- Pass 2 with USB reset also fails
- `GetDeviceStatus` returns `0x0008` consistently after reset

### Implications

- No MTP session can be established (OpenSession requires a bulk write)
- Read, write, enumeration, and all MTP operations are blocked
- May work on other macOS versions or with different USB host controllers

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

- Disabled resetOnOpen as it causes re-enumeration and may revert to 'Charging only' mode.
- Stabilization delay set to 2000ms.
- All benchmark data previously listed was **mock data** and has been removed pending real device validation.
- The bulk transfer timeout issue may be specific to macOS Tahoe 26 and Apple Silicon USB host controllers.

## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-08
- **Commit**: HEAD

### Evidence Artifacts

- `Docs/benchmarks/probes/pixel7-probe-debug.txt` -- Debug probe output showing bulk transfer timeout
