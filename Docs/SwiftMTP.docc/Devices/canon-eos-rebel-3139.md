# Canon EOS (04A9:3139)

Canon EOS Rebel / EOS R class cameras in PTP/MTP mode.

## Device Information

| Field | Value |
|-------|-------|
| Manufacturer | Canon Inc. |
| USB VID | `0x04A9` |
| USB PID | `0x3139` (EOS Rebel / EOS R-class) |
| Interface Class | Still Image (0x06 / 0x01 / 0x01) |
| MTP Status | Experimental |
| Quirk ID | `canon-eos-rebel-3139` |

## Supported Operations

| Operation | Supported |
|-----------|-----------|
| GetStorageIDs | Yes |
| GetObjectHandles | Yes |
| GetObjectInfo | Yes |
| GetObject (download) | Yes |
| SendObject (upload) | Camera filesystem only |
| DeleteObject | Yes |
| GetPartialObject64 | No |
| SendPartialObject | No |
| GetObjectPropValue | Yes (subset) |
| GetDevicePropValue | Yes (battery, date, mode) |
| Prefer Object Property List | No |
| Write Resume Disabled | Yes |

## Enabling PTP/MTP Mode

1. On the camera body: **Menu → Wrench/Setup → USB Connection → PTP** (or `PC Connection`).
2. On some EOS R-series bodies the menu path is: **Menu → Setup 4 → USB Connection → PTP**.
3. Connect the camera via USB-C or Mini-USB (depending on body).
4. Power the camera on **after** connecting the cable.
5. macOS should enumerate it as `Canon EOS XXX`; `swift run swiftmtp probe` will show the VID:PID.

## Capture Events

Canon EOS cameras emit `ObjectAdded` (0x4001) events when photos are taken in tethered mode.
SwiftMTP event pump polls at 50 ms intervals for this device. To listen:

```swift
for await event in device.events {
    switch event {
    case .objectAdded(let handle):
        let info = try await device.getInfo(handle: handle)
        print("New capture: \(info.name)")
    default:
        break
    }
}
```

## Performance Notes

- RAW (CR2/CR3) files are typically 20–35 MB. With `maxChunkBytes = 1 MB`, expect ~10–20 s for large files.
- Extend `SWIFTMTP_IO_TIMEOUT_MS=60000` for continuous burst downloads.
- JPEG + RAW pairs are common; filter by `formatCode` to separate.

## Troubleshooting

### Camera not recognized after connection

**Symptom:** `swift run swiftmtp probe` returns no devices.

1. Verify the camera is in **PTP** (not MSC or Printer) mode.
2. Some EOS bodies show a USB connection dialog — select **PTP/MTP**, not **Mass Storage**.
3. Use a direct USB port; USB hubs can cause enumeration failures.
4. Verify kernel detach succeeded: `ioreg -p IOUSB -w0 -l | grep -A 5 Canon`

### SendObject (upload) failures

Canon EOS cameras accept uploads only to the card filesystem root or `DCIM/` folder.
The quirk profile disables write resume (`disableWriteResume: true`); uploads are atomic.

### Write large files

Use `SWIFTMTP_OVERALL_DEADLINE_MS=300000` for 20+ MB uploads.

## Provenance

- **Status**: Experimental (profile contributed by community)
- **Tested body**: EOS Rebel SL3 (0x04A9:0x3139)
- **Date**: 2025-02-25
