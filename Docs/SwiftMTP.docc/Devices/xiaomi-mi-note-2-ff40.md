# Xiaomi Mi Note 2 Ff40

@Metadata {
    @DisplayName("Xiaomi Mi Note 2")
    @PageKind(article)
}

Current bring-up status for Xiaomi Mi Note 2 (`VID:PID 2717:ff40`).

## Identity

| Property | Value |
|---|---|
| Vendor ID | `0x2717` |
| Product ID | `0xff40` |
| Interface | class `0xff`, subclass `0xff`, protocol `0x00` |
| Endpoints | IN `0x81`, OUT `0x01`, EVT `0x82` |
| Quirk Profile | `xiaomi-mi-note-2-ff40` |
| Status | Stable profile, validation in progress |

## Evidence

- `Docs/benchmarks/connected-lab/20260216-015505`
- `Docs/benchmarks/connected-lab/20260212-053429`
- Targeted debug probe on 2026-02-16 (`SWIFTMTP_DEBUG=1 ... probe --vid 2717 --pid ff40`)

## Modes x Operations

| Parameter | Value | Unit |
|-----------|-------|------|
| Maximum Chunk Size | 2.1 MB | bytes |
| Handshake Timeout | 6000 | ms |
| I/O Timeout | 15000 | ms |
| Inactivity Timeout | 8000 | ms |
| Overall Deadline | 120000 | ms || Stabilization Delay | 400 | ms |

| Mode | Evidence | Open + DeviceInfo | Storage IDs | Root List | Read Smoke | Write Smoke | Delete Smoke | Result |
|---|---|---|---|---|---|---|---|---|
| MTP (storage gated) | `20260216-015505` | Pass | `0` storages | Fail | Skipped | Skipped | Skipped | `storage_gated` |
| MTP (storage exposed) | `20260212-053429` | Pass | `1` storage | Pass (`416` root objects) | Not run | Fail (`InvalidParameter 0x201D` on write to `Download`) | Skipped | `partial` |
| PTP | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Charge-only | Not yet captured | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Write Path Notes

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

- Historical failure class was `SendObject` rejection with `0x201D` when targeting `Download`.
- Write fallback ladder is now implemented in core and in `device-lab` write smoke:
  - strategy fallback (`partial` to conservative variants)
  - folder fallback (`Download`/`Downloads` then media folders, then `SwiftMTP` folder)
- Latest run did not reach write validation because storage was gated.

## Next Validation Steps

1. Unlock/authorize file access and replug until `storageCount>0` is observed.
2. Re-run `device-lab connected --json` and verify write succeeds with fallback metadata captured.
3. Confirm cleanup path (`delete-uploaded-object`) in same run.
