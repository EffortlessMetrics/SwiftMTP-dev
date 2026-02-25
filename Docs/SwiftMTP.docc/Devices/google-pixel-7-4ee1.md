# Google Pixel 7 4Ee1

@Metadata {
    @DisplayName("Google Pixel 7")
    @PageKind(article)
}

Current bring-up status for Google Pixel 7 (`VID:PID 18d1:4ee1`).

## Identity

| Property | Value |
|----------|-------|
| Vendor ID | 0x18d1 |
| Product ID | 0x4ee1 |
| Device Info Pattern | `None` |

|---|---|
| Vendor ID | `0x18d1` |
| Product ID | `0x4ee1` |
| Interface | class `0x06`, subclass `0x01`, protocol `0x01` |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `google-pixel-7-4ee1` |
| Status | Experimental |

## Evidence

- `Docs/benchmarks/connected-lab/20260216-015505`
- `Docs/benchmarks/connected-lab/20260212-053429`
- Targeted debug probe on 2026-02-16 (`SWIFTMTP_DEBUG=1 ... probe --vid 18d1 --pid 4ee1`)

## Modes x Operations

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 20000 | ms |
| I/O Timeout | 30000 | ms |
| Inactivity Timeout | 10000 | ms |
| Overall Deadline | 180000 | ms || Stabilization Delay | 3000 | ms |

## Troubleshooting

### Bulk OUT timeout (sent=0, rc=-7) — the most common failure

This is the primary failure mode on macOS 26. The symptom is that SwiftMTP claims the
USB interface successfully but the first bulk write immediately times out with zero bytes sent.

**Step-by-step recovery:**

1. **Set USB mode to File Transfer.** On the phone: Settings → Connected devices →
   USB → File Transfer (MTP). "Charging only" and "Photo Transfer (PTP)" both block MTP bulk access.

2. **Enable Developer Options + USB Debugging.**
   Settings → About phone → tap "Build number" 7 times → Developer options →
   USB debugging → On. Without this, macOS 26 does not register the MTP IOUSBInterface.

3. **Approve the computer trust prompt.** Reconnect the cable and tap "Allow" on
   "Allow USB debugging?" when the dialog appears. If the dialog does not appear, revoke
   existing authorizations: Developer options → Revoke USB debugging authorizations.

4. **Unplug and replug** the USB cable to force re-enumeration. Then re-run
   `swift run --package-path SwiftMTPKit swiftmtp probe`.

5. **Verify ioreg sees the MTP interface:**
   ```
   ioreg -p IOUSB -l | grep -A5 "Pixel 7"
   ```
   Look for `IOUSBInterface` children under the Pixel 7 node.
   If absent, the macOS USB stack has not enumerated the MTP interface (Pixel 7 / macOS 26.2 known issue).

6. **Try PTP mode** as a workaround if MTP remains blocked:
   `adb shell svc usb setFunction ptp` or Settings → USB → Photo Transfer.

### Identifying macOS 26.2 vs. device configuration issue

If you see `bulk OUT timeout` but ioreg *does* show `IOUSBInterface` children, the device is
correctly enumerated and the failure is transient. Run with `SWIFTMTP_DEBUG=1` and submit
the debug log as a device submission.

If ioreg shows **no** `IOUSBInterface` children after following all steps above, this is a
confirmed macOS 26 / Pixel 7 USB kernel extension incompatibility outside SwiftMTP's control.

## Notes

- ROOT CAUSE: Device is not exposing MTP interfaces to macOS (no IOUSBInterface children in ioreg).
- Symptom: Claim succeeds but bulk writes timeout (sent=0/12, rc=-7).
- This is a Pixel 7 / macOS 26.2 USB stack incompatibility, NOT a SwiftMTP bug.
- Required: Enable Developer Options, USB debugging, and trust the computer on the Pixel.
- Alternative: Try PTP mode (adb usb ptp) instead of MTP.
- Samsung and Xiaomi devices work correctly; Pixel 7 Still Image class is not being exposed.
- **Error message**: SwiftMTP now emits an actionable error with the steps above when this condition is detected.
## Provenance

- **Author**: Steven Zimmerman
- **Date**: 2026-02-12
- **Commit**: Unknown

### Evidence Artifacts

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (handshake blocked) | `20260216-015505` | Fail (claimed, then bulk OUT timeout `sent=0 rc=-7`) | N/A | N/A | Skipped | Skipped | Skipped | `class3-handshake` |
| MTP (handshake blocked) | `20260212-053429` | Fail | N/A | N/A | Skipped | Skipped | Skipped | `blocked` |
| MTP (storage exposed) | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Transport Notes

- Reset + teardown + fresh reopen rung is now executed on first open-session I/O failure.
- For this device, the second pass still fails in the same way: OUT endpoint accepts claim but rejects first command write.
- This is now reported as a handshake failure, not an interface-discovery failure.

## Next Validation Steps

1. Unlock phone, set USB mode to File Transfer, approve access, unplug/replug.
2. Re-run `swift run --package-path SwiftMTPKit swiftmtp device-lab connected --json`.
3. If still blocked, capture a side-by-side libusb trace (`mtp-detect` vs `swiftmtp probe`) for this device state.
