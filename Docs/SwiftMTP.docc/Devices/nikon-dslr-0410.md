# Nikon DSLR / Z-Series (04B0:0410)

Nikon D-series DSLR and Z-series mirrorless cameras in MTP/PTP mode.

## Device Information

| Field | Value |
|-------|-------|
| Manufacturer | Nikon Corporation |
| USB VID | `0x04B0` |
| USB PID | `0x0410` (D3200-class / Z-class representative) |
| Interface Class | Still Image (0x06 / 0x01 / 0x01) |
| MTP Status | Experimental |
| Quirk ID | `nikon-dslr-0410` |

## Supported Operations

| Operation | Supported |
|-----------|-----------|
| GetStorageIDs | Yes |
| GetObjectHandles | Yes |
| GetObjectInfo | Yes |
| GetObject (download) | Yes |
| SendObject (upload) | Yes (limited to SD-card paths) |
| DeleteObject | Yes |
| GetPartialObject64 | No |
| SendPartialObject | No |
| GetObjectPropValue | Yes (object size via 0xDC04) |
| GetDevicePropValue | Yes (battery, mode dial) |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Enabling MTP/PTP Mode

1. **Settings → USB Options → MTP/PTP** (menu location varies by body).
2. On Z-series mirrorless: **Menu → Connect & share → USB → MTP/PTP (Sel. photos)**.
3. Power the camera **on** before connecting — Nikon enumeration is sensitive to power sequence.
4. macOS assigns the interface; `swift run swiftmtp probe` shows `04B0:0410`.

## Vendor Extension Notes

Nikon exposes vendor-specific operations in the `0x9xxx` range:
- `0x9201` — `Nikon_GetPreviewImg`: thumbnail preview without full download
- `0x9501` — `Nikon_StartLiveView`: activate liveview (requires session lock)

These are not currently wrapped by SwiftMTP. Use `device.executeRawCommand` for access.

## Object Size for NEF Files

NEF raw files report size via `GetObjectPropValue` property `0xDC04` (Object Size UInt64).
SwiftMTP automatically falls back to `GetObjectInfo.sizeBytes` when the U64 property is unavailable.

## Troubleshooting

### Camera not enumerated (probe returns empty)

1. Confirm **MTP/PTP** mode in camera menus.
2. Some Nikon bodies default to **PictBridge** mode — select **MTP/PTP** explicitly.
3. Turn the camera **on** before connecting USB.
4. Remove any third-party USB-C adapters; use the original cable.

### Storage appears empty (`GetStorageIDs` returns nothing)

1. SD card must be inserted and recognized (check card status on LCD).
2. If card is locked (write-protect slider), some operations are restricted.
3. Nikon bodies in **live tethering** mode may hide SD card storage — exit live view first.

### Large NEF download timeout

NEF files on newer Z-series are 25–45 MB. Extend timeouts:
```
export SWIFTMTP_IO_TIMEOUT_MS=45000
export SWIFTMTP_OVERALL_DEADLINE_MS=300000
```

## Provenance

- **Status**: Experimental (profile contributed by community)
- **Tested body**: Nikon D3200 (04B0:0410)
- **Date**: 2025-02-25
